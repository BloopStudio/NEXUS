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

# Base per-level numbers — keep these in sync with their actual source:
# GENERATOR (idle_generator.gd ENERGY_PER_SEC), TURRET (station.gd
# _turret_damage/_turret_fire_rate), SHIELD (game_state.gd
# SHIELD_MAX_HP_BONUS_PER_LEVEL), REPAIR (wave_manager.gd _apply_repair_regen),
# BOOSTER (game_state.gd BOOSTER_DAMAGE_BONUS_PER_LEVEL), MINE (station.gd
# _mine_damage). get_module_effect_text() below folds in the skill tree's
# current bonuses (damage/idle/repair/max-HP tiers) so the displayed numbers
# are what the module ACTUALLY does right now, not just its flat base value.
const GENERATOR_PER_SEC := {1: 3.0, 2: 6.0, 3: 11.0}
const TURRET_DAMAGE := {1: 15.0, 2: 28.0, 3: 50.0}
const TURRET_COOLDOWN := {1: 2.5, 2: 1.8, 3: 1.2}
const MINE_DAMAGE := {1: 20.0, 2: 35.0, 3: 55.0}

# Static fallback text for modules whose effect isn't skill-scaled (charge
# modules) or expressed as a percentage of a value that already bakes the
# skill bonus in (station max HP), so the raw text stays accurate as-is.
const MODULE_EFFECTS := {
	GameState.ModuleType.EMERGENCY_SHIELD: {1: "Soigne 30% de la vie max + invulnérabilité 3 s (usage unique)"},
	GameState.ModuleType.EMP:              {1: "80 dégâts + étourdit tous les ennemis à l'écran (usage unique)"},
}


## Live effect text for `mtype` at `level`, including the team's current
## skill tree bonuses (Dégâts/Économie/Défense) — e.g. a level-1 Tourelle
## reads "18 dégâts..." instead of a flat "15 dégâts..." once Armement I is
## unlocked, so the panel always shows what the module actually does right
## now, not just its unmodified base value.
func get_module_effect_text(mtype: int, level: int) -> String:
	match mtype:
		GameState.ModuleType.GENERATOR:
			var per_sec: float = GENERATOR_PER_SEC[level] * GameState.get_skill_idle_multiplier()
			return "+%.1f énergie/s" % per_sec
		GameState.ModuleType.TURRET:
			var dmg: float = TURRET_DAMAGE[level] * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier()
			return "%d dégâts, tir toutes les %.1f s" % [int(dmg), TURRET_COOLDOWN[level]]
		GameState.ModuleType.MINE:
			var dmg: float = MINE_DAMAGE[level] * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier()
			return "%d dégâts en zone toutes les 3 s" % int(dmg)
		GameState.ModuleType.REPAIR:
			var heal: float = (20.0 + float(level) * 15.0) * GameState.get_skill_repair_multiplier()
			return "+%d vie après chaque vague" % int(heal)
		GameState.ModuleType.SHIELD:
			var hp: float = GameState.SHIELD_MAX_HP_BONUS_PER_LEVEL * level * GameState.get_skill_max_hp_multiplier()
			return "+%d vie max" % int(hp)
		GameState.ModuleType.BOOSTER:
			# Effective total damage bump this module contributes once the
			# team's flat skill-tree damage bonus is compounded on top of it.
			var pct: float = ((1.0 + GameState.BOOSTER_DAMAGE_BONUS_PER_LEVEL * level) * GameState.get_skill_damage_multiplier() * GameState.get_mutator_damage_multiplier() - 1.0) * 100.0
			return "+%d%% dégâts des joueurs" % int(round(pct))
		_:
			return MODULE_EFFECTS.get(mtype, {}).get(level, "")

var _hint_label: Label = null
var _skill_panel: PanelContainer = null
var _skill_tree_btn: Button = null
var _skill_tree_panel: PanelContainer = null
var _slot_unlock_btn: Button = null
var _arena_expand_btn: Button = null
var _outpost_build_btns: Array[Button] = []
# branch (GameState.SkillBranch) -> Array[Button], one per tier (3 each)
var _skill_tier_buttons: Dictionary = {}

