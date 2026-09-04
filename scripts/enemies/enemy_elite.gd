## EnemyElite — a mechanical-faction commander: high HP, slow on its own,
## but pulses an aura that buffs every other enemy within range (speed +
## contact damage) for as long as they stay nearby. Killing it fast denies
## that buff to the whole group around it — a priority target instead of
## just another HP bar. Appears from wave 7 onward.
extends "res://scripts/enemies/enemy_base.gd"

const AURA_RADIUS := 130.0
const AURA_INTERVAL := 1.0
const AURA_SPEED_MULT := 1.25
const AURA_DAMAGE_MULT := 1.3
const AURA_BUFF_DURATION := 1.5  # > AURA_INTERVAL so it never visibly lapses while in range

var _aura_timer: float = 0.0


func _ready() -> void:
	max_hp = 110.0
	speed = 42.0
	contact_damage = 22.0
	color = Color(1.0, 0.8, 0.15)  # gold
	shape_radius = 19.0
	reward_energy = 14.0
	super()


func _process(delta: float) -> void:
	super(delta)
	if _dead or not NetworkManager.is_host():
		return
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer = AURA_INTERVAL
		_pulse_aura()


func _pulse_aura() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.has_method("apply_buff") and global_position.distance_to(enemy.global_position) <= AURA_RADIUS:
			enemy.apply_buff(AURA_SPEED_MULT, AURA_DAMAGE_MULT, AURA_BUFF_DURATION)


func _draw_shape(col: Color) -> void:
	# Faint aura ring, always visible so its threat radius reads at a
	# glance instead of requiring a tooltip.
	draw_arc(Vector2.ZERO, AURA_RADIUS, 0, TAU, 48, Color(col.r, col.g, col.b, 0.12), 2.0)

	# Hexagon body with a crown of spikes — distinct silhouette from every
	# other enemy shape in the game.
	var hex := PackedVector2Array()
	for i in 6:
		var a := i * PI / 3.0 - PI / 6.0
		hex.append(Vector2(cos(a), sin(a)) * shape_radius)
	draw_polygon(hex, [col.darkened(0.15)])
	for i in 6:
		var a := i * PI / 3.0 - PI / 6.0
		var base := Vector2(cos(a), sin(a)) * shape_radius
		var tip := Vector2(cos(a), sin(a)) * (shape_radius + 6.0)
		draw_line(base, tip, col.lightened(0.3), 2.0)
