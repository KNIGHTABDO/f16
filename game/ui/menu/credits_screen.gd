class_name CreditsScreen
extends Control
## Credits screen dynamically reading and displaying all CREDITS.md files under res://assets.

const KNOWN_CREDIT_FILES := [
	"res://assets/models/CREDITS.md",
	"res://assets/sounds/CREDITS.md",
	"res://assets/textures/vfx/CREDITS.md"
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dark military glass background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.05, 0.08, 0.94)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Header (leaving space for back button on top-left)
	var header_hbox := HBoxContainer.new()
	header_hbox.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(header_hbox)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(150, 0)
	header_hbox.add_child(spacer)

	var title_lbl := Label.new()
	title_lbl.text = "KNIGHT WINGS // CREDITS & OPEN LICENSES"
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color("#3FD0FF"))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(title_lbl)

	# Panel containing the formatted credits
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var rich_lbl := RichTextLabel.new()
	rich_lbl.bbcode_enabled = true
	rich_lbl.fit_content = true
	rich_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich_lbl.add_theme_font_size_override("normal_font_size", 16)
	rich_lbl.add_theme_font_size_override("bold_font_size", 18)
	scroll.add_child(rich_lbl)

	rich_lbl.text = _gather_credits_bbcode()


func _gather_credits_bbcode() -> String:
	var out := ""
	out += "[font_size=24][color=#3FD0FF][b]KNIGHT WINGS[/b][/color][/font_size]\n"
	out += "[color=#90A4AE]Tactical Combat Flight Simulator for iOS & iPadOS[/color]\n\n"
	out += "[font_size=18][color=#3FD0FF][b]ENGINE & TOOLS[/b][/color][/font_size]\n"
	out += "Godot Engine 4.7.2 (MIT License)\n"
	out += "Jolt Physics 3D (MIT License)\n\n"

	out += "[font_size=18][color=#3FD0FF][b]FONTS[/b][/color][/font_size]\n"
	out += "Rajdhani (SIL Open Font License 1.1) by Indian Type Foundry\n"
	out += "Inter (SIL Open Font License 1.1) by Rasmus Andersson\n\n"

	# Scan for all CREDITS.md files under res://assets
	var scanned_files := _find_credits_files("res://assets")
	# Ensure known ones are included if not discovered by directory scan
	for k in KNOWN_CREDIT_FILES:
		if not scanned_files.has(k) and FileAccess.file_exists(k):
			scanned_files.append(k)

	for path in scanned_files:
		var file_section := _format_markdown_file(path)
		if file_section != "":
			out += file_section + "\n\n"

	return out


func _find_credits_files(base_path: String) -> Array[String]:
	var results: Array[String] = []
	var dir := DirAccess.open(base_path)
	if not dir:
		return results

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			results.append_array(_find_credits_files(base_path + "/" + file_name))
		elif file_name.to_lower() == "credits.md":
			results.append(base_path + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results


func _format_markdown_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""

	var text := FileAccess.get_file_as_string(path)
	var category := path.trim_prefix("res://assets/").get_base_dir().to_upper()
	if category == "":
		category = "ASSETS"

	var section := "[font_size=20][color=#3FD0FF][b]═══ %s CREDITS ═══[/b][/color][/font_size]\n[color=#546E7A][i]%s[/i][/color]\n\n" % [category, path]

	# Simple markdown to BBCode conversion
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("# "):
			section += "[font_size=18][color=#3FD0FF][b]" + l.trim_prefix("# ") + "[/b][/color][/font_size]\n"
		elif l.begins_with("## "):
			section += "[font_size=16][color=#80D8FF][b]" + l.trim_prefix("## ") + "[/b][/color][/font_size]\n"
		elif l.begins_with("### "):
			section += "[font_size=15][color=#E0F7FA][b]" + l.trim_prefix("### ") + "[/b][/color][/font_size]\n"
		elif l.begins_with("- "):
			section += "  • " + l.trim_prefix("- ") + "\n"
		elif l.begins_with("* "):
			section += "  • " + l.trim_prefix("* ") + "\n"
		else:
			section += l + "\n"

	return section
