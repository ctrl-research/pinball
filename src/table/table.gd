class_name Table
extends Node2D
## Builds the machine from `TableLayout` and runs everything physical about it:
## the plunger, nudging, the drain, and the boss hazards that act on hardware
## rather than on arithmetic.
##
## It reports events (`drained`, `bank_cleared`) and never decides anything
## about the run -- that is `game.gd` reading `Run`.

signal drained(via_outlane: bool)

const BG_FAR := Color(0.052, 0.048, 0.078)
const BG_NEAR := Color(0.105, 0.096, 0.145)
const WALL_COLOUR := Color(0.42, 0.44, 0.62)
const WALL_SIDE := Color(0.17, 0.18, 0.27)
## Filled parts sit slightly darker than the stroked walls so the divider
## reads as a piece of the playfield rather than a very fat wall.
const SOLID_COLOUR := Color(0.28, 0.30, 0.44)
const LANE_COLOUR := Color(0.14, 0.15, 0.23)

## How far the outlane mouth moves for each effect that acts on it. The boss
## opens it, the mod closes it, and both can be in play at once.
const WIDE_DRAIN_SHIFT := 10.0
const OUTLANE_GUARD_SHIFT := -6.0

## Charge per second on the plunger, so a full pull takes ~0.7s of holding.
const PLUNGE_CHARGE_RATE := 1.4
## Bumper Gravity. Deliberately weak and short-ranged: a pull strong enough to
## visibly yank the ball is a pull strong enough to hold it in the nest forever,
## and a consumable that ends the ball is not a power-up. This nudges the ball's
## path towards the cluster and lets the bumpers do the rest.
const GRAVITY_WELL_FORCE := 260.0
const GRAVITY_WELL_RANGE := 90.0

const NUDGE_IMPULSE := 105.0
const SHAKE_DECAY := 9.0

## How close to the bat a falling ball has to be for Dead Bounce to catch it,
## and how long before the same ball can be caught again. The cooldown is what
## makes it one kick per landing rather than one per physics tick.
## Completing the top lanes pays this many lanes' worth on top of the three the
## player already scored getting there.
const LANE_GROUP_BONUS := 5

## The ramp's palette. Cool and light against the playfield's warm wood and the
## walls' lilac-grey, because the one thing the drawing has to say is that this
## is not another wall.
const RAMP_RAIL := Color(0.44, 0.52, 0.70)
const RAMP_FLOOR := Color(0.16, 0.20, 0.31)
const RAMP_SHEEN := Color(0.30, 0.38, 0.56)
const RAMP_MOUTH := Color(0.38, 0.64, 0.92)

## The saucer reads warm where the ramp reads cool, so the table's two capture
## elements are told apart at a glance rather than by memory.
## How long the saucer stays shut after spitting a ball out.
## How hard a ball has to be travelling *upward* to make the ramp.
const RAMP_ENTRY_SPEED := 60.0

const SAUCER_REARM := 0.9

const SAUCER_RIM := Color(0.86, 0.62, 0.28)
const SAUCER_LIP := Color(1.0, 0.84, 0.46)

const DEAD_BOUNCE_REACH := TableLayout.BALL_RADIUS + TableLayout.FLIPPER_RADIUS + 2.5
const DEAD_BOUNCE_COOLDOWN_MS := 300.0

## How hard the Kickback coil fires a ball back up the left outlane. Enough to
## clear the lane and rejoin the playfield, on the same reasoning as the plunge
## floor: a save that returns the ball to the same spot is not a save.
const KICKBACK_SPEED := 620.0
const WARP_PERIOD := 3.0
const DROP_RESET_DELAY := 0.8

## Anything outside this is not a ball in play. Generous on every side: real
## play reaches y~10 at the arch, y~344 at the drain and x~270 in the lane.
##
## This is a backstop, not the containment. The geometry is what keeps the ball
## in, and tests/containment_test.tscn is what proves it -- but no amount of
## testing proves there is no hole left, and the failure this guards against is
## the worst one the game has: a ball that leaves the cabinet never drains, so
## the stage never ends and the run cannot even be lost. Costing the player a
## ball is a bad outcome. Costing them the run with no way to act is not an
## outcome at all.
const PLAY_BOUNDS := Rect2(-24.0, -40.0, 328.0, 420.0)

var balls: Array[Ball] = []
var home_position := Vector2.ZERO
var active := false

