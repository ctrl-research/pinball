extends Node
## Fires a ball at every wall from every angle, at the speed clamp, and checks
## that none of them get out.
##
## Reported from play: the ball sometimes leaves the cabinet entirely and
## vanishes, and the game then sits in PLAYING forever because nothing ever
## drains. A ball that escapes is worse than any scoring bug -- the run is over
## and the player cannot even lose.
##
## The flippers hammer throughout. That is not incidental: a flipper is a
## kinematic body moving at solenoid speed, and the classic way a pinball
## escapes its table is being squeezed between one and a wall and squirted
## through the geometry. A containment test that leaves the flippers at rest is
## testing the one configuration the ball is least likely to escape from.
##
## Deterministic enumeration rather than random shaking, so a failure names the
## exact spawn and heading that produced it and can be re-run.
##
## Prints CONTAINMENT_OK on success; CI greps for it.

const SETTLE_FRAMES := 150
const DIRECTIONS := 12
## How often the flippers reverse while a case runs.
const FLIP_PERIOD := 5

## Spawn points chosen to aim at every boundary the table has: the arch, both
## orbits, the plunger lane, the bumper nest, and the lower playfield.
const SPAWNS := [
	Vector2(127, 40),   # under the apex of the arch
	Vector2(20, 120),   # left orbit lane
	Vector2(234, 120),  # right orbit lane
	Vector2(264, 200),  # inside the plunger lane
	Vector2(127, 140),  # the bumper nest
	Vector2(127, 250),  # above the slingshots
	Vector2(60, 300),   # left inlane / outlane mouth
	Vector2(194, 300),  # right inlane / outlane mouth
	Vector2(100, 310),  # on the left flipper
	Vector2(154, 310),  # on the right flipper
	Vector2(127, 316),  # in the drain gap between the tips
	Vector2(84, 296),   # the pinch between flipper root and divider
	Vector2(170, 296),  # and its mirror
]

## Generous: legitimate play reaches y~10 at the arch and y~344 at the drain.
## Anything outside this is not a ball in play, it is a ball that got out.
const BOUNDS := Rect2(-24, -40, 328, 420)

var _table: Table
var _escapes: Array[String] = []
var _cases: Array = []
var _index := -1
var _frames := 0
var _ball: Ball


func _ready() -> void:
	Run.new_run(777)
	# A full rack, because that is the configuration most likely to open a gap:
	# Heavy Bat makes the bats livelier and Dead Bounce writes velocities
	# directly. A ball that leaves the cabinet never drains, so the stage never
	# ends and the run cannot even be lost.
	for id in ["heavy_bat", "dead_bounce", "hot_winding"]:
		Run.add_coil(id)
	_table = Table.new()
	add_child(_table)
	_table.active = true

	for spawn in SPAWNS:
		for d in DIRECTIONS:
			var angle := TAU * float(d) / float(DIRECTIONS)
			_cases.append({"at": spawn, "vel": Vector2.RIGHT.rotated(angle) * Ball.MAX_SPEED})
	_next_case()


func _next_case() -> void:
	_index += 1
	_frames = 0
	if _index >= _cases.size():
		_finish()
		return
	for b in _table.balls:
		if is_instance_valid(b):
			b.queue_free()
	_table.balls.clear()
	_ball = _table.spawn_ball_at(_cases[_index]["at"])
	_ball.linear_velocity = _cases[_index]["vel"]


func _physics_process(_delta: float) -> void:
	if _index < 0 or _index >= _cases.size():
		return
	_frames += 1
	_work_flippers()

	# Checked every frame, not just at the end: a ball that leaves and is then
	# swept up by the drain would otherwise look like a pass.
	if is_instance_valid(_ball) and _table.balls.has(_ball):
		if not BOUNDS.has_point(_ball.position):
			var case: Dictionary = _cases[_index]
			_escapes.append("from %s heading %s -> escaped to %s"
				% [case["at"], case["vel"].normalized().round(), _ball.position.round()])
			_next_case()
			return

	if _frames >= SETTLE_FRAMES:
		_next_case()


## Both flippers, hammering out of phase, so the ball meets a rising bat and a
## falling one and every combination of the two.
func _work_flippers() -> void:
	var phase := int(_frames / FLIP_PERIOD) % 2 == 0
	if phase:
		Input.action_press("flip_left")
		Input.action_release("flip_right")
	else:
		Input.action_release("flip_left")
		Input.action_press("flip_right")


func _finish() -> void:
	Input.action_release("flip_left")
	Input.action_release("flip_right")
	print("CONTAINMENT: %d cases, %d escapes" % [_cases.size(), _escapes.size()])
	if _escapes.is_empty():
		print("CONTAINMENT_OK")
		get_tree().quit(0)
		return
	for e in _escapes:
		print("ESCAPE: %s" % e)
	push_error("CONTAINMENT_FAILED")
	print("CONTAINMENT_FAILED: %d" % _escapes.size())
	get_tree().quit(1)
