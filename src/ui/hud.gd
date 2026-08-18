class_name Hud
extends CanvasLayer
## The two side panels, the backbox readout, and every between-stage screen.
##
## The split follows what the player is asking at the time. On the left is what
## they *have* -- the trinkets and the MULT those trinkets are feeding, which is the
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
signal sold(kind: String, index: int)

const SLOT_H := 26.0
const CONSUMABLE_H := 20.0
const SLOT_GAP := 3.0

const INK := Color(0.86, 0.88, 0.96)
const DIM := Color(0.46, 0.48, 0.62)
const GOLD := Color(1.0, 0.82, 0.32)
const RED := Color(0.94, 0.36, 0.40)
const PANEL_BG := Color(0.055, 0.052, 0.082)
const PANEL_EDGE := Color(0.15, 0.15, 0.22)
const EMPTY_SLOT := Color(0.10, 0.10, 0.16)
const FULL_SLOT := Color(0.16, 0.14, 0.23)
const CONSUMABLE_SLOT := Color(0.12, 0.18, 0.20)

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
var _status: Label
var _toast_label: Label
var _progress: ColorRect
var _slots: Array[Control] = []
var _consumable_slots: Array[Control] = []
var _active_labels: Array[Label] = []

var _overlay: Control
var _overlay_title: Label
var _overlay_body: VBoxContainer
var _toast_t := 0.0


func _ready() -> void:
	layer = 1
	_build()
	for s in [Run.score_changed, Run.mult_changed, Run.trinkets_changed,
			Run.consumables_changed, Run.tokens_changed, Run.stage_changed,
			Run.nudges_changed]:
		s.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast_label.text = ""
	# Nudge recharges continuously and effects count down, so neither readout
	# can be signal-driven.
	_nudge.text = "NUDGE  %s" % _pips(int(Run.nudges), Run.MAX_NUDGES)

	var row := 0
	for id in Run.effects:
		if row >= _active_labels.size():
			break
		_active_labels[row].text = "%s  %ds" % [
			str(Catalog.CONSUMABLES[id]["name"]).to_upper(),
			int(ceil(Run.effect_remaining(id)))]
		row += 1
	for i in range(row, _active_labels.size()):
		_active_labels[i].text = ""


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

	_label("TRINKETS", Vector2(x, p.position.y + 6.0), w, 8, DIM)
	var y := p.position.y + 18.0
	for i in Run.MAX_TRINKETS:
		_slots.append(_slot(Vector2(x, y), w, SLOT_H))
		y += SLOT_H + SLOT_GAP

	y += 6.0
	_label("CONSUMABLES", Vector2(x, y), w, 8, DIM)
	y += 12.0
	for i in Run.MAX_CONSUMABLES:
		_consumable_slots.append(_slot(Vector2(x, y), w, CONSUMABLE_H))
		y += CONSUMABLE_H + SLOT_GAP

	y += 6.0
	_label("ACTIVE", Vector2(x, y), w, 8, DIM)
	y += 10.0
	for i in Run.MAX_CONSUMABLES:
		_active_labels.append(_label("", Vector2(x, y), w, 8, Color(0.55, 0.90, 0.95)))
		y += 10.0

	y += 6.0
	_label("MULTIPLIER", Vector2(x, y), w, 8, DIM)
	_mult = _label("x1", Vector2(x, y + 10.0), w, 20, GOLD)
	_toast_label = _label("", Vector2(x, y + 36.0), w, 9, GOLD, true)


