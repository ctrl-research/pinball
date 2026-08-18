class_name Cabinet
extends Node2D
## The physical machine: rails, lockdown bar, backbox, and the perspective
## playfield mounted inside them.
##
## The playfield is rendered flat into a SubViewport and warped onto a
## trapezoid by `perspective.gdshader`. That indirection is the whole design:
## the simulation stays a plain top-down 2D world that has never heard of
## perspective, and only the last step before the screen knows about it. A ball
## can never behave differently because of how it is being drawn.
##
## This file also owns the screen layout for everything else, because the panel
## positions are defined by where the cabinet is and there should be one answer
## to that rather than two that drift.

# --- Screen layout (640x360) --------------------------------------------------

const VIEW := Vector2(640.0, 360.0)
const CENTRE_X := 320.0

## Width of the far edge as a fraction of the near edge. Shared with the
## shader; they must agree or the rails will not line up with the playfield.
##
## Gentle on purpose. A stronger warp looks better in a screenshot and shrinks
## the bumper cluster exactly where a lot of the scoring happens -- so this is
## the number that gives if perspective ever starts costing readability.
const TOP_SCALE := 0.82

const PLAYFIELD_TOP_Y := 72.0
const PLAYFIELD_H := 264.0
const PLAYFIELD_BOTTOM_W := 268.0
const PLAYFIELD_BOTTOM_Y := PLAYFIELD_TOP_Y + PLAYFIELD_H

const RAIL := 8.0
const LOCKDOWN_H := 12.0

const BACKBOX := Rect2(202.0, 6.0, 236.0, 60.0)

## Powerups and multipliers left, score right.
const PANEL_LEFT := Rect2(6.0, 6.0, 166.0, 348.0)
const PANEL_RIGHT := Rect2(468.0, 6.0, 166.0, 348.0)

## The flat playfield is rendered at its own logical size. Taller than
## TableLayout.HEIGHT so the outlane chutes, which overrun the drain line, are
## not clipped off the bottom of the render target.
const RENDER_SIZE := Vector2i(280, 352)

# --- Palette ------------------------------------------------------------------

const BODY := Color(0.125, 0.115, 0.170)
const BODY_EDGE := Color(0.065, 0.060, 0.095)
const RAIL_LIT := Color(0.62, 0.64, 0.78)
const RAIL_DARK := Color(0.30, 0.31, 0.42)
const LOCKDOWN_COL := Color(0.70, 0.19, 0.26)
const LOCKDOWN_LIT := Color(0.88, 0.32, 0.36)
const SHELL := Color(0.085, 0.080, 0.125)
const SHELL_EDGE := Color(0.34, 0.36, 0.50)

var viewport: SubViewport
var _screen: TextureRect


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = RENDER_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	add_child(viewport)

	var quad := playfield_bounds()
	_screen = TextureRect.new()
	_screen.position = quad.position
	_screen.size = quad.size
	_screen.texture = viewport.get_texture()
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Linear, against the project default of nearest. Once the image is being
	# warped its pixels no longer line up with the screen grid, so nearest buys
	# no crispness here and costs a shimmer on every moving edge.
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/ui/perspective.gdshader")
	mat.set_shader_parameter("top_scale", TOP_SCALE)
	_screen.material = mat
	add_child(_screen)  # after _draw, so the playfield sits over the body


## Put the table inside the render target.
func mount(table: Node) -> void:
	viewport.add_child(table)


## The axis-aligned box the warped playfield is drawn into. The shader discards
## the corners outside the trapezoid.
static func playfield_bounds() -> Rect2:
	return Rect2(
		CENTRE_X - PLAYFIELD_BOTTOM_W * 0.5, PLAYFIELD_TOP_Y,
		PLAYFIELD_BOTTOM_W, PLAYFIELD_H)


## Half-width of the playfield at a given screen y, following the same straight
## edges the shader uses.
static func half_width_at(y: float) -> float:
	var t := clampf((y - PLAYFIELD_TOP_Y) / PLAYFIELD_H, 0.0, 1.0)
	return PLAYFIELD_BOTTOM_W * 0.5 * lerpf(TOP_SCALE, 1.0, t)


