class_name TableLayout
extends RefCounted
## The machine, as data.
##
## Every wall, target and lane on the playfield is described here as plain
## numbers, and `table.gd` turns that description into collision shapes while
## `table_art.gd` draws the same numbers. Nothing is hand-placed in a .tscn.
##
## That is not tidiness for its own sake. Table mods are a core roguelike axis
## of this game ("Extra Bumper", "Wide Flippers", "Post Rubber", "Outlane
## Guards"), and a mod is only cheap to build if the playfield is a value that
## can be edited before it is instantiated. A scene full of hand-placed nodes
## would make every mod a bespoke patch. It also means collision and rendering
## cannot drift apart, because there is only one source for both.
##
## Coordinates are table-local pixels: origin at the top-left of the playfield,
## +x right, +y down. The table node is positioned in the viewport by `game.gd`.

# --- Overall dimensions -------------------------------------------------------

const WIDTH := 280.0
const HEIGHT := 344.0

const WALL_THICKNESS := 6.0
const BALL_RADIUS := 4.0

## The lower playfield is bounded by the left wall and the plunger-lane divider,
## not by the outer edge of the cabinet — so its centre sits left of the arch's
## centre. Real machines do exactly this; the plunger lane eats the right side
## below the arch and the flippers straddle what is left.
const PLAYFIELD_LEFT := 6.0
const PLAYFIELD_RIGHT := 248.0
const LOWER_CENTRE := (PLAYFIELD_LEFT + PLAYFIELD_RIGHT) * 0.5  # 127.0

# --- Top arch -----------------------------------------------------------------

const ARCH_CENTRE := Vector2(140.0, 72.0)
const ARCH_RX := 134.0
const ARCH_RY := 62.0

# --- Plunger lane -------------------------------------------------------------

const LANE_DIVIDER_X := 251.0  # wall centre; spans 248..254
const LANE_DIVIDER_TOP := 96.0
const LANE_FLOOR_Y := 332.0
const LANE_RIGHT_X := 274.0
const BALL_REST := Vector2(264.0, 320.0)

## One-way gate across the mouth of the plunger lane. Without it a ball that
## wanders back into the lane is a free save: it rolls down to the plunger and
## can simply be launched again, never draining and never losing its MULT.
##
## It slopes *up* to the right on purpose. A ball that arrives from the
## playfield lands on the gate and rolls back down its slope into the playfield
## instead of balancing on it, which is what stops the gate oscillating between
## open and closed underneath a stationary ball.
const GATE_A := Vector2(254.0, 92.0)
const GATE_B := Vector2(274.0, 84.0)
const GATE_SENSOR := Rect2(251.0, 62.0, 26.0, 28.0)
## Held closed for long enough that a ball resting on it has time to roll clear
## before it opens again.
const GATE_HOLD := 0.6

## Impulse speeds for a zero-charge and a full-charge plunge, in px/s.
##
## The floor is not a taste decision, it is an escape velocity. Lifting the ball
## from its rest at y=320 clear of the lane divider at y=96 needs
## sqrt(2 * 480 * 224) ~= 464px/s, and reaching the arch needs ~511. An earlier
## version set the minimum to 400 and described it as "a weak plunge that dies
## in the orbit, a real outcome you can misplay" -- but 400 cannot leave the
## lane at all. The ball rose a little, fell back, and sat there until the
## player plunged again, which reads as a broken game rather than a bad shot.
##
## So the minimum clears the arch with margin, and the charge controls *where*
## the ball ends up rather than *whether* it gets there.
const PLUNGE_MIN_SPEED := 540.0
const PLUNGE_MAX_SPEED := 760.0

# --- Flippers -----------------------------------------------------------------

const FLIPPER_LENGTH := 34.0
const FLIPPER_RADIUS := 4.5
const FLIPPER_SPAN := 39.0  # pivot offset either side of LOWER_CENTRE

