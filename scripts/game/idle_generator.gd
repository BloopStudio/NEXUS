## IdleGenerator — passive energy production from GENERATOR modules, and
## passive rare-material production from DRILL modules.
## Only runs on the host; both currencies are authoritative on the host and
## synced via GameState.
extends Node

# Energy per second per level
const ENERGY_PER_SEC := {1: 3.0, 2: 6.0, 3: 11.0}

# Rare materials per second per level — deliberately much smaller than
# energy, since materials only spend on the Forge orbitale HP tiers rather
# than the whole build/upgrade economy.
const MATERIALS_PER_SEC := {1: 0.4, 2: 0.8, 3: 1.4}


func _ready() -> void:
	# Only host simulates idle generation
	if not NetworkManager.is_host():
		set_process(false)


func _process(delta: float) -> void:
	if GameState.phase == GameState.Phase.MENU or GameState.phase == GameState.Phase.GAME_OVER:
		return

	var energy_total := 0.0
	var materials_total := 0.0
	for i in GameState.module_slots.size():
		var slot: Dictionary = GameState.module_slots[i]
		if slot.get("disabled", false):
			continue
		var level: int = slot.get("level", 0)
		if slot["type"] == GameState.ModuleType.GENERATOR:
			# Synergy: a Générateur next to another Générateur produces more —
			# clustering them beats spreading them around the ring.
			var adjacent_generators := GameState.count_adjacent_type(i, GameState.ModuleType.GENERATOR)
			energy_total += ENERGY_PER_SEC.get(level, 0.0) * (1.0 + 0.1 * adjacent_generators)
		elif slot["type"] == GameState.ModuleType.DRILL:
			materials_total += MATERIALS_PER_SEC.get(level, 0.0)

	# Outposts have their own GENERATOR/DRILL slots (same buildable types as
	# the station, minus synergies — see outpost.gd) — these used to be
	# silently ignored here, the same class of bug already fixed for the
	# outpost Réparation/Bouclier/Amplificateur modules.
	for outpost in GameState.outposts:
		if not outpost["built"]:
			continue
		for slot in outpost["slots"]:
			if slot.get("disabled", false):
				continue
			var level: int = slot.get("level", 0)
			if slot["type"] == GameState.ModuleType.GENERATOR:
				energy_total += ENERGY_PER_SEC.get(level, 0.0)
			elif slot["type"] == GameState.ModuleType.DRILL:
				materials_total += MATERIALS_PER_SEC.get(level, 0.0)

	if energy_total > 0.0:
		GameState.add_energy(energy_total * GameState.get_skill_idle_multiplier() * GameState.get_mutator_energy_multiplier() * delta)
	if materials_total > 0.0:
		GameState.add_rare_materials(materials_total * delta)
