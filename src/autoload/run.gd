extends Node
## Run state and all scoring arithmetic (autoload "Run").
##
## Everything that answers "how many points was that worth" lives here, and the
## table only ever reports *what was hit*. Keeping the arithmetic in one place
## is what makes relics tractable: a relic is a branch at a named hook in this
## file rather than a patch threaded through a dozen playfield scripts.
##
## The table is a physics toy that emits events. This is the game.

signal score_changed
signal mult_changed
signal relics_changed
signal tokens_changed
signal stage_changed
signal nudges_changed
signal ball_awarded  ## a relic conjured an extra ball onto the playfield
signal toast(text: String)

const MAX_RELICS := 5
const BASE_BALLS := 3
const MAX_NUDGES := 2
const NUDGE_RECHARGE := 5.0  # seconds per nudge
const COMBO_WINDOW := 1.5

# --- Run-scoped state ---------------------------------------------------------

var ante := 1
var blind := Catalog.SMALL
var tokens := 0
var relics: Array[String] = []
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
var _ball_saved_this_stage := false

# --- Ball-scoped state --------------------------------------------------------

var mult := 1.0
var nudges := float(MAX_NUDGES)
var tilted := false
var _hits_this_ball := 0
var _bumper_hits := 0
var _spinner_bonus := 0
var _last_hit_time := -999.0
var _hits_since_jackpot := 0
var _hits_since_reset := 0
var _penny_progress := 0


func _ready() -> void:
	new_run()


func _process(delta: float) -> void:
	if nudges < MAX_NUDGES:
		var before := int(nudges)
		nudges = minf(float(MAX_NUDGES), nudges + delta / NUDGE_RECHARGE)
		if int(nudges) != before:
			nudges_changed.emit()


# --- Lifecycle ----------------------------------------------------------------


func new_run(with_seed: int = 0) -> void:
	seed_value = with_seed if with_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value
	ante = 1
	blind = Catalog.SMALL
	tokens = 4
	relics.clear()
	mods.clear()
	levels.clear()
	begin_stage()
	relics_changed.emit()
	tokens_changed.emit()


func begin_stage() -> void:
	score = 0
	target = Catalog.blind_target(ante, blind)
	balls_left = balls_for_stage()
	stage_mult_bonus = 0.0
	_ball_saved_this_stage = false
	boss_id = ""
	if blind == Catalog.BOSS:
		boss_id = str(Catalog.BOSSES[rng.randi() % Catalog.BOSSES.size()]["id"])
		if boss_id == "short_ball":
			balls_left = maxi(1, balls_left - 1)
	begin_ball()
	stage_changed.emit()
	score_changed.emit()


func begin_ball() -> void:
	# Deadhead is the whole reason this is a branch and not an assignment: it
	# converts the run from three independent attempts into one accumulating
	# one, which is the single biggest swing any relic in the pool can make.
	if not has_relic("deadhead"):
		mult = 1.0
	mult += stage_mult_bonus
	nudges = float(MAX_NUDGES)
	tilted = false
	_hits_this_ball = 0
	_bumper_hits = 0
	_spinner_bonus = 0
	_last_hit_time = -999.0
	_hits_since_jackpot = 0
	_hits_since_reset = 0
	mult_changed.emit()
	nudges_changed.emit()


## Called when a ball leaves play. Returns true if a relic put it back.
func consume_ball(via_outlane: bool) -> bool:
	if via_outlane and has_relic("outlane_insurance"):
		_grant_tokens(3, "Outlane Insurance +$3")
	if has_relic("ball_saver") and not _ball_saved_this_stage:
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
	if has_relic("cold_solder"):
		n -= 1
	return maxi(1, n)


func stage_won() -> bool:
	return score >= target


func run_lost() -> bool:
	return balls_left <= 0 and not stage_won()