const LEFT_FLIPPER_PIVOT := Vector2(LOWER_CENTRE - FLIPPER_SPAN, 300.0)   # (88, 300)
const RIGHT_FLIPPER_PIVOT := Vector2(LOWER_CENTRE + FLIPPER_SPAN, 300.0)  # (166, 300)

## Rest and flipped angles. Both flippers use a shape running along +x from the
## pivot; the right one is simply rotated past 180 degrees, which keeps one
## shape and one sweep routine for both instead of a mirrored special case.
const LEFT_REST_DEG := 28.0
const LEFT_UP_DEG := -30.0
const RIGHT_REST_DEG := 152.0
const RIGHT_UP_DEG := 210.0

## A 58-degree sweep in 48ms is roughly a real solenoid. Fast enough to feel
## instant, slow enough that the kinematic body still resolves contacts at
## 120Hz instead of teleporting through the ball.
const FLIPPER_SWEEP_TIME := 0.048

# --- Lanes --------------------------------------------------------------------

## The outlane channel, between the cabinet wall and the divider's left face.
## Barely wider than a ball, as on a real machine: entering one should take a
## bad bounce rather than merely drifting left. At 18 it was a lane the ball
## fell into by default.
const OUTLANE_WIDTH := 11.0
## Inner face of the left cabinet wall -- the outlane's outer boundary.
const CABINET_INNER := PLAYFIELD_LEFT + WALL_THICKNESS * 0.5

## The inlane/outlane divider, as a solid.
##
## This is the single most load-bearing shape on the table, and the first
## version of it lost the ball every time.
##
## It used to be a *line* -- the inlane floor -- with the outlane's outer wall
## generated as a parallel offset of it. That forces both lanes to end in the
## same place, and there is nowhere for them both to go: the inlane wants to end
## at the flipper, and the outlane needs to get past the flipper's root without
## touching it. The compromise was ending the inlane about 12px short and
## letting the ball hop the gap. In play it does not hop. It falls straight down
## the gap, so the inlane fed the drain and *both* side paths were a guaranteed
## loss.
##
## The fix is the shape a real machine uses: one solid wedge whose top edge is
## the inlane floor and whose left face is the outlane's inner wall. The two
## lanes diverge instead of running parallel -- the inlane cuts inward and ends
## against the flipper root with no gap at all, while the outlane drops straight
## down the outside of it. Because the wedge is filled, there is no longer
## anywhere between the inlane and the flipper for a ball to fall into.
##
## Every edge is either sloped or vertical. No horizontal ledges, because a
## ledge is where a ball comes to rest and stays.
const DIVIDER_PEAK_INSET := 4.0  ## peak sits this far right of the outlane wall
const DIVIDER_FLOOR := [
	Vector2(46, 263), Vector2(66, 279), Vector2(84, 291),
]
## Where the wedge's left face begins, and where its base sits. The base is
## below the drain line so the outlane is a chute all the way out.
const DIVIDER_SHOULDER_Y := 256.0
const DIVIDER_PEAK_Y := 244.0

## Left orbit guide: makes a lane up the left side wide enough for one ball.
## It stops short of the inlane floor on purpose — the gap between the two is
## the outlane mouth, so a ball coming down the orbit either catches the inlane
## and lives or slips past it and drains. That gamble is the point of the orbit.
const LEFT_ORBIT_GUIDE := [
	Vector2(30, 96), Vector2(28, 150), Vector2(32, 200), Vector2(34, 232),
]

# --- Scoring elements ---------------------------------------------------------

const BUMPER_RADIUS := 12.0
const BUMPERS := [
	Vector2(100, 130),
	Vector2(154, 118),
	Vector2(127, 168),
]
## Where "Extra Bumper" (table mod) drops its fourth pop bumper.
const BUMPER_MOD_SLOT := Vector2(127, 100)

