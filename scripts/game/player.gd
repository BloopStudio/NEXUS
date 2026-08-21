## Player — controllable character for each connected peer
## Can move, manually shoot enemies, and interact with modules.
extends Node2D

const SPEED          := 180.0
const SHOOT_RANGE    := 220.0
const SHOOT_COOLDOWN := 0.6
const BULLET_SPEED   := 350.0
const BULLET_DAMAGE  := 12.0

const C_PLAYER  := Color(0.0, 0.831, 1.0)
const C_OUTLINE := Color(1.0, 1.0, 1.0, 0.5)

@export var peer_id: int = 1
var player_name: String = "Player"
var player_color: Color = C_PLAYER

var _shoot_timer: float = 0.0
var _is_local: bool = false


func _ready() -> void:
	_is_local = (peer_id == multiplayer.get_unique_id())
	set_process(_is_local)
	set_physics_process(_is_local)


func _process(delta: float) -> void:
	_shoot_timer -= delta
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
		_shoot_rpc.rpc(target)


@rpc("any_peer", "call_local", "unreliable")
func _move_rpc(pos: Vector2) -> void:
	global_position = pos
	queue_redraw()


@rpc("any_peer", "call_local", "reliable")
func _shoot_rpc(target_pos: Vector2) -> void:
	# Spawn a bullet
	var bullet := _Bullet.new()
	bullet.global_position = global_position
	bullet.direction = (target_pos - global_position).normalized()
	bullet.damage = BULLET_DAMAGE
	get_parent().add_child(bullet)
	queue_redraw()


func _draw() -> void:
	# Body: small circle with direction indicator
	draw_circle(Vector2.ZERO, 12.0, player_color.darkened(0.3))
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 24, player_color, 2.0)

	# Aim direction line (toward mouse, only for local player)
	if _is_local:
		var aim := to_local(get_global_mouse_position()).normalized() * 18.0
		draw_line(Vector2.ZERO, aim, player_color.lightened(0.4), 1.5)

	# Name tag
	draw_string(ThemeDB.fallback_font, Vector2(-20, -20), player_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_OUTLINE)


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
		# Check collision with enemies
		if NetworkManager.is_host():
			for child in get_parent().get_children():
				if child.has_method("take_damage") and not child.is_queued_for_deletion():
					if global_position.distance_to(child.global_position) < 16.0:
						child.take_damage(damage)
						queue_free()
						return
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.9, 0.3))
