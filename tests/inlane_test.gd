extends Node
## Regression test for the bug that made the game unplayable: a ball entering
## either inlane must arrive at the flipper, and a ball entering either outlane
## must drain.
##
## This is worth its own test rather than a line in the headless sim because the
## sim's bot cannot be relied on to route a ball down a specific lane -- it took
## a human playing to notice that the inlane fed the drain, and a bot bouncing
## around at random would not have found it any faster. Here the ball is placed
## on the lane deliberately and simply followed.
##
## Prints INLANE_TEST_OK on success; CI greps for it.

const SETTLE_FRAMES := 300  # 2.5s at 120Hz

var _table: Table
var _failures := 0
var _cases: Array = []
var _index := -1
var _frames := 0
var _ball: Ball
var _reached_flipper := false
var _went_outlane := false


func _ready() -> void:
	Run.new_run(4242)
	_table = Table.new()
	add_child(_table)
	_table.active = true

	# Spawn points sit just above each lane's floor, near its entrance.
	# Expectations are deliberately loose: the point is which side of the
	# divider the ball ends up on, not where exactly it comes to rest.
	# Spawn points sit just above each lane's floor, near its entrance. What is
	# asserted is *routing*, not survival: with nobody holding a flipper, a ball
	# that correctly reaches one rolls down it and drains through the middle,
	# which is exactly what a real table does. So an inlane passes by delivering
	# the ball into the flipper's box, and an outlane passes by draining without
	# ever getting there.
	_cases = [
		{
			"name": "left inlane delivers to the flipper",
			"at": Vector2(40, 250), "want_outlane": false,
			"box": Rect2(80, 282, 44, 42),
		},
		{
			"name": "right inlane delivers to the flipper",
			"at": Vector2(214, 250), "want_outlane": false,
			"box": Rect2(130, 282, 44, 42),
		},
		{
			"name": "left outlane drains",
			"at": Vector2(14, 250), "want_outlane": true,
			"box": Rect2(80, 282, 44, 42),
		},
		{
			"name": "right outlane drains",
			"at": Vector2(240, 250), "want_outlane": true,
			"box": Rect2(130, 282, 44, 42),
		},
		# With the Wormhole open the bottom of the table stops being the end of
		# the ball: it goes down the outlane and comes back up the plunger lane.
		{
			"name": "wormhole returns a drained ball to the plunger",
			"at": Vector2(14, 250), "want_outlane": true, "wormhole": true,
			"box": Rect2(130, 282, 44, 42),
		},
	]
	_next_case()


func _next_case() -> void:
	_index += 1
	_frames = 0
	_reached_flipper = false
	_went_outlane = false
	if _index >= _cases.size():
		_finish()
		return
	for b in _table.balls:
		if is_instance_valid(b):
			b.queue_free()
	_table.balls.clear()
	Run.effects.erase("wormhole")
	if bool(_cases[_index].get("wormhole", false)):
		Run.effects["wormhole"] = Time.get_ticks_msec() + 60_000
	_ball = _table.spawn_ball_at(_cases[_index]["at"])


func _physics_process(_delta: float) -> void:
	if _index < 0 or _index >= _cases.size():
		return
	_frames += 1

	var case: Dictionary = _cases[_index]
	if is_instance_valid(_ball) and _table.balls.has(_ball):
		if (case["box"] as Rect2).has_point(_ball.position):
			_reached_flipper = true
		if bool(_ball.get_meta("via_outlane", false)):
			_went_outlane = true

	if _frames < SETTLE_FRAMES:
		return

	if bool(case.get("wormhole", false)):
		# Survival is the whole point here, not routing.
		var alive := is_instance_valid(_ball) and _table.balls.has(_ball)
		if not alive:
			_fail("%s -- the ball was lost anyway" % case["name"])
		elif not _went_outlane:
			_fail("%s -- never reached the outlane, so nothing was returned"
				% case["name"])
		elif not _ball.in_plunger_lane:
			_fail("%s -- survived but ended at %s, not the plunger"
				% [case["name"], _ball.position.round()])
		else:
			print("  ok: %s" % case["name"])
	elif bool(case["want_outlane"]):
		if not _went_outlane:
			_fail("%s -- never entered the outlane" % case["name"])
		elif _reached_flipper:
			_fail("%s -- reached the flipper, so it was not really an outlane"
				% case["name"])
		else:
			print("  ok: %s" % case["name"])
	elif _went_outlane:
		_fail("%s -- fell into the outlane instead" % case["name"])
	elif not _reached_flipper:
		_fail("%s -- never arrived at the flipper" % case["name"])
	else:
		print("  ok: %s" % case["name"])
	_next_case()


func _fail(why: String) -> void:
	_failures += 1
	print("FAIL: %s" % why)


func _finish() -> void:
	if _failures > 0:
		push_error("INLANE_TEST_FAILED")
		print("INLANE_TEST_FAILED: %d" % _failures)
		get_tree().quit(1)
		return
	print("INLANE_TEST_OK")
	get_tree().quit(0)
