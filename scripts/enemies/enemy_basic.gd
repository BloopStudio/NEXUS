## EnemyBasic — standard triangle enemy
extends "res://scripts/enemies/enemy_base.gd"

func _ready() -> void:
	max_hp = 50.0
	speed = 55.0
	contact_damage = 15.0
	color = Color(1.0, 0.25, 0.25)
	shape_radius = 14.0
	reward_energy = 5.0
	super()


func _draw_shape(col: Color) -> void:
	# Triangle pointing toward station (rotated toward target)
	var angle := (_target - global_position).angle() + PI / 2.0
	var pts := PackedVector2Array()
	for i in 3:
		var a := angle + i * (TAU / 3.0)
		pts.append(Vector2(cos(a), sin(a)) * shape_radius)
	draw_polygon(pts, [col])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.3), 1.5)
