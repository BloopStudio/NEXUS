## GameState — Autoload singleton
## Holds the shared game state, synchronized by the host.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal energy_changed(new_value: float)
signal wave_changed(new_number: int)
signal station_health_changed(new_hp: float)
signal phase_changed(new_phase: Phase)
signal game_over()
signal module_slots_changed(slot_index: int)

# ─── Enums ─────────────────────────────────────────────────────────────────────
enum Phase { MENU, BUILD, WAVE, UPGRADE, GAME_OVER }

# ─── Module types ──────────────────────────────────────────────────────────────
# BOOSTER is appended last so existing type values (used over the network)
# stay stable.
enum ModuleType { EMPTY, GENERATOR, TURRET, SHIELD, REPAIR, BOOSTER }

# ─── Costs (energy) ────────────────────────────────────────────────────────────
const MODULE_COSTS := {
	ModuleType.GENERATOR: 30,
	ModuleType.TURRET:    40,
	ModuleType.SHIELD:    50,
	ModuleType.REPAIR:    35,
	ModuleType.BOOSTER:   45,
}
const BOOSTER_DAMAGE_BONUS_PER_LEVEL := 0.15  # +15% player bullet damage per level, per module
const REPAIR_MAX_HP_BONUS_PER_LEVEL := 60.0   # +60 max station HP per level, per module
const UPGRADE_COST_MULTIPLIER := 1.8  # cost *= multiplier per level

# ─── State ─────────────────────────────────────────────────────────────────────
var phase: Phase = Phase.MENU

var energy: float = 50.0:
	set(v):
		energy = maxf(0.0, v)
		energy_changed.emit(energy)

var wave_number: int = 0:
	set(v):
		wave_number = v
		wave_changed.emit(wave_number)

var station_max_hp: float = 500.0
var station_hp: float = 500.0:
	set(v):
		station_hp = clampf(v, 0.0, station_max_hp)
		station_health_changed.emit(station_hp)
		if station_hp <= 0.0 and phase != Phase.GAME_OVER:
			_trigger_game_over()

# Slots: array of {type: ModuleType, level: int}
# 8 slots arranged in a ring around the station
var module_slots: Array[Dictionary] = []

# ─── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_init_slots()
	set_process(true)


# ─── Network sync (host → clients) ─────────────────────────────────────────────
# The host is authoritative: it periodically pushes a full snapshot so every
# client's local copy of the shared station state stays in sync. Without
# this, building/upgrading or taking station damage was only ever visible
# to whichever peer triggered it.
var _sync_timer: float = 0.0
const SYNC_INTERVAL := 0.15


func _process(delta: float) -> void:
	if not NetworkManager.is_host():
		return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_apply_snapshot_rpc.rpc(energy, wave_number, station_hp, station_max_hp, int(phase), module_slots)


@rpc("authority", "reliable")
func _apply_snapshot_rpc(e: float, w: int, hp: float, max_hp: float, ph: int, slots: Array) -> void:
	station_max_hp = max_hp
	wave_number = w
	energy = e
	station_hp = hp

	# Only touch module_slots (and emit its signal) when something actually
	# changed — this snapshot arrives ~7×/second, and module_slots_changed
	# triggers a full rebuild of the build/upgrade panel. Emitting it every
	# tick regardless of content would make building/upgrading on a client
	# nearly impossible, the exact same class of bug as the original
	# "menu rebuilt every energy tick" issue, just via the network path.
	if not _slots_equal(module_slots, slots):
		module_slots.clear()
		for s in slots:
			module_slots.append(s as Dictionary)
		module_slots_changed.emit(-1)  # -1 = "refresh everything"

	# Same reasoning for phase — UI resets its selection on phase_changed.
	if ph != int(phase):
		set_phase(ph as Phase)


func _slots_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var sa: Dictionary = a[i]
		var sb: Dictionary = b[i]
		if sa.get("type") != sb.get("type") or sa.get("level") != sb.get("level"):
			return false
	return true


## Client → host: ask to build/upgrade a slot. On the host this just applies
## immediately (it calls itself); the next periodic snapshot then carries
## the result to everyone.
func request_build_module(slot_index: int, type: ModuleType) -> void:
	if NetworkManager.is_host():
		build_module(slot_index, type)
	else:
		_request_build_rpc.rpc_id(1, slot_index, int(type))


@rpc("any_peer", "reliable")
func _request_build_rpc(slot_index: int, type: int) -> void:
	if not multiplayer.is_server():
		return
	build_module(slot_index, type as ModuleType)


