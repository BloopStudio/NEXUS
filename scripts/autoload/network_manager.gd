## NetworkManager — Autoload singleton
## Handles all P2P networking via ENet (no dedicated server needed).
## Party code = Base64 of "ip:port" — host shares it, guests decode and connect.
## The host's port is opened automatically via UPnP when possible, so most
## players never need to touch their router settings.
extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const UPNP_DISCOVER_TIMEOUT_MS := 3000
## ENet only calls connection_failed on an active refusal (e.g. wrong port).
## When packets are just silently dropped — the far end unreachable, a closed
## firewall, or (very common) the host's router doing CGNAT so its "public"
## IP isn't actually reachable from the internet — neither connected_to_server
## nor connection_failed ever fires, and the UI was stuck on "Connexion en
## cours…" forever. This bounds that wait so joining always resolves. Kept
## short since the party code can carry several candidate addresses to try
## in sequence (see the STUN section below) — a slow per-candidate timeout
## would make the worst case (host truly unreachable) painfully long.
const CANDIDATE_TIMEOUT_SECONDS := 5.0

# ─── STUN (NAT address discovery) ───────────────────────────────────────────────
# STUN (RFC 5389) is the standard, widely-used technique (it's the "S" in
# WebRTC's ICE) for a peer to learn its own address as seen from the public
# internet — a small public server just echoes back "here's where this
# packet came from," no relay of game traffic, no cost, no account needed.
# Unlike UPnP, it doesn't configure anything on the router (so it works even
# when UPnP is disabled/unsupported, exactly the case that was leaving some
# hosts unreachable) — it only *discovers* the address; whether that address
# is actually reachable still depends on the router's NAT behavior. Many
# consumer routers preserve the same port for outbound UDP ("port-preserving"
# NAT) even without UPnP, so trying <stun-discovered-ip>:<game-port> as a
# fallback candidate meaningfully improves the odds without needing any
## signaling exchange beyond the party code we already share.
const STUN_SERVERS := [
	{"host": "stun.l.google.com", "port": 19302},
	{"host": "stun1.l.google.com", "port": 19302},
]
const STUN_MAGIC_COOKIE := 0x2112A442
const STUN_TIMEOUT_MS := 1500

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connection_succeeded()
signal server_disconnected()
## Emitted after host_game() once UPnP port mapping has been attempted.
## success = true if the port was opened automatically (internet play should
## just work from a code); false means UPnP wasn't available and the party
## code will likely only work for players on the same local network, or the
## host will need to forward the port manually.
signal upnp_status(success: bool)
## Emitted once the STUN discovery attempt (see get_party_code) finishes —
## success = true if a public IP was discovered. Runs in parallel with UPnP
## on its own thread, so this can fire before or after upnp_status.
signal stun_status(success: bool)
## Emitted right before each connection attempt while trying the candidate
## addresses from a party code, so the UI can show progress instead of a
## single unmoving "Connexion en cours…" for up to several attempts.
signal joining_candidate(index: int, total: int, ip: String)
## Emitted on every peer (host included) when the host starts the match —
## this is what actually moves everyone from the main menu into the game
## scene together, instead of only the host who clicked "Démarrer".
signal game_starting(mutator: int)
## Emitted whenever the local copy of `players` changes for a reason other
## than a peer joining/leaving (e.g. a fresh ping reading) — connect this if
## you display more than just the join/leave events (see HUD player list).
signal players_updated()

# Local player info sent to peers on join
var local_player_info := {"name": "Player", "color": Color.CYAN}
# All players: peer_id -> info dict (peer id 1 is always the host)
var players := {}

const HOST_PEER_ID := 1
const PING_INTERVAL := 1.5
var _ping_timer: float = 0.0

var _upnp: UPNP
var _upnp_port: int = -1
var _upnp_mapped_public_ip: String = ""
var _stun_thread: Thread = null
var _stun_public_ip: String = ""

## True while a connection attempt hasn't yet resolved to success or
## failure — guards the timeout callback against firing after the fact (e.g.
## once already connected, or after a newer attempt superseded it).
var _joining: bool = false
## Bumped on every _connect_candidate() call; a timeout callback compares
## against this to ignore a stale timer left over from an abandoned attempt.
var _join_timeout_token: int = 0

