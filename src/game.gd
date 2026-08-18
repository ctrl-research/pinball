class_name Game
extends Node2D
## The run, as a state machine. Owns the table and the HUD and decides what
## happens between balls; the table decides nothing and `Run` remembers
## everything.

enum State { INTRO, PLAYING, CLEARED, SHOP, LOST, WON }

var state := State.INTRO
var shop_offers: Array = []
var table: Table
var hud: Hud
var cabinet: Cabinet


func _ready() -> void:
	cabinet = Cabinet.new()
	add_child(cabinet)

	# The table lives inside the cabinet's render target at its own origin, not
	# at a screen position: where it ends up on screen is entirely the
	# perspective shader's business now. `home_position` stays zero so a nudge
	# still shakes the playfield within the machine rather than shaking the
	# machine itself, which is the right way round -- you are hitting the table,
	# not the cabinet.
	table = Table.new()
	table.home_position = Vector2.ZERO
	cabinet.mount(table)
	table.drained.connect(_on_drained)

	hud = Hud.new()
	add_child(hud)
	hud.confirmed.connect(_on_confirmed)
	hud.bought.connect(_on_bought)

	Run.toast.connect(hud.toast)
	_enter_intro()


func _process(_delta: float) -> void:
	if state != State.PLAYING:
		return
	# Checked live rather than at the drain: crossing the target mid-ball is
	# the moment of victory, and making the player wait for the ball to die
	# before telling them so would throw away the best beat in the stage.
	if Run.stage_won():
		_enter_cleared()


# --- States -------------------------------------------------------------------


func _enter_intro() -> void:
	state = State.INTRO
	table.active = false
	table.build()
	table.set_fog(Run.boss_active("fog"))
	hud.show_intro()


func _start_stage() -> void:
	state = State.PLAYING
	table.serve_ball()
	table.active = true
	hud.show_play()


func _enter_cleared() -> void:
	state = State.CLEARED
	table.active = false
	Sfx.play("win")
	var payout := Run.stage_payout()
	Run.collect_payout()
	hud.show_cleared(payout)


func _enter_shop() -> void:
	state = State.SHOP
	shop_offers = Run.roll_shop()
	hud.show_shop(shop_offers)


func _enter_lost() -> void:
	state = State.LOST
	table.active = false
	Sfx.play("lose")
	hud.show_lost()


func _enter_won() -> void:
	state = State.WON
	table.active = false
	Sfx.play("win")
	hud.show_won()


# --- Events -------------------------------------------------------------------


func _on_drained(via_outlane: bool) -> void:
	if state != State.PLAYING:
		return
	table.active = false
	if Run.consume_ball(via_outlane):
		_start_stage()  # a relic put the ball back
		return
	if Run.stage_won():
		_enter_cleared()
	elif Run.balls_left <= 0:
		_enter_lost()
	else:
		_start_stage()


func _on_confirmed() -> void:
	match state:
		State.INTRO:
			_start_stage()
		State.CLEARED:
			_enter_shop()
		State.SHOP:
			Run.advance_blind()
			if Run.run_complete():
				_enter_won()
			else:
				Run.begin_stage()
				_enter_intro()
		State.LOST, State.WON:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_bought(index: int) -> void:
	if state != State.SHOP or index < 0 or index >= shop_offers.size():
		return
	var offer: Dictionary = shop_offers[index]
	if Run.buy(offer):
		Sfx.play("buy")
		shop_offers.remove_at(index)
		hud.show_shop(shop_offers)
