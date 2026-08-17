extends Node
## Unit test for the scoring engine (`src/autoload/run.gd`).
##
## Deliberately not a physics test: every relic, boss and level interaction is
## pure arithmetic on `Run`, so it can be checked exactly and instantly. The
## headless sim covers whether a ball can actually reach the things being
## scored -- these two together are the whole surface.
##
## Prints RUN_TEST_OK on success; CI greps for it, so a silent early exit fails
## the build rather than passing it.

var _failures := 0


func _ready() -> void:
	_targets()
	_base_scoring()
	_relics()
	_levels()
	_bosses()
	_tilt()
	_deadhead()
	_economy()
	_progression()

	if _failures > 0:
		push_error("RUN_TEST_FAILED: %d check(s)" % _failures)
		print("RUN_TEST_FAILED: %d" % _failures)
		get_tree().quit(1)
		return
	print("RUN_TEST_OK")
	get_tree().quit(0)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL: %s" % what)


func _eq(actual, expected, what: String) -> void:
	_check(actual == expected, "%s -- got %s, expected %s" % [what, actual, expected])


func _targets() -> void:
	_eq(Catalog.blind_target(1, Catalog.SMALL), 300, "ante 1 small blind")
	_eq(Catalog.blind_target(1, Catalog.BIG), 450, "ante 1 big blind")
	_eq(Catalog.blind_target(1, Catalog.BOSS), 600, "ante 1 boss blind")
	_eq(Catalog.blind_target(8, Catalog.BOSS), 100000, "ante 8 boss blind")


func _base_scoring() -> void:
	Run.new_run(1001)
	_eq(Run.target, 300, "fresh run targets the ante 1 small blind")
	_eq(Run.mult, 1.0, "MULT starts at x1")

	_eq(Run.register_hit(Catalog.Source.BUMPER), 10, "bumper at level 1, MULT x1")
	_eq(Run.score, 10, "the hit banks immediately")

	Run.add_mult(2.0)
	_eq(Run.register_hit(Catalog.Source.BUMPER), 30, "bumper at MULT x3")
	_eq(Run.score, 40, "score accumulates")

	# A spinner rip scores per revolution, which is the whole reason the orbit
	# is worth shooting.
	Run.new_run(1002)
	_eq(Run.register_hit(Catalog.Source.SPINNER, 10), 50, "10 spinner revolutions")


func _relics() -> void:
	Run.new_run(1003)
	Run.add_relic("brass_bumper")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 30, "Brass Bumper triples bumpers")
	_eq(Run.register_hit(Catalog.Source.SLINGSHOT), 15, "and leaves slingshots alone")

	Run.new_run(1004)
	Run.add_relic("slingshot_savant")
	_eq(Run.register_hit(Catalog.Source.SLINGSHOT), 40, "Slingshot Savant adds +25")

	Run.new_run(1005)
	Run.add_relic("skill_shot")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 50, "Skill Shot x5 on the first hit")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 10, "and only the first hit")

	Run.new_run(1006)
	Run.add_relic("cold_solder")
	_eq(Run.balls_for_stage(), 2, "Cold Solder costs a ball")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 20, "Cold Solder doubles values")

	Run.new_run(1007)
	Run.add_relic("tilt_gremlin")
	Run.nudges = 0.0
	_eq(Run.effective_mult(), 3.0, "Tilt Gremlin adds +2 MULT with no nudges left")
	Run.nudges = 2.0
	_eq(Run.effective_mult(), 1.0, "and nothing once they recharge")

	# Five slots, and no duplicates.
	Run.new_run(1008)
	for id in ["brass_bumper", "skill_shot", "ball_saver", "penny_slot", "combo_coil"]:
		_check(Run.add_relic(id), "relic %s fits" % id)
	_check(not Run.add_relic("deadhead"), "the sixth relic is refused")
	_check(not Run.add_relic("brass_bumper"), "duplicates are refused")


