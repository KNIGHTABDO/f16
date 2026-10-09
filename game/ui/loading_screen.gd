class_name LoadingScreen
extends CanvasLayer
## Loading screen between the mission picker and the flight. Loads the level scene on a thread while it shows the map art,
## a progress bar and a tip that changes every few seconds. The level calls dismiss() once its world is built.

const GROUP := "loading_screen"
const TIP_S := 4.0  ## s each tip stays up

var _scene_path := ""
var _bar: ProgressBar
var _tip: Label
var _tips: Array = []
var _tip_index := 0
var _tip_left := 0.0
var _progress: Array = []
var _changing := false


## Shows the loading screen over the current scene and starts loading `scene_path` on a thread.
static func start(scene_path: String, map_id: String, mode_id: String) -> void:
	var screen := LoadingScreen.new()
	screen.name = "LoadingScreen"
	screen.add_to_group(GROUP)
	screen.layer = 100  ## above the results screen the flight may still show
	screen.process_mode = Node.PROCESS_MODE_ALWAYS  ## keeps running while the tree is paused
	screen._scene_path = scene_path
	screen._build(map_id, mode_id)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	ResourceLoader.load_threaded_request(scene_path)


## Removes every loading screen. The level calls this once its world is built. The menu calls it when a flight cannot start.
static func dismiss() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		node.queue_free()


func _build(map_id: String, mode_id: String) -> void:
	var data := MissionGenerator.data()
	var map: Dictionary = data["maps"][map_id]
	var mode: Dictionary = data["modes"][mode_id]
	_tips = data["tips"]

	var art := TextureRect.new()
	art.texture = Progression.art_texture(String(map.get("loading", map.get("art", ""))))
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)

	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.03, 0.06, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 48.0
	box.offset_right = -48.0
	box.offset_top = -200.0
	box.offset_bottom = -48.0
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var title := Label.new()
	title.text = "%s  ·  %s" % [mode["title"], map["name"]]
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#3FD0FF"))
	box.add_child(title)

	_bar = ProgressBar.new()
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(_bar)

	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 18)
	_tip.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	box.add_child(_tip)
	if not _tips.is_empty():
		_show_tip(randi() % _tips.size())


func _process(delta: float) -> void:
	if _changing:
		return
	_tip_left -= delta
	if _tip_left <= 0.0 and not _tips.is_empty():
		_show_tip((_tip_index + 1) % _tips.size())
	var status := ResourceLoader.load_threaded_get_status(_scene_path, _progress)
	if not _progress.is_empty():
		_bar.value = float(_progress[0]) * 100.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_changing = true
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(_scene_path) as PackedScene)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_changing = true
		push_error("LoadingScreen: could not load '%s'" % _scene_path)
		queue_free()
		GameState.goto_menu()


func _show_tip(index: int) -> void:
	_tip_index = index
	_tip_left = TIP_S
	_tip.text = String(_tips[index])