var _panel: PanelContainer = null
var _panel_title: Label    = null
var _panel_body: VBoxContainer = null
var _selected_slot: int    = -1
## -1 = the main station's module_slots; otherwise which GameState.outposts
## index the current selection belongs to. Reuses the exact same panel/
## build/upgrade/destroy flow as the main station rather than a whole
## separate UI — see _current_slots() and friends below.
var _selected_outpost: int = -1

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
	GameState.arena_expanded.connect(_refresh_skill_tree_panel)
	GameState.outpost_changed.connect(_refresh_skill_tree_panel)
	GameState.outpost_changed.connect(_on_outpost_changed)
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
	_skill_panel = PanelContainer.new()
	_skill_panel.add_theme_stylebox_override("panel", _skill_panel_style())
	_skill_panel.anchor_left = 0.0
	_skill_panel.anchor_right = 0.0
	_skill_panel.offset_left = 8.0
	_skill_panel.offset_right = 236.0
	_skill_panel.offset_top = 64.0
	_skill_panel.offset_bottom = 100.0
	add_child(_skill_panel)

	_skill_tree_btn = Button.new()
	_skill_tree_btn.flat = true
	_skill_tree_btn.text = "🌳 Arbre de compétences"
	_skill_tree_btn.add_theme_font_size_override("font_size", 13)
	_skill_tree_btn.pressed.connect(_on_skill_tree_toggle_pressed)
	_skill_panel.add_child(_skill_tree_btn)

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
	if idx == _selected_slot and _selected_outpost == -1:
		_deselect()
	else:
		_selected_outpost = -1
		_select(idx)


## Connected externally by game.gd, one per Outpost instance.
func on_outpost_slot_clicked(outpost_index: int, slot_index: int) -> void:
	if GameState.phase != GameState.Phase.BUILD and GameState.phase != GameState.Phase.UPGRADE:
		return
	if slot_index == _selected_slot and outpost_index == _selected_outpost:
		_deselect()
	else:
		_selected_outpost = outpost_index
		_select(slot_index)


func _select(idx: int) -> void:
	_selected_slot = idx
	_hint_label.visible = false
	_panel.visible = true
	_rebuild_panel_contents()


func _deselect() -> void:
	_selected_slot = -1
	_selected_outpost = -1
	_panel.visible = false
	_hint_label.visible = (GameState.phase == GameState.Phase.BUILD)


# ─── Outpost-vs-main-station indirection ───────────────────────────────────
## Which slots array the current selection reads/writes.
func _current_slots() -> Array:
	if _selected_outpost >= 0:
		return GameState.outposts[_selected_outpost]["slots"]
	return GameState.module_slots


## Outposts skip the charge modules (Bouclier d'urgence/Bombe EMP) — keeps
## their build menu simpler and avoids needing outpost-specific charge-
## trigger click handling.
func _current_buildable_types() -> Array:
	if _selected_outpost >= 0:
		return BUILDABLE_TYPES.filter(func(t): return t not in CHARGE_TYPES)
	return BUILDABLE_TYPES


func _current_upgrade_cost() -> float:
	if _selected_outpost >= 0:
		return GameState.get_outpost_module_upgrade_cost(_selected_outpost, _selected_slot)
	return GameState.get_module_upgrade_cost(_selected_slot)


