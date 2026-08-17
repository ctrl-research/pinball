class_name Hud
extends CanvasLayer
## The right-hand panel and every between-stage screen.
##
## All controls are built in code so the scene file stays trivial and the
## layout is one readable block of numbers rather than a tree you have to open
## an editor to inspect.

signal confirmed
signal bought(index: int)

const PANEL_X := 304.0
const PANEL_W := 336.0
const SLOT_W := 60.0
const SLOT_H := 44.0

const INK := Color(0.86, 0.88, 0.96)
const DIM := Color(0.48, 0.50, 0.64)
const GOLD := Color(1.0, 0.82, 0.32)
const RED := Color(0.94, 0.36, 0.40)
const PANEL_BG := Color(0.063, 0.059, 0.090)

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
var _hint: Label
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

	var bg := ColorRect.new()
	bg.position = Vector2(PANEL_X - 8.0, 0.0)
	bg.size = Vector2(PANEL_W + 8.0, 360.0)
	bg.color = PANEL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_ante = _label("", Vector2(PANEL_X, 10), 14, GOLD)
	_blind = _label("", Vector2(PANEL_X, 28), 10, INK)
	_boss = _label("", Vector2(PANEL_X, 42), 8, RED)

	for i in Run.MAX_RELICS:
		var slot := ColorRect.new()
		slot.position = Vector2(PANEL_X + 4.0 + float(i) * (SLOT_W + 4.0), 58.0)
		slot.size = Vector2(SLOT_W, SLOT_H)
		slot.color = Color(0.11, 0.11, 0.17)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(slot)

		var text := Label.new()
		text.position = Vector2(3, 2)
		text.size = Vector2(SLOT_W - 6.0, SLOT_H - 4.0)
		text.add_theme_font_size_override("font_size", 7)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(text)
		_slots.append(slot)

	_label("SCORE", Vector2(PANEL_X, 122), 8, DIM)
	_score = _label("0", Vector2(PANEL_X, 134), 26, INK)
	_target = _label("", Vector2(PANEL_X, 168), 10, DIM)
	_mult = _label("", Vector2(PANEL_X, 192), 18, GOLD)

	_balls = _label("", Vector2(PANEL_X, 232), 10, INK)
	_nudge = _label("", Vector2(PANEL_X, 250), 10, INK)
	_tokens = _label("", Vector2(PANEL_X, 268), 10, GOLD)

	_toast_label = _label("", Vector2(PANEL_X, 296), 11, GOLD)
	_hint = _label("A / D flip   SPACE plunge   Q / W / E nudge",
		Vector2(PANEL_X, 336), 7, DIM)
	_hint.size.x = PANEL_W - 8.0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_overlay()


func _label(text: String, pos: Vector2, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(PANEL_W - 8.0, float(size) + 6.0)
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
	# Nearly opaque: at 0.86 the panel's own SCORE and MULT readouts bled
	# through the overlay text and sat behind it as ghost numbers.
	dim.color = Color(0.02, 0.02, 0.04, 0.97)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.position = Vector2(60, 54)
	box.size = Vector2(520, 250)
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
	_target.text = "TARGET  %s" % _commas(Run.target)
	_score.add_theme_color_override("font_color", GOLD if Run.stage_won() else INK)
	_mult.text = "MULT  x%s" % _trim(Run.effective_mult())
	_balls.text = "BALLS  %s" % _pips(Run.balls_left, Run.balls_for_stage())
	_tokens.text = "$%d" % Run.tokens

	for i in _slots.size():
		var text := _slots[i].get_child(0) as Label
		if i < Run.relics.size():
			var def: Dictionary = Catalog.RELICS[Run.relics[i]]
			text.text = str(def["name"]).to_upper()
			text.add_theme_color_override("font_color", GOLD)
			_slots[i].color = Color(0.17, 0.15, 0.24)
			_slots[i].tooltip_text = str(def["desc"])
		else:
			text.text = ""
			_slots[i].color = Color(0.11, 0.11, 0.17)


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