## The cabinet's outer shell, rails included. Its sides converge with the
## playfield, because a cabinet whose rails stayed parallel while the playfield
## receded would read as a bug rather than as a machine.
static func body_quad(outset: float = 0.0) -> PackedVector2Array:
	var top := half_width_at(PLAYFIELD_TOP_Y) + (RAIL + outset) * TOP_SCALE
	var bottom := half_width_at(PLAYFIELD_BOTTOM_Y) + RAIL + outset
	return PackedVector2Array([
		Vector2(CENTRE_X - top, PLAYFIELD_TOP_Y - outset),
		Vector2(CENTRE_X + top, PLAYFIELD_TOP_Y - outset),
		Vector2(CENTRE_X + bottom, PLAYFIELD_BOTTOM_Y),
		Vector2(CENTRE_X - bottom, PLAYFIELD_BOTTOM_Y),
	])


func _draw() -> void:
	_draw_backbox()
	_draw_body()
	_draw_lockdown()


func _draw_body() -> void:
	draw_colored_polygon(body_quad(2.0), BODY_EDGE)
	draw_colored_polygon(body_quad(), BODY)

	# Rails are drawn as the strip between the body edge and the playfield, lit
	# along their inner lip so the playfield reads as sunk into the machine.
	var outer := body_quad()
	var inner := PackedVector2Array([
		Vector2(CENTRE_X - half_width_at(PLAYFIELD_TOP_Y), PLAYFIELD_TOP_Y),
		Vector2(CENTRE_X + half_width_at(PLAYFIELD_TOP_Y), PLAYFIELD_TOP_Y),
		Vector2(CENTRE_X + half_width_at(PLAYFIELD_BOTTOM_Y), PLAYFIELD_BOTTOM_Y),
		Vector2(CENTRE_X - half_width_at(PLAYFIELD_BOTTOM_Y), PLAYFIELD_BOTTOM_Y),
	])
	draw_colored_polygon(PackedVector2Array([outer[0], inner[0], inner[3], outer[3]]), RAIL_DARK)
	draw_colored_polygon(PackedVector2Array([outer[1], inner[1], inner[2], outer[2]]), RAIL_DARK)
	draw_line(outer[0], outer[3], RAIL_LIT, 1.5)
	draw_line(outer[1], outer[2], RAIL_LIT, 1.5)
	draw_line(inner[0], inner[3], Color(0.05, 0.05, 0.08), 1.0)
	draw_line(inner[1], inner[2], Color(0.05, 0.05, 0.08), 1.0)


func _draw_lockdown() -> void:
	# The bar the player's hands rest on, at the near edge. It is the one part
	# of the machine that is unambiguously closest to you, so it gets the full
	# width and the brightest edge -- it anchors the whole perspective.
	var half := half_width_at(PLAYFIELD_BOTTOM_Y) + RAIL
	var top := PLAYFIELD_BOTTOM_Y
	draw_rect(Rect2(CENTRE_X - half, top, half * 2.0, LOCKDOWN_H), LOCKDOWN_COL)
	draw_rect(Rect2(CENTRE_X - half, top, half * 2.0, 2.0), LOCKDOWN_LIT)
	draw_rect(Rect2(CENTRE_X - half, top + LOCKDOWN_H - 2.0, half * 2.0, 2.0), BODY_EDGE)


func _draw_backbox() -> void:
	draw_rect(BACKBOX.grow(2.0), BODY_EDGE)
	draw_rect(BACKBOX, SHELL)
	draw_rect(Rect2(BACKBOX.position + Vector2(3, 3), BACKBOX.size - Vector2(6, 6)),
		Color(0.045, 0.042, 0.070))
	draw_rect(BACKBOX.grow(2.0), SHELL_EDGE, false, 1.0)
	# The neck down to the playfield, so the head is attached to something.
	var neck_w := 26.0
	draw_rect(Rect2(CENTRE_X - neck_w * 0.5, BACKBOX.end.y, neck_w,
		PLAYFIELD_TOP_Y - BACKBOX.end.y), BODY_EDGE)
