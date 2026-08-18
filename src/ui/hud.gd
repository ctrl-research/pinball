class_name Hud
extends CanvasLayer
## The two side panels, the backbox readout, and every between-stage screen.
##
## The split follows what the player is asking at the time. On the left is what
## they *have* -- the relics and the MULT those relics are feeding, which is the
## build and changes slowly. On the right is where they *are* -- score against
## target, balls, nudges, money, which changes every second the ball is alive.
## Mixing the two into one column was the old layout's real problem: a number
## that moves constantly sitting next to one that almost never does trains you
## to stop reading either.
##
## All controls are built in code so the scene file stays trivial, and the
## geometry comes from `Cabinet` so the panels cannot drift away from the
## machine they are bracketing.

signal confirmed
signal bought(index: int)

const SLOT_H := 38.0
const SLOT_GAP := 4.0

const INK := Color(0.86, 0.88, 0.96)
const DIM := Color(0.46, 0.48, 0.62)
const GOLD := Color(1.0, 0.82, 0.32)
const RED := Color(0.94, 0.36, 0.40)
const PANEL_BG := Color(0.055, 0.052, 0.082)
const PANEL_EDGE := Color(0.15, 0.15, 0.22)

var _root: Control
var _ante: Label
var _blind: Label
var _boss: Label
var _score: Label
var _target: Label
var _mult: Label
var _balls: Label
var _nudge: Label
var _tokens: Label
var _toast_label: Label
var _progress: ColorRect
var _slots: Array[Control] = []

var _overlay: Control
var _overlay_title: Label
var _overlay_body: VBoxContainer
var _toast_t := 0.0


func _ready() -> void:
	layer = 1
	_build()
	for s in [Run.score_changed, Run.mult_changed, Run.relics_changed,
			Run.tokens_changed, Run.stage_changed, Run.nudges_changed]:
		s.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast_label.text = ""
	# Nudge recharges continuously, so its readout cannot be signal-driven.
	_nudge.text = "NUDGE  %s" % _pips(int(Run.nudges), Run.MAX_NUDGES)


func _input(event: InputEvent) -> void:
	# Guarded on InputEventKey because is_echo() does not exist on mouse events,
	# and the overlay's buttons generate plenty of those.
	if not _overlay.visible or not (event is InputEventKey):
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ui_accept") or event.is_action("plunge"):
		confirmed.emit()
		# Null while the tree is being torn down, which an event injected on the
		# same frame as a scene change or a quit can land in.
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


# --- Construction -------------------------------------------------------------


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel_backing(Cabinet.PANEL_LEFT)
	_panel_backing(Cabinet.PANEL_RIGHT)
	_build_backbox()
	_build_left()
	_build_right()
	_build_overlay()


func _panel_backing(rect: Rect2) -> void:
	var edge := ColorRect.new()
	edge.position = rect.position - Vector2.ONE
	edge.size = rect.size + Vector2.ONE * 2.0
	edge.color = PANEL_EDGE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)

	var bg := ColorRect.new()
	bg.position = rect.position
	bg.size = rect.size
	bg.color = PANEL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)


## The head of the machine. Ante and blind live here rather than in a panel
## because on a real cabinet this is exactly what the backbox is for, and it
## puts the one thing that frames the whole stage above the playfield where the
## player is already looking.
func _build_backbox() -> void:
	var box := Cabinet.BACKBOX
	_ante = _label("", Vector2(box.position.x, box.position.y + 6.0), box.size.x, 13, GOLD)
	_ante.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blind = _label("", Vector2(box.position.x, box.position.y + 24.0), box.size.x, 10, INK)
	_blind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss = _label("", Vector2(box.position.x + 4.0, box.position.y + 40.0),
		box.size.x - 8.0, 7, RED, true)
	_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_left() -> void:
	var p := Cabinet.PANEL_LEFT
	var x := p.position.x + 4.0
	var w := p.size.x - 8.0

	_label("POWER-UPS", Vector2(x, p.position.y + 6.0), w, 8, DIM)

	for i in Run.MAX_RELICS:
		var slot := ColorRect.new()
		slot.position = Vector2(x, p.position.y + 20.0 + float(i) * (SLOT_H + SLOT_GAP))
		slot.size = Vector2(w, SLOT_H)
		slot.color = Color(0.10, 0.10, 0.16)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(slot)

		# autowrap before size, for the reason spelled out on _label().
		var text := Label.new()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(w - 8.0, 0.0)
		text.position = Vector2(4, 2)
		text.size = Vector2(w - 8.0, SLOT_H - 4.0)
		text.add_theme_font_size_override("font_size", 7)
		text.clip_text = true
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(text)
		_slots.append(slot)

	var mult_y := p.position.y + 20.0 + float(Run.MAX_RELICS) * (SLOT_H + SLOT_GAP) + 10.0
	_label("MULTIPLIER", Vector2(x, mult_y), w, 8, DIM)
	_mult = _label("x1", Vector2(x, mult_y + 12.0), w, 26, GOLD)

	_toast_label = _label("", Vector2(x, mult_y + 48.0), w, 10, GOLD, true)


