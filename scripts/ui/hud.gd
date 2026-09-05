## HUD — in-game heads-up display
## All drawn with Control nodes created in code (no .tscn needed).
extends CanvasLayer

const C_ACCENT  := Color(0.0, 0.831, 1.0)
const C_WHITE   := Color(1.0, 1.0, 1.0)
const C_DIM     := Color(0.6, 0.6, 0.7)
const C_BG      := Color(0.05, 0.05, 0.09, 0.82)
const C_HP_OK   := Color(0.2, 0.9, 0.3)
const C_HP_LOW  := Color(1.0, 0.3, 0.1)

var _energy_label:  Label      = null
var _materials_label: Label    = null
var _wave_label:    Label      = null
var _timer_bar:     ColorRect  = null
var _timer_bar_bg:  ColorRect  = null
var _timer_max:     float      = 20.0
var _timer_value:   float      = 20.0
var _station_label: Label      = null
var _station_bar:   ColorRect  = null
var _station_bar_bg: ColorRect = null
var _player_list:   VBoxContainer = null
var _settings_btn:  Button        = null
var _quit_btn:      Button        = null

# ── Spell slots (bottom-center) ──
const SPELL_KEYS := ["E", "A"]
var _spell_icon_labels: Array[Label] = []
var _spell_cd_overlays: Array[ColorRect] = []
var _spell_cd_labels: Array[Label] = []
var _spell_levelup_buttons: Array[Button] = []


func _ready() -> void:
	layer = 10
	_build_ui()
	_connect_signals()
	I18n.language_changed.connect(_on_language_changed)
	set_process(true)


## Re-texts the static labels/buttons in place (unlike main_menu.gd/
## settings_menu.gd, this doesn't rebuild — the HUD's structure is simple
## enough, and rebuilding while a wave is running would risk losing the
## spell-slot polling state momentarily).
func _on_language_changed() -> void:
	_energy_label.text = I18n.t("hud.energy") % int(GameState.energy)
	_materials_label.text = I18n.t("hud.materials") % int(GameState.rare_materials)
	_wave_label.text = I18n.t("hud.wave") % GameState.wave_number
	_station_label.text = I18n.t("hud.station") % [int(GameState.station_hp), int(GameState.station_max_hp)]
	_settings_btn.text = I18n.t("hud.settings")
	_quit_btn.text = I18n.t("hud.quit")
	_refresh_player_list()


func _process(_delta: float) -> void:
	_update_spell_slots()