## One inventory cell: a tinted box with a wrapped label inside it.
func _slot(pos: Vector2, w: float, h: float) -> ColorRect:
	var slot := ColorRect.new()
	slot.position = pos
	slot.size = Vector2(w, h)
	slot.color = EMPTY_SLOT
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(slot)

	# autowrap before size, for the reason spelled out on _label().
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(w - 8.0, 0.0)
	text.position = Vector2(4, 2)
	text.size = Vector2(w - 8.0, h - 4.0)
	text.add_theme_font_size_override("font_size", 7)
	text.clip_text = true
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(text)
	return slot


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

	_status = _label("", Vector2(x, p.position.y + 94.0), w, 9, GOLD)
	_balls = _label("", Vector2(x, p.position.y + 108.0), w, 10, INK)
	_nudge = _label("", Vector2(x, p.position.y + 126.0), w, 10, INK)
	_tokens = _label("", Vector2(x, p.position.y + 146.0), w, 14, GOLD)

	_label("A / D  flippers\nSPACE  hold to plunge\nQ / W / E  nudge\n1 / 2 / 3  consumables\n\n"
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

	# Once the target is met the stage is safe but not over, and the player has
	# no way to know that from a score readout alone.
	if Run.target_met:
		var mult := Run.payout_multiplier()
		_status.text = "TARGET MET" if mult <= 1 else "TARGET MET   PAYOUT x%d" % mult
	else:
		_status.text = ""

	_mult.text = "x%s" % _trim(Run.effective_mult())
	_balls.text = "BALLS  %s" % _pips(Run.balls_left, Run.balls_for_stage())
	_tokens.text = "$%d" % Run.tokens

	for i in _slots.size():
		var text := _slots[i].get_child(0) as Label
		if i < Run.trinkets.size():
			var def: Dictionary = Catalog.TRINKETS[Run.trinkets[i]]
			text.text = "%s\n%s" % [str(def["name"]).to_upper(), str(def["desc"])]
			text.add_theme_color_override("font_color", GOLD)
			_slots[i].color = FULL_SLOT
		else:
			text.text = ""
			_slots[i].color = EMPTY_SLOT

	for i in _consumable_slots.size():
		var text := _consumable_slots[i].get_child(0) as Label
		# The number is the keybind. A slot that does not say which key fires it
		# is a mechanic the player has to be told about out of band.
		if Run.consumables[i] != "":
			var def: Dictionary = Catalog.CONSUMABLES[Run.consumables[i]]
			text.text = "%d  %s" % [i + 1, str(def["name"]).to_upper()]
			text.add_theme_color_override("font_color", Color(0.55, 0.90, 0.95))
			_consumable_slots[i].color = CONSUMABLE_SLOT
		else:
			text.text = "%d  --" % (i + 1)
			text.add_theme_color_override("font_color", DIM)
			_consumable_slots[i].color = EMPTY_SLOT


func toast(text: String) -> void:
	_toast_label.text = text
	_toast_t = 2.0


# --- Screens ------------------------------------------------------------------


func show_play() -> void:
	_overlay.visible = false
	_refresh()


func show_intro() -> void:
	_refresh()
	_status.text = ""
	var boss_line := ""
	if Run.boss_id != "":
		var boss := _boss_def(Run.boss_id)
		boss_line = "%s  -  %s" % [str(boss["name"]), str(boss["desc"])]
	_open(Catalog.BLIND_NAME[Run.blind].to_upper(), [
		"Score %s to clear it." % _commas(Run.target),
		"%d balls -- all of them, target met or not." % Run.balls_for_stage(),
		boss_line,
	])

	_overlay_body.add_child(_body_line("", INK))
	_overlay_body.add_child(_body_line("SPACE to start", INK))


func _head_centred(text: String) -> Label:
	var l := _head(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func show_cleared(payout: Array) -> void:
	var lines: Array = ["Scored %s against %s" % [_commas(Run.score), _commas(Run.target)], ""]
	for item in payout:
		lines.append("%s   +$%d" % [str(item["label"]), int(item["amount"])])
	lines.append("")
	lines.append("SPACE for the shop")
	_open("VICTORY", lines)


## Two columns: what is for sale, and what you already own with a price on it.
##
## The inventory being *in* the shop is the point. Selling is only a real
## decision if you can see the thing you would be giving up next to the thing
## you would be buying with it -- a sell button somewhere else is just a refund.
func show_shop(offers: Array) -> void:
	_refresh()
	_open("SHOP     $%d" % Run.tokens, [])

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_overlay_body.add_child(columns)

	var buy_col := VBoxContainer.new()
	buy_col.custom_minimum_size = Vector2(300.0, 0.0)
	buy_col.add_theme_constant_override("separation", 3)
	columns.add_child(buy_col)
	buy_col.add_child(_head("FOR SALE"))
	if offers.is_empty():
		buy_col.add_child(_body_line("Sold out.", DIM))
	for i in offers.size():
		buy_col.add_child(_offer_row(offers[i], i, 292.0))

	var own_col := VBoxContainer.new()
	own_col.custom_minimum_size = Vector2(200.0, 0.0)
	own_col.add_theme_constant_override("separation", 3)
	columns.add_child(own_col)

	own_col.add_child(_head("TRINKETS  %d/%d" % [Run.trinkets.size(), Run.MAX_TRINKETS]))
	if Run.trinkets.is_empty():
		own_col.add_child(_body_line("none", DIM))
	for i in Run.trinkets.size():
		own_col.add_child(_sell_button("trinket", Run.trinkets[i], i))

	own_col.add_child(_head("CONSUMABLES  %d/%d"
		% [Run.consumable_count(), Run.MAX_CONSUMABLES]))
	if Run.consumable_count() == 0:
		own_col.add_child(_body_line("none", DIM))
	for i in Run.consumables.size():
		# Index, not position: slot 2 sells slot 2 even if slot 1 is a hole.
		if Run.consumables[i] != "":
			own_col.add_child(_sell_button("consumable", Run.consumables[i], i))

	_overlay_body.add_child(_body_line("Click to buy or sell.  SPACE to move on.", DIM))


func _head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", DIM)
	return l


## An offer row: a button carrying the name and price, with the description
## wrapped underneath it.
##
## Not one button with everything in it -- a Button grows to fit its text and
## will not wrap, so the longest description would widen its column and push the
## whole two-column layout off the side of the screen.
func _offer_row(offer: Dictionary, index: int, width: float) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.custom_minimum_size = Vector2(width, 0.0)

	var cost := int(offer["cost"])
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 10)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(width, 0.0)
	b.text = "%s   $%d" % [str(offer["name"]), cost]
	# Two different reasons a button can be dead, and the player should not have
	# to work out which one applies.
	if not Run.can_take(offer):
		b.disabled = true
		b.text += "   (no room)"
	elif Run.tokens < cost:
		b.disabled = true
		b.text += "   (too dear)"
	else:
		b.pressed.connect(bought.emit.bind(index))
	row.add_child(b)

	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(width, 0.0)
	desc.text = str(offer["desc"])
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", DIM)
	row.add_child(desc)
	return row


func _sell_button(kind: String, id: String, index: int) -> Button:
	var def: Dictionary = Catalog.TRINKETS[id] if kind == "trinket" else Catalog.CONSUMABLES[id]
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 9)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(196.0, 0.0)
	b.text = "%s   sell $%d" % [str(def["name"]), Catalog.sell_price(kind, id)]
	b.tooltip_text = str(def["desc"])
	b.pressed.connect(sold.emit.bind(kind, index))
	return b


func show_lost() -> void:
	_open("DEFEAT", [
		"Ante %d, %s" % [Run.ante, Catalog.BLIND_NAME[Run.blind]],
		"Scored %s, needed %s" % [_commas(Run.score), _commas(Run.target)],
		"Short by %s." % _commas(Run.target - Run.score),
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
