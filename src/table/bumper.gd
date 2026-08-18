class_name Bumper
extends StaticBody2D
## Pop bumper. Deflects physically *and* kicks actively -- a bumper that only
## bounced would feel like a rock, and one that only kicked would let a slow
## ball roll through its middle.

signal scored(points: int, at: Vector2)

const KICK := 330.0
## Long enough that a ball cannot machine-gun a single bumper on one contact,
## short enough that a ball ricocheting around the cluster still reads as the
## rapid-fire rattle that is the whole appeal of a bumper nest.
const COOLDOWN := 0.08

var _cool := 0.0
var _flash := 0.0


func setup() -> void:
	collision_layer = 1
	collision_mask = 0

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.5
	mat.friction = 0.1
	physics_material_override = mat

	var body_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TableLayout.BUMPER_RADIUS - 2.0
	body_shape.shape = circle
	add_child(body_shape)

	# The trigger ring sits outside the solid core so the kick lands as the
	# ball arrives rather than after it has already bounced away.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var area_shape := CollisionShape2D.new()
	var area_circle := CircleShape2D.new()
	area_circle.radius = TableLayout.BUMPER_RADIUS + 1.0
	area_shape.shape = area_circle
	area.add_child(area_shape)
	add_child(area)
	area.body_entered.connect(_on_entered)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		queue_redraw()


func _on_entered(body: Node) -> void:
	if _cool > 0.0 or not (body is Ball):
		return
	_cool = COOLDOWN
	_flash = 1.0
	queue_redraw()

	var ball := body as Ball
	var dir := (ball.global_position - global_position)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.UP
	ball.apply_central_impulse(dir * KICK)

	var points := Run.register_hit(Catalog.Source.BUMPER)
	Sfx.play("bumper")
	scored.emit(points, global_position)


func _draw() -> void:
	var r := TableLayout.BUMPER_RADIUS
	var skirt := Color(0.16, 0.20, 0.34).lerp(Color(0.35, 0.45, 0.75), _flash)
	var cap := Color(0.98, 0.76, 0.20).lerp(Color(1.0, 1.0, 0.92), _flash)
	var lift := TableLayout.EXTRUDE * 1.6  # the tallest thing on the playfield

	draw_circle(Vector2(1.0, lift + 2.0), r * 0.95, Color(0.0, 0.0, 0.0, 0.40))
	# The body, as a stack of discs from the base up to the cap. A pop bumper
	# is a cone with a mushroom on top, and three offset circles read as that
	# far better at this size than any attempt at an actual silhouette.
	draw_circle(Vector2(0.0, lift), r, skirt.darkened(0.55))
	draw_circle(Vector2(0.0, lift * 0.5), r, skirt.darkened(0.25))
	draw_circle(Vector2.ZERO, r, skirt)
	draw_circle(Vector2.ZERO, r - 3.0, Color(0.10, 0.12, 0.20))
	draw_circle(Vector2(0.0, -1.0), r - 5.0, cap)
	draw_circle(Vector2(-1.5, -2.5), (r - 5.0) * 0.4, cap.lightened(0.45))
	draw_arc(Vector2.ZERO, r - 1.0, 0.0, TAU, 20, Color(0.55, 0.62, 0.90), 1.0)
