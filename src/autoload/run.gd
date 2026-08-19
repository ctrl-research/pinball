extends Node
## Run state and all scoring arithmetic (autoload "Run").
##
## Everything that answers "how many points was that worth" lives here, and the
## table only ever reports *what was hit*. Keeping the arithmetic in one place
## is what makes trinkets tractable: a trinket is a branch at a named hook in this
## file rather than a patch threaded through a dozen playfield scripts.
##
## The table is a physics toy that emits events. This is the game.

signal score_changed
signal mult_changed
signal trinkets_changed
signal consumables_changed
signal balls_changed
signal tokens_changed
signal stage_changed
signal nudges_changed
signal fever_changed
signal ball_awarded  ## a trinket conjured an extra ball onto the playfield
signal toast(text: String)

const MAX_TRINKETS := 5
## Three is enough to hold an answer for the boss you can see coming and still
## have to choose; five would mean never having to.
const MAX_CONSUMABLES := 3
## Per-slot stack ceiling. Three slots of five is a lot of held power already,
## and a cap keeps the readout single-digit and hoarding bounded. Purely a
## balance number -- nothing breaks if it moves.
const MAX_STACK := 5
## Five slots, all Vanilla to begin with. The slots are simultaneously the
## inventory and the draw weights, which is what keeps the odds readable: two
## Gold in five slots is plainly a 2-in-5 chance, in a way that a separate
## weight table never would be.
const BALL_SLOTS := 5
const BASE_BALLS := 3
const MAX_NUDGES := 2
const NUDGE_RECHARGE := 5.0  # seconds per nudge
const COMBO_WINDOW := 1.5

## --- Fever ---
##
## A short-term combo multiplier, stacked on top of MULT rather than folded into
## it. The two answer different questions: MULT is the ball you have built over
## twenty seconds and lose on the drain, fever is the last two seconds. Keeping
## them separate is what makes a bumper nest feel different from a slow ball
## that has been alive a while, and lets the readout show both.
##
## Score is value x MULT x FEVER, so the cap matters: uncapped, a bumper nest
## with a stacked MULT would produce numbers that make the ante curve
## meaningless.
const FEVER_BASE := 1.0
const FEVER_STEP := 0.25
const FEVER_MAX := 5.0
## Contacts needed to climb one level. A level per hit made the number move so
## constantly that it read as noise attached to the ball rather than as
## something the player was building: every contact bumped it, so no contact
## felt like it mattered. Five gives the meter a floor to climb, and makes the
## level itself an event worth a sound and a flash.
const FEVER_HITS_PER_LEVEL := 5
## Two seconds of no contact and it is gone. Short enough that it has to be kept
## alive deliberately, long enough to survive a trip round the orbit.
const FEVER_WINDOW := 2.0

# --- Run-scoped state ---------------------------------------------------------

var ante := 1
var blind := Catalog.SMALL
var tokens := 0
var trinkets: Array[String] = []
## Always MAX_CONSUMABLES long, with "" for an empty slot.
##
## Fixed slots rather than a list that closes up, because these are bound to
## keys and fired under pressure. If firing slot 1 shuffled slot 2 down into it,
## a panicked double-tap would burn two items, and "my Slow Ball is 2" would
## never become muscle memory. A hole is the price of a stable binding.
var consumables: Array[String] = ["", "", ""]
## How many are in each slot. Invariant: consumables[i] == "" iff stacks[i] == 0.
##
## Parallel to `consumables` rather than an array of dictionaries because every
## call site already indexes by slot, and a slot number is what the 1-3 keys
## address. Kept honest by going through the helpers below rather than by being
## touched directly.
var consumable_stacks: Array[int] = [0, 0, 0]
var ball_slots: Array[String] = []
var ball_levels := {}  ## ball id -> level, absent means 1

## The balls this stage will serve, drawn at the start of it and shown to the
## player. Drawn up front rather than per serve so a bad draw is a roll you can
## see and plan around, instead of the machine appearing to cheat at the moment
## it matters.
var ball_queue: Array[String] = []
var current_ball := Catalog.VANILLA
var mods: Array[String] = []
var levels := {}  ## Catalog.Source -> int, absent means level 1
var rng := RandomNumberGenerator.new()
var seed_value := 0

# --- Stage-scoped state -------------------------------------------------------

