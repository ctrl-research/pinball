extends Control
## Title screen. Also the only place a run's seed can be set, which is what
## makes a run reproducible when something goes wrong in it.

const GOLD := Color(1.0, 0.82, 0.32)
const INK := Color(0.86, 0.88, 0.96)
const DIM := Color(0.48, 0.50, 0.64)

var _seed_field: LineEdit
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

	_text("TILT", Vector2(0, 62), 56, GOLD)
	_text("a pinball roguelike", Vector2(0, 128), 14, INK)
	_text("Beat the score with the balls you are given.\n"
		+ "Bolt something onto the machine. Do it again, harder.",
		Vector2(0, 156), 10, DIM)

	var play := Button.new()
	play.text = "PLAY"
	play.position = Vector2(270, 214)
	play.size = Vector2(100, 28)
	play.add_theme_font_size_override("font_size", 14)
	play.pressed.connect(_play)
	add_child(play)

	_text("seed (optional)", Vector2(0, 258), 8, DIM)
	_seed_field = LineEdit.new()
	_seed_field.position = Vector2(270, 272)
	_seed_field.size = Vector2(100, 20)
	_seed_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_field.add_theme_font_size_override("font_size", 10)
	add_child(_seed_field)

	_text("A / D or arrows flip   SPACE plunges   Q / W / E nudge",
		Vector2(0, 316), 9, DIM)
	_text("Nudge too often and the machine tilts.", Vector2(0, 332), 9, DIM)

	play.grab_focus()


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
	Run.new_run(_seed_field.text.hash() if _seed_field.text.strip_edges() != "" else 0)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## Full-width centred text at a given y.
func _text(content: String, pos: Vector2, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = content
	l.position = Vector2(0, pos.y)
	l.size = Vector2(640, float(size) * 3.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
