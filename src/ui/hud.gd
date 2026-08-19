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

## Inventory cells are sized from the type they hold rather than pinned to a
## pixel count, so raising Style.TEXT_SCALE reflows the panel instead of
## overlapping it. Trinket names get one line and clip: at the larger size a
## wrapped second line costs more room than the tail of "Outlane Insurance" is
## worth.
const SLOT_GAP := 3.0
const SLOT_PAD := 5.0


static func slot_h() -> float:
	return float(Style.pt(8)) + SLOT_PAD * 2.0


static func consumable_h() -> float:
	return float(Style.pt(8)) + SLOT_PAD * 2.0


## One line of a given design size, plus leading. What the panel cursor advances
## by.
static func lh(design_size: int, leading: float = 3.0) -> float:
	return float(Style.pt(design_size)) + leading

const INK := Color(0.86, 0.88, 0.96)
const DIM := Color(0.46, 0.48, 0.62)
const GOLD := Color(1.0, 0.82, 0.32)
## Ball-queue pips: radius, and the spacing between their centres.
const PIP_RADIUS := 4.0
const PIP_PITCH := 12.0

const FEVER_COLOUR := Color(1.0, 0.45, 0.55)
const RED := Color(0.94, 0.36, 0.40)
const PANEL_BG := Color(0.055, 0.052, 0.082)
const PANEL_EDGE := Color(0.15, 0.15, 0.22)
const EMPTY_SLOT := Color(0.10, 0.10, 0.16)
const FULL_SLOT := Color(0.16, 0.14, 0.23)
const CONSUMABLE_SLOT := Color(0.12, 0.18, 0.20)

var _root: Control
var _type: TextScreen
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
var _fever: Label
var _fever_head: Label
var _queue: Label
var _queue_pips: Control
var _fever_bar: ColorRect
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
			Run.consumables_changed, Run.balls_changed, Run.tokens_changed,
			Run.stage_changed, Run.nudges_changed]:
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

	var fever := Run.fever
	_fever.text = "x%s" % _trim(fever)
	_fever_head.text = "FEVER  MAX" if fever >= Run.FEVER_MAX else "FEVER  %s" % _pips(
		Run.fever_hits_done(), Run.FEVER_HITS_PER_LEVEL)
	_fever.add_theme_color_override("font_color",
		FEVER_COLOUR if fever > 1.0 else DIM)
	_fever_bar.size.x = (Cabinet.PANEL_RIGHT.size.x - 8.0) * clampf(
		Run.fever_remaining() / Run.FEVER_WINDOW, 0.0, 1.0)

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
	# ui_accept only. The plunger key used to double as "proceed", which meant a
	# tap meant to dismiss a screen also charged the plunger on the frame after.
	if event.is_action("ui_accept"):
		confirmed.emit()
		# Null while the tree is being torn down, which an event injected on the
		# same frame as a scene change or a quit can land in.
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


# --- Construction -------------------------------------------------------------


func _build() -> void:
	# Every panel and every readout is hosted in the text screen rather than on
	# the CanvasLayer directly, so the UI gets its own tube: native-resolution
	# pixels, its own scanlines, and a signal wobble that leaves the machine
	# underneath perfectly still. See `text_screen.gd`.
	_type = TextScreen.new()
	add_child(_type)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type.host().add_child(_root)

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
		box.size.x - 8.0, 8, RED, true)
	_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_left() -> void:
	var p := Cabinet.PANEL_LEFT
	var x := p.position.x + 4.0
	var w := p.size.x - 8.0

	_label("TRINKETS", Vector2(x, p.position.y + 6.0), w, 8, DIM)
	var y := p.position.y + lh(8) + 3.0
	for i in Run.MAX_TRINKETS:
		_slots.append(_slot(Vector2(x, y), w, slot_h()))
		y += slot_h() + SLOT_GAP

	y += 5.0
	_label("CONSUMABLES", Vector2(x, y), w, 8, DIM)
	y += lh(8) + 2.0
	for i in Run.MAX_CONSUMABLES:
		_consumable_slots.append(_slot(Vector2(x, y), w, consumable_h()))
		y += consumable_h() + SLOT_GAP

	y += 5.0
	_label("ACTIVE", Vector2(x, y), w, 8, DIM)
	y += lh(8)
	for i in Run.MAX_CONSUMABLES:
		_active_labels.append(_label("", Vector2(x, y), w, 8, Color(0.55, 0.90, 0.95)))
		y += lh(8, 1.0)

	# Pinned to the bottom of the panel rather than following the cursor: MULT
	# is the number the player looks for without reading, and it should not move
	# because a consumable expired three rows above it.
	var foot := p.position.y + p.size.y
	_toast_label = _label("", Vector2(x, foot - lh(9) - 4.0), w, 9, GOLD, true)
	_mult = _label("x1", Vector2(x, foot - lh(9) - lh(20) - 6.0), w, 20, GOLD)
	_label("MULTIPLIER", Vector2(x, foot - lh(9) - lh(20) - lh(8) - 6.0), w, 8, DIM)


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
	text.add_theme_font_size_override("font_size", Style.pt(8))
	text.clip_text = true
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(text)
	return slot


