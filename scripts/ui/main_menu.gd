## MainMenu — entry screen
## Dark neon aesthetic, drawn entirely in code (no external assets needed).
extends Control

# ─── Colors ────────────────────────────────────────────────────────────────────
const C_BG       := Color(0.039, 0.039, 0.059)
const C_ACCENT   := Color(0.0, 0.831, 1.0)       # cyan
const C_PANEL    := Color(0.08, 0.08, 0.14, 0.95)
const C_BTN      := Color(0.0, 0.4, 0.55)
const C_BTN_HOV  := Color(0.0, 0.6, 0.8)
const C_TEXT     := Color(1, 1, 1)
const C_DIM      := Color(0.6, 0.6, 0.7)
const C_ERROR    := Color(1.0, 0.3, 0.3)
const C_SUCCESS  := Color(0.3, 1.0, 0.5)

# ─── UI nodes (built in _ready) ────────────────────────────────────────────────
var _status_label: Label
var _code_input: LineEdit
var _code_display: Button
var _party_code_panel: PanelContainer
var _join_panel: PanelContainer
var _player_name_input: LineEdit
var _spell_slot_e: OptionButton
var _spell_slot_a: OptionButton
var _class_dropdown: OptionButton
var _mutator_dropdown: OptionButton
var _update_btn: Button
var _update_url: String = ""
var _scores_panel: PanelContainer
var _scores_list: VBoxContainer
var _lobby_panel: PanelContainer
var _lobby_list: VBoxContainer

# GitHub Releases API — no auth needed for a public repo's latest release.
const UPDATE_CHECK_URL := "https://api.github.com/repos/BloopStudio/NEXUS/releases/latest"

func _ready() -> void:
	_build_ui()
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.upnp_status.connect(_on_upnp_status)
	NetworkManager.stun_status.connect(_on_stun_status)
	NetworkManager.game_starting.connect(_on_game_starting)
	NetworkManager.joining_candidate.connect(_on_joining_candidate)
	NetworkManager.player_connected.connect(_on_lobby_players_changed)
	NetworkManager.player_disconnected.connect(_on_lobby_players_changed)
	NetworkManager.players_updated.connect(_on_lobby_players_changed)
	_check_for_update()


