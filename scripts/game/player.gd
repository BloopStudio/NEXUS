## Player — controllable character for each connected peer
## Can move, manually shoot enemies, and interact with modules.
extends Node2D

const SPEED          := 180.0
const SHOOT_RANGE    := 220.0
const SHOOT_COOLDOWN := 0.6
const BULLET_SPEED   := 350.0
const BULLET_DAMAGE  := 12.0

const ABILITY_PULSE_DURATION := 0.4

const C_PLAYER  := Color(0.0, 0.831, 1.0)
const C_OUTLINE := Color(1.0, 1.0, 1.0, 0.5)

## The two spells picked in the main-menu loadout screen (see
## Spells.DEFAULT_LOADOUT for the fallback), bound respectively to the
## "ability" (E) and "ability_2" (A) input actions — not fixed to a single
## spell, the player chooses which spell sits in which slot before the match.
var equipped_spells: Array = Spells.DEFAULT_LOADOUT.duplicate()
## Independent level (1-3) per equipped slot — see Spells.get_scaled_def().
var spell_levels: Array[int] = [1, 1]

var player_class: int = PlayerClasses.DEFAULT_CLASS

# ─── Health / downed state ──────────────────────────────────────────────────
# Contact with an enemy (they're pathing through/near you toward the
# station) now actually costs something — being reduced to 0 HP doesn't end
# the match (only the station losing all its HP does), it "downs" you:
# no movement/shooting/casting until a teammate revives you nearby, or —
# so a solo player or an abandoned teammate is never stuck forever —
# AUTO_REVIVE_TIME passes and you get back up on your own at reduced HP.
const CONTACT_INVULN_TIME := 1.0
const REVIVE_RADIUS := 50.0
const REVIVE_HOLD_TIME := 2.5
const AUTO_REVIVE_TIME := 20.0
const REVIVE_HP_RATIO := 0.5
const AUTO_REVIVE_HP_RATIO := 0.25

var max_hp: float = 100.0
var hp: float = 100.0
var is_downed: bool = false
var _invuln_timer: float = 0.0
var _down_timer: float = 0.0
## How long the LOCAL player has been standing near a downed teammate,
## accumulated toward REVIVE_HOLD_TIME.
var _revive_progress: float = 0.0

@export var peer_id: int = 1
var player_name: String = "Player"
var player_color: Color = C_PLAYER

var _shoot_timer: float = 0.0
## slot index (0 or 1) -> seconds of cooldown remaining, keyed the same way
## as equipped_spells so the HUD can read both in lockstep.
var _spell_cooldowns: Array[float] = [0.0, 0.0]
var _ability_pulse: float = 0.0
var _pulse_color: Color = C_PLAYER
var _pulse_radius: float = 60.0
var _dash_timer: float = 0.0
var _is_local: bool = false


func _ready() -> void:
	_is_local = (peer_id == multiplayer.get_unique_id())
	max_hp = PlayerClasses.DEFS[player_class]["max_hp"]
	hp = max_hp
	add_to_group("players")
	# _process only ticks cosmetic timers (ability pulse animation) and
	# redraws — needs to run for every peer's copy so remote players' ability
	# bursts animate for observers too, not just the player who used it.
	set_process(true)
	set_physics_process(_is_local)


