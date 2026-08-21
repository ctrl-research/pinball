extends Node
## Does a run survive being written to disk and read back?
##
## This has its own suite because the failure mode is silence. A save that
## quietly forgets the player's trinkets looks exactly like a save that worked,
## so the round trip is asserted field by field against a run built to have
## something in every container rather than by spot-checking a couple of
## numbers.
##
## `_untyped_source()` is the case that matters most. ConfigFile turns out to
## preserve a typed array's element type, so loading a file this build wrote is
## the easy path; anything else -- a hand-edited save, a file from a build with
## differently shaped containers -- arrives as plain `Array`s, and assigning one
## of those to an `Array[String]` fails at runtime without stopping anything.
##
## Prints SAVE_TEST_OK on success; CI greps for it.

var _failures := 0


func _ready() -> void:
	_round_trip()
	_untyped_source()
	_stale_format()
	_clear()
	_settings()
	_finish()


## Everything filled, then saved, then read back into a Run that has been
## deliberately scribbled over in between.
func _round_trip() -> void:
	Save.clear_run()
	Run.new_run(9182)
	Run.ante = 5
	Run.blind = Catalog.BOSS
	Run.tokens = 37
	Run.trinkets.assign(["deadhead", "combo_coil", "penny_slot"])
	Run.add_consumable("surge")
	Run.add_consumable("surge")
	Run.add_consumable("slow_ball")
	Run.ball_slots[0] = "gold"
	Run.ball_slots[1] = "ember"
	Run.ball_levels["gold"] = 3
	Run.coils.assign(["hot_winding", "kickback"])
	Run.mods.assign(["extra_bumper"])
	Run.levels[Catalog.Source.BUMPER] = 4
	Run.best_stage_score = 24500
	Run.best_stage_label = "Ante 4 Boss Blind"
	Run.best_chain = 31
	Run.ball_uses["gold"] = 6

	var want := Run.to_dict().duplicate(true)
	Save.save_run()
	_check(Save.has_run(), "the run is on disk")

	# Scribbled over, so a loader that silently does nothing is caught rather
	# than passing because the values happened to still be there.
	Run.new_run(1)
	Run.tokens = 0
	Run.trinkets.clear()

	_check(Save.load_run(), "and loads back")
	var got := Run.to_dict()
	for key in want:
		_eq(str(got.get(key)), str(want[key]), "%s survived the round trip" % key)

	# The containers have to come back as their declared types, or the next
	# `append` on them fails somewhere far away from here.
	_check(Run.trinkets is Array[String], "trinkets is still Array[String]")
	_check(Run.consumable_stacks is Array[int], "stacks is still Array[int]")
	_eq(Run.trinkets.size(), 3, "and holds what it held")
	_eq(Run.coils.size(), 2, "as does coils")

	# A resumed run starts the stage it was on, which means a live target and a
	# full complement of balls rather than whatever was left mid-stage.
	_eq(Run.score, 0, "the restored stage starts at zero")
	_eq(Run.target, Catalog.blind_target(5, Catalog.BOSS), "with its own target")
	_check(Run.balls_left > 0, "and balls to play it with")


## Loading from plain, untyped containers -- which is what any source other than
## this build's own ConfigFile will hand over.
func _untyped_source() -> void:
	Run.new_run(3)
	var plain := {
		"ante": 2,
		"tokens": 11,
		"trinkets": ["deadhead", "penny_slot"],
		"consumables": ["surge", "", ""],
		"consumable_stacks": [2, 0, 0],
		"ball_slots": ["gold", "vanilla", "vanilla", "vanilla", "vanilla"],
		"coils": ["kickback"],
		"mods": ["extra_bumper"],
	}
	Run.from_dict(plain)

	_eq(Run.ante, 2, "an untyped save still loads")
	_eq(Run.tokens, 11, "with its money")
	_eq(Run.trinkets.size(), 2, "and its trinkets")
	_eq(Run.coils.size(), 1, "and its coils")
	_eq(Run.mods.size(), 1, "and its mods")
	_eq(Run.consumable_stacks[0], 2, "and its stacks")
	_check(Run.trinkets is Array[String], "as a typed array on the far side")

	# And the loaded containers have to still behave like their declared type.
	_check(Run.add_trinket("combo_coil"), "a loaded rack still takes an addition")
	_eq(Run.trinkets.size(), 3, "and grows")


## A save from a build whose shape has changed is dropped, not half-read.
func _stale_format() -> void:
	Save.clear_run()
	Run.new_run(4)
	Save.save_run()
	var cfg := ConfigFile.new()
	cfg.load(Save.RUN_PATH)
	cfg.set_value("meta", "format", Save.RUN_FORMAT + 99)
	cfg.save(Save.RUN_PATH)

	_check(not Save.load_run(), "a future format is refused")
	_check(not Save.has_run(), "and the file is discarded rather than left to rot")


func _clear() -> void:
	Run.new_run(5)
	Save.save_run()
	_check(Save.has_run(), "saved")
	Save.clear_run()
	_check(not Save.has_run(), "and cleared")
	_check(not Save.load_run(), "loading nothing reports nothing")


func _settings() -> void:
	var was := Crt.enabled
	Crt.enabled = false
	Save.save_settings()
	Crt.enabled = true
	Save.load_settings()
	_check(not Crt.enabled, "the CRT setting survives a reload")
	Crt.enabled = true
	Save.save_settings()
	Crt.enabled = false
	Save.load_settings()
	_check(Crt.enabled, "and so does the other way round")
	Crt.enabled = was
	Save.save_settings()


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL: %s" % what)


func _eq(actual, expected, what: String) -> void:
	_check(actual == expected, "%s -- got %s, expected %s" % [what, actual, expected])


func _finish() -> void:
	Save.clear_run()
	if _failures > 0:
		push_error("SAVE_TEST_FAILED")
		print("SAVE_TEST_FAILED: %d" % _failures)
		get_tree().quit(1)
		return
	print("SAVE_TEST_OK")
	get_tree().quit(0)
