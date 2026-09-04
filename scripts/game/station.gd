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
	6: Color(0.9,  0.2,  0.15),   # MINE       — red
	7: Color(1.0,  0.7,  0.1),    # EMERGENCY_SHIELD — amber
	8: Color(0.4,  1.0,  0.4),    # EMP        — radioactive green
	9: Color(0.75, 0.5,  0.25),   # DRILL      — copper
}

var _hovered_slot: int = -1

# Auto-firing for Turret modules, and pulse timers for Mine modules —
# indexed by slot index; grown/shrunk to match module_slots.size() (the
# skill tree can unlock extra slots mid-match).
var _turret_timers: Array[float] = []
var _mine_timers: Array[float] = []

# Muzzle flash: slot_index -> {"target": Vector2, "t": float}
var _flashes: Dictionary = {}
const FLASH_DURATION := 0.09
# Mine pulse: slot_index -> seconds remaining for the expanding ring visual
var _mine_pulses: Dictionary = {}
const MINE_PULSE_DURATION := 0.35
const MINE_RADIUS := 150.0
const MINE_INTERVAL := 3.0

signal slot_clicked(slot_index: int)

func _ready() -> void:
	_resize_timers()
	GameState.station_health_changed.connect(func(_v): queue_redraw())
	GameState.module_slots_changed.connect(func(_i): queue_redraw())
	# Built-in listener (separate from game.gd wiring slot_clicked to the
	# build/upgrade panel) — that panel already ignores clicks outside
	# BUILD/UPGRADE, this is the WAVE-phase counterpart for charge modules.
	slot_clicked.connect(_on_slot_clicked_for_charge_trigger)

	set_process(true)
	set_process_input(true)


func _slot_count() -> int:
	return GameState.module_slots.size()


func _resize_timers() -> void:
	var n := _slot_count()
	_turret_timers.resize(n)
	_mine_timers.resize(n)


func _process(delta: float) -> void:
	if _turret_timers.size() != _slot_count():
		_resize_timers()
	_update_turrets(delta)
	_update_mines(delta)
	_update_flashes(delta)
	_update_mine_pulses(delta)
	# The disabled-slot ring and synergy-link glow both animate via
	# Time.get_ticks_msec() inside _draw(), but nothing else redraws every
	# frame — without this they'd sit frozen on whatever phase happened to
	# be showing at the last state-triggered redraw instead of actually
	# pulsing. Only pay for a continuous redraw while there's something to
	# animate, not on every station in every match.
	if _has_animated_visuals():
		queue_redraw()


