## Spells — static definitions for player-castable abilities.
## Players pick two of these before a match and bind them to the two ability
## keys (E / A by default, both rebindable) — see main_menu.gd's loadout
## picker and player.gd's cast logic. Purely data: each id names its own
## `kind`, matched in Player._apply_spell_effect() to decide what it does.
class_name Spells

const SHOCKWAVE := "shockwave"
const HEAL       := "heal"
const SLOW       := "slow"
const DASH       := "dash"

const DEFS := {
	SHOCKWAVE: {
		"name": "Onde de choc",
		"desc": "Explosion autour de vous, dégâts en zone",
		"icon": "💥",
		"cooldown": 6.0,
		"color": Color(0.0, 0.831, 1.0),
		"radius": 90.0,
		"damage": 30.0,
	},
	HEAL: {
		"name": "Soin d'urgence",
		"desc": "Restaure instantanément la vie de la station",
		"icon": "✚",
		"cooldown": 12.0,
		"color": Color(0.2, 1.0, 0.4),
		"amount": 80.0,
	},
	SLOW: {
		"name": "Champ ralentisseur",
		"desc": "Ralentit les ennemis proches quelques secondes",
		"icon": "❄",
		"cooldown": 9.0,
		"color": Color(0.3, 0.6, 1.0),
		"radius": 110.0,
		"slow_factor": 0.4,
		"duration": 3.0,
	},
	DASH: {
		"name": "Ruée",
		"desc": "Vitesse de déplacement fortement augmentée",
		"icon": "🚀",
		"cooldown": 5.0,
		"color": Color(1.0, 0.8, 0.1),
		"speed_mult": 2.2,
		"duration": 1.2,
	},
}

const DEFAULT_LOADOUT := [SHOCKWAVE, HEAL]


static func all_ids() -> Array:
	return DEFS.keys()