var _wall_lines: Array = []
var _solid_polys: Array = []
var _outlane_polys: Array = []
var _saucer_ball: Ball
var _saucer_t := 0.0
var _saucer_cool := 0.0
## Kickback is one use per stage. A save you can spend twice on one ball is not
## a save, it is a wall.
var _kickback_used := false
var _drop_targets: Array[Target] = []
var _rollovers: Array[Sensor] = []
var _left_flipper: Flipper
var _right_flipper: Flipper
var _plunge := 0.0
var _shake := Vector2.ZERO
var _warp_t := 0.0
var _drop_reset_t := -1.0
var _fog: ColorRect
var _gate: StaticBody2D
var _gate_shape: CollisionShape2D
var _gate_sensor: Area2D
var _gate_closed_for := 0.0
var _bumper_spots: Array = []
var _portal_t := 0.0


func _ready() -> void:
	build()
	# Deferred for the same reason as the drain: this fires from inside a
	# bumper's Area2D signal, and spawning a ball there builds collision shapes
	# during the physics flush.
	Run.ball_awarded.connect(_spawn_extra_ball, CONNECT_DEFERRED)


# --- Construction -------------------------------------------------------------


func build() -> void:
	# Removed before freeing, not just queued: a rebuild happens between stages
	# and a queued-but-still-parented wall body would collide for one more
	# frame alongside the wall that replaced it.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	balls.clear()
	_drop_targets.clear()
	_rollovers.clear()

	var mouth := 0.0
	if Run.boss_active("wide_drain"):
		mouth += WIDE_DRAIN_SHIFT
	if Run.has_mod("outlane_guards"):
		mouth += OUTLANE_GUARD_SHIFT

	_wall_lines = TableLayout.walls(mouth)
	_solid_polys = TableLayout.solids(mouth)
	_outlane_polys = TableLayout.outlane_polys(mouth)

	_build_walls()
	_build_flippers()
	_build_bumpers()
	_build_slingshots()
	_build_targets()
	_build_sensors()
	_build_gate()
	_build_drain()
	_build_fog()
	queue_redraw()


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.25  # dead, so the live rubbers read as live by contrast
	mat.friction = 0.05  # see the note on rolling resistance in ball.gd
	body.physics_material_override = mat
	for line in _wall_lines:
		# Strokes the centreline into a closed ribbon with rounded caps, so a
		# ball cannot catch on a wall's square end. Thickness is per-wall: the
		# arch is collided with far deeper than it is drawn.
		var shapes := Geometry2D.offset_polyline(
			line, TableLayout.WALL_THICKNESS * 0.5,
			Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		for poly in shapes:
			var cp := CollisionPolygon2D.new()
			cp.polygon = poly
			body.add_child(cp)
	# Filled regions go in as-is. CollisionPolygon2D decomposes a concave
	# polygon into convex pieces itself, which is what the divider wedge needs.
	for poly in _solid_polys:
		var cp := CollisionPolygon2D.new()
		cp.polygon = poly
		body.add_child(cp)
	# Collided with, never drawn: the cap behind the arch.
	for poly in TableLayout.hidden_solids():
		var cp := CollisionPolygon2D.new()
		cp.polygon = poly
		body.add_child(cp)
	add_child(body)


func _build_flippers() -> void:
	_left_flipper = Flipper.new()
	_left_flipper.position = TableLayout.LEFT_FLIPPER_PIVOT
	add_child(_left_flipper)
	_left_flipper.setup(true)

	_right_flipper = Flipper.new()
	_right_flipper.position = TableLayout.RIGHT_FLIPPER_PIVOT
	add_child(_right_flipper)
	_right_flipper.setup(false)


func _build_bumpers() -> void:
	var spots: Array = TableLayout.BUMPERS.duplicate()
	if Run.has_mod("extra_bumper"):
		spots.append(TableLayout.BUMPER_MOD_SLOT)
	_bumper_spots = spots
	for spot in spots:
		var b := Bumper.new()
		b.position = spot
		add_child(b)
		b.setup()
		b.scored.connect(_on_scored)


func _build_slingshots() -> void:
	for is_left in [true, false]:
		var s := Slingshot.new()
		add_child(s)
		s.setup(TableLayout.slingshot(is_left))
		s.scored.connect(_on_scored)


func _build_targets() -> void:
	for spot in TableLayout.DROP_TARGETS:
		var t := Target.new()
		t.position = spot
		add_child(t)
		t.setup(true)
		t.scored.connect(_on_scored)
		t.dropped.connect(_check_drop_bank)
		_drop_targets.append(t)
	for spot in TableLayout.STANDUP_TARGETS:
		var t := Target.new()
		t.position = spot
		add_child(t)
		t.setup(false)
		t.scored.connect(_on_scored)


func _build_sensors() -> void:
	for spot in TableLayout.ROLLOVERS:
		var s := Sensor.new()
		s.position = spot
		add_child(s)
		s.setup(Catalog.Source.ROLLOVER, TableLayout.ROLLOVER_SIZE)
		s.scored.connect(_on_scored)
		s.scored.connect(_check_lane_group.unbind(2))
		_rollovers.append(s)

	var spinner := Sensor.new()
	spinner.position = TableLayout.SPINNER_RECT.get_center()
	add_child(spinner)
	spinner.setup(Catalog.Source.SPINNER, TableLayout.SPINNER_RECT.size)
	spinner.scored.connect(_on_scored)

	# The ramp mouth and the saucer are Areas rather than Sensors: a Sensor
	# scores and lets the ball through, and both of these take the ball away
	# instead. They report the hit themselves once the capture has happened.
	var ramp := Area2D.new()
	ramp.position = TableLayout.RAMP_ENTRY.get_center()
	ramp.collision_layer = 0
	ramp.collision_mask = 2
	var ramp_shape := CollisionShape2D.new()
	var ramp_rect := RectangleShape2D.new()
	ramp_rect.size = TableLayout.RAMP_ENTRY.size
	ramp_shape.shape = ramp_rect
	ramp.add_child(ramp_shape)
	add_child(ramp)
	ramp.body_entered.connect(func(body: Node) -> void:
		if body is Ball:
			_enter_ramp(body as Ball))

	var saucer := Area2D.new()
	saucer.position = TableLayout.SAUCER_CENTRE
	saucer.collision_layer = 0
	saucer.collision_mask = 2
	var saucer_shape := CollisionShape2D.new()
	var saucer_circle := CircleShape2D.new()
	saucer_circle.radius = TableLayout.SAUCER_RADIUS
	saucer_shape.shape = saucer_circle
	saucer.add_child(saucer_shape)
	add_child(saucer)
	saucer.body_entered.connect(func(body: Node) -> void:
		if body is Ball:
			_enter_saucer(body as Ball))

	var orbit := Sensor.new()
	orbit.position = TableLayout.ORBIT_RECT.get_center()
	add_child(orbit)
	orbit.setup(Catalog.Source.ORBIT, TableLayout.ORBIT_RECT.size)
	orbit.scored.connect(_on_scored)


## The plunger lane's one-way gate.
##
## Fails *open*, deliberately. A gate stuck closed traps the ball in the lane
## and the game cannot be played at all; a gate stuck open only restores the
## behaviour of not having one. So the default state is disabled and closing it
## takes a positive detection each frame.
func _build_gate() -> void:
	_gate = StaticBody2D.new()
	_gate.name = "LaneGate"
	_gate.collision_layer = 1
	_gate.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.1
	_gate.physics_material_override = mat

	var mid := (TableLayout.GATE_A + TableLayout.GATE_B) * 0.5
	var span := TableLayout.GATE_B - TableLayout.GATE_A
	_gate.position = mid
	_gate.rotation = span.angle()

	_gate_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(span.length(), 3.0)
	_gate_shape.shape = rect
	_gate_shape.disabled = true
	_gate.add_child(_gate_shape)
	add_child(_gate)

	_gate_sensor = Area2D.new()
	_gate_sensor.position = TableLayout.GATE_SENSOR.get_center()
	_gate_sensor.collision_layer = 0
	_gate_sensor.collision_mask = 2
	var sensor_shape := CollisionShape2D.new()
	var sensor_rect := RectangleShape2D.new()
	sensor_rect.size = TableLayout.GATE_SENSOR.size
	sensor_shape.shape = sensor_rect
	_gate_sensor.add_child(sensor_shape)
	add_child(_gate_sensor)


func _update_gate(delta: float) -> void:
	if _gate_sensor == null:
		return
	for body in _gate_sensor.get_overlapping_bodies():
		# Descending into the lane mouth is the only thing the gate stops. A
		# ball on its way out is travelling up through the same space.
		if body is Ball and (body as Ball).linear_velocity.y > 20.0:
			_gate_closed_for = TableLayout.GATE_HOLD
			break
	_gate_closed_for = maxf(0.0, _gate_closed_for - delta)
	_gate_shape.set_deferred("disabled", _gate_closed_for <= 0.0)


func _build_drain() -> void:
	var drain := Area2D.new()
	drain.name = "Drain"
	drain.position = Vector2(TableLayout.WIDTH * 0.5, TableLayout.DRAIN_Y + 10.0)
	drain.collision_layer = 0
	drain.collision_mask = 2
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TableLayout.WIDTH + 40.0, 20.0)
	cs.shape = rect
	drain.add_child(cs)
	add_child(drain)
	drain.body_entered.connect(_on_drain)


