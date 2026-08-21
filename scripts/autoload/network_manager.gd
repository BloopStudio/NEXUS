## NetworkManager — Autoload singleton
## Handles all P2P networking via ENet (no dedicated server needed).
## Party code = Base64 of "ip:port" — host shares it, guests decode and connect.
extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connection_succeeded()
signal server_disconnected()

# Local player info sent to peers on join
var local_player_info := {"name": "Player", "color": Color.CYAN}
# All players: peer_id -> info dict
var players := {}


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
	return OK


## Returns the party code (Base64 of "ip:port") the host shares with friends.
## Shows both LAN IP and asks user to replace with public IP for internet play.
func get_party_code(port: int = DEFAULT_PORT) -> String:
	var local_ip := _get_local_ip()
	var raw := "%s:%d" % [local_ip, port]
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