var score := 0
var target := 0
var balls_left := 0
var boss_id := ""
var stage_mult_bonus := 0.0  ## Drop Devotion, and anything else that persists a stage
## True once the target has been crossed, with the balls that were still in hand
## at that moment. A stage now always runs its full complement of balls, so
## `balls_left` is zero by the time it is scored -- but "how many balls you did
## not need" is still the thing the payout should reward, and this is the only
## place it exists.
## Active consumable effects: id -> the real-time millisecond it expires at.
##
## Real time from Time.get_ticks_msec() rather than accumulated delta, because
## Slow Ball scales delta -- timing a six-second effect with a clock the effect
## itself slows down would make it last eleven.
var effects := {}
var _second_wind_used := false
var target_met := false
var balls_left_at_target := 0
var _ball_saved_this_stage := false

# --- Ball-scoped state --------------------------------------------------------

var mult := 1.0
var nudges := float(MAX_NUDGES)
var tilted := false
var _hits_this_ball := 0
var _bumper_hits := 0
var _spinner_bonus := 0
var _last_hit_time := -999.0
var fever := FEVER_BASE
var _fever_expires := 0.0
## Progress toward the next level, in contacts. Fractional because Combo Coil
## and the Ember ball make a hit worth more than one.
var _fever_progress := 0.0
## Contacts in the current unbroken chain, and the best chain of the run. Not
## the same as the level: this keeps counting once fever is capped, which is
## what makes it worth reporting at the end.
var fever_chain := 0
var best_chain := 0

# --- Run statistics -----------------------------------------------------------
#
# Kept for the end-of-run summary and nothing else: no rule reads any of this.
# A run is eight antes long and the only number a player carries out of it is
# whether they died, so these are the story of how it went.

## The best single stage of the run, and which one it was.
var best_stage_score := 0
var best_stage_label := ""
## Ball id -> how many times it has been served this run.
var ball_uses := {}
var _hits_since_jackpot := 0
var _hits_since_reset := 0
var _penny_progress := 0
var _lucky_progress := 0
var _ghost_saves := 0


func _ready() -> void:
	new_run()


## How far Slow Ball winds the world down.
const SLOW_SCALE := 0.55


func _process(delta: float) -> void:
	_expire_effects()
	_expire_fever()
	# Derived every frame rather than set on use and unset on expiry. A leaked
	# time scale means the whole game runs slow forever, and deriving it makes
	# that unreachable -- there is no path where it is set and not cleared.
	var want := SLOW_SCALE if effect_active("slow_ball") else 1.0
	if not is_equal_approx(Engine.time_scale, want):
		Engine.time_scale = want

	if nudges < MAX_NUDGES:
		var before := int(nudges)
		var rate := NUDGE_RECHARGE / (3.0 if effect_active("steady_hand") else 1.0)
		nudges = minf(float(MAX_NUDGES), nudges + delta / rate)
		if int(nudges) != before:
			nudges_changed.emit()


# --- Lifecycle ----------------------------------------------------------------


func new_run(with_seed: int = 0) -> void:
	seed_value = with_seed if with_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value
	ante = 1
	blind = Catalog.SMALL
	tokens = 4
	trinkets.clear()
	_clear_consumables()
	ball_slots.clear()
	for i in BALL_SLOTS:
		ball_slots.append(Catalog.VANILLA)
	ball_levels.clear()
	ball_queue.clear()
	current_ball = Catalog.VANILLA
	mods.clear()
	levels.clear()
	best_stage_score = 0
	best_stage_label = ""
	best_chain = 0
	ball_uses.clear()
	begin_stage()
	trinkets_changed.emit()
	consumables_changed.emit()
	balls_changed.emit()
	tokens_changed.emit()


func begin_stage() -> void:
	score = 0
	target = Catalog.blind_target(ante, blind)
	balls_left = balls_for_stage()
	stage_mult_bonus = 0.0
	effects.clear()
	_second_wind_used = false
	target_met = false
	balls_left_at_target = 0
	_ball_saved_this_stage = false
	boss_id = ""
	if blind == Catalog.BOSS:
		boss_id = str(Catalog.BOSSES[rng.randi() % Catalog.BOSSES.size()]["id"])
		if boss_id == "short_ball":
			balls_left = maxi(1, balls_left - 1)
	roll_ball_queue()
	begin_ball()
	stage_changed.emit()
	score_changed.emit()