## Synergies only exist on the main station's ring — an outpost's slots
## aren't adjacent to anything to synergize with.
func _current_synergy_note(slot_index: int, mtype: int = -1) -> String:
	if _selected_outpost >= 0:
		return ""
	if mtype == -1:
		return GameState.get_synergy_note(slot_index)
	return GameState.get_synergy_note_for_type(slot_index, mtype)


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

	var slot: Dictionary = _current_slots()[_selected_slot]
	var mtype: int = slot.get("type", 0)
	var location_label := "Avant-poste %d" % (_selected_outpost + 1) if _selected_outpost >= 0 else "Emplacement"

	if mtype == GameState.ModuleType.EMPTY:
		_panel_title.text = "%s — Construire" % location_label

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_panel_body.add_child(row)

		for t in _current_buildable_types():
			var captured_t: GameState.ModuleType = t
			var b := Button.new()
			b.custom_minimum_size = Vector2(96, 56)
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = "%s : %s%s" % [ModuleInfo.NAMES[t], get_module_effect_text(t, 1), _current_synergy_note(_selected_slot, t)]
			b.pressed.connect(func(): _build(captured_t))
			row.add_child(b)
			_build_buttons.append(b)

		var hint := Label.new()
		hint.text = "Survole un module pour voir son effet."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", C_DIM)
		_panel_body.add_child(hint)
	else:
		_panel_title.text = "%s — %s" % [location_label, ModuleInfo.NAMES[mtype]]
		var level: int = slot.get("level", 0)

		var current_effect := Label.new()
		current_effect.text = "Actuellement : %s%s" % [get_module_effect_text(mtype, level), _current_synergy_note(_selected_slot)]
		current_effect.add_theme_font_size_override("font_size", 12)
		current_effect.add_theme_color_override("font_color", C_DIM)
		_panel_body.add_child(current_effect)

		if slot.get("disabled", false):
			var disabled_lbl := Label.new()
			disabled_lbl.text = "🔒 Désactivé temporairement (touché par un Saboteur) — reprend son effet automatiquement."
			disabled_lbl.add_theme_font_size_override("font_size", 12)
			disabled_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			disabled_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_panel_body.add_child(disabled_lbl)

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
	var slot: Dictionary = _current_slots()[_selected_slot]
	var mtype: int = slot.get("type", 0)
	var buildable := _current_buildable_types()

	if mtype == GameState.ModuleType.EMPTY:
		for i in _build_buttons.size():
			var t: GameState.ModuleType = buildable[i]
			var cost: float = GameState.get_module_build_cost(t)
			var can: bool   = GameState.can_afford(cost)
			var b := _build_buttons[i]
			b.text = "%s %s\n%d ⚡" % [ModuleInfo.ICONS[t], ModuleInfo.NAMES[t], int(cost)]
			b.disabled = not can
			b.modulate = C_WHITE if can else C_DISABLED
	elif _upgrade_button != null:
		var level: int = slot.get("level", 0)
		var cost: float = _current_upgrade_cost()
		var can: bool   = GameState.can_afford(cost)
		_upgrade_label.text = "Niveau %d → %d : %s%s" % [level, level + 1, get_module_effect_text(mtype, level + 1), _current_synergy_note(_selected_slot)]
		_upgrade_button.text = "Améliorer — %d ⚡" % int(cost)
		_upgrade_button.disabled = not can
		_upgrade_button.modulate = C_WHITE if can else C_DISABLED


func _build(mtype: GameState.ModuleType) -> void:
	if _selected_slot < 0:
		return
	AudioManager.play_sfx(AudioManager.SFX.BUILD)
	if _selected_outpost >= 0:
		GameState.request_build_outpost_module(_selected_outpost, _selected_slot, mtype)
	else:
		GameState.request_build_module(_selected_slot, mtype)
	# The panel refreshes itself via _on_module_slots_changed/outpost_changed
	# once the change actually lands (instant for the host, one round-trip
	# for a client) — no need to rebuild here.


func _upgrade() -> void:
	if _selected_slot < 0:
		return
	AudioManager.play_sfx(AudioManager.SFX.UPGRADE)
	if _selected_outpost >= 0:
		GameState.request_upgrade_outpost_module(_selected_outpost, _selected_slot)
	else:
		GameState.request_upgrade_module(_selected_slot)


func _destroy() -> void:
	if _selected_slot < 0:
		return
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	if _selected_outpost >= 0:
		GameState.request_destroy_outpost_module(_selected_outpost, _selected_slot)
	else:
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
	if _panel.visible and _selected_outpost == -1 and (slot_index == _selected_slot or slot_index == -1):
		_rebuild_panel_contents()
	_refresh_skill_tree_panel()


