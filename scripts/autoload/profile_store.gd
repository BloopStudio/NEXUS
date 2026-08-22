## ProfileStore — Autoload singleton
## Persists the local player's identity (name + chosen spell loadout) and a
## local scoreboard of the best waves reached, across app restarts. Purely
## local: nothing here is networked — a joining player's saved profile is
## private to their own machine.
extends Node

const SAVE_PATH := "user://profile.json"
const MAX_SCORES := 10

var player_name: String = ""
var spell_loadout: Array = []
var player_class: int = 0  # PlayerClasses.PlayerClass
## Array of {"name": String, "wave": int, "date": String}, sorted best-first.
var scores: Array = []


func _ready() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	player_name = parsed.get("player_name", "")
	spell_loadout = parsed.get("spell_loadout", [])
	player_class = parsed.get("player_class", 0)
	scores = parsed.get("scores", [])


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("ProfileStore: could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({
		"player_name": player_name,
		"spell_loadout": spell_loadout,
		"player_class": player_class,
		"scores": scores,
	}))
	f.close()


## Called from the main menu whenever the player confirms their name/loadout/
## class (host/join/solo) — keeps the save file current without needing a
## separate "save profile" action.
func set_player_info(name: String, spells: Array, player_class_id: int) -> void:
	if name == player_name and spells == spell_loadout and player_class_id == player_class:
		return
	player_name = name
	spell_loadout = spells
	player_class = player_class_id
	_save()


## Records a completed match's result into the local scoreboard, host-only
## (see game.gd's game-over handling) — only the host's own machine has an
## authoritative wave_number to trust.
func record_score(wave_reached: int) -> void:
	if wave_reached <= 0:
		return
	scores.append({
		"name": player_name if not player_name.is_empty() else "Joueur",
		"wave": wave_reached,
		"date": Time.get_date_string_from_system(),
	})
	scores.sort_custom(func(a, b): return a["wave"] > b["wave"])
	if scores.size() > MAX_SCORES:
		scores = scores.slice(0, MAX_SCORES)
	_save()


func get_top_scores() -> Array:
	return scores