func _has_animated_visuals() -> bool:
	var n := _slot_count()
	for i in n:
		if GameState.module_slots[i].get("disabled", false):
			return true
	for i in n:
		var next_i := (i + 1) % n
		if _synergy_link_color(GameState.module_slots[i]["type"], GameState.module_slots[next_i]["type"]) != null:
			return true
	return false


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
	var n := _slot_count()
	var positions: Array[Vector2] = []
	for i in n:
		positions.append(_slot_pos(i))

	# Outer ring
	draw_arc(Vector2.ZERO, RING_RADIUS + 4, 0, TAU, 64, C_RING, 2.0)

	# Slot connectors (lines from center to each slot)
	for i in n:
		draw_line(Vector2.ZERO, positions[i], C_RING, 1.0)

	# Slots
	for i in n:
		var pos := positions[i]
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

		# Disabled overlay (Saboteur hit it) — dark wash + pulsing red
		# ring, so it reads clearly which slot stopped working and why.
		if slot.get("disabled", false):
			var pulse: float = 0.5 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
			draw_circle(pos, SLOT_RADIUS, Color(0.02, 0.02, 0.03, 0.6))
			draw_arc(pos, SLOT_RADIUS + 5, 0, TAU, 24, Color(1.0, 0.15, 0.15, pulse), 2.5)

	# Synergy links — a bright pulsing line between two adjacent slots
	# whose module types actively boost each other, so the bonus (silent
	# and invisible otherwise) actually reads as something happening.
	_draw_synergy_links(positions)

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

	# Mine pulses — expanding ring from the station center
	for slot_index in _mine_pulses:
		var t: float = _mine_pulses[slot_index]
		var progress := 1.0 - clampf(t / MINE_PULSE_DURATION, 0.0, 1.0)
		var alpha := 1.0 - progress
		draw_arc(Vector2.ZERO, MINE_RADIUS * progress, 0, TAU, 40, Color(1.0, 0.3, 0.2, alpha), 3.0)

	# Hovered-slot tooltip: module name (or "Vide" for an empty slot), floating
	# just above the slot so it's clear what you're about to click.
	if _hovered_slot >= 0 and _hovered_slot < n:
		var slot: Dictionary = GameState.module_slots[_hovered_slot]
		var mtype: int = slot["type"]
		var level: int = slot.get("level", 0)
		var label: String = ModuleInfo.NAMES[mtype]
		if mtype != GameState.ModuleType.EMPTY:
			label += " (niv. %d)" % level
		label += GameState.get_synergy_note(_hovered_slot)
		if slot.get("disabled", false):
			label += " · 🔒 désactivé (Saboteur)"
		var font := ThemeDB.fallback_font
		var font_size := 14
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var tooltip_pos := positions[_hovered_slot] + Vector2(-text_size.x / 2.0, -SLOT_RADIUS - 14.0)
		draw_rect(Rect2(tooltip_pos + Vector2(-6, -text_size.y + 3), text_size + Vector2(12, 8)),
			Color(0.02, 0.02, 0.04, 0.85))
		draw_string(font, tooltip_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


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

	for i in _slot_count():
		var slot := GameState.module_slots[i]
		if slot["type"] != GameState.ModuleType.TURRET or slot.get("disabled", false):
			continue

		_turret_timers[i] -= delta
		if _turret_timers[i] <= 0.0:
			# Synergy: a Turret next to another Turret fires faster — rewards
			# clustering them instead of spreading modules evenly.
			var adjacent_turrets := GameState.count_adjacent_type(i, GameState.ModuleType.TURRET)
			var fire_rate := _turret_fire_rate(slot["level"]) * (1.0 - 0.15 * adjacent_turrets)
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

	var dmg := _turret_damage(GameState.module_slots[slot_index]["level"]) * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier()
	var impact_dir := (enemy.global_position - _slot_pos(slot_index)).normalized()
	enemy.take_damage(dmg, impact_dir)
	GameState.record_damage(dmg)

	_turret_flash_rpc.rpc(slot_index, to_local(enemy.global_position))


## Broadcasts the muzzle-flash visual (and its sound) to every peer — firing
## is host-only simulation, but everyone should see/hear the shot.
@rpc("authority", "call_local", "reliable")
func _turret_flash_rpc(slot_index: int, target_local_pos: Vector2) -> void:
	AudioManager.play_sfx(AudioManager.SFX.TURRET_SHOT, -10.0)
	_flashes[slot_index] = {"target": target_local_pos, "t": FLASH_DURATION}
	queue_redraw()


func _turret_damage(level: int) -> float:
	match level:
		1: return 15.0
		2: return 28.0
		3: return 50.0
		_: return 15.0


# ─── Mine logic ────────────────────────────────────────────────────────────────
## Unlike Turret (single-target), Mine periodically pulses damage to every
## enemy within MINE_RADIUS of the station — a defensive, no-aim area module.
func _update_mines(delta: float) -> void:
	if not NetworkManager.is_host():
		return

	for i in _slot_count():
		var slot := GameState.module_slots[i]
		if slot["type"] != GameState.ModuleType.MINE or slot.get("disabled", false):
			continue

		_mine_timers[i] -= delta
		if _mine_timers[i] <= 0.0:
			_mine_timers[i] = MINE_INTERVAL
			_pulse_mine(i, slot["level"])


func _pulse_mine(slot_index: int, level: int) -> void:
	var game := get_parent()
	if game == null or not game.has_method("get_enemies_in_radius"):
		return
	# Synergy: a Mine next to an Amplificateur (Booster) hits harder — the
	# module that's otherwise player-damage-only also helps a nearby Mine.
	var adjacent_boosters := GameState.count_adjacent_type(slot_index, GameState.ModuleType.BOOSTER)
	var dmg := _mine_damage(level) * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier() * (1.0 + 0.25 * adjacent_boosters)
	for enemy in game.get_enemies_in_radius(global_position, MINE_RADIUS):
		enemy.take_damage(dmg)
		GameState.record_damage(dmg)
	_mine_pulse_rpc.rpc(slot_index)


## Broadcasts the mine pulse ring (and its sound) to every peer — damage is
## host-only simulation, but everyone should see/hear the pulse.
@rpc("authority", "call_local", "reliable")
func _mine_pulse_rpc(slot_index: int) -> void:
	AudioManager.play_sfx(AudioManager.SFX.TURRET_SHOT, -6.0)
	_mine_pulses[slot_index] = MINE_PULSE_DURATION
	queue_redraw()


func _mine_damage(level: int) -> float:
	match level:
		1: return 20.0
		2: return 35.0
		3: return 55.0
		_: return 20.0


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


# ─── Single-charge modules (Bouclier d'urgence, Bombe EMP) ─────────────────────
# Unlike every other module, these don't do anything passively — clicking
# their built slot DURING A WAVE triggers a one-time effect and consumes
# them. Outside a wave, the same click instead opens the normal build/
# upgrade panel (see upgrade_menu.gd's on_slot_clicked, which ignores clicks
# outside BUILD/UPGRADE) — the two handlers just watch different phases of
# the exact same signal.
func _on_slot_clicked_for_charge_trigger(idx: int) -> void:
	if GameState.phase != GameState.Phase.WAVE:
		return
	var slot: Dictionary = GameState.module_slots[idx]
	if slot["type"] != GameState.ModuleType.EMERGENCY_SHIELD and slot["type"] != GameState.ModuleType.EMP:
		return
	if slot.get("disabled", false):
		return
	if NetworkManager.is_host():
		_trigger_charge_module(idx)
	else:
		_request_trigger_charge_rpc.rpc_id(1, idx)


@rpc("any_peer", "reliable")
func _request_trigger_charge_rpc(idx: int) -> void:
	if not NetworkManager.is_host():
		return
	_trigger_charge_module(idx)


func _trigger_charge_module(idx: int) -> void:
	var mtype := GameState.consume_charge_module(idx)
	if mtype == GameState.ModuleType.EMPTY:
		return  # slot wasn't actually a charge module (race with another trigger) — no-op
	_charge_effect_rpc.rpc(int(mtype))


## Plays the effect on every peer; only the host applies the actual
## gameplay change (damage/heal/stun), same authority pattern as
## turrets/mines/spells.
@rpc("authority", "call_local", "reliable")
func _charge_effect_rpc(mtype: int) -> void:
	match mtype:
		GameState.ModuleType.EMERGENCY_SHIELD:
			AudioManager.play_sfx(AudioManager.SFX.UPGRADE, 6.0)
			if NetworkManager.is_host():
				GameState.heal_station(GameState.station_max_hp * GameState.EMERGENCY_SHIELD_HEAL_RATIO)
				GameState.station_invuln_timer = GameState.EMERGENCY_SHIELD_INVULN_SECONDS
		GameState.ModuleType.EMP:
			AudioManager.play_sfx(AudioManager.SFX.TURRET_SHOT, 8.0)
			if NetworkManager.is_host():
				var game := get_parent()
				if game != null and game.has_method("get_enemies_in_radius"):
					for enemy in game.get_enemies_in_radius(global_position, 99999.0):
						enemy.take_damage(GameState.EMP_DAMAGE)
						GameState.record_damage(GameState.EMP_DAMAGE)
						if enemy.has_method("apply_slow"):
							enemy.apply_slow(0.0, GameState.EMP_STUN_SECONDS)


# ─── Helpers ───────────────────────────────────────────────────────────────────
func _slot_pos(index: int) -> Vector2:
	var angle := (index / float(_slot_count())) * TAU - PI / 2.0
	return Vector2(cos(angle), sin(angle)) * RING_RADIUS


func _get_slot_at(local_pos: Vector2) -> int:
	for i in _slot_count():
		if local_pos.distance_to(_slot_pos(i)) <= SLOT_RADIUS + 8:
			return i
	return -1


func get_slot_world_pos(index: int) -> Vector2:
	return global_position + _slot_pos(index)


## Slot closest to `world_pos` — used by the Saboteur enemy on arrival to
## figure out which built module it actually reached (it targets a slot's
## world position directly, but doesn't otherwise know its own index).
func get_nearest_slot_index(world_pos: Vector2) -> int:
	var local_pos := to_local(world_pos)
	var best := -1
	var best_dist := INF
	for i in _slot_count():
		var d := local_pos.distance_to(_slot_pos(i))
		if d < best_dist:
			best_dist = d
			best = i
	return best


# ─── Synergy visuals ────────────────────────────────────────────────────────────
func _draw_synergy_links(positions: Array[Vector2]) -> void:
	var n := _slot_count()
	if n < 2:
		return
	var pulse: float = 0.55 + 0.35 * sin(Time.get_ticks_msec() / 300.0)
	for i in n:
		var next_i := (i + 1) % n
		var a: Dictionary = GameState.module_slots[i]
		var b: Dictionary = GameState.module_slots[next_i]
		if a.get("disabled", false) or b.get("disabled", false):
			continue
		var link_col = _synergy_link_color(a["type"], b["type"])
		if link_col == null:
			continue
		var col: Color = link_col
		col.a = pulse
		draw_line(positions[i], positions[next_i], col, 3.0)
		draw_circle(positions[i].lerp(positions[next_i], 0.5), 4.0, col)


## Returns the link color for an actively-synergizing adjacent pair, or null
## if this pair of types doesn't synergize — kept in sync with the actual
## bonuses computed in station.gd/idle_generator.gd via
## GameState.count_adjacent_type().
func _synergy_link_color(type_a: int, type_b: int) -> Variant:
	if type_a == GameState.ModuleType.TURRET and type_b == GameState.ModuleType.TURRET:
		return Color(1.0, 0.6, 0.1)
	if (type_a == GameState.ModuleType.MINE and type_b == GameState.ModuleType.BOOSTER) \
			or (type_a == GameState.ModuleType.BOOSTER and type_b == GameState.ModuleType.MINE):
		return Color(1.0, 0.25, 0.55)
	if type_a == GameState.ModuleType.GENERATOR and type_b == GameState.ModuleType.GENERATOR:
		return Color(1.0, 0.95, 0.3)
	return null
