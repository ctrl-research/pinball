extends Node
## Gamepad bindings (autoload "Controls").
##
## Added in code rather than typed into `project.godot`, because an input event
## in that file is a serialised `Object(InputEventJoypadButton, ...)` blob with
## a dozen fields, and a table of them is neither readable nor reviewable. Here
## the whole mapping is eleven lines you can check against a controller in your
## hand. The keyboard bindings stay in the project file, where the editor's
## Input Map panel can show them.
##
## Nothing is removed and nothing is rebound: these are added alongside the
## keys, so both work at once.

## Godot's `ui_*` defaults already put A on `ui_accept` and the d-pad on the
## directions. That is not a conflict to design around, it is the thing that
## makes menus work on a pad for free -- so the bindings below are chosen to
## agree with it rather than to fight it:
##
##   A         plunge, and "yes" in every menu. The same button means the same
##             thing in both places.
##   d-pad     nudge while the ball is live, navigate while it is not. The table
##             only reads nudge when it is `active`, which no overlay is.
##
## B is `ui_cancel` as well as consumable 3. Nothing in this game handles
## cancel, so the overlap costs nothing today; if a menu ever grows a back
## button, consumable 3 is what moves.
const JOYPAD := {
	"flip_left": JOY_BUTTON_LEFT_SHOULDER,
	"flip_right": JOY_BUTTON_RIGHT_SHOULDER,
	"plunge": JOY_BUTTON_A,
	"nudge_left": JOY_BUTTON_DPAD_LEFT,
	"nudge_right": JOY_BUTTON_DPAD_RIGHT,
	"nudge_up": JOY_BUTTON_DPAD_UP,
	"use_consumable_1": JOY_BUTTON_X,
	"use_consumable_2": JOY_BUTTON_Y,
	"use_consumable_3": JOY_BUTTON_B,
	"toggle_crt": JOY_BUTTON_BACK,
}


func _ready() -> void:
	for action in JOYPAD:
		bind(str(action), int(JOYPAD[action]))


## Idempotent: adding the same event twice would make one press register twice,
## and this runs again in any test that reloads the autoload.
func bind(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		push_warning("Controls: no action %s to bind a pad button to" % action)
		return
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton \
				and (existing as InputEventJoypadButton).button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button as JoyButton
	InputMap.action_add_event(action, event)
