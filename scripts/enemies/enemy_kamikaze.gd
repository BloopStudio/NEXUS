## EnemyKamikaze — rushes the station fast and detonates on arrival instead
## of chipping away with the usual per-frame contact damage: one big burst to
## the station plus an area hit to any nearby players, then it's gone. Low
## HP and high speed means the only real counter is shooting it down before
## it reaches melee range — trading contact damage back is a losing move.
extends "res://scripts/enemies/enemy_base.gd"

const EXPLOSION_RADIUS := 70.0
const EXPLOSION_PLAYER_DAMAGE := 30.0


func _ready() -> void:
	max_hp = 25.0
	speed = 100.0
	contact_damage = 45.0
	color = Color(1.0, 0.45, 0.05)  # orange
	shape_radius = 12.0
	reward_energy = 6.0
	super()


func _on_reach_station() -> void:
	if not NetworkManager.is_host():
		return
	GameState.damage_station(contact_damage)
	AudioManager.play_sfx(AudioManager.SFX.STATION_DAMAGE)
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("take_contact_damage") and global_position.distance_to(p.global_position) < EXPLOSION_RADIUS:
			p.take_contact_damage(EXPLOSION_PLAYER_DAMAGE)
	_die()


## Bigger, faster burst than the base class's — reads as an explosion rather
## than a regular death poof. Runs uniformly on every peer via WaveManager's
## networked removal (play_death_effects), same as any other enemy death.
func _spawn_death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var particles := CPUParticles2D.new()
	particles.global_position = global_position
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 28
	particles.lifetime = 0.55
	particles.explosiveness = 1.0
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 220.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.0
	particles.color = color
	parent.add_child(particles)
	particles.emitting = true
	var t := parent.get_tree().create_timer(particles.lifetime + 0.1)
	t.timeout.connect(particles.queue_free)


func _draw_shape(col: Color) -> void:
	# Spiky circle — reads as "about to go off".
	var pts := PackedVector2Array()
	var spikes := 8
	for i in spikes * 2:
		var r: float = shape_radius if i % 2 == 0 else shape_radius * 0.55
		var a := TAU * i / (spikes * 2)
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_polygon(pts, [col])
