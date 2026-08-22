## EnemyShield — carries a frontal shield that blocks damage arriving from
## roughly the direction it's walking toward (a shot fired from near the
## station, where players/turrets usually are, lands on its front) — hits
## from the side or behind go through untouched. Area-of-effect sources
## (mines, EMP, Onde de choc) have no single angle to block, so they always
## get through — flanking one of these physically, not just switching
## weapons, is the only reliable answer.
extends "res://scripts/enemies/enemy_base.gd"

## Frontal cone half-angle ~70° (dot < this blocks) — wide enough to be a
## real shield, narrow enough that circling around it clearly works.
const FRONT_BLOCK_DOT := -0.34

var _block_flash: float = 0.0


func _ready() -> void:
	max_hp = 70.0
	speed = 45.0
	contact_damage = 18.0
	color = Color(0.3, 0.75, 1.0)  # icy blue
	shape_radius = 15.0
	reward_energy = 10.0
	super()


func _process(delta: float) -> void:
	super(delta)
	if _block_flash > 0.0:
		_block_flash -= delta
		queue_redraw()


func _blocks_damage(from_direction: Vector2) -> bool:
	if from_direction == Vector2.ZERO:
		return false
	return from_direction.normalized().dot(_move_dir) < FRONT_BLOCK_DOT


func _on_damage_blocked() -> void:
	_block_flash = 0.15
	queue_redraw()
	AudioManager.play_sfx(AudioManager.SFX.ENEMY_HIT, -14.0)


func _draw_shape(col: Color) -> void:
	draw_circle(Vector2.ZERO, shape_radius, col.darkened(0.15))
	# The shield itself: an arc on the front (local "up", matching the
	# rotation _draw() already applies for _facing_angle) — flashes white
	# for an instant when it actually blocks a hit.
	var shield_col := Color.WHITE if _block_flash > 0.0 else Color(0.7, 0.95, 1.0)
	draw_arc(Vector2.ZERO, shape_radius + 4.0, -PI * 0.75, -PI * 0.25, 16, shield_col, 4.0)
