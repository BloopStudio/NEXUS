## Player — controllable character for each connected peer
## Can move, manually shoot enemies, and interact with modules.
extends Node2D

const SPEED          := 180.0
const SHOOT_RANGE    := 220.0
const SHOOT_COOLDOWN := 0.6
const BULLET_SPEED   := 350.0
const BULLET_DAMAGE  := 12.0

## "Onde de choc" — an area-damage burst around the player, on a cooldown.
## The only player ability for now; default key is E (rebindable).
const ABILITY_COOLDOWN := 6.0
const ABILITY_RADIUS   := 90.0
const ABILITY_DAMAGE   := 30.0
const ABILITY_PULSE_DURATION := 0.4

const C_PLAYER  := Color(0.0, 0.831, 1.0)
const C_OUTLINE := Color(1.0, 1.0, 1.0, 0.5)

@export var peer_id: int = 1
var player_name: String = "Player"
var player_color: Color = C_PLAYER

var _shoot_timer: float = 0.0
var _ability_timer: float = 0.0
var _ability_pulse: float = 0.0
var _is_local: bool = false


func _ready() -> void:
	_is_local = (peer_id == multiplayer.get_unique_id())
	# _process only ticks cosmetic timers (ability pulse animation) and
	# redraws — needs to run for every peer's copy so remote players' ability
	# bursts animate for observers too, not just the player who used it.
	set_process(true)
	set_physics_process(_is_local)


func _process(delta: float) -> void:
	_shoot_timer -= delta
	if _ability_timer > 0.0:
		_ability_timer -= delta
	if _ability_pulse > 0.0:
		_ability_pulse -= delta
	# Aim indicator
	queue_redraw()


func _physics_process(delta: float) -> void:
	# WASD / Arrow keys movement
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var new_pos := global_position + dir * SPEED * delta
		# Keep within arena bounds
		new_pos = new_pos.clamp(Vector2(-420, -420), Vector2(420, 420))
		_move_rpc.rpc(new_pos)

	# Shoot (default: left click, rebindable in Settings)
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0:
		_shoot_timer = SHOOT_COOLDOWN
		var target := get_global_mouse_position()
		_shoot_rpc.rpc(target, BULLET_DAMAGE * GameState.get_player_damage_multiplier())

	# Ability: "Onde de choc" — area burst, default key E
	if Input.is_action_just_pressed("ability") and _ability_timer <= 0.0:
		_ability_timer = ABILITY_COOLDOWN
		_ability_rpc.rpc()


@rpc("any_peer", "call_local", "unreliable")
func _move_rpc(pos: Vector2) -> void:
	global_position = pos
	queue_redraw()


@rpc("any_peer", "call_local", "reliable")
func _ability_rpc() -> void:
	_ability_pulse = ABILITY_PULSE_DURATION
	AudioManager.play_sfx(AudioManager.SFX.UPGRADE, 2.0)
	queue_redraw()

	# Only the host actually applies damage — same pattern as bullets/mines,
	# every peer just plays the same visual/audio locally.
	if NetworkManager.is_host():
		var parent := get_parent()
		if parent != null and parent.has_method("get_enemies_in_radius"):
			var dmg := ABILITY_DAMAGE * GameState.get_player_damage_multiplier()
			for enemy in parent.get_enemies_in_radius(global_position, ABILITY_RADIUS):
				enemy.take_damage(dmg)


@rpc("any_peer", "call_local", "reliable")
func _shoot_rpc(target_pos: Vector2, damage: float) -> void:
	# Spawn a bullet
	var bullet := _Bullet.new()
	bullet.global_position = global_position
	bullet.direction = (target_pos - global_position).normalized()
	bullet.damage = damage
	get_parent().add_child(bullet)
	queue_redraw()


func _draw() -> void:
	# Soft outer glow so players read clearly against the background grid.
	draw_circle(Vector2.ZERO, 17.0, Color(player_color.r, player_color.g, player_color.b, 0.12))

	# Body: shaded circle + bright rim + a small highlight for some depth.
	draw_circle(Vector2.ZERO, 12.0, player_color.darkened(0.35))
	draw_circle(Vector2(-4.0, -4.0), 4.0, player_color.lightened(0.5).lerp(Color.WHITE, 0.3) * Color(1, 1, 1, 0.55))
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 28, player_color, 2.0, true)

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

	# Ability pulse — expanding, fading ring on every peer that sees it.
	if _ability_pulse > 0.0:
		var progress := 1.0 - clampf(_ability_pulse / ABILITY_PULSE_DURATION, 0.0, 1.0)
		draw_arc(Vector2.ZERO, ABILITY_RADIUS * progress, 0, TAU, 40,
			Color(player_color.r, player_color.g, player_color.b, 1.0 - progress), 3.0, true)

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
					enemy.take_damage(damage)
					queue_free()
					return
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.9, 0.3))
