## Station — the central hub players defend
## Drawn entirely with _draw() — no sprites needed.
## 8 module slots arranged in a ring around the core.
extends Node2D

const CORE_RADIUS    := 40.0
const RING_RADIUS    := 110.0  # distance from center to module slots
const SLOT_RADIUS    := 22.0

const C_CORE         := Color(0.0, 0.831, 1.0)       # cyan
const C_CORE_DAMAGED := Color(1.0, 0.4, 0.1)
const C_RING         := Color(0.1, 0.2, 0.3)
const C_SLOT_EMPTY   := Color(0.15, 0.15, 0.25)
const C_SLOT_HOVER   := Color(0.3, 0.3, 0.5)
const C_HP_BAR_BG    := Color(0.1, 0.1, 0.1)
const C_HP_BAR_OK    := Color(0.2, 0.9, 0.3)
const C_HP_BAR_LOW   := Color(1.0, 0.3, 0.1)

## Module colors by type
const MODULE_COLORS := {
	0: Color(0.15, 0.15, 0.25),   # EMPTY
	1: Color(1.0,  0.9,  0.1),    # GENERATOR  — yellow
	2: Color(1.0,  0.5,  0.0),    # TURRET     — orange
	3: Color(0.2,  0.3,  1.0),    # SHIELD     — blue
	4: Color(0.2,  1.0,  0.3),    # REPAIR     — green
	5: Color(1.0,  0.15, 0.7),    # BOOSTER    — magenta
}

var _hovered_slot: int = -1

# Auto-firing for Turret modules
var _turret_timers: Array[float] = []

# Muzzle flash: slot_index -> {"target": Vector2, "t": float}
var _flashes: Dictionary = {}
const FLASH_DURATION := 0.09

signal slot_clicked(slot_index: int)

func _ready() -> void:
	_turret_timers.resize(8)
	_turret_timers.fill(0.0)
	GameState.station_health_changed.connect(func(_v): queue_redraw())
	GameState.module_slots_changed.connect(func(_i): queue_redraw())

	set_process(true)
	set_process_input(true)


func _process(delta: float) -> void:
	_update_turrets(delta)
	_update_flashes(delta)


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


func _draw() -> void:
	# Outer ring
	draw_arc(Vector2.ZERO, RING_RADIUS + 4, 0, TAU, 64, C_RING, 2.0)

	# Slot connectors (lines from center to each slot)
	for i in 8:
		var pos := _slot_pos(i)
		draw_line(Vector2.ZERO, pos, C_RING, 1.0)

	# Slots
	for i in 8:
		var pos := _slot_pos(i)
		var slot := GameState.module_slots[i]
		var mtype: int = slot["type"]
		var col: Color = MODULE_COLORS.get(mtype, C_SLOT_EMPTY)
		var is_hover := (i == _hovered_slot)

		if is_hover:
			draw_circle(pos, SLOT_RADIUS + 4, C_SLOT_HOVER)
		draw_circle(pos, SLOT_RADIUS, col)

		# Level indicators (small dots)
		var level: int = slot.get("level", 0)
		for l in level:
			var dot_offset := Vector2(cos(PI / 4.0 * l) * 10, sin(PI / 4.0 * l) * 10)
			draw_circle(pos + dot_offset, 3.0, Color.WHITE)

	# HP bar (arc)
	var hp_ratio := GameState.station_hp / GameState.station_max_hp
	var hp_color := C_HP_BAR_OK.lerp(C_HP_BAR_LOW, 1.0 - hp_ratio)
	draw_arc(Vector2.ZERO, CORE_RADIUS + 8, -PI / 2, -PI / 2 + TAU * hp_ratio, 48, hp_color, 4.0)

	# Core
	var core_col := C_CORE.lerp(C_CORE_DAMAGED, 1.0 - (GameState.station_hp / GameState.station_max_hp))
	draw_circle(Vector2.ZERO, CORE_RADIUS, core_col.darkened(0.4))
	draw_arc(Vector2.ZERO, CORE_RADIUS, 0, TAU, 48, core_col, 2.5)

	# Inner hexagon
	var hex := PackedVector2Array()
	for i in 6:
		var a := i * PI / 3.0 - PI / 6.0
		hex.append(Vector2(cos(a), sin(a)) * 20.0)
	draw_polygon(hex, [core_col.darkened(0.2)])

	# Turret muzzle flashes
	for slot_index in _flashes:
		var f: Dictionary = _flashes[slot_index]
		var alpha: float = clampf(f["t"] / FLASH_DURATION, 0.0, 1.0)
		var from: Vector2 = _slot_pos(slot_index)
		draw_line(from, f["target"], Color(1.0, 0.85, 0.3, alpha), 2.0)
		draw_circle(from, 6.0 * alpha, Color(1.0, 0.9, 0.5, alpha))


func _input(event: InputEvent) -> void:
	# Use get_global_mouse_position() (not the raw viewport-space event.position)
	# so slot hit-testing accounts for the active Camera2D / viewport stretch.
	if event is InputEventMouseMotion:
		var new_hover := _get_slot_at(to_local(get_global_mouse_position()))
		if new_hover != _hovered_slot:
			_hovered_slot = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _get_slot_at(to_local(get_global_mouse_position()))
		if idx >= 0:
			slot_clicked.emit(idx)


# ─── Turret logic ──────────────────────────────────────────────────────────────
func _update_turrets(delta: float) -> void:
	if not NetworkManager.is_host():
		return  # Only host simulates

	for i in 8:
		var slot := GameState.module_slots[i]
		if slot["type"] != GameState.ModuleType.TURRET:
			continue

		_turret_timers[i] -= delta
		if _turret_timers[i] <= 0.0:
			var fire_rate := _turret_fire_rate(slot["level"])
			_turret_timers[i] = fire_rate
			_fire_turret(i)


func _turret_fire_rate(level: int) -> float:
	match level:
		1: return 2.5
		2: return 1.8
		3: return 1.2
		_: return 2.5


func _fire_turret(slot_index: int) -> void:
	# Find nearest enemy and shoot it
	var game := get_parent()
	if game == null or not game.has_method("get_nearest_enemy"):
		return
	var enemy: Node2D = game.get_nearest_enemy(_slot_pos(slot_index))
	if enemy == null:
		return

	var dmg := _turret_damage(GameState.module_slots[slot_index]["level"])
	enemy.take_damage(dmg)
	AudioManager.play_sfx(AudioManager.SFX.TURRET_SHOT, -10.0)

	_flashes[slot_index] = {"target": to_local(enemy.global_position), "t": FLASH_DURATION}
	queue_redraw()


func _turret_damage(level: int) -> float:
	match level:
		1: return 15.0
		2: return 28.0
		3: return 50.0
		_: return 15.0


# ─── Helpers ───────────────────────────────────────────────────────────────────
func _slot_pos(index: int) -> Vector2:
	var angle := (index / 8.0) * TAU - PI / 2.0
	return Vector2(cos(angle), sin(angle)) * RING_RADIUS


func _get_slot_at(local_pos: Vector2) -> int:
	for i in 8:
		if local_pos.distance_to(_slot_pos(i)) <= SLOT_RADIUS + 8:
			return i
	return -1


func get_slot_world_pos(index: int) -> Vector2:
	return global_position + _slot_pos(index)