func _build_fog() -> void:
	_fog = ColorRect.new()
	_fog.position = Vector2.ZERO
	_fog.size = Vector2(TableLayout.WIDTH, 130.0)
	_fog.color = Color(BG_FAR.r, BG_FAR.g, BG_FAR.b, 0.97)
	_fog.z_index = 20
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.visible = Run.boss_active("fog")
	add_child(_fog)


# --- Balls --------------------------------------------------------------------


## Called when a new stage starts, not a new ball: the Kickback is a once-a-
## stage save and must not come back with every serve.
func reset_stage_saves() -> void:
	_kickback_used = false


func serve_ball() -> void:
	for b in balls:
		if is_instance_valid(b):
			b.queue_free()
	balls.clear()
	_plunge = 0.0
	for t in _drop_targets:
		t.reset_target()
	for r in _rollovers:
		r.unlight()
	# The type is decided here, before the body exists, which is what makes a
	# ball's size safe to vary at all.
	Run.take_next_ball()
	_add_ball(TableLayout.BALL_REST, true)


func _add_ball(at: Vector2, in_lane: bool) -> Ball:
	var b := Ball.new()
	b.position = at
	b.in_plunger_lane = in_lane
	add_child(b)
	balls.append(b)
	return b


## Drop a ball at a given spot on the playfield. Exists for tests: the inlane
## regression test needs to place a ball on a specific lane and watch where it
## ends up, which serve_ball() cannot express.
func spawn_ball_at(at: Vector2) -> Ball:
	return _add_ball(at, false)


