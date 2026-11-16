class_name GravityFieldVisual
extends Node2D

@export var radius: float = 180.0


func _draw() -> void:
	draw_circle(
		Vector2.ZERO,
		radius,
		Color(0.3, 0.7, 1.0, 0.035)
	)

	draw_arc(
		Vector2.ZERO,
		radius,
		0.0,
		TAU,
		96,
		Color(0.3, 0.7, 1.0, 0.3),
		1.0
	)
