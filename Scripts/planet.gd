# planet.gd
class_name GravityPlanet
extends StaticBody2D

@export var body_radius: float = 16.0
@export var gravity_radius: float = 140.0
@export var gravity_strength: float = 200000.0

@export var field_color: Color = Color(0.4, 0.7, 1.0, 0.45)


func _ready() -> void:
	# Solid surface: hitting it kills the meteorite.
	collision_layer = 1
	collision_mask = 0

	var circle := CircleShape2D.new()
	circle.radius = body_radius
	$CollisionShape2D.shape = circle

	add_to_group("gravity_planets")
	queue_redraw()


func acceleration_at(point: Vector2) -> Vector2:
	var offset := global_position - point
	var distance := offset.length()

	if distance < 0.001 or distance > gravity_radius:
		return Vector2.ZERO

	# Constant, clearly visible acceleration inside the circle. Reusing
	# the distance avoids a second square root from normalized().
	return offset * (800.0 / distance)




func _draw() -> void:
	# Faint fill showing the affected area.
	var fill := field_color
	fill.a = 0.05

	draw_circle(Vector2.ZERO, gravity_radius, fill)

	# Outline of the gravity radius.
	draw_arc(
		Vector2.ZERO,
		gravity_radius,
		0.0,
		TAU,
		96,
		field_color,
		1.0,
		false
	)
