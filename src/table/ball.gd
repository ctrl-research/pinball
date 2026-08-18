class_name Ball
extends RigidBody2D
## The silver ball.
##
## Deliberately dumb: it knows how to not tunnel and how to not get stuck, and
## nothing at all about scoring. Everything it touches reports the hit itself.

const RADIUS := TableLayout.BALL_RADIUS

## Hard speed ceiling. At 120Hz a ball at 900px/s advances 7.5px per tick,
## which is just under its own diameter -- so together with cast-shape CCD it
## cannot skip past a 6px wall. Raising this without raising the tick rate is
## how balls start escaping the table.
const MAX_SPEED := 900.0

## A ball that has been nearly still for this long somewhere it should not rest
## gets a nudge from the game itself. Real machines have this problem too and
## solve it with a ball-search relay; this is that relay.
const STUCK_SPEED := 6.0
const STUCK_TIME := 2.5

var in_plunger_lane := true

var _stuck_for := 0.0


func _ready() -> void:
	var mat := PhysicsMaterial.new()
	# The ball itself is dead; every surface declares its own liveliness. Godot
	# combines restitution by taking the maximum, so a bouncy ball would make
	# the outer walls as lively as the slingshot rubbers and the table would
	# read as one uniform trampoline.
	mat.bounce = 0.0
	# Near-frictionless on purpose. This is a top-down projection of an
	# inclined table: gravity here already *is* the incline component, and what
	# is left for a steel ball on a wooden playfield is rolling resistance,
	# which is almost nothing. A "realistic" sliding friction stalls the ball
	# on every shallow lane -- which is exactly what the headless sim caught.
	mat.friction = 0.1
	physics_material_override = mat

	mass = 1.0
	gravity_scale = 1.0
	linear_damp = 0.15
	angular_damp = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 2
	collision_mask = 1 | 2  # walls, and other balls during multiball

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var v := state.linear_velocity
	var speed := v.length()
	if speed > MAX_SPEED:
		state.linear_velocity = v / speed * MAX_SPEED


func _physics_process(delta: float) -> void:
	# Never ball-search a ball sitting in the plunger lane; that is where it is
	# supposed to be sitting still.
	if in_plunger_lane or linear_velocity.length() > STUCK_SPEED:
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for >= STUCK_TIME:
		_stuck_for = 0.0
		apply_central_impulse(Vector2(randf_range(-60.0, 60.0), -90.0))


func _draw() -> void:
	# The shadow is the single cheapest depth cue on the table: it is what
	# separates a ball resting *on* the playfield from a disc painted on it,
	# and it is the only thing that makes a ball airborne off a slingshot read
	# as airborne.
	draw_circle(TableLayout.BALL_SHADOW, RADIUS * 0.95, Color(0.0, 0.0, 0.0, 0.45))

	# Drawn rather than sprited so the ball scales cleanly with the layout
	# constants; the highlight is what sells it as a chrome sphere at 8px.
	draw_circle(Vector2.ZERO, RADIUS, Color(0.78, 0.80, 0.86))
	draw_circle(Vector2(-1.2, -1.2), RADIUS * 0.45, Color(0.96, 0.97, 1.0))
	draw_arc(Vector2.ZERO, RADIUS - 0.5, 0.5, 2.4, 8, Color(0.36, 0.38, 0.46), 1.0)
