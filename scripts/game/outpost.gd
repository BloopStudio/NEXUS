## Outpost — one of up to GameState.MAX_OUTPOSTS lightweight secondary
## defense points ("stations multiples"). Has its own small ring of
## buildable module slots (same module types/turret+mine gameplay as the
## main station, minus synergies/disable/charge modules to keep it simple)
## and its own HP — losing it doesn't end the match. Drawn at a world
## offset from the main station instead of the origin; multiple instances
## of this same script, one per outpost_index, are added in game.gd.
extends Node2D

const RADIUS := 26.0
const RING_RADIUS := 55.0
const SLOT_RADIUS := 17.0
const C_CORE := Color(0.15, 0.9, 0.65)  # teal, distinct from the main station's cyan
const C_CORE_DAMAGED := Color(1.0, 0.4, 0.1)
const C_SLOT_HOVER := Color(0.3, 0.3, 0.5)
const C_RING := Color(0.1, 0.2, 0.3)

const MODULE_COLORS := {
	0: Color(0.15, 0.15, 0.25),   # EMPTY
	1: Color(1.0,  0.9,  0.1),    # GENERATOR
	2: Color(1.0,  0.5,  0.0),    # TURRET
	3: Color(0.2,  0.3,  1.0),    # SHIELD
	4: Color(0.2,  1.0,  0.3),    # REPAIR
	5: Color(1.0,  0.15, 0.7),    # BOOSTER
	6: Color(0.9,  0.2,  0.15),   # MINE
	9: Color(0.75, 0.5,  0.25),   # DRILL
}

const MINE_RADIUS := 130.0
const MINE_INTERVAL := 3.0
const FLASH_DURATION := 0.09
const MINE_PULSE_DURATION := 0.35

## Set by game.gd right after instantiation — which GameState.outposts
## entry this node represents.
var outpost_index: int = 0

var _hovered_slot: int = -1
var _turret_timers: Array[float] = []
var _mine_timers: Array[float] = []
var _flashes: Dictionary = {}
var _mine_pulses: Dictionary = {}

signal slot_clicked(outpost_index: int, slot_index: int)


func _ready() -> void:
	position = GameState.get_outpost_offset(outpost_index)
	_turret_timers.resize(GameState.OUTPOST_SLOT_COUNT)
	_mine_timers.resize(GameState.OUTPOST_SLOT_COUNT)
	GameState.outpost_changed.connect(func(): queue_redraw())
	I18n.language_changed.connect(func(): queue_redraw())
	GameState.arena_expanded.connect(func(): position = GameState.get_outpost_offset(outpost_index))
	set_process(true)
	set_process_input(true)


func _built() -> bool:
	return GameState.outposts[outpost_index]["built"]


func _slots() -> Array:
	return GameState.outposts[outpost_index]["slots"]


func _process(delta: float) -> void:
	if not _built():
		return
	_update_turrets(delta)
	_update_mines(delta)
	_update_flashes(delta)
	_update_mine_pulses(delta)


func _slot_pos(index: int) -> Vector2:
	var angle := (index / float(GameState.OUTPOST_SLOT_COUNT)) * TAU - PI / 2.0
	return Vector2(cos(angle), sin(angle)) * RING_RADIUS


func _get_slot_at(local_pos: Vector2) -> int:
	for i in GameState.OUTPOST_SLOT_COUNT:
		if local_pos.distance_to(_slot_pos(i)) <= SLOT_RADIUS + 8:
			return i
	return -1


func get_slot_world_pos(index: int) -> Vector2:
	return global_position + _slot_pos(index)


func _input(event: InputEvent) -> void:
	if not _built():
		return
	if event is InputEventMouseMotion:
		var new_hover := _get_slot_at(to_local(get_global_mouse_position()))
		if new_hover != _hovered_slot:
			_hovered_slot = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _get_slot_at(to_local(get_global_mouse_position()))
		if idx >= 0:
			slot_clicked.emit(outpost_index, idx)


