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
	mat.bounce = 0.2
	mat.friction = 0.7  # grip, so a held flipper can cradle a ball
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
	var step := delta / TableLayout.FLIPPER_SWEEP_TIME
	_t = clampf(_t + (step if want else -step), 0.0, 1.0)
	# lerp_angle takes the short way round, which for both flippers is the
	# 58-degree sweep and never the 302-degree one.
	rotation = lerp_angle(rest_angle, up_angle, _t)


func _draw() -> void:
	var length: float = get_meta("length", TableLayout.FLIPPER_LENGTH)
	var r := TableLayout.FLIPPER_RADIUS
	var body := Color(0.86, 0.24, 0.32) if not disabled else Color(0.32, 0.30, 0.36)
	draw_line(Vector2.ZERO, Vector2(length, 0.0), body, r * 2.0)
	draw_circle(Vector2.ZERO, r, body)
	draw_circle(Vector2(length, 0.0), r * 0.8, body)
	draw_circle(Vector2.ZERO, r * 0.45, Color(0.20, 0.19, 0.24))
