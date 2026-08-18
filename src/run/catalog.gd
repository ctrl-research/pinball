class_name Catalog
extends RefCounted
## Everything the shop can sell and every blind the run can throw at you, as
## data. Behaviour lives in `run.gd` — this file is only names, numbers and
## text, so balance passes never touch logic.

# --- Scoring sources ----------------------------------------------------------

enum Source { BUMPER, SLINGSHOT, DROP, STANDUP, SPINNER, ROLLOVER, ORBIT, JACKPOT }

## Base value and per-level gain for each class of target. Levelling a *class*
## rather than an instance is what makes a table mod that adds a fourth bumper
## worth more at ante 6 than it was at ante 1.
const SOURCE_STATS := {
	Source.BUMPER: {"name": "Pop Bumpers", "base": 10, "per_level": 8},
	Source.SLINGSHOT: {"name": "Slingshots", "base": 15, "per_level": 10},
	Source.DROP: {"name": "Drop Targets", "base": 50, "per_level": 35},
	Source.STANDUP: {"name": "Standup Targets", "base": 30, "per_level": 20},
	Source.SPINNER: {"name": "Spinner", "base": 5, "per_level": 4},
	Source.ROLLOVER: {"name": "Rollover Lanes", "base": 25, "per_level": 15},
	Source.ORBIT: {"name": "Orbits", "base": 100, "per_level": 60},
	Source.JACKPOT: {"name": "Jackpot", "base": 500, "per_level": 0},
}

# --- Blinds -------------------------------------------------------------------

const SMALL := 0
const BIG := 1
const BOSS := 2

## Balatro's ante curve, borrowed wholesale because it is a curve that is known
## to work: roughly triples early, then stretches so the last two antes are
## build checks rather than arithmetic.
const ANTE_BASE := [300, 800, 2000, 5000, 11000, 20000, 35000, 50000]
const BLIND_MULT := [1.0, 1.5, 2.0]
const BLIND_NAME := ["Small Blind", "Big Blind", "Boss Blind"]
const BLIND_REWARD := [3, 4, 5]

const BOSSES := [
	{"id": "governor", "name": "The Governor", "desc": "MULT is capped at x4"},
	{"id": "dead_bumper", "name": "The Dead Bumper", "desc": "Pop bumpers score nothing"},
	{"id": "wide_drain", "name": "The Drain", "desc": "Outlanes are twice as wide"},
	{"id": "short_ball", "name": "The Short Ball", "desc": "You get one fewer ball"},
	{"id": "warp", "name": "The Warp", "desc": "The left flipper dies for 3s at a time"},
	{"id": "no_tilt", "name": "The Tilt", "desc": "Nudging is disabled"},
	{"id": "reset", "name": "The Reset", "desc": "Every 5th hit resets MULT to x1"},
	{"id": "fog", "name": "The Fog", "desc": "The upper playfield is not drawn"},
]

# --- Trinkets -------------------------------------------------------------------

const COMMON := 0
const UNCOMMON := 1
const RARE := 2

const TRINKETS := {
	"brass_bumper": {
		"name": "Brass Bumper", "desc": "Pop bumpers score x3 value",
		"cost": 4, "rarity": COMMON,
	},
	"slingshot_savant": {
		"name": "Slingshot Savant", "desc": "Slingshots score +25 value",
		"cost": 4, "rarity": COMMON,
	},
	"combo_coil": {
		"name": "Combo Coil", "desc": "Each hit within 1.5s of the last: +0.2 MULT",
		"cost": 6, "rarity": UNCOMMON,
	},
	"skill_shot": {
		"name": "Skill Shot", "desc": "The first hit of each ball scores x5",
		"cost": 5, "rarity": COMMON,
	},
	"ball_saver": {
		"name": "Ball Saver", "desc": "The first drain each stage returns the ball",
		"cost": 6, "rarity": UNCOMMON,
	},
	"tilt_gremlin": {
		"name": "Tilt Gremlin", "desc": "+2 MULT while you have no nudges left",
		"cost": 5, "rarity": UNCOMMON,
	},
	"drop_devotion": {
		"name": "Drop Devotion", "desc": "Clearing the drop bank: +1 MULT for the stage",
		"cost": 6, "rarity": UNCOMMON,
	},
	"spinner_fever": {
		"name": "Spinner Fever", "desc": "Each spin this ball raises spinner value by 5",
		"cost": 5, "rarity": COMMON,
	},
	"outlane_insurance": {
		"name": "Outlane Insurance", "desc": "Draining down an outlane pays $3",
		"cost": 4, "rarity": COMMON,
	},
	"penny_slot": {
		"name": "Penny Slot", "desc": "$1 per 1,000 points scored",
		"cost": 6, "rarity": UNCOMMON,
	},
	"magnet_coil": {
		"name": "Magnet Coil", "desc": "Every 10 bumper hits spawns a second ball",
		"cost": 8, "rarity": RARE,
	},
	"jackpot_lamp": {
		"name": "Jackpot Lamp", "desc": "Every 8th hit scores a flat 500 x MULT",
		"cost": 7, "rarity": UNCOMMON,
	},
	"cold_solder": {
		"name": "Cold Solder", "desc": "-1 ball per stage, but all values x2",
		"cost": 7, "rarity": RARE,
	},
	# The deliberate rule-breaker. Balatro keeps one joker that invalidates a
	# core rule; this is ours -- it turns three separate attempts into one long
	# accumulating attempt, so it is rare and it is expensive.
	"deadhead": {
		"name": "Deadhead", "desc": "MULT no longer resets between balls",
		"cost": 10, "rarity": RARE,
	},
}