## Tokens paid out for clearing the current stage, itemised for the results
## screen. Unused balls pay out for the same reason Balatro pays for unused
## hands: it makes overkill on a small blind a strategy rather than a waste.
func stage_payout() -> Array:
	var items: Array = []
	items.append({"label": Catalog.BLIND_NAME[blind], "amount": Catalog.BLIND_REWARD[blind]})
	if balls_left > 0:
		items.append({"label": "%d ball(s) unused" % balls_left, "amount": balls_left})
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

	# --- per-source relic and boss hooks ---
	match source:
		Catalog.Source.BUMPER:
			_bumper_hits += count
			if boss_active("dead_bumper"):
				value = 0.0
			if has_relic("brass_bumper"):
				value *= 3.0
			if has_relic("magnet_coil") and _bumper_hits >= 10:
				_bumper_hits -= 10
				ball_awarded.emit()
				toast.emit("MAGNET COIL - EXTRA BALL")
		Catalog.Source.SLINGSHOT:
			if has_relic("slingshot_savant"):
				value += 25.0 * count
		Catalog.Source.SPINNER:
			if has_relic("spinner_fever"):
				# Each spin raises the value of the spins after it, so a long
				# rip is worth far more than the sum of its revolutions.
				value += float(_spinner_bonus) * count
				_spinner_bonus += 5 * count

	if has_relic("cold_solder"):
		value *= 2.0

	# --- per-hit relic and boss hooks ---
	var now := float(Time.get_ticks_msec()) / 1000.0
	if has_relic("combo_coil") and now - _last_hit_time <= COMBO_WINDOW:
		add_mult(0.2)
	_last_hit_time = now

	if _hits_this_ball == 0 and has_relic("skill_shot"):
		value *= 5.0
		toast.emit("SKILL SHOT x5")
	_hits_this_ball += count

	if boss_active("reset"):
		_hits_since_reset += count
		if _hits_since_reset >= 5:
			_hits_since_reset = 0
			mult = 1.0 + stage_mult_bonus
			mult_changed.emit()

	var points := int(round(value * effective_mult()))

	if has_relic("jackpot_lamp"):
		_hits_since_jackpot += count
		if _hits_since_jackpot >= 8:
			_hits_since_jackpot -= 8
			points += int(round(Catalog.source_value(Catalog.Source.JACKPOT, 1) * effective_mult()))
			toast.emit("JACKPOT")

	_bank(points)
	return points


func _bank(points: int) -> void:
	if points <= 0:
		return
	score += points
	if has_relic("penny_slot"):
		_penny_progress += points
		while _penny_progress >= 1000:
			_penny_progress -= 1000
			tokens += 1
			tokens_changed.emit()
	score_changed.emit()


func add_mult(amount: float) -> void:
	mult += amount
	mult_changed.emit()


## The MULT actually applied to a hit, after effects that modify it without
## being part of its stored value. Kept separate from `mult` so that a
## temporary source (Tilt Gremlin) and a cap (The Governor) do not corrupt the
## number the player has been building.
func effective_mult() -> float:
	var m := mult
	if has_relic("tilt_gremlin") and int(nudges) <= 0:
		m += 2.0
	if boss_active("governor"):
		m = minf(m, 4.0)
	return maxf(0.0, m)


## Drop banks are the only element that scores as a set rather than per-hit.
func drop_bank_cleared() -> void:
	if has_relic("drop_devotion"):
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


func has_relic(id: String) -> bool:
	return relics.has(id)


func add_relic(id: String) -> bool:
	if relics.size() >= MAX_RELICS or has_relic(id):
		return false
	relics.append(id)
	relics_changed.emit()
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


## Three offers: weighted toward relics, because relics are the axis players
## build around and a shop that mostly sells flat numbers is a shop nobody
## remembers.
func roll_shop(count: int = 3) -> Array:
	var offers: Array = []
	var relic_pool: Array = []
	for id in Catalog.RELICS:
		if not has_relic(id) and relics.size() < MAX_RELICS:
			relic_pool.append(id)
	var mod_pool: Array = []
	for id in Catalog.MODS:
		if not has_mod(id):
			mod_pool.append(id)

	for i in count:
		var roll := rng.randf()
		if roll < 0.6 and not relic_pool.is_empty():
			var id: String = relic_pool[rng.randi() % relic_pool.size()]
			relic_pool.erase(id)
			offers.append({
				"kind": "relic", "id": id,
				"name": Catalog.RELICS[id]["name"], "desc": Catalog.RELICS[id]["desc"],
				"cost": Catalog.RELICS[id]["cost"],
			})
		elif roll < 0.8 and not mod_pool.is_empty():
			var id: String = mod_pool[rng.randi() % mod_pool.size()]
			mod_pool.erase(id)
			offers.append({
				"kind": "mod", "id": id,
				"name": Catalog.MODS[id]["name"], "desc": Catalog.MODS[id]["desc"],
				"cost": Catalog.MODS[id]["cost"],
			})
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


func buy(offer: Dictionary) -> bool:
	if not spend(int(offer["cost"])):
		return false
	match str(offer["kind"]):
		"relic":
			add_relic(str(offer["id"]))
		"mod":
			add_mod(str(offer["id"]))
		"level":
			level_up(int(offer["id"]))
	return true
