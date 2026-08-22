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

const BUILDABLE_TYPES := [
	GameState.ModuleType.GENERATOR, GameState.ModuleType.TURRET,
	GameState.ModuleType.SHIELD,    GameState.ModuleType.REPAIR,
	GameState.ModuleType.BOOSTER,   GameState.ModuleType.MINE,
	GameState.ModuleType.EMERGENCY_SHIELD, GameState.ModuleType.EMP,
]

## Modules with no level/upgrade path — one-time use, triggered by clicking
## their built slot during a WAVE (see station.gd), consumed on use.
const CHARGE_TYPES := [GameState.ModuleType.EMERGENCY_SHIELD, GameState.ModuleType.EMP]

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
	GameState.ModuleType.EMERGENCY_SHIELD: {1: "Soigne 30% de la vie max + invulnérabilité 3 s (usage unique)"},
	GameState.ModuleType.EMP:              {1: "80 dégâts + étourdit tous les ennemis à l'écran (usage unique)"},
}

var _hint_label: Label = null
var _skill_tree_btn: Button = null
var _skill_tree_panel: PanelContainer = null
var _slot_unlock_btn: Button = null
# branch (GameState.SkillBranch) -> Array[Button], one per tier (3 each)
var _skill_tier_buttons: Dictionary = {}

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
	GameState.skill_tree_changed.connect(_on_skill_tree_changed)
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

	# Skill tree entry point (top-left, under the HUD's energy panel). Always
	# visible during BUILD/UPGRADE. Wrapped in its own visible panel — a bare
	# Button here used to fully darken (via `modulate`) while unaffordable,
	# which made it blend into the dark background almost completely and read
	# as "not there" to players who hadn't saved up energy yet.
	var skill_panel := PanelContainer.new()
	skill_panel.add_theme_stylebox_override("panel", _skill_panel_style())
	skill_panel.anchor_left = 0.0
	skill_panel.anchor_right = 0.0
	skill_panel.offset_left = 8.0
	skill_panel.offset_right = 236.0
	skill_panel.offset_top = 64.0
	skill_panel.offset_bottom = 100.0
	add_child(skill_panel)

	_skill_tree_btn = Button.new()
	_skill_tree_btn.flat = true
	_skill_tree_btn.text = "🌳 Arbre de compétences"
	_skill_tree_btn.add_theme_font_size_override("font_size", 13)
	_skill_tree_btn.pressed.connect(_on_skill_tree_toggle_pressed)
	skill_panel.add_child(_skill_tree_btn)

	_build_skill_tree_panel()

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
			b.tooltip_text = "%s : %s" % [ModuleInfo.NAMES[t], MODULE_EFFECTS[t][1]]
			b.pressed.connect(func(): _build(captured_t))
			row.add_child(b)
			_build_buttons.append(b)

		var hint := Label.new()
		hint.text = "Survole un module pour voir son effet."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", C_DIM)
		_panel_body.add_child(hint)
	else:
		_panel_title.text = "Emplacement %d — %s" % [_selected_slot + 1, ModuleInfo.NAMES[mtype]]
		var level: int = slot.get("level", 0)

		var current_effect := Label.new()
		current_effect.text = "Actuellement : %s" % MODULE_EFFECTS[mtype][level]
		current_effect.add_theme_font_size_override("font_size", 12)
		current_effect.add_theme_color_override("font_color", C_DIM)
		_panel_body.add_child(current_effect)

		if mtype in CHARGE_TYPES:
			var lbl := Label.new()
			lbl.text = "⚡ Usage unique — clique sur l'emplacement PENDANT une vague pour l'activer."
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", C_ACCENT)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_panel_body.add_child(lbl)
		elif level >= 3:
			var lbl := Label.new()
			lbl.text = "%s %s — Niveau MAX" % [ModuleInfo.ICONS[mtype], ModuleInfo.NAMES[mtype]]
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
			b.text = "%s %s\n%d ⚡" % [ModuleInfo.ICONS[t], ModuleInfo.NAMES[t], int(cost)]
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
	_refresh_skill_tree_panel()


## A slot's contents changed — either locally, another player built/upgraded
## it over the network, or a full snapshot just landed (-1 = refresh all).
## Keep the panel in sync if it's showing the affected slot.
func _on_module_slots_changed(slot_index: int) -> void:
	if _panel.visible and (slot_index == _selected_slot or slot_index == -1):
		_rebuild_panel_contents()
	_refresh_skill_tree_panel()


func _on_skill_tree_changed() -> void:
	_refresh_skill_tree_panel()


func _update_visibility() -> void:
	var show := GameState.phase == GameState.Phase.BUILD or GameState.phase == GameState.Phase.UPGRADE
	_hint_label.visible = show and _selected_slot < 0
	_skill_tree_btn.visible = show
	if not show:
		_panel.visible = false
		_skill_tree_panel.visible = false
	_refresh_skill_tree_panel()


# ─── Skill tree (branching: slots + Dégâts/Économie/Défense) ──────────────────

func _on_skill_tree_toggle_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	_skill_tree_panel.visible = not _skill_tree_panel.visible
	if _skill_tree_panel.visible:
		_panel.visible = false  # the two overlays would otherwise fight for space