func _build_ui() -> void:
	# All panels are anchor-positioned (relative to the corners/center of the
	# viewport) rather than pinned to fixed pixel coordinates, so the HUD
	# stays correctly placed if the window is resized.

	# ── Top-left: Energy + rare materials ─────────────────────────────────────
	var tl := _panel_anchored(0.0, 0.0, Vector2(8, 8), Vector2(208, 66))
	var tl_vbox := VBoxContainer.new()
	tl.add_child(tl_vbox)
	_energy_label = Label.new()
	_energy_label.add_theme_font_size_override("font_size", 18)
	_energy_label.add_theme_color_override("font_color", C_ACCENT)
	_energy_label.text = I18n.t("hud.energy") % 50
	tl_vbox.add_child(_energy_label)

	# Only meaningful once a Foreuse module exists somewhere on the team, but
	# always shown at 0 rather than conditionally — simpler than plumbing a
	# "has a Foreuse ever been built" flag through, and a "0" is itself a
	# hint the module exists and does something.
	_materials_label = Label.new()
	_materials_label.add_theme_font_size_override("font_size", 13)
	_materials_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.4))
	_materials_label.text = I18n.t("hud.materials") % 0
	tl_vbox.add_child(_materials_label)

	# ── Top-center: Wave + countdown bar ─────────────────────────────────────
	var tc_root := PanelContainer.new()
	tc_root.add_theme_stylebox_override("panel", _panel_style())
	tc_root.anchor_left = 0.5
	tc_root.anchor_right = 0.5
	tc_root.offset_left = -160.0
	tc_root.offset_right = 160.0
	tc_root.offset_top = 8.0
	tc_root.offset_bottom = 60.0
	add_child(tc_root)

	var tc_vbox := VBoxContainer.new()
	tc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc_root.add_child(tc_vbox)

	_wave_label = Label.new()
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 18)
	_wave_label.add_theme_color_override("font_color", C_WHITE)
	_wave_label.text = I18n.t("hud.wave") % 0
	tc_vbox.add_child(_wave_label)

	# Countdown bar background
	_timer_bar_bg = ColorRect.new()
	_timer_bar_bg.color = Color(0.12, 0.12, 0.2)
	_timer_bar_bg.custom_minimum_size = Vector2(0, 10)
	tc_vbox.add_child(_timer_bar_bg)

	# Countdown bar fill (positioned inside bg)
	_timer_bar = ColorRect.new()
	_timer_bar.color = C_ACCENT
	_timer_bar_bg.add_child(_timer_bar)
	_timer_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── Top-right: Station HP ─────────────────────────────────────────────────
	var tr := _panel_anchored(1.0, 0.0, Vector2(-208, 8), Vector2(-8, 60))
	var tr_vbox := VBoxContainer.new()
	tr.add_child(tr_vbox)

	_station_label = Label.new()
	_station_label.add_theme_font_size_override("font_size", 15)
	_station_label.add_theme_color_override("font_color", C_WHITE)
	_station_label.text = I18n.t("hud.station") % [500, 500]
	tr_vbox.add_child(_station_label)

	_station_bar_bg = ColorRect.new()
	_station_bar_bg.color = Color(0.12, 0.12, 0.2)
	_station_bar_bg.custom_minimum_size = Vector2(0, 10)
	tr_vbox.add_child(_station_bar_bg)

	_station_bar = ColorRect.new()
	_station_bar.color = C_HP_OK
	_station_bar_bg.add_child(_station_bar)
	_station_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── Bottom-left: Player list ──────────────────────────────────────────────
	var bl := _panel_anchored(0.0, 1.0, Vector2(8, -140), Vector2(208, -8))
	_player_list = VBoxContainer.new()
	bl.add_child(_player_list)
	_refresh_player_list()

	# ── Bottom-center: spell slots (icon + key + cooldown overlay) ───────────
	var spell_row := HBoxContainer.new()
	spell_row.anchor_left = 0.5
	spell_row.anchor_right = 0.5
	spell_row.anchor_top = 1.0
	spell_row.anchor_bottom = 1.0
	spell_row.offset_left = -60.0
	spell_row.offset_right = 60.0
	spell_row.offset_top = -92.0
	spell_row.offset_bottom = -8.0
	spell_row.add_theme_constant_override("separation", 8)
	add_child(spell_row)

	for i in 2:
		var slot_col := VBoxContainer.new()
		slot_col.add_theme_constant_override("separation", 2)
		spell_row.add_child(slot_col)

		# Level-up button — placed ABOVE its spell's icon (rather than below)
		# so it reads as "what upgrades this slot" sitting over the slot it
		# affects. Only meaningfully clickable during BUILD/UPGRADE (spends
		# shared team energy, same rhythm as building modules).
		var captured_i: int = i
		var levelup_btn := Button.new()
		levelup_btn.custom_minimum_size = Vector2(0, 20)
		levelup_btn.add_theme_font_size_override("font_size", 10)
		levelup_btn.pressed.connect(func(): _on_spell_levelup_pressed(captured_i))
		slot_col.add_child(levelup_btn)
		_spell_levelup_buttons.append(levelup_btn)

		var slot := PanelContainer.new()
		slot.add_theme_stylebox_override("panel", _panel_style())
		slot.custom_minimum_size = Vector2(52, 52)
		slot_col.add_child(slot)

		var slot_stack := Control.new()
		slot_stack.custom_minimum_size = Vector2(48, 48)
		slot.add_child(slot_stack)

		var icon_lbl := Label.new()
		icon_lbl.add_theme_font_size_override("font_size", 22)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot_stack.add_child(icon_lbl)
		_spell_icon_labels.append(icon_lbl)

		# Darkening overlay whose height tracks remaining-cooldown ratio —
		# a simple "fills back up" bar instead of a radial wipe.
		var overlay := ColorRect.new()
		overlay.color = Color(0.0, 0.0, 0.0, 0.65)
		overlay.anchor_left = 0.0
		overlay.anchor_right = 1.0
		overlay.anchor_bottom = 1.0
		overlay.anchor_top = 1.0
		slot_stack.add_child(overlay)
		_spell_cd_overlays.append(overlay)

		var cd_lbl := Label.new()
		cd_lbl.add_theme_font_size_override("font_size", 13)
		cd_lbl.add_theme_color_override("font_color", C_WHITE)
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot_stack.add_child(cd_lbl)
		_spell_cd_labels.append(cd_lbl)

		var key_lbl := Label.new()
		key_lbl.text = SPELL_KEYS[i]
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.add_theme_color_override("font_color", C_DIM)
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_lbl.anchor_left = 1.0
		key_lbl.anchor_right = 1.0
		key_lbl.anchor_top = 0.0
		key_lbl.offset_left = -14.0
		key_lbl.offset_top = -2.0
		slot_stack.add_child(key_lbl)

	# ── Top-right, below station HP: settings + leave the match ──────────────
	_settings_btn = Button.new()
	var settings_btn := _settings_btn
	settings_btn.text = I18n.t("hud.settings")
	settings_btn.anchor_left = 1.0
	settings_btn.anchor_right = 1.0
	settings_btn.offset_left = -208.0
	settings_btn.offset_right = -8.0
	settings_btn.offset_top = 68.0
	settings_btn.offset_bottom = 100.0
	settings_btn.add_theme_font_size_override("font_size", 13)
	settings_btn.pressed.connect(_on_settings_pressed)
	add_child(settings_btn)

	_quit_btn = Button.new()
	var quit_btn := _quit_btn
	quit_btn.text = I18n.t("hud.quit")
	quit_btn.anchor_left = 1.0
	quit_btn.anchor_right = 1.0
	quit_btn.offset_left = -208.0
	quit_btn.offset_right = -8.0
	quit_btn.offset_top = 104.0
	quit_btn.offset_bottom = 136.0
	quit_btn.add_theme_font_size_override("font_size", 13)
	quit_btn.pressed.connect(_on_quit_pressed)
	add_child(quit_btn)