# ─── UI builder ────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Root: full-screen CanvasLayer background
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# The whole menu used to be a fixed-size box pinned to screen-center —
	# fine at the project's default 1280×720, but on a smaller/resized
	# window the "Rejoindre" panel pushed the connect button below the
	# visible area with no way to reach it. A ScrollContainer + CenterContainer
	# keeps things centered when everything fits, and scrollable instead of
	# cut off when it doesn't.
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var center_wrap := CenterContainer.new()
	center_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center_wrap)

	# Center column
	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(520, 0)
	center.add_theme_constant_override("separation", 18)
	center_wrap.add_child(center)

	# Title
	var title := Label.new()
	title.text = "NEXUS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", C_ACCENT)
	center.add_child(title)

	var sub := Label.new()
	sub.text = "Defend the station. Together."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", C_DIM)
	center.add_child(sub)

	_spacer(center, 16)

	# Player name row
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Nom : "
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_row.add_child(name_lbl)
	_player_name_input = LineEdit.new()
	_player_name_input.placeholder_text = "Joueur"
	_player_name_input.custom_minimum_size = Vector2(180, 36)
	# Reuse the name from last time if one was saved, otherwise fall back to
	# a random default like before.
	_player_name_input.text = ProfileStore.player_name if not ProfileStore.player_name.is_empty() \
		else "Joueur%d" % randi_range(1, 99)
	name_row.add_child(_player_name_input)

	_spacer(center, 8)

	# ── Class: light stat modifier + suggested starting spell ──
	var class_row := HBoxContainer.new()
	class_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(class_row)
	var class_lbl := Label.new()
	class_lbl.text = "Classe : "
	class_lbl.add_theme_color_override("font_color", C_TEXT)
	class_row.add_child(class_lbl)

	_class_dropdown = OptionButton.new()
	_class_dropdown.custom_minimum_size = Vector2(220, 36)
	var saved_class: int = ProfileStore.player_class
	var default_class_idx := 0
	for class_id in PlayerClasses.all_ids():
		var cdef: Dictionary = PlayerClasses.DEFS[class_id]
		_class_dropdown.add_item("%s %s" % [cdef["icon"], cdef["name"]])
		_class_dropdown.set_item_metadata(_class_dropdown.item_count - 1, class_id)
		_class_dropdown.set_item_tooltip(_class_dropdown.item_count - 1, cdef["desc"])
		if class_id == saved_class:
			default_class_idx = _class_dropdown.item_count - 1
	_class_dropdown.selected = default_class_idx
	_class_dropdown.item_selected.connect(_on_class_selected)
	class_row.add_child(_class_dropdown)

	_spacer(center, 8)

	# ── Mutator: host-picked, whole-run station modifier (like a roguelite
	# seed) — only matters when hosting; a joiner's own pick is ignored, the
	# host's choice is what gets broadcast to everyone at match start.
	var mutator_row := HBoxContainer.new()
	mutator_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(mutator_row)
	var mutator_lbl := Label.new()
	mutator_lbl.text = "Modificateur (hôte) : "
	mutator_lbl.add_theme_color_override("font_color", C_TEXT)
	mutator_row.add_child(mutator_lbl)

	_mutator_dropdown = OptionButton.new()
	_mutator_dropdown.custom_minimum_size = Vector2(220, 36)
	for mutator_id in Mutators.all_ids():
		var mdef: Dictionary = Mutators.DEFS[mutator_id]
		_mutator_dropdown.add_item("%s %s" % [mdef["icon"], mdef["name"]])
		_mutator_dropdown.set_item_metadata(_mutator_dropdown.item_count - 1, mutator_id)
		_mutator_dropdown.set_item_tooltip(_mutator_dropdown.item_count - 1, mdef["desc"])
	_mutator_dropdown.selected = 0
	mutator_row.add_child(_mutator_dropdown)

	_spacer(center, 8)

	# ── Loadout: which spell goes on which key ──
	# Two independent dropdowns, not a fixed pairing — the player can put any
	# spell on either key, or even pick the same one twice.
	var loadout_lbl := Label.new()
	loadout_lbl.text = "Sorts (touches E / A) :"
	loadout_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_lbl.add_theme_color_override("font_color", C_DIM)
	loadout_lbl.add_theme_font_size_override("font_size", 13)
	center.add_child(loadout_lbl)

	var loadout_row := HBoxContainer.new()
	loadout_row.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout_row.add_theme_constant_override("separation", 10)
	center.add_child(loadout_row)

	# Reuse the loadout from last time if one was saved.
	var saved_loadout: Array = ProfileStore.spell_loadout
	var default_e: String = saved_loadout[0] if saved_loadout.size() == 2 else Spells.DEFAULT_LOADOUT[0]
	var default_a: String = saved_loadout[1] if saved_loadout.size() == 2 else Spells.DEFAULT_LOADOUT[1]
	_spell_slot_e = _make_spell_dropdown("E : ", default_e)
	loadout_row.add_child(_spell_slot_e.get_parent())
	_spell_slot_a = _make_spell_dropdown("A : ", default_a)
	loadout_row.add_child(_spell_slot_a.get_parent())

	_spacer(center, 8)

	# ── Buttons ──
	var btn_host := _make_button("🛡  Héberger une partie")
	btn_host.pressed.connect(_on_host_pressed)
	center.add_child(btn_host)

	var btn_join := _make_button("🔗  Rejoindre avec un code")
	btn_join.pressed.connect(_on_join_pressed)
	center.add_child(btn_join)

	var btn_solo := _make_button("🤖  Solo (test local)")
	btn_solo.pressed.connect(_on_solo_pressed)
	center.add_child(btn_solo)

	var btn_settings := _make_button("⚙  Réglages")
	btn_settings.pressed.connect(_on_settings_pressed)
	center.add_child(btn_settings)

	var btn_scores := _make_button("🏆  Classement local")
	btn_scores.pressed.connect(_on_scores_pressed)
	center.add_child(btn_scores)

	_spacer(center, 8)

	# ── Leaderboard panel (hidden until opened) ──
	_scores_panel = PanelContainer.new()
	_scores_panel.visible = false
	center.add_child(_scores_panel)
	_scores_list = VBoxContainer.new()
	_scores_list.add_theme_constant_override("separation", 4)
	_scores_panel.add_child(_scores_list)

	# ── Party code display (host) ──
	_party_code_panel = PanelContainer.new()
	_party_code_panel.visible = false
	center.add_child(_party_code_panel)
	var pc_vbox := VBoxContainer.new()
	_party_code_panel.add_child(pc_vbox)
	var pc_lbl := Label.new()
	pc_lbl.text = "Code de partie (clique dessus pour le copier) :"
	pc_lbl.add_theme_color_override("font_color", C_DIM)
	pc_lbl.add_theme_font_size_override("font_size", 13)
	pc_vbox.add_child(pc_lbl)
	_code_display = Button.new()
	_code_display.flat = true
	_code_display.clip_text = false
	_code_display.custom_minimum_size = Vector2(0, 40)
	_code_display.add_theme_font_size_override("font_size", 18)
	_code_display.add_theme_color_override("font_color", C_ACCENT)
	_code_display.add_theme_color_override("font_hover_color", C_ACCENT.lightened(0.3))
	_code_display.tooltip_text = "Cliquer pour copier"
	_code_display.pressed.connect(_on_code_display_pressed)
	pc_vbox.add_child(_code_display)
	var btn_start := _make_button("▶  Démarrer la partie")
	btn_start.pressed.connect(_on_start_pressed)
	pc_vbox.add_child(btn_start)

	# ── Join code input ──
	_join_panel = PanelContainer.new()
	_join_panel.visible = false
	center.add_child(_join_panel)
	var join_vbox := VBoxContainer.new()
	_join_panel.add_child(join_vbox)
	var join_lbl := Label.new()
	join_lbl.text = "Entre le code de partie :"
	join_lbl.add_theme_color_override("font_color", C_DIM)
	join_vbox.add_child(join_lbl)
	_code_input = LineEdit.new()
	_code_input.placeholder_text = "Code Base64..."
	_code_input.custom_minimum_size = Vector2(380, 38)
	join_vbox.add_child(_code_input)

	var note := Label.new()
	note.text = "ℹ  Le code fourni par l'hôte suffit — aucune manip réseau\n    n'est nécessaire dans la grande majorité des cas."
	note.add_theme_color_override("font_color", C_DIM)
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	join_vbox.add_child(note)

	var btn_connect := _make_button("🔌  Se connecter")
	btn_connect.pressed.connect(_on_connect_pressed)
	join_vbox.add_child(btn_connect)

	# ── Lobby player list — shared by both the host (right after hosting)
	# and a joiner (right after connecting), so everyone sees who's already
	# in the party before the match actually starts, not just once in-game.
	_lobby_panel = PanelContainer.new()
	_lobby_panel.visible = false
	center.add_child(_lobby_panel)
	var lobby_vbox := VBoxContainer.new()
	lobby_vbox.add_theme_constant_override("separation", 4)
	_lobby_panel.add_child(lobby_vbox)
	var lobby_lbl := Label.new()
	lobby_lbl.text = "Joueurs dans la partie :"
	lobby_lbl.add_theme_color_override("font_color", C_DIM)
	lobby_lbl.add_theme_font_size_override("font_size", 13)
	lobby_vbox.add_child(lobby_lbl)
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 3)
	lobby_vbox.add_child(_lobby_list)

	# ── Status label ──
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", C_DIM)
	var game_version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	_status_label.text = "BloopStudio — v%s" % game_version
	center.add_child(_status_label)

	# ── Update banner — hidden until a newer release is actually found ──
	_update_btn = Button.new()
	_update_btn.visible = false
	_update_btn.flat = true
	_update_btn.custom_minimum_size = Vector2(380, 32)
	_update_btn.add_theme_font_size_override("font_size", 13)
	_update_btn.add_theme_color_override("font_color", C_SUCCESS)
	_update_btn.pressed.connect(_on_update_pressed)
	center.add_child(_update_btn)