## Draws this stage's balls from the slot ratio.
##
## One draw per ball, independent, so five slots of Vanilla and one Gold is a
## 1-in-5 chance *each time* rather than a guarantee of exactly one Gold. That
## is the honest reading of "based on the ratio", and it is what makes a second
## Gold worth buying.
func roll_ball_queue() -> void:
	ball_queue.clear()
	for i in balls_for_stage():
		ball_queue.append(ball_slots[rng.randi() % ball_slots.size()])
	# Nothing is in play until one is served. Leaving the previous stage's ball
	# sitting in `current_ball` would show the player a ball they no longer have
	# at the head of a queue they have not started.
	current_ball = ""
	balls_changed.emit()


## Takes the next ball off the queue. Falls back to Vanilla rather than failing:
## a relic that conjures an extra ball can outrun the queue, and an extra ball
## with no bonus is a much better outcome than no ball at all.
func take_next_ball() -> String:
	current_ball = ball_queue.pop_front() if not ball_queue.is_empty() else Catalog.VANILLA
	# Per-ball charges are refreshed *here*, when a ball is physically served,
	# and deliberately not in begin_ball(). A Ghost save calls begin_ball() to
	# reset the MULT -- refreshing there let the same ball re-earn its own save
	# every time it used one, which is an infinite ball.
	_ghost_saves = ball_level("ghost") if current_ball == "ghost" else 0
	_lucky_progress = 0
	ball_uses[current_ball] = int(ball_uses.get(current_ball, 0)) + 1
	balls_changed.emit()
	return current_ball


func ball_level(id: String) -> int:
	return int(ball_levels.get(id, 1))


## Whether a ball has actually been served. False between stages and between
## the roll and the plunge, when the queue exists but nothing is on the table.
func ball_in_play() -> bool:
	return current_ball != ""


## How much of `id`'s effect is in play right now: zero unless it is the ball on
## the table, and scaled by its level when it is.
func ball_power(id: String) -> float:
	return float(ball_level(id)) if current_ball == id else 0.0


func begin_ball() -> void:
	# Deadhead is the whole reason this is a branch and not an assignment: it
	# converts the run from three independent attempts into one accumulating
	# one, which is the single biggest swing any trinket in the pool can make.
	if not has_trinket("deadhead"):
		mult = 1.0
	mult += stage_mult_bonus
	nudges = float(MAX_NUDGES)
	tilted = false
	_hits_this_ball = 0
	_bumper_hits = 0
	_spinner_bonus = 0
	_last_hit_time = -999.0
	fever = FEVER_BASE
	_fever_expires = 0.0
	_fever_progress = 0.0
	fever_chain = 0
	fever_changed.emit()
	_hits_since_jackpot = 0
	_hits_since_reset = 0
	mult_changed.emit()
	nudges_changed.emit()


## Called when a ball leaves play. Returns true if a trinket put it back.
func consume_ball(via_outlane: bool) -> bool:
	if via_outlane and has_trinket("outlane_insurance"):
		_grant_tokens(3, "Outlane Insurance +$3")
	if current_ball == "ghost" and _ghost_saves > 0:
		_ghost_saves -= 1
		toast.emit("GHOST BALL")
		begin_ball()
		return true
	if effect_active("second_wind") and not _second_wind_used:
		_second_wind_used = true
		toast.emit("SECOND WIND")
		begin_ball()
		return true
	if has_trinket("ball_saver") and not _ball_saved_this_stage:
		_ball_saved_this_stage = true
		toast.emit("BALL SAVED")
		begin_ball()
		return true
	balls_left -= 1
	stage_changed.emit()
	if balls_left > 0:
		begin_ball()
	return false


func balls_for_stage() -> int:
	var n := BASE_BALLS
	if has_trinket("cold_solder"):
		n -= 1
	return maxi(1, n)


func stage_won() -> bool:
	return score >= target


func run_lost() -> bool:
	return balls_left <= 0 and not stage_won()


## How far past the target you finished, as a multiplier on the blind's reward.
## x1 for exactly meeting it, x2 for doubling it, capped at x5.
##
## A multiplier rather than a flat bonus because the reward should scale with the
## build: an ante 8 boss beaten twice over is a far harder thing than an ante 1
## small blind beaten twice over, and a flat bonus pays them the same. It also
## reuses the vocabulary the game already has -- everything else here multiplies
## too.
##
## Capped because the tail is unbounded. A single good ball with a stacked MULT
## can exceed an early target by an order of magnitude, and paying for all of it
## would make ante 1 fund the whole run.
const PAYOUT_MULT_CAP := 5