# Party-code join: candidate addresses tried in sequence, one at a time.
var _join_candidates: Array = []
var _join_candidate_index: int = -1
var _join_port: int = DEFAULT_PORT


func _process(delta: float) -> void:
	# Host-only: periodically ping every connected client so everyone's
	# player list can show a rough latency-to-host figure.
	if multiplayer.multiplayer_peer == null or not is_host():
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_INTERVAL
		for peer_id in players.keys():
			if peer_id != HOST_PEER_ID:
				_ping_rpc.rpc_id(peer_id, Time.get_ticks_msec())
var _upnp_thread: Thread = null


# ─── Hosting ───────────────────────────────────────────────────────────────────

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: failed to create server on port %d — %s" % [port, err])
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Register host as player 1
	players[1] = local_player_info.duplicate()

	_try_setup_upnp(port)
	_try_stun_discovery()
	return OK


## Attempts to open the port automatically on the host's router via UPnP/IGD.
## UPnP discovery can take up to ~3s (or longer on some routers), so this
## runs on a background Thread — doing it on the main thread used to freeze
## the whole game (rendering, input, networking) every time someone hosted.
## Connect to `upnp_status` to know the outcome.
func _try_setup_upnp(port: int) -> void:
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))


func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var success := false
	var mapped_ip := ""

	var discover_result := upnp.discover(UPNP_DISCOVER_TIMEOUT_MS)
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		push_warning("NetworkManager: UPnP discovery failed (%d) — router may not support UPnP or it's disabled." % discover_result)
	elif upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		push_warning("NetworkManager: no valid UPnP gateway found on the network.")
	else:
		upnp.delete_port_mapping(port, "UDP")  # clean up any stale mapping from a previous session
		var map_result := upnp.add_port_mapping(port, port, "NEXUS", "UDP", 0)
		if map_result != UPNP.UPNP_RESULT_SUCCESS:
			push_warning("NetworkManager: UPnP port mapping failed (%d)." % map_result)
		else:
			success = true
			mapped_ip = upnp.query_external_address()

	call_deferred("_on_upnp_worker_done", upnp, port, success, mapped_ip)


func _on_upnp_worker_done(upnp: UPNP, port: int, success: bool, mapped_ip: String) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null

	if success:
		_upnp = upnp
		_upnp_port = port
		_upnp_mapped_public_ip = mapped_ip
	upnp_status.emit(success)


## Returns the public IP UPnP reported for the current port mapping, or an
## empty string if UPnP mapping wasn't successful.
func get_upnp_public_ip() -> String:
	return _upnp_mapped_public_ip


## Kicks off the STUN discovery on a background Thread (the round trip to a
## public server, bounded by STUN_TIMEOUT_MS, would otherwise briefly freeze
## the game the same way blocking UPnP discovery used to — see host_game()).
func _try_stun_discovery() -> void:
	_stun_thread = Thread.new()
	_stun_thread.start(_stun_worker)


func _stun_worker() -> void:
	var ip := _stun_discover_public_ip()
	call_deferred("_on_stun_worker_done", ip)


func _on_stun_worker_done(ip: String) -> void:
	if _stun_thread:
		_stun_thread.wait_to_finish()
		_stun_thread = null
	_stun_public_ip = ip
	stun_status.emit(not ip.is_empty())


## Tries each configured STUN server in turn, returning the first publicly
## observed IP found, or "" if none responded in time.
func _stun_discover_public_ip() -> String:
	for server in STUN_SERVERS:
		var ip := _stun_query_server(server["host"], server["port"])
		if not ip.is_empty():
			return ip
	return ""


## Sends one RFC 5389 Binding Request and waits (blocking — this always runs
## off the main thread, see _try_stun_discovery) up to STUN_TIMEOUT_MS for a
## Binding Success Response, parsing out the XOR-MAPPED-ADDRESS attribute.
func _stun_query_server(host: String, port: int) -> String:
	var udp := PacketPeerUDP.new()
	if udp.connect_to_host(host, port) != OK:
		return ""

	var txn := PackedByteArray()
	for i in 12:
		txn.append(randi() % 256)

	var packet := PackedByteArray()
	packet.append_array(_stun_be16(0x0001))  # Binding Request
	packet.append_array(_stun_be16(0))       # message length: no attributes
	packet.append_array(_stun_be32(STUN_MAGIC_COOKIE))
	packet.append_array(txn)
	udp.put_packet(packet)

	var waited_ms := 0
	while waited_ms < STUN_TIMEOUT_MS:
		if udp.get_available_packet_count() > 0:
			var ip := _stun_parse_response(udp.get_packet())
			udp.close()
			return ip
		OS.delay_msec(50)
		waited_ms += 50

	udp.close()
	return ""


