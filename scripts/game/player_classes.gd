## PlayerClasses — chosen once per player in the main-menu, before a match.
## Purely stat modifiers + a suggested starting spell — no unique abilities of
## their own, so they stay simple to balance and don't need separate art.
class_name PlayerClasses

enum PlayerClass { DAMAGE, HEAL, TANK }

const DEFS := {
	PlayerClass.DAMAGE: {
		"name": "Dégâts", "icon": "⚔",
		"desc": "+25% dégâts de tir et de sorts, vie réduite",
		"max_hp": 80.0,
		"damage_mult": 1.25,
		"default_spell": "shockwave",
	},
	PlayerClass.HEAL: {
		"name": "Soin", "icon": "✚",
		"desc": "Vie et dégâts normaux, sort de soin suggéré",
		"max_hp": 100.0,
		"damage_mult": 1.0,
		"default_spell": "heal",
	},
	PlayerClass.TANK: {
		"name": "Tank", "icon": "🛡",
		"desc": "+60% vie, dégâts réduits",
		"max_hp": 160.0,
		"damage_mult": 0.8,
		"default_spell": "slow",
	},
}
const DEFAULT_CLASS := PlayerClass.DAMAGE


static func all_ids() -> Array:
	return DEFS.keys()
