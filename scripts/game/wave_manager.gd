## WaveManager — spawns enemy waves, manages phase timing
## Only the host runs the wave logic; state is shared via GameState.
extends Node2D

const BUILD_TIME     := 20.0   # seconds of calm between waves
const SPAWN_INTERVAL := 0.4    # seconds between individual spawns

const ENEMY_BASIC  := preload("res://scripts/enemies/enemy_basic.gd")
const ENEMY_FAST   := preload("res://scripts/enemies/enemy_fast.gd")
const ENEMY_TANK   := preload("res://scripts/enemies/enemy_tank.gd")
const ENEMY_RANGED := preload("res://scripts/enemies/enemy_ranged.gd")

var _spawn_queue: Array[String] = []
var _spawn_timer: float = 0.0
var _phase_timer: float = BUILD_TIME

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

	# Shuffle to mix types
	q.shuffle()
	return q


func _spawn_next() -> void:
	if _spawn_queue.is_empty() or station_node == null:
		return

	var type: String = _spawn_queue.pop_front()

	# Spawn at a random point on a circle far outside the arena
	var angle := randf() * TAU
	var spawn_radius := 480.0
	var spawn_pos := station_node.global_position + Vector2(cos(angle), sin(angle)) * spawn_radius

	var id := _next_enemy_id
	_next_enemy_id += 1
	_spawn_enemy_rpc.rpc(id, type, spawn_pos)
	_active_enemies += 1


## Creates the enemy node on every peer (host included, via call_local) so
## everyone sees the same wave — only the host actually simulates movement
## and combat (gated inside enemy_base.gd), everyone else just displays it.
@rpc("authority", "call_local", "reliable")
func _spawn_enemy_rpc(id: int, type: String, spawn_pos: Vector2) -> void:
	if station_node == null:
		return
	var enemy: Node2D
	match type:
		"basic":  enemy = ENEMY_BASIC.new()
		"fast":   enemy = ENEMY_FAST.new()
		"tank":   enemy = ENEMY_TANK.new()
		"ranged": enemy = ENEMY_RANGED.new()
		_:        enemy = ENEMY_BASIC.new()

	enemy.enemy_id = id
	enemy.global_position = spawn_pos
	enemy.init(station_node.global_position)
	_enemy_registry[id] = enemy

	if NetworkManager.is_host():
		enemy.died.connect(_on_enemy_died)

	get_parent().add_child(enemy)


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

	# Heal shield modules
	_apply_shield_regen()

	# Transition to upgrade phase briefly then build
	GameState.set_phase(GameState.Phase.UPGRADE)
	await get_tree().create_timer(0.5).timeout
	GameState.set_phase(GameState.Phase.BUILD)
	_phase_timer = maxf(8.0, BUILD_TIME - GameState.wave_number * 0.5)


func _apply_shield_regen() -> void:
	for slot in GameState.module_slots:
		if slot["type"] == GameState.ModuleType.SHIELD:
			var regen: float = 20.0 + float(slot["level"]) * 15.0
			GameState.heal_station(regen)


func _on_enemy_died(enemy: Node2D, energy: float) -> void:
	_active_enemies = maxi(0, _active_enemies - 1)
	GameState.add_energy(energy)
	_remove_enemy_rpc.rpc(enemy.enemy_id)