## The kicking face is called out separately from the triangle, because the
## kick direction is that face's normal and re-deriving it from the polygon's
## winding order is a bug waiting for someone to reorder a vertex.
## The bottom edge is the inlane's ceiling, so it has to clear the inlane floor
## by more than a ball diameter along its whole length.
const LEFT_SLINGSHOT_TRI := [Vector2(52, 212), Vector2(54, 256), Vector2(98, 244)]
const LEFT_SLINGSHOT_FACE := [Vector2(52, 212), Vector2(98, 244)]
const SLINGSHOT_KICK := 260.0

const TARGET_SIZE := Vector2(6, 16)
const DROP_TARGETS := [
	Vector2(52, 150),
	Vector2(52, 172),
	Vector2(52, 194),
]
const STANDUP_TARGETS := [
	Vector2(232, 140),
	Vector2(232, 168),
]

## Spinner sits in the left orbit lane, so the only way to score it is to make
## the orbit — it is the reward half of the orbit's risk.
const SPINNER_RECT := Rect2(9, 122, 18, 16)
const ROLLOVER_SIZE := Vector2(22, 10)
const ROLLOVERS := [
	Vector2(105, 56),
	Vector2(149, 56),
]
## Crossing this, high on the left orbit, completes an orbit shot.
const ORBIT_RECT := Rect2(9, 96, 18, 12)

## The drain line sits exactly at the bottom of the playfield, and the outlane
## chutes stop 6px below it. Both are bounded so that the whole table, chute
## tips included, fits inside the 640x360 viewport once the table is placed at
## its origin -- otherwise the drain is drawn off the bottom of the screen and
## the ball vanishes a moment before it is lost.
const DRAIN_Y := HEIGHT
const CHUTE_OVERRUN := 6.0


# --- Presentation -------------------------------------------------------------

## Every solid part is drawn twice: a dark side face offset toward the player,
## then the lit top face over it. In a top-down view with the camera at the near
## edge, the only side face you can see is the near one, so the offset is +y.
##
## These are in flat playfield pixels, before the perspective warp -- which
## means a part near the far end has its extrusion foreshortened along with
## everything else, for free. That is the payoff for warping the finished image
## rather than the drawing code.
const EXTRUDE := 3.0
const WALL_EXTRUDE := 2.5
const BALL_SHADOW := Vector2(1.5, 3.0)

## Lamp inserts are flush with the playfield and deliberately get no side face.
## Giving them one would make them read as blocks standing on the wood, and
## half of what sells the rest as raised is that these are not.


## A polyline shifted toward the player, for drawing a part's side face.
static func shift(pts: PackedVector2Array, dy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + Vector2(0.0, dy))
	return out


# --- Derived geometry ---------------------------------------------------------


