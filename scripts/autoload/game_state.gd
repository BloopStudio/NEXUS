## GameState — Autoload singleton
## Holds the shared game state, synchronized by the host.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal energy_changed(new_value: float)
signal wave_changed(new_number: int)
signal station_health_changed(new_hp: float)
signal phase_changed(new_phase: Phase)
signal game_over()

# ─── Enums ─────────────────────────────────────────────────────────────────────
enum Phase { MENU, BUILD, WAVE, UPGRADE, GAME_OVER }

# ─── Module types ──────────────────────────────────────────────────────────────
enum ModuleType { EMPTY, GENERATOR, TURRET, SHIELD, REPAIR }

# ─── Costs (energy) ────────────────────────────────────────────────────────────
const MODULE_COSTS := {
	ModuleType.GENERATOR: 30,
	ModuleType.TURRET:    40,
	ModuleType.SHIELD:    50,
	ModuleType.REPAIR:    35,
}
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
	return true


func upgrade_module(slot_index: int) -> bool:
	var slot := module_slots[slot_index]
	if slot["type"] == ModuleType.EMPTY or slot["level"] >= 3:
		return false
	var cost := get_module_upgrade_cost(slot_index)
	if not spend_energy(cost):
		return false
	module_slots[slot_index]["level"] += 1
	return true


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
