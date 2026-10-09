class_name HUDDamage
extends Control
## Aircraft damage status display and directional damage vignette flash.

var hud_color := Color("#3CFF6A")
var aircraft: Aircraft
var hud_scale := 1.0

var _flash_intensity := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	Events.damaged.connect(_on_damaged)


func _exit_tree() -> void:
	if Events.damaged.is_connected(_on_damaged):
		Events.damaged.disconnect(_on_damaged)


func _on_damaged(victim: Node3D, amount: float, _source: Node) -> void:
	if victim == aircraft:
		_flash_intensity = clampf(_flash_intensity + amount / 40.0, 0.3, 1.0)


func update_damage(delta: float) -> void:
	if _flash_intensity > 0.0:
		_flash_intensity = maxf(0.0, _flash_intensity - delta * 2.0)
	queue_redraw()


func _draw() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return

	var vp_size := size

	# 1. Red Screen Edge Damage Vignette
	if _flash_intensity > 0.01:
		var edge_w := 60.0 * hud_scale
		var v_col := Color(0.9, 0.08, 0.08, _flash_intensity * 0.45)
		# Top
		draw_rect(Rect2(0, 0, vp_size.x, edge_w), v_col, true)
		# Bottom
		draw_rect(Rect2(0, vp_size.y - edge_w, vp_size.x, edge_w), v_col, true)
		# Left
		draw_rect(Rect2(0, 0, edge_w, vp_size.y), v_col, true)
		# Right
		draw_rect(Rect2(vp_size.x - edge_w, 0, edge_w, vp_size.y), v_col, true)

	# 2. Aircraft Health & System Status Bar (Bottom Center)
	if not Settings.hud_show_damage:
		return

	var center_x := vp_size.x * 0.5
	var bar_y := vp_size.y - 36.0 * hud_scale
	var bar_w := 180.0 * hud_scale
	var bar_h := 8.0 * hud_scale

	var hp_frac := clampf(aircraft.health / maxf(aircraft.max_health, 1.0), 0.0, 1.0)
	var hp_col := Color("#3CFF6A").lerp(Color("#FF2020"), 1.0 - hp_frac)

	# Bar backdrop
	draw_rect(Rect2(center_x - bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.04, 0.08, 0.06, 0.8), true)
	draw_rect(Rect2(center_x - bar_w * 0.5, bar_y, bar_w * hp_frac, bar_h), hp_col, true)
	draw_rect(Rect2(center_x - bar_w * 0.5, bar_y, bar_w, bar_h), Color(hud_color.r, hud_color.g, hud_color.b, 0.5), false, 1.2)

	# Status text
	var fs := int(11.0 * hud_scale)
	var status_text := "INTEGRITY %d%%" % roundi(hp_frac * 100.0)
	draw_string(_font, Vector2(center_x, bar_y - 4 * hud_scale), status_text, HORIZONTAL_ALIGNMENT_CENTER, int(bar_w), fs, hp_col)