func payout_multiplier() -> int:
	if target <= 0:
		return 1
	return clampi(int(floor(float(score) / float(target))), 1, PAYOUT_MULT_CAP)


## Tokens paid out for clearing the current stage, itemised for the results
## screen.
##
## Balls you never needed still pay, for the same reason Balatro pays for unused
## hands: it keeps beating a small blind on one ball a strategy rather than a
## waste, even though you now play the remaining balls anyway.
func stage_payout() -> Array:
	var items: Array = []
	var base: int = Catalog.BLIND_REWARD[blind]
	items.append({"label": Catalog.BLIND_NAME[blind], "amount": base})

	var mult := payout_multiplier()
	if mult > 1:
		# Shown as the *extra* it earned, so the column still sums to the total.
		items.append({"label": "Overkill x%d" % mult, "amount": base * (mult - 1)})

	# Minus one, because the ball in hand when the target fell was needed.
	var spare := maxi(0, balls_left_at_target - 1)
	if spare > 0:
		items.append({"label": "%d ball(s) not needed" % spare, "amount": spare})

	var interest := mini(5, tokens / 5)
	if interest > 0:
		items.append({"label": "Interest", "amount": interest})
	return items


func collect_payout() -> void:
	for item in stage_payout():
		tokens += int(item["amount"])
	tokens_changed.emit()


func advance_blind() -> void:
	blind += 1
	if blind > Catalog.BOSS:
		blind = Catalog.SMALL
		ante += 1


func run_complete() -> bool:
	return ante > Catalog.ANTE_BASE.size()


# --- Scoring ------------------------------------------------------------------


## The table calls this and nothing else. `source` is a Catalog.Source; the
## return value is the points banked, for the score popup.
func register_hit(source: int, count: int = 1) -> int:
	if tilted:
		return 0

	var level: int = int(levels.get(source, 1))
	var value := float(Catalog.source_value(source, level) * count)

	# --- per-source trinket and boss hooks ---
	match source:
		Catalog.Source.BUMPER:
			_bumper_hits += count
			if boss_active("dead_bumper"):
				value = 0.0
			if has_trinket("brass_bumper"):
				value *= 3.0
			if has_trinket("magnet_coil") and _bumper_hits >= 10:
				_bumper_hits -= 10
				ball_awarded.emit()
				toast.emit("MAGNET COIL - EXTRA BALL")
		Catalog.Source.SLINGSHOT:
			if has_trinket("slingshot_savant"):
				value += 25.0 * count
		Catalog.Source.SPINNER:
			if has_trinket("spinner_fever"):
				# Each spin raises the value of the spins after it, so a long
				# rip is worth far more than the sum of its revolutions.
				value += float(_spinner_bonus) * count
				_spinner_bonus += 5 * count

	if has_trinket("cold_solder"):
		value *= 2.0
	if effect_active("ball_polish"):
		value *= 2.0
	if current_ball == "gold":
		# x2 at level 1, x3 at level 2, and so on: an upgrade is always "more of
		# what this ball already did".
		value *= 1.0 + ball_power("gold")

	# --- per-hit trinket and boss hooks ---
	var now := float(Time.get_ticks_msec()) / 1000.0
	_last_hit_time = now

	if _hits_this_ball == 0 and has_trinket("skill_shot"):
		value *= 5.0
		toast.emit("SKILL SHOT x5")
	_hits_this_ball += count

	if boss_active("reset"):
		_hits_since_reset += count
		if _hits_since_reset >= 5:
			_hits_since_reset = 0
			mult = 1.0 + stage_mult_bonus
			mult_changed.emit()

	if effect_active("jackpot_charge"):
		value += 500.0
	# value x MULT x FEVER. Fever is applied last so the readout reads left to
	# right in the same order the arithmetic happens.
	var points := int(round(value * effective_mult() * fever))

	if has_trinket("jackpot_lamp"):
		_hits_since_jackpot += count
		if _hits_since_jackpot >= 8:
			_hits_since_jackpot -= 8
			points += int(round(
				Catalog.source_value(Catalog.Source.JACKPOT, 1) * effective_mult() * fever))
			toast.emit("JACKPOT")

	_bank(points)
	# Stoked *after* the hit is scored, so the contact that starts a combo is
	# worth its base value and only the ones that follow are worth more. Stoking
	# first would mean a single isolated hit already scored above base, which is
	# not what "combo" means to anyone.
	_stoke_fever()
	return points


