extends Node
## Regression test for the shop's mouse path.
##
## Everything else between stages can be driven from the keyboard, and the
## headless sim does exactly that -- it taps space to get through the overlays.
## Buying and selling cannot: they are clicks on rows, and nothing else in the
## suite presses one. That was survivable while the UI was plain Controls on a
## CanvasLayer, and stopped being survivable when it moved inside a
## SubViewportContainer, which has to *forward* input rather than simply
## receive it. A shop that quietly stops taking clicks is an unplayable game
## that passes every other gate.
##
## So this sends a real InputEventMouseButton at real window coordinates and
## checks the money moved. Prints CLICK_TEST_OK on success; CI greps for it.

var _game: Game
var _failures := 0
var _bought := -1
var _sold_kind := ""


func _ready() -> void:
	Run.new_run(4242)
	Run.tokens = 40
	_game = Game.new()
	add_child(_game)
	await get_tree().process_frame

	_game.hud.bought.connect(func(i: int) -> void: _bought = i)
	_game.hud.sold.connect(func(kind: String, _i: int) -> void: _sold_kind = kind)

	await _test_buy()
	await _test_sell()
	await _test_on_screen()
	_test_panel_fits()
	_finish()


## The first row on the shelf, bought by clicking it.
func _test_buy() -> void:
	_game._enter_shop()
	await _settle()

	var offers := _game.shop_offers
	if offers.is_empty():
		_fail("the shop offered nothing to click")
		return
	var button := _find_button(_game.hud, str(offers[0]["name"]))
	if button == null:
		_fail("no button for the first offer")
		return

	var before := Run.tokens
	var cost := int(offers[0]["cost"])
	await _click(button)

	if _bought != 0:
		_fail("clicking the first offer did not report a purchase")
	elif Run.tokens != before - cost:
		_fail("bought %s but money went %d -> %d, not -%d"
			% [offers[0]["name"], before, Run.tokens, cost])
	else:
		print("  ok: a click on the shelf buys the item")


## And the inventory side, which is a different set of rows built the same way.
func _test_sell() -> void:
	Run.trinkets.clear()
	Run.trinkets.append("deadhead")
	_game._enter_shop()
	await _settle()

	var button := _find_button(_game.hud, "Deadhead")
	if button == null:
		_fail("no sell button for an owned trinket")
		return

	var before := Run.tokens
	await _click(button)

	if _sold_kind != "trinket":
		_fail("clicking an owned trinket did not report a sale")
	elif Run.tokens <= before:
		_fail("sold a trinket but money did not go up (%d -> %d)"
			% [before, Run.tokens])
	else:
		print("  ok: a click on the inventory sells the item")


## The right panel's last flowing element must not run into the block anchored
## to its floor.
##
## The panel is a fixed 348px and every feature added to it has been paid for
## out of the same budget. When the fever readout became a five-segment meter it
## grew by six pixels and landed on top of the key map -- which nothing caught,
## because overlapping labels still draw, still pass every other gate, and only
## look wrong. This is the invariant that was actually broken: the meter ends
## above the keys.
func _test_panel_fits() -> void:
	var meter: Control = _game.hud._fever_meter
	var keys: Label = null
	for child in _game.hud._root.get_children():
		if child is Label and (child as Label).text.begins_with("A / D"):
			keys = child as Label
	if keys == null:
		_fail("the key map is missing from the panel")
		return

	var meter_bottom := meter.position.y + meter.size.y
	var panel := Cabinet.PANEL_RIGHT
	if meter_bottom > keys.position.y:
		_fail("the fever meter ends at y=%.0f, over the key map at y=%.0f"
			% [meter_bottom, keys.position.y])
	elif meter_bottom > panel.position.y + panel.size.y:
		_fail("the fever meter ends at y=%.0f, past the panel at y=%.0f"
			% [meter_bottom, panel.position.y + panel.size.y])
	else:
		print("  ok: the right panel's contents fit above the key map")


## Every overlay must fit on the screen, checked at its worst case: a full rack
## of trinkets, consumables and balls, which is thirteen inventory rows on top
## of the offers.
##
## This is here because raising the text scale pushed the shop's NEXT BLIND
## button clean off the bottom of the screen. The keyboard still worked, so the
## sim sailed through it and the buy/sell checks above passed too -- the button
## was simply not reachable by mouse, which is an unfinishable run for anyone
## playing with one.
func _test_on_screen() -> void:
	Run.trinkets.clear()
	Run.trinkets.assign(["deadhead", "combo_coil", "jackpot_lamp", "penny_slot",
		"outlane_insurance"])
	Run._clear_consumables()
	for id in ["surge", "slow_ball", "wormhole"]:
		Run.add_consumable(id)
	for i in Run.BALL_SLOTS:
		Run.ball_slots[i] = "gold"
	Run.coils.clear()
	for id in ["hot_winding", "heavy_bat", "dead_bounce"]:
		Run.add_coil(id)

	var screen := Rect2(Vector2.ZERO, Vector2(TextScreen.RESOLUTION))
	# Every tab, not just the one the shop opens on: each holds a different
	# number of rows, and it is the tallest that decides whether the button
	# fits.
	var screens := {
		"shop tab 0": func() -> void: _game._enter_shop(),
		"shop tab 1": func() -> void: _game.hud._on_shop_tab(1),
		"shop tab 2": func() -> void: _game.hud._on_shop_tab(2),
		"shop tab 3": func() -> void: _game.hud._on_shop_tab(3),
		"intro": func() -> void: _game.hud.show_intro(),
		"cleared": func() -> void: _game.hud.show_cleared(Run.stage_payout()),
		"defeat": func() -> void: _game.hud.show_lost(),
		"victory": func() -> void: _game.hud.show_won(),
	}
	for name in screens:
		(screens[name] as Callable).call()
		await _settle()
		var button := _last_button(_game.hud)
		if button == null:
			_fail("%s has no button to continue with" % name)
			continue
		var rect := button.get_global_rect()
		if not screen.encloses(rect):
			_fail("%s: its %s button is at %s, outside the %s screen"
				% [name, button.text, rect, screen.size])
		else:
			print("  ok: %s fits on screen" % name)


## The continue button is the last one built on every screen.
func _last_button(node: Node) -> Button:
	var found: Button = null
	for child in node.get_children():
		if child is Button and (child as Button).is_visible_in_tree():
			found = child
		var deeper := _last_button(child)
		if deeper != null:
			found = deeper
	return found


## The UI is laid out in the text screen's 640x360 space, while a real click
## arrives in window pixels, so the button's rect has to be mapped through the
## same stretch the player's pointer goes through.
##
## That mapping comes from the root viewport rather than from DisplayServer,
## which reports a window size of (0, 0) with no window at all -- and a scale
## factor of zero puts every click at the origin, where it hits nothing and the
## test fails for a reason that has nothing to do with the shop.
func _click(button: Button) -> void:
	var to_window := get_tree().root.get_final_transform()
	var at: Vector2 = to_window * button.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await _settle()


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.begins_with(label):
			return child
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _fail(why: String) -> void:
	_failures += 1
	print("FAIL: %s" % why)


func _finish() -> void:
	if _failures > 0:
		push_error("CLICK_TEST_FAILED")
		print("CLICK_TEST_FAILED: %d" % _failures)
		get_tree().quit(1)
		return
	print("CLICK_TEST_OK")
	get_tree().quit(0)
