# goal.gd
class_name LevelGoal
extends Area2D

signal reached(meteorite: AsteroidProjectile)

@export var goal_radius: float = 24.0
## How long the goal takes to pull the meteor into its center.
@export var absorb_duration: float = 0.45
## Extra spin applied to the meteor while it is being sucked in.
@export var absorb_spin: float = TAU

var _absorbing: bool = false
var _absorb_tween: Tween

@onready var complete_sound: AudioStreamPlayer = get_node_or_null("../Audio/Complete") as AudioStreamPlayer


func _ready() -> void:
	# Goal is on collision layer 3 and detects meteorites on layer 2.
	collision_layer = 4
	collision_mask = 2
	monitoring = true

	var circle := CircleShape2D.new()
	circle.radius = goal_radius
	$CollisionShape2D.shape = circle

	body_entered.connect(_on_body_entered)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	var asteroid := body as AsteroidProjectile

	if asteroid == null or _absorbing:
		return
	if not asteroid.flying or asteroid.dead or asteroid.absorbing:
		return

	# A reset meteor can produce one stale overlap report when its collision
	# shape is re-enabled. Ignore reports from well outside the goal.
	var max_entry_distance := goal_radius + 64.0
	if asteroid.global_position.distance_squared_to(global_position) > \
			max_entry_distance * max_entry_distance:
		return

	_absorbing = true
	if complete_sound != null:
		complete_sound.play()

	# Stop normal flight and make the trail shrink while the meteor is pulled in.
	asteroid.begin_goal_absorption(absorb_duration)

	_absorb_tween = create_tween()
	_absorb_tween.set_parallel(true)
	_absorb_tween.tween_property(asteroid, "global_position", global_position, absorb_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_absorb_tween.tween_property(asteroid, "scale", Vector2.ZERO, absorb_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_absorb_tween.tween_property(asteroid, "rotation", asteroid.rotation + absorb_spin, absorb_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_absorb_tween.finished.connect(_finish_absorption.bind(asteroid))


func _finish_absorption(asteroid: AsteroidProjectile) -> void:
	_absorb_tween = null

	if not is_instance_valid(asteroid):
		return

	asteroid.visible = false
	reached.emit(asteroid)


## Cancels the pull-in animation. Called when a level resets its shot.
func reset_goal() -> void:
	_absorbing = false

	if _absorb_tween and _absorb_tween.is_valid():
		_absorb_tween.kill()
	_absorb_tween = null


func _draw() -> void:
	draw_circle(
		Vector2.ZERO,
		goal_radius,
		Color(0.2, 1.0, 0.5, 0.12)
	)

	draw_arc(
		Vector2.ZERO,
		goal_radius,
		0.0,
		TAU,
		64,
		Color(0.2, 1.0, 0.5),
		2.0
	)
