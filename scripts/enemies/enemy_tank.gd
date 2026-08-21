## EnemyTank — large hexagon, slow, heavy HP and damage
extends "res://scripts/enemies/enemy_base.gd"

func _ready() -> void:
	max_hp = 200.0
	speed = 28.0
	contact_damage = 60.0
	color = Color(0.7, 0.1, 0.9)   # purple
	shape_radius = 26.0
	reward_energy = 20.0
	super()


func _draw_shape(col: Color) -> void:
	# Hexagon
	var pts := PackedVector2Array()
	for i in 6:
		var a := i * (TAU / 6.0) - PI / 6.0
		pts.append(Vector2(cos(a), sin(a)) * shape_radius)
	draw_polygon(pts, [col.darkened(0.3)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.5)
	# Inner glow
	draw_circle(Vector2.ZERO, shape_radius * 0.4, col.lightened(0.2))
