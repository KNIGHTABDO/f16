class_name SectionHeader
extends MarginContainer

var title_text: String = ""
var subtitle_text: String = ""

var _title_label: Label
var _subtitle_label: Label


func _init(title: String = "", subtitle: String = "") -> void:
	title_text = title
	subtitle_text = subtitle


func _ready() -> void:
	custom_minimum_size.y = 56.0
	add_theme_constant_override("margin_top", 12)
	add_theme_constant_override("margin_bottom", 6)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	# Cyan vertical accent bar
	var accent := ColorRect.new()
	accent.color = Color("#3FD0FF")
	accent.custom_minimum_size = Vector2(4, 24)
	hbox.add_child(accent)

	_title_label = Label.new()
	_title_label.text = title_text.to_upper()
	_title_label.add_theme_color_override("font_color", Color("#3FD0FF"))
	_title_label.add_theme_font_size_override("font_size", 22)
	hbox.add_child(_title_label)

	if subtitle_text != "":
		_subtitle_label = Label.new()
		_subtitle_label.text = subtitle_text
		_subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8, 0.8))
		_subtitle_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(_subtitle_label)


func set_title(t: String) -> void:
	title_text = t
	if _title_label:
		_title_label.text = t.to_upper()


func set_subtitle(s: String) -> void:
	subtitle_text = s
	if _subtitle_label:
		_subtitle_label.text = s