func _spawn_extra_ball() -> void:
	# Dropped into the arch rather than the lane: a multiball that has to be
	# plunged is not a multiball.
	var b := _add_ball(Vector2(TableLayout.LOWER_CENTRE, 70.0), false)
	b.linear_velocity = Vector2(randf_range(-60.0, 60.0), 40.0)


func ball_in_play() -> bool:
	return not balls.is_empty()


# --- Per-frame ----------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_shake = _shake.lerp(Vector2.ZERO, minf(1.0, delta * SHAKE_DECAY))
	position = home_position + _shake

	if not active:
		return

	_track_balls()
	_catch_escapees()
	_update_ramp(delta)
	_update_saucer(delta)
	_apply_bumper_gravity(delta)
	_apply_dead_bounce()
	if Run.effect_active("wormhole"):
		_portal_t += delta
		queue_redraw()
	_update_plunger(delta)
	_update_gate(delta)
	_update_warp(delta)
	_update_drop_reset(delta)


func _track_balls() -> void:
	for b in balls:
		if not is_instance_valid(b):
			continue
		var p := b.position
		b.in_plunger_lane = p.x > TableLayout.LANE_DIVIDER_X and p.y > TableLayout.LANE_DIVIDER_TOP
		# Remembered rather than tested at the moment of the drain, because by
		# then the ball is below the table and inside nothing.
		var in_outlane := false
		for poly in _outlane_polys:
			if Geometry2D.is_point_in_polygon(p, poly):
				in_outlane = true
				break
		if in_outlane:
			b.set_meta("via_outlane", true)






## "Dead Bounce": kicks a ball off a *lowered* flipper instead of letting it die
## there.
##
## Without the coil that ball is simply lost. Measured on the bare table, one
## dropped just above the left flipper rolls off and drains 1.03 seconds later,
## and nothing the player presses in that second saves it -- flipping does not
## catch it, because the bat sweeps out from underneath.
##
## This is a *contact* event, not a resting state, and the first version of it
## got that wrong: it waited for the ball to slow below 90px/s, which never
## happens. The ball lands on the bat at around 120px/s and only accelerates as
## it rolls off, so the coil did nothing at all and the drain simply happened
## 0.09s later.
func _apply_dead_bounce() -> void:
	if not Run.has_coil("dead_bounce"):
		return
	var now := float(Time.get_ticks_msec())
	for b in balls:
		if not is_instance_valid(b) or b.in_plunger_lane:
			continue
		# Falling only. A ball already on its way up has been dealt with, and
		# kicking it again is how a save becomes a trampoline.
		if b.linear_velocity.y <= 0.0:
			continue
		if now < float(b.get_meta("dead_bounce_until", 0.0)):
			continue
		for flipper: Flipper in [_left_flipper, _right_flipper]:
			if flipper == null or not flipper.is_resting():
				continue
			# Distance to the bat itself rather than to its pivot, so a ball
			# beside the flipper root -- which is the drain, not the bat -- is
			# not rescued by something it never touched.
			var closest := Geometry2D.get_closest_point_to_segment(
				b.position, flipper.position, flipper.tip())
			if b.position.distance_to(closest) > DEAD_BOUNCE_REACH:
				continue
			if b.position.y > closest.y:  # under the bat, not resting on it
				continue
			b.linear_velocity = flipper.dead_bounce_impulse()
			b.set_meta("dead_bounce_until", now + DEAD_BOUNCE_COOLDOWN_MS)
			Sfx.play("sling")
			break


