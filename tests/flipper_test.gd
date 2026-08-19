extends Node
## What the flippers do to a ball, asserted against measurements rather than
## against intentions.
##
## This suite exists because the coil layer was designed on two claims about the
## flippers, and one of them was false. `Magna-Hold` was to be its headline --
## "cradling is impossible here, a resting flipper rolls the ball to its tip" --
## and a ball dropped on a *held* flipper turns out to stop dead and stay there,
## because `flipper.gd` sets friction to 0.7 for exactly that purpose. The coil
## would have sold the player something they already had.
##
## What was true is the other half: a ball landing on a *lowered* flipper drains
## in about a second with no input that saves it. That is the gap `Dead Bounce`
## closes, and both facts are now assertions so the next design argument starts
## from the table instead of from memory.
##
## Prints FLIPPER_TEST_OK on success; CI greps for it.

## Just above the left flipper, out from the pivot -- where a ball returning
## down the left side actually lands.
const DROP_AT := Vector2(96, 280)
const SETTLE_FRAMES := 480  # 4s at 120Hz

var _table: Table
var _failures := 0
var _cases: Array = []
var _index := -1
var _frames := 0
var _ball: Ball
var _lost_at := -1.0
var _peak_rise := 0.0


func _ready() -> void:
	Run.new_run(2468)
	_table = Table.new()
	add_child(_table)
	_table.active = true

	_cases = [
		# The baseline the coil is measured against. A ball left on a lowered
		# flipper is simply lost, and quickly.
		{
			"name": "a ball on a resting flipper drains",
			"hold": false, "coils": [], "want": "lost",
		},
		# The behaviour that made Magna-Hold redundant.
		{
			"name": "a held flipper cradles the ball",
			"hold": true, "coils": [], "want": "cradled",
		},
		# ... and what the coil actually buys.
		{
			"name": "Dead Bounce saves the ball a resting flipper would lose",
			"hold": false, "coils": ["dead_bounce"], "want": "saved",
		},
		{
			"name": "and does nothing when it is not owned",
			"hold": false, "coils": ["hot_winding"], "want": "lost",
		},
	]
	_next_case()


func _next_case() -> void:
	_index += 1
	_frames = 0
	_lost_at = -1.0
	_peak_rise = 0.0
	if _index >= _cases.size():
		_finish()
		return
	for b in _table.balls:
		if is_instance_valid(b):
			b.queue_free()
	_table.balls.clear()
	Input.action_release("flip_left")

	Run.coils.clear()
	for id in _cases[_index]["coils"]:
		Run.add_coil(str(id))
	# Rebuilt because the flippers read their coils in setup(): Heavy Bat is a
	# physics material and Hot Winding a sweep time, neither of which is
	# re-read per frame.
	_table.build()
	_ball = _table.spawn_ball_at(DROP_AT)


func _physics_process(delta: float) -> void:
	if _index < 0 or _index >= _cases.size():
		return
	_frames += 1
	if bool(_cases[_index]["hold"]):
		Input.action_press("flip_left")

	var alive := is_instance_valid(_ball) and _table.balls.has(_ball)
	if alive:
		# How far above the drop point the ball ever got. A save has to actually
		# send it somewhere, not merely delay the loss.
		_peak_rise = maxf(_peak_rise, DROP_AT.y - _ball.position.y)
	elif _lost_at < 0.0:
		_lost_at = float(_frames) * delta

	if _frames < SETTLE_FRAMES:
		return

	var case: Dictionary = _cases[_index]
	match str(case["want"]):
		"lost":
			if alive:
				_fail("%s -- it survived at %s" % [case["name"], _ball.position.round()])
			else:
				print("  ok: %s (at %.2fs)" % [case["name"], _lost_at])
		"cradled":
			if not alive:
				_fail("%s -- it was lost at %.2fs" % [case["name"], _lost_at])
			elif _ball.linear_velocity.length() > 20.0:
				_fail("%s -- it is still moving at %.0f px/s"
					% [case["name"], _ball.linear_velocity.length()])
			else:
				print("  ok: %s (stopped %.1fpx from the pivot)"
					% [case["name"],
						_ball.position.distance_to(TableLayout.LEFT_FLIPPER_PIVOT)])
		"saved":
			if not alive:
				_fail("%s -- it drained anyway at %.2fs" % [case["name"], _lost_at])
			elif _peak_rise < 20.0:
				_fail("%s -- it lived but never left the flipper (rose %.0fpx)"
					% [case["name"], _peak_rise])
			else:
				print("  ok: %s (kicked %.0fpx up the table)" % [case["name"], _peak_rise])
	_next_case()


func _fail(why: String) -> void:
	_failures += 1
	print("FAIL: %s" % why)


func _finish() -> void:
	Input.action_release("flip_left")
	if _failures > 0:
		push_error("FLIPPER_TEST_FAILED")
		print("FLIPPER_TEST_FAILED: %d" % _failures)
		get_tree().quit(1)
		return
	print("FLIPPER_TEST_OK")
	get_tree().quit(0)
