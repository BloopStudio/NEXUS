## WaveManager — spawns enemy waves, manages phase timing
## Only the host runs the wave logic; state is shared via GameState.
extends Node2D

const BUILD_TIME     := 20.0   # seconds of calm between waves
const SPAWN_INTERVAL := 0.4    # seconds between individual spawns

const ENEMY_BASIC    := preload("res://scripts/enemies/enemy_basic.gd")
const ENEMY_FAST     := preload("res://scripts/enemies/enemy_fast.gd")
const ENEMY_TANK     := preload("res://scripts/enemies/enemy_tank.gd")
const ENEMY_RANGED   := preload("res://scripts/enemies/enemy_ranged.gd")
const ENEMY_SPLITTER := preload("res://scripts/enemies/enemy_splitter.gd")
const ENEMY_SABOTEUR := preload("res://scripts/enemies/enemy_saboteur.gd")
const ENEMY_SHIELD   := preload("res://scripts/enemies/enemy_shield.gd")
const ENEMY_KAMIKAZE := preload("res://scripts/enemies/enemy_kamikaze.gd")
const ENEMY_ELITE      := preload("res://scripts/enemies/enemy_elite.gd")
const ENEMY_ABERRATION := preload("res://scripts/enemies/enemy_aberration.gd")

var _spawn_queue: Array[String] = []
var _spawn_timer: float = 0.0
var _phase_timer: float = BUILD_TIME
var _build_time_max: float = BUILD_TIME

# The countdown itself only ever runs in the host's _process (clients don't
# run this node's process at all — see _ready), so without broadcasting it
# clients never see a build-phase timer. Throttled well below the
# once-per-frame local emit rate since exact sub-second precision doesn't
# matter for a UI bar.
var _timer_sync_timer: float = 0.0
const TIMER_SYNC_INTERVAL := 0.2

var station_node: Node2D = null

signal wave_started(wave_number: int)
signal wave_cleared()
signal build_phase_tick(seconds_left: float)

var _active_enemies: int = 0

# ─── Enemy networking ───────────────────────────────────────────────────────────
# Every peer (host included) keeps this id -> enemy node map in sync via the
# spawn/remove RPCs below, so the host's simulation is mirrored everywhere.
var _enemy_registry: Dictionary = {}
var _next_enemy_id: int = 0
var _enemy_sync_timer: float = 0.0
const ENEMY_SYNC_INTERVAL := 0.1


func _ready() -> void:
	if not NetworkManager.is_host():
		set_process(false)
		return


func _process(delta: float) -> void:
	match GameState.phase:
		GameState.Phase.BUILD:
			_phase_timer -= delta
			build_phase_tick.emit(_phase_timer)
			_timer_sync_timer -= delta
			if _timer_sync_timer <= 0.0:
				_timer_sync_timer = TIMER_SYNC_INTERVAL
				_build_timer_rpc.rpc(maxf(0.0, _phase_timer), _build_time_max)
			if _phase_timer <= 0.0:
				_start_wave()

		GameState.Phase.WAVE:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0 and _spawn_queue.size() > 0:
				_spawn_timer = SPAWN_INTERVAL
				_spawn_next()
			elif _spawn_queue.is_empty() and _active_enemies == 0:
				_wave_cleared()

		_:
			pass

	_enemy_sync_timer -= delta
	if _enemy_sync_timer <= 0.0:
		_enemy_sync_timer = ENEMY_SYNC_INTERVAL
		_broadcast_enemy_sync()


# ─── Wave logic ────────────────────────────────────────────────────────────────
func _start_wave() -> void:
	GameState.wave_number += 1
	var wave := GameState.wave_number

	# Build spawn queue based on wave number
	_spawn_queue.clear()
	_spawn_queue.append_array(_build_wave_queue(wave))
	_active_enemies = 0

	GameState.set_phase(GameState.Phase.WAVE)
	AudioManager.play_sfx(AudioManager.SFX.WAVE_START)
	wave_started.emit(wave)


func _build_wave_queue(wave: int) -> Array[String]:
	var q: Array[String] = []

	# Basics always
	var basics := 4 + wave * 2
	for _i in basics:
		q.append("basic")

	# Fasts from wave 2
	if wave >= 2:
		var fasts := wave - 1
		for _i in fasts:
			q.append("fast")

	# Tanks from wave 4
	if wave >= 4:
		var tanks := (wave - 3)
		for _i in tanks:
			q.append("tank")

	# Ranged attackers from wave 3
	if wave >= 3:
		var ranged := 1 + (wave - 3) / 2
		for _i in ranged:
			q.append("ranged")

	# Splitters from wave 5
	if wave >= 5:
		var splitters := 1 + (wave - 5) / 3
		for _i in splitters:
			q.append("splitter")

	# Saboteurs from wave 4 — target modules instead of the station core, so
	# they add a different threat pattern (protect the ring, not just the
	# center) rather than more raw pressure.
	if wave >= 4:
		var saboteurs := 1 + (wave - 4) / 4
		for _i in saboteurs:
			q.append("saboteur")

	# Shielded enemies from wave 3 — block frontal damage, forcing players to
	# spread out and flank rather than massing fire on one spot.
	if wave >= 3:
		var shielded := 1 + (wave - 3) / 2
		for _i in shielded:
			q.append("shield")

	# Kamikazes from wave 6 — must be shot down at range before they reach
	# melee, or their detonation punishes standing still near the station.
	if wave >= 6:
		var kamikazes := 1 + (wave - 6) / 3
		for _i in kamikazes:
			q.append("kamikaze")

	# Elites from wave 7 — buff every enemy near them (speed + damage) on a
	# pulsing aura, rewarding focusing them down over spreading damage thin.
	if wave >= 7:
		var elites := 1 + (wave - 7) / 5
		for _i in elites:
			q.append("elite")

	# Aberrations from wave 15 — a second, stranger faction debuts: phases
	# fully invulnerable on a cycle, so sustained fire alone doesn't cut it.
	if wave >= 15:
		var aberrations := 1 + (wave - 15) / 3
		for _i in aberrations:
			q.append("aberration")

	# Shuffle to mix types
	q.shuffle()
	return q