## Called on every scoring contact. Combo Coil now feeds this rather than MULT:
## a trinket that granted +0.2 MULT on quick hits was solving the same problem
## fever solves, and two systems for "you are hitting things quickly" is one
## more than the player can read.
##
## "Builds twice as fast" is applied to *progress* rather than to the step, so
## Combo Coil and the Ember ball still mean what they say: the level is worth
## the same 0.25 to everyone, and what they buy is reaching it in half the
## contacts. Doubling the step instead would have quietly changed the ceiling
## as well as the rate.
func _stoke_fever() -> void:
	var gain := 2.0 if has_trinket("combo_coil") else 1.0
	if current_ball == "ember":
		gain *= 1.0 + ball_power("ember")

	fever_chain += 1
	best_chain = maxi(best_chain, fever_chain)

	_fever_progress += gain
	while _fever_progress >= float(FEVER_HITS_PER_LEVEL) and fever < FEVER_MAX:
		_fever_progress -= float(FEVER_HITS_PER_LEVEL)
		fever = minf(FEVER_MAX, fever + FEVER_STEP)
	# At the cap there is nothing left to fill, so the bar reads empty rather
	# than sitting at some arbitrary fraction of a level that cannot arrive.
	if fever >= FEVER_MAX:
		_fever_progress = 0.0

	_fever_expires = float(Time.get_ticks_msec()) + FEVER_WINDOW * 1000.0
	fever_changed.emit()


## The ball served most often this run, and how many times. Ties break on the
## catalogue's own order so the same run always reports the same ball.
func most_used_ball() -> Array:
	var best_id := ""
	var best_count := 0
	for id in Catalog.BALLS:
		var count := int(ball_uses.get(id, 0))
		if count > best_count:
			best_id = str(id)
			best_count = count
	return [best_id, best_count]


## Contacts banked toward the next level, for the readout. Whole hits, because
## the readout is pips and half a pip is not a thing the player can act on.
func fever_hits_done() -> int:
	return clampi(int(floor(_fever_progress)), 0, FEVER_HITS_PER_LEVEL)


func _bank(points: int) -> void:
	if points <= 0:
		return
	score += points
	if score > best_stage_score:
		best_stage_score = score
		best_stage_label = "Ante %d %s" % [ante, Catalog.BLIND_NAME[blind]]
	if not target_met and score >= target:
		target_met = true
		balls_left_at_target = balls_left
		toast.emit("TARGET MET - PLAY ON FOR BONUS")
	if has_trinket("penny_slot"):
		_penny_progress += points
		while _penny_progress >= 1000:
			_penny_progress -= 1000
			tokens += 1
			tokens_changed.emit()
	if current_ball == "lucky":
		_lucky_progress += points
		var per := maxi(100, 500 - 100 * (ball_level("lucky") - 1))
		while _lucky_progress >= per:
			_lucky_progress -= per
			tokens += 1
			tokens_changed.emit()
	score_changed.emit()


func add_mult(amount: float) -> void:
	if effect_active("overclock"):
		amount *= 2.0
	mult += amount
	mult_changed.emit()


## The MULT actually applied to a hit, after effects that modify it without
## being part of its stored value. Kept separate from `mult` so that a
## temporary source (Tilt Gremlin) and a cap (The Governor) do not corrupt the
## number the player has been building.
func effective_mult() -> float:
	var m := mult
	if has_trinket("tilt_gremlin") and int(nudges) <= 0:
		m += 2.0
	if boss_active("governor"):
		m = minf(m, 4.0)
	return maxf(0.0, m)


## Drop banks are the only element that scores as a set rather than per-hit.
func drop_bank_cleared() -> void:
	if has_trinket("drop_devotion"):
		stage_mult_bonus += 1.0
		add_mult(1.0)
		toast.emit("DROP DEVOTION +1 MULT")


# --- Nudge and tilt -----------------------------------------------------------


## 0 = nudged, 1 = tilted, 2 = refused (the boss has taken nudging away).
func try_nudge() -> int:
	if tilted:
		return 1
	if boss_active("no_tilt"):
		return 2
	if nudges < 1.0:
		tilted = true
		mult = 1.0
		mult_changed.emit()
		toast.emit("TILT")
		return 1
	nudges -= 1.0
	nudges_changed.emit()
	return 0


# --- Inventory ----------------------------------------------------------------