# ─── Signal connections ────────────────────────────────────────────────────────

func _connect_signals() -> void:
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.rare_materials_changed.connect(_on_rare_materials_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.station_health_changed.connect(_on_station_health_changed)
	GameState.phase_changed.connect(_on_phase_changed)

	NetworkManager.player_connected.connect(func(_id): _refresh_player_list())
	NetworkManager.player_disconnected.connect(func(_id): _refresh_player_list())
	NetworkManager.players_updated.connect(_refresh_player_list)


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_energy_changed(val: float) -> void:
	_energy_label.text = I18n.t("hud.energy") % int(val)


func _on_rare_materials_changed(val: float) -> void:
	_materials_label.text = I18n.t("hud.materials") % int(val)


func _on_wave_changed(num: int) -> void:
	_wave_label.text = I18n.t("hud.wave") % num


func _on_station_health_changed(hp: float) -> void:
	var ratio := hp / GameState.station_max_hp
	_station_label.text = I18n.t("hud.station") % [int(hp), int(GameState.station_max_hp)]
	_station_bar.anchor_right = ratio
	_station_bar.color = C_HP_OK.lerp(C_HP_LOW, 1.0 - ratio)


func _on_phase_changed(phase: GameState.Phase) -> void:
	match phase:
		GameState.Phase.BUILD:
			_wave_label.add_theme_color_override("font_color", C_ACCENT)
			_timer_bar.color = C_ACCENT
		GameState.Phase.WAVE:
			_wave_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))
			_timer_bar.anchor_right = 0.0  # Hide bar during wave


func update_build_timer(seconds_left: float, max_time: float) -> void:
	_timer_max = maxf(1.0, max_time)
	_timer_value = seconds_left
	var ratio := clampf(seconds_left / _timer_max, 0.0, 1.0)
	_timer_bar.anchor_right = ratio


