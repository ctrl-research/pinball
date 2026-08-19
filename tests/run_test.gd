extends Node
## Unit test for the scoring engine (`src/autoload/run.gd`).
##
## Deliberately not a physics test: every trinket, boss and level interaction is
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
	_trinkets()
	_levels()
	_bosses()
	_tilt()
	_deadhead()
	_economy()
	_progression()
	_stage_completion()
	_inventory()
	_consumables()
	_slow_ball()
	_fever()

	if _failures > 0:
		push_error("RUN_TEST_FAILED: %d check(s)" % _failures)
		print("RUN_TEST_FAILED: %d" % _failures)
		get_tree().quit(1)
		return
	print("RUN_TEST_OK")
	get_tree().quit(0)


## Scores one hit from a standing start.
##
## Fever multiplies consecutive contacts, so a test measuring what a *bumper* is
## worth would otherwise be measuring the combo it built one line earlier. The
## fever tests use register_hit directly, because there the combo is the point.
func _cold_hit(source: int, count: int = 1) -> int:
	Run.fever = Run.FEVER_BASE
	return Run.register_hit(source, count)


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
	_eq(_cold_hit(Catalog.Source.BUMPER), 30, "bumper at MULT x3")
	_eq(Run.score, 40, "score accumulates")

	# A spinner rip scores per revolution, which is the whole reason the orbit
	# is worth shooting.
	Run.new_run(1002)
	_eq(Run.register_hit(Catalog.Source.SPINNER, 10), 50, "10 spinner revolutions")


func _trinkets() -> void:
	Run.new_run(1003)
	Run.add_trinket("brass_bumper")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 30, "Brass Bumper triples bumpers")
	_eq(_cold_hit(Catalog.Source.SLINGSHOT), 15, "and leaves slingshots alone")

	Run.new_run(1004)
	Run.add_trinket("slingshot_savant")
	_eq(Run.register_hit(Catalog.Source.SLINGSHOT), 40, "Slingshot Savant adds +25")

	Run.new_run(1005)
	Run.add_trinket("skill_shot")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 50, "Skill Shot x5 on the first hit")
	_eq(_cold_hit(Catalog.Source.BUMPER), 10, "and only the first hit")

	Run.new_run(1006)
	Run.add_trinket("cold_solder")
	_eq(Run.balls_for_stage(), 2, "Cold Solder costs a ball")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 20, "Cold Solder doubles values")

	Run.new_run(1007)
	Run.add_trinket("tilt_gremlin")
	Run.nudges = 0.0
	_eq(Run.effective_mult(), 3.0, "Tilt Gremlin adds +2 MULT with no nudges left")
	Run.nudges = 2.0
	_eq(Run.effective_mult(), 1.0, "and nothing once they recharge")

	# Five slots, and no duplicates.
	Run.new_run(1008)
	for id in ["brass_bumper", "skill_shot", "ball_saver", "penny_slot", "combo_coil"]:
		_check(Run.add_trinket(id), "trinket %s fits" % id)
	_check(not Run.add_trinket("deadhead"), "the sixth trinket is refused")
	_check(not Run.add_trinket("brass_bumper"), "duplicates are refused")


func _levels() -> void:
	Run.new_run(1009)
	Run.level_up(Catalog.Source.BUMPER)
	_eq(Run.register_hit(Catalog.Source.BUMPER), 18, "Bumpers Lv2 is 10 + 8")
	Run.level_up(Catalog.Source.BUMPER)
	_eq(_cold_hit(Catalog.Source.BUMPER), 26, "Bumpers Lv3 is 10 + 16")


func _bosses() -> void:
	Run.new_run(1010)
	Run.boss_id = "governor"
	Run.mult = 10.0
	_eq(Run.effective_mult(), 4.0, "The Governor caps MULT at x4")

	Run.new_run(1011)
	Run.boss_id = "dead_bumper"
	_eq(Run.register_hit(Catalog.Source.BUMPER), 0, "The Dead Bumper zeroes bumpers")
	_eq(_cold_hit(Catalog.Source.SLINGSHOT), 15, "but not slingshots")

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
	Run.add_trinket("deadhead")
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
	Run.add_trinket("penny_slot")
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
	_check(payout.size() >= 1, "clearing always pays the blind reward")


