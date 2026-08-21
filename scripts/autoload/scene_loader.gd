## SceneLoader — Autoload singleton
## Swaps scenes via threaded loading, showing a loading screen in between.
## Use SceneLoader.change_scene("res://scenes/game.tscn") instead of
## get_tree().change_scene_to_file(...) everywhere in the game.
extends CanvasLayer

const C_BG     := Color(0.039, 0.039, 0.059)
const C_ACCENT := Color(0.0, 0.831, 1.0)
const MIN_DISPLAY_TIME := 0.35  # avoids an imperceptible flash on instant loads

var _overlay: ColorRect = null
var _label: Label = null
var _bar_bg: ColorRect = null
var _bar_fill: ColorRect = null

var _target_path: String = ""
var _loading: bool = false
var _elapsed: float = 0.0


func _ready() -> void:
	layer = 100
	_build_ui()
	set_process(false)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = C_BG
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.visible = false
	add_child(_overlay)

	_label = Label.new()
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 0.5
	_label.anchor_bottom = 0.5
	_label.offset_left = -200.0
	_label.offset_right = 200.0
	_label.offset_top = -60.0
	_label.offset_bottom = -10.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = "NEXUS"
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_color_override("font_color", C_ACCENT)
	_overlay.add_child(_label)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.12, 0.12, 0.2)
	_bar_bg.anchor_left = 0.5
	_bar_bg.anchor_right = 0.5
	_bar_bg.anchor_top = 0.5
	_bar_bg.anchor_bottom = 0.5
	_bar_bg.offset_left = -160.0
	_bar_bg.offset_right = 160.0
	_bar_bg.offset_top = 10.0
	_bar_bg.offset_bottom = 20.0
	_overlay.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = C_ACCENT
	_bar_fill.anchor_bottom = 1.0
	_bar_bg.add_child(_bar_fill)


func change_scene(path: String) -> void:
	if _loading:
		return
	_loading = true
	_elapsed = 0.0
	_target_path = path
	_overlay.visible = true
	_bar_fill.anchor_right = 0.0

	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("SceneLoader: failed to start loading %s (%d)" % [path, err])
		_loading = false
		_overlay.visible = false
		return

	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta

	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_target_path, progress)
	if progress.size() > 0:
		_bar_fill.anchor_right = clampf(progress[0], 0.0, 1.0)

	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			if _elapsed < MIN_DISPLAY_TIME:
				return  # keep showing briefly so it doesn't flash on instant loads
			var packed: PackedScene = ResourceLoader.load_threaded_get(_target_path)
			set_process(false)
			_loading = false
			_overlay.visible = false
			get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("SceneLoader: failed to load %s" % _target_path)
			set_process(false)
			_loading = false
			_overlay.visible = false