func _build_right() -> void:
	var p := Cabinet.PANEL_RIGHT
	var x := p.position.x + 4.0
	var w := p.size.x - 8.0
	# Laid out with a running cursor rather than hardcoded offsets. The panel is
	# a fixed 348px tall and the type is now half again as large, so there is no
	# slack left for a row that has quietly drifted onto the one below it.
	var y := p.position.y + 5.0

	_label("SCORE", Vector2(x, y), w, 8, DIM)
	y += lh(8)
	_score = _label("0", Vector2(x, y), w, 20, INK)
	y += lh(20) + 4.0

	_label("TARGET", Vector2(x, y), w, 8, DIM)
	y += lh(8)
	_target = _label("0", Vector2(x, y), w, 14, INK)
	y += lh(14) + 4.0

	# A bar as well as the numbers. "12,480 of 20,000" is arithmetic the player
	# has to do mid-ball; a bar is the same fact at a glance.
	var track := ColorRect.new()
	track.position = Vector2(x, y)
	track.size = Vector2(w, 6.0)
	track.color = Color(0.14, 0.14, 0.21)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(track)
	y += 12.0

	_progress = ColorRect.new()
	_progress.position = Vector2.ZERO
	_progress.size = Vector2(0.0, 6.0)
	_progress.color = GOLD
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_progress)

	_status = _label("", Vector2(x, y), w, 9, GOLD)
	y += lh(9) + 2.0
	_balls = _label("", Vector2(x, y), w, 10, INK)
	y += lh(10)

	# Shown up front, because the balls are drawn from the slot ratio at the
	# start of the stage. A roll you can see is a roll you can plan around; the
	# same roll revealed one ball at a time reads as the machine cheating.
	# Colour first, names second. The pip colours are the ball colours on the
	# playfield, so the head of the queue is the thing the player is looking at.
	_queue_pips = Control.new()
	_queue_pips.position = Vector2(x, y)
	_queue_pips.size = Vector2(w, PIP_RADIUS * 3.0)
	_queue_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_pips.draw.connect(_draw_queue)
	_root.add_child(_queue_pips)
	y += PIP_RADIUS * 3.0

	_queue = _label("", Vector2(x, y), w, 8, DIM, true)
	# Room for the second line the queue wraps onto with a full rack.
	y += lh(8, 1.0) * 2.0

	_nudge = _label("", Vector2(x, y), w, 10, INK)
	y += lh(10) + 3.0
	_tokens = _label("", Vector2(x, y), w, 14, GOLD)
	y += lh(14) + 4.0

	# Fever lives here rather than beside MULT because this panel is the
	# fast-moving one, and fever is the fastest number in the game -- it climbs
	# on every contact and falls off a cliff two seconds later.
	# The header carries the progress pips, the same way BALLS and NUDGE do.
	# With five contacts to a level the number itself now sits still most of the
	# time, and a meter that only moves once every five hits looks broken unless
	# something shows the four hits in between.
	_fever_head = _label("FEVER", Vector2(x, y), w, 8, DIM)
	y += lh(8)
	_fever = _label("x1", Vector2(x, y), w, 18, FEVER_COLOUR)
	y += lh(18) + 2.0

	var fever_track := ColorRect.new()
	fever_track.position = Vector2(x, y)
	fever_track.size = Vector2(w, 4.0)
	fever_track.color = Color(0.14, 0.14, 0.21)
	fever_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(fever_track)
	y += 12.0

	# The bar is the *timer*, not the size of the multiplier: what the player
	# needs to know mid-ball is how long they have left to keep it alive.
	_fever_bar = ColorRect.new()
	_fever_bar.size = Vector2(0.0, 4.0)
	_fever_bar.color = FEVER_COLOUR
	_fever_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fever_track.add_child(_fever_bar)

	# Anchored to the panel floor rather than left on the cursor. It is the last
	# block, so it is the one that silently walks off the bottom of the panel
	# when anything above it grows -- which is exactly what it did at 1.5x.
	# Pinned here, a collision shows up as an overlap instead of as a row that
	# is simply not there.
	#
	# It is also the block that gives up room when type grows: it is read once
	# and then never again. The tilt warning it used to carry is on the title
	# screen, which is where anyone actually reads it.
	var keys := "A / D  flippers\nSPACE  plunge\nQ W E  nudge   1 2 3  items"
	_label(keys, Vector2(x, p.position.y + p.size.y - lh(8) * 3.0 - 4.0), w, 8, DIM, true)


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
	l.add_theme_font_size_override("font_size", Style.pt(size))
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

	# Nearly the whole screen. The overlay is the one place with genuinely
	# variable content -- a shop with a full rack is thirteen inventory rows --
	# and at the larger type there is no margin left to spend on decoration.
	var box := VBoxContainer.new()
	box.position = Vector2(36, 14)
	box.size = Vector2(568, 338)
	box.add_theme_constant_override("separation", 4)
	_overlay.add_child(box)

	_overlay_title = Label.new()
	_overlay_title.add_theme_font_size_override("font_size", Style.pt(17))
	_overlay_title.add_theme_color_override("font_color", GOLD)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_title)

	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 3)
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
	_queue.text = _queue_text()
	_queue_pips.queue_redraw()
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
			# The count is only shown when there is more than one; "x1" on every
			# slot is noise that makes a real stack harder to spot.
			var n: int = Run.consumable_stacks[i]
			text.text = "%d  %s%s" % [
				i + 1, str(def["name"]).to_upper(), "" if n <= 1 else "  x%d" % n]
			text.add_theme_color_override("font_color", Color(0.55, 0.90, 0.95))
			_consumable_slots[i].color = CONSUMABLE_SLOT
		else:
			text.text = "%d  --" % (i + 1)
			text.add_theme_color_override("font_color", DIM)
			_consumable_slots[i].color = EMPTY_SLOT


