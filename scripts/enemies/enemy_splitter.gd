## EnemySplitter — squat hexagon that breaks into two Fast enemies on death.
## Adds a "don't just tank it" threat: ignoring it costs you double the
## trouble a moment later.
extends "res://scripts/enemies/enemy_base.gd"


func _ready() -> void:
	max_hp = 45.0
	speed = 45.0
	contact_damage = 14.0
	color = Color(0.9, 0.85, 0.1)  # yellow-green
	shape_radius = 16.0
	reward_energy = 6.0
	super()


## WaveManager checks this after the enemy dies (host-only) to know what,
## if anything, to spawn in its place. Empty string = no split.
func get_split_type() -> String:
	return "fast"


func get_split_count() -> int:
	return 2


func _draw_shape(col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 5:
		var a := i * (TAU / 5.0) - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * shape_radius)
	draw_polygon(pts, [col.darkened(0.25)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.3), 2.0)
	# Crack lines hinting it's about to split.
	for p in pts:
		draw_line(Vector2.ZERO, p * 0.9, col.darkened(0.5), 1.0)