func _draw() -> void:
	if not _built():
		return

	var positions: Array[Vector2] = []
	for i in GameState.OUTPOST_SLOT_COUNT:
		positions.append(_slot_pos(i))

	draw_arc(Vector2.ZERO, RING_RADIUS + 4, 0, TAU, 40, C_RING, 2.0)
	for i in GameState.OUTPOST_SLOT_COUNT:
		draw_line(Vector2.ZERO, positions[i], C_RING, 1.0)
		var tick_angle := (i / float(GameState.OUTPOST_SLOT_COUNT)) * TAU - PI / 2.0
		var tick_dir := Vector2(cos(tick_angle), sin(tick_angle))
		draw_line(tick_dir * (RING_RADIUS + 4), tick_dir * (RING_RADIUS + 10), C_RING, 1.2)

	var slots := _slots()
	for i in GameState.OUTPOST_SLOT_COUNT:
		var pos := positions[i]
		var slot: Dictionary = slots[i]
		var mtype: int = slot["type"]
		var col: Color = MODULE_COLORS.get(mtype, C_CORE)
		if mtype != GameState.ModuleType.EMPTY:
			draw_circle(pos, SLOT_RADIUS * 1.8, Color(col.r, col.g, col.b, 0.08))
			draw_circle(pos, SLOT_RADIUS * 1.3, Color(col.r, col.g, col.b, 0.14))
		if i == _hovered_slot:
			draw_circle(pos, SLOT_RADIUS + 4, C_SLOT_HOVER)
		draw_circle(pos, SLOT_RADIUS, col)
		draw_arc(pos, SLOT_RADIUS, 0, TAU, 20, col.lightened(0.35), 1.2)
		ModuleInfo.draw_glyph(self, pos, mtype, SLOT_RADIUS)
		var level: int = slot.get("level", 0)
		for l in level:
			var dot_offset := Vector2(cos(PI / 4.0 * l) * 8, sin(PI / 4.0 * l) * 8)
			draw_circle(pos + dot_offset, 2.5, Color.WHITE)

	var hp: float = GameState.outposts[outpost_index]["hp"]
	var max_hp: float = GameState.outposts[outpost_index]["max_hp"]
	var hp_ratio := hp / max_hp if max_hp > 0.0 else 0.0
	var col := C_CORE.lerp(C_CORE_DAMAGED, 1.0 - hp_ratio)

	draw_circle(Vector2.ZERO, RADIUS * 1.9, Color(col.r, col.g, col.b, 0.06))

	var pts := PackedVector2Array([
		Vector2(0, -RADIUS), Vector2(RADIUS, 0), Vector2(0, RADIUS), Vector2(-RADIUS, 0),
	])
	draw_polygon(pts, [col.darkened(0.4)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.5)
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.35), 1.0)
	draw_arc(Vector2.ZERO, RADIUS + 8, -PI / 2, -PI / 2 + TAU * hp_ratio, 32, col, 4.0)

	var font := ThemeDB.fallback_font
	var label := I18n.t("outpost.label") % (outpost_index + 1)
	var font_size := 12
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-text_size.x / 2.0, -RING_RADIUS - SLOT_RADIUS - 12.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.8))

	for slot_index in _flashes:
		var f: Dictionary = _flashes[slot_index]
		var alpha: float = clampf(f["t"] / FLASH_DURATION, 0.0, 1.0)
		var from: Vector2 = _slot_pos(slot_index)
		draw_line(from, f["target"], Color(1.0, 0.85, 0.3, alpha), 2.0)
		draw_circle(from, 6.0 * alpha, Color(1.0, 0.9, 0.5, alpha))

	for slot_index in _mine_pulses:
		var t: float = _mine_pulses[slot_index]
		var progress := 1.0 - clampf(t / MINE_PULSE_DURATION, 0.0, 1.0)
		var alpha := 1.0 - progress
		draw_arc(Vector2.ZERO, MINE_RADIUS * progress, 0, TAU, 32, Color(1.0, 0.3, 0.2, alpha), 3.0)


