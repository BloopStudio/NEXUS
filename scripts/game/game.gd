## Game — main scene controller
## Draws a dark grid background, hosts station + wave manager + players.
extends Node2D

const C_BG        := Color(0.039, 0.039, 0.059)
const C_GRID      := Color(0.08, 0.09, 0.14, 0.6)
const GRID_STEP   := 60

var _station: Node2D       = null
var _wave_manager: Node2D  = null
var _players: Dictionary   = {}   # peer_id -> Player node

var _notice_label: Label   = null
var _notice_timer: float   = 0.0

var _camera: Camera2D      = null
var _shake_time: float     = 0.0
var _shake_strength: float = 0.0
var _last_station_hp: float = -1.0


func _ready() -> void:
	# Camera centered on origin
	_camera = Camera2D.new()
	_camera.position = Vector2.ZERO
	add_child(_camera)

	# HUD (CanvasLayer — always on top)
	var hud_script = load("res://scripts/ui/hud.gd")
	var hud: Node = hud_script.new()
	hud.name = "HUD"
	add_child(hud)

	# Upgrade menu (CanvasLayer — shown during UPGRADE phase)
	var upgrade_script = load("res://scripts/ui/upgrade_menu.gd")
	var upgrade_menu: Node = upgrade_script.new()
	upgrade_menu.name = "UpgradeMenu"
	add_child(upgrade_menu)

	# Station at center
	var station_script = load("res://scripts/game/station.gd")
	_station = station_script.new()
	_station.name = "Station"
	_station.position = Vector2.ZERO
	add_child(_station)
	_station.slot_clicked.connect(upgrade_menu.on_slot_clicked)

	# Idle generator (child node, host-only logic inside)
	var idle_script = load("res://scripts/game/idle_generator.gd")
	var idle_gen: Node = idle_script.new()
	idle_gen.name = "IdleGenerator"
	add_child(idle_gen)

	# Wave manager
	var wm_script = load("res://scripts/game/wave_manager.gd")
	_wave_manager = wm_script.new()
	_wave_manager.name = "WaveManager"
	_wave_manager.station_node = _station
	add_child(_wave_manager)
	_wave_manager.wave_cleared.connect(_on_wave_cleared)

	# Players
	_spawn_players()

	# Notice label (canvas-space, centered via CanvasLayer)
	var cl := CanvasLayer.new()
	add_child(cl)
	_notice_label = Label.new()
	_notice_label.anchor_left   = 0.5
	_notice_label.anchor_right  = 0.5
	_notice_label.anchor_top    = 0.35
	_notice_label.anchor_bottom = 0.35
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", 32)
	_notice_label.add_theme_color_override("font_color", Color(0.0, 0.831, 1.0))
	_notice_label.modulate.a = 0.0
	cl.add_child(_notice_label)

	# Connect game_over signal
	GameState.game_over.connect(_on_game_over)

	_last_station_hp = GameState.station_hp
	GameState.station_health_changed.connect(_on_station_hp_changed)

	# If the host leaves (or a client's connection drops), don't leave
	# everyone else stranded in a dead game scene.
	NetworkManager.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice_label.modulate.a = 0.0
		else:
			# Fade out in last 0.5 s
			_notice_label.modulate.a = clampf(_notice_timer / 0.5, 0.0, 1.0)

	_update_camera_shake(delta)


func _on_station_hp_changed(new_hp: float) -> void:
	if new_hp < _last_station_hp:
		_start_camera_shake(6.0, 0.25)
	_last_station_hp = new_hp


func _start_camera_shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = duration


func _update_camera_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		_camera.offset = Vector2.ZERO
		return
	_shake_time -= delta
	var falloff := clampf(_shake_time, 0.0, 1.0)
	_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * falloff


func _draw() -> void:
	# Solid background
	var vp := get_viewport_rect()
	var half := vp.size * 0.5
	draw_rect(Rect2(-half * 2, vp.size * 4), C_BG)

	# Tech grid — draw a large region around origin
	var extent := 1200
	var x := -extent
	while x <= extent:
		draw_line(Vector2(x, -extent), Vector2(x, extent), C_GRID, 1.0)
		x += GRID_STEP
	var y := -extent
	while y <= extent:
		draw_line(Vector2(-extent, y), Vector2(extent, y), C_GRID, 1.0)
		y += GRID_STEP


# ─── Player spawning ────────────────────────────────────────────────────────────

func _spawn_players() -> void:
	for peer_id in NetworkManager.players:
		_add_player(peer_id)


func _add_player(peer_id: int) -> void:
	if _players.has(peer_id):
		return
	var player_script = load("res://scripts/game/player.gd")
	var player: Node2D = player_script.new()
	# Deterministic, peer_id-based name: dynamically-added nodes get an
	# auto-incrementing name by default, and that counter can drift between
	# peers (e.g. if the player list arrives in a different order), which
	# silently breaks RPC routing for anything not on an autoload — this is
	# what made bullets/enemies invisible to non-host players.
	player.name = "Player_%d" % peer_id
	player.peer_id = peer_id
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	player.player_name  = info.get("name",  "Player")
	player.player_color = info.get("color", Color.CYAN)
	# Spread players in a small arc at start
	var angle := (float(_players.size()) / maxf(1.0, float(NetworkManager.players.size()))) * TAU
	player.position = Vector2(cos(angle), sin(angle)) * 80.0
	add_child(player)
	_players[peer_id] = player


# ─── Nearest enemy helper (used by Station turrets) ────────────────────────────

func get_nearest_enemy(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for child in get_children():
		if child.has_method("take_damage") and not child.is_queued_for_deletion():
			# Exclude Station and Player nodes by checking for "died" signal
			if child.has_signal("died"):
				var d := pos.distance_to(child.global_position)
				if d < best_dist:
					best_dist = d
					best = child
	return best


# ─── Signal handlers ────────────────────────────────────────────────────────────

func _on_wave_cleared() -> void:
	_show_notice("VAGUE TERMINÉE", 2.5)


func _on_server_disconnected() -> void:
	_show_notice("HÔTE DÉCONNECTÉ", 1.5)
	await get_tree().create_timer(1.0).timeout
	SceneLoader.change_scene("res://scenes/main_menu.tscn")


func _on_game_over() -> void:
	AudioManager.play_sfx(AudioManager.SFX.GAME_OVER)
	await get_tree().create_timer(2.0).timeout
	NetworkManager.disconnect_from_game()
	SceneLoader.change_scene("res://scenes/main_menu.tscn")


# ─── Helpers ───────────────────────────────────────────────────────────────────

func _show_notice(text: String, duration: float) -> void:
	_notice_label.text = text
	_notice_label.modulate.a = 1.0
	_notice_timer = duration