## The ball in play followed by everything still to come. Before the first
## plunge there is no head, only a queue.
func _queue_ids() -> Array:
	var ids: Array = []
	if Run.ball_in_play():
		ids.append(Run.current_ball)
	ids.append_array(Run.ball_queue)
	return ids


## "GOLD > EMBER, VANILLA". The trailing "BALL" in every name is dropped: in a
## row of balls it is the one word that never distinguishes one from another.
## Vanilla is written out rather than blanked, because an absent name reads as
## missing information where "VANILLA" reads as a plain ball, which is what it is.
func _queue_text() -> String:
	var names: Array[String] = []
	for id in _queue_ids():
		names.append(str(Catalog.BALLS[id]["name"]).to_upper().trim_suffix(" BALL"))
	if names.is_empty():
		return ""
	if not Run.ball_in_play() or names.size() == 1:
		return ", ".join(names)
	return "%s > %s" % [names[0], ", ".join(names.slice(1))]


## One pip per ball, in that ball's own colour. The ball in play is drawn full
## size with a halo; the ones behind it are smaller and dimmed, so the row reads
## as a queue moving left rather than as a set of equals.
func _draw_queue() -> void:
	var ids := _queue_ids()
	var y := 6.0
	for i in ids.size():
		var colour: Color = Catalog.BALL_COLOURS.get(ids[i], INK)
		var centre := Vector2(PIP_RADIUS + float(i) * PIP_PITCH, y)
		var lead := i == 0 and Run.ball_in_play()
		if lead:
			_queue_pips.draw_circle(centre, PIP_RADIUS + 2.0, Color(colour, 0.3))
			_queue_pips.draw_circle(centre, PIP_RADIUS, colour)
		else:
			_queue_pips.draw_circle(centre, PIP_RADIUS - 1.0, colour.darkened(0.4))


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

	_add_continue("START")