## A stage no longer ends the moment the target falls; it runs all of its balls
## and is judged once, at the end.
func _stage_completion() -> void:
	Run.new_run(1022)
	_check(not Run.target_met, "the target starts unmet")
	_eq(Run.balls_left, 3, "three balls in hand")

	# Cross the target on the first ball.
	Run.register_hit(Catalog.Source.ORBIT, 3)  # 100 * 3 = 300
	_check(Run.stage_won(), "300 clears the ante 1 small blind")
	_check(Run.target_met, "and the crossing is recorded")
	_eq(Run.balls_left_at_target, 3, "with the balls that were still in hand")
	_eq(Run.balls_left, 3, "crossing the target consumes nothing")

	# Draining still costs balls, and the stage stays winnable-but-unfinished.
	Run.consume_ball(false)
	_eq(Run.balls_left, 2, "a drain after the target still costs a ball")
	_check(Run.stage_won(), "and the stage is still won")
	_eq(Run.balls_left_at_target, 3, "the recorded figure does not drift")

	# Two balls were never needed, so two are paid for.
	var labels: Array = []
	for item in Run.stage_payout():
		labels.append(str(item["label"]))
	_check(labels.has("2 ball(s) not needed"), "pays for the balls not needed -- got %s" % [labels])

	# Overkill multiplies the blind's reward rather than adding to it.
	Run.new_run(1023)
	Run.score = Run.target
	_eq(Run.payout_multiplier(), 1, "exactly meeting the target is x1")
	Run.score = Run.target * 2
	_eq(Run.payout_multiplier(), 2, "doubling the target is x2")
	Run.score = Run.target * 99
	_eq(Run.payout_multiplier(), Run.PAYOUT_MULT_CAP, "and it is capped")

	Run.new_run(1025)
	Run.blind = Catalog.SMALL
	Run.begin_stage()
	var base: int = Catalog.BLIND_REWARD[Catalog.SMALL]
	Run.score = Run.target * 3
	var total := 0
	var saw_overkill := false
	for item in Run.stage_payout():
		total += int(item["amount"])
		if str(item["label"]).begins_with("Overkill"):
			saw_overkill = true
	_check(saw_overkill, "tripling the target shows an overkill line")
	_check(total >= base * 3, "and the blind reward is tripled -- got %d for base %d"
		% [total, base])

	# Losing: balls gone, target missed.
	Run.new_run(1024)
	for i in 3:
		Run.consume_ball(false)
	_eq(Run.balls_left, 0, "three drains use three balls")
	_check(not Run.stage_won(), "with no score the target is missed")
	_check(Run.run_lost(), "which is a loss")


