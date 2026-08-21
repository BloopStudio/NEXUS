## NetworkManager — Autoload singleton
## Handles all P2P networking via ENet (no dedicated server needed).
## Party code = Base64 of "ip:port" — host shares it, guests decode and connect.
## The host's port is opened automatically via UPnP when possible, so most
## players never need to touch their router settings.
extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const UPNP_DISCOVER_TIMEOUT_MS := 3000

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
## Emitted on every peer (host included) when the host starts the match —
## this is what actually moves everyone from the main menu into the game
## scene together, instead of only the host who clicked "Démarrer".
signal game_starting()

# Local player info sent to peers on join
var local_player_info := {"name": "Player", "color": Color.CYAN}
# All players: peer_id -> info dict
var players := {}

var _upnp: UPNP
var _upnp_port: int = -1
var _upnp_mapped_public_ip: String = ""


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
	return OK


## Attempts to open the port automatically on the host's router via UPnP/IGD.
## Runs in the background; connect to `upnp_status` to know the outcome.
## Zero external server involved — this only talks to the local router.
func _try_setup_upnp(port: int) -> void:
	_upnp = UPNP.new()
	var discover_result := _upnp.discover(UPNP_DISCOVER_TIMEOUT_MS)
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		push_warning("NetworkManager: UPnP discovery failed (%d) — router may not support UPnP or it's disabled." % discover_result)
		upnp_status.emit(false)
		return

	if _upnp.get_gateway() == null or not _upnp.get_gateway().is_valid_gateway():
		push_warning("NetworkManager: no valid UPnP gateway found on the network.")
		upnp_status.emit(false)
		return

	# Clean up any stale mapping from a previous session first.
	_upnp.delete_port_mapping(port, "UDP")

	var map_result := _upnp.add_port_mapping(port, port, "NEXUS", "UDP", 0)
	if map_result != UPNP.UPNP_RESULT_SUCCESS:
		push_warning("NetworkManager: UPnP port mapping failed (%d)." % map_result)
		upnp_status.emit(false)
		return

	_upnp_port = port
	_upnp_mapped_public_ip = _upnp.query_external_address()
	upnp_status.emit(true)


## Returns the public IP UPnP reported for the current port mapping, or an
## empty string if UPnP mapping wasn't successful.
func get_upnp_public_ip() -> String:
	return _upnp_mapped_public_ip


## Returns the party code (Base64 of "ip:port") the host shares with friends.
## Uses the UPnP-mapped public IP when available (works over the internet
## with zero router configuration); falls back to the LAN IP otherwise,
## which only works for players on the same local network.
func get_party_code(port: int = DEFAULT_PORT) -> String:
	var ip := _upnp_mapped_public_ip if not _upnp_mapped_public_ip.is_empty() else _get_local_ip()
	var raw := "%s:%d" % [ip, port]
	return Marshalls.utf8_to_base64(raw)


## Decode a party code → {ip, port} dict. Returns empty dict on failure.
func decode_party_code(code: String) -> Dictionary:
	var raw := Marshalls.base64_to_utf8(code.strip_edges())
	if raw.is_empty() or not ":" in raw:
		return {}
	var parts := raw.rsplit(":", false, 1)
	if parts.size() != 2 or not parts[1].is_valid_int():
		return {}
	return {"ip": parts[0], "port": parts[1].to_int()}


# ─── Joining ───────────────────────────────────────────────────────────────────

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("NetworkManager: failed to connect to %s:%d" % [ip, port])
		connection_failed.emit()
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func join_with_code(code: String) -> Error:
	var info := decode_party_code(code)
	if info.is_empty():
		push_error("NetworkManager: invalid party code")
		connection_failed.emit()
		return ERR_INVALID_PARAMETER
	return join_game(info["ip"], info["port"])


# ─── Disconnect ────────────────────────────────────────────────────────────────

func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	_disconnect_signals()
	_teardown_upnp()


func _teardown_upnp() -> void:
	if _upnp != null and _upnp_port != -1:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = -1
	_upnp_mapped_public_ip = ""


# ─── RPCs ──────────────────────────────────────────────────────────────────────

## Client → Host: register this player's info
@rpc("any_peer", "reliable")
func register_player(info: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = info
	player_connected.emit(sender)
	# Notify the new peer about all existing players
	_send_player_list.rpc_id(sender, players)


## Host → new client: here's the full player list
@rpc("authority", "reliable")
func _send_player_list(list: Dictionary) -> void:
	players = list


## Broadcast: a player disconnected, remove from list
@rpc("any_peer", "call_local", "reliable")
func _remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)


## Host only: tell every connected peer (host included, via call_local) to
## start the match together. Call this instead of changing the scene
## directly — otherwise clients are left stuck on "En attente du démarrage".
func start_game() -> void:
	if not is_host():
		return
	_start_game_rpc.rpc()


@rpc("authority", "call_local", "reliable")
func _start_game_rpc() -> void:
	game_starting.emit()


# ─── Signal handlers ───────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	# Host: wait for the peer to register themselves
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_player.rpc(peer_id)


func _on_connected_to_server() -> void:
	# Send our info to the host
	register_player.rpc_id(1, local_player_info)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


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


func is_host() -> bool:
	return multiplayer.is_server()


func get_player_count() -> int:
	return players.size()