func _levels() -> void:
	Run.new_run(1009)
	Run.level_up(Catalog.Source.BUMPER)
	_eq(Run.register_hit(Catalog.Source.BUMPER), 18, "Bumpers Lv2 is 10 + 8")
	Run.level_up(Catalog.Source.BUMPER)
	_eq(Run.register_hit(Catalog.Source.BUMPER), 26, "Bumpers Lv3 is 10 + 16")


func _bosses() -> void:
	Run.new_run(1010)
	Run.boss_id = "governor"
	Run.mult = 10.0
	_eq(Run.effective_mult(), 4.0, "The Governor caps MULT at x4")

	Run.new_run(1011)
	Run.boss_id = "dead_bumper"
	_eq(Run.register_hit(Catalog.Source.BUMPER), 0, "The Dead Bumper zeroes bumpers")
	_eq(Run.register_hit(Catalog.Source.SLINGSHOT), 15, "but not slingshots")

	Run.new_run(1012)
	Run.boss_id = "no_tilt"
	_eq(Run.try_nudge(), 2, "The Tilt refuses the nudge outright")
	_check(not Run.tilted, "and refusing is not the same as tilting")

	Run.new_run(1013)
	Run.boss_id = "reset"
	Run.add_mult(4.0)
	for i in 5:
		Run.register_hit(Catalog.Source.SLINGSHOT)
	_eq(Run.mult, 1.0, "The Reset drops MULT every 5th hit")


func _tilt() -> void:
	Run.new_run(1014)
	Run.add_mult(4.0)
	_eq(Run.try_nudge(), 0, "first nudge is free")
	_eq(Run.try_nudge(), 0, "second nudge is free")
	_eq(Run.try_nudge(), 1, "the third tilts")
	_check(Run.tilted, "and the machine is tilted")
	_eq(Run.mult, 1.0, "a tilt costs the MULT")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 0, "a tilted machine scores nothing")


func _deadhead() -> void:
	Run.new_run(1015)
	Run.add_mult(4.0)
	Run.begin_ball()
	_eq(Run.mult, 1.0, "MULT resets between balls by default")

	Run.new_run(1016)
	Run.add_relic("deadhead")
	Run.add_mult(4.0)
	Run.begin_ball()
	_eq(Run.mult, 5.0, "Deadhead carries MULT between balls")


func _economy() -> void:
	Run.new_run(1017)
	Run.tokens = 50
	var offers := Run.roll_shop(3)
	_eq(offers.size(), 3, "the shop offers three things")
	var before := Run.tokens
	var cost := int(offers[0]["cost"])
	_check(Run.buy(offers[0]), "an affordable offer can be bought")
	_eq(Run.tokens, before - cost, "and it is paid for")

	Run.tokens = 0
	_check(not Run.buy(offers[1]), "a broke player cannot buy")

	Run.new_run(1018)
	Run.add_relic("penny_slot")
	Run.tokens = 0
	Run.register_hit(Catalog.Source.ORBIT, 10)  # 100 * 10 = 1000
	_eq(Run.tokens, 1, "Penny Slot pays $1 per 1,000 points")


func _progression() -> void:
	Run.new_run(1019)
	_eq(Run.ante, 1, "runs start at ante 1")
	Run.advance_blind()
	_eq(Run.blind, Catalog.BIG, "small blind leads to big")
	Run.advance_blind()
	_eq(Run.blind, Catalog.BOSS, "big blind leads to boss")
	Run.advance_blind()
	_eq(Run.blind, Catalog.SMALL, "and the boss rolls the ante over")
	_eq(Run.ante, 2, "to ante 2")

	# A boss blind must always pick a hazard, or the boss is just a big number.
	Run.new_run(1020)
	Run.blind = Catalog.BOSS
	Run.begin_stage()
	_check(Run.boss_id != "", "a boss blind always has a boss")

	Run.new_run(1021)
	Run.score = Run.target
	_check(Run.stage_won(), "hitting the target clears the stage")
	var payout := Run.stage_payout()
	_check(payout.size() >= 2, "clearing pays the blind and the unused balls")