## Inventory limits and selling.
func _inventory() -> void:
	Run.new_run(1030)
	for id in ["brass_bumper", "skill_shot", "ball_saver", "penny_slot", "combo_coil"]:
		_check(Run.add_trinket(id), "trinket %s fits" % id)
	_check(not Run.add_trinket("deadhead"), "the sixth trinket is refused")

	# Duplicates stack into one slot rather than taking a second.
	_eq(Run.add_consumable("ball_polish"), true, "a consumable fits")
	_eq(Run.add_consumable("ball_polish"), true, "a second stacks")
	_eq(Run.consumable_stacks[0], 2, "making a stack of two")
	_eq(Run.consumable_count(), 1, "in a single slot")

	_eq(Run.add_consumable("overclock"), true, "a different kind takes its own slot")
	_eq(Run.add_consumable("surge"), true, "and a third fills the rack")
	_check(not Run.add_consumable("slow_ball"), "a fourth *kind* is refused")
	_check(Run.add_consumable("ball_polish"), "but stacking an existing kind still fits")
	_eq(Run.consumable_stacks[0], 3, "making three")

	# Firing takes one off the stack and leaves the rest on the same key.
	_check(Run.use_consumable(0), "slot 1 fires")
	_eq(Run.consumable_stacks[0], 2, "consuming exactly one")
	_eq(Run.consumables[0], "ball_polish", "and the slot keeps its kind")
	_check(Run.use_consumable(0), "it fires again")
	_check(Run.use_consumable(0), "and again")
	_eq(Run.consumable_stacks[0], 0, "until the stack is spent")
	_eq(Run.consumables[0], "", "and the slot empties")
	_check(not Run.use_consumable(0), "an empty slot fires nothing")

	# Slots are fixed: an emptied one leaves a hole rather than shuffling.
	_eq(Run.consumables[2], "surge", "slot 3 never moved")
	_check(Run.add_consumable("slow_ball"), "a new kind refills the hole")
	_eq(Run.consumables[0], "slow_ball", "in slot 1")

	# The stack has a ceiling.
	Run.new_run(1043)
	for i in Run.MAX_STACK:
		_check(Run.add_consumable("surge"), "surge %d stacks" % (i + 1))
	_eq(Run.consumable_stacks[0], Run.MAX_STACK, "up to the cap")
	_check(Run.add_consumable("surge"), "past the cap it takes a fresh slot")
	_eq(Run.consumable_stacks[1], 1, "starting a second stack")

	# A full rack still has room for a kind it already holds.
	Run.new_run(1044)
	for id in ["surge", "overclock", "ball_polish"]:
		Run.add_consumable(id)
	_check(not Run.can_take({"kind": "consumable", "id": "slow_ball", "cost": 7}),
		"a full rack refuses a new kind")
	_check(Run.can_take({"kind": "consumable", "id": "surge", "cost": 6}),
		"but accepts one it can stack")

	# Selling takes one off the stack, not the lot.
	Run.new_run(1045)
	Run.add_consumable("ball_polish")
	Run.add_consumable("ball_polish")
	Run.tokens = 0
	_eq(Run.sell("consumable", 0), Catalog.sell_price("consumable", "ball_polish"),
		"selling pays for one")
	_eq(Run.consumable_stacks[0], 1, "and leaves the rest of the stack")
	_eq(Run.sell("consumable", 0), Catalog.sell_price("consumable", "ball_polish"),
		"the last one sells too")
	_eq(Run.consumables[0], "", "emptying the slot")
	_eq(Run.sell("consumable", 0), 0, "and an empty slot sells nothing")

	# Selling returns 75% of shelf price, rounded down.
	_eq(Catalog.sell_price("trinket", "brass_bumper"), 3, "a $4 trinket sells for $3")
	_eq(Catalog.sell_price("consumable", "steady_hand"), 2, "a $3 consumable sells for $2")
	_eq(Catalog.sell_price("trinket", "deadhead"), 7, "a $10 trinket sells for $7")

	# Fresh rack: the consumable cases above each start their own run, so the
	# trinkets added at the top of this test are long gone.
	Run.new_run(1046)
	Run.add_trinket("brass_bumper")
	Run.add_trinket("skill_shot")
	Run.tokens = 0
	var before := Run.trinkets.size()
	_eq(Run.sell("trinket", 0), 3, "selling pays out")
	_eq(Run.trinkets.size(), before - 1, "and removes the item")
	_eq(Run.tokens, 3, "and the money arrives")
	_eq(Run.sell("trinket", 99), 0, "selling nothing pays nothing")

	# A full inventory refuses the offer before it takes the money.
	Run.new_run(1031)
	Run.tokens = 50
	for id in ["brass_bumper", "skill_shot", "ball_saver", "penny_slot", "combo_coil"]:
		Run.add_trinket(id)
	var offer := {"kind": "trinket", "id": "deadhead", "cost": 10}
	_check(not Run.can_take(offer), "a full trinket rack cannot take another")
	_check(not Run.buy(offer), "so the purchase is refused")
	_eq(Run.tokens, 50, "and no money changes hands")

	# Nor can you buy a duplicate trinket.
	_check(not Run.can_take({"kind": "trinket", "id": "brass_bumper", "cost": 4}),
		"duplicated trinkets are refused")


