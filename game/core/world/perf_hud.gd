class_name PerfHud
extends CanvasLayer
## Live FPS, frame time, draw calls and 3D render scale. Shown while Settings.show_perf_hud is on
## (the "Show FPS Counter" toggle). Text refreshes four times a second to keep the overlay cheap.

const REFRESH_S := 0.25

var governor: PerfGovernor = null

var _label: Label
var _ms := 16.7
var _elapsed := 0.0


func _init() -> void:
	layer = 100


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 48.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	_label.visible = Settings.show_perf_hud
	if not _label.visible:
		return
	_ms = lerpf(_ms, delta * 1000.0, 0.1)
	_elapsed += delta
	if _elapsed < REFRESH_S:
		return
	_elapsed = 0.0
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var status := ""
	if governor != null:
		status = "  %.2f scale" % governor.scale
		if governor.throttled:
			status += "  THROTTLED 30 fps"
	_label.text = "%d fps  %.1f ms\n%d draw calls%s" % [int(Engine.get_frames_per_second()), _ms, draws, status]