## Lighting every top lane pays a bonus and resets them.
##
## Three lanes rather than the two the table had, because two is a pair and
## three is a *group*: the arch stops being somewhere the ball passes through
## and becomes a thing with a state the player is trying to advance. The bonus
## is deliberately worth more than the three lanes that earned it, or completing
## the set would be worth exactly as much as not bothering.
func _check_lane_group() -> void:
	for r in _rollovers:
		if not r.lit:
			return
	for r in _rollovers:
		r.unlight()
	var points := Run.register_hit(Catalog.Source.ROLLOVER, LANE_GROUP_BONUS)
	_on_scored(points, Vector2(TableLayout.LOWER_CENTRE, 56.0))
	Run.toast.emit("LANES COMPLETE")
	Sfx.play("drop")


## The ramp: carries a ball over the top of the table and drops it into the left
## orbit.
##
## The ball is taken out of the simulation for the trip -- frozen, with its
## collision off -- and walked along `TableLayout.ramp_path()` by hand. That is
## what "elevated" has to mean in a top-down projection: there is no third axis
## to lift it into, so the only honest way to say the ball is above the
## playfield is for the playfield to stop being able to touch it.
##
## It is released heading down the orbit lane rather than dropped still, because
## a ball that arrives with no speed trickles past the spinner and scores
## nothing -- which would make the ramp a worse shot than the orbit it feeds.
func _update_ramp(delta: float) -> void:
	for b in balls:
		if not is_instance_valid(b) or not b.held:
			continue
		if not b.has_meta("ramp_at"):
			continue
		var travelled := float(b.get_meta("ramp_at")) + TableLayout.RAMP_SPEED * delta
		var total := TableLayout.ramp_length()
		if travelled >= total:
			b.remove_meta("ramp_at")
			b.release(TableLayout.ramp_at(total)[0],
				Vector2(0.0, TableLayout.RAMP_EXIT_SPEED))
			continue
		b.set_meta("ramp_at", travelled)
		if b.freeze:
			b.position = TableLayout.ramp_at(travelled)[0]
	queue_redraw()


func _enter_ramp(b: Ball) -> void:
	if b.held or b.in_plunger_lane:
		return
	# The ramp has to be *shot*, not fallen into. Without this the mouth is a
	# hole in the middle of the right-hand playfield that swallows anything
	# drifting over it, which makes the table's best shot the one you cannot
	# help taking. A real ramp is entered from below with pace behind it.
	if b.linear_velocity.y > -RAMP_ENTRY_SPEED:
		return
	b.set_meta("ramp_at", 0.0)
	b.capture(TableLayout.RAMP_POINTS[0])
	Sfx.play("lane")
	_on_scored(Run.register_hit(Catalog.Source.RAMP), TableLayout.RAMP_ENTRY.get_center())


## The saucer: swallows the ball, holds it, kicks it back out.
##
## Every other element on this table resolves in the same tick it is touched.
## This one is the only place the ball stops, and that pause is the point --
## it is the moment a player reads the score they have just built.
func _update_saucer(delta: float) -> void:
	_saucer_cool = maxf(0.0, _saucer_cool - delta)
	if _saucer_ball == null or not is_instance_valid(_saucer_ball):
		_saucer_ball = null
		return
	_saucer_t -= delta
	if _saucer_ball.freeze:
		_saucer_ball.position = TableLayout.SAUCER_CENTRE
	queue_redraw()
	if _saucer_t > 0.0:
		return
	var b := _saucer_ball
	_saucer_ball = null
	# Released clear of the mouth, not at its centre. Re-enabling the ball's
	# collision layer inside the area counts as *entering* it, so a ball handed
	# back where it was swallowed is swallowed again on the same frame -- which
	# it was, forever.
	var out: Vector2 = TableLayout.SAUCER_KICK.normalized() * (
		TableLayout.SAUCER_RADIUS + b.radius + 2.0)
	b.release(TableLayout.SAUCER_CENTRE + out, TableLayout.SAUCER_KICK)
	# And a moment before it will take another, so a ball that is kicked into
	# something and comes straight back is a shot rather than a trap.
	_saucer_cool = SAUCER_REARM
	Sfx.play("plunge")


func _enter_saucer(b: Ball) -> void:
	if b.held or b.in_plunger_lane or _saucer_ball != null or _saucer_cool > 0.0:
		return
	b.capture(TableLayout.SAUCER_CENTRE)
	_saucer_ball = b
	_saucer_t = TableLayout.SAUCER_HOLD
	Sfx.play("target")
	_on_scored(Run.register_hit(Catalog.Source.SAUCER), TableLayout.SAUCER_CENTRE)