func _head_centred(text: String) -> Label:
	var l := _head(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func show_cleared(payout: Array) -> void:
	var lines: Array = ["Scored %s against %s" % [_commas(Run.score), _commas(Run.target)], ""]
	for item in payout:
		lines.append("%s   +$%d" % [str(item["label"]), int(item["amount"])])
	_open("VICTORY", lines)
	_add_continue("TO THE SHOP")


## Two columns: what is for sale, and what you already own with a price on it.
##
## The inventory being *in* the shop is the point. Selling is only a real
## decision if you can see the thing you would be giving up next to the thing
## you would be buying with it -- a sell button somewhere else is just a refund.
func show_shop(offers: Array) -> void:
	_refresh()
	_open("SHOP     $%d" % Run.tokens, [])

	# Three columns rather than two. The inventory is thirteen rows at a full
	# rack -- five trinkets, three consumables, five balls -- and stacked in one
	# column at the current type size that ran the NEXT BLIND button off the
	# bottom of the screen. Splitting the rack in two spends the empty
	# horizontal space instead of the vertical space there is none of.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	_overlay_body.add_child(columns)

	var buy_col := _shop_column(232.0)
	columns.add_child(buy_col)
	buy_col.add_child(_head("FOR SALE"))
	if offers.is_empty():
		buy_col.add_child(_body_line("Sold out.", DIM))
	for i in offers.size():
		buy_col.add_child(_offer_row(offers[i], i, 228.0))

	var held_col := _shop_column(156.0)
	columns.add_child(held_col)
	held_col.add_child(_head("TRINKETS  %d/%d" % [Run.trinkets.size(), Run.MAX_TRINKETS]))
	if Run.trinkets.is_empty():
		held_col.add_child(_body_line("none", DIM))
	for i in Run.trinkets.size():
		held_col.add_child(_sell_button("trinket", Run.trinkets[i], i))

	held_col.add_child(_head("CONSUMABLES  %d/%d"
		% [Run.consumable_count(), Run.MAX_CONSUMABLES]))
	if Run.consumable_count() == 0:
		held_col.add_child(_body_line("none", DIM))
	for i in Run.consumables.size():
		# Index, not position: slot 2 sells slot 2 even if slot 1 is a hole.
		if Run.consumables[i] != "":
			held_col.add_child(_sell_button("consumable", Run.consumables[i], i))

	var ball_col := _shop_column(156.0)
	columns.add_child(ball_col)
	ball_col.add_child(_head("BALLS  %d/%d" % [_owned_balls(), Run.BALL_SLOTS]))
	for i in Run.ball_slots.size():
		ball_col.add_child(_ball_slot_row(i))

	_overlay_body.add_child(_body_line("Click to buy or sell.", DIM))
	_add_continue("NEXT BLIND")


func _shop_column(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0.0)
	col.add_theme_constant_override("separation", 2)
	return col


func _owned_balls() -> int:
	var n := 0
	for id in Run.ball_slots:
		if id != Catalog.VANILLA:
			n += 1
	return n


## A ball slot: sellable if it holds something, and plain text if it is Vanilla,
## since selling an empty slot is not an action.
func _ball_slot_row(index: int) -> Control:
	var id: String = Run.ball_slots[index]
	var def: Dictionary = Catalog.BALLS[id]
	if id == Catalog.VANILLA:
		var l := _body_line("%d.  Vanilla" % (index + 1), DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		return l
	var lvl := Run.ball_level(id)
	var b := Button.new()
	b.add_theme_font_size_override("font_size", Style.pt(8))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(152.0, 0.0)
	var name := str(def["name"])
	if lvl > 1:
		name += " Lv%d" % lvl
	b.text = "%d. %s  sell $%d" % [index + 1, name, Catalog.ball_sell_price(id, lvl)]
	b.tooltip_text = str(def["desc"])
	b.pressed.connect(sold.emit.bind("ball", index))
	return b


func _head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Style.pt(9))
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
	b.add_theme_font_size_override("font_size", Style.pt(9))
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
	desc.add_theme_font_size_override("font_size", Style.pt(8))
	desc.add_theme_color_override("font_color", DIM)
	row.add_child(desc)
	return row


func _sell_button(kind: String, id: String, index: int) -> Button:
	var def: Dictionary = Catalog.TRINKETS[id] if kind == "trinket" else Catalog.CONSUMABLES[id]
	var b := Button.new()
	b.add_theme_font_size_override("font_size", Style.pt(8))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(152.0, 0.0)
	var label := str(def["name"])
	if kind == "consumable" and Run.consumable_stacks[index] > 1:
		# Says "one" because a click sells one off the stack, not the lot.
		label += " x%d" % Run.consumable_stacks[index]
		b.text = "%s   sell one $%d" % [label, Catalog.sell_price(kind, id)]
	else:
		b.text = "%s   sell $%d" % [label, Catalog.sell_price(kind, id)]
	b.tooltip_text = str(def["desc"])
	b.pressed.connect(sold.emit.bind(kind, index))
	return b


func show_lost() -> void:
	_open("DEFEAT", [
		"Ante %d, %s" % [Run.ante, Catalog.BLIND_NAME[Run.blind]],
		"Scored %s, needed %s" % [_commas(Run.score), _commas(Run.target)],
		"Short by %s." % _commas(Run.target - Run.score),
	])
	_add_summary()
	_add_continue("MENU")


func show_won() -> void:
	_open("MACHINE BEATEN", [
		"All 8 antes cleared.",
	])
	_add_summary()
	_add_continue("MENU")


## How the run went, on the screen where the run is over.
##
## A run is eight antes long and the only thing a player otherwise carries out
## of it is whether they died. These are the three numbers that describe how,
## and they are chosen to be about the *player* rather than about the machine:
## the best stage is what the build was worth at its peak, the longest combo is
## how well the flippers were played, and the most-used ball is what the run
## turned out to be made of.
func _add_summary() -> void:
	_overlay_body.add_child(_body_line("", INK))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var ball: Array = Run.most_used_ball()
	var ball_text := "--"
	if not str(ball[0]).is_empty():
		ball_text = "%s  x%d" % [str(Catalog.BALLS[ball[0]]["name"]), int(ball[1])]

	var rows := [
		["Best stage", "%s%s" % [_commas(Run.best_stage_score),
			"" if Run.best_stage_label.is_empty() else "   " + Run.best_stage_label]],
		["Longest combo", "%d hits" % Run.best_chain],
		["Most-used ball", ball_text],
	]
	for row in rows:
		grid.add_child(_stat_label(str(row[0]), DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_stat_label(str(row[1]), INK, HORIZONTAL_ALIGNMENT_LEFT))
	_overlay_body.add_child(grid)


## A grid cell rather than a centred line: the values line up in a column, which
## is the only reason to use a table instead of three more sentences.
func _stat_label(text: String, colour: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Style.pt(9))
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(150.0, 0.0)
	return l


func _open(title: String, lines: Array) -> void:
	_overlay_title.text = title
	for child in _overlay_body.get_children():
		_overlay_body.remove_child(child)
		child.queue_free()
	for line in lines:
		_overlay_body.add_child(_body_line(str(line), INK))
	_overlay.visible = true


## The button every screen ends on.
##
## Added last, after each screen's own content, and given focus so the keyboard
## still works -- Godot routes ui_accept to the focused control, so this is one
## affordance rather than a button and a separate key binding to keep in step.
func _continue_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", Style.pt(11))
	b.custom_minimum_size = Vector2(160.0, 24.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(confirmed.emit)
	return b


func _add_continue(label: String) -> void:
	_overlay_body.add_child(_body_line("", INK))
	var b := _continue_button(label)
	_overlay_body.add_child(b)
	# Deferred because a Control cannot take focus in the same frame it enters
	# the tree.
	b.grab_focus.call_deferred()


func _body_line(text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Style.pt(9))
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
	# x4 reads better than x4.0. Two decimals rather than one because fever
	# moves in quarters: at one decimal x1.25 printed as x1.2 and x1.75 as x1.8,
	# so the readout disagreed with the arithmetic it was reporting.
	if is_equal_approx(v, float(int(v))):
		return str(int(v))
	var text := "%.2f" % v
	return text.trim_suffix("0")


static func _pips(filled: int, total: int) -> String:
	var s := ""
	for i in maxi(total, filled):
		s += "*" if i < filled else "-"
	return s
