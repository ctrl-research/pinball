extends Node
## Prints the playfield that `TableLayout` actually generates, as JSON, so
## `tools/preview_table.py` can draw a picture of it.
##
## Worth having because the table is data: the walls are computed (offset
## polylines, mirrored halves, a rounded arch), so reading the constants tells
## you much less than seeing the result -- and a mod or a boss reshapes it.
## This dumps what the game will build, not what the source says.
##
##   godot --headless --path . tools/dump_layout.tscn > /tmp/layout.json
##   python3 tools/preview_table.py /tmp/layout.json table.png

const MOUTH_SHIFT := 0.0  # try 10.0 for "The Drain", -6.0 for Outlane Guards


func _ready() -> void:
	var data := {
		"size": [TableLayout.WIDTH, TableLayout.HEIGHT],
		"wall_thickness": TableLayout.WALL_THICKNESS,
		"ball_radius": TableLayout.BALL_RADIUS,
		"walls": _lines(TableLayout.walls(MOUTH_SHIFT)),
		"outlanes": _lines(TableLayout.outlane_polys(MOUTH_SHIFT)),
		"solids": _lines(TableLayout.solids(MOUTH_SHIFT)),
		"slingshots": [
			_pts(TableLayout.slingshot(true)["tri"]),
			_pts(TableLayout.slingshot(false)["tri"]),
		],
		"bumpers": _list(TableLayout.BUMPERS),
		"bumper_radius": TableLayout.BUMPER_RADIUS,
		"drops": _list(TableLayout.DROP_TARGETS),
		"standups": _list(TableLayout.STANDUP_TARGETS),
		"target_size": [TableLayout.TARGET_SIZE.x, TableLayout.TARGET_SIZE.y],
		"rollovers": _list(TableLayout.ROLLOVERS),
		"rollover_size": [TableLayout.ROLLOVER_SIZE.x, TableLayout.ROLLOVER_SIZE.y],
		"spinner": _rect(TableLayout.SPINNER_RECT),
		"orbit": _rect(TableLayout.ORBIT_RECT),
		"ball_rest": [TableLayout.BALL_REST.x, TableLayout.BALL_REST.y],
		"gate": [
			[TableLayout.GATE_A.x, TableLayout.GATE_A.y],
			[TableLayout.GATE_B.x, TableLayout.GATE_B.y],
		],
		"drain_y": TableLayout.DRAIN_Y,
		"flippers": [
			_flipper(true), _flipper(false),
		],
	}
	print(JSON.stringify(data))
	get_tree().quit(0)


func _flipper(is_left: bool) -> Dictionary:
	var pivot := TableLayout.LEFT_FLIPPER_PIVOT if is_left else TableLayout.RIGHT_FLIPPER_PIVOT
	var angles := TableLayout.flipper_angles(is_left)
	return {
		"pivot": [pivot.x, pivot.y],
		"rest": angles.x,
		"up": angles.y,
		"length": TableLayout.FLIPPER_LENGTH,
		"radius": TableLayout.FLIPPER_RADIUS,
	}


func _rect(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _pts(pts: PackedVector2Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append([p.x, p.y])
	return out


func _lines(lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		out.append(_pts(line))
	return out


func _list(points: Array) -> Array:
	var out: Array = []
	for p in points:
		out.append([p.x, p.y])
	return out