func _process(delta: float) -> void:
	_shoot_timer -= delta
	for i in _spell_cooldowns.size():
		if _spell_cooldowns[i] > 0.0:
			_spell_cooldowns[i] -= delta
	if _ability_pulse > 0.0:
		_ability_pulse -= delta
	if _dash_timer > 0.0:
		_dash_timer -= delta
	if _invuln_timer > 0.0:
		_invuln_timer -= delta

	# Auto-revive fallback (host-only, authoritative) — no teammate needed.
	if is_downed and NetworkManager.is_host():
		_down_timer += delta
		if _down_timer >= AUTO_REVIVE_TIME:
			_apply_revive(AUTO_REVIVE_HP_RATIO)

	# Revive-by-proximity: only the LOCAL, non-downed player checks this —
	# each client only really "knows" its own position well (others are
	# replicated over the network), and only they can request their own
	# revive-assist action.
	if _is_local and not is_downed:
		var nearest_downed: Node2D = null
		var nearest_dist := REVIVE_RADIUS
		for p in get_tree().get_nodes_in_group("players"):
			if p != self and p.is_downed:
				var d := global_position.distance_to(p.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest_downed = p
		if nearest_downed != null:
			_revive_progress += delta
			if _revive_progress >= REVIVE_HOLD_TIME:
				_revive_progress = 0.0
				_request_revive_rpc.rpc_id(1, nearest_downed.peer_id)
		else:
			_revive_progress = maxf(0.0, _revive_progress - delta * 2.0)

	# Aim indicator
	queue_redraw()


func _physics_process(delta: float) -> void:
	if is_downed:
		return

	# WASD / Arrow keys movement
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var speed := SPEED * (Spells.DEFS[Spells.DASH]["speed_mult"] if _dash_timer > 0.0 else 1.0)
		var new_pos := global_position + dir * speed * delta
		# Keep within arena bounds
		new_pos = new_pos.clamp(Vector2(-420, -420), Vector2(420, 420))
		_move_rpc.rpc(new_pos)

	# Shoot (default: left click, rebindable in Settings)
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0:
		_shoot_timer = SHOOT_COOLDOWN
		var target := get_global_mouse_position()
		_shoot_rpc.rpc(target)

	# Spell slots: "ability" (default E) and "ability_2" (default A)
	if Input.is_action_just_pressed("ability"):
		_try_cast(0)
	if Input.is_action_just_pressed("ability_2"):
		_try_cast(1)


func _try_cast(slot: int) -> void:
	if slot >= equipped_spells.size():
		return
	if _spell_cooldowns[slot] > 0.0:
		return
	var spell_id: String = equipped_spells[slot]
	var scaled := Spells.get_scaled_def(spell_id, spell_levels[slot])
	_spell_cooldowns[slot] = scaled["cooldown"]
	_cast_spell_rpc.rpc(spell_id, spell_levels[slot])


## Returns [spell_id, remaining_cooldown, max_cooldown, level] for the given
## slot, used by the HUD to draw the two spell icons. Empty array if unset.
func get_spell_slot_info(slot: int) -> Array:
	if slot >= equipped_spells.size():
		return []
	var spell_id: String = equipped_spells[slot]
	var level: int = spell_levels[slot]
	var cd: float = Spells.get_scaled_def(spell_id, level)["cooldown"]
	return [spell_id, maxf(0.0, _spell_cooldowns[slot]), cd, level]


## Spends team energy (host-authoritative, like building a module) to raise
## one equipped spell by a level — only available during BUILD/UPGRADE, same
## rhythm as everything else you spend energy on.
func request_level_up_spell(slot: int) -> void:
	if GameState.phase != GameState.Phase.BUILD and GameState.phase != GameState.Phase.UPGRADE:
		return
	if NetworkManager.is_host():
		_level_up_spell(slot)
	else:
		_request_level_up_rpc.rpc_id(1, slot)


func _level_up_spell(slot: int) -> void:
	if slot >= spell_levels.size():
		return
	var level: int = spell_levels[slot]
	if level >= Spells.MAX_LEVEL:
		return
	if not GameState.spend_energy(Spells.LEVEL_UP_COST[level]):
		return
	_sync_spell_level_rpc.rpc(slot, level + 1)


## True if `sender_id` is allowed to drive THIS player's own node: either
## its own owning peer, or a local (non-networked) call — Godot reports
## sender 0 for a call_local invocation triggered by the node's own peer.
## Any OTHER peer calling one of this node's "any_peer" RPCs is spoofing a
## different player and must be rejected — without this, any connected
## client could fake another player's movement, spell casts, bullet
## damage, or instant revives.
func _is_own_action(sender_id: int) -> bool:
	return sender_id == 0 or sender_id == peer_id


@rpc("any_peer", "reliable")
func _request_level_up_rpc(slot: int) -> void:
	if not NetworkManager.is_host():
		return
	if not _is_own_action(multiplayer.get_remote_sender_id()):
		return
	_level_up_spell(slot)


@rpc("authority", "call_local", "reliable")
func _sync_spell_level_rpc(slot: int, level: int) -> void:
	if slot < spell_levels.size():
		spell_levels[slot] = level
		AudioManager.play_sfx(AudioManager.SFX.UPGRADE, 2.0)


@rpc("any_peer", "call_local", "unreliable")
func _move_rpc(pos: Vector2) -> void:
	if not _is_own_action(multiplayer.get_remote_sender_id()):
		return
	global_position = pos
	queue_redraw()


## Plays the cast visual/audio on every peer, and — same pattern as
## bullets/mines — applies the actual gameplay effect host-side only.
## `level` comes from the caster's own spell_levels at the moment they cast,
## so every peer (including the host applying the effect) uses the exact
## same scaled numbers without needing to separately track each player's
## levels.
@rpc("any_peer", "call_local", "reliable")
func _cast_spell_rpc(spell_id: String, level: int) -> void:
	if not _is_own_action(multiplayer.get_remote_sender_id()):
		return
	if not Spells.DEFS.has(spell_id):
		return
	var def: Dictionary = Spells.get_scaled_def(spell_id, level)
	_pulse_color = def["color"]
	_pulse_radius = def.get("radius", 60.0)
	AudioManager.play_sfx(AudioManager.SFX.UPGRADE, 2.0)
	queue_redraw()

	match spell_id:
		Spells.DASH:
			_dash_timer = def["duration"]
		_:
			_ability_pulse = ABILITY_PULSE_DURATION

	if not NetworkManager.is_host():
		return

	match spell_id:
		Spells.SHOCKWAVE:
			var parent := get_parent()
			if parent != null and parent.has_method("get_enemies_in_radius"):
				var dmg: float = def["damage"] * GameState.get_player_damage_multiplier() * PlayerClasses.DEFS[player_class]["damage_mult"]
				for enemy in parent.get_enemies_in_radius(global_position, def["radius"]):
					enemy.take_damage(dmg)
					GameState.record_damage(dmg)
		Spells.HEAL:
			GameState.heal_station(def["amount"])
		Spells.SLOW:
			var parent := get_parent()
			if parent != null and parent.has_method("get_enemies_in_radius"):
				for enemy in parent.get_enemies_in_radius(global_position, def["radius"]):
					if enemy.has_method("apply_slow"):
						enemy.apply_slow(def["slow_factor"], def["duration"])
		Spells.DASH:
			pass  # movement-only, handled above on every peer


# ─── Health / downed / revive ───────────────────────────────────────────────

## Host-authoritative: called from enemy_base.gd when an enemy's path brings
## it into contact with this player (incidental — enemies still path toward
## the station, not players; this is what happens if you're standing in the
## way). A brief invulnerability window after each hit stops one lingering
## enemy from melting a player every single frame it stays in contact.
func take_contact_damage(amount: float) -> void:
	if not NetworkManager.is_host() or is_downed or _invuln_timer > 0.0:
		return
	_invuln_timer = CONTACT_INVULN_TIME
	var new_hp := maxf(0.0, hp - amount)
	var downed := new_hp <= 0.0
	if downed:
		_down_timer = 0.0
	_sync_hp_rpc.rpc(new_hp, downed)


func _apply_revive(hp_ratio: float) -> void:
	_sync_hp_rpc.rpc(max_hp * hp_ratio, false)


@rpc("authority", "call_local", "reliable")
func _sync_hp_rpc(new_hp: float, downed: bool) -> void:
	var was_downed := is_downed
	hp = new_hp
	is_downed = downed
	if downed and not was_downed:
		AudioManager.play_sfx(AudioManager.SFX.STATION_DAMAGE, -2.0)
	elif was_downed and not downed:
		AudioManager.play_sfx(AudioManager.SFX.UPGRADE, 3.0)
	queue_redraw()


## Sent by a nearby teammate (see _process's proximity check) once they've
## held position near this downed player for REVIVE_HOLD_TIME. Runs on THIS
## player's own node (deterministic "Player_<id>" naming routes it there on
## every peer), so the host-side handler can validate/apply directly.
@rpc("any_peer", "reliable")
func _request_revive_rpc(downed_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	# The client only checks proximity/hold-time locally before sending
	# this — re-validate both here, otherwise any peer could revive anyone
	# from anywhere with a single spoofed call.
	if not _is_own_action(multiplayer.get_remote_sender_id()):
		return
	if is_downed:
		return
	var game := get_parent()
	if game == null or not game.has_method("get_player_by_peer"):
		return
	var downed: Node2D = game.get_player_by_peer(downed_peer_id)
	if downed == null or not downed.is_downed:
		return
	if global_position.distance_to(downed.global_position) > REVIVE_RADIUS:
		return
	downed._apply_revive(REVIVE_HP_RATIO)


## `damage` is NOT taken from the caller — a client could otherwise fire a
## bullet with an arbitrary damage value baked in. It's recomputed here from
## this node's own (host-known) class/skill/module state instead, which
## every peer already has a consistent copy of.
@rpc("any_peer", "call_local", "reliable")
func _shoot_rpc(target_pos: Vector2) -> void:
	if not _is_own_action(multiplayer.get_remote_sender_id()):
		return
	var dmg: float = BULLET_DAMAGE * GameState.get_player_damage_multiplier() * PlayerClasses.DEFS[player_class]["damage_mult"]
	var bullet := _Bullet.new()
	bullet.global_position = global_position
	bullet.direction = (target_pos - global_position).normalized()
	bullet.damage = dmg
	get_parent().add_child(bullet)
	queue_redraw()


func _draw() -> void:
	# Downed: grayed-out body + a status ring showing revive progress from
	# whichever nearby teammate is reviving (if any) instead of the normal
	# body/aim/name rendering.
	if is_downed:
		draw_circle(Vector2.ZERO, 12.0, Color(0.3, 0.3, 0.35))
		draw_arc(Vector2.ZERO, 12.0, 0, TAU, 28, Color(0.6, 0.6, 0.65), 2.0, true)
		draw_line(Vector2(-7, -7), Vector2(7, 7), Color(1.0, 0.3, 0.3), 2.0)
		draw_line(Vector2(-7, 7), Vector2(7, -7), Color(1.0, 0.3, 0.3), 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-30, -20), "À TERRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.4, 0.4))
		return

	# Faint pulsing ring while reviving a nearby downed teammate.
	if _is_local and _revive_progress > 0.0:
		var revive_ratio := clampf(_revive_progress / REVIVE_HOLD_TIME, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 22.0, -PI / 2, -PI / 2 + TAU * revive_ratio, 24, Color(0.3, 1.0, 0.5), 2.5)

	# Brief white flash while contact-damage invulnerability is active, so
	# getting hit reads clearly even though nothing else changes visually.
	var body_color := player_color
	if _invuln_timer > 0.0 and int(_invuln_timer * 12.0) % 2 == 0:
		body_color = Color.WHITE

	# Soft outer glow so players read clearly against the background grid.
	draw_circle(Vector2.ZERO, 17.0, Color(player_color.r, player_color.g, player_color.b, 0.12))

	# Body: shaded circle + bright rim + a small highlight for some depth.
	draw_circle(Vector2.ZERO, 12.0, body_color.darkened(0.35))
	draw_circle(Vector2(-4.0, -4.0), 4.0, body_color.lightened(0.5).lerp(Color.WHITE, 0.3) * Color(1, 1, 1, 0.55))
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 28, body_color, 2.0, true)

	# HP bar — only shown once damaged, so an untouched player doesn't
	# clutter the view with a bar that's always full.
	if hp < max_hp:
		var ratio := hp / max_hp
		var bar_w := 26.0
		draw_rect(Rect2(-bar_w / 2.0, -22.0, bar_w, 3.0), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(-bar_w / 2.0, -22.0, bar_w * ratio, 3.0),
			Color(0.2, 1.0, 0.3) if ratio > 0.4 else Color(1.0, 0.4, 0.1))

	# Aim direction: gun barrel + line (toward mouse, only for the local
	# player — remote players' aim isn't networked, only their position).
	if _is_local:
		var aim_dir := to_local(get_global_mouse_position()).normalized()
		var aim := aim_dir * 18.0
		draw_line(Vector2.ZERO, aim, player_color.lightened(0.4), 1.5, true)
		var barrel_base := aim_dir * 10.0
		var perp := Vector2(-aim_dir.y, aim_dir.x) * 2.0
		draw_polygon(PackedVector2Array([
			barrel_base + perp, barrel_base - perp,
			aim_dir * 20.0 - perp, aim_dir * 20.0 + perp,
		]), [Color(0.85, 0.85, 0.9)])

	# Spell cast pulse — expanding, fading ring on every peer that sees it,
	# colored per-spell so Heal/Slow/Shockwave read differently at a glance.
	if _ability_pulse > 0.0:
		var progress := 1.0 - clampf(_ability_pulse / ABILITY_PULSE_DURATION, 0.0, 1.0)
		draw_arc(Vector2.ZERO, _pulse_radius * progress, 0, TAU, 40,
			Color(_pulse_color.r, _pulse_color.g, _pulse_color.b, 1.0 - progress), 3.0, true)

	# Dash trail — glowing rim while the speed boost is active.
	if _dash_timer > 0.0:
		draw_arc(Vector2.ZERO, 15.0, 0, TAU, 24, Spells.DEFS[Spells.DASH]["color"], 3.0, true)

	# Name tag — centered above the player, with a backing pill for contrast
	# against the background grid (a plain outlined string was easy to miss).
	var font := ThemeDB.fallback_font
	var font_size := 13
	var text_size := font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tag_pos := Vector2(-text_size.x / 2.0, -30.0)
	draw_rect(Rect2(tag_pos + Vector2(-6, -text_size.y + 2), text_size + Vector2(12, 6)),
		Color(0.02, 0.02, 0.04, 0.65))
	draw_string(font, tag_pos, player_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, player_color.lightened(0.5))


# ─── Inner Bullet class ────────────────────────────────────────────────────────
class _Bullet extends Node2D:
	var direction: Vector2 = Vector2.RIGHT
	var damage: float = 12.0
	var _lifetime: float = 1.2

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		global_position += direction * BULLET_SPEED * delta
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()
			return
		# Check collision with enemies — via the "enemies" group instead of
		# rescanning/duck-typing every sibling (which also includes every
		# other in-flight bullet), a lot cheaper with several players firing.
		if NetworkManager.is_host():
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if not enemy.is_queued_for_deletion() and global_position.distance_to(enemy.global_position) < 16.0:
					enemy.take_damage(damage, direction)
					GameState.record_damage(damage)
					queue_free()
					return
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.9, 0.3))
