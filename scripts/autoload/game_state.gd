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
signal skill_tree_changed()
signal arena_expanded()
signal outpost_changed()

# ─── Enums ─────────────────────────────────────────────────────────────────────
enum Phase { MENU, BUILD, WAVE, UPGRADE, GAME_OVER }

# ─── Module types ──────────────────────────────────────────────────────────────
# New types are always appended last so existing type values (used over the
# network) stay stable. EMERGENCY_SHIELD/EMP are single-charge: triggered by
# clicking their built slot during a WAVE (not built passively like the
# others), consumed on use — see station.gd's charge-module handling.
enum ModuleType { EMPTY, GENERATOR, TURRET, SHIELD, REPAIR, BOOSTER, MINE, EMERGENCY_SHIELD, EMP }

# ─── Costs (energy) ────────────────────────────────────────────────────────────
const MODULE_COSTS := {
	ModuleType.GENERATOR: 30,
	ModuleType.TURRET:    40,
	ModuleType.SHIELD:    50,
	ModuleType.REPAIR:    35,
	ModuleType.BOOSTER:   45,
	ModuleType.MINE:      55,
	ModuleType.EMERGENCY_SHIELD: 70,
	ModuleType.EMP:              90,
}
const EMERGENCY_SHIELD_HEAL_RATIO := 0.3
const EMERGENCY_SHIELD_INVULN_SECONDS := 3.0
const EMP_DAMAGE := 80.0
const EMP_STUN_SECONDS := 2.5
const BOOSTER_DAMAGE_BONUS_PER_LEVEL := 0.15  # +15% player bullet damage per level, per module
const SHIELD_MAX_HP_BONUS_PER_LEVEL := 60.0   # +60 max station HP per level, per module
const UPGRADE_COST_MULTIPLIER := 1.8  # cost *= multiplier per level

# ─── Skill tree ────────────────────────────────────────────────────────────────
# A real branching tree (replacing the old single repeatable "unlock slot"
# button): 3 branches, 3 sequential tiers each — a tier must be bought in
# order within its branch, but branches are independent of each other.
# Costs are shared team energy, same as everything else.
enum SkillBranch { DAMAGE, ECONOMY, DEFENSE }
const SKILL_TREE := {
	SkillBranch.DAMAGE: [
		{"name": "Armement I",   "desc": "+10% dégâts (joueurs, tourelles, mines)", "cost": 90.0},
		{"name": "Armement II",  "desc": "+10% dégâts supplémentaires (total +20%)", "cost": 200.0},
		{"name": "Armement III", "desc": "+10% dégâts supplémentaires (total +30%)", "cost": 360.0},
	],
	SkillBranch.ECONOMY: [
		{"name": "Commerce I",   "desc": "+10% énergie passive (générateurs)", "cost": 90.0},
		{"name": "Commerce II",  "desc": "-10% coût de construction des modules", "cost": 200.0},
		{"name": "Commerce III", "desc": "+15% remboursement à la destruction", "cost": 360.0},
	],
	SkillBranch.DEFENSE: [
		{"name": "Fortification I",   "desc": "+15% vie max de la station", "cost": 90.0},
		{"name": "Fortification II",  "desc": "+20% soin des modules Réparation", "cost": 200.0},
		{"name": "Fortification III", "desc": "+15% vie max supplémentaire (total +30%)", "cost": 360.0},
	],
}
const SKILL_BRANCH_NAMES := {
	SkillBranch.DAMAGE: "⚔ Dégâts", SkillBranch.ECONOMY: "⚡ Économie", SkillBranch.DEFENSE: "🛡 Défense",
}

# ─── State ─────────────────────────────────────────────────────────────────────
var phase: Phase = Phase.MENU

## Host-chosen station-wide modifier for the current match (see mutators.gd) —
## set once by reset() and left alone for the whole run, same "seed" spirit
## as a roguelite run modifier.
var active_mutator: int = Mutators.Mutator.NONE

func get_mutator_damage_multiplier() -> float:
	return Mutators.DEFS[active_mutator].get("damage_mult", 1.0)

func get_mutator_station_hp_multiplier() -> float:
	return Mutators.DEFS[active_mutator].get("station_hp_mult", 1.0)

