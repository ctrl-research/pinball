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


func _trinkets() -> void:
	Run.new_run(1003)
	Run.add_trinket("brass_bumper")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 30, "Brass Bumper triples bumpers")
	_eq(Run.register_hit(Catalog.Source.SLINGSHOT), 15, "and leaves slingshots alone")

	Run.new_run(1004)
	Run.add_trinket("slingshot_savant")
	_eq(Run.register_hit(Catalog.Source.SLINGSHOT), 40, "Slingshot Savant adds +25")

	Run.new_run(1005)
	Run.add_trinket("skill_shot")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 50, "Skill Shot x5 on the first hit")
	_eq(Run.register_hit(Catalog.Source.BUMPER), 10, "and only the first hit")

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

	_eq(Run.add_consumable("ball_polish"), true, "a consumable fits")
	_eq(Run.add_consumable("ball_polish"), true, "and duplicates are allowed")
	_eq(Run.add_consumable("overclock"), true, "three consumables fit")
	_check(not Run.add_consumable("slow_ball"), "the fourth consumable is refused")
	_eq(Run.consumable_count(), 3, "three are held")

	# Slots are fixed: firing one leaves a hole rather than shuffling.
	_check(Run.use_consumable(0), "slot 1 fires")
	_eq(Run.consumables[0], "", "and leaves slot 1 empty")
	_eq(Run.consumables[2], "overclock", "without moving slot 3")
	_check(not Run.use_consumable(0), "so slot 1 cannot fire twice")
	_eq(Run.consumable_count(), 2, "two are left")
	_check(Run.add_consumable("surge"), "and a new one refills the hole")
	_eq(Run.consumables[0], "surge", "in slot 1")

	# Selling returns 75% of shelf price, rounded down.
	_eq(Catalog.sell_price("trinket", "brass_bumper"), 3, "a $4 trinket sells for $3")
	_eq(Catalog.sell_price("consumable", "steady_hand"), 2, "a $3 consumable sells for $2")
	_eq(Catalog.sell_price("trinket", "deadhead"), 7, "a $10 trinket sells for $7")

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
	_eq(Run.register_hit(Catalog.Source.BUMPER), 20, "Ball Polish doubles values")
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
