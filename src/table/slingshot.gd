class_name Slingshot
extends StaticBody2D
## The rubber above each flipper. A ball that brushes its inboard face is flung
## across the lower playfield -- the single biggest source of chaos down there,
## and the reason no two saves are the same.
##
## The kicking face is passed in explicitly rather than derived from the
## triangle, because "which edge of this polygon faces the player" is a
## question about winding order that silently answers itself wrongly the first
## time someone reorders a vertex.

signal scored(points: int, at: Vector2)

const COOLDOWN := 0.1
## Sideways spread on the kick. Zero would make every slingshot hit send the
## ball to the same place, which is exactly what a slingshot must not do.
const SPREAD := 0.22

var _normal := Vector2.UP
var _cool := 0.0
var _flash := 0.0
var _tri := PackedVector2Array()


func setup(data: Dictionary) -> void:
	collision_layer = 1
	collision_mask = 0
	_tri = data["tri"]

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.75  # live rubber, against 0.25 dead outer walls
	mat.friction = 0.2
	physics_material_override = mat

	var poly := CollisionPolygon2D.new()
	poly.polygon = _tri
	add_child(poly)

	var a: Vector2 = data["face_a"]
	var b: Vector2 = data["face_b"]
	var along := (b - a).normalized()
	var n := Vector2(-along.y, along.x)
	# Point the normal away from the triangle, whichever way the edge was given.
	var centroid := (_tri[0] + _tri[1] + _tri[2]) / 3.0
	if n.dot((a + b) * 0.5 - centroid) < 0.0:
		n = -n
	_normal = n

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var area_poly := CollisionPolygon2D.new()
	# A thin slab laid on the outside of the kicking face.
	area_poly.polygon = PackedVector2Array([a, b, b + n * 5.0, a + n * 5.0])
	area.add_child(area_poly)
	add_child(area)
	area.body_entered.connect(_on_entered)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		queue_redraw()


func _on_entered(body: Node) -> void:
	if _cool > 0.0 or not (body is Ball):
		return
	_cool = COOLDOWN
	_flash = 1.0
	queue_redraw()

	var ball := body as Ball
	var dir := _normal.rotated(randf_range(-SPREAD, SPREAD))
	ball.apply_central_impulse(dir * TableLayout.SLINGSHOT_KICK)

	var points := Run.register_hit(Catalog.Source.SLINGSHOT)
	Sfx.play("sling")
	scored.emit(points, global_position)


func _draw() -> void:
	var base := Color(0.20, 0.18, 0.28)
	var rubber := Color(0.92, 0.86, 0.30).lerp(Color(1.0, 1.0, 0.95), _flash)
	draw_colored_polygon(_tri, base)
	draw_polyline(PackedVector2Array([_tri[0], _tri[1], _tri[2], _tri[0]]), rubber, 2.0)
