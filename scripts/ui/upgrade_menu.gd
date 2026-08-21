## UpgradeMenu — shown during UPGRADE / BUILD phases
## Click directly on a station slot (see Station.slot_clicked) to build or
## upgrade it — there is no separate list of slots to pick from.
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

var _hint_label: Label = null

var _panel: PanelContainer = null
var _panel_title: Label    = null
var _panel_body: VBoxContainer = null
var _selected_slot: int    = -1

# Build mode: one button per buildable type, kept alive across affordability
# refreshes so a passive energy tick never interrupts an in-progress click.
var _build_buttons: Array[Button] = []
# Upgrade mode: single "upgrade" button, kept alive the same way.
var _upgrade_button: Button = null
var _upgrade_label: Label   = null


func _ready() -> void:
	layer = 20
	_build_ui()
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.module_slots_changed.connect(_on_module_slots_changed)
	_update_visibility()


func _build_ui() -> void:
	# Persistent hint, shown whenever nothing is selected during BUILD phase.
	_hint_label = Label.new()
	_hint_label.anchor_left   = 0.5
	_hint_label.anchor_right  = 0.5
	_hint_label.anchor_top    = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left   = -300.0
	_hint_label.offset_right  =  300.0
	_hint_label.offset_top    = -60.0
	_hint_label.offset_bottom = -20.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.text = "Clique sur un emplacement de la station pour construire ou améliorer"
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", C_DIM)
	add_child(_hint_label)

	# Contextual panel — anchored at the bottom so it never covers the station
	# ring (which sits centered around the middle of the screen).
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_left   = 0.5
	_panel.anchor_right  = 0.5
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -260.0
	_panel.offset_right  =  260.0
	_panel.offset_top    = -190.0
	_panel.offset_bottom = -16.0
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.theme_override_constants = {"separation": 10}
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 17)
	_panel_title.add_theme_color_override("font_color", C_ACCENT)
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_panel_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(_deselect)
	header.add_child(close_btn)

	_panel_body = VBoxContainer.new()
	_panel_body.theme_override_constants = {"separation": 8}
	vbox.add_child(_panel_body)


# ─── Station slot click (connected externally by game.gd) ─────────────────────

func on_slot_clicked(idx: int) -> void:
	if GameState.phase != GameState.Phase.BUILD and GameState.phase != GameState.Phase.UPGRADE:
		return
	if idx == _selected_slot:
		_deselect()
	else:
		_select(idx)


func _select(idx: int) -> void:
	_selected_slot = idx
	_hint_label.visible = false
	_panel.visible = true
	_rebuild_panel_contents()


func _deselect() -> void:
	_selected_slot = -1
	_panel.visible = false
	_hint_label.visible = (GameState.phase == GameState.Phase.BUILD)


# ─── Panel contents ─────────────────────────────────────────────────────────────
## Builds the interactive widgets for the selected slot ONCE. Subsequent
## energy changes only tweak `disabled`/`modulate` on these SAME instances
## (see _refresh_affordability) — never destroy/recreate them, otherwise a
## click in progress gets orphaned onto a freed node and never registers
## (this used to make building/upgrading a second module nearly impossible
## once a Generator module was passively trickling energy every frame).

