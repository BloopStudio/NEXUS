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
var _wave_label:    Label      = null
var _timer_bar:     ColorRect  = null
var _timer_bar_bg:  ColorRect  = null
var _timer_max:     float      = 20.0
var _timer_value:   float      = 20.0
var _station_label: Label      = null
var _station_bar:   ColorRect  = null
var _station_bar_bg: ColorRect = null
var _player_list:   VBoxContainer = null


func _ready() -> void:
	layer = 10
	_build_ui()
	_connect_signals()


func _build_ui() -> void:
	# All panels are anchor-positioned (relative to the corners/center of the
	# viewport) rather than pinned to fixed pixel coordinates, so the HUD
	# stays correctly placed if the window is resized.

	# ── Top-left: Energy ──────────────────────────────────────────────────────
	var tl := _panel_anchored(0.0, 0.0, Vector2(8, 8), Vector2(208, 48))
	_energy_label = Label.new()
	_energy_label.add_theme_font_size_override("font_size", 18)
	_energy_label.add_theme_color_override("font_color", C_ACCENT)
	_energy_label.text = "ÉNERGIE: 50"
	tl.add_child(_energy_label)

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
	_wave_label.text = "VAGUE 0"
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
	_station_label.text = "STATION 500/500"
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

	# ── Top-right, below station HP: leave the match without quitting ────────
	var quit_btn := Button.new()
	quit_btn.text = "✕ Quitter"
	quit_btn.anchor_left = 1.0
	quit_btn.anchor_right = 1.0
	quit_btn.offset_left = -208.0
	quit_btn.offset_right = -8.0
	quit_btn.offset_top = 68.0
	quit_btn.offset_bottom = 100.0
	quit_btn.add_theme_font_size_override("font_size", 13)
	quit_btn.pressed.connect(_on_quit_pressed)
	add_child(quit_btn)


# ─── Signal connections ────────────────────────────────────────────────────────

func _connect_signals() -> void:
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.station_health_changed.connect(_on_station_health_changed)
	GameState.phase_changed.connect(_on_phase_changed)

	# Wave manager countdown
	# We listen on _process instead to avoid coupling to WaveManager instance
	set_process(true)

	NetworkManager.player_connected.connect(func(_id): _refresh_player_list())
	NetworkManager.player_disconnected.connect(func(_id): _refresh_player_list())
	NetworkManager.players_updated.connect(_refresh_player_list)


func _process(_delta: float) -> void:
	# Update countdown bar each frame (WaveManager fires a signal but we poll for simplicity)
	pass


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_energy_changed(val: float) -> void:
	_energy_label.text = "ÉNERGIE: %d" % int(val)


func _on_wave_changed(num: int) -> void:
	_wave_label.text = "VAGUE %d" % num


func _on_station_health_changed(hp: float) -> void:
	var ratio := hp / GameState.station_max_hp
	_station_label.text = "STATION %d/%d" % [int(hp), int(GameState.station_max_hp)]
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
			suffix = "  👑 hôte"
		elif info.has("ping_ms"):
			suffix = "  %dms" % int(info["ping_ms"])
		else:
			suffix = "  …ms"

		lbl.text = "● %s%s" % [info.get("name", "Player"), suffix]
		_player_list.add_child(lbl)


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
