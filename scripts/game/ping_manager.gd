## PingManager — team-visible map markers ("focus ici" / "besoin d'aide"),
## the silent alternative to voice chat. Any peer can drop one; placement is
## purely cosmetic (no gameplay effect) so it doesn't need host authority to
## take effect locally, but a client can only reach the host directly over
## ENet — the host relays it back out to everyone else, same pattern as the
## turret flash / mine pulse visuals.
extends Node2D

const PING_DURATION := 4.0
const TYPES := {
	"focus": {"color": Color(1.0, 0.85, 0.2), "label": "FOCUS"},
	"help":  {"color": Color(1.0, 0.25, 0.25), "label": "BESOIN D'AIDE"},
}

# Active pings: {"pos": Vector2, "type": String, "t": float, "sender_name": String}
var _pings: Array = []


func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ping_focus"):
		_request_ping("focus")
	elif event.is_action_pressed("ping_help"):
		_request_ping("help")


func _request_ping(type: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var pos := get_global_mouse_position()
	if NetworkManager.is_host():
		var info: Dictionary = NetworkManager.players.get(1, {})
		_place_ping_rpc.rpc(pos, type, info.get("name", "Hôte"))
	else:
		_request_place_ping_rpc.rpc_id(1, pos, type)


## Client → host relay: the host stamps the sender's own name (never trusts
## a client-supplied one) before broadcasting.
@rpc("any_peer", "reliable")
func _request_place_ping_rpc(pos: Vector2, type: String) -> void:
	if not NetworkManager.is_host():
		return
	if not TYPES.has(type):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var info: Dictionary = NetworkManager.players.get(sender_id, {})
	_place_ping_rpc.rpc(pos, type, info.get("name", "Joueur"))


@rpc("authority", "call_local", "reliable")
func _place_ping_rpc(pos: Vector2, type: String, sender_name: String) -> void:
	if not TYPES.has(type):
		return
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK, 2.0)
	_pings.append({"pos": pos, "type": type, "t": PING_DURATION, "sender_name": sender_name})
	queue_redraw()


func _process(delta: float) -> void:
	if _pings.is_empty():
		return
	var i := _pings.size() - 1
	while i >= 0:
		_pings[i]["t"] -= delta
		if _pings[i]["t"] <= 0.0:
			_pings.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for p in _pings:
		var def: Dictionary = TYPES[p["type"]]
		var col: Color = def["color"]
		var alpha := clampf(p["t"] / PING_DURATION, 0.0, 1.0)
		var progress := 1.0 - alpha
		var pos: Vector2 = to_local(p["pos"])

		var ring_radius := 16.0 + progress * 26.0
		draw_arc(pos, ring_radius, 0, TAU, 28, Color(col.r, col.g, col.b, alpha), 3.0)
		draw_circle(pos, 5.0, Color(col.r, col.g, col.b, alpha))
		draw_line(pos, pos + Vector2(0, -34), Color(col.r, col.g, col.b, alpha * 0.8), 2.0)

		var text := "%s — %s" % [def["label"], p["sender_name"]]
		var font_size := 13
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_pos := pos + Vector2(-text_size.x / 2.0, -44.0)
		draw_rect(Rect2(text_pos + Vector2(-6, -text_size.y + 3), text_size + Vector2(12, 8)),
			Color(0.02, 0.02, 0.04, 0.75 * alpha))
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col.r, col.g, col.b, alpha))
