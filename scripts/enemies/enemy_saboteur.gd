## EnemySaboteur — ignores the station core and heads for a random currently
## -built module slot instead (WaveManager picks it at spawn time and passes
## its world position as this enemy's `_target`, same as every other type —
## see wave_manager.gd's _compute_target_for). Reaching it disables the
## module for a while instead of dealing station damage, forcing players to
## also watch the ring, not just hold the center.
extends "res://scripts/enemies/enemy_base.gd"

const DISABLE_DURATION := 8.0


func _ready() -> void:
	max_hp = 45.0
	speed = 75.0
	contact_damage = 8.0  # only hits players caught in its path, never the station
	color = Color(0.65, 0.15, 0.95)  # violet
	shape_radius = 13.0
	reward_energy = 9.0
	super()


## Reached its target (a module slot, or the station center if nothing was
## built when it spawned) — disables whichever module is actually there
## instead of damaging the station, then self-destructs.
func _on_reach_station() -> void:
	if not NetworkManager.is_host():
		return
	var game := get_parent()
	var station: Node2D = game.get_node_or_null("Station") if game != null else null
	if station != null:
		var idx: int = station.get_nearest_slot_index(global_position)
		if idx >= 0 and GameState.module_slots[idx]["type"] != GameState.ModuleType.EMPTY:
			GameState.disable_module(idx, DISABLE_DURATION)
			AudioManager.play_sfx(AudioManager.SFX.STATION_DAMAGE, -8.0)
	_die()


func _draw_shape(col: Color) -> void:
	# Spiked diamond — visually distinct from the ranged enemy's plain diamond.
	var pts := PackedVector2Array([
		Vector2(0, -shape_radius * 1.3),
		Vector2(shape_radius * 0.55, -shape_radius * 0.2),
		Vector2(shape_radius, shape_radius * 0.3),
		Vector2(0, shape_radius * 0.7),
		Vector2(-shape_radius, shape_radius * 0.3),
		Vector2(-shape_radius * 0.55, -shape_radius * 0.2),
	])
	draw_polygon(pts, [col.darkened(0.25)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.35), 1.5)