## +9% HP/damage per wave, compounding — wave 10 enemies hit ~2.4x as hard
## and take ~2.4x as long to kill as wave 1's, on top of there being more of
## them. Splitter children inherit their parent's wave via GameState.wave_number
## (waves don't change mid-spawn), so they scale the same way.
func _difficulty_multiplier(wave: int) -> float:
	return pow(1.09, float(wave - 1))


func _spawn_next() -> void:
	if _spawn_queue.is_empty() or station_node == null:
		return

	var type: String = _spawn_queue.pop_front()

	# Spawn at a random point on a circle far outside the arena — scales
	# with GameState.get_arena_radius() so expanding the map keeps enemies
	# spawning a consistent distance beyond the new, larger play area.
	var angle := randf() * TAU
	var spawn_radius := GameState.get_arena_radius() + 60.0
	var spawn_pos := station_node.global_position + Vector2(cos(angle), sin(angle)) * spawn_radius

	var id := _next_enemy_id
	_next_enemy_id += 1
	var targets_outpost := _roll_targets_outpost(type)
	_spawn_enemy_rpc.rpc(id, type, spawn_pos, _compute_target_for(type, targets_outpost), targets_outpost)
	_active_enemies += 1


## The Saboteur ignores this entirely (its own module targeting always
## wins) — for everything else, once the team has built the Outpost, some
## enemies peel off to hit it instead of the main station, rewarding
## players who don't just abandon it once it's up.
const OUTPOST_TARGET_CHANCE := 0.35

func _roll_targets_outpost(type: String) -> bool:
	return type != "saboteur" and GameState.outpost_built and randf() < OUTPOST_TARGET_CHANCE


## Every enemy type targets the station core except the Saboteur, which picks
## a random currently-built module slot instead — computed once, here, on the
## host, and sent through the spawn RPC so every peer's copy agrees on it
## (a client independently rerolling its own random slot would only affect
## cosmetics like facing angle, but there's no reason to let it drift).
func _compute_target_for(type: String, targets_outpost: bool) -> Vector2:
	if station_node == null:
		return Vector2.ZERO
	if type == "saboteur":
		var candidates: Array[int] = []
		for i in GameState.module_slots.size():
			if GameState.module_slots[i]["type"] != GameState.ModuleType.EMPTY:
				candidates.append(i)
		if not candidates.is_empty():
			return station_node.get_slot_world_pos(candidates[randi() % candidates.size()])
		return station_node.global_position
	if targets_outpost:
		return station_node.global_position + GameState.OUTPOST_OFFSET
	return station_node.global_position


## Creates the enemy node on every peer (host included, via call_local) so
## everyone sees the same wave — only the host actually simulates movement
## and combat (gated inside enemy_base.gd), everyone else just displays it.
@rpc("authority", "call_local", "reliable")
func _spawn_enemy_rpc(id: int, type: String, spawn_pos: Vector2, target_pos: Vector2, targets_outpost: bool = false) -> void:
	if station_node == null:
		return
	var enemy: Node2D
	match type:
		"basic":    enemy = ENEMY_BASIC.new()
		"fast":     enemy = ENEMY_FAST.new()
		"tank":     enemy = ENEMY_TANK.new()
		"ranged":   enemy = ENEMY_RANGED.new()
		"splitter": enemy = ENEMY_SPLITTER.new()
		"saboteur": enemy = ENEMY_SABOTEUR.new()
		"shield":   enemy = ENEMY_SHIELD.new()
		"kamikaze": enemy = ENEMY_KAMIKAZE.new()
		"elite":    enemy = ENEMY_ELITE.new()
		"aberration": enemy = ENEMY_ABERRATION.new()
		_:          enemy = ENEMY_BASIC.new()

	enemy.enemy_id = id
	enemy.global_position = spawn_pos
	enemy.init(target_pos)
	enemy.targets_outpost = targets_outpost and type != "saboteur"
	enemy.add_to_group("enemies")
	_enemy_registry[id] = enemy

	if NetworkManager.is_host():
		enemy.died.connect(_on_enemy_died)

	# Each subclass's _ready() (run by add_child, below) sets its base
	# max_hp/contact_damage/speed — scaling has to happen AFTER that or
	# _ready() just overwrites it back to the wave-1 values.
	get_parent().add_child(enemy)

	# Waves used to only get harder by throwing MORE enemies at the station —
	# each individual enemy stayed exactly as strong on wave 20 as on wave 1,
	# so once a station out-built the spawn rate the game stopped escalating.
	# Scale HP/damage per wave (speed too, capped, so it stays dodgeable).
	var difficulty := _difficulty_multiplier(GameState.wave_number) * GameState.get_mutator_wave_hp_multiplier()
	enemy.max_hp *= difficulty
	enemy.hp = enemy.max_hp
	enemy.contact_damage *= difficulty
	enemy.speed *= minf(1.5, 1.0 + float(GameState.wave_number - 1) * 0.025)