func get_mutator_energy_multiplier() -> float:
	return Mutators.DEFS[active_mutator].get("energy_mult", 1.0)

func get_mutator_cost_multiplier() -> float:
	return Mutators.DEFS[active_mutator].get("cost_mult", 1.0)

func get_mutator_wave_hp_multiplier() -> float:
	return Mutators.DEFS[active_mutator].get("wave_hp_mult", 1.0)

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
# 8 slots arranged in a ring around the station by default — the skill tree
# (see unlock_slot() below) can grow this up to MAX_SLOTS during a match.
var module_slots: Array[Dictionary] = []
const STARTING_SLOTS := 8
const MAX_SLOTS := 12
const SLOT_UNLOCK_COSTS := [150.0, 220.0, 300.0, 400.0]  # cost of the 9th..12th slot

# Host-only countdown, one entry per module_slots index, kept OUT of the
# synced slot dicts on purpose — it changes every frame and syncing it would
# spam module_slots_changed (the exact "menu rebuilt every tick" bug class
# fixed earlier). Only the boolean "disabled" flag on the slot dict itself
# is synced, and that only flips twice per disable (on/off).
var _module_disable_timers: Array[float] = []

# branch (int) -> tiers unlocked so far (0..3)
var skill_tiers: Dictionary = {
	SkillBranch.DAMAGE: 0, SkillBranch.ECONOMY: 0, SkillBranch.DEFENSE: 0,
}

# ─── End-of-match stats ─────────────────────────────────────────────────────────
# Tracked for the post-game stats screen (see game.gd). Damage is recorded by
# every peer's own local combat code as it happens (turrets/mines/bullets are
# each simulated once, host-only — see station.gd/player.gd) and only the
# host's copy matters, since it's what gets shown and saved to the scoreboard.
var total_damage_dealt: float = 0.0
var _match_start_msec: int = 0

func record_damage(amount: float) -> void:
	total_damage_dealt += amount


func get_survival_seconds() -> float:
	if _match_start_msec == 0:
		return 0.0
	return (Time.get_ticks_msec() - _match_start_msec) / 1000.0

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
	if station_invuln_timer > 0.0:
		station_invuln_timer -= delta
	_tick_module_disable_timers(delta)
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	# Bundled as a dict (rather than more positional params) so adding a new
	# synced field later doesn't risk a mismatched-argument-order mistake.
	var extra := {
		"arena_tier": arena_tier,
		"outpost_built": outpost_built,
		"outpost_hp": outpost_hp,
		"outpost_max_hp": outpost_max_hp,
	}
	_apply_snapshot_rpc.rpc(energy, wave_number, station_hp, station_max_hp, int(phase), module_slots,
		skill_tiers, total_damage_dealt, extra)


@rpc("authority", "reliable")
func _apply_snapshot_rpc(e: float, w: int, hp: float, max_hp: float, ph: int, slots: Array,
		tiers: Dictionary, dmg_dealt: float, extra: Dictionary) -> void:
	station_max_hp = max_hp
	wave_number = w
	energy = e
	station_hp = hp
	total_damage_dealt = dmg_dealt
	if tiers != skill_tiers:
		skill_tiers = tiers
		skill_tree_changed.emit()

	var new_arena_tier: int = extra.get("arena_tier", 0)
	if new_arena_tier != arena_tier:
		arena_tier = new_arena_tier
		arena_expanded.emit()

	var new_outpost_built: bool = extra.get("outpost_built", false)
	var new_outpost_hp: float = extra.get("outpost_hp", 0.0)
	outpost_max_hp = extra.get("outpost_max_hp", OUTPOST_MAX_HP)
	if new_outpost_built != outpost_built or new_outpost_hp != outpost_hp:
		outpost_built = new_outpost_built
		outpost_hp = new_outpost_hp
		outpost_changed.emit()

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
		if sa.get("type") != sb.get("type") or sa.get("level") != sb.get("level") \
				or sa.get("disabled", false) != sb.get("disabled", false):
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
	_module_disable_timers.clear()
	for i in STARTING_SLOTS:
		module_slots.append({"type": ModuleType.EMPTY, "level": 0})
		_module_disable_timers.append(0.0)


