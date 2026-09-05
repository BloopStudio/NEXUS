## ModuleInfo — shared module name/icon lookup (by GameState.ModuleType index).
## Previously duplicated between upgrade_menu.gd and station.gd (needed for
## the slot hover tooltip) — a single shared source avoids the two drifting.
class_name ModuleInfo

const ICONS := ["➕", "⚡", "🔫", "🛡", "❤", "💪", "💣", "🚨", "☢", "⛏"]
const NAMES := ["Vide", "Générateur", "Tourelle", "Bouclier", "Réparation", "Amplificateur", "Mine", "Bouclier d'urgence", "Bombe EMP", "Foreuse"]


## Draws a small vector glyph for `mtype` centered on `pos`, scaled to slot
## radius `r` — shared by station.gd and outpost.gd so a module reads as the
## same shape everywhere, and so type is legible by silhouette alone, not
## just by MODULE_COLORS' hue (a real accessibility gap: nothing previously
## distinguished, say, Bouclier from Générateur for a colorblind player,
## or in the split-second glance during a wave). `ci` is the CanvasItem
## currently inside its own _draw() — Godot's draw_* calls only take effect
## on the item actually being drawn, so this can't be a free function.
static func draw_glyph(ci: CanvasItem, pos: Vector2, mtype: int, r: float) -> void:
	var g := Color(1.0, 1.0, 1.0, 0.88)
	var w := maxf(1.4, r * 0.09)
	match mtype:
		0:  # EMPTY — a faint "build here" plus, dim against the empty slot
			var s := r * 0.42
			var dim := Color(1.0, 1.0, 1.0, 0.28)
			ci.draw_line(pos + Vector2(-s, 0), pos + Vector2(s, 0), dim, w)
			ci.draw_line(pos + Vector2(0, -s), pos + Vector2(0, s), dim, w)
		1:  # GENERATOR — lightning bolt
			var pts := PackedVector2Array([
				Vector2(0.12, -0.55), Vector2(-0.32, 0.08), Vector2(-0.02, 0.08),
				Vector2(-0.12, 0.55), Vector2(0.32, -0.12), Vector2(0.02, -0.12),
			])
			var poly := PackedVector2Array()
			for p in pts:
				poly.append(pos + p * r)
			ci.draw_colored_polygon(poly, g)
		2:  # TURRET — barrel pointing outward + base
			ci.draw_circle(pos, r * 0.22, g)
			ci.draw_line(pos, pos + Vector2(0, -r * 0.62), g, w * 1.3)
		3:  # SHIELD — protective arc over a base line
			ci.draw_arc(pos + Vector2(0, r * 0.08), r * 0.5, PI * 1.12, PI * 1.88, 16, g, w)
			ci.draw_line(pos + Vector2(-r * 0.32, r * 0.28), pos + Vector2(r * 0.32, r * 0.28), g, w)
		4:  # REPAIR — bold medical cross
			var s := r * 0.5
			ci.draw_line(pos + Vector2(-s, 0), pos + Vector2(s, 0), g, w * 1.6)
			ci.draw_line(pos + Vector2(0, -s), pos + Vector2(0, s), g, w * 1.6)
		5:  # BOOSTER — two stacked chevrons pointing up
			for dy in [0.15, -0.28]:
				ci.draw_line(pos + Vector2(-r * 0.32, r * (dy + 0.16)), pos + Vector2(0, r * dy), g, w)
				ci.draw_line(pos + Vector2(r * 0.32, r * (dy + 0.16)), pos + Vector2(0, r * dy), g, w)
		6:  # MINE — spiked starburst
			for i in 8:
				var a := i * PI / 4.0
				var dir := Vector2(cos(a), sin(a))
				ci.draw_line(pos + dir * r * 0.18, pos + dir * r * 0.55, g, w)
		7:  # EMERGENCY_SHIELD — diamond
			var s := r * 0.5
			var poly := PackedVector2Array([pos + Vector2(0, -s), pos + Vector2(s, 0), pos + Vector2(0, s), pos + Vector2(-s, 0)])
			ci.draw_polyline(poly + PackedVector2Array([poly[0]]), g, w)
		8:  # EMP — radial burst (asterisk)
			for i in 6:
				var a := i * PI / 3.0
				var dir := Vector2(cos(a), sin(a))
				ci.draw_line(pos - dir * r * 0.5, pos + dir * r * 0.5, g, w)
		9:  # DRILL — angled bit + shaft
			var poly := PackedVector2Array([pos + Vector2(-r * 0.22, -r * 0.5), pos + Vector2(r * 0.22, -r * 0.5), pos + Vector2(0, r * 0.15)])
			ci.draw_colored_polygon(poly, g)
			ci.draw_line(pos + Vector2(0, r * 0.15), pos + Vector2(0, r * 0.55), g, w)
