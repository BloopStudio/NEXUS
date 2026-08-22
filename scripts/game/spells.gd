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

## Cost (team energy) to reach the next level from the current one — index 1
## is the cost from level 1→2, index 2 is level 2→3. Index 0 is unused
## (level 1 is free, it's just the base spell). Max level is 3.
const LEVEL_UP_COST := [0.0, 70.0, 140.0]
const MAX_LEVEL := 3


static func all_ids() -> Array:
	return DEFS.keys()


## Returns a copy of a spell's definition with its numbers scaled for
## `level` (1-3): cooldown drops, magnitude (damage/amount/radius/duration)
## grows — so leveling a spell is a real, felt upgrade without needing a
## whole new spell definition per level.
static func get_scaled_def(spell_id: String, level: int) -> Dictionary:
	var def: Dictionary = DEFS[spell_id].duplicate()
	var lvl := clampi(level, 1, MAX_LEVEL)
	var growth := 1.0 + 0.25 * (lvl - 1)
	var cd_mult := 1.0 - 0.15 * (lvl - 1)

	def["cooldown"] = def["cooldown"] * cd_mult
	if def.has("damage"):
		def["damage"] *= growth
	if def.has("amount"):
		def["amount"] *= growth
	if def.has("radius"):
		def["radius"] *= 1.0 + 0.1 * (lvl - 1)
	if def.has("duration"):
		def["duration"] *= 1.0 + 0.2 * (lvl - 1)
	if def.has("slow_factor"):
		def["slow_factor"] = maxf(0.15, def["slow_factor"] - 0.08 * (lvl - 1))
	if def.has("speed_mult"):
		def["speed_mult"] += 0.3 * (lvl - 1)
	return def