## Pulls the ball towards the bumper cluster while Bumper Gravity is running.
##
## Falls off with distance and stops entirely beyond its range, so the rest of
## the table plays normally -- the effect is "the nest is sticky", not "the
## table is tilted".
func _apply_bumper_gravity(delta: float) -> void:
	if not Run.effect_active("bumper_gravity"):
		return
	for b in balls:
		if not is_instance_valid(b) or b.in_plunger_lane:
			continue
		for spot in _bumper_spots:
			var to_bumper: Vector2 = spot - b.position
			var distance := to_bumper.length()
			if distance < 1.0 or distance > GRAVITY_WELL_RANGE:
				continue
			var falloff := 1.0 - distance / GRAVITY_WELL_RANGE
			b.apply_central_impulse(
				to_bumper / distance * GRAVITY_WELL_FORCE * falloff * delta)


## Sweeps up any ball that has left the table, as if it had drained.
func _catch_escapees() -> void:
	for b in balls.duplicate():
		if not is_instance_valid(b):
			balls.erase(b)
			continue
		# A carried ball is exactly where the table put it, which for the top of
		# the ramp is outside the bounds a rolling ball should ever reach.
		if b.held or PLAY_BOUNDS.has_point(b.position):
			continue
		push_warning("ball escaped the table at %s -- treating it as drained"
			% b.position.round())
		_retire_ball(b, false)


## Removes a ball from play, ending the ball if it was the last one out.
##
## Unless the Wormhole is open, in which case the ball is not lost at all: it
## comes back up the plunger lane and the player re-plunges it. That is the
## whole consumable -- for thirty seconds the bottom of the table stops being
## the end of the ball.
func _retire_ball(b: Ball, via_outlane: bool) -> void:
	# Checked before the Wormhole, because a kickback puts the ball back into
	# *play* while the wormhole only puts it back in the lane. Given both, the
	# one that keeps the ball moving is the better outcome for the player.
	if (via_outlane and Run.has_coil("kickback") and not _kickback_used
			and is_instance_valid(b) and b.position.x < TableLayout.LOWER_CENTRE):
		_kickback_used = true
		b.position = Vector2(TableLayout.OUTLANE_WIDTH * 0.5, 300.0)
		b.linear_velocity = Vector2(0.0, -KICKBACK_SPEED)
		b.angular_velocity = 0.0
		b.set_meta("via_outlane", false)
		Sfx.play("plunge")
		Run.toast.emit("KICKBACK")
		return
	if Run.effect_active("wormhole") and is_instance_valid(b):
		b.position = TableLayout.BALL_REST
		b.linear_velocity = Vector2.ZERO
		b.angular_velocity = 0.0
		b.in_plunger_lane = true
		b.set_meta("via_outlane", false)
		_plunge = 0.0
		Sfx.play("plunge")
		Run.toast.emit("WORMHOLE")
		return
	balls.erase(b)
	b.queue_free()
	# Deferred because this runs inside the physics server's query flush: the
	# listener re-serves a ball, and building one adds collision shapes to a new
	# body, which the server refuses to do mid-flush.
	if balls.is_empty():
		drained.emit.call_deferred(via_outlane)


func _update_plunger(delta: float) -> void:
	var lane_ball := _lane_ball()
	if lane_ball == null:
		_plunge = 0.0
		return
	if Input.is_action_pressed("plunge"):
		_plunge = minf(1.0, _plunge + delta * PLUNGE_CHARGE_RATE)
		queue_redraw()
		return
	# `just_released` is checked as well as the accumulated charge because a
	# quick tap can begin and end between two physics ticks, leaving a charge of
	# exactly zero. Without this, tapping the plunger does nothing at all, which
	# reads as a broken game rather than as a charge mechanic the player has yet
	# to discover. A tap launches at minimum power, which is a weak plunge --
	# a real outcome you can misplay, not a punishment for not knowing.
	if _plunge > 0.0 or Input.is_action_just_released("plunge"):
		var speed: float = lerpf(
			TableLayout.PLUNGE_MIN_SPEED, TableLayout.PLUNGE_MAX_SPEED, _plunge)
		lane_ball.linear_velocity = Vector2(0.0, -speed)
		lane_ball.in_plunger_lane = false
		_plunge = 0.0
		Sfx.play("plunge")
		queue_redraw()


func _lane_ball() -> Ball:
	for b in balls:
		if is_instance_valid(b) and b.in_plunger_lane and b.linear_velocity.length() < 30.0:
			return b
	return null


func _update_warp(delta: float) -> void:
	if not Run.boss_active("warp"):
		return
	_warp_t += delta
	var dead := fmod(_warp_t, WARP_PERIOD * 2.0) < WARP_PERIOD
	if _left_flipper.disabled != dead:
		_left_flipper.disabled = dead
		_left_flipper.queue_redraw()


