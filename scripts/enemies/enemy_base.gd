## EnemyBase — base class for all enemies
## Simple geometric shapes, move toward the station, deal contact damage.
extends Node2D

# Override in subclasses
var max_hp: float = 50.0
var speed: float = 60.0
var contact_damage: float = 20.0
var color: Color = Color(1.0, 0.2, 0.2)
var shape_radius: float = 14.0
var reward_energy: float = 5.0

var hp: float = max_hp
var _target: Vector2 = Vector2.ZERO  # station global pos
var _dead := false
var _hit_flash := 0.0  # seconds remaining for red flash

## Network id assigned by the host's WaveManager, used to keep every peer's
## puppet copy of this enemy in sync (position/hp ticks, and removal on death).
var enemy_id: int = -1

## Facing angle (radians) toward the station — applied only to the shape
## drawing, not to the whole node's transform, so the HP bar above it stays
## upright instead of tilting along with the enemy.
var _facing_angle: float = 0.0

# Non-host peers only receive a position update ~10×/second (see
# WaveManager._sync_enemies_rpc); snapping straight to it made movement look
# choppy. Instead we lerp toward the latest known position every frame.
var _net_target_pos: Vector2 = Vector2.ZERO
const NET_INTERP_SPEED := 12.0

# Set by the player "Champ ralentisseur" spell (host-only, since only the
# host moves enemies) — a multiplier on speed for the remaining duration.
var _slow_factor: float = 1.0
var _slow_timer: float = 0.0

signal died(enemy: Node2D, energy_reward: float)


func _ready() -> void:
	hp = max_hp
	_net_target_pos = global_position
	set_process(true)  # host simulates movement; clients interpolate toward network updates


func init(target_pos: Vector2) -> void:
	_target = target_pos


func _process(delta: float) -> void:
	if _dead:
		return

	if NetworkManager.is_host():
		if _slow_timer > 0.0:
			_slow_timer -= delta
			if _slow_timer <= 0.0:
				_slow_factor = 1.0

		# Move toward station
		var dir := (_target - global_position).normalized()
		global_position += dir * speed * _slow_factor * delta

		# Contact damage when close enough
		if global_position.distance_to(_target) < shape_radius + 42.0:
			_on_reach_station()

		# Incidental contact damage to any player standing in the way —
		# enemies still path toward the station, not players, this is just
		# what happens if you don't dodge one on its way through.
		for p in get_tree().get_nodes_in_group("players"):
			if p.has_method("take_contact_damage") and global_position.distance_to(p.global_position) < shape_radius + 14.0:
				p.take_contact_damage(contact_damage * 0.5)
	else:
		global_position = global_position.lerp(_net_target_pos, clampf(delta * NET_INTERP_SPEED, 0.0, 1.0))
		queue_redraw()

	_face_target()

	# Flash timer
	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()


## Actual forward movement direction (unlike _facing_angle, which has an
## extra +90° baked in for the shape-drawing transform) — used by subclasses
## like enemy_shield.gd to tell a frontal hit from a flanking one.
var _move_dir: Vector2 = Vector2.RIGHT

## Rotates the shape to point toward the station — computed the same way on
## every peer (host movement and client interpolation both converge on
## `_target`), so it stays in sync without any extra network traffic.
func _face_target() -> void:
	var dir := _target - global_position
	if dir.length() > 1.0:
		_move_dir = dir.normalized()
		_facing_angle = dir.angle() + PI / 2.0


## Called by WaveManager when a network position/hp update arrives for this
## enemy (client-side only — the host is its own source of truth).
## take_damage() (and its hit-flash/sound) only ever runs where the actual
## collision happens — turrets, mines, bullets, the player ability — all of
## which are host-only logic, so clients never called it and never saw the
## flash. Piggybacking a "did hp drop since last sync?" check on this
## existing ~10Hz update gives clients the same feedback without a new RPC
## per hit.
func set_network_state(pos: Vector2, new_hp: float) -> void:
	_net_target_pos = pos
	if new_hp < hp:
		_hit_flash = 0.12
		AudioManager.play_sfx(AudioManager.SFX.ENEMY_HIT, -8.0)
		queue_redraw()
	hp = new_hp


func _draw() -> void:
	var col := color if _hit_flash <= 0.0 else Color.WHITE
	# Soft glow behind the shape so enemies read clearly against the grid.
	draw_circle(Vector2.ZERO, shape_radius * 1.35, Color(color.r, color.g, color.b, 0.15))

	draw_set_transform(Vector2.ZERO, _facing_angle, Vector2.ONE)
	_draw_shape(col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# HP bar (drawn unrotated so it always reads horizontally)
	var ratio := hp / max_hp
	var bar_w := shape_radius * 2.0
	draw_rect(Rect2(-shape_radius, -shape_radius - 10, bar_w, 4), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(-shape_radius, -shape_radius - 10, bar_w * ratio, 4),
		Color(0.2, 1.0, 0.3) if ratio > 0.5 else Color(1.0, 0.4, 0.1))


## Override to draw the enemy's specific shape
func _draw_shape(col: Color) -> void:
	draw_circle(Vector2.ZERO, shape_radius, col)


## Host-only: applied by the player "Champ ralentisseur" spell.
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = factor
	_slow_timer = duration


## `from_direction` is the direction the damage traveled when it hit (e.g. a
## bullet's velocity direction) — Vector2.ZERO means "no particular
## direction" (area-of-effect sources: mines, EMP, the player's Onde de
## choc), which always gets through since there's no single angle to block.
## Used by enemy_shield.gd to block frontal hits while letting flanking ones
## through; every other enemy type ignores it (see _blocks_damage()).
func take_damage(amount: float, from_direction: Vector2 = Vector2.ZERO) -> void:
	if _dead:
		return
	if _blocks_damage(from_direction):
		_on_damage_blocked()
		return
	hp -= amount
	_hit_flash = 0.12
	queue_redraw()
	AudioManager.play_sfx(AudioManager.SFX.ENEMY_HIT, -8.0)
	if hp <= 0.0:
		_die()


## Override to reject damage arriving from a particular direction (see
## enemy_shield.gd). Base enemies block nothing.
func _blocks_damage(_from_direction: Vector2) -> bool:
	return false


## Override for a distinct "blocked" visual/sound instead of taking the hit.
func _on_damage_blocked() -> void:
	pass


func _on_reach_station() -> void:
	if not NetworkManager.is_host():
		return
	GameState.damage_station(contact_damage)
	AudioManager.play_sfx(AudioManager.SFX.STATION_DAMAGE)
	_die()


## Host-only: marks this enemy as dead and reports it for the reward/wave
## bookkeeping. Actual removal (sound, particles, queue_free) happens
## uniformly on every peer via WaveManager's death broadcast — see
## play_death_effects() — so hosts and clients see the exact same thing.
func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self, reward_energy)


## Called on every peer (via WaveManager's networked removal) right before
## this enemy is freed.
func play_death_effects() -> void:
	AudioManager.play_sfx(AudioManager.SFX.ENEMY_DEATH, -4.0)
	_spawn_death_burst()


## Small one-shot particle burst matching the enemy's color, left behind
## after this node is freed.
func _spawn_death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var particles := CPUParticles2D.new()
	particles.global_position = global_position
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 14
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 120.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = color
	parent.add_child(particles)
	particles.emitting = true
	var t := parent.get_tree().create_timer(particles.lifetime + 0.1)
	t.timeout.connect(particles.queue_free)