# ─── Module placement synergies ─────────────────────────────────────────────
# Slots sit in a ring (see station.gd's _slot_pos) — "adjacent" means the
# immediate left/right neighbor in that ring, wrapping around. Rewards
# actually thinking about where you build, not just how much you build.
## Counts how many of `slot_index`'s two ring-neighbors are built as `type`
## (0, 1, or 2).
func count_adjacent_type(slot_index: int, type: ModuleType) -> int:
	var n := module_slots.size()
	if n == 0:
		return 0
	var count := 0
	for offset in [-1, 1]:
		var neighbor_index: int = ((slot_index + offset) % n + n) % n
		if module_slots[neighbor_index]["type"] == type:
			count += 1
	return count


## Disables a built module for `duration` seconds — its passive/active
## effect stops applying (checked at each call site: idle generation, turret
## fire, mine pulse, booster/shield/repair bonuses, charge-module trigger)
## without touching its type/level, so it resumes exactly as it was once the
## timer runs out. Used by the Saboteur enemy (see enemy_saboteur.gd).
func disable_module(slot_index: int, duration: float) -> void:
	if slot_index < 0 or slot_index >= module_slots.size():
		return
	if module_slots[slot_index]["type"] == ModuleType.EMPTY:
		return
	module_slots[slot_index]["disabled"] = true
	_module_disable_timers[slot_index] = duration
	module_slots_changed.emit(slot_index)