## Reads the local player's equipped spells/cooldowns each frame and updates
## the two bottom-center slot icons — polling is simpler than plumbing a
## signal through Game/Player for something this cheap to just read.
func _update_spell_slots() -> void:
	var game := get_parent()
	if game == null or not game.has_method("get_local_player"):
		return
	var player: Node = game.get_local_player()
	if player == null or not player.has_method("get_spell_slot_info"):
		return

	var can_build := GameState.phase == GameState.Phase.BUILD or GameState.phase == GameState.Phase.UPGRADE

	for i in 2:
		var info: Array = player.get_spell_slot_info(i)
		if info.is_empty():
			_spell_icon_labels[i].text = ""
			_spell_levelup_buttons[i].visible = false
			continue
		var spell_id: String = info[0]
		var remaining: float = info[1]
		var max_cd: float = info[2]
		var level: int = info[3]
		var def: Dictionary = Spells.DEFS[spell_id]
		_spell_icon_labels[i].text = def["icon"]
		_spell_icon_labels[i].tooltip_text = "%s (niv. %d)" % [def["name"], level]

		var ratio := clampf(remaining / max_cd, 0.0, 1.0) if max_cd > 0.0 else 0.0
		_spell_cd_overlays[i].anchor_top = 1.0 - ratio
		_spell_cd_labels[i].text = "%d" % ceili(remaining) if remaining > 0.05 else ""

		var btn := _spell_levelup_buttons[i]
		btn.visible = can_build
		if can_build:
			if level >= Spells.MAX_LEVEL:
				btn.text = I18n.t("hud.level_max")
				btn.disabled = true
			else:
				var cost: float = Spells.LEVEL_UP_COST[level]
				btn.text = "▲ Nv.%d (%d⚡)" % [level + 1, int(cost)]
				btn.disabled = not GameState.can_afford(cost)


func _on_spell_levelup_pressed(slot: int) -> void:
	var game := get_parent()
	if game == null or not game.has_method("get_local_player"):
		return
	var player = game.get_local_player()
	if player == null:
		return
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	player.request_level_up_spell(slot)


# ─── Player list ──────────────────────────────────────────────────────────────

func _refresh_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()

	for peer_id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[peer_id]
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 13)
		var col: Color = info.get("color", C_ACCENT)
		lbl.add_theme_color_override("font_color", col)

		var suffix := ""
		if peer_id == NetworkManager.HOST_PEER_ID:
			suffix = I18n.t("hud.host_tag")
		elif info.has("ping_ms"):
			suffix = "  %dms" % int(info["ping_ms"])
		else:
			suffix = "  …ms"

		lbl.text = "● %s%s" % [info.get("name", "Player"), suffix]
		_player_list.add_child(lbl)


func _on_settings_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	# Settings is a plain Control, not its own CanvasLayer — added straight
	# under the HUD (layer 10) it would render BEHIND the UpgradeMenu
	# (layer 20) whenever that's open. A dedicated higher-layer wrapper
	# guarantees it's always on top, in-game or from the main menu alike.
	var overlay := CanvasLayer.new()
	overlay.layer = 30
	add_child(overlay)
	var settings_script = load("res://scripts/ui/settings_menu.gd")
	var settings: Control = settings_script.new()
	settings.closed.connect(func(): overlay.queue_free())
	overlay.add_child(settings)


# ─── Leaving the match ──────────────────────────────────────────────────────────

func _on_quit_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	NetworkManager.disconnect_from_game()
	SceneLoader.change_scene("res://scenes/main_menu.tscn")


# ─── Helper ───────────────────────────────────────────────────────────────────

## Anchored panel: `anchor` picks the corner (0,0 = top-left, 1,0 = top-right,
## 0,1 = bottom-left, ...) and `top_left_offset`/`bottom_right_offset` are
## pixel offsets from that anchor point — this is what keeps HUD panels
## correctly placed when the window is resized, instead of the fixed pixel
## coordinates the HUD used to be built with (which only looked right at the
## project's default 1280×720).
func _panel_anchored(anchor_x: float, anchor_y: float, top_left_offset: Vector2, bottom_right_offset: Vector2) -> Control:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.anchor_left = anchor_x
	bg.anchor_right = anchor_x
	bg.anchor_top = anchor_y
	bg.anchor_bottom = anchor_y
	bg.offset_left = top_left_offset.x
	bg.offset_top = top_left_offset.y
	bg.offset_right = bottom_right_offset.x
	bg.offset_bottom = bottom_right_offset.y
	add_child(bg)
	return bg


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	return sb