## Host-only: periodically pushes position/hp for every alive enemy so
## clients' puppet copies track the host's simulation.
func _broadcast_enemy_sync() -> void:
	if _enemy_registry.is_empty() or multiplayer.multiplayer_peer == null:
		return
	var data: Array = []
	for id in _enemy_registry:
		var e: Node2D = _enemy_registry[id]
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			data.append([id, e.global_position.x, e.global_position.y, e.hp])
	if data.size() > 0:
		_sync_enemies_rpc.rpc(data)


## Drives the HUD's build-phase countdown bar on every peer (host included,
## via call_local, so there's a single code path).
@rpc("authority", "call_local", "unreliable")
func _build_timer_rpc(seconds_left: float, max_time: float) -> void:
	var game := get_parent()
	if game != null and game.has_node("HUD"):
		game.get_node("HUD").update_build_timer(seconds_left, max_time)


@rpc("authority", "unreliable")
func _sync_enemies_rpc(data: Array) -> void:
	for entry in data:
		var id: int = entry[0]
		if not _enemy_registry.has(id):
			continue
		var e: Node2D = _enemy_registry[id]
		if is_instance_valid(e):
			e.set_network_state(Vector2(entry[1], entry[2]), entry[3])


## Broadcast to every peer that this enemy died — this is what actually
## plays the death sound/particles and frees the node, uniformly everywhere.
@rpc("authority", "call_local", "reliable")
func _remove_enemy_rpc(id: int) -> void:
	if not _enemy_registry.has(id):
		return
	var enemy: Node2D = _enemy_registry[id]
	_enemy_registry.erase(id)
	if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
		enemy.play_death_effects()
		enemy.queue_free()


func _wave_cleared() -> void:
	AudioManager.play_sfx(AudioManager.SFX.WAVE_CLEARED)
	wave_cleared.emit()

	# Heal via repair modules
	_apply_repair_regen()

	# Transition to upgrade phase briefly then build
	GameState.set_phase(GameState.Phase.UPGRADE)
	await get_tree().create_timer(0.5).timeout
	GameState.set_phase(GameState.Phase.BUILD)
	_phase_timer = maxf(8.0, BUILD_TIME - GameState.wave_number * 0.5)
	_build_time_max = _phase_timer


func _apply_repair_regen() -> void:
	for slot in GameState.module_slots:
		if slot["type"] == GameState.ModuleType.REPAIR and not slot.get("disabled", false):
			var regen: float = (20.0 + float(slot["level"]) * 15.0) * GameState.get_skill_repair_multiplier()
			GameState.heal_station(regen)


func _on_enemy_died(enemy: Node2D, energy: float) -> void:
	GameState.add_energy(energy)
	_remove_enemy_rpc.rpc(enemy.enemy_id)
	# This death always removes exactly one active enemy from the count,
	# whether or not it spawns replacements below — forgetting this decrement
	# for splitters used to leak the counter upward by one per split, which
	# eventually left it stuck above zero forever (empty spawn queue + dead
	# screen, but the WAVE→BUILD transition never fires since it waits for
	# _active_enemies == 0).
	_active_enemies = maxi(0, _active_enemies - 1)

	# Some enemies (Splitter) spawn replacements on death instead of just
	# disappearing — read this before the node is queued for removal above.
	if enemy.has_method("get_split_type"):
		var split_type: String = enemy.get_split_type()
		if not split_type.is_empty():
			_spawn_split_children(split_type, enemy.get_split_count(), enemy.global_position)


## Splits spawn immediately at the death position (scattered a little so
## they don't perfectly overlap) rather than going through the normal
## spawn-queue/timer — they're a consequence of this death, not a new wave.
func _spawn_split_children(type: String, count: int, at_pos: Vector2) -> void:
	for i in count:
		var offset := Vector2(cos(TAU * i / count), sin(TAU * i / count)) * 24.0
		var id := _next_enemy_id
		_next_enemy_id += 1
		var targets_outpost := _roll_targets_outpost(type)
		_spawn_enemy_rpc.rpc(id, type, at_pos + offset, _compute_target_for(type, targets_outpost), targets_outpost)
		_active_enemies += 1