## Consumables are fired mid-ball and most of them run on a real-time clock.
func _consumables() -> void:
	Run.new_run(1032)
	Run.add_consumable("ball_polish")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 10, "unfired, it does nothing")
	_check(Run.use_consumable(0), "it can be fired")
	_eq(Run.consumable_count(), 0, "and leaves the rack afterwards")
	_check(Run.effect_active("ball_polish"), "the effect is running")
	_eq(_cold_hit(Catalog.Source.BUMPER), 20, "Ball Polish doubles values")
	_check(Run.effect_remaining("ball_polish") > 15.0, "with time left on it")

	# Effects do not survive the stage.
	Run.blind = Catalog.BIG
	Run.begin_stage()
	_check(not Run.effect_active("ball_polish"), "a new stage clears the effect")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 10, "so values are back to normal")

	# Expiry is driven by the real clock, so a zero-length effect is already over.
	Run.new_run(1038)
	Run.effects["ball_polish"] = Time.get_ticks_msec() - 1
	_check(Run.effect_active("ball_polish"), "an expired effect is still listed...")
	Run._expire_effects()
	_check(not Run.effect_active("ball_polish"), "...until it is swept")

	# Instants.
	Run.new_run(1033)
	Run.add_consumable("extra_ball")
	var balls := Run.balls_left
	Run.use_consumable(0)
	_eq(Run.balls_left, balls + 1, "Extra Ball is a resource, granted immediately")
	_check(not Run.effect_active("extra_ball"), "and starts no timer")

	Run.new_run(1034)
	Run.add_consumable("surge")
	Run.use_consumable(0)
	_eq(Run.mult, 3.0, "Surge lifts MULT to x3 at once")
	Run.new_run(1039)
	Run.add_mult(4.0)  # MULT x5, already above the floor
	Run.add_consumable("surge")
	Run.use_consumable(0)
	_eq(Run.mult, 5.0, "and never lowers a MULT that is already higher")

	Run.new_run(1036)
	Run.add_consumable("overclock")
	Run.use_consumable(0)
	Run.add_mult(1.0)
	_eq(Run.mult, 3.0, "Overclock doubles MULT gains")

	Run.new_run(1040)
	Run.add_consumable("jackpot_charge")
	Run.use_consumable(0)
	_eq(Run.register_hit(Catalog.Source.BUMPER), 510, "Jackpot Charge adds a flat 500")

	Run.new_run(1037)
	Run.add_consumable("second_wind")
	Run.use_consumable(0)
	var had := Run.balls_left
	_check(Run.consume_ball(false), "Second Wind returns the first drained ball")
	_eq(Run.balls_left, had, "at no cost")
	_check(not Run.consume_ball(false), "but only once")

	# Refiring restarts rather than stacks.
	Run.new_run(1041)
	Run.add_consumable("ball_polish")
	Run.add_consumable("ball_polish")
	Run.use_consumable(0)
	Run.use_consumable(0)
	_eq(Run.register_hit(Catalog.Source.BUMPER), 20, "two Ball Polish is still x2, not x4")

	_check(not Run.use_consumable(0), "firing nothing fails cleanly")


## Slow Ball drives Engine.time_scale, and a leaked time scale would slow the
## whole game down forever -- so the derivation is what is checked, not the use.
func _slow_ball() -> void:
	Run.new_run(1042)
	Run.add_consumable("slow_ball")
	Run.use_consumable(0)
	_check(Run.effect_active("slow_ball"), "Slow Ball is running")
	_check(Run.effect_remaining("slow_ball") <= 6.0, "for no more than its 6s")

	Run.begin_stage()
	_check(not Run.effect_active("slow_ball"), "and a new stage ends it")


## Fever: a short-term combo multiplier stacked on top of MULT.
func _fever() -> void:
	Run.new_run(1050)
	_eq(Run.fever, Run.FEVER_BASE, "fever starts at x1")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 10, "the first hit is not yet feverish")
	_eq(Run.fever, 1.25, "but it stokes the fever")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 13, "and the next hit is worth more")

	# It multiplies with MULT rather than replacing it.
	Run.new_run(1051)
	Run.add_mult(3.0)  # MULT x4
	Run.register_hit(Catalog.Source.BUMPER)  # fever -> 1.25
	_eq(Run.register_hit(Catalog.Source.BUMPER), 50, "10 x MULT 4 x fever 1.25")

	# Capped, or a bumper nest on a stacked MULT would break the ante curve.
	Run.new_run(1052)
	for i in 40:
		Run.register_hit(Catalog.Source.BUMPER)
	_eq(Run.fever, Run.FEVER_MAX, "fever is capped")

	# It expires on a cliff.
	Run.new_run(1053)
	Run.register_hit(Catalog.Source.BUMPER)
	_check(Run.fever > Run.FEVER_BASE, "fever is up")
	_check(Run.fever_remaining() > 0.0, "with time on it")
	Run._fever_expires = float(Time.get_ticks_msec()) - 1.0
	Run._expire_fever()
	_eq(Run.fever, Run.FEVER_BASE, "and drops all the way back, not part way")

	# A new ball starts cold.
	Run.new_run(1054)
	Run.register_hit(Catalog.Source.BUMPER)
	Run.begin_ball()
	_eq(Run.fever, Run.FEVER_BASE, "a new ball starts at x1")

	# Combo Coil now feeds fever instead of MULT.
	Run.new_run(1055)
	Run.add_trinket("combo_coil")
	Run.register_hit(Catalog.Source.BUMPER)
	_eq(Run.fever, 1.5, "Combo Coil builds fever twice as fast")
