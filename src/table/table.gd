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
const NUDGE_IMPULSE := 105.0
const SHAKE_DECAY := 9.0
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
	_build_post()
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
		_rollovers.append(s)

	var spinner := Sensor.new()
	spinner.position = TableLayout.SPINNER_RECT.get_center()
	add_child(spinner)
	spinner.setup(Catalog.Source.SPINNER, TableLayout.SPINNER_RECT.size)
	spinner.scored.connect(_on_scored)

	var orbit := Sensor.new()
	orbit.position = TableLayout.ORBIT_RECT.get_center()
	add_child(orbit)
	orbit.setup(Catalog.Source.ORBIT, TableLayout.ORBIT_RECT.size)
	orbit.scored.connect(_on_scored)


func _build_post() -> void:
	if not Run.has_mod("post_rubber"):
		return
	# Sits below the flipper tips, not between them: at 18px the drain gap is
	# barely two ball widths, so a post up there would wall it off completely
	# rather than give you a save you have to earn.
	var post := StaticBody2D.new()
	post.position = Vector2(TableLayout.LOWER_CENTRE, 330.0)
	post.collision_layer = 1
	post.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.9
	post.physics_material_override = mat
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 2.5
	cs.shape = circle
	post.add_child(cs)
	add_child(post)


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


## Sweeps up any ball that has left the table, as if it had drained.
func _catch_escapees() -> void:
	for b in balls.duplicate():
		if not is_instance_valid(b):
			balls.erase(b)
			continue
		if PLAY_BOUNDS.has_point(b.position):
			continue
		push_warning("ball escaped the table at %s -- treating it as drained"
			% b.position.round())
		_retire_ball(b, false)


## Removes a ball from play, ending the ball if it was the last one out.
func _retire_ball(b: Ball, via_outlane: bool) -> void:
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

	_draw_plunger()


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


func _draw_plunger() -> void:
	var x := TableLayout.BALL_REST.x
	var top := TableLayout.LANE_FLOOR_Y - 2.0
	var travel := 14.0
	draw_line(Vector2(x, top), Vector2(x, top + 8.0), Color(0.30, 0.32, 0.44), 5.0)
	if _plunge > 0.0:
		draw_rect(Rect2(x - 6.0, top - travel * _plunge, 12.0, travel * _plunge),
			Color(0.95, 0.45, 0.35))
