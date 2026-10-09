class_name HUDTapes
extends RefCounted
## Fighter-style speed and altitude tapes, shared by the arcade and realistic HUDs.
## Monochrome: one colour for ticks, labels and the value window. Draws into any CanvasItem.


static func speed_value(kmh: float, units: String) -> float:
	match units:
		"aviation":
			return kmh / 1.852
		"imperial":
			return kmh / 1.60934
		_:
			return kmh


static func speed_unit(units: String) -> String:
	match units:
		"aviation":
			return "KT"
		"imperial":
			return "MPH"
		_:
			return "KM/H"


static func alt_value(meters: float, units: String) -> float:
	if units == "metric":
		return meters
	return meters * 3.28084


static func alt_unit(units: String) -> String:
	return "M" if units == "metric" else "FT"


## Speed tape: 10-unit ticks, labelled every 50, scale tuned per unit.
static func draw_speed(ci: CanvasItem, font: Font, rect: Rect2, value: float, units: String, col: Color, s: float) -> void:
	var ppu := 1.2 if units != "metric" else 0.7
	draw_tape(ci, font, rect, value, 10.0, 50.0, ppu * s, false, col, int(12.0 * s))


## Altitude tape: 20-unit ticks in feet (10 in metres), labelled every 100 (50).
static func draw_altitude(ci: CanvasItem, font: Font, rect: Rect2, value: float, units: String, col: Color, s: float) -> void:
	if units == "metric":
		draw_tape(ci, font, rect, value, 10.0, 50.0, 0.9 * s, true, col, int(12.0 * s))
	else:
		draw_tape(ci, font, rect, value, 20.0, 100.0, 0.25 * s, true, col, int(12.0 * s))


## Core tape: ticks scroll past a fixed centre line; the value window sits on the centre line.
## on_right puts the scale on the right edge (altitude style), otherwise on the left (speed style).
static func draw_tape(ci: CanvasItem, font: Font, rect: Rect2, value: float, minor: float, major: float,
		px_per_unit: float, on_right: bool, col: Color, fs: int) -> void:
	var mid_y := rect.position.y + rect.size.y * 0.5
	var edge_x := rect.end.x if on_right else rect.position.x
	var dir := -1.0 if on_right else 1.0
	var tick_col := Color(col.r, col.g, col.b, 0.5)
	var label_col := Color(col.r, col.g, col.b, 0.85)

	ci.draw_rect(rect, Color(0.0, 0.03, 0.03, 0.32), true)
	ci.draw_line(Vector2(edge_x, rect.position.y), Vector2(edge_x, rect.end.y), tick_col, 1.0)

	var half := rect.size.y * 0.5 / px_per_unit
	var k := floorf((value - half) / minor)
	var k_end := ceilf((value + half) / minor)
	var int_major := int(major)
	while k <= k_end:
		var v := k * minor
		var iv := int(roundf(v))
		var y := mid_y - (v - value) * px_per_unit
		if y >= rect.position.y and y <= rect.end.y:
			var is_major := iv % int_major == 0
			var tick_len := 9.0 if is_major else 5.0
			ci.draw_line(Vector2(edge_x, y), Vector2(edge_x + dir * tick_len, y), tick_col if not is_major else label_col, 1.0)
			if is_major and iv >= 0:
				var tx := edge_x + dir * (tick_len + 4.0)
				if on_right:
					ci.draw_string(font, Vector2(tx - 48.0, y + fs * 0.35), str(iv), HORIZONTAL_ALIGNMENT_RIGHT, 48, fs, label_col)
				else:
					ci.draw_string(font, Vector2(tx, y + fs * 0.35), str(iv), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)
		k += 1.0

	# Value window on the centre line
	var box_h := float(fs) * 2.0
	var box := Rect2(rect.position.x, mid_y - box_h * 0.5, rect.size.x, box_h)
	ci.draw_rect(box, Color(0.0, 0.03, 0.03, 0.75), true)
	ci.draw_rect(box, Color(col.r, col.g, col.b, 0.9), false, 1.2)
	ci.draw_string(font, Vector2(box.position.x, mid_y + fs * 0.35), str(roundi(value)), HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), fs + 4, col)
