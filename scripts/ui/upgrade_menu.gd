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
const C_ERROR    := Color(1.0, 0.4, 0.4)

# Icons per module type (enum index matches GameState.ModuleType)
const MODULE_ICONS  := ["➕", "⚡", "🔫", "🛡", "❤", "💪", "💣"]
const MODULE_NAMES  := ["Vide", "Générateur", "Tourelle", "Bouclier", "Réparation", "Amplificateur", "Mine"]
const BUILDABLE_TYPES := [
	GameState.ModuleType.GENERATOR, GameState.ModuleType.TURRET,
	GameState.ModuleType.SHIELD,    GameState.ModuleType.REPAIR,
	GameState.ModuleType.BOOSTER,   GameState.ModuleType.MINE,
]

# Per-level effect text, purely for display — keep these numbers in sync
# with their actual source: GENERATOR (idle_generator.gd ENERGY_PER_SEC),
# TURRET (station.gd _turret_damage/_turret_fire_rate), SHIELD (game_state.gd
# SHIELD_MAX_HP_BONUS_PER_LEVEL), REPAIR (wave_manager.gd _apply_repair_regen),
# BOOSTER (game_state.gd BOOSTER_DAMAGE_BONUS_PER_LEVEL).
const MODULE_EFFECTS := {
	GameState.ModuleType.GENERATOR: {1: "+3 énergie/s", 2: "+6 énergie/s", 3: "+11 énergie/s"},
	GameState.ModuleType.TURRET:    {1: "15 dégâts, tir toutes les 2,5 s", 2: "28 dégâts, tir toutes les 1,8 s", 3: "50 dégâts, tir toutes les 1,2 s"},
	GameState.ModuleType.SHIELD:    {1: "+60 vie max", 2: "+120 vie max", 3: "+180 vie max"},
	GameState.ModuleType.REPAIR:    {1: "+35 vie après chaque vague", 2: "+50 vie après chaque vague", 3: "+65 vie après chaque vague"},
	GameState.ModuleType.BOOSTER:   {1: "+15% dégâts des joueurs", 2: "+30% dégâts des joueurs", 3: "+45% dégâts des joueurs"},
	GameState.ModuleType.MINE:      {1: "20 dégâts en zone toutes les 3 s", 2: "35 dégâts en zone toutes les 3 s", 3: "55 dégâts en zone toutes les 3 s"},
}

var _hint_label: Label = null
var _skill_btn: Button = null

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

	# Skill tree: unlock extra station slots (top-left, under the HUD's
	# energy panel). Always visible during BUILD/UPGRADE, one click each.
	_skill_btn = Button.new()
	_skill_btn.anchor_left = 0.0
	_skill_btn.anchor_right = 0.0
	_skill_btn.offset_left = 8.0
	_skill_btn.offset_right = 236.0
	_skill_btn.offset_top = 64.0
	_skill_btn.offset_bottom = 96.0
	_skill_btn.add_theme_font_size_override("font_size", 13)
	_skill_btn.pressed.connect(_on_skill_pressed)
	add_child(_skill_btn)

	# Contextual panel — anchored at the bottom so it never covers the station
	# ring (which sits centered around the middle of the screen).
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_left   = 0.5
	_panel.anchor_right  = 0.5
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -350.0
	_panel.offset_right  =  350.0
	_panel.offset_top    = -190.0
	_panel.offset_bottom = -16.0
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
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
	_panel_body.add_theme_constant_override("separation", 8)
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
		row.add_theme_constant_override("separation", 8)
		_panel_body.add_child(row)

		for t in BUILDABLE_TYPES:
			var captured_t: GameState.ModuleType = t
			var b := Button.new()
			b.custom_minimum_size = Vector2(96, 56)
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = "%s : %s" % [MODULE_NAMES[t], MODULE_EFFECTS[t][1]]
			b.pressed.connect(func(): _build(captured_t))
			row.add_child(b)
			_build_buttons.append(b)

		var hint := Label.new()
		hint.text = "Survole un module pour voir son effet."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", C_DIM)
		_panel_body.add_child(hint)
	else:
		_panel_title.text = "Emplacement %d — %s" % [_selected_slot + 1, MODULE_NAMES[mtype]]
		var level: int = slot.get("level", 0)

		var current_effect := Label.new()
		current_effect.text = "Actuellement : %s" % MODULE_EFFECTS[mtype][level]
		current_effect.add_theme_font_size_override("font_size", 12)
		current_effect.add_theme_color_override("font_color", C_DIM)
		_panel_body.add_child(current_effect)

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

		var invested := GameState.get_module_total_invested(mtype, level)
		var refund := int(invested * GameState.DESTROY_REFUND_RATIO)
		var destroy_btn := Button.new()
		destroy_btn.text = "🗑 Détruire (+%d ⚡ remboursés)" % refund
		destroy_btn.add_theme_color_override("font_color", C_ERROR)
		destroy_btn.pressed.connect(_destroy)
		_panel_body.add_child(destroy_btn)

	_refresh_affordability()