func request_upgrade_module(slot_index: int) -> void:
	if NetworkManager.is_host():
		upgrade_module(slot_index)
	else:
		_request_upgrade_rpc.rpc_id(1, slot_index)


@rpc("any_peer", "reliable")
func _request_upgrade_rpc(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	upgrade_module(slot_index)


func _init_slots() -> void:
	module_slots.clear()
	for i in 8:
		module_slots.append({"type": ModuleType.EMPTY, "level": 0})


# ─── Phase management ──────────────────────────────────────────────────────────
func set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(phase)


# ─── Energy helpers ────────────────────────────────────────────────────────────
func can_afford(cost: float) -> bool:
	return energy >= cost


func spend_energy(cost: float) -> bool:
	if not can_afford(cost):
		return false
	energy -= cost
	return true


func add_energy(amount: float) -> void:
	energy += amount


# ─── Module helpers ────────────────────────────────────────────────────────────
func get_module_build_cost(type: ModuleType) -> float:
	return MODULE_COSTS.get(type, 999.0)


func get_module_upgrade_cost(slot_index: int) -> float:
	var slot := module_slots[slot_index]
	if slot["type"] == ModuleType.EMPTY:
		return 0.0
	var base: float = MODULE_COSTS.get(slot["type"], 0.0)
	return base * pow(UPGRADE_COST_MULTIPLIER, slot["level"])


func build_module(slot_index: int, type: ModuleType) -> bool:
	var cost := get_module_build_cost(type)
	if not spend_energy(cost):
		return false
	module_slots[slot_index] = {"type": type, "level": 1}
	_recompute_station_max_hp()
	module_slots_changed.emit(slot_index)
	return true


func upgrade_module(slot_index: int) -> bool:
	var slot := module_slots[slot_index]
	if slot["type"] == ModuleType.EMPTY or slot["level"] >= 3:
		return false
	var cost := get_module_upgrade_cost(slot_index)
	if not spend_energy(cost):
		return false
	module_slots[slot_index]["level"] += 1
	_recompute_station_max_hp()
	module_slots_changed.emit(slot_index)
	return true


## Clears a built module back to EMPTY. No energy refund — mirrors the
## "sunk cost" of most base-building games and keeps the economy simple.
func destroy_module(slot_index: int) -> bool:
	if module_slots[slot_index]["type"] == ModuleType.EMPTY:
		return false
	module_slots[slot_index] = {"type": ModuleType.EMPTY, "level": 0}
	_recompute_station_max_hp()
	module_slots_changed.emit(slot_index)
	return true


func request_destroy_module(slot_index: int) -> void:
	if NetworkManager.is_host():
		destroy_module(slot_index)
	else:
		_request_destroy_rpc.rpc_id(1, slot_index)


@rpc("any_peer", "reliable")
func _request_destroy_rpc(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	destroy_module(slot_index)


## REPAIR modules raise the station's max HP (the extra capacity becomes
## available headroom — building one doesn't instantly heal the station).
func _recompute_station_max_hp() -> void:
	var bonus := 0.0
	for slot in module_slots:
		if slot["type"] == ModuleType.REPAIR:
			bonus += REPAIR_MAX_HP_BONUS_PER_LEVEL * slot["level"]
	var new_max := 500.0 + bonus
	if new_max != station_max_hp:
		station_max_hp = new_max
		station_hp = station_hp  # re-run the setter so it re-clamps against the new max


## Sums the damage bonus from every built BOOSTER module (players hit harder
## the more of these the team builds and upgrades).
func get_player_damage_multiplier() -> float:
	var mult := 1.0
	for slot in module_slots:
		if slot["type"] == ModuleType.BOOSTER:
			mult += BOOSTER_DAMAGE_BONUS_PER_LEVEL * slot["level"]
	return mult


# ─── Station ───────────────────────────────────────────────────────────────────
func heal_station(amount: float) -> void:
	station_hp += amount


func damage_station(amount: float) -> void:
	station_hp -= amount


# ─── Full reset ────────────────────────────────────────────────────────────────
func reset() -> void:
	energy = 50.0
	wave_number = 0
	station_max_hp = 500.0
	station_hp = 500.0
	_init_slots()
	set_phase(Phase.BUILD)


# ─── Internal ──────────────────────────────────────────────────────────────────
func _trigger_game_over() -> void:
	set_phase(Phase.GAME_OVER)
	game_over.emit()
