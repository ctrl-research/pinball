extends Node
## A bot that plays the real game scene headlessly, so CI exercises physics,
## the state machine and the HUD rather than only whether the scripts parse.
##
## It is a bad pinball player on purpose -- it plunges, it flips on a timer
## when the ball is low, and that is all. The point is not that it scores well;
## it is that a ball can be served, can reach something that scores, and that
## the run advances through every screen without anything crashing.
##
## Prints SIM_OK only if every floor below is met, so losing coverage fails the
## build instead of quietly passing.

const GAME := preload("res://scenes/game.tscn")

const TOTAL_FRAMES := 3600
## The bot cannot be relied on to actually beat a 300-point blind, so at this
## frame the stage is handed to it. Everything after this point -- results,
## shop, the next intro, a rebuilt table -- is code that would otherwise never
## run in CI.
const FORCE_CLEAR_FRAME := 1500

## After this the bot stops flipping entirely, and the ball is required to
## drain. Flipping on a timer whenever the ball is low turns out to be a very
## effective if stupid save, so without a deliberate hands-off phase the sim
## can keep one ball alive for its whole run and never exercise the drain --
## which is exactly how two separate ball-trap bugs survived earlier passes.
const NO_FLIP_AFTER := 2600
## Long enough to reach a full charge: the plunger fills in 0.71s of holding,
## and a weak plunge dies in the orbit without reaching the playfield.
const PLUNGE_HOLD := 120
const FLIP_PERIOD := 8

## Trace cadence. Verbose on purpose: when this test fails on CI the log is the
## only evidence available, and "the bot scored nothing" is not a diagnosis.
const TRACE_EVERY := 400

var _game: Game
var _frame := 0
var _plunge_hold := 0
var _max_score := 0
var _score_before_force := 0
var _balls_served := 0
var _drains := 0
var _last_ball_id := 0
var _states_seen := {}
var _forced := false


func _ready() -> void:
	# Both RNGs are pinned. Run.rng picks the boss and the shop; the global one
	# is what slingshot spread and the ball-search jitter draw from, and leaving
	# that free would make this test pass or fail on the physics dice -- which
	# on CI means an intermittent red build nobody can reproduce.
	seed(20260816)
	Run.new_run(20260816)
	_game = GAME.instantiate()
	add_child(_game)
	_game.table.drained.connect(func(_outlane): _drains += 1)


func _process(_delta: float) -> void:
	_frame += 1
	_states_seen[_game.state] = true
	_max_score = maxi(_max_score, Run.score)
	if _frame % TRACE_EVERY == 0:
		_trace()

	if _game.state == Game.State.PLAYING:
		if _frame == FORCE_CLEAR_FRAME and not _forced:
			_forced = true
			_score_before_force = Run.score
			Run.score = Run.target
		_play()
	else:
		_release_all()
		# The overlay listens for a real key event, not an action state, so the
		# bot has to send one -- which is the point: it tests the same path a
		# player's spacebar takes.
		if _frame % 24 == 0:
			_tap_space()

	if _frame >= TOTAL_FRAMES:
		_finish()


func _play() -> void:
	var table: Table = _game.table
	if table.balls.is_empty():
		_release_all()
		return

	var ball: Ball = table.balls[0]
	if not is_instance_valid(ball):
		return
	# Counted by identity, not by watching the list empty: a drain re-serves
	# synchronously inside the signal, so the list is never observed empty from
	# out here and a "was there a ball last frame" counter always reads 1.
	if ball.get_instance_id() != _last_ball_id:
		_last_ball_id = ball.get_instance_id()
		_balls_served += 1

	if ball.in_plunger_lane:
		if _plunge_hold < PLUNGE_HOLD:
			_plunge_hold += 1
			Input.action_press("plunge")
		else:
			Input.action_release("plunge")
			_plunge_hold = 0
		return

	Input.action_release("plunge")
	_plunge_hold = 0

	var flipping := int(_frame / FLIP_PERIOD) % 2 == 0 and _frame < NO_FLIP_AFTER
	if ball.position.y > 240.0 and flipping:
		if ball.position.x < TableLayout.LOWER_CENTRE:
			Input.action_press("flip_left")
		else:
			Input.action_press("flip_right")
	else:
		Input.action_release("flip_left")
		Input.action_release("flip_right")


func _release_all() -> void:
	for action in ["plunge", "flip_left", "flip_right"]:
		Input.action_release(action)


func _tap_space() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		ev.keycode = KEY_SPACE
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _trace() -> void:
	var where := "no ball"
	var table: Table = _game.table
	if not table.balls.is_empty() and is_instance_valid(table.balls[0]):
		var b: Ball = table.balls[0]
		where = "pos=(%d,%d) vel=%d lane=%s" % [
			int(b.position.x), int(b.position.y), int(b.linear_velocity.length()),
			b.in_plunger_lane]
	print("SIM f=%d state=%d score=%d balls_left=%d served=%d drains=%d %s"
		% [_frame, _game.state, Run.score, Run.balls_left, _balls_served, _drains, where])


func _finish() -> void:
	var problems: Array[String] = []
	if _max_score <= 0:
		problems.append("the bot never scored a point -- nothing on the table is reachable")
	if _balls_served < 2:
		problems.append("only %d ball(s) were served" % _balls_served)
	if _drains < 1:
		problems.append("no ball drained even with the flippers held off for %d frames"
			% (TOTAL_FRAMES - NO_FLIP_AFTER))
	for required in [Game.State.INTRO, Game.State.PLAYING, Game.State.SHOP]:
		if not _states_seen.has(required):
			problems.append("never reached state %d" % required)

	print("SIM: frames=%d score_max=%d organic_score=%d balls=%d drains=%d states=%s"
		% [_frame, _max_score, _score_before_force, _balls_served, _drains,
			_states_seen.keys()])
	if problems.is_empty():
		print("SIM_OK")
		get_tree().quit(0)
		return
	for p in problems:
		print("SIM_FAIL: %s" % p)
	push_error("SIM_FAIL")
	get_tree().quit(1)
