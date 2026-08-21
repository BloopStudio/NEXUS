## SettingsManager — Autoload singleton
## Persists and applies graphics/audio/control settings to user://settings.cfg.
extends Node

const SAVE_PATH := "user://settings.cfg"

const REBINDABLE_ACTIONS := ["move_up", "move_down", "move_left", "move_right", "shoot"]
const ACTION_LABELS := {
	"move_up": "Avancer", "move_down": "Reculer",
	"move_left": "Aller à gauche", "move_right": "Aller à droite",
	"shoot": "Tirer",
}

var fullscreen: bool = false
var vsync: bool = true
var window_size: Vector2i = Vector2i(1280, 720)
var show_fps: bool = false
var fps_limit: int = 0  # 0 = unlimited
const FPS_LIMIT_OPTIONS := [0, 30, 60, 120, 144]

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0

# action_name -> InputEvent (only the *first* rebound event, we keep it simple)
var _custom_binds: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_all()


# ─── Load / Save ─────────────────────────────────────────────────────────────────

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	window_size = cfg.get_value("graphics", "window_size", window_size)
	show_fps = cfg.get_value("graphics", "show_fps", show_fps)
	fps_limit = cfg.get_value("graphics", "fps_limit", fps_limit)

	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)

	for action in REBINDABLE_ACTIONS:
		var event: InputEvent = cfg.get_value("controls", action, null)
		if event != null:
			_custom_binds[action] = event


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "window_size", window_size)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("graphics", "fps_limit", fps_limit)

	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)

	for action in _custom_binds:
		cfg.set_value("controls", action, _custom_binds[action])

	cfg.save(SAVE_PATH)


# ─── Apply ─────────────────────────────────────────────────────────────────────

func apply_all() -> void:
	apply_graphics()
	apply_audio()
	apply_controls()


func apply_graphics() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if not fullscreen:
		DisplayServer.window_set_size(window_size)
	Engine.max_fps = fps_limit
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	FpsCounter.set_visible_state(show_fps)


func apply_audio() -> void:
	AudioManager.set_bus_volume("Master", master_volume)
	AudioManager.set_bus_volume("Music", music_volume)
	AudioManager.set_bus_volume("SFX", sfx_volume)


func apply_controls() -> void:
	for action in _custom_binds:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, _custom_binds[action])


## Rebinds `action` to `event` (keyboard key or mouse button), replacing any
## previous binding for it, then persists immediately.
func rebind_action(action: String, event: InputEvent) -> void:
	_custom_binds[action] = event
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	save_settings()


## Returns the first bound InputEvent for `action`, or null.
func get_action_event(action: String) -> InputEvent:
	var events := InputMap.action_get_events(action)
	return events[0] if events.size() > 0 else null
