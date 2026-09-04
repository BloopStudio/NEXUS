## EnemyAberration — the first enemy of a second, stranger faction that
## starts showing up from wave 15 onward: instead of blocking one direction
## like the Bouclier, it periodically phases fully out of reality for about
## a second (translucent, immune to everything) before phasing back in —
## forces timing damage into its vulnerable windows instead of just
## sustained fire. The phase clock runs identically on every peer (a shared
## deterministic cycle off Time.get_ticks_msec(), not a host-broadcast
## state) so the translucency reads correctly everywhere without any extra
## networking, while _blocks_damage (host-only-invoked, like every other
## damage check) reads that same cycle to decide whether a hit lands.
extends "res://scripts/enemies/enemy_base.gd"

const PHASE_CYCLE := 3.0
const PHASE_DURATION := 1.0

var _phased: bool = false


func _ready() -> void:
	max_hp = 60.0
	speed = 65.0
	contact_damage = 16.0
	color = Color(0.55, 0.15, 0.65)  # sickly violet
	shape_radius = 14.0
	reward_energy = 11.0
	super()


func _process(delta: float) -> void:
	super(delta)
	if _dead:
		return
	var cycle_pos := fmod(Time.get_ticks_msec() / 1000.0, PHASE_CYCLE)
	var new_phased := cycle_pos < PHASE_DURATION
	if new_phased != _phased:
		_phased = new_phased
		queue_redraw()


func _blocks_damage(_from_direction: Vector2) -> bool:
	return _phased


func _draw_shape(col: Color) -> void:
	var draw_col := Color(col.r, col.g, col.b, 0.35) if _phased else col
	# Irregular, jagged silhouette — reads as "not of this world" next to
	# every other enemy's clean geometric shape.
	var pts := PackedVector2Array([
		Vector2(0, -shape_radius * 1.2),
		Vector2(shape_radius * 0.8, -shape_radius * 0.2),
		Vector2(shape_radius * 0.5, shape_radius),
		Vector2(-shape_radius * 0.5, shape_radius),
		Vector2(-shape_radius * 0.8, -shape_radius * 0.2),
	])
	draw_polygon(pts, [draw_col])