func _update_drop_reset(delta: float) -> void:
	if _drop_reset_t < 0.0:
		return
	_drop_reset_t -= delta
	if _drop_reset_t <= 0.0:
		_drop_reset_t = -1.0
		for t in _drop_targets:
			t.reset_target()


func _process(_delta: float) -> void:
	if not active:
		return
	if Input.is_action_just_pressed("nudge_left"):
		_nudge(Vector2(1.0, -0.35))
	elif Input.is_action_just_pressed("nudge_right"):
		_nudge(Vector2(-1.0, -0.35))
	elif Input.is_action_just_pressed("nudge_up"):
		_nudge(Vector2(0.0, -1.0))


func _nudge(dir: Vector2) -> void:
	var result := Run.try_nudge()
	if result == 2:
		return  # the boss has taken nudging away
	# A tilt still shakes the cabinet. You should see what you did.
	_shake = -dir.normalized() * 3.0
	if result == 1:
		Sfx.play("tilt")
		return
	Sfx.play("nudge")
	for b in balls:
		if is_instance_valid(b):
			b.apply_central_impulse(dir.normalized() * NUDGE_IMPULSE)


# --- Events -------------------------------------------------------------------


func _check_drop_bank() -> void:
	for t in _drop_targets:
		if not t.down:
			return
	Run.drop_bank_cleared()
	Sfx.play("bank")
	_drop_reset_t = DROP_RESET_DELAY


func _on_drain(body: Node) -> void:
	if not (body is Ball):
		return
	var b := body as Ball
	Sfx.play("drain")
	# Multiball: only the last ball leaving the playfield ends the ball.
	_retire_ball(b, b.get_meta("via_outlane", false))


func _on_scored(points: int, at: Vector2) -> void:
	if points <= 0:
		return
	_popup(str(points), at)


func _popup(text: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(-14.0, -12.0)
	label.size = Vector2(28.0, 10.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.68))
	label.z_index = 15
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 12.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)


func set_fog(on: bool) -> void:
	if _fog != null:
		_fog.visible = on


# --- Rendering ----------------------------------------------------------------


func _draw() -> void:
	_draw_playfield()

	# The lanes the ball travels are painted a shade darker than the playfield
	# so the routes read at a glance -- inserts do this job on a real table and
	# a flat playfield is unreadable without them.
	for poly in _outlane_polys:
		draw_colored_polygon(poly, LANE_COLOUR)

	# Side faces first, then tops over them. Two passes over the whole set
	# rather than side-then-top per wall, so that where two walls overlap the
	# near one's top face still covers the far one's side.
	for poly in _solid_polys:
		draw_colored_polygon(TableLayout.shift(poly, TableLayout.WALL_EXTRUDE), WALL_SIDE)
	# The arch is drawn from its own line: its collision is the solid cap behind
	# it, which has no centreline to stroke.
	var arch := TableLayout.arch_polyline()
	for line in _wall_lines + [arch]:
		draw_polyline(TableLayout.shift(line, TableLayout.WALL_EXTRUDE),
			WALL_SIDE, TableLayout.WALL_THICKNESS)
	for line in _wall_lines + [arch]:
		draw_polyline(line, WALL_COLOUR, TableLayout.WALL_THICKNESS)
	for poly in _solid_polys:
		draw_colored_polygon(poly, SOLID_COLOUR)
		draw_polyline(poly, WALL_COLOUR, 1.5)

	# Drawn thin and pale whatever its state: a gate you can see swinging shut
	# reads as a bug, and on a real machine it is a wire flap you barely notice.
	draw_line(TableLayout.GATE_A, TableLayout.GATE_B, Color(0.34, 0.36, 0.50), 2.0)

	_draw_saucer()
	_draw_ramp()
	_draw_portals()
	_draw_plunger()


