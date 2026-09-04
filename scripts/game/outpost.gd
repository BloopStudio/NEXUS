## Outpost — a lightweight second defensible point ("stations multiples").
## No module slots of its own, just an HP bar — some enemies target it
## instead of the main station once it's built (see wave_manager.gd), and
## losing it doesn't end the match, only the main station does.
extends Node2D

const RADIUS := 26.0
const C_CORE := Color(0.15, 0.9, 0.65)  # teal, distinct from the main station's cyan
const C_CORE_DAMAGED := Color(1.0, 0.4, 0.1)


func _ready() -> void:
	position = GameState.OUTPOST_OFFSET
	GameState.outpost_changed.connect(func(): queue_redraw())
	queue_redraw()


func _draw() -> void:
	if not GameState.outpost_built:
		return

	var hp_ratio := GameState.outpost_hp / GameState.outpost_max_hp if GameState.outpost_max_hp > 0.0 else 0.0
	var col := C_CORE.lerp(C_CORE_DAMAGED, 1.0 - hp_ratio)

	# Diamond body — visually distinct from the main station's hexagon core.
	var pts := PackedVector2Array([
		Vector2(0, -RADIUS), Vector2(RADIUS, 0), Vector2(0, RADIUS), Vector2(-RADIUS, 0),
	])
	draw_polygon(pts, [col.darkened(0.4)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.5)

	# HP bar (arc, same visual language as the main station's).
	draw_arc(Vector2.ZERO, RADIUS + 8, -PI / 2, -PI / 2 + TAU * hp_ratio, 32, col, 4.0)

	var font := ThemeDB.fallback_font
	var label := "Avant-poste"
	var font_size := 12
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-text_size.x / 2.0, -RADIUS - 14.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.8))
