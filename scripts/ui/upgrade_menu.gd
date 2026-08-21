## UpgradeMenu — shown during UPGRADE / BUILD phases
## Lets players build and upgrade station modules.
extends CanvasLayer

const C_BG      := Color(0.05, 0.05, 0.09, 0.92)
const C_PANEL   := Color(0.08, 0.09, 0.16, 0.97)
const C_ACCENT  := Color(0.0, 0.831, 1.0)
const C_WHITE   := Color(1.0, 1.0, 1.0)
const C_DIM     := Color(0.5, 0.5, 0.6)
const C_DISABLED := Color(0.3, 0.3, 0.35)

# Icons per module type (enum index matches GameState.ModuleType)
const MODULE_ICONS  := ["➕", "⚡", "🔫", "🛡", "❤"]
const MODULE_NAMES  := ["Vide", "Générateur", "Tourelle", "Bouclier", "Réparation"]

var _root_panel: PanelContainer = null
var _slot_buttons: Array[Button] = []
var _sub_panel: Control         = null  # Build/upgrade sub-menu
var _selected_slot: int         = -1


func _ready() -> void:
	layer = 20
	_build_ui()
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.energy_changed.connect(_on_energy_changed)
	_update_visibility()


func _build_ui() -> void:
	# Semi-transparent overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.35)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Centered panel
	_root_panel = PanelContainer.new()
	_root_panel.anchor_left   = 0.5
	_root_panel.anchor_right  = 0.5
	_root_panel.anchor_top    = 0.5
	_root_panel.anchor_bottom = 0.5
	_root_panel.offset_left   = -320.0
	_root_panel.offset_right  =  320.0
	_root_panel.offset_top    = -260.0
	_root_panel.offset_bottom =  260.0
	add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.theme_override_constants = {"separation": 12}
	_root_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "PHASE DE CONSTRUCTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Cliquez sur un emplacement pour construire ou améliorer"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(sub)

	# 2×4 grid of slot buttons
	var grid := GridContainer.new()
	grid.columns = 4
	grid.theme_override_constants = {"h_separation": 10, "v_separation": 10}
	vbox.add_child(grid)

	_slot_buttons.clear()
	for i in 8:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(130, 90)
		btn.add_theme_font_size_override("font_size", 14)
		var idx := i  # capture
		btn.pressed.connect(func(): _on_slot_pressed(idx))
		grid.add_child(btn)
		_slot_buttons.append(btn)

	# Sub-panel for build/upgrade options (hidden initially)
	_sub_panel = VBoxContainer.new()
	_sub_panel.visible = false
	_sub_panel.theme_override_constants = {"separation": 8}
	vbox.add_child(_sub_panel)

	_refresh_slots()


# ─── Slot rendering ────────────────────────────────────────────────────────────

func _refresh_slots() -> void:
	for i in 8:
		var slot: Dictionary = GameState.module_slots[i]
		var mtype: int       = slot.get("type", 0)
		var level: int       = slot.get("level", 0)
		var btn: Button      = _slot_buttons[i]

		if mtype == GameState.ModuleType.EMPTY:
			btn.text = "➕\nVide"
			btn.modulate = Color(0.7, 0.7, 0.8)
		else:
			var stars := "★".repeat(level) + "☆".repeat(3 - level)
			btn.text = "%s\n%s\nNiv.%d %s" % [
				MODULE_ICONS[mtype], MODULE_NAMES[mtype], level, stars
			]
			btn.modulate = Color.WHITE

		# Highlight selected
		btn.flat = (i != _selected_slot)


# ─── Slot click ───────────────────────────────────────────────────────────────

func _on_slot_pressed(idx: int) -> void:
	_selected_slot = idx
	_refresh_slots()
	_show_sub_menu(idx)


func _show_sub_menu(idx: int) -> void:
	# Clear sub-panel
	for child in _sub_panel.get_children():
		child.queue_free()
	_sub_panel.visible = true

	var slot: Dictionary = GameState.module_slots[idx]
	var mtype: int       = slot.get("type", 0)

	if mtype == GameState.ModuleType.EMPTY:
		# Build options
		var lbl := Label.new()
		lbl.text = "Construire un module :"
		lbl.add_theme_color_override("font_color", C_WHITE)
		_sub_panel.add_child(lbl)

		var row := HBoxContainer.new()
		row.theme_override_constants = {"separation": 8}
		_sub_panel.add_child(row)

		for t in [GameState.ModuleType.GENERATOR, GameState.ModuleType.TURRET,
				  GameState.ModuleType.SHIELD,    GameState.ModuleType.REPAIR]:
			var cost: float = GameState.get_module_build_cost(t)
			var can: bool   = GameState.can_afford(cost)
			var b := Button.new()
			b.text = "%s %s\n%d ⚡" % [MODULE_ICONS[t], MODULE_NAMES[t], int(cost)]
			b.custom_minimum_size = Vector2(120, 60)
			b.disabled = not can
			if not can:
				b.modulate = C_DISABLED
			var captured_t := t
			b.pressed.connect(func(): _build(idx, captured_t))
			row.add_child(b)
	else:
		# Upgrade or max info
		var level: int = slot.get("level", 0)
		if level >= 3:
			var lbl := Label.new()
			lbl.text = "%s %s — Niveau MAX" % [MODULE_ICONS[mtype], MODULE_NAMES[mtype]]
			lbl.add_theme_color_override("font_color", C_ACCENT)
			_sub_panel.add_child(lbl)
		else:
			var cost: float = GameState.get_module_upgrade_cost(idx)
			var can: bool   = GameState.can_afford(cost)

			var lbl := Label.new()
			lbl.text = "%s %s — Niveau %d → %d" % [MODULE_ICONS[mtype], MODULE_NAMES[mtype], level, level + 1]
			lbl.add_theme_color_override("font_color", C_WHITE)
			_sub_panel.add_child(lbl)

			var b := Button.new()
			b.text = "Améliorer — %d ⚡" % int(cost)
			b.disabled = not can
			if not can:
				b.modulate = C_DISABLED
			b.pressed.connect(func(): _upgrade(idx))
			_sub_panel.add_child(b)


func _build(idx: int, mtype: GameState.ModuleType) -> void:
	if GameState.build_module(idx, mtype):
		_selected_slot = -1
		_sub_panel.visible = false
		_refresh_slots()


func _upgrade(idx: int) -> void:
	if GameState.upgrade_module(idx):
		_sub_panel.visible = false
		_refresh_slots()


# ─── Visibility ───────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameState.Phase) -> void:
	_update_visibility()
	if phase == GameState.Phase.BUILD:
		_refresh_slots()
		_selected_slot = -1
		_sub_panel.visible = false


func _on_energy_changed(_val: float) -> void:
	if _root_panel.visible and _selected_slot >= 0:
		_show_sub_menu(_selected_slot)


func _update_visibility() -> void:
	var show := GameState.phase == GameState.Phase.BUILD or GameState.phase == GameState.Phase.UPGRADE
	if _root_panel:
		_root_panel.visible = show
	# Overlay visibility follows panel
	if get_child_count() > 0:
		get_child(0).visible = show
