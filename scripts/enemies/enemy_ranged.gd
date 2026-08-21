## EnemyRanged — keeps its distance and fires at the station instead of
## charging in for contact damage. Adds a different threat pattern: players
## have to actively hunt it down instead of just holding the line.
extends "res://scripts/enemies/enemy_base.gd"

const STANDOFF_RADIUS := 220.0
const FIRE_INTERVAL := 1.8
const RANGED_DAMAGE := 12.0

var _fire_timer: float = 0.0
var _fire_flash: float = 0.0


func _ready() -> void:
	max_hp = 35.0
	speed = 55.0
	contact_damage = 10.0
	color = Color(1.0, 0.15, 0.6)  # magenta
	shape_radius = 13.0
	reward_energy = 7.0
	_fire_timer = randf_range(0.4, FIRE_INTERVAL)
	super()


func _process(delta: float) -> void:
	if _dead:
		return

	if NetworkManager.is_host():
		var to_target := _target - global_position
		if to_target.length() > STANDOFF_RADIUS:
			global_position += to_target.normalized() * speed * delta
		else:
			_fire_timer -= delta
			if _fire_timer <= 0.0:
				_fire_timer = FIRE_INTERVAL
				GameState.damage_station(RANGED_DAMAGE)
				AudioManager.play_sfx(AudioManager.SFX.STATION_DAMAGE, -6.0)
				_fire_flash = 0.15
	else:
		global_position = global_position.lerp(_net_target_pos, clampf(delta * NET_INTERP_SPEED, 0.0, 1.0))

	_face_target()

	if _hit_flash > 0.0:
		_hit_flash -= delta
	if _fire_flash > 0.0:
		_fire_flash -= delta

	queue_redraw()


func _draw_shape(col: Color) -> void:
	# Diamond shape, distinct from the fast enemy's smaller diamond.
	var pts := PackedVector2Array([
		Vector2(0, -shape_radius),
		Vector2(shape_radius * 0.7, 0),
		Vector2(0, shape_radius),
		Vector2(-shape_radius * 0.7, 0),
	])
	draw_polygon(pts, [col.darkened(0.2)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.3), 1.5)

	if _fire_flash > 0.0:
		# This runs inside the rotated draw transform set up by _draw() in
		# the base class, which already aligns "up" with the direction to
		# the target — so the beam is simply drawn straight ahead here.
		draw_line(Vector2.ZERO, Vector2(0, -260), Color(1.0, 0.4, 0.9, _fire_flash / 0.15), 2.0)