## How big the ball is this stage. Heavy Ball is the clearest thing the
## playfield-as-data buys us: doubling one number means the ball no longer fits
## through the 18px drain gap, and no longer fits down an 11px outlane or a
## 22px orbit either. It protects and locks out in the same stroke, and nobody
## had to write a rule saying so.
## How big the ball on the table is.
##
## This is the one modifier that changes the *geometry* of play, and it only
## works because the type is fixed when the ball is served. Growing a ball
## mid-flight wedges it inside an 11px outlane -- which is exactly why Heavy
## Ball failed as a consumable and works as a ball.
##
## At 1.75x it no longer fits an outlane at all, which is most of its value, and
## still clears the 18px drain gap, which is what stops it being a free win.
func ball_radius_scale() -> float:
	if current_ball != "heavy":
		return 1.0
	return 1.75 + 0.15 * float(ball_level("heavy") - 1)


func effect_active(id: String) -> bool:
	return effects.has(id)


## Seconds left on an effect, for the readout. Zero if it is not running.
func effect_remaining(id: String) -> float:
	if not effects.has(id):
		return 0.0
	return maxf(0.0, (float(effects[id]) - float(Time.get_ticks_msec())) / 1000.0)


## Fever decays as a cliff, not a slope. A slow bleed would mean the number is
## always slightly wrong and never worth reading; falling off a cliff after two
## silent seconds is a rule you can play around.
func _expire_fever() -> void:
	# Partial progress and the chain count expire too, and that is the whole
	# point of a combo: five contacts spread over a minute must not add up to a
	# level. Guarding on `fever > FEVER_BASE` alone would have let a chain that
	# never reached its first level sit there indefinitely, waiting to be
	# finished off by an unrelated hit later in the ball.
	if fever <= FEVER_BASE and _fever_progress <= 0.0 and fever_chain == 0:
		return
	if float(Time.get_ticks_msec()) >= _fever_expires:
		var had_level := fever > FEVER_BASE
		fever = FEVER_BASE
		_fever_progress = 0.0
		fever_chain = 0
		fever_changed.emit()
		# Only announced when there was a multiplier to lose. Saying "FEVER
		# LOST" to someone who had not got one yet is a toast about nothing.
		if had_level:
			toast.emit("FEVER LOST")


## Seconds left before fever drops, for the readout.
func fever_remaining() -> float:
	# A chain below the first level still shows its timer: the player is
	# building something, and hiding the clock until level 1 lands would keep
	# the bar dark for exactly the five hits it is most useful.
	if fever <= FEVER_BASE and _fever_progress <= 0.0:
		return 0.0
	return maxf(0.0, (_fever_expires - float(Time.get_ticks_msec())) / 1000.0)


func _expire_effects() -> void:
	var now := float(Time.get_ticks_msec())
	for id in effects.keys():
		if float(effects[id]) <= now:
			effects.erase(id)
			toast.emit("%s ENDED" % str(Catalog.CONSUMABLES[id]["name"]).to_upper())


func has_trinket(id: String) -> bool:
	return trinkets.has(id)


func add_trinket(id: String) -> bool:
	if trinkets.size() >= MAX_TRINKETS or has_trinket(id):
		return false
	trinkets.append(id)
	trinkets_changed.emit()
	return true


## Duplicates are allowed, unlike trinkets: holding two Ball Polish is a
## legitimate thing to want, and holding two of the same trinket is not.
## Buying a second of something you already hold stacks it rather than taking a
## second slot -- that is the whole point of holding three *kinds*.
func add_consumable(id: String) -> bool:
	var slot := _stackable_slot(id)
	if slot < 0:
		slot = consumables.find("")
	if slot < 0:
		return false
	consumables[slot] = id
	consumable_stacks[slot] += 1
	consumables_changed.emit()
	return true


## An existing slot holding `id` with room left, or -1.
func _stackable_slot(id: String) -> int:
	for i in consumables.size():
		if consumables[i] == id and consumable_stacks[i] < MAX_STACK:
			return i
	return -1


## Removes one from a slot, clearing it if that was the last. Returns the id, or
## "" if the slot was already empty.
func _take_one(slot: int) -> String:
	if slot < 0 or slot >= consumables.size() or consumables[slot] == "":
		return ""
	var id: String = consumables[slot]
	consumable_stacks[slot] -= 1
	if consumable_stacks[slot] <= 0:
		consumable_stacks[slot] = 0
		consumables[slot] = ""
	return id