## The ramp, drawn last of the playfield furniture so it sits over everything it
## passes above -- which is the only way a top-down projection can say "this is
## higher than that".
##
## Two rails and a floor rather than a single stroke: a bare line reads as
## another wall, and the whole point of the ramp is that it is not one.
func _draw_ramp() -> void:
	var path := TableLayout.ramp_path()
	var w := TableLayout.RAMP_WIDTH

	# The side face first, offset down-screen and drawn wider, so the track
	# reads as standing off the playfield rather than painted onto it. This is
	# the only cue available: there is no third axis to lift it into.
	draw_polyline(TableLayout.shift(path, TableLayout.EXTRUDE * 2.0),
		Color(0.04, 0.04, 0.07), w + 5.0)
	# Cool metal against the warm wood, so it does not read as more wall. The
	# walls are lilac-grey; this is deliberately bluer and lighter.
	draw_polyline(path, RAMP_RAIL, w + 4.0)
	draw_polyline(path, RAMP_FLOOR, w)
	# A highlight down the centre of the floor, which is what makes a flat
	# stroke read as a channel with two raised edges.
	draw_polyline(path, RAMP_SHEEN, 2.0)

	# The mouth, brighter than the track, because the entry is the thing the
	# player is aiming at and the rest is just where the ball goes afterwards.
	var mouth := TableLayout.RAMP_ENTRY
	draw_rect(mouth.grow(1.0), Color(0.06, 0.07, 0.11))
	draw_rect(mouth, RAMP_RAIL)
	draw_rect(mouth.grow(-2.0), RAMP_MOUTH)
	draw_rect(mouth, Color(0.72, 0.86, 1.0), false, 1.0)

	# The ball riding it needs no drawing here: balls are child nodes, and a
	# parent's _draw runs before its children, so it is already over the rails.


## The saucer: a hole, so it is drawn as depth rather than as a lamp -- a dark
## well with a lit rim, and the ball sunk into it while it is held.
func _draw_saucer() -> void:
	var c := TableLayout.SAUCER_CENTRE
	var r := TableLayout.SAUCER_RADIUS
	# A lit metal rim, because against a dark playfield a dark hole is simply
	# not there: the first version read as a smudge and gave the player nothing
	# to aim at. The ring is what makes it a shot.
	draw_circle(c, r + 3.0, Color(0.10, 0.10, 0.16))
	draw_circle(c, r + 2.0, SAUCER_RIM)
	draw_circle(c, r - 0.5, Color(0.03, 0.03, 0.06))
	# A crescent of light on the far rim, so the hole reads as a bowl sunk into
	# the wood rather than as a disc lying on it.
	draw_arc(c, r - 0.5, PI * 1.1, PI * 1.9, 14, SAUCER_LIP, 1.5)
	if _saucer_ball != null and is_instance_valid(_saucer_ball):
		# Sunk: drawn smaller and dimmer than a ball on the playfield, because
		# it is below the surface rather than on it.
		draw_circle(c, _saucer_ball.radius * 0.8, _saucer_ball.tint.darkened(0.35))


## The wood, lit from the near end.
##
## Banded rather than smoothly graded: a 2D draw call has no gradient, and at
## this resolution a dozen steps is indistinguishable from one. The gradient is
## doing real work -- with a flat playfield the perspective warp alone reads as
## a picture that has been squashed, and the falloff toward the far end is what
## makes it read as distance instead.
func _draw_playfield() -> void:
	# A few pixels past the chute tips so the render target has no bare edge.
	var height := TableLayout.HEIGHT + TableLayout.CHUTE_OVERRUN + 6.0
	var bands := 14
	for i in bands:
		var t := float(i) / float(bands - 1)
		var y := height * float(i) / float(bands)
		draw_rect(Rect2(0.0, y, TableLayout.WIDTH, height / float(bands) + 1.0),
			BG_FAR.lerp(BG_NEAR, t))


## The two mouths of the wormhole: one across the drain, one at the plunger.
## Drawn only while it is open, because a portal that is always there stops
## reading as a thing you spent money on.
func _draw_portals() -> void:
	if not Run.effect_active("wormhole"):
		return
	var pulse := 0.5 + 0.5 * sin(_portal_t * 5.0)
	_draw_portal(Vector2(TableLayout.LOWER_CENTRE, TableLayout.DRAIN_Y - 4.0), 46.0, pulse)
	_draw_portal(TableLayout.BALL_REST + Vector2(0.0, 6.0), 12.0, 1.0 - pulse)


func _draw_portal(at: Vector2, width: float, pulse: float) -> void:
	var rings := 4
	for i in rings:
		var t := float(i) / float(rings)
		var w := width * (1.0 - t * 0.55)
		var h := w * 0.34
		var glow := Color(0.45, 0.30, 0.95).lerp(Color(0.60, 0.95, 1.0), t + pulse * 0.25)
		glow.a = 0.30 + 0.55 * (1.0 - t) * (0.55 + 0.45 * pulse)
		draw_arc(at, w * 0.5, 0.0, TAU, 24, glow, maxf(1.0, h * 0.22))


func _draw_plunger() -> void:
	var x := TableLayout.BALL_REST.x
	var top := TableLayout.LANE_FLOOR_Y - 2.0
	var travel := 14.0
	draw_line(Vector2(x, top), Vector2(x, top + 8.0), Color(0.30, 0.32, 0.44), 5.0)
	if _plunge > 0.0:
		draw_rect(Rect2(x - 6.0, top - travel * _plunge, 12.0, travel * _plunge),
			Color(0.95, 0.45, 0.35))