func _rebuild_panel_contents() -> void:
	for child in _panel_body.get_children():
		child.queue_free()
	_build_buttons.clear()
	_upgrade_button = null
	_upgrade_label = null

	var slot: Dictionary = GameState.module_slots[_selected_slot]
	var mtype: int = slot.get("type", 0)

	if mtype == GameState.ModuleType.EMPTY:
		_panel_title.text = "Emplacement %d — Construire" % (_selected_slot + 1)

		var row := HBoxContainer.new()
		row.theme_override_constants = {"separation": 8}
		_panel_body.add_child(row)

		for t in [GameState.ModuleType.GENERATOR, GameState.ModuleType.TURRET,
				  GameState.ModuleType.SHIELD,    GameState.ModuleType.REPAIR]:
			var captured_t: GameState.ModuleType = t
			var b := Button.new()
			b.custom_minimum_size = Vector2(112, 56)
			b.pressed.connect(func(): _build(captured_t))
			row.add_child(b)
			_build_buttons.append(b)
	else:
		_panel_title.text = "Emplacement %d — %s" % [_selected_slot + 1, MODULE_NAMES[mtype]]
		var level: int = slot.get("level", 0)

		if level >= 3:
			var lbl := Label.new()
			lbl.text = "%s %s — Niveau MAX" % [MODULE_ICONS[mtype], MODULE_NAMES[mtype]]
			lbl.add_theme_color_override("font_color", C_ACCENT)
			_panel_body.add_child(lbl)
		else:
			_upgrade_label = Label.new()
			_upgrade_label.add_theme_color_override("font_color", C_WHITE)
			_panel_body.add_child(_upgrade_label)

			_upgrade_button = Button.new()
			_upgrade_button.pressed.connect(_upgrade)
			_panel_body.add_child(_upgrade_button)

	_refresh_affordability()


## Cheap, non-destructive refresh — called on every energy tick.
func _refresh_affordability() -> void:
	if _selected_slot < 0 or not _panel.visible:
		return
	var slot: Dictionary = GameState.module_slots[_selected_slot]
	var mtype: int = slot.get("type", 0)

	if mtype == GameState.ModuleType.EMPTY:
		var types := [GameState.ModuleType.GENERATOR, GameState.ModuleType.TURRET,
					  GameState.ModuleType.SHIELD,    GameState.ModuleType.REPAIR]
		for i in _build_buttons.size():
			var t: GameState.ModuleType = types[i]
			var cost: float = GameState.get_module_build_cost(t)
			var can: bool   = GameState.can_afford(cost)
			var b := _build_buttons[i]
			b.text = "%s %s\n%d ⚡" % [MODULE_ICONS[t], MODULE_NAMES[t], int(cost)]
			b.disabled = not can
			b.modulate = C_WHITE if can else C_DISABLED
	elif _upgrade_button != null:
		var level: int = slot.get("level", 0)
		var cost: float = GameState.get_module_upgrade_cost(_selected_slot)
		var can: bool   = GameState.can_afford(cost)
		_upgrade_label.text = "%s %s — Niveau %d → %d" % [MODULE_ICONS[mtype], MODULE_NAMES[mtype], level, level + 1]
		_upgrade_button.text = "Améliorer — %d ⚡" % int(cost)
		_upgrade_button.disabled = not can
		_upgrade_button.modulate = C_WHITE if can else C_DISABLED


func _build(mtype: GameState.ModuleType) -> void:
	if _selected_slot < 0:
		return
	if GameState.build_module(_selected_slot, mtype):
		AudioManager.play_sfx(AudioManager.SFX.BUILD)
		_rebuild_panel_contents()


func _upgrade() -> void:
	if _selected_slot < 0:
		return
	if GameState.upgrade_module(_selected_slot):
		AudioManager.play_sfx(AudioManager.SFX.UPGRADE)
		_rebuild_panel_contents()


# ─── Signal handlers ────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameState.Phase) -> void:
	_update_visibility()
	if phase == GameState.Phase.BUILD:
		_deselect()


func _on_energy_changed(_val: float) -> void:
	_refresh_affordability()


## A slot's contents changed elsewhere (e.g. another player built/upgraded it
## over the network) — keep the panel in sync if it's the one being viewed.
func _on_module_slots_changed(slot_index: int) -> void:
	if slot_index == _selected_slot and _panel.visible:
		_rebuild_panel_contents()


func _update_visibility() -> void:
	var show := GameState.phase == GameState.Phase.BUILD or GameState.phase == GameState.Phase.UPGRADE
	_hint_label.visible = show and _selected_slot < 0
	if not show:
		_panel.visible = false
