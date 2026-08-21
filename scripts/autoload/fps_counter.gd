## FpsCounter — Autoload singleton
## Small always-on-top FPS readout, toggled from Settings > Graphismes.
extends CanvasLayer

var _label: Label = null


func _ready() -> void:
	layer = 200
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.offset_left = -90.0
	_label.offset_right = -8.0
	_label.offset_top = 8.0
	_label.offset_bottom = 28.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_label.visible = false
	add_child(_label)
	set_process(false)


func set_visible_state(shown: bool) -> void:
	_label.visible = shown
	set_process(shown)


func _process(_delta: float) -> void:
	_label.text = "%d FPS" % Engine.get_frames_per_second()
