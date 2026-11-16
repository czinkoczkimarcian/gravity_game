extends Node2D

@onready var meteorite: Variant = get_node_or_null("Asteroids")

@export var click_radius: float = 14.0
@export var maximum_drag: float = 100.0
@export var power_multiplier: float = 4.0
@export var minimum_drag: float = 5.0

@onready var aim_line: Line2D = $AimLine

@onready var goal: Variant = get_node_or_null("Goal")
@onready var complete_label: Label = $HUD/LevelCompleteLabel

@export_file("*.tscn") var next_level: String = "level_5.tscn"

## Brief pause after the meteor reassembles before control returns.
@export var death_reset_delay: float = 0.1

var level_complete: bool = false

var dragging: bool = false
var shot_taken: bool = false
var start_position: Vector2

var _scene_change_pending: bool = false


func _ready() -> void:
	aim_line.clear_points()
	aim_line.hide()

	complete_label.text = "Level Complete!\nPress R to retry"
	complete_label.hide()

	if meteorite == null:
		push_error("Assign the Meteorite field on the Level root.")
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return

	if goal == null:
		push_error("Level root is missing a Goal child.")
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return

	start_position = meteorite.global_position

	meteorite.died.connect(_on_meteorite_died, CONNECT_DEFERRED)
	goal.reached.connect(_on_goal_reached)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
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


func _process(_delta: float) -> void:
	if not dragging:
		return

	var pull := get_pull_vector()
	var origin: Vector2 = meteorite.global_position

	aim_line.clear_points()
	aim_line.add_point(aim_line.to_local(origin))
	aim_line.add_point(aim_line.to_local(origin + pull))


func try_start_drag() -> void:
	if shot_taken or meteorite.dead:
		return

	var distance := get_global_mouse_position().distance_to(
		meteorite.global_position
	)

	if distance <= click_radius:
		dragging = true
		aim_line.clear_points()
		aim_line.show()


func get_pull_vector() -> Vector2:
	var pull: Vector2 = meteorite.global_position - get_global_mouse_position()
	return pull.limit_length(maximum_drag)


func release_shot() -> void:
	var pull := get_pull_vector()

	dragging = false
	aim_line.hide()

	if pull.length() < minimum_drag:
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

	complete_label.hide()

	aim_line.clear_points()
	aim_line.hide()

	$Audio/Death.play()

	if goal != null and goal.has_method("reset_goal"):
		goal.reset_goal()

	meteorite.reset_to(start_position)


func _on_meteorite_died() -> void:
	await get_tree().create_timer(death_reset_delay).timeout

	if not is_instance_valid(self) or not is_inside_tree():
		return
	if meteorite == null or not meteorite.dead or level_complete:
		return

	_reset_shot_now()


func _on_goal_reached(asteroid: Variant) -> void:
	if level_complete or asteroid != meteorite:
		return

	level_complete = true
	dragging = false
	shot_taken = true

	meteorite.flying = false
	meteorite.velocity = Vector2.ZERO

	aim_line.clear_points()
	aim_line.hide()

	complete_label.show()

	if not next_level.is_empty() and not _scene_change_pending:
		_scene_change_pending = true
		await get_tree().create_timer(2.0).timeout

		if is_instance_valid(self) and level_complete and _scene_change_pending:
			get_tree().change_scene_to_file(next_level)