## Slots in use, not items held -- it is what the "2/3" readout means.
func consumable_count() -> int:
	var n := 0
	for id in consumables:
		if id != "":
			n += 1
	return n


func _clear_consumables() -> void:
	consumables.clear()
	consumable_stacks.clear()
	for i in MAX_CONSUMABLES:
		consumables.append("")
		consumable_stacks.append(0)


## Fire a consumable, mid-ball, from the 1-3 keys.
##
## Instants act now; everything else starts a real-time timer. Refiring an
## effect that is already running restarts it rather than stacking, because two
## overlapping copies of Ball Polish would be x4 and nothing in the shop says so.
func use_consumable(index: int) -> bool:
	if index < 0 or index >= consumables.size() or consumables[index] == "":
		return false
	var id: String = consumables[index]
	var def: Dictionary = Catalog.CONSUMABLES[id]
	# One at a time; the rest of the stack stays in the slot, on the same key.
	_take_one(index)

	match id:
		"extra_ball":
			balls_left += 1
			stage_changed.emit()
		"surge":
			mult = maxf(mult, 3.0)
			mult_changed.emit()
		_:
			effects[id] = Time.get_ticks_msec() + int(float(def["duration"]) * 1000.0)

	consumables_changed.emit()
	toast.emit(str(def["name"]).to_upper())
	return true


## Sell an owned item back. Returns what it fetched, or 0 if there was nothing
## at that index.
func sell(kind: String, index: int) -> int:
	var list: Array = trinkets if kind == "trinket" else consumables
	if index < 0 or index >= list.size():
		return 0
	var id: String = str(list[index])
	if id == "":
		return 0
	var price := Catalog.sell_price(kind, id)
	# Trinkets close up. Consumables sell one off the stack and the slot stays
	# put, emptying only when the last one goes.
	if kind == "trinket":
		list.remove_at(index)
	else:
		_take_one(index)
	tokens += price
	tokens_changed.emit()
	if kind == "trinket":
		trinkets_changed.emit()
	else:
		consumables_changed.emit()
	return price


## Buying a ball fills the first Vanilla slot -- Vanilla *is* the empty slot.
func add_ball(id: String) -> bool:
	var slot := ball_slots.find(Catalog.VANILLA)
	if slot < 0:
		return false
	ball_slots[slot] = id
	balls_changed.emit()
	return true


## Selling turns the slot back into Vanilla rather than removing it: there are
## always exactly five, because five is what the odds are computed against.
func sell_ball(index: int) -> int:
	if index < 0 or index >= ball_slots.size():
		return 0
	var id: String = ball_slots[index]
	if id == Catalog.VANILLA:
		return 0
	# Priced on everything sunk into it, upgrades included -- selling a Gold Lv3
	# for the price of a plain Gold would make an upgrade a thing you can only
	# ever throw away.
	var price := Catalog.ball_sell_price(id, ball_level(id))
	ball_slots[index] = Catalog.VANILLA
	# The level belongs to the balls in the rack, not to the run's memory of
	# them. Kept past the last copy, it would come back free with the next one
	# you bought -- sell low, rebuy cheap, keep the levels.
	if not ball_slots.has(id):
		ball_levels.erase(id)
	tokens += price
	tokens_changed.emit()
	balls_changed.emit()
	return price


func upgrade_ball(id: String) -> void:
	ball_levels[id] = ball_level(id) + 1
	balls_changed.emit()


## Whether there is room for what an offer would give you. Checked by the shop
## so a full inventory greys the button out rather than taking the money.
func can_take(offer: Dictionary) -> bool:
	match str(offer["kind"]):
		"trinket":
			return trinkets.size() < MAX_TRINKETS and not has_trinket(str(offer["id"]))
		"consumable":
			return consumables.has("") or _stackable_slot(str(offer["id"])) >= 0
		"ball":
			return ball_slots.has(Catalog.VANILLA)
		"ball_upgrade":
			# Upgrading a ball you do not own would be buying nothing.
			return ball_slots.has(str(offer["id"]))
	return true


func add_mod(id: String) -> bool:
	if mods.has(id):
		return false
	mods.append(id)
	return true


func has_mod(id: String) -> bool:
	return mods.has(id)


func level_up(source: int) -> void:
	levels[source] = int(levels.get(source, 1)) + 1


func boss_active(id: String) -> bool:
	return boss_id == id


func _grant_tokens(amount: int, why: String) -> void:
	tokens += amount
	tokens_changed.emit()
	toast.emit(why)