# --- Consumables --------------------------------------------------------------

## One-shot items, held up to three at a time and fired **mid-ball** with the
## 1-3 keys. Most run on a timer and then stop.
##
## That timing is the whole design. A consumable spent on a menu is just a
## slower shop purchase; a consumable spent with the ball live is a read -- pop
## Ball Polish now, or hold it in case this ball reaches the bumpers? An earlier
## version had these chosen on the stage intro screen and it was exactly the
## boring version of this.
##
## `duration` of 0 means it fires once and is over; anything else is seconds of
## real time, which is why the strongest ones are the shortest.
const CONSUMABLES = {
	"steady_hand": {
		"name": "Steady Hand", "desc": "30s: nudges recharge 3x faster",
		"cost": 3, "duration": 30.0,
	},
	"ball_polish": {
		"name": "Ball Polish", "desc": "20s: all values x2",
		"cost": 5, "duration": 20.0,
	},
	"overclock": {
		"name": "Overclock", "desc": "20s: MULT gains are doubled",
		"cost": 6, "duration": 20.0,
	},
	"second_wind": {
		"name": "Second Wind", "desc": "30s: a drain returns the ball",
		"cost": 5, "duration": 30.0,
	},
	"jackpot_charge": {
		"name": "Jackpot Charge", "desc": "12s: every hit also pays a flat 500",
		"cost": 5, "duration": 12.0,
	},
	## The one the whole scheme was worth building for. Slowing time is the most
	## powerful thing you can hand a player in a real-time game, so it is also
	## the shortest and the dearest -- six seconds is enough to save one ball you
	## had already lost, and not enough to play the game in.
	"slow_ball": {
		"name": "Slow Ball", "desc": "6s: everything runs at 55% speed",
		"cost": 7, "duration": 6.0,
	},
	## Instant, because a MULT floor is not a state you can be in for 20 seconds
	## -- it is a thing that either happened or did not.
	"surge": {
		"name": "Surge", "desc": "MULT jumps to at least x3, now",
		"cost": 6, "duration": 0.0,
	},
	"extra_ball": {
		"name": "Extra Ball", "desc": "One more ball this stage",
		"cost": 6, "duration": 0.0,
	},
}

# --- Table mods ---------------------------------------------------------------

## Permanent changes to the physical playfield -- the roguelike lever pinball
## has and a card game does not.
const MODS := {
	"extra_bumper": {
		"name": "Extra Bumper", "desc": "A fourth pop bumper joins the cluster", "cost": 7,
	},
	"wide_flippers": {
		"name": "Wide Flippers", "desc": "+4px flipper length; a narrower drain", "cost": 8,
	},
	"post_rubber": {
		"name": "Post Rubber", "desc": "A centre post between the flippers", "cost": 8,
	},
	"outlane_guards": {
		"name": "Outlane Guards", "desc": "Both outlanes are narrowed", "cost": 6,
	},
}


static func blind_target(ante: int, blind: int) -> int:
	var base: int = ANTE_BASE[clampi(ante - 1, 0, ANTE_BASE.size() - 1)]
	return int(round(float(base) * BLIND_MULT[blind]))


static func source_value(source: int, level: int) -> int:
	var stats: Dictionary = SOURCE_STATS[source]
	return int(stats["base"]) + int(stats["per_level"]) * maxi(0, level - 1)


## What an owned item fetches when sold: three quarters of its shelf price,
## rounded down. Deliberately lossy -- a lossless sell would make the shop a
## place to park money rather than a place to make a decision.
const SELL_FRACTION := 0.75


static func sell_price(kind: String, id: String) -> int:
	var table: Dictionary = TRINKETS if kind == "trinket" else CONSUMABLES
	if not table.has(id):
		return 0
	return int(floor(float(table[id]["cost"]) * SELL_FRACTION))
