## AudioManager — Autoload singleton
## Plays SFX and exposes the Master/Music/SFX bus volumes used by the
## Settings screen. Volumes are persisted via SettingsManager.
extends Node

enum SFX {
	UI_CLICK, BUILD, UPGRADE, TURRET_SHOT, ENEMY_HIT, ENEMY_DEATH,
	WAVE_START, WAVE_CLEARED, STATION_DAMAGE, GAME_OVER,
}

const SFX_PATHS := {
	SFX.UI_CLICK:       "res://assets/sfx/ui_click.wav",
	SFX.BUILD:           "res://assets/sfx/build.wav",
	SFX.UPGRADE:         "res://assets/sfx/upgrade.wav",
	SFX.TURRET_SHOT:     "res://assets/sfx/turret_shot.wav",
	SFX.ENEMY_HIT:       "res://assets/sfx/enemy_hit.wav",
	SFX.ENEMY_DEATH:     "res://assets/sfx/enemy_death.wav",
	SFX.WAVE_START:      "res://assets/sfx/wave_start.wav",
	SFX.WAVE_CLEARED:    "res://assets/sfx/wave_cleared.wav",
	SFX.STATION_DAMAGE:  "res://assets/sfx/station_damage.wav",
	SFX.GAME_OVER:       "res://assets/sfx/game_over.wav",
}

# A handful of pooled players avoids allocating a node per sound effect,
# which matters once turrets/enemies are firing/dying every frame.
const POOL_SIZE := 12

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0


func _ready() -> void:
	_ensure_buses()

	for key in SFX_PATHS:
		var stream: AudioStream = load(SFX_PATHS[key])
		_streams[key] = stream

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


func play_sfx(sfx: SFX, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sfx)
	if stream == null:
		return
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Creates the "Music" and "SFX" buses (routed to Master) if the project's
## default bus layout doesn't already have them, so Settings/AudioManager
## can rely on them existing regardless of how the project was set up.
func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


# ─── Bus volume helpers (linear 0..1 <-> dB) ────────────────────────────────────

func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.0001)


func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))
