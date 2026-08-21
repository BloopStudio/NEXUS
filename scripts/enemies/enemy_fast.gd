## EnemyFast — small diamond, moves quickly, low HP
extends "res://scripts/enemies/enemy_base.gd"

func _ready() -> void:
	max_hp = 25.0
	speed = 120.0
	contact_damage = 8.0
	color = Color(1.0, 0.6, 0.1)   # orange
	shape_radius = 10.0
	reward_energy = 3.0
	super()


func _draw_shape(col: Color) -> void:
	# Diamond shape
	var pts := PackedVector2Array([
		Vector2(0, -shape_radius),
		Vector2(shape_radius, 0),
		Vector2(0, shape_radius),
		Vector2(-shape_radius, 0),
	])
	draw_polygon(pts, [col])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.4), 1.0)