## The top arch, as a polyline running left-to-right along its inside face.
static func arch_polyline(steps: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t: float = PI * (1.0 - float(i) / float(steps))
		pts.append(ARCH_CENTRE + Vector2(ARCH_RX * cos(t), -ARCH_RY * sin(t)))
	return pts


## Mirror a point across the lower playfield's centre line.
static func mirror(p: Vector2) -> Vector2:
	return Vector2(2.0 * LOWER_CENTRE - p.x, p.y)


static func mirror_all(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(mirror(p))
	return out


## One slingshot, mirrored from the left one rather than written out twice --
## the two must stay symmetric, and two lists of coordinates do not.
static func slingshot(is_left: bool) -> Dictionary:
	var tri := PackedVector2Array(LEFT_SLINGSHOT_TRI)
	var a: Vector2 = LEFT_SLINGSHOT_FACE[0]
	var b: Vector2 = LEFT_SLINGSHOT_FACE[1]
	if not is_left:
		tri = mirror_all(tri)
		a = mirror(a)
		b = mirror(b)
	return {"tri": tri, "face_a": a, "face_b": b}


## The inlane/outlane divider, as a filled polygon.
##
## `mouth_shift` slides the outlane's inner wall sideways: that one number is
## how "The Drain" (boss: wider outlanes) and "Outlane Guards" (mod: narrower)
## are implemented, because widening the channel is exactly what makes a ball
## more likely to fall into it.
static func divider_polygon(is_left: bool, mouth_shift: float = 0.0) -> PackedVector2Array:
	var wall_x := CABINET_INNER + OUTLANE_WIDTH + mouth_shift
	var base_y := DRAIN_Y + CHUTE_OVERRUN

	var poly := PackedVector2Array()
	poly.append(Vector2(wall_x + DIVIDER_PEAK_INSET, DIVIDER_PEAK_Y))  # the peak
	for p in DIVIDER_FLOOR:
		poly.append(p)                                    # down the inlane floor
	poly.append(Vector2(DIVIDER_FLOOR[DIVIDER_FLOOR.size() - 1].x, base_y))
	poly.append(Vector2(wall_x, base_y))                  # along the base
	poly.append(Vector2(wall_x, DIVIDER_SHOULDER_Y))      # up the outlane wall
	# and back to the peak along a sloped shoulder, so a ball that lands on the
	# divider's outer face is guided into the outlane instead of perching there.
	return poly if is_left else mirror_all(poly)


## The outlane channel itself, for telling an outlane drain from a centre drain.
static func outlane_polys(mouth_shift: float = 0.0) -> Array:
	var wall_x := CABINET_INNER + OUTLANE_WIDTH + mouth_shift
	var base_y := DRAIN_Y + CHUTE_OVERRUN
	var left := PackedVector2Array([
		Vector2(CABINET_INNER, DIVIDER_PEAK_Y), Vector2(wall_x, DIVIDER_PEAK_Y),
		Vector2(wall_x, base_y), Vector2(CABINET_INNER, base_y),
	])
	return [left, mirror_all(left)]


## Every static wall on the table, as polylines to be stroked into collision.
static func walls(_mouth_shift: float = 0.0) -> Array:
	var w: Array = []

	w.append(arch_polyline())

	# Left cabinet wall, straight down past the drain. It is the outlane's outer
	# boundary the whole way -- no funnel, because a funnel here would steer
	# every ball on this side into the outlane rather than past it.
	w.append(PackedVector2Array([
		Vector2(PLAYFIELD_LEFT, 70), Vector2(PLAYFIELD_LEFT, DRAIN_Y + CHUTE_OVERRUN),
	]))

	# Right cabinet wall and the plunger lane it encloses.
	w.append(PackedVector2Array([
		Vector2(LANE_RIGHT_X, 70), Vector2(LANE_RIGHT_X, LANE_FLOOR_Y),
		Vector2(LANE_DIVIDER_X, LANE_FLOOR_Y),
	]))
	w.append(PackedVector2Array([
		Vector2(LANE_DIVIDER_X, LANE_DIVIDER_TOP), Vector2(LANE_DIVIDER_X, LANE_FLOOR_Y),
	]))
	# The right outlane's outer wall. The left side gets this for free from the
	# cabinet, but on the right the plunger lane is in the way, so without this
	# the right outlane would be wider than the left -- an asymmetry a player
	# would feel as the right side draining more, and be right about.
	w.append(PackedVector2Array([
		Vector2(PLAYFIELD_RIGHT, DIVIDER_PEAK_Y - 6.0),
		Vector2(PLAYFIELD_RIGHT, DRAIN_Y + CHUTE_OVERRUN),
	]))

	# Orbit guides.
	var left_guide := PackedVector2Array(LEFT_ORBIT_GUIDE)
	w.append(left_guide)
	w.append(mirror_all(left_guide))

	return w


## Filled parts of the playfield, as polygons. Only the two dividers so far.
static func solids(mouth_shift: float = 0.0) -> Array:
	return [divider_polygon(true, mouth_shift), divider_polygon(false, mouth_shift)]


static func flipper_angles(is_left: bool) -> Vector2:
	## Returns (rest, flipped) in radians.
	if is_left:
		return Vector2(deg_to_rad(LEFT_REST_DEG), deg_to_rad(LEFT_UP_DEG))
	return Vector2(deg_to_rad(RIGHT_REST_DEG), deg_to_rad(RIGHT_UP_DEG))
