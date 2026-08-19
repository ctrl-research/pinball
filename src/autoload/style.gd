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

const FONT_PATH := "res://assets/fonts/Jersey25.ttf"

## Jersey 25 is far less grid-sensitive than Silkscreen was -- it stays legible
## between multiples -- but multiples of 8 still land on whole pixels and look
## crispest, so prefer them for new text.
const DESIGN_GRID := 8

## Jersey 25 is the heavy member of its family, so "bold" is the file rather
## than a weight axis to ask for.
##
## It is the third face tried, and each rejection was on legibility rather than
## taste, decided by rendering the same confusable string in each:
##
##   Pixelify Sans  drew "BEAT" as "GEAT" and "flip" as "Aip", at every size.
##   Silkscreen     drew a malformed 4 that reads as a 9, and an H and M that
##                  are near-identical at panel sizes.
##
## Jersey 25 separates H/M, 4/9, B/8, 0/O and I/L/1 cleanly, and is narrower
## into the bargain -- it fits a whole panel line where Silkscreen ran out.


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