## Cheap, non-destructive refresh — called on every energy tick.
func _refresh_affordability() -> void:
	if _selected_slot < 0 or not _panel.visible:
		return
	var slot: Dictionary = GameState.module_slots[_selected_slot]
	var mtype: int = slot.get("type", 0)

	if mtype == GameState.ModuleType.EMPTY:
		for i in _build_buttons.size():
			var t: GameState.ModuleType = BUILDABLE_TYPES[i]
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
		_upgrade_label.text = "Niveau %d → %d : %s" % [level, level + 1, MODULE_EFFECTS[mtype][level + 1]]
		_upgrade_button.text = "Améliorer — %d ⚡" % int(cost)
		_upgrade_button.disabled = not can
		_upgrade_button.modulate = C_WHITE if can else C_DISABLED


func _build(mtype: GameState.ModuleType) -> void:
	if _selected_slot < 0:
		return
	AudioManager.play_sfx(AudioManager.SFX.BUILD)
	GameState.request_build_module(_selected_slot, mtype)
	# The panel refreshes itself via _on_module_slots_changed once the
	# change actually lands (instant for the host, one round-trip for a
	# client) — no need to rebuild here.


func _upgrade() -> void:
	if _selected_slot < 0:
		return
	AudioManager.play_sfx(AudioManager.SFX.UPGRADE)
	GameState.request_upgrade_module(_selected_slot)


func _destroy() -> void:
	if _selected_slot < 0:
		return
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	GameState.request_destroy_module(_selected_slot)
	_deselect()


# ─── Signal handlers ────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameState.Phase) -> void:
	_update_visibility()
	if phase == GameState.Phase.BUILD:
		_deselect()


func _on_energy_changed(_val: float) -> void:
	_refresh_affordability()
	_refresh_skill_button()


## A slot's contents changed — either locally, another player built/upgraded
## it over the network, or a full snapshot just landed (-1 = refresh all).
## Keep the panel in sync if it's showing the affected slot.
func _on_module_slots_changed(slot_index: int) -> void:
	if _panel.visible and (slot_index == _selected_slot or slot_index == -1):
		_rebuild_panel_contents()
	_refresh_skill_button()


func _update_visibility() -> void:
	var show := GameState.phase == GameState.Phase.BUILD or GameState.phase == GameState.Phase.UPGRADE
	_hint_label.visible = show and _selected_slot < 0
	_skill_btn.visible = show
	if not show:
		_panel.visible = false
	_refresh_skill_button()


# ─── Skill tree (extra station slots) ──────────────────────────────────────────

func _on_skill_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	GameState.request_unlock_slot()


func _refresh_skill_button() -> void:
	var cost := GameState.get_next_slot_unlock_cost()
	if cost < 0.0:
		_skill_btn.text = "🌳 Emplacements au maximum"
		_skill_btn.disabled = true
		return
	var can := GameState.can_afford(cost)
	_skill_btn.text = "🌳 Nouvel emplacement — %d ⚡" % int(cost)
	_skill_btn.disabled = not can
	_skill_btn.modulate = C_WHITE if can else C_DISABLED
