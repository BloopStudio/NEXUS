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

func _ready() -> void:
	_build_ui()
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.upnp_status.connect(_on_upnp_status)
	NetworkManager.game_starting.connect(_on_game_starting)


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

	# Center column
	var center := VBoxContainer.new()
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = -260.0
	center.offset_right  = 260.0
	center.offset_top  = -320.0
	center.offset_bottom = 320.0
	center.add_theme_constant_override("separation", 18)
	add_child(center)

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
	_player_name_input.text = "Joueur%d" % randi_range(1, 99)
	name_row.add_child(_player_name_input)

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

	_spacer(center, 8)

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
	_code_display.autowrap_mode = TextServer.AUTOWRAP_WORD
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

	# ── Status label ──
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", C_DIM)
	_status_label.text = "v0.1.0 — Godot 4 — ENet P2P"
	center.add_child(_status_label)


# ─── Button callbacks ───────────────────────────────────────────────────────────
func _on_host_pressed() -> void:
	_apply_player_name()
	var err := NetworkManager.host_game()
	if err != OK:
		_set_status("Erreur : impossible d'ouvrir le port 7777.", C_ERROR)
		return
	var code := NetworkManager.get_party_code()
	_code_display.text = code
	_party_code_panel.visible = true
	_join_panel.visible = false
	_set_status("Ouverture automatique du port…", C_DIM)


func _on_upnp_status(success: bool) -> void:
	if not _party_code_panel.visible:
		return
	# The public IP may only be known once UPnP finishes — refresh the code.
	_code_display.text = NetworkManager.get_party_code()
	if success:
		_set_status("Prêt ! Partage juste le code — aucune manip requise.", C_SUCCESS)
	else:
		_set_status("Routeur incompatible UPnP : le code ne marchera qu'en réseau local, sauf si tu ouvres le port 7777 (UDP) toi-même.", C_ERROR)


func _on_join_pressed() -> void:
	_join_panel.visible = not _join_panel.visible
	_party_code_panel.visible = false


func _on_solo_pressed() -> void:
	_apply_player_name()
	NetworkManager.host_game()
	GameState.reset()
	SceneLoader.change_scene("res://scenes/game.tscn")


func _on_code_display_pressed() -> void:
	if _code_display.text.is_empty():
		return
	DisplayServer.clipboard_set(_code_display.text)
	AudioManager.play_sfx(AudioManager.SFX.UI_CLICK)
	_set_status("Code copié dans le presse-papiers !", C_SUCCESS)


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
	NetworkManager.start_game()


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


func _on_connection_failed() -> void:
	_set_status("Connexion échouée. Vérifie le code et le port.", C_ERROR)


func _on_game_starting() -> void:
	GameState.reset()
	SceneLoader.change_scene("res://scenes/game.tscn")


# ─── Helpers ───────────────────────────────────────────────────────────────────


func _apply_player_name() -> void:
	var n := _player_name_input.text.strip_edges()
	if n.is_empty():
		n = "Joueur"
	NetworkManager.local_player_info["name"] = n


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
