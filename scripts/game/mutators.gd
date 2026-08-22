## Mutators — station-wide modifiers picked by the host before a match starts
## (like a roguelite "seed"), applied for the whole run. Mirrors PlayerClasses/
## Spells' pattern: static data, no autoload needed.
class_name Mutators

enum Mutator { NONE, GLASS_CANNON, FORTRESS, RUSH, ECONOMIST }

const DEFS := {
	Mutator.NONE: {
		"name": "Aucun", "icon": "➖",
		"desc": "Partie standard, sans modificateur.",
	},
	Mutator.GLASS_CANNON: {
		"name": "Canon de verre", "icon": "💎",
		"desc": "+20% dégâts (joueurs/tourelles/mines), -20% vie de la station.",
		"damage_mult": 1.2, "station_hp_mult": 0.8,
	},
	Mutator.FORTRESS: {
		"name": "Forteresse", "icon": "🏰",
		"desc": "+30% vie de la station, -15% dégâts.",
		"damage_mult": 0.85, "station_hp_mult": 1.3,
	},
	Mutator.RUSH: {
		"name": "Ruée", "icon": "⚡",
		"desc": "+25% énergie passive, mais ennemis +10% de vie.",
		"energy_mult": 1.25, "wave_hp_mult": 1.1,
	},
	Mutator.ECONOMIST: {
		"name": "Économe", "icon": "💰",
		"desc": "-15% coût de construction/amélioration, -10% dégâts.",
		"damage_mult": 0.9, "cost_mult": 0.85,
	},
}

static func all_ids() -> Array:
	return DEFS.keys()
