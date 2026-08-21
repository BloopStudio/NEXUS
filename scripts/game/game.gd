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

	# A player leaving mid-match used to stay stuck on-screen forever —
	# nothing ever removed their Player node.
	NetworkManager.player_disconnected.connect(_on_player_disconnected)


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
	var spells: Array = info.get("spells", [])
	if spells.size() == 2:
		player.equipped_spells = spells
	# Spread players in a small arc at start
	var angle := (float(_players.size()) / maxf(1.0, float(NetworkManager.players.size()))) * TAU
	player.position = Vector2(cos(angle), sin(angle)) * 80.0
	add_child(player)
	_players[peer_id] = player


## Used by the HUD to read the local player's equipped spells/cooldowns.
func get_local_player() -> Node2D:
	if multiplayer.multiplayer_peer == null:
		return null
	return _players.get(multiplayer.get_unique_id(), null)


# ─── Nearest enemy helper (used by Station turrets) ────────────────────────────
# Enemies register themselves in the "enemies" group on spawn (see
# WaveManager._spawn_enemy_rpc). Looking them up this way is an engine-
# maintained flat list, versus rescanning every child of Game (which also
# includes players and every currently-flying bullet) and duck-typing each
# one with has_method()/has_signal() reflection calls — this used to run on
# every single turret shot, mine pulse, and player ability cast.

func get_nearest_enemy(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion():
			continue
		var d := pos.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


## Used by the MINE module and player ability for their area-of-effect pulse.
func get_enemies_in_radius(pos: Vector2, radius: float) -> Array:
	var result := []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion() and pos.distance_to(enemy.global_position) <= radius:
			result.append(enemy)
	return result


# ─── Signal handlers ────────────────────────────────────────────────────────────

func _on_player_disconnected(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
		_show_notice("JOUEUR DÉCONNECTÉ", 2.0)


func _on_wave_cleared() -> void:
	_show_notice("VAGUE TERMINÉE", 2.5)


func _on_server_disconnected() -> void:
	_show_notice("HÔTE DÉCONNECTÉ", 1.5)
	await get_tree().create_timer(1.0).timeout
	SceneLoader.change_scene("res://scenes/main_menu.tscn")


func _on_game_over() -> void:
	AudioManager.play_sfx(AudioManager.SFX.GAME_OVER)

	# Local scoreboard only makes sense from the host's own machine — it's
	# the only peer with an authoritative, trustworthy wave_number (clients
	# just mirror the host's synced copy).
	if NetworkManager.is_host():
		ProfileStore.record_score(GameState.wave_number)

	_show_game_over_stats()


## Replaces the old "wait 2s then silently kick back to menu" behavior —
## that was too fast to actually read anything. Shown on every peer; each
## one returns to the menu independently when THEY dismiss it.
func _show_game_over_stats() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 40
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	overlay.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	overlay.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(380, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "💀 Partie terminée"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	vbox.add_child(title)

	var survival := GameState.get_survival_seconds()
	var minutes := int(survival) / 60
	var seconds := int(survival) % 60

	for line in [
		"🌊 Vague atteinte : %d" % GameState.wave_number,
		"💥 Dégâts totaux infligés : %d" % int(GameState.total_damage_dealt),
		"⏱ Temps de survie : %02d:%02d" % [minutes, seconds],
	]:
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(lbl)

	if NetworkManager.is_host():
		var top: Array = ProfileStore.get_top_scores()
		if not top.is_empty() and top[0].get("wave", 0) == GameState.wave_number:
			var record_lbl := Label.new()
			record_lbl.text = "🏆 Nouveau record local !"
			record_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			record_lbl.add_theme_font_size_override("font_size", 14)
			record_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			vbox.add_child(record_lbl)

	var continue_btn := Button.new()
	continue_btn.text = "Retour au menu"
	continue_btn.custom_minimum_size = Vector2(0, 44)
	continue_btn.pressed.connect(func():
		AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
		NetworkManager.disconnect_from_game()
		SceneLoader.change_scene("res://scenes/main_menu.tscn")
	)
	vbox.add_child(continue_btn)


# ─── Helpers ───────────────────────────────────────────────────────────────────

func _show_notice(text: String, duration: float) -> void:
	_notice_label.text = text
	_notice_label.modulate.a = 1.0
	_notice_timer = duration