func _build_right() -> void:
	var p := Cabinet.PANEL_RIGHT
	var x := p.position.x + 4.0
	var w := p.size.x - 8.0

	_label("SCORE", Vector2(x, p.position.y + 6.0), w, 8, DIM)
	_score = _label("0", Vector2(x, p.position.y + 16.0), w, 24, INK)

	_label("TARGET", Vector2(x, p.position.y + 52.0), w, 8, DIM)
	_target = _label("0", Vector2(x, p.position.y + 62.0), w, 14, INK)

	# A bar as well as the numbers. "12,480 of 20,000" is arithmetic the player
	# has to do mid-ball; a bar is the same fact at a glance.
	var track := ColorRect.new()
	track.position = Vector2(x, p.position.y + 84.0)
	track.size = Vector2(w, 6.0)
	track.color = Color(0.14, 0.14, 0.21)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(track)

	_progress = ColorRect.new()
	_progress.position = Vector2.ZERO
	_progress.size = Vector2(0.0, 6.0)
	_progress.color = GOLD
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_progress)

	_balls = _label("", Vector2(x, p.position.y + 104.0), w, 10, INK)
	_nudge = _label("", Vector2(x, p.position.y + 122.0), w, 10, INK)
	_tokens = _label("", Vector2(x, p.position.y + 142.0), w, 14, GOLD)

	_label("A / D  flippers\nSPACE  hold to plunge\nQ / W / E  nudge\n\n"
		+ "Nudge on empty and it tilts.",
		Vector2(x, p.position.y + 274.0), w, 7, DIM, true)


## `wrap` is applied before the size is set, and that order matters: a Label
## grows to its own minimum size, and an unwrapped Label's minimum width is the
## full width of its text. Setting autowrap afterwards is too late -- the Label
## has already claimed the space, and a long line runs off the screen.
func _label(text: String, pos: Vector2, width: float, size: int, colour: Color,
		wrap: bool = false) -> Label:
	var l := Label.new()
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0.0)
	l.text = text
	l.position = pos
	l.size = Vector2(width, float(size) * 4.0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Nearly opaque: at 0.86 the panel readouts bled through the overlay text
	# and sat behind it as ghost numbers.
	dim.color = Color(0.02, 0.02, 0.04, 0.97)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.position = Vector2(60, 50)
	box.size = Vector2(520, 260)
	box.add_theme_constant_override("separation", 8)
	_overlay.add_child(box)

	_overlay_title = Label.new()
	_overlay_title.add_theme_font_size_override("font_size", 22)
	_overlay_title.add_theme_color_override("font_color", GOLD)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_title)

	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 6)
	box.add_child(_overlay_body)


# --- Panel refresh ------------------------------------------------------------


