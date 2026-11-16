# anti_gravity_planet.gd
class_name AntiGravityPlanet
extends StaticBody2D

@export var body_radius: float = 16.0
@export var field_radius: float = 140.0
@export var push_strength: float = 800.0

@export var field_color: Color = Color(0.85, 0.4, 1.0, 0.45)


func _ready() -> void:
	# Ugyanaz a réteg/maszk, mint a sima bolygónál: a felszín halálos.
	collision_layer = 1
	collision_mask = 0

	var circle := CircleShape2D.new()
	circle.radius = body_radius
	$CollisionShape2D.shape = circle

	# Ugyanabba a csoportba tesszük, hogy a meteor kódja változtatás
	# nélkül működjön tovább (csak az acceleration_at-et hívja).
	add_to_group("gravity_planets")
	add_to_group("anti_gravity_planets")
	queue_redraw()


func acceleration_at(point: Vector2) -> Vector2:
	var offset := global_position - point
	var distance := offset.length()

	if distance < 0.001 or distance > field_radius:
		return Vector2.ZERO

	# FONTOS: mínusz előjel -> a ponttól elfelé mutató irány.
	return -offset.normalized() * push_strength


func _draw() -> void:
	# Halvány kitöltés a hatósugáron belül.
	var fill := field_color
	fill.a = 0.05
	draw_circle(Vector2.ZERO, field_radius, fill)

	# A hatósugár körvonala.
	draw_arc(Vector2.ZERO, field_radius, 0.0, TAU, 96, field_color, 1.0, false)

	# Kifelé mutató nyilak a taszítás jelzésére.
	var spokes := 12
	for i in spokes:
		var angle := TAU * float(i) / float(spokes)
		var dir := Vector2.RIGHT.rotated(angle)
		var tip_r := field_radius * 0.65
		var base_r := tip_r - 6.0
		var perp := dir.orthogonal() * 3.0
		var tip := dir * tip_r
		var left := dir * base_r + perp
		var right := dir * base_r - perp
		draw_colored_polygon([tip, left, right], field_color)
