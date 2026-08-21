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

signal died(enemy: Node2D, energy_reward: float)


func _ready() -> void:
	hp = max_hp
	set_process(NetworkManager.is_host())  # only host moves enemies


func init(target_pos: Vector2) -> void:
	_target = target_pos


func _process(delta: float) -> void:
	if _dead:
		return

	# Move toward station
	var dir := (_target - global_position).normalized()
	global_position += dir * speed * delta

	# Contact damage when close enough
	if global_position.distance_to(_target) < shape_radius + 42.0:
		_on_reach_station()

	# Flash timer
	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()


func _draw() -> void:
	var col := color if _hit_flash <= 0.0 else Color.WHITE
	_draw_shape(col)

	# HP bar
	var ratio := hp / max_hp
	var bar_w := shape_radius * 2.0
	draw_rect(Rect2(-shape_radius, -shape_radius - 10, bar_w, 4), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(-shape_radius, -shape_radius - 10, bar_w * ratio, 4),
		Color(0.2, 1.0, 0.3) if ratio > 0.5 else Color(1.0, 0.4, 0.1))


## Override to draw the enemy's specific shape
func _draw_shape(col: Color) -> void:
	draw_circle(Vector2.ZERO, shape_radius, col)


func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	_hit_flash = 0.12
	queue_redraw()
	AudioManager.play_sfx(AudioManager.SFX.ENEMY_HIT, -8.0)
	if hp <= 0.0:
		_die()


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