# ─── Button callbacks ───────────────────────────────────────────────────────────
func _on_host_pressed() -> void:
	_apply_player_name()
	_upnp_done = false
	_upnp_success = false
	_stun_done = false
	_stun_success = false
	var err := NetworkManager.host_game()
	if err != OK:
		_set_status("Erreur : impossible d'ouvrir le port 7777.", C_ERROR)
		return
	var code := NetworkManager.get_party_code()
	_code_display.text = code
	_party_code_panel.visible = true
	_join_panel.visible = false
	_lobby_panel.visible = true
	_refresh_lobby_list()
	_set_status("Ouverture automatique du port…", C_DIM)


## UPnP and STUN discovery run in parallel on separate threads and can finish
## in either order — both feed into the same party code, so either one
## arriving refreshes the displayed code and status message.
var _upnp_done := false
var _upnp_success := false
var _stun_done := false
var _stun_success := false

func _on_upnp_status(success: bool) -> void:
	_upnp_done = true
	_upnp_success = success
	_refresh_connectivity_status()


func _on_stun_status(success: bool) -> void:
	_stun_done = true
	_stun_success = success
	_refresh_connectivity_status()


func _refresh_connectivity_status() -> void:
	if not _party_code_panel.visible:
		return
	_code_display.text = NetworkManager.get_party_code()

	if _upnp_success:
		_set_status("Prêt ! Partage juste le code — aucune manip requise.", C_SUCCESS)
	elif _stun_success:
		_set_status("Port non ouvert automatiquement, mais une adresse alternative a été trouvée — le code a de bonnes chances de fonctionner quand même.", C_SUCCESS)
	elif _upnp_done and _stun_done:
		_set_status("Routeur incompatible UPnP et adresse non joignable détectée : le code ne marchera qu'en réseau local, sauf si tu ouvres le port 7777 (UDP) toi-même.", C_ERROR)
	else:
		_set_status("Ouverture automatique du port…", C_DIM)