## Builds the skill tree overlay ONCE — same "never destroy/recreate on a
## passive tick" rule as the build/upgrade panel (see _rebuild_panel_contents'
## docstring): energy changes just update these SAME button instances.
func _build_skill_tree_panel() -> void:
	_skill_tree_panel = PanelContainer.new()
	_skill_tree_panel.visible = false
	_skill_tree_panel.add_theme_stylebox_override("panel", _skill_panel_style())
	_skill_tree_panel.anchor_left = 0.5
	_skill_tree_panel.anchor_right = 0.5
	_skill_tree_panel.anchor_top = 0.5
	_skill_tree_panel.anchor_bottom = 0.5
	_skill_tree_panel.offset_left = -420.0
	_skill_tree_panel.offset_right = 420.0
	_skill_tree_panel.offset_top = -220.0
	_skill_tree_panel.offset_bottom = 220.0
	add_child(_skill_tree_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	_skill_tree_panel.add_child(root_vbox)

	var header := HBoxContainer.new()
	root_vbox.add_child(header)
	var title := Label.new()
	title.text = "🌳 Arbre de compétences"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(func(): _skill_tree_panel.visible = false)
	header.add_child(close_btn)

	# Slot unlock — kept as its own row above the branches, same mechanic as
	# before (repeatable, increasing cost), just relocated into this panel.
	_slot_unlock_btn = Button.new()
	_slot_unlock_btn.custom_minimum_size = Vector2(0, 40)
	_slot_unlock_btn.add_theme_font_size_override("font_size", 13)
	_slot_unlock_btn.pressed.connect(_on_slot_unlock_pressed)
	root_vbox.add_child(_slot_unlock_btn)

	var branches_row := HBoxContainer.new()
	branches_row.add_theme_constant_override("separation", 14)
	branches_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(branches_row)

	for branch in [GameState.SkillBranch.DAMAGE, GameState.SkillBranch.ECONOMY, GameState.SkillBranch.DEFENSE]:
		branches_row.add_child(_build_branch_column(branch))


func _build_branch_column(branch: GameState.SkillBranch) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col_title := Label.new()
	col_title.text = GameState.SKILL_BRANCH_NAMES[branch]
	col_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_title.add_theme_font_size_override("font_size", 15)
	col_title.add_theme_color_override("font_color", C_ACCENT)
	col.add_child(col_title)

	var tier_buttons: Array[Button] = []
	var tiers: Array = GameState.SKILL_TREE[branch]
	for tier_index in tiers.size():
		var tier_def: Dictionary = tiers[tier_index]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 11)
		var captured_branch: GameState.SkillBranch = branch
		var captured_tier: int = tier_index
		btn.pressed.connect(func(): _on_skill_tier_pressed(captured_branch, captured_tier))
		col.add_child(btn)
		tier_buttons.append(btn)
	_skill_tier_buttons[branch] = tier_buttons

	return col


func _on_slot_unlock_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	GameState.request_unlock_slot()


func _on_skill_tier_pressed(branch: GameState.SkillBranch, tier_index: int) -> void:
	if tier_index != GameState.get_skill_tier(branch):
		return  # not the next tier in this branch — ignore (button should be disabled anyway)
	AudioManager.play_sfx(AudioManager.SFX.UPGRADE)
	GameState.request_unlock_skill(branch)


func _refresh_skill_tree_panel() -> void:
	# Top-left toggle button
	_skill_tree_btn.disabled = false
	_skill_tree_btn.add_theme_color_override("font_color", C_WHITE)

	# Slot unlock row
	var slot_cost := GameState.get_next_slot_unlock_cost()
	if slot_cost < 0.0:
		_slot_unlock_btn.text = "➕ Emplacements au maximum"
		_slot_unlock_btn.disabled = true
	else:
		var can_slot := GameState.can_afford(slot_cost)
		_slot_unlock_btn.text = "➕ Nouvel emplacement (%d/%d) — %d ⚡" % [
			GameState.module_slots.size(), GameState.MAX_SLOTS, int(slot_cost)]
		_slot_unlock_btn.disabled = not can_slot

	# Branch tier buttons
	for branch in _skill_tier_buttons:
		var tiers: Array = GameState.SKILL_TREE[branch]
		var unlocked: int = GameState.get_skill_tier(branch)
		var buttons: Array[Button] = _skill_tier_buttons[branch]
		for i in buttons.size():
			var btn := buttons[i]
			var tier_def: Dictionary = tiers[i]
			if i < unlocked:
				btn.text = "✅ %s\n%s" % [tier_def["name"], tier_def["desc"]]
				btn.disabled = true
				btn.modulate = Color(0.6, 1.0, 0.7)
			elif i == unlocked:
				var can := GameState.can_afford(tier_def["cost"])
				btn.text = "%s\n%s\n%d ⚡" % [tier_def["name"], tier_def["desc"], int(tier_def["cost"])]
				btn.disabled = not can
				btn.modulate = Color.WHITE if can else Color(0.6, 0.6, 0.65)
			else:
				btn.text = "🔒 %s" % tier_def["name"]
				btn.disabled = true
				btn.modulate = Color(0.4, 0.4, 0.45)


func _skill_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.16, 0.97)
	sb.border_color = C_ACCENT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb
