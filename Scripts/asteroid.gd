class_name AsteroidProjectile
extends CharacterBody2D

signal died

@export_group("Movement")
@export var maximum_speed: float = 500.0

@export_group("Trail")
@export var max_trail_points: int = 28
@export var trail_min_distance: float = 4.0
@export var trail_width: float = 0.0
@export var trail_fade_duration: float = 0.6

@export_group("Break Effect")
## Atlas coordinate of the cracked meteor tile in the TileMapLayer's TileSet.
@export var cracked_atlas_coords: Vector2i = Vector2i(1, 0)
## How long the cracked meteor stays visible before it breaks apart.
@export var crack_duration: float = 0.15
## Atlas coordinates of the debris tiles. Leave empty to use every tile
## in the TileSet except the intact and cracked meteor tiles.
@export var debris_atlas_coords: Array[Vector2i] = [
	Vector2i(2, 0),
	Vector2i(3, 0),
	Vector2i(4, 0),
	Vector2i(5, 0),
	Vector2i(6, 0),
	Vector2i(7, 0),
]
@export_range(1, 12, 1) var debris_count: int = 4
@export var debris_min_speed: float = 450.0
@export var debris_max_speed: float = 650.0
## Each piece bounces this many times on the level walls before returning.
@export_range(1, 6, 1) var debris_wall_bounces: int = 2
## Brief pause after the last wall hit so the final ricochet is visible.
@export var debris_bounce_settle_time: float = 0.12
## Safety limit while waiting for every piece to finish its wall bounces.
@export var debris_bounce_timeout: float = 3.0
## How long the pieces take to fly back to the meteor's home position.
@export var debris_return_duration: float = 0.4
## Radius of the cluster the pieces form before the intact meteor reappears.
@export var debris_assembly_radius: float = 7.0
## Pieces explode outward without being pulled down.
@export var debris_gravity_scale: float = 0.0
@export var debris_bounce: float = 0.95
@export var debris_spin: float = 7.0

var flying: bool = false
var dead: bool = false
var absorbing: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var tilemap: TileMapLayer = get_node_or_null("TileMapLayer") as TileMapLayer

var trail: Line2D
var _last_committed_pos: Vector2
var _home_position: Vector2
var _fade_tween: Tween
var _shrink_tween: Tween
var _return_tween: Tween

# Original TileMapLayer cells, used to restore the intact meteor on reset.
var _original_cells: Array[Dictionary] = []
var _atlas_source_id: int = -1
var _active_debris: Array[RigidBody2D] = []
var _debris_bounce_counts: Dictionary = {}
var _debris_last_bounce_ms: Dictionary = {}


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_home_position = global_position
	_create_trail()

	if tilemap == null:
		push_warning("AsteroidProjectile: no TileMapLayer child found; break effect disabled.")
	else:
		_save_original_cells()


func _create_trail() -> void:
	trail = Line2D.new()
	trail.name = "Trail"
	trail.top_level = true
	trail.show_behind_parent = true
	trail.z_index = 0
	trail.z_as_relative = true
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND

	var asteroid_radius := 8.0
	if collision_shape and collision_shape.shape is CircleShape2D:
		asteroid_radius = (collision_shape.shape as CircleShape2D).radius

	var base_width := trail_width
	if base_width <= 0.0:
		base_width = asteroid_radius * 3.2
	trail.width = base_width

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.2, 0.0, 0.0, 0.0))
	gradient.add_point(0.2, Color(0.6, 0.1, 0.0, 0.35))
	gradient.add_point(0.5, Color(0.95, 0.35, 0.0, 0.75))
	gradient.add_point(0.8, Color(1.0, 0.75, 0.15, 0.95))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 0.7, 1.0))

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 1
	trail.texture = tex
	trail.texture_mode = Line2D.LINE_TEXTURE_STRETCH

	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 0.15))
	width_curve.add_point(Vector2(0.45, 0.55))
	width_curve.add_point(Vector2(0.85, 1.0))
	width_curve.add_point(Vector2(1.0, 0.85))
	trail.width_curve = width_curve

	add_child(trail)
	trail.position = Vector2.ZERO


func launch(initial_velocity: Vector2) -> void:
	if dead:
		return

	_kill_fade_tweens()
	velocity = initial_velocity
	flying = true
	trail.modulate.a = 1.0
	trail.clear_points()
	_last_committed_pos = global_position
	trail.add_point(trail.to_local(global_position))


## Called by the goal when the meteor enters its radius. Stops normal
## flight and shrinks the trail while the goal's tween pulls the meteor in.
func begin_goal_absorption(duration: float = 0.45) -> void:
	if dead or absorbing:
		return

	absorbing = true
	flying = false
	velocity = Vector2.ZERO

	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	_fade_trail_out(duration)


func _physics_process(delta: float) -> void:
	if not flying or dead or absorbing:
		return

	var acceleration := Vector2.ZERO
	var sources := get_tree().get_nodes_in_group("gravity_planets")

	for node in sources:
		if not node.has_method("acceleration_at"):
			continue
		var planet: Variant = node
		var pull: Vector2 = planet.acceleration_at(global_position)
		acceleration += pull

	velocity += acceleration * delta
	velocity = velocity.limit_length(maximum_speed)

	var collision := move_and_collide(velocity * delta)

	if collision != null:
		die()
	else:
		_update_trail()


func _update_trail() -> void:
	var world_pos := global_position

	if _last_committed_pos.distance_to(world_pos) >= trail_min_distance:
		trail.add_point(trail.to_local(world_pos))
		_last_committed_pos = world_pos

		while trail.get_point_count() > max_trail_points:
			trail.remove_point(0)


func die() -> void:
	if dead:
		return

	dead = true
	flying = false
	velocity = Vector2.ZERO

	# Show the cracked meteor for a moment before it breaks apart.
	_swap_to_cracked()

	if crack_duration > 0.0:
		await get_tree().create_timer(crack_duration).timeout

	# The level may have been reset or the scene may have changed while waiting.
	if not is_instance_valid(self) or not is_inside_tree() or not dead:
		return

	if tilemap:
		tilemap.hide()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	_spawn_debris()
	_fade_trail_out()

	# Let the pieces explode outward and bounce off the level walls.
	await _wait_for_wall_bounces()

	if not is_instance_valid(self) or not is_inside_tree() or not dead:
		return

	await _fly_debris_home()

	if not is_instance_valid(self) or not is_inside_tree() or not dead:
		return

	# Reassemble the intact meteor at its home position.
	global_position = _home_position
	_last_committed_pos = global_position
	_restore_original_cells()
	if tilemap:
		tilemap.show()
	if trail:
		trail.clear_points()
		trail.modulate.a = 1.0

	died.emit()


func _fade_trail_out(duration: float = -1.0) -> void:
	_kill_fade_tweens()

	if not trail:
		return

	var count := trail.get_point_count()
	if count == 0:
		return

	var fade_time := trail_fade_duration
	if duration > 0.0:
		fade_time = duration

	trail.modulate.a = 1.0

	_fade_tween = create_tween()
	_fade_tween.tween_property(trail, "modulate:a", 0.0, fade_time) \
		.set_ease(Tween.EASE_IN)

	_shrink_tween = create_tween()
	var interval := fade_time / float(count)
	for i in range(count):
		_shrink_tween.tween_callback(_pop_trail_front)
		_shrink_tween.tween_interval(interval)
	_shrink_tween.tween_callback(_finish_trail_fade)


func _pop_trail_front() -> void:
	if trail and trail.get_point_count() > 0:
		trail.remove_point(0)


func _finish_trail_fade() -> void:
	if trail:
		trail.clear_points()
		trail.modulate.a = 1.0


func _kill_fade_tweens() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _shrink_tween and _shrink_tween.is_valid():
		_shrink_tween.kill()
	_fade_tween = null
	_shrink_tween = null


func reset_to(start_position: Vector2) -> void:
	_kill_fade_tweens()
	_clear_debris()
	_restore_original_cells()

	if tilemap:
		tilemap.show()
	if collision_shape:
		collision_shape.set_deferred("disabled", false)

	flying = false
	dead = false
	absorbing = false
	visible = true
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	velocity = Vector2.ZERO
	global_position = start_position
	_home_position = start_position
	_last_committed_pos = start_position

	if trail:
		trail.clear_points()
		trail.modulate.a = 1.0


# --- TileMap helpers -------------------------------------------------------

func _save_original_cells() -> void:
	_original_cells.clear()
	_atlas_source_id = -1

	for cell in tilemap.get_used_cells():
		_original_cells.append({
			"coords": cell,
			"source_id": tilemap.get_cell_source_id(cell),
			"atlas_coords": tilemap.get_cell_atlas_coords(cell),
			"alternative_tile": tilemap.get_cell_alternative_tile(cell),
		})

	if _original_cells.is_empty():
		push_warning("AsteroidProjectile: TileMapLayer has no cells to save.")
		return

	_atlas_source_id = _original_cells[0]["source_id"]


func _swap_to_cracked() -> void:
	if tilemap == null:
		return

	for entry in _original_cells:
		tilemap.set_cell(
			entry["coords"],
			entry["source_id"],
			cracked_atlas_coords,
			entry["alternative_tile"]
		)


func _restore_original_cells() -> void:
	if tilemap == null:
		return

	for entry in _original_cells:
		tilemap.set_cell(
			entry["coords"],
			entry["source_id"],
			entry["atlas_coords"],
			entry["alternative_tile"]
		)


# --- Debris ----------------------------------------------------------------

func _spawn_debris() -> void:
	if tilemap == null or tilemap.tile_set == null:
		return

	var parent := get_parent()
	if parent == null or not is_inside_tree() or not parent.is_inside_tree():
		return

	var debris_coords := _get_debris_atlas_coords()
	if debris_coords.is_empty():
		return

	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = debris_bounce
	physics_material.friction = 0.3

	for i in range(debris_count):
		var atlas_coords: Vector2i = debris_coords.pick_random()
		var debris_texture := _create_debris_texture(atlas_coords)
		if debris_texture == null:
			continue

		var origin := global_position
		if not _original_cells.is_empty():
			var cell: Vector2i = _original_cells.pick_random()["coords"]
			origin = tilemap.to_global(tilemap.map_to_local(cell))

		var direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var start_position := origin + direction * randf_range(0.0, 4.0)
		var speed := randf_range(debris_min_speed, debris_max_speed)

		var body := RigidBody2D.new()
		body.name = "MeteorDebris%d" % (i + 1)
		body.z_index = z_index + 1
		body.collision_layer = 0
		body.collision_mask = 1
		body.gravity_scale = debris_gravity_scale
		body.physics_material_override = physics_material
		body.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
		body.linear_damp = 0.0
		body.angular_damp = 0.0
		body.contact_monitor = true
		body.max_contacts_reported = 4

		var sprite := Sprite2D.new()
		sprite.texture = debris_texture
		body.add_child(sprite)

		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = maxf(
			4.0,
			minf(debris_texture.region.size.x, debris_texture.region.size.y) * 0.28
		)
		collision.shape = shape
		body.add_child(collision)

		parent.add_child(body)
		body.global_position = start_position
		body.rotation = randf_range(-PI, PI)
		body.linear_velocity = direction * speed
		body.angular_velocity = randf_range(-debris_spin, debris_spin)

		var id := body.get_instance_id()
		_debris_bounce_counts[id] = 0
		_debris_last_bounce_ms[id] = -1000
		body.body_entered.connect(_on_debris_body_entered.bind(body))

		_active_debris.append(body)


func _on_debris_body_entered(_other: Node, debris: RigidBody2D) -> void:
	if not is_instance_valid(debris) or debris.freeze:
		return

	var id := debris.get_instance_id()
	if not _debris_bounce_counts.has(id):
		return

	# Ignore duplicate contact reports from the same hit.
	var now := Time.get_ticks_msec()
	var last := int(_debris_last_bounce_ms.get(id, -1000))
	if now - last < 60:
		return

	_debris_last_bounce_ms[id] = now
	_debris_bounce_counts[id] = int(_debris_bounce_counts[id]) + 1


func _all_debris_bounced(required: int) -> bool:
	for body in _active_debris:
		if not is_instance_valid(body):
			continue
		var count := int(_debris_bounce_counts.get(body.get_instance_id(), 0))
		if count < required:
			return false
	return true


func _wait_for_wall_bounces() -> void:
	if _active_debris.is_empty():
		return

	var required := maxi(debris_wall_bounces, 0)
	if required <= 0:
		return

	var timeout := maxf(debris_bounce_timeout, 0.05)
	var elapsed := 0.0

	while elapsed < timeout:
		if _all_debris_bounced(required):
			if debris_bounce_settle_time > 0.0:
				await get_tree().create_timer(debris_bounce_settle_time).timeout
			return
		await get_tree().create_timer(0.03).timeout
		elapsed += 0.03


## Pulls every piece back to the meteor's home position, tucking them into
## a small cluster before the intact meteor tile is restored.
func _fly_debris_home() -> void:
	if _active_debris.is_empty():
		return

	var return_time := maxf(debris_return_duration, 0.05)
	var count := _active_debris.size()
	var shrink_time := return_time * 0.25
	var shrink_delay := return_time - shrink_time

	_return_tween = create_tween()
	_return_tween.set_parallel(true)

	for i in range(count):
		var body := _active_debris[i]
		if not is_instance_valid(body):
			continue

		# Take the piece out of the physics simulation so it can be tweened.
		body.freeze = true
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
		body.collision_layer = 0
		body.collision_mask = 0

		var angle := TAU * float(i) / float(count)
		var target := _home_position + \
			Vector2.RIGHT.rotated(angle) * debris_assembly_radius

		_return_tween.tween_property(body, "global_position", target, return_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_return_tween.tween_property(body, "rotation", 0.0, return_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_return_tween.tween_property(body, "scale", Vector2.ZERO, shrink_time) \
			.set_delay(shrink_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_return_tween.tween_property(body, "modulate:a", 0.0, shrink_time) \
			.set_delay(shrink_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Wait slightly past the tween so the pieces finish shrinking before
	# the intact meteor tile appears.
	await get_tree().create_timer(return_time + 0.02).timeout

	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	_return_tween = null
	_clear_debris()


func _create_debris_texture(atlas_coords: Vector2i) -> AtlasTexture:
	var source := _find_atlas_source(atlas_coords)
	if source == null or source.texture == null:
		return null

	var debris_texture := AtlasTexture.new()
	debris_texture.atlas = source.texture
	debris_texture.region = source.get_tile_texture_region(atlas_coords)
	return debris_texture


func _find_atlas_source(atlas_coords: Vector2i) -> TileSetAtlasSource:
	if tilemap == null or tilemap.tile_set == null:
		return null

	# Prefer the source that the meteor itself comes from.
	if _atlas_source_id >= 0:
		var preferred := tilemap.tile_set.get_source(_atlas_source_id) as TileSetAtlasSource
		if preferred != null and preferred.has_tile(atlas_coords):
			return preferred

	for i in range(tilemap.tile_set.get_source_count()):
		var source_id := tilemap.tile_set.get_source_id(i)
		var source := tilemap.tile_set.get_source(source_id) as TileSetAtlasSource
		if source != null and source.has_tile(atlas_coords):
			return source

	return null


func _get_debris_atlas_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []

	if not debris_atlas_coords.is_empty():
		coords.assign(debris_atlas_coords)
		return coords

	if tilemap == null or tilemap.tile_set == null:
		return coords

	# Auto-detect: every tile in the meteor's atlas source except the
	# intact/cracked tiles becomes a debris candidate.
	var skip: Array[Vector2i] = [cracked_atlas_coords]
	for entry in _original_cells:
		var original_coords: Vector2i = entry["atlas_coords"]
		if not skip.has(original_coords):
			skip.append(original_coords)

	for i in range(tilemap.tile_set.get_source_count()):
		var source_id := tilemap.tile_set.get_source_id(i)
		if _atlas_source_id >= 0 and source_id != _atlas_source_id:
			continue

		var source := tilemap.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue

		for t in range(source.get_tiles_count()):
			var tile_coords := source.get_tile_id(t)
			if not skip.has(tile_coords):
				coords.append(tile_coords)

	return coords


func _clear_debris() -> void:
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	_return_tween = null

	for body in _active_debris:
		if is_instance_valid(body):
			body.queue_free()
	_active_debris.clear()
	_debris_bounce_counts.clear()
	_debris_last_bounce_ms.clear()
