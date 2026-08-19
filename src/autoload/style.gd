extends Node
## Project-wide typography (autoload "Style").
##
## Sets the fallback font every Control falls back to, rather than a font
## override on each label. Nothing in the UI asks for a font by name -- the HUD
## only ever overrides *sizes* -- so replacing the fallback restyles the entire
## game from one place, and swapping the typeface later is a one-line change.
##
## Built in code rather than as a .tres because the weight axis is addressed by
## an OpenType tag, and a tag hand-encoded as an integer in a resource file is
## unreadable and silently wrong if it is off by one byte.

const FONT_PATH := "res://assets/fonts/Silkscreen-Bold.ttf"

## Silkscreen is drawn on an 8px grid, so sizes that are multiples of 8 land on
## whole pixels and anything else resamples -- at 7px the W loses a column and
## reads as a different glyph entirely. Prefer 8, 16 and 24 for new text; the
## in-between sizes the panels use are legible but not crisp, and that is the
## price of fitting this much text into a 166px column.
const DESIGN_GRID := 8

## Silkscreen ships Regular and Bold as separate files rather than a weight
## axis, so "heavy" is the file we load, not a number we ask for.
##
## Pixelify Sans was tried first, as the closest OFL match to Balatro's own
## m6x11. It was rejected on legibility, not taste: at *every* size from 7 to
## 24 it drew "BEAT" as "GEAT", "flip" as "Aip" and capital E as a euro sign.
## A font that cannot spell the word BEAT is not a candidate, however well it
## matches a reference.


func _ready() -> void:
	var base := load(FONT_PATH)
	if base == null:
		push_warning("Style: %s missing; keeping the default font" % FONT_PATH)
		return

	# Wrapped in a FontVariation purely to turn substitutions off. This is UI
	# text, not prose -- a score readout has no business swapping glyphs, and a
	# ligature in a pixel face tends to read as a different letter entirely.
	#
	# Assigned as a whole dictionary rather than mutated key by key: the
	# property getter hands back a copy, so writing into it does nothing.
	var ts := TextServerManager.get_primary_interface()
	var features := {}
	for feature in ["liga", "clig", "dlig", "calt"]:
		features[ts.name_to_tag(feature)] = 0

	var bold := FontVariation.new()
	bold.base_font = base
	bold.opentype_features = features

	# Both, and the order matters. `fallback_font` alone does nothing here: the
	# default theme ships its *own* default_font, and a theme's font always wins
	# over the fallback -- the fallback is only consulted when a theme has none.
	# Setting only the fallback leaves every Label still rendering Open Sans,
	# which is exactly what it did.
	ThemeDB.get_default_theme().default_font = bold
	ThemeDB.fallback_font = bold
