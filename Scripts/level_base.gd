class_name GravityLevelBase
extends Node2D

## Shared level controller. Each level script inherits this and only stores
## its scene-specific exported values in the level scene.

@export var click_radius: float = 14.0
@export var maximum_drag: float = 100.0
@export var power_multiplier: float = 4.0
@export var minimum_drag: float = 5.0

@export_file("*.tscn") var next_level: String = ""
@export_range(1, 99, 1) var level_number: int = 1
@export var is_final_level: bool = false
@export var completion_delay: float = 2.6

## Brief pause after the meteor reassembles before control returns.
@export var death_reset_delay: float = 0.1

var level_complete: bool = false

var dragging: bool = false
var shot_taken: bool = false
var start_position: Vector2

var _scene_change_pending: bool = false

@onready var meteorite: AsteroidProjectile = get_node_or_null("Asteroids") as AsteroidProjectile
@onready var goal: LevelGoal = get_node_or_null("Goal") as LevelGoal
@onready var complete_ui: LevelCompleteUI = $HUD/LevelCompleteUI
@onready var aim_line: Line2D = $AimLine
@onready var death_sound: AudioStreamPlayer = get_node_or_null("Audio/Death") as AudioStreamPlayer


func _ready() -> void:
	# Aiming follows raw mouse-motion events below. Send those events as
	# they arrive instead of coalescing them once per rendered frame.
	Input.set_use_accumulated_input(false)

	aim_line.clear_points()
	aim_line.hide()
	complete_ui.hide_complete()

	if meteorite == null:
		push_error("Assign the Meteorite field on the Level root.")
		set_process_unhandled_input(false)
		return

	if goal == null:
		push_error("Level root is missing a Goal child.")
		set_process_unhandled_input(false)
		return

	start_position = meteorite.global_position

	meteorite.died.connect(_on_meteorite_died, CONNECT_DEFERRED)
	goal.reached.connect(_on_goal_reached)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return

	if event is InputEventMouseMotion:
		if dragging:
			_update_aim_line()
		return

	if event.is_action_pressed("Retry"):
		reset_shot()
		return

	if level_complete:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				try_start_drag()
			elif dragging:
				release_shot()


func _update_aim_line() -> void:
	var origin := meteorite.global_position
	var mouse := get_global_mouse_position()
	var pull := (origin - mouse).limit_length(maximum_drag)

	var start := aim_line.to_local(origin)
	var end := aim_line.to_local(origin + pull)

	# Reuse the two line points instead of rebuilding the array each update.
	if aim_line.get_point_count() == 2:
		aim_line.set_point_position(0, start)
		aim_line.set_point_position(1, end)
	else:
		aim_line.points = PackedVector2Array([start, end])


func try_start_drag() -> void:
	if shot_taken or meteorite.dead:
		return

	var mouse := get_global_mouse_position()
	if mouse.distance_squared_to(meteorite.global_position) > click_radius * click_radius:
		return

	dragging = true
	aim_line.show()
	_update_aim_line()


func get_pull_vector() -> Vector2:
	var pull := meteorite.global_position - get_global_mouse_position()
	return pull.limit_length(maximum_drag)


func release_shot() -> void:
	var pull := get_pull_vector()

	dragging = false
	aim_line.hide()

	if pull.length_squared() < minimum_drag * minimum_drag:
		return

	shot_taken = true
	meteorite.launch(pull * power_multiplier)


func reset_shot() -> void:
	# Do not interrupt the break animation. The delayed death handler
	# below will reset the shot once the effect has finished.
	if meteorite != null and meteorite.dead:
		return

	_reset_shot_now()


func _reset_shot_now() -> void:
	level_complete = false
	dragging = false
	shot_taken = false
	_scene_change_pending = false

	complete_ui.hide_complete()

	aim_line.clear_points()
	aim_line.hide()

	if death_sound != null:
		death_sound.play()

	if goal != null:
		goal.reset_goal()

	meteorite.reset_to(start_position)


func _on_meteorite_died() -> void:
	await get_tree().create_timer(death_reset_delay).timeout

	if not is_instance_valid(self) or not is_inside_tree():
		return
	if meteorite == null or not meteorite.dead or level_complete:
		return

	_reset_shot_now()


func _on_goal_reached(asteroid: AsteroidProjectile) -> void:
	if level_complete or asteroid != meteorite:
		return

	level_complete = true
	dragging = false
	shot_taken = true

	meteorite.flying = false
	meteorite.velocity = Vector2.ZERO

	aim_line.clear_points()
	aim_line.hide()

	var title := "LEVEL COMPLETE"
	if is_final_level:
		title = "ALL SECTORS CLEARED"

	complete_ui.present(title)

	if not next_level.is_empty() and not _scene_change_pending:
		_scene_change_pending = true
		await get_tree().create_timer(completion_delay).timeout

		if is_instance_valid(self) and level_complete and _scene_change_pending:
			get_tree().change_scene_to_file(next_level)