func spend(amount: int) -> bool:
	if tokens < amount:
		return false
	tokens -= amount
	tokens_changed.emit()
	return true


# --- Shop ---------------------------------------------------------------------


## Four offers, weighted toward trinkets and consumables.
##
## Trinkets lead because they are the axis players build around; consumables are
## second because they are the only thing that answers a boss you can already
## see. Table mods and levels are the long tail -- they matter, but a shop that
## mostly sells flat numbers is a shop nobody remembers.
func roll_shop(count: int = 4) -> Array:
	var offers: Array = []
	var trinket_pool: Array = []
	for id in Catalog.TRINKETS:
		if not has_trinket(id):
			trinket_pool.append(id)
	var mod_pool: Array = []
	for id in Catalog.MODS:
		if not has_mod(id):
			mod_pool.append(id)
	var consumable_pool: Array = Catalog.CONSUMABLES.keys()
	var ball_pool: Array = []
	for id in Catalog.BALLS:
		if id != Catalog.VANILLA:
			ball_pool.append(id)
	# Only offer to upgrade a ball actually owned; upgrading one you do not have
	# is buying nothing.
	var upgrade_pool: Array = []
	for id in ball_slots:
		if id != Catalog.VANILLA and not upgrade_pool.has(id):
			upgrade_pool.append(id)

	for i in count:
		var roll := rng.randf()
		if roll < 0.14 and not ball_pool.is_empty() and ball_slots.has(Catalog.VANILLA):
			var id: String = ball_pool[rng.randi() % ball_pool.size()]
			offers.append(_offer("ball", id, Catalog.BALLS[id]))
			continue
		if roll < 0.22 and not upgrade_pool.is_empty():
			var id: String = upgrade_pool[rng.randi() % upgrade_pool.size()]
			var lvl := ball_level(id)
			offers.append({
				"kind": "ball_upgrade", "id": id,
				"name": "%s Lv%d" % [Catalog.BALLS[id]["name"], lvl + 1],
				"desc": "Stronger: %s" % str(Catalog.BALLS[id]["desc"]).to_lower(),
				"cost": Catalog.ball_upgrade_cost(lvl),
			})
			continue
		if roll < 0.55 and not trinket_pool.is_empty():
			var id: String = trinket_pool[rng.randi() % trinket_pool.size()]
			trinket_pool.erase(id)
			offers.append(_offer("trinket", id, Catalog.TRINKETS[id]))
		elif roll < 0.80 and not consumable_pool.is_empty():
			# Not erased from the pool: two of the same consumable on one shelf
			# is fine, because holding two of them is fine.
			var id: String = consumable_pool[rng.randi() % consumable_pool.size()]
			offers.append(_offer("consumable", id, Catalog.CONSUMABLES[id]))
		elif roll < 0.88 and not mod_pool.is_empty():
			var id: String = mod_pool[rng.randi() % mod_pool.size()]
			mod_pool.erase(id)
			offers.append(_offer("mod", id, Catalog.MODS[id]))
		else:
			var sources := Catalog.SOURCE_STATS.keys()
			sources.erase(Catalog.Source.JACKPOT)
			var src: int = sources[rng.randi() % sources.size()]
			var lvl: int = int(levels.get(src, 1))
			offers.append({
				"kind": "level", "id": src,
				"name": "%s Lv%d" % [Catalog.SOURCE_STATS[src]["name"], lvl + 1],
				"desc": "+%d base value" % int(Catalog.SOURCE_STATS[src]["per_level"]),
				"cost": 3 + lvl,
			})
	return offers


func _offer(kind: String, id: String, def: Dictionary) -> Dictionary:
	return {
		"kind": kind, "id": id,
		"name": str(def["name"]), "desc": str(def["desc"]), "cost": int(def["cost"]),
	}


func buy(offer: Dictionary) -> bool:
	# Capacity is checked before the money moves, so a full inventory cannot
	# take payment for something it has nowhere to put.
	if not can_take(offer):
		return false
	if not spend(int(offer["cost"])):
		return false
	match str(offer["kind"]):
		"trinket":
			add_trinket(str(offer["id"]))
		"consumable":
			add_consumable(str(offer["id"]))
		"ball":
			add_ball(str(offer["id"]))
		"ball_upgrade":
			upgrade_ball(str(offer["id"]))
		"mod":
			add_mod(str(offer["id"]))
		"level":
			level_up(int(offer["id"]))
	return true
