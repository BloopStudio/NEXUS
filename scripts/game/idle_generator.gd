## IdleGenerator — passive energy production from GENERATOR modules
## Only runs on the host; energy is authoritative on the host and synced via GameState.
extends Node

# Energy per second per level
const ENERGY_PER_SEC := {1: 3.0, 2: 6.0, 3: 11.0}


func _ready() -> void:
	# Only host simulates idle generation
	if not NetworkManager.is_host():
		set_process(false)


func _process(delta: float) -> void:
	if GameState.phase == GameState.Phase.MENU or GameState.phase == GameState.Phase.GAME_OVER:
		return

	var total := 0.0
	for i in GameState.module_slots.size():
		var slot: Dictionary = GameState.module_slots[i]
		if slot["type"] == GameState.ModuleType.GENERATOR:
			var level: int = slot.get("level", 0)
			# Synergy: a Générateur next to another Générateur produces more —
			# clustering them beats spreading them around the ring.
			var adjacent_generators := GameState.count_adjacent_type(i, GameState.ModuleType.GENERATOR)
			total += ENERGY_PER_SEC.get(level, 0.0) * (1.0 + 0.1 * adjacent_generators)

	if total > 0.0:
		GameState.add_energy(total * GameState.get_skill_idle_multiplier() * delta)