## STUN packs multi-byte integers big-endian ("network byte order"); Godot's
## PackedByteArray encode_u16/u32 are little-endian, so this can't just use
## those directly.
func _stun_be16(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 8) & 0xFF, v & 0xFF])


func _stun_be32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


func _stun_read_be16(b: PackedByteArray, offset: int) -> int:
	return (b[offset] << 8) | b[offset + 1]


## Extracts the IPv4 address from a Binding Success Response's
## XOR-MAPPED-ADDRESS attribute (falls back to the older, non-XOR
## MAPPED-ADDRESS if that's all the server sent). Returns "" if the response
## isn't a valid/parseable success response.
func _stun_parse_response(resp: PackedByteArray) -> String:
	if resp.size() < 20:
		return ""
	if _stun_read_be16(resp, 0) != 0x0101:  # Binding Success Response
		return ""
	var msg_len := _stun_read_be16(resp, 2)
	if resp.size() < 20 + msg_len:
		return ""

	var offset := 20
	var end := 20 + msg_len
	var fallback_ip := ""
	while offset + 4 <= end:
		var attr_type := _stun_read_be16(resp, offset)
		var attr_len := _stun_read_be16(resp, offset + 2)
		var value_start := offset + 4
		if value_start + attr_len > resp.size():
			break

		if attr_type == 0x0020 and attr_len >= 8 and resp[value_start + 1] == 0x01:  # XOR-MAPPED-ADDRESS, IPv4
			var octets := PackedByteArray()
			for i in 4:
				var cookie_byte := (STUN_MAGIC_COOKIE >> (24 - i * 8)) & 0xFF
				octets.append(resp[value_start + 4 + i] ^ cookie_byte)
			return "%d.%d.%d.%d" % [octets[0], octets[1], octets[2], octets[3]]
		elif attr_type == 0x0001 and attr_len >= 8 and resp[value_start + 1] == 0x01:  # MAPPED-ADDRESS, IPv4
			fallback_ip = "%d.%d.%d.%d" % [resp[value_start + 4], resp[value_start + 5], resp[value_start + 6], resp[value_start + 7]]

		var padded_len := attr_len + ((4 - attr_len % 4) % 4)
		offset = value_start + padded_len

	return fallback_ip


## Returns the party code the host shares with friends: Base64 of a small
## JSON object carrying every candidate address worth trying, in the order
## most likely to actually work — UPnP-mapped public IP (opened on the
## router, should just work), then the STUN-discovered public IP (not
## router-configured, but many NATs preserve the port anyway), then the LAN
## IP (only reachable from the same local network). The joiner tries them
## one at a time (see join_with_code) until one connects.
func get_party_code(port: int = DEFAULT_PORT) -> String:
	var ips: Array = []
	if not _upnp_mapped_public_ip.is_empty():
		ips.append(_upnp_mapped_public_ip)
	if not _stun_public_ip.is_empty() and _stun_public_ip != _upnp_mapped_public_ip:
		ips.append(_stun_public_ip)
	ips.append(_get_local_ip())
	return Marshalls.utf8_to_base64(JSON.stringify({"port": port, "ips": ips}))


## Decode a party code → {ips: Array[String], port: int} dict. Returns an
## empty dict on failure (e.g. garbled input, or an old-format single "ip:port"
## code from a previous NEXUS version — codes aren't meant to be kept around).
func decode_party_code(code: String) -> Dictionary:
	var raw := Marshalls.base64_to_utf8(code.strip_edges())
	if raw.is_empty():
		return {}
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("ips") or not parsed.has("port"):
		return {}
	if typeof(parsed["ips"]) != TYPE_ARRAY or parsed["ips"].is_empty():
		return {}
	return {"ips": parsed["ips"], "port": int(parsed["port"])}