func is_module_disabled(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= module_slots.size():
		return false
	return module_slots[slot_index].get("disabled", false)


func _tick_module_disable_timers(delta: float) -> void:
	for i in _module_disable_timers.size():
		if _module_disable_timers[i] <= 0.0:
			continue
		_module_disable_timers[i] -= delta
		if _module_disable_timers[i] <= 0.0 and module_slots[i].get("disabled", false):
			module_slots[i]["disabled"] = false
			module_slots_changed.emit(i)


## Human-readable "+X% (synergie ...)" suffix describing the placement
## bonus a built module at `slot_index` currently gets from its ring
## neighbors, or "" if its type doesn't have one or no neighbor qualifies.
## Shared by station.gd's hover tooltip and upgrade_menu.gd's build/upgrade
## panel, so both always read the exact same numbers.
func get_synergy_note(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= module_slots.size():
		return ""
	return get_synergy_note_for_type(slot_index, module_slots[slot_index]["type"])


## Same as get_synergy_note(), but for a hypothetical `mtype` at `slot_index`
## instead of whatever's actually built there — used to preview the bonus a
## module WOULD get before you spend energy building it (the ring-neighbor
## check only looks at the neighbors' types, so it works on an empty slot
## exactly the same way).
func get_synergy_note_for_type(slot_index: int, mtype: int) -> String:
	if slot_index < 0 or slot_index >= module_slots.size():
		return ""
	match mtype:
		ModuleType.TURRET:
			var adj := count_adjacent_type(slot_index, ModuleType.TURRET)
			if adj > 0:
				return " · +%d%% cadence (synergie tourelle voisine)" % int(15 * adj)
		ModuleType.MINE:
			var adj := count_adjacent_type(slot_index, ModuleType.BOOSTER)
			if adj > 0:
				return " · +%d%% dégâts (synergie amplificateur voisin)" % int(25 * adj)
		ModuleType.GENERATOR:
			var adj := count_adjacent_type(slot_index, ModuleType.GENERATOR)
			if adj > 0:
				return " · +%d%% production (synergie générateur voisin)" % int(10 * adj)
	return ""


## Cost of the next slot the skill tree would unlock, or -1.0 if already at
## MAX_SLOTS.
func get_next_slot_unlock_cost() -> float:
	var next_index := module_slots.size() - STARTING_SLOTS
	if next_index < 0 or next_index >= SLOT_UNLOCK_COSTS.size():
		return -1.0
	return SLOT_UNLOCK_COSTS[next_index]


## Adds one more (empty) module slot to the station ring, if affordable and
## not already at MAX_SLOTS. This is the whole "skill tree" for now: a
## single repeatable node, each pick pricier than the last.
func unlock_slot() -> bool:
	var cost := get_next_slot_unlock_cost()
	if cost < 0.0 or not spend_energy(cost):
		return false
	module_slots.append({"type": ModuleType.EMPTY, "level": 0})
	_module_disable_timers.append(0.0)
	module_slots_changed.emit(-1)
	return true


func request_unlock_slot() -> void:
	if NetworkManager.is_host():
		unlock_slot()
	else:
		_request_unlock_slot_rpc.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_unlock_slot_rpc() -> void:
	if not multiplayer.is_server():
		return
	unlock_slot()


# ─── Skill tree ────────────────────────────────────────────────────────────────

func get_skill_tier(branch: SkillBranch) -> int:
	return skill_tiers.get(branch, 0)


## Cost of the next tier in `branch`, or -1.0 if that branch is fully unlocked.
func get_next_skill_cost(branch: SkillBranch) -> float:
	var tier: int = get_skill_tier(branch)
	var tiers: Array = SKILL_TREE[branch]
	if tier >= tiers.size():
		return -1.0
	return tiers[tier]["cost"]


func unlock_skill(branch: SkillBranch) -> bool:
	if not SKILL_TREE.has(branch):
		return false
	var cost := get_next_skill_cost(branch)
	if cost < 0.0 or not spend_energy(cost):
		return false
	skill_tiers[branch] = get_skill_tier(branch) + 1
	_recompute_station_max_hp()
	skill_tree_changed.emit()
	return true


func request_unlock_skill(branch: SkillBranch) -> void:
	if NetworkManager.is_host():
		unlock_skill(branch)
	else:
		_request_unlock_skill_rpc.rpc_id(1, int(branch))


@rpc("any_peer", "reliable")
func _request_unlock_skill_rpc(branch: int) -> void:
	if not multiplayer.is_server():
		return
	unlock_skill(branch as SkillBranch)


## +10% per DAMAGE tier, applied on top of BOOSTER modules — used for player
## bullets/abilities, turret shots, and mine pulses alike.
func get_skill_damage_multiplier() -> float:
	return 1.0 + 0.10 * get_skill_tier(SkillBranch.DAMAGE)


## +10% per ECONOMY tier-1-unlocked, applied to idle GENERATOR output.
func get_skill_idle_multiplier() -> float:
	return 1.0 + 0.10 * get_skill_tier(SkillBranch.ECONOMY)


## -10% per ECONOMY tier-2-unlocked, applied to module build/upgrade costs.
func get_skill_cost_multiplier() -> float:
	return 1.0 - (0.10 if get_skill_tier(SkillBranch.ECONOMY) >= 2 else 0.0)


## +15% destroy refund once ECONOMY tier 3 is unlocked (additive to the base ratio).
func get_skill_refund_bonus() -> float:
	return 0.15 if get_skill_tier(SkillBranch.ECONOMY) >= 3 else 0.0


## +15%/+15% station max HP per DEFENSE tier 1/3 (tier 2 is the Repair buff below).
func get_skill_max_hp_multiplier() -> float:
	var tier: int = get_skill_tier(SkillBranch.DEFENSE)
	var mult := 1.0
	if tier >= 1:
		mult += 0.15
	if tier >= 3:
		mult += 0.15
	return mult


## +20% REPAIR module healing once DEFENSE tier 2 is unlocked.
func get_skill_repair_multiplier() -> float:
	return 1.2 if get_skill_tier(SkillBranch.DEFENSE) >= 2 else 1.0


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
	return MODULE_COSTS.get(type, 999.0) * get_skill_cost_multiplier() * get_mutator_cost_multiplier()


func get_module_upgrade_cost(slot_index: int) -> float:
	var slot := module_slots[slot_index]
	if slot["type"] == ModuleType.EMPTY:
		return 0.0
	var base: float = MODULE_COSTS.get(slot["type"], 0.0)
	return base * pow(UPGRADE_COST_MULTIPLIER, slot["level"]) * get_skill_cost_multiplier() * get_mutator_cost_multiplier()


func build_module(slot_index: int, type: ModuleType) -> bool:
	if slot_index < 0 or slot_index >= module_slots.size():
		return false
	if not MODULE_COSTS.has(type):
		return false
	var cost := get_module_build_cost(type)
	if not spend_energy(cost):
		return false
	module_slots[slot_index] = {"type": type, "level": 1}
	_module_disable_timers[slot_index] = 0.0
	_recompute_station_max_hp()
	module_slots_changed.emit(slot_index)
	return true


func upgrade_module(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= module_slots.size():
		return false
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


const DESTROY_REFUND_RATIO := 0.3

## Total energy spent building + upgrading a module up to `level` — used to
## compute the destroy refund.
func get_module_total_invested(type: ModuleType, level: int) -> float:
	var base: float = MODULE_COSTS.get(type, 0.0)
	var total := base  # cost to build at level 1
	for l in range(1, level):
		total += base * pow(UPGRADE_COST_MULTIPLIER, l)
	return total


## Clears a built module back to EMPTY, refunding DESTROY_REFUND_RATIO of
## everything spent building + upgrading it.
func destroy_module(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= module_slots.size():
		return false
	var slot: Dictionary = module_slots[slot_index]
	if slot["type"] == ModuleType.EMPTY:
		return false
	var invested := get_module_total_invested(slot["type"], slot["level"])
	module_slots[slot_index] = {"type": ModuleType.EMPTY, "level": 0}
	_module_disable_timers[slot_index] = 0.0
	add_energy(invested * (DESTROY_REFUND_RATIO + get_skill_refund_bonus()))
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


## SHIELD modules raise the station's max HP (the extra capacity becomes
## available headroom — building one doesn't instantly heal the station).
func _recompute_station_max_hp() -> void:
	var bonus := 0.0
	for slot in module_slots:
		if slot["type"] == ModuleType.SHIELD and not slot.get("disabled", false):
			bonus += SHIELD_MAX_HP_BONUS_PER_LEVEL * slot["level"]
	var new_max := (500.0 + bonus) * get_skill_max_hp_multiplier() * get_mutator_station_hp_multiplier()
	if new_max != station_max_hp:
		station_max_hp = new_max
		station_hp = station_hp  # re-run the setter so it re-clamps against the new max


## Sums the damage bonus from every built BOOSTER module (players hit harder
## the more of these the team builds and upgrades).
func get_player_damage_multiplier() -> float:
	var mult := 1.0
	for slot in module_slots:
		if slot["type"] == ModuleType.BOOSTER and not slot.get("disabled", false):
			mult += BOOSTER_DAMAGE_BONUS_PER_LEVEL * slot["level"]
	return mult * get_skill_damage_multiplier() * get_mutator_damage_multiplier()


# ─── Station ───────────────────────────────────────────────────────────────────
## Set by an Emergency Shield charge — the station ignores damage entirely
## while this is > 0 (see damage_station below).
var station_invuln_timer: float = 0.0

func heal_station(amount: float) -> void:
	station_hp += amount


func damage_station(amount: float) -> void:
	if station_invuln_timer > 0.0:
		return
	station_hp -= amount


# ─── Arena expansion ("carte qui s'agrandit par morceaux") ─────────────────
# The playable radius (player movement bounds, enemy spawn ring) starts at
# ARENA_BASE_RADIUS and grows in discrete steps the team pays for, same
# rhythm as unlocking a station slot — not a full map/tile rework, just the
# existing circular arena widening piece by piece.
const ARENA_BASE_RADIUS := 420.0
const ARENA_GROWTH_PER_TIER := 70.0
const MAX_ARENA_TIER := 3
const ARENA_EXPAND_COSTS := [220.0, 380.0, 600.0]

var arena_tier: int = 0

func get_arena_radius() -> float:
	return ARENA_BASE_RADIUS + float(arena_tier) * ARENA_GROWTH_PER_TIER


## Cost of the next arena expansion, or -1.0 if already at MAX_ARENA_TIER.
func get_next_arena_expand_cost() -> float:
	if arena_tier >= MAX_ARENA_TIER:
		return -1.0
	return ARENA_EXPAND_COSTS[arena_tier]


func expand_arena() -> bool:
	var cost := get_next_arena_expand_cost()
	if cost < 0.0 or not spend_energy(cost):
		return false
	arena_tier += 1
	arena_expanded.emit()
	return true


func request_expand_arena() -> void:
	if NetworkManager.is_host():
		expand_arena()
	else:
		_request_expand_arena_rpc.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_expand_arena_rpc() -> void:
	if not multiplayer.is_server():
		return
	expand_arena()


# ─── Outpost ("stations multiples") ─────────────────────────────────────────
# A second, lighter defensible point the team can build once the arena has
# been expanded at least once (there needs to be room for it) — its own HP
# bar, but losing it doesn't end the match like losing the main station
# does. Some enemies target it instead of the main station (see
# wave_manager.gd's _compute_target_for), rewarding players who don't
# abandon it once it's up.
const OUTPOST_MAX_HP := 220.0
const OUTPOST_BUILD_COST := 260.0
const OUTPOST_MIN_ARENA_TIER := 1
## Fixed offset from the main station — simple and predictable rather than
## player-chosen placement, which would need its own UI/networking.
const OUTPOST_OFFSET := Vector2(0.0, -260.0)

var outpost_built: bool = false
var outpost_hp: float = 0.0
var outpost_max_hp: float = OUTPOST_MAX_HP


func can_build_outpost() -> bool:
	return not outpost_built and arena_tier >= OUTPOST_MIN_ARENA_TIER


func build_outpost() -> bool:
	if not can_build_outpost() or not spend_energy(OUTPOST_BUILD_COST):
		return false
	outpost_built = true
	outpost_max_hp = OUTPOST_MAX_HP
	outpost_hp = OUTPOST_MAX_HP
	outpost_changed.emit()
	return true


func request_build_outpost() -> void:
	if NetworkManager.is_host():
		build_outpost()
	else:
		_request_build_outpost_rpc.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_build_outpost_rpc() -> void:
	if not multiplayer.is_server():
		return
	build_outpost()


func damage_outpost(amount: float) -> void:
	if not outpost_built:
		return
	outpost_hp = maxf(0.0, outpost_hp - amount)
	if outpost_hp <= 0.0:
		outpost_built = false
	outpost_changed.emit()


func heal_outpost(amount: float) -> void:
	if not outpost_built:
		return
	outpost_hp = minf(outpost_max_hp, outpost_hp + amount)
	outpost_changed.emit()


## Clears a built EMERGENCY_SHIELD/EMP slot back to EMPTY and returns which
## type it was (EMPTY if the slot wasn't actually a charge module) — the
## caller (station.gd, which has scene access to apply the actual effect on
## enemies/station) checks the return value to know what to do next. This
## intentionally does NOT refund any energy — it's a one-time use, not a
## destroy.
func consume_charge_module(slot_index: int) -> ModuleType:
	if slot_index < 0 or slot_index >= module_slots.size():
		return ModuleType.EMPTY
	var slot: Dictionary = module_slots[slot_index]
	var mtype: ModuleType = slot["type"]
	if mtype != ModuleType.EMERGENCY_SHIELD and mtype != ModuleType.EMP:
		return ModuleType.EMPTY
	module_slots[slot_index] = {"type": ModuleType.EMPTY, "level": 0}
	_module_disable_timers[slot_index] = 0.0
	module_slots_changed.emit(slot_index)
	return mtype


# ─── Full reset ────────────────────────────────────────────────────────────────
func reset(mutator: int = Mutators.Mutator.NONE) -> void:
	active_mutator = mutator
	energy = 50.0
	wave_number = 0
	station_max_hp = 500.0 * get_mutator_station_hp_multiplier()
	station_hp = station_max_hp
	skill_tiers = {SkillBranch.DAMAGE: 0, SkillBranch.ECONOMY: 0, SkillBranch.DEFENSE: 0}
	total_damage_dealt = 0.0
	station_invuln_timer = 0.0
	arena_tier = 0
	outpost_built = false
	outpost_hp = 0.0
	outpost_max_hp = OUTPOST_MAX_HP
	_match_start_msec = Time.get_ticks_msec()
	_init_slots()
	set_phase(Phase.BUILD)


# ─── Internal ──────────────────────────────────────────────────────────────────
func _trigger_game_over() -> void:
	set_phase(Phase.GAME_OVER)
	game_over.emit()