func _on_join_pressed() -> void:
	_join_panel.visible = not _join_panel.visible
	_party_code_panel.visible = false


func _on_solo_pressed() -> void:
	_apply_player_name()
	NetworkManager.host_game()
	GameState.reset(_get_selected_mutator())
	SceneLoader.change_scene("res://scenes/game.tscn")


func _on_code_display_pressed() -> void:
	if _code_display.text.is_empty():
		return
	DisplayServer.clipboard_set(_code_display.text)
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	_set_status("Code copié dans le presse-papiers !", C_SUCCESS)


func _on_scores_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	_scores_panel.visible = not _scores_panel.visible
	if not _scores_panel.visible:
		return

	for child in _scores_list.get_children():
		child.queue_free()

	var top: Array = ProfileStore.get_top_scores()
	if top.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Aucune partie hébergée pour l'instant."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", C_DIM)
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_scores_list.add_child(empty_lbl)
		return

	var header := Label.new()
	header.text = "Meilleures vagues atteintes (parties hébergées ici) :"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", C_DIM)
	header.add_theme_font_size_override("font_size", 12)
	_scores_list.add_child(header)

	for i in top.size():
		var entry: Dictionary = top[i]
		var row := Label.new()
		row.text = "%d. %s — Vague %d (%s)" % [i + 1, entry.get("name", "?"), entry.get("wave", 0), entry.get("date", "")]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", C_ACCENT if i == 0 else C_TEXT)
		_scores_list.add_child(row)


func _on_settings_pressed() -> void:
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	var settings_script = load("res://scripts/ui/settings_menu.gd")
	var settings: Control = settings_script.new()
	settings.closed.connect(func(): settings.queue_free())
	add_child(settings)


func _on_start_pressed() -> void:
	if NetworkManager.get_player_count() < 1:
		_set_status("En attente d'au moins un joueur…", C_ERROR)
		return
	NetworkManager.start_game(_get_selected_mutator())


func _on_connect_pressed() -> void:
	_apply_player_name()
	var code := _code_input.text.strip_edges()
	if code.is_empty():
		_set_status("Entre un code de partie.", C_ERROR)
		return
	_set_status("Connexion en cours…", C_DIM)
	var err := NetworkManager.join_with_code(code)
	if err != OK:
		_set_status("Code invalide.", C_ERROR)


func _on_connection_succeeded() -> void:
	_set_status("Connecté ! En attente du démarrage…", C_SUCCESS)
	_lobby_panel.visible = true
	_refresh_lobby_list()


## The joiner tries each address the party code carries (UPnP-mapped, STUN-
## discovered, LAN) in turn — surface which one is currently being tried
## instead of a single unmoving "Connexion en cours…" for up to ~15s.
func _on_joining_candidate(index: int, total: int, _ip: String) -> void:
	if total <= 1:
		_set_status("Connexion en cours…", C_DIM)
	else:
		_set_status("Connexion en cours… (essai %d/%d)" % [index + 1, total], C_DIM)


func _on_connection_failed() -> void:
	_set_status("Connexion échouée (délai dépassé). Vérifie le code, ou l'hôte n'est " +
		"pas joignable depuis internet (pare-feu, ou routeur/box en CGNAT — dans ce " +
		"cas, seul le réseau local de l'hôte peut se connecter).", C_ERROR)


func _on_game_starting(mutator: int) -> void:
	GameState.reset(mutator)
	SceneLoader.change_scene("res://scenes/game.tscn")


# ─── Update check ───────────────────────────────────────────────────────────────
# NEXUS has no update server of its own (just GitHub Releases), so this can't
# silently download-and-swap the running binary — instead it checks the
# latest release on startup and, if it's newer, shows a button that opens the
# download page in the browser. Versions are "0.1.<commit count>", so the
# comparison is just the trailing number.

