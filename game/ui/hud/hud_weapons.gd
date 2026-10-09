class_name HUDWeapons
extends Control
## Weapon status panel displaying selected weapon, ammo, gun rounds, and flares.
## Reads state duck-typed from the player aircraft and weapons system with fallback placeholders.

var hud_color := Color("#3CFF6A")
var aircraft: Aircraft
var hud_scale := 1.0

# Current weapon state
var selected_id := "aim9x"
var selected_name := "AIM-9X"
var selected_type := "missile"
var selected_count := 4
var gun_ammo := 511
var gun_ammo_max := 511
var flares := 60
var weapon_list: Array = []

var _icons: Dictionary = {}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(200, 110)
	size = custom_minimum_size
	_load_icons()


func _load_icons() -> void:
	var paths := {
		"missile": "res://assets/ui/icons/missile.png",
		"bomb": "res://assets/ui/icons/bomb.png",
		"rocket": "res://assets/ui/icons/rocket.png",
		"gun": "res://assets/ui/icons/gun.png",
		"flare": "res://assets/ui/icons/flare.png"
	}
	for k in paths:
		if ResourceLoader.exists(paths[k]):
			_icons[k] = load(paths[k])


func update_weapons() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return

	var w_node: Node = aircraft.get("weapons") if "weapons" in aircraft else null
	if w_node == null:
		w_node = aircraft.get_node_or_null("Weapons")

	if w_node != null and is_instance_valid(w_node):
		# 1. Duck-typed read from active WeaponSystem
		if w_node.has_method("get_selected"):
			var cur: Dictionary = w_node.call("get_selected")
			selected_id = str(cur.get("id", "aim9x"))
			selected_name = str(cur.get("name", selected_id.to_upper()))
			selected_type = str(cur.get("type", "missile"))
			selected_count = int(cur.get("count", 0))

		if w_node.has_method("get_gun_ammo"):
			gun_ammo = int(w_node.call("get_gun_ammo"))
		if w_node.has_method("get_gun_ammo_max"):
			gun_ammo_max = int(w_node.call("get_gun_ammo_max"))
		if w_node.has_method("get_flares"):
			flares = int(w_node.call("get_flares"))
		if w_node.has_method("get_weapon_list"):
			weapon_list = w_node.call("get_weapon_list")
	else:
		# 2. Fallback read from AircraftData
		if aircraft.data != null:
			gun_ammo_max = aircraft.data.gun_ammo
			gun_ammo = gun_ammo_max
			flares = aircraft.data.flares
			var loadout: Array = aircraft.data.loadout("")
			if not loadout.is_empty():
				var first: Dictionary = loadout[0]
				selected_id = str(first.get("weapon", "aim9x"))
				selected_count = int(first.get("count", 4))
				selected_name = selected_id.to_upper()
				weapon_list = loadout

	queue_redraw()


func _draw() -> void:
	var w := size.x * hud_scale
	var h := size.y * hud_scale
	var col := hud_color

	# Glass background panel
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.04, 0.75), true)
	draw_rect(Rect2(0, 0, w, h), Color(col.r, col.g, col.b, 0.45), false, 1.5)

	# 1. Selected Weapon Header & Count
	var fs_title := int(15.0 * hud_scale)
	var fs_cnt := int(22.0 * hud_scale)

	# Weapon Icon
	var icon_tex: Texture2D = _icons.get(selected_type, _icons.get("missile"))
	if icon_tex != null:
		draw_texture_rect(icon_tex, Rect2(12 * hud_scale, 10 * hud_scale, 24 * hud_scale, 24 * hud_scale), false, col)

	# Name & Count
	draw_string(_font, Vector2(44 * hud_scale, 28 * hud_scale), selected_name, HORIZONTAL_ALIGNMENT_LEFT, 100 * int(hud_scale), fs_title, Color("#FFFFFF"))
	var cnt_str := "%d" % selected_count if selected_count >= 0 else "RDY"
	var cnt_col := col if selected_count > 0 else Color("#FF4444")
	draw_string(_font, Vector2(w - 48 * hud_scale, 30 * hud_scale), cnt_str, HORIZONTAL_ALIGNMENT_RIGHT, 40 * int(hud_scale), fs_cnt, cnt_col)

	# Separator line
	draw_line(Vector2(12 * hud_scale, 42 * hud_scale), Vector2(w - 12 * hud_scale, 42 * hud_scale), Color(col.r, col.g, col.b, 0.3), 1.0)

	# 2. Gun Ammo Bar & Readout
	var fs_sm := int(12.0 * hud_scale)
	draw_string(_font, Vector2(12 * hud_scale, 62 * hud_scale), "GUN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, col)

	var gun_frac := clampf(float(gun_ammo) / maxf(float(gun_ammo_max), 1.0), 0.0, 1.0)
	var bar_w := 75.0 * hud_scale
	var bar_h := 6.0 * hud_scale
	var bar_p := Vector2(48 * hud_scale, 54 * hud_scale)
	draw_rect(Rect2(bar_p, Vector2(bar_w, bar_h)), Color(col.r, col.g, col.b, 0.2), true)
	draw_rect(Rect2(bar_p, Vector2(bar_w * gun_frac, bar_h)), col, true)

	draw_string(_font, Vector2(w - 60 * hud_scale, 62 * hud_scale), "%d" % gun_ammo, HORIZONTAL_ALIGNMENT_RIGHT, 50 * int(hud_scale), fs_sm, Color("#FFFFFF"))

	# 3. Flares Counter
	draw_string(_font, Vector2(12 * hud_scale, 86 * hud_scale), "FLR", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, col)
	var flr_str := "%d" % flares
	draw_string(_font, Vector2(w - 60 * hud_scale, 86 * hud_scale), flr_str, HORIZONTAL_ALIGNMENT_RIGHT, 50 * int(hud_scale), fs_sm, Color("#FFFFFF"))

	# Subtle flare inventory dots
	var dot_x := 48.0 * hud_scale
	var max_dots := mini(flares / 5, 8)
	for d in max_dots:
		draw_circle(Vector2(dot_x + d * 8.0 * hud_scale, 82 * hud_scale), 2.0 * hud_scale, col)