# ─── Joining ───────────────────────────────────────────────────────────────────

## Direct single-address connect — the low-level primitive both join_with_code
## (below, trying several candidates in sequence) and manual/LAN-IP joins use.
func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	_join_candidates = [ip]
	_join_candidate_index = 0
	_join_port = port
	joining_candidate.emit(0, 1, ip)
	return _connect_candidate(ip, port)


## Tries every candidate address from a party code (see get_party_code) one
## at a time, in order, falling through to the next on failure or timeout —
## connection_failed only fires once ALL of them have been exhausted.
func join_with_code(code: String) -> Error:
	var info := decode_party_code(code)
	if info.is_empty():
		push_error("NetworkManager: invalid party code")
		connection_failed.emit()
		return ERR_INVALID_PARAMETER

	_join_candidates = info["ips"]
	_join_port = info["port"]
	_join_candidate_index = 0
	var first_ip: String = _join_candidates[0]
	joining_candidate.emit(0, _join_candidates.size(), first_ip)
	var err := _connect_candidate(first_ip, _join_port)
	if err != OK:
		_advance_to_next_candidate()
	return OK


func _connect_candidate(ip: String, port: int) -> Error:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	_disconnect_signals()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_warning("NetworkManager: failed to start connecting to %s:%d — %s" % [ip, port, err])
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_joining = true
	_join_timeout_token += 1
	var token := _join_timeout_token
	get_tree().create_timer(CANDIDATE_TIMEOUT_SECONDS).timeout.connect(_on_join_timeout.bind(token))
	return OK


## Moves on to the next candidate address, or gives up (connection_failed)
## once they're all exhausted.
func _advance_to_next_candidate() -> void:
	_join_candidate_index += 1
	if _join_candidate_index >= _join_candidates.size():
		push_warning("NetworkManager: all %d candidate address(es) failed to connect." % _join_candidates.size())
		connection_failed.emit()
		return

	var ip: String = _join_candidates[_join_candidate_index]
	joining_candidate.emit(_join_candidate_index, _join_candidates.size(), ip)
	var err := _connect_candidate(ip, _join_port)
	if err != OK:
		_advance_to_next_candidate()


# ─── Disconnect ────────────────────────────────────────────────────────────────

func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	_disconnect_signals()
	_teardown_upnp()
	_teardown_stun()


func _teardown_upnp() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null and _upnp_port != -1:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = -1
	_upnp_mapped_public_ip = ""


func _teardown_stun() -> void:
	if _stun_thread != null:
		_stun_thread.wait_to_finish()
		_stun_thread = null
	_stun_public_ip = ""


# ─── RPCs ──────────────────────────────────────────────────────────────────────

## Client → Host: register this player's info
@rpc("any_peer", "reliable")
func register_player(info: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = _sanitize_player_info(info)
	player_connected.emit(sender)
	# Notify the new peer about all existing players
	_send_player_list.rpc_id(sender, players)


## A modified/malicious client could send a garbage class id, an unknown
## spell id, or a wrongly-typed name/color at registration — a legit client
## never can (the main menu's dropdowns only ever offer valid values), but
## nothing stops a hand-crafted RPC call from skipping that UI entirely.
## Left unchecked, that data gets stored and synced to every peer, and the
## first time anything indexes PlayerClasses.DEFS[class_id] or
## Spells.DEFS[spell_id] with it (damage calcs, spell casts, the HUD) it
## crashes that lookup on EVERY peer, not just the sender's. Clamp
## everything to known-safe values before it's ever stored.
func _sanitize_player_info(info: Dictionary) -> Dictionary:
	var player_name: String = str(info.get("name", "Player")).left(24)
	if player_name.is_empty():
		player_name = "Player"
	var color_val = info.get("color", Color.CYAN)
	var color: Color = color_val if color_val is Color else Color.CYAN
	var class_id = info.get("class", PlayerClasses.DEFAULT_CLASS)
	if not (class_id is int and PlayerClasses.DEFS.has(class_id)):
		class_id = PlayerClasses.DEFAULT_CLASS
	var spells_val = info.get("spells", [])
	var safe_spells: Array = []
	if spells_val is Array and spells_val.size() == 2 \
			and Spells.DEFS.has(spells_val[0]) and Spells.DEFS.has(spells_val[1]):
		safe_spells = spells_val
	return {"name": player_name, "color": color, "class": class_id, "spells": safe_spells}


## Host → client(s): here's the full player list. Sent to just the joining
## peer on connect, and re-broadcast to everyone whenever it changes (e.g. a
## fresh ping reading) so every player list stays in sync.
@rpc("authority", "reliable")
func _send_player_list(list: Dictionary) -> void:
	players = list
	players_updated.emit()


## Host → everyone: a player disconnected, remove from list. Only the host
## ever legitimately detects another peer's disconnect in this star
## topology (a client only sees its own connection to the host drop) —
## "authority" (not "any_peer") means a malicious client can't spoof this
## to get an arbitrary real player removed/kicked from everyone's game.
@rpc("authority", "call_local", "reliable")
func _remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)


