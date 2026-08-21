## SettingsMenu — Contrôles / Graphismes / Son
## Self-contained overlay; emits `closed` when dismissed.
extends Control

signal closed()

const C_BG      := Color(0.039, 0.039, 0.059, 0.96)
const C_ACCENT  := Color(0.0, 0.831, 1.0)
const C_TEXT    := Color(1, 1, 1)
const C_DIM     := Color(0.6, 0.6, 0.7)

var _listening_action: String = ""
var _rebind_buttons: Dictionary = {}  # action -> Button

var _fullscreen_check: CheckButton
var _vsync_check: CheckButton
var _resolution_option: OptionButton

var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -280.0
	panel.offset_bottom = 280.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.theme_override_constants = {"separation": 12}
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "RÉGLAGES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 420)
	vbox.add_child(tabs)

	tabs.add_child(_build_controls_tab())
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_audio_tab())

	var close_btn := Button.new()
	close_btn.text = "Fermer"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(_on_close)
	vbox.add_child(close_btn)


# ─── Contrôles ────────────────────────────────────────────────────────────────

func _build_controls_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "Contrôles"
	root.theme_override_constants = {"separation": 10}

	var hint := Label.new()
	hint.text = "Clique sur une touche puis appuie sur la nouvelle touche/bouton."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", C_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(hint)

	for action in SettingsManager.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.theme_override_constants = {"separation": 12}
		root.add_child(row)

		var lbl := Label.new()
		lbl.text = SettingsManager.ACTION_LABELS.get(action, action)
		lbl.custom_minimum_size = Vector2(180, 0)
		lbl.add_theme_color_override("font_color", C_TEXT)
		row.add_child(lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 36)
		btn.text = _event_display_name(SettingsManager.get_action_event(action))
		var captured_action: String = action
		btn.pressed.connect(func(): _start_listening(captured_action, btn))
		row.add_child(btn)
		_rebind_buttons[action] = btn

	return root


func _start_listening(action: String, btn: Button) -> void:
	_listening_action = action
	btn.text = "Appuie sur une touche…"
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		SettingsManager.rebind_action(_listening_action, event)
		_finish_listening()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		SettingsManager.rebind_action(_listening_action, event)
		_finish_listening()
		get_viewport().set_input_as_handled()


func _finish_listening() -> void:
	var btn: Button = _rebind_buttons.get(_listening_action)
	if btn:
		btn.text = _event_display_name(SettingsManager.get_action_event(_listening_action))
	_listening_action = ""
	set_process_unhandled_input(false)


func _event_display_name(event: InputEvent) -> String:
	if event == null:
		return "—"
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "Clic gauche"
			MOUSE_BUTTON_RIGHT: return "Clic droit"
			MOUSE_BUTTON_MIDDLE: return "Clic molette"
			_: return "Bouton souris %d" % event.button_index
	return "?"


# ─── Graphismes ───────────────────────────────────────────────────────────────

func _build_graphics_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "Graphismes"
	root.theme_override_constants = {"separation": 14}

	var fs_row := HBoxContainer.new()
	root.add_child(fs_row)
	var fs_lbl := Label.new()
	fs_lbl.text = "Plein écran"
	fs_lbl.custom_minimum_size = Vector2(200, 0)
	fs_lbl.add_theme_color_override("font_color", C_TEXT)
	fs_row.add_child(fs_lbl)
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.button_pressed = SettingsManager.fullscreen
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fullscreen_check)

	var vs_row := HBoxContainer.new()
	root.add_child(vs_row)
	var vs_lbl := Label.new()
	vs_lbl.text = "V-Sync"
	vs_lbl.custom_minimum_size = Vector2(200, 0)
	vs_lbl.add_theme_color_override("font_color", C_TEXT)
	vs_row.add_child(vs_lbl)
	_vsync_check = CheckButton.new()
	_vsync_check.button_pressed = SettingsManager.vsync
	_vsync_check.toggled.connect(_on_vsync_toggled)
	vs_row.add_child(_vsync_check)

	var res_row := HBoxContainer.new()
	root.add_child(res_row)
	var res_lbl := Label.new()
	res_lbl.text = "Résolution fenêtrée"
	res_lbl.custom_minimum_size = Vector2(200, 0)
	res_lbl.add_theme_color_override("font_color", C_TEXT)
	res_row.add_child(res_lbl)
	_resolution_option = OptionButton.new()
	for res in RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [res.x, res.y])
	var current_idx := RESOLUTIONS.find(SettingsManager.window_size)
	_resolution_option.selected = maxi(0, current_idx)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	res_row.add_child(_resolution_option)

	return root


func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.fullscreen = pressed
	SettingsManager.apply_graphics()
	SettingsManager.save_settings()


func _on_vsync_toggled(pressed: bool) -> void:
	SettingsManager.vsync = pressed
	SettingsManager.apply_graphics()
	SettingsManager.save_settings()


func _on_resolution_selected(idx: int) -> void:
	SettingsManager.window_size = RESOLUTIONS[idx]
	SettingsManager.apply_graphics()
	SettingsManager.save_settings()


# ─── Son ──────────────────────────────────────────────────────────────────────

func _build_audio_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "Son"
	root.theme_override_constants = {"separation": 18}

	_master_slider = _volume_row(root, "Général", SettingsManager.master_volume, _on_master_changed)
	_music_slider  = _volume_row(root, "Musique", SettingsManager.music_volume, _on_music_changed)
	_sfx_slider    = _volume_row(root, "Effets sonores", SettingsManager.sfx_volume, _on_sfx_changed)

	return root


func _volume_row(root: Control, label: String, value: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.theme_override_constants = {"separation": 12}
	root.add_child(row)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.add_theme_color_override("font_color", C_TEXT)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 0)
	slider.value_changed.connect(cb)
	row.add_child(slider)
	return slider


func _on_master_changed(v: float) -> void:
	SettingsManager.master_volume = v
	AudioManager.set_bus_volume("Master", v)
	SettingsManager.save_settings()


func _on_music_changed(v: float) -> void:
	SettingsManager.music_volume = v
	AudioManager.set_bus_volume("Music", v)
	SettingsManager.save_settings()


func _on_sfx_changed(v: float) -> void:
	SettingsManager.sfx_volume = v
	AudioManager.set_bus_volume("SFX", v)
	SettingsManager.save_settings()
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)


# ─── Close ────────────────────────────────────────────────────────────────────

func _on_close() -> void:
	if not _listening_action.is_empty():
		_finish_listening()
	closed.emit()