# ─── Turret logic (simplified — no synergy bonus) ───────────────────────────
func _update_turrets(delta: float) -> void:
	if not NetworkManager.is_host():
		return
	var slots := _slots()
	for i in GameState.OUTPOST_SLOT_COUNT:
		if slots[i]["type"] != GameState.ModuleType.TURRET:
			continue
		_turret_timers[i] -= delta
		if _turret_timers[i] <= 0.0:
			_turret_timers[i] = _turret_fire_rate(slots[i]["level"])
			_fire_turret(i)


func _turret_fire_rate(level: int) -> float:
	match level:
		1: return 2.5
		2: return 1.8
		3: return 1.2
		_: return 2.5


func _turret_damage(level: int) -> float:
	match level:
		1: return 15.0
		2: return 28.0
		3: return 50.0
		_: return 15.0


func _fire_turret(slot_index: int) -> void:
	var game := get_parent()
	if game == null or not game.has_method("get_nearest_enemy"):
		return
	var enemy: Node2D = game.get_nearest_enemy(get_slot_world_pos(slot_index))
	if enemy == null:
		return
	var dmg := _turret_damage(_slots()[slot_index]["level"]) * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier()
	var impact_dir := (enemy.global_position - get_slot_world_pos(slot_index)).normalized()
	enemy.take_damage(dmg, impact_dir)
	GameState.record_damage(dmg)
	_turret_flash_rpc.rpc(slot_index, to_local(enemy.global_position))


@rpc("authority", "call_local", "reliable")
func _turret_flash_rpc(slot_index: int, target_local_pos: Vector2) -> void:
	AudioManager.play_sfx(AudioManager.SFX.TURRET_SHOT, -12.0)
	_flashes[slot_index] = {"target": target_local_pos, "t": FLASH_DURATION}
	queue_redraw()


func _update_flashes(delta: float) -> void:
	if _flashes.is_empty():
		return
	var expired := []
	for slot_index in _flashes:
		_flashes[slot_index]["t"] -= delta
		if _flashes[slot_index]["t"] <= 0.0:
			expired.append(slot_index)
	for slot_index in expired:
		_flashes.erase(slot_index)
	queue_redraw()


# ─── Mine logic (simplified — no synergy bonus) ─────────────────────────────
func _update_mines(delta: float) -> void:
	if not NetworkManager.is_host():
		return
	var slots := _slots()
	for i in GameState.OUTPOST_SLOT_COUNT:
		if slots[i]["type"] != GameState.ModuleType.MINE:
			continue
		_mine_timers[i] -= delta
		if _mine_timers[i] <= 0.0:
			_mine_timers[i] = MINE_INTERVAL
			_pulse_mine(i, slots[i]["level"])


func _mine_damage(level: int) -> float:
	match level:
		1: return 20.0
		2: return 35.0
		3: return 55.0
		_: return 20.0


func _pulse_mine(slot_index: int, level: int) -> void:
	var game := get_parent()
	if game == null or not game.has_method("get_enemies_in_radius"):
		return
	var dmg := _mine_damage(level) * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier()
	for enemy in game.get_enemies_in_radius(global_position, MINE_RADIUS):
		enemy.take_damage(dmg)
		GameState.record_damage(dmg)
	_mine_pulse_rpc.rpc(slot_index)


@rpc("authority", "call_local", "reliable")
func _mine_pulse_rpc(slot_index: int) -> void:
	AudioManager.play_sfx(AudioManager.SFX.TURRET_SHOT, -8.0)
	_mine_pulses[slot_index] = MINE_PULSE_DURATION
	queue_redraw()


func _update_mine_pulses(delta: float) -> void:
	if _mine_pulses.is_empty():
		return
	var expired := []
	for slot_index in _mine_pulses:
		_mine_pulses[slot_index] -= delta
		if _mine_pulses[slot_index] <= 0.0:
			expired.append(slot_index)
	for slot_index in expired:
		_mine_pulses.erase(slot_index)
	queue_redraw()