func _refresh() -> void:
	_ante.text = "ANTE %d / %d" % [Run.ante, Catalog.ANTE_BASE.size()]
	_blind.text = Catalog.BLIND_NAME[Run.blind].to_upper()
	if Run.boss_id != "":
		var boss := _boss_def(Run.boss_id)
		_boss.text = "%s - %s" % [str(boss["name"]).to_upper(), str(boss["desc"])]
	else:
		_boss.text = ""

	_score.text = _commas(Run.score)
	_score.add_theme_color_override("font_color", GOLD if Run.stage_won() else INK)
	_target.text = _commas(Run.target)
	var frac := 0.0 if Run.target <= 0 else clampf(float(Run.score) / float(Run.target), 0.0, 1.0)
	_progress.size.x = (Cabinet.PANEL_RIGHT.size.x - 8.0) * frac

	_mult.text = "x%s" % _trim(Run.effective_mult())
	_balls.text = "BALLS  %s" % _pips(Run.balls_left, Run.balls_for_stage())
	_tokens.text = "$%d" % Run.tokens

	for i in _slots.size():
		var text := _slots[i].get_child(0) as Label
		if i < Run.relics.size():
			var def: Dictionary = Catalog.RELICS[Run.relics[i]]
			text.text = "%s\n%s" % [str(def["name"]).to_upper(), str(def["desc"])]
			text.add_theme_color_override("font_color", GOLD)
			_slots[i].color = Color(0.16, 0.14, 0.23)
		else:
			text.text = ""
			_slots[i].color = Color(0.10, 0.10, 0.16)


func toast(text: String) -> void:
	_toast_label.text = text
	_toast_t = 2.0


# --- Screens ------------------------------------------------------------------


func show_play() -> void:
	_overlay.visible = false
	_refresh()


func show_intro() -> void:
	_refresh()
	var boss_line := ""
	if Run.boss_id != "":
		var boss := _boss_def(Run.boss_id)
		boss_line = "%s  -  %s" % [str(boss["name"]), str(boss["desc"])]
	_open(Catalog.BLIND_NAME[Run.blind].to_upper(), [
		"Score %s to clear it." % _commas(Run.target),
		"%d balls." % Run.balls_for_stage(),
		boss_line,
		"",
		"SPACE to start",
	])


func show_cleared(payout: Array) -> void:
	var lines: Array = ["Scored %s of %s" % [_commas(Run.score), _commas(Run.target)], ""]
	for item in payout:
		lines.append("%s   +$%d" % [str(item["label"]), int(item["amount"])])
	lines.append("")
	lines.append("SPACE for the shop")
	_open("BLIND CLEARED", lines)


func show_shop(offers: Array) -> void:
	_refresh()
	_open("SHOP     $%d" % Run.tokens, [])
	if offers.is_empty():
		_overlay_body.add_child(_body_line("Sold out.", DIM))
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var button := Button.new()
		button.text = "%d.  %s  -  %s   ($%d)" % [
			i + 1, str(offer["name"]), str(offer["desc"]), int(offer["cost"])]
		button.add_theme_font_size_override("font_size", 10)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = Run.tokens < int(offer["cost"])
		button.pressed.connect(bought.emit.bind(i))
		_overlay_body.add_child(button)
	_overlay_body.add_child(_body_line("", INK))
	_overlay_body.add_child(_body_line("Click to buy.  SPACE to move on.", DIM))


func show_lost() -> void:
	_open("GAME OVER", [
		"Ante %d, %s" % [Run.ante, Catalog.BLIND_NAME[Run.blind]],
		"Scored %s of %s" % [_commas(Run.score), _commas(Run.target)],
		"",
		"SPACE for the menu",
	])


func show_won() -> void:
	_open("MACHINE BEATEN", [
		"All 8 antes cleared.",
		"",
		"SPACE for the menu",
	])


func _open(title: String, lines: Array) -> void:
	_overlay_title.text = title
	for child in _overlay_body.get_children():
		_overlay_body.remove_child(child)
		child.queue_free()
	for line in lines:
		_overlay_body.add_child(_body_line(str(line), INK))
	_overlay.visible = true


func _body_line(text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# --- Formatting ---------------------------------------------------------------


func _boss_def(id: String) -> Dictionary:
	for boss in Catalog.BOSSES:
		if str(boss["id"]) == id:
			return boss
	return {"name": "", "desc": ""}


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


static func _trim(v: float) -> String:
	# x4 reads better than x4.0; x4.2 still needs its decimal.
	return str(int(v)) if is_equal_approx(v, float(int(v))) else "%.1f" % v


static func _pips(filled: int, total: int) -> String:
	var s := ""
	for i in maxi(total, filled):
		s += "*" if i < filled else "-"
	return s
