class_name Target
extends StaticBody2D
## Drop targets and standup targets. Same body, different response to being hit:
## a drop target sinks and stays down until the bank is cleared, a standup just
## scores and springs back.
##
## Hits are detected by an Area2D inflated a few pixels past the solid body,
## not by contact reporting. A ball glancing off a 6px-wide target at 600px/s
## can resolve its contact and leave in under two ticks; an inflated trigger
## catches the approach instead of the touch, which is the difference between a
## target that always registers and one that mostly does.

signal scored(points: int, at: Vector2)
signal dropped

const TRIGGER_INFLATE := 3.0
const STANDUP_COOLDOWN := 0.25

var is_drop := true
var down := false

var _cool := 0.0
var _flash := 0.0
var _shape: CollisionShape2D
var _area: Area2D


func setup(drop: bool) -> void:
	is_drop = drop
	collision_layer = 1
	collision_mask = 0

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.45
	mat.friction = 0.2
	physics_material_override = mat

	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = TableLayout.TARGET_SIZE
	_shape.shape = rect
	add_child(_shape)

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = TableLayout.TARGET_SIZE + Vector2.ONE * TRIGGER_INFLATE * 2.0
	area_shape.shape = area_rect
	_area.add_child(area_shape)
	add_child(_area)
	_area.body_entered.connect(_on_entered)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		queue_redraw()


func _on_entered(body: Node) -> void:
	if down or _cool > 0.0 or not (body is Ball):
		return
	_flash = 1.0
	queue_redraw()

	if is_drop:
		# `down` alone gates re-entry (see the guard above), so the Area2D's
		# monitoring is deliberately left alone. Toggling it here would mean
		# changing an area's state from inside that same area's signal, which
		# Godot refuses mid-query -- and set_deferred does not reliably escape
		# it when the drain re-serves the ball inside the same flush.
		down = true
		_shape.set_deferred("disabled", true)
		var points := Run.register_hit(Catalog.Source.DROP)
		Sfx.play("drop")
		scored.emit(points, global_position)
		dropped.emit()
	else:
		_cool = STANDUP_COOLDOWN
		var points := Run.register_hit(Catalog.Source.STANDUP)
		Sfx.play("target")
		scored.emit(points, global_position)


## Raise a dropped target -- called on the whole bank once every target is down.
func reset_target() -> void:
	if not down:
		return
	down = false
	_shape.set_deferred("disabled", false)
	queue_redraw()


func _draw() -> void:
	var size := TableLayout.TARGET_SIZE
	var r := Rect2(-size * 0.5, size)
	if down:
		# A dropped target still reads as a slot in the playfield, so the bank
		# stays legible when it is half cleared.
		draw_rect(Rect2(r.position + Vector2(1, 2), Vector2(size.x - 2, size.y - 4)),
			Color(0.10, 0.10, 0.16))
		return
	var face := Color(0.36, 0.80, 0.92) if is_drop else Color(0.94, 0.50, 0.30)
	face = face.lerp(Color.WHITE, _flash)
	# A target stands up out of the playfield, so it gets the tallest side face
	# of anything except a bumper -- that is what makes a dropped one read as
	# having actually gone down rather than merely changed colour.
	var lift := TableLayout.EXTRUDE * 1.3
	draw_rect(Rect2(r.position + Vector2(0.0, lift), size), face.darkened(0.7))
	draw_rect(r, Color(0.08, 0.09, 0.14))
	draw_rect(Rect2(r.position + Vector2.ONE, size - Vector2.ONE * 2.0), face)
	draw_rect(Rect2(r.position + Vector2.ONE, Vector2(size.x - 2.0, 1.0)),
		face.lightened(0.4))