## An outpost's build/HP state changed — keep the panel in sync if it's
## currently showing a slot on that outpost (outpost_changed doesn't carry
## which one, so just always rebuild when the selection is on an outpost —
## this signal is nowhere near as frequent as module_slots_changed).
func _on_outpost_changed() -> void:
	if _panel.visible and _selected_outpost >= 0:
		_rebuild_panel_contents()


func _on_skill_tree_changed() -> void:
	_refresh_skill_tree_panel()
	# The build/upgrade panel's displayed numbers (get_module_effect_text)
	# fold in the current skill bonuses, so a newly-unlocked tier has to
	# rebuild it too, not just the skill-tree overlay itself.
	if _panel.visible and _selected_slot >= 0:
		_rebuild_panel_contents()


func _update_visibility() -> void:
	var show := GameState.phase == GameState.Phase.BUILD or GameState.phase == GameState.Phase.UPGRADE
	_hint_label.visible = show and _selected_slot < 0
	# Hide the whole bordered panel, not just the button inside it — toggling
	# only the button used to leave its empty background/border on-screen
	# during a wave (nothing else clears a PanelContainer's own stylebox).
	_skill_panel.visible = show
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

	# Arena expansion ("la carte s'agrandit par morceaux") — same repeatable/
	# increasing-cost rhythm as the slot unlock row above.
	_arena_expand_btn = Button.new()
	_arena_expand_btn.custom_minimum_size = Vector2(0, 40)
	_arena_expand_btn.add_theme_font_size_override("font_size", 13)
	_arena_expand_btn.pressed.connect(_on_arena_expand_pressed)
	root_vbox.add_child(_arena_expand_btn)

	# Outposts ("stations multiples") — one button per outpost slot, each a
	# one-time build only offered once the arena has room for it (see
	# GameState.OUTPOST_MIN_ARENA_TIER).
	for i in GameState.MAX_OUTPOSTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 13)
		var captured_index: int = i
		btn.pressed.connect(func(): _on_outpost_build_pressed(captured_index))
		root_vbox.add_child(btn)
		_outpost_build_btns.append(btn)

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


func _on_arena_expand_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	GameState.request_expand_arena()


func _on_outpost_build_pressed(index: int) -> void:
	AudioManager.play_sfx(AudioManager.SFX.BUILD)
	GameState.request_build_outpost(index)


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

	# Arena expansion row
	var arena_cost := GameState.get_next_arena_expand_cost()
	if arena_cost < 0.0:
		_arena_expand_btn.text = "🗺 Carte au maximum"
		_arena_expand_btn.disabled = true
	else:
		var can_arena := GameState.can_afford(arena_cost)
		_arena_expand_btn.text = "🗺 Agrandir la carte (%d/%d) — %d ⚡" % [
			GameState.arena_tier, GameState.MAX_ARENA_TIER, int(arena_cost)]
		_arena_expand_btn.disabled = not can_arena

	# Outpost rows — one per outpost slot
	for i in _outpost_build_btns.size():
		var btn := _outpost_build_btns[i]
		var min_tier: int = GameState.OUTPOST_MIN_ARENA_TIER[i] if i < GameState.OUTPOST_MIN_ARENA_TIER.size() else 1
		if i < GameState.outposts.size() and GameState.outposts[i]["built"]:
			btn.text = "🏳 Avant-poste %d déjà construit" % (i + 1)
			btn.disabled = true
		elif GameState.arena_tier < min_tier:
			btn.text = "🏳 Avant-poste %d (agrandir la carte au palier %d)" % [i + 1, min_tier]
			btn.disabled = true
		else:
			var can_outpost := GameState.can_afford(GameState.OUTPOST_BUILD_COST)
			btn.text = "🏳 Construire l'avant-poste %d — %d ⚡" % [i + 1, int(GameState.OUTPOST_BUILD_COST)]
			btn.disabled = not can_outpost

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
