class_name Sensor
extends Area2D
## Non-solid scoring elements: rollover lanes, the spinner, and the orbit
## trigger. The ball passes straight through all of them; only the bookkeeping
## differs.

signal scored(points: int, at: Vector2)

const COOLDOWN := 0.4
## Pixels per second of ball speed per spinner revolution. A ball that limps
## through the spinner ticks it once; one that rips through on a full orbit
## racks up a dozen, which is what makes the orbit shot worth aiming for.
const PX_PER_REV := 45.0
const MAX_REVS := 14

var kind := Catalog.Source.ROLLOVER
var size := Vector2(20, 10)
var lit := false

var _cool := 0.0
var _flash := 0.0


func setup(source: int, rect_size: Vector2) -> void:
	kind = source
	size = rect_size
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_entered)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()


func _on_entered(body: Node) -> void:
	if _cool > 0.0 or not (body is Ball):
		return
	_cool = COOLDOWN
	_flash = 1.0
	queue_redraw()

	var count := 1
	if kind == Catalog.Source.SPINNER:
		var speed := (body as Ball).linear_velocity.length()
		count = clampi(int(speed / PX_PER_REV), 1, MAX_REVS)
		Sfx.play("spinner")
	else:
		lit = true
		Sfx.play("lane")

	var points := Run.register_hit(kind, count)
	scored.emit(points, global_position)


func unlight() -> void:
	lit = false
	queue_redraw()


func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	var on := lit or _flash > 0.0
	var tint := Color(0.98, 0.84, 0.36) if on else Color(0.24, 0.26, 0.40)
	tint = tint.lerp(Color.WHITE, _flash)
	draw_rect(r, Color(0.09, 0.10, 0.16))
	draw_rect(Rect2(r.position + Vector2.ONE, size - Vector2.ONE * 2.0), tint)
	if kind == Catalog.Source.SPINNER:
		# A pair of bars so the spinner reads as a paddle rather than a lamp.
		draw_line(Vector2(-size.x * 0.5 + 2, 0), Vector2(size.x * 0.5 - 2, 0),
			Color(0.10, 0.11, 0.18), 2.0)
