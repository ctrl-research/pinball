extends Control
## Title screen. Also the only place a run's seed can be set, which is what
## makes a run reproducible when something goes wrong in it.

const GOLD := Color(1.0, 0.82, 0.32)
const INK := Color(0.86, 0.88, 0.96)
const DIM := Color(0.48, 0.50, 0.64)

var _seed_field: LineEdit
var _type: TextScreen
var _default: Button
## change_scene_to_file is deferred to the end of the frame, so the menu is
## still live and still taking input after PLAY is pressed. Without this guard
## a second press starts a second run, throwing away the first before anyone
## sees it -- which looks exactly like the start button not working.
var _starting := false


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.043, 0.039, 0.063)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# The title's type goes through the same tube the HUD's does, so the menu
	# and the game are made of the same pixels. The background stays outside it:
	# it is a flat full-screen fill, and running a lateral wobble over something
	# with no detail in it only moves its edges off the screen.
	_type = TextScreen.new()
	add_child(_type)

	# Spaced for the scaled type. The title is set a size smaller than it reads
	# because Style.TEXT_SCALE multiplies it too, and at the old 56 it grew into
	# the subtitle beneath it.
	_text("TILT", Vector2(0, 34), 46, GOLD)
	_text("a pinball roguelike", Vector2(0, 112), 14, INK)
	_text("Beat the score with the balls you are given.\n"
		+ "Bolt something onto the machine. Do it again, harder.",
		Vector2(0, 143), 8, DIM)

	# Settings are applied before anything is drawn, so the CRT does not flicker
	# on for a frame before being turned off.
	Save.load_settings()

	var play := Button.new()
	play.text = "PLAY"
	play.position = Vector2(255, 194)
	play.size = Vector2(130, 32)
	play.add_theme_font_size_override("font_size", Style.pt(14))
	play.pressed.connect(_play)
	_type.host().add_child(play)

	# Offered only when there is something to continue, and placed above the seed
	# field because a run in progress makes the seed irrelevant.
	if Save.has_run():
		var resume := Button.new()
		resume.text = "CONTINUE"
		resume.position = Vector2(255, 232)
		resume.size = Vector2(130, 26)
		resume.add_theme_font_size_override("font_size", Style.pt(11))
		resume.pressed.connect(_resume)
		_type.host().add_child(resume)
		_default = resume
		_text("or start a new run above", Vector2(0, 262), 8, DIM)
	else:
		_text("seed (optional)", Vector2(0, 240), 8, DIM)
	_seed_field = LineEdit.new()
	_seed_field.visible = not Save.has_run()
	_seed_field.position = Vector2(255, 256)
	_seed_field.size = Vector2(130, 24)
	_seed_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_field.add_theme_font_size_override("font_size", Style.pt(8))
	# Deliberately not in the text screen. Typing into a field inside a nested
	# viewport means its focus and its caret live in a different input context
	# from the rest of the menu, which is a lot of risk to accept for a wobble
	# on the one control the player types into.
	add_child(_seed_field)

	_text(Hud.keymap_text(Hud.pad_connected()).replace("\n", "    "),
		Vector2(0, 300), 8, DIM)
	_text("Nudge too often and the machine tilts.", Vector2(0, 322), 8, DIM)

	# Whichever is the likely intent takes the focus ring, because that is what
	# the keyboard acts on. With a run in progress that is CONTINUE -- focusing
	# PLAY would mean a stray Return discards the saved run, which is the one
	# outcome here that cannot be undone.
	if _default == null:
		_default = play
	_default.grab_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if _seed_field.has_focus():
		return
	if event.is_action("ui_accept") or event.is_action("plunge"):
		_play()
		get_viewport().set_input_as_handled()


func _play() -> void:
	if _starting:
		return
	_starting = true
	# Starting fresh abandons whatever was saved, and says so by deleting it
	# before the new run can overwrite it with its own first stage.
	Save.clear_run()
	Run.new_run(_seed_field.text.hash() if _seed_field.text.strip_edges() != "" else 0)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## Picks up where the last run left off, at the start of the stage it was on.
func _resume() -> void:
	if _starting:
		return
	if not Save.load_run():
		# The file was there and would not parse. Falling through to a fresh run
		# is better than a dead button.
		_play()
		return
	_starting = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## Full-width centred text at a given y.
func _text(content: String, pos: Vector2, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = content
	l.position = Vector2(0, pos.y)
	l.size = Vector2(640, float(size) * 3.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", Style.pt(size))
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type.host().add_child(l)
	return l
