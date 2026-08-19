extends Node
## Prints everything in `catalog.gd` as JSON, so the reference manual's tables
## can be generated from the same data the game runs on.
##
## The manual is meant to stay true as the game changes, and the reliable way to
## do that is to stop anyone having to remember. A cost or an effect retyped
## into a document is a cost or an effect that will eventually be wrong; one
## generated from Catalog cannot be.
##
##   godot --headless --path . tools/dump_catalog.tscn > /tmp/catalog.json
##   python3 tools/build_manual.py /tmp/catalog.json

func _ready() -> void:
	var levels: Array = []
	for source in Catalog.SOURCE_STATS:
		var stats: Dictionary = Catalog.SOURCE_STATS[source]
		levels.append({
			"name": stats["name"], "base": stats["base"], "per_level": stats["per_level"],
		})

	var blinds: Array = []
	for ante in range(1, Catalog.ANTE_BASE.size() + 1):
		blinds.append({
			"ante": ante,
			"small": Catalog.blind_target(ante, Catalog.SMALL),
			"big": Catalog.blind_target(ante, Catalog.BIG),
			"boss": Catalog.blind_target(ante, Catalog.BOSS),
		})

	print(JSON.stringify({
		"trinkets": _entries(Catalog.TRINKETS, "trinket"),
		"consumables": _entries(Catalog.CONSUMABLES, "consumable"),
		"mods": _entries(Catalog.MODS, ""),
		"coils": _entries(Catalog.COILS, "coil"),
		"balls": _entries(Catalog.BALLS, "ball"),
		"bosses": Catalog.BOSSES,
		"levels": levels,
		"blinds": blinds,
		"limits": {
			"trinkets": Run.MAX_TRINKETS,
			"consumables": Run.MAX_CONSUMABLES,
			"stack": Run.MAX_STACK,
			"balls": Run.BASE_BALLS,
			"ball_slots": Run.BALL_SLOTS,
			"coils": Run.MAX_COILS,
			"ball_upgrade": Catalog.BALL_UPGRADE_COST,
			"ball_upgrade_step": Catalog.BALL_UPGRADE_STEP,
			"nudges": Run.MAX_NUDGES,
			"nudge_recharge": Run.NUDGE_RECHARGE,
			"payout_cap": Run.PAYOUT_MULT_CAP,
			"fever_hits": Run.FEVER_HITS_PER_LEVEL,
			"fever_step": Run.FEVER_STEP,
			"fever_max": Run.FEVER_MAX,
			"fever_window": Run.FEVER_WINDOW,
			"sell_fraction": Catalog.SELL_FRACTION,
			"blind_rewards": Catalog.BLIND_REWARD,
			"blind_names": Catalog.BLIND_NAME,
		},
	}))
	get_tree().quit(0)


func _entries(table: Dictionary, kind: String) -> Array:
	var out: Array = []
	for id in table:
		var def: Dictionary = table[id]
		var row := {
			"id": id, "name": def["name"], "desc": def["desc"], "cost": def["cost"],
		}
		if kind != "":
			row["sell"] = Catalog.sell_price(kind, id)
		if def.has("duration"):
			row["duration"] = def["duration"]
		out.append(row)
	return out
