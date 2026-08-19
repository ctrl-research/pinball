class_name Flipper
extends AnimatableBody2D
## A flipper, as a kinematic body swept between two angles.
##
## The ball is launched by the flipper's *actual motion*, not by a scripted
## impulse: `sync_to_physics` makes the physics server integrate this body's
## transform change into a velocity and hand that momentum to anything it
## touches. That is why a ball caught near the tip flies further than one
## caught at the root, why a late flip is weaker than a full sweep, and why
## catching the ball on a held flipper works at all -- none of which fall out
## of a "if flipping, add impulse" implementation.
##
## The alternative (RigidBody2D driven by a motorised PinJoint2D) is more
## physically honest and much jitterier, because a solenoid-speed motor fights
## the solver every tick.

const LENGTH_MOD_BONUS := 4.0  # "Wide Flippers" table mod

## "Hot Winding": the sweep runs faster, so a flip started late still connects.
const HOT_WINDING_SCALE := 0.8

## "Heavy Bat": a livelier face. Double-edged on purpose -- the same bounce that
## sends a shot further is the one that makes it harder to place.
const BAT_BOUNCE := 0.2
const HEAVY_BAT_BOUNCE := 0.36

## "Dead Bounce": a ball that lands on a flipper sitting at rest normally rolls
## off the tip and drains inside a second, with no input that saves it. With the
## coil fitted it is kicked back up the table instead.
##
## The flipper must be genuinely down: this is a save for a ball you never had a
## chance at, not a second flipper button.
const DEAD_BOUNCE_SPEED := 210.0
const DEAD_BOUNCE_MAX_T := 0.08

var rest_angle := 0.0
var up_angle := 0.0
var action := "flip_left"
var disabled := false

var _t := 0.0  ## 0 = at rest, 1 = fully flipped


func setup(is_left: bool) -> void:
	var angles := TableLayout.flipper_angles(is_left)
	rest_angle = angles.x
	up_angle = angles.y
	action = "flip_left" if is_left else "flip_right"

	var length := TableLayout.FLIPPER_LENGTH
	if Run.has_mod("wide_flippers"):
		length += LENGTH_MOD_BONUS

	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0

	var mat := PhysicsMaterial.new()
	mat.bounce = HEAVY_BAT_BOUNCE if Run.has_coil("heavy_bat") else BAT_BOUNCE
	# Grip, so a held flipper can cradle a ball. This is not aspirational: a
	# ball dropped onto a raised flipper comes to a dead stop at the root and
	# stays there, which is why `Magna-Hold` was cut from the coil list.
	mat.friction = 0.7
	physics_material_override = mat

	# A capsule from the pivot out to the tip. Capsule2D is vertical by
	# default, so it is rotated a quarter turn to run along +x -- both flippers
	# share this one shape and the right one simply rests past 180 degrees.
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = TableLayout.FLIPPER_RADIUS
	capsule.height = length + TableLayout.FLIPPER_RADIUS * 2.0
	shape.shape = capsule
	shape.position = Vector2(length * 0.5, 0.0)
	shape.rotation = PI * 0.5
	add_child(shape)

	rotation = rest_angle
	set_meta("length", length)


func _physics_process(delta: float) -> void:
	var want := Input.is_action_pressed(action) and not disabled and not Run.tilted
	var sweep := TableLayout.FLIPPER_SWEEP_TIME
	if Run.has_coil("hot_winding"):
		sweep *= HOT_WINDING_SCALE
	var step := delta / sweep
	var was := _t
	_t = clampf(_t + (step if want else -step), 0.0, 1.0)
	# lerp_angle takes the short way round, which for both flippers is the
	# 58-degree sweep and never the 302-degree one.
	rotation = lerp_angle(rest_angle, up_angle, _t)
	# Rotating the node alone would redraw fine, but the side face is offset
	# against global down and so has to be recomputed as the bat turns.
	if not is_equal_approx(was, _t):
		queue_redraw()


## The bat's length, which varies with the Wide Flippers mod.
func bat_length() -> float:
	return get_meta("length", TableLayout.FLIPPER_LENGTH)


## The far end of the bat, in table space.
func tip() -> Vector2:
	return position + Vector2(bat_length(), 0.0).rotated(rotation)


## True while the bat is down far enough for a ball to be landing *on* it rather
## than being struck by it.
func is_resting() -> bool:
	return _t <= DEAD_BOUNCE_MAX_T


## The kick Dead Bounce gives a ball that has settled on a lowered flipper.
## Angled along the bat and up, so the ball is returned into the playfield
## rather than punted straight into the wall beside it.
func dead_bounce_impulse() -> Vector2:
	return Vector2(0.0, -DEAD_BOUNCE_SPEED).rotated(rotation * 0.35)


func _draw() -> void:
	var length: float = get_meta("length", TableLayout.FLIPPER_LENGTH)
	var r := TableLayout.FLIPPER_RADIUS
	var body := Color(0.86, 0.24, 0.32) if not disabled else Color(0.32, 0.30, 0.36)
	# The side face is offset in *global* down, not local: the flipper rotates
	# and the light does not, so an offset along the local axis would swing the
	# shadow around with the sweep and read as the bat flapping rather than
	# turning.
	var down := Vector2(0.0, TableLayout.EXTRUDE).rotated(-rotation)
	var side := body.darkened(0.62)
	draw_line(down, Vector2(length, 0.0) + down, side, r * 2.0)
	draw_circle(down, r, side)
	draw_line(Vector2.ZERO, Vector2(length, 0.0), body, r * 2.0)
	draw_circle(Vector2.ZERO, r, body)
	draw_circle(Vector2(length, 0.0), r * 0.8, body)
	draw_circle(Vector2.ZERO, r * 0.45, Color(0.20, 0.19, 0.24))