func _check_for_update() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_update_check_completed)
	# Best-effort: a failed/offline check just leaves the banner hidden.
	http.request(UPDATE_CHECK_URL, ["User-Agent: NEXUS-Game"])


func _on_update_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("tag_name"):
		return

	var latest_tag: String = parsed["tag_name"]  # e.g. "v0.1.42"
	var latest_patch := latest_tag.trim_prefix("v").get_slice(".", 2) if latest_tag.count(".") >= 2 else ""
	var current_version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var current_patch := current_version.get_slice(".", 2) if current_version.count(".") >= 2 else ""
	if not latest_patch.is_valid_int() or not current_patch.is_valid_int():
		return

	if latest_patch.to_int() > current_patch.to_int():
		_update_url = parsed.get("html_url", "https://github.com/BloopStudio/NEXUS/releases/latest")
		_update_btn.text = "⬇ Nouvelle version %s disponible — cliquer pour télécharger" % latest_tag
		_update_btn.visible = true


func _on_update_pressed() -> void:
	if not _update_url.is_empty():
		OS.shell_open(_update_url)


# ─── Helpers ───────────────────────────────────────────────────────────────────


func _apply_player_name() -> void:
	var n := _player_name_input.text.strip_edges()
	if n.is_empty():
		n = "Joueur"
	var spells: Array = [
		_spell_slot_e.get_item_metadata(_spell_slot_e.selected),
		_spell_slot_a.get_item_metadata(_spell_slot_a.selected),
	]
	var player_class: int = _class_dropdown.get_item_metadata(_class_dropdown.selected)
	NetworkManager.local_player_info["name"] = n
	NetworkManager.local_player_info["spells"] = spells
	NetworkManager.local_player_info["class"] = player_class
	ProfileStore.set_player_info(n, spells, player_class)


## Suggests (doesn't force) the newly picked class's default spell on slot E
## — the two spell dropdowns stay fully independent, the player can still
## change it right after.
## Rebuilds the lobby's live player list — connected to player_connected/
## player_disconnected/players_updated, so it stays current whether someone
## just joined, left, or merely had a detail (ping, name) refresh, for both
## the host (right after hosting) and a joiner (right after connecting).
func _on_lobby_players_changed(_arg = null) -> void:
	_refresh_lobby_list()


func _refresh_lobby_list() -> void:
	for child in _lobby_list.get_children():
		child.queue_free()
	var local_id := -1
	if multiplayer.multiplayer_peer != null:
		local_id = multiplayer.get_unique_id()
	var ids: Array = NetworkManager.players.keys()
	ids.sort()
	for peer_id in ids:
		var info: Dictionary = NetworkManager.players[peer_id]
		var row := Label.new()
		var tags := ""
		if peer_id == 1:
			tags += " 👑"
		if peer_id == local_id:
			tags += " (toi)"
		row.text = "●  %s%s" % [info.get("name", "Joueur"), tags]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", info.get("color", C_TEXT))
		_lobby_list.add_child(row)


func _get_selected_mutator() -> int:
	return _mutator_dropdown.get_item_metadata(_mutator_dropdown.selected)


func _on_class_selected(index: int) -> void:
	var class_id: int = _class_dropdown.get_item_metadata(index)
	var suggested: String = PlayerClasses.DEFS[class_id]["default_spell"]
	for i in _spell_slot_e.item_count:
		if _spell_slot_e.get_item_metadata(i) == suggested:
			_spell_slot_e.selected = i
			break


## Builds a "<label> [dropdown]" pair listing every spell — returns the
## OptionButton; its parent HBoxContainer is what actually gets added to the
## tree (see caller).
func _make_spell_dropdown(label_text: String, default_id: String) -> OptionButton:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", C_TEXT)
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(170, 32)
	var default_idx := 0
	for id in Spells.all_ids():
		var def: Dictionary = Spells.DEFS[id]
		opt.add_item("%s %s" % [def["icon"], def["name"]])
		opt.set_item_metadata(opt.item_count - 1, id)
		if id == default_id:
			default_idx = opt.item_count - 1
	opt.selected = default_idx
	row.add_child(opt)
	return opt


func _set_status(text: String, color: Color = C_DIM) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(380, 48)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.pressed.connect(func(): AudioManager.play_sfx(AudioManager.SFX.UI_CLICK))
	return btn


func _spacer(parent: Control, height: int) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	parent.add_child(sp)
