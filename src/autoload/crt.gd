extends CanvasLayer
## The CRT pass (autoload "Crt").
##
## An autoload rather than a node in each scene: the effect belongs to the
## screen, not to the game, so the menu and the table should sit behind the same
## glass. Putting it in one place also means a scene change cannot lose it.

const TOGGLE_ACTION := "toggle_crt"

var enabled := true:
	set(value):
		enabled = value
		if _screen != null:
			_screen.visible = value

var _screen: ColorRect


func _ready() -> void:
	# Above every other layer. The HUD is layer 1; this has to be in front of
	# all of it or the panels end up outside the tube.
	layer = 100

	_screen = ColorRect.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.color = Color.WHITE  # the shader replaces this wholesale
	# Without this the shop's buttons stop taking clicks, because a full-screen
	# Control in front of them swallows every one.
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/ui/crt.gdshader")
	_screen.material = mat
	add_child(_screen)


func _input(event: InputEvent) -> void:
	# Toggleable because a CRT is a matter of taste and it costs legibility:
	# the panels carry 7pt text, and anyone who finds it harder to read should
	# be able to turn it off without editing the project.
	if event.is_action_pressed(TOGGLE_ACTION):
		enabled = not enabled
		# Null while the tree is being torn down.
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
