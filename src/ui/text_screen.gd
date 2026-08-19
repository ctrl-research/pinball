class_name TextScreen
extends SubViewportContainer
## A layer of glass for the UI alone: everything hosted in here is rendered at
## the game's native 640x360, upscaled with nearest-neighbour, and put through
## `text_crt.gdshader`.
##
## The reason this exists is that a screen-space pass cannot wobble text. By the
## time the frame reaches the CRT shader the glyphs are baked into it alongside
## the playfield, so displacing anything displaces everything -- and a frame
## that moves as one rigid piece is invisible, because there is nothing left
## standing still to see it against. Worse, once the amplitude is raised far
## enough to notice, it is the *cabinet* that visibly swims.
##
## Giving the UI its own viewport fixes both halves at once. The wobble is a
## texture lookup into a layer that holds nothing but type, so the machine
## underneath stays nailed down while the readouts ripple -- which is what a
## real cabinet looks like, since the score display is the part that was ever a
## CRT.
##
## Rendering at 640x360 rather than at the window's resolution is the other half
## of the look. Godot's `canvas_items` stretch rasterises fonts at the *scaled*
## size, so a 1280x720 window draws 8pt text as smooth 16px glyphs. Going
## through a native-resolution viewport puts the type back on the pixel grid the
## rest of the game is drawn on.

const RESOLUTION := Vector2i(640, 360)

var _vp: SubViewport
var _mat: ShaderMaterial


func _init() -> void:
	# Built here rather than in _ready() so host() can be called immediately
	# after construction, before the node has entered the tree.
	_vp = SubViewport.new()
	_vp.size = RESOLUTION
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Off, so the viewport keeps its native size and the container simply
	# enlarges the result. With stretch on, the viewport would be resized to the
	# window and the pixels would come back exactly as smooth as before.
	stretch = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/ui/text_crt.gdshader")
	material = _mat


func _ready() -> void:
	# Follows the F1 switch. Only the shader goes: the native-resolution render
	# stays either way, because that is the game's pixel grid rather than an
	# effect laid over it.
	Crt.toggled.connect(_on_crt_toggled)
	_on_crt_toggled(Crt.enabled)


func _on_crt_toggled(on: bool) -> void:
	material = _mat if on else null


## Where UI goes. Children keep their ordinary 640x360 coordinates, because that
## is exactly the viewport's size -- nothing has to be repositioned to move into
## here.
func host() -> SubViewport:
	return _vp