# ─── Ping ────────────────────────────────────────────────────────────────────

## Host → client: "what's your round-trip time to me?" — the client just
## echoes the timestamp straight back.
@rpc("authority", "unreliable")
func _ping_rpc(sent_at_msec: int) -> void:
	_pong_rpc.rpc_id(HOST_PEER_ID, sent_at_msec)


## Client → host: pong reply: this let get_ticks_msec()-sent_at give the RTT.
@rpc("any_peer", "unreliable")
func _pong_rpc(sent_at_msec: int) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	players[sender]["ping_ms"] = Time.get_ticks_msec() - sent_at_msec
	# _send_player_list.rpc() (below) only reaches OTHER peers — it isn't
	# call_local, so without this the host's own `players` dict was updating
	# correctly (assigned directly above) but its HUD never found out, since
	# players_updated only fired for clients receiving the broadcast. The
	# host's player list looked frozen on whatever ping it saw first.
	players_updated.emit()
	_send_player_list.rpc(players)


## Host only: tell every connected peer (host included, via call_local) to
## start the match together. Call this instead of changing the scene
## directly — otherwise clients are left stuck on "En attente du démarrage".
## `mutator` (see mutators.gd) is the host's pick for the whole run — every
## peer needs the same value since it changes shared station math.
func start_game(mutator: int = 0) -> void:
	if not is_host():
		return
	_start_game_rpc.rpc(mutator)


@rpc("authority", "call_local", "reliable")
func _start_game_rpc(mutator: int) -> void:
	game_starting.emit(mutator)


# ─── Signal handlers ───────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	# Host: wait for the peer to register themselves
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_player.rpc(peer_id)


func _on_connected_to_server() -> void:
	_joining = false
	# Send our info to the host
	register_player.rpc_id(1, local_player_info)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	if not _joining:
		return
	_joining = false
	multiplayer.multiplayer_peer = null
	_advance_to_next_candidate()


## Fires CANDIDATE_TIMEOUT_SECONDS after _connect_candidate() if we're still
## waiting — ENet's own signals alone aren't enough here (see the const's
## comment: a dropped/black-holed connection never calls connection_failed).
## `token` guards against a stale timer left over from an attempt that's
## already succeeded, failed, or been superseded by a newer one.
func _on_join_timeout(token: int) -> void:
	if not _joining or token != _join_timeout_token:
		return
	_joining = false
	push_warning("NetworkManager: candidate address timed out after %ss." % CANDIDATE_TIMEOUT_SECONDS)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_advance_to_next_candidate()


func _on_server_disconnected() -> void:
	disconnect_from_game()
	server_disconnected.emit()


# ─── Helpers ───────────────────────────────────────────────────────────────────

func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		# Prefer IPv4, skip loopback
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"


func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)


## Make sure any still-running background thread is always joined before the
## engine tears this node down — otherwise closing the game while UPnP/STUN
## discovery is in flight crashes on shutdown.
func _exit_tree() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _stun_thread != null:
		_stun_thread.wait_to_finish()
		_stun_thread = null


## multiplayer.is_server() internally calls get_unique_id(), which errors
## every time it's asked with no multiplayer_peer assigned (e.g. before
## hosting/joining, or after a join attempt fails) — several callers across
## the codebase (some in a _process() that runs every frame) call is_host()
## without first checking that a peer exists, so the guard belongs here once
## rather than repeated at every call site.
func is_host() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.is_server()


func get_player_count() -> int:
	return players.size()
