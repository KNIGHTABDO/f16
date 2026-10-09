class_name HangarTurntable
extends SubViewportContainer
## Hangar turntable: the aircraft model (or its profile card) on a plate under studio lights.
## Spins slowly when idle and keeps spinning after a flick. Drag to spin and tilt; pinch, wheel or magnify to zoom.
## Touch and wheel input is read in _input, not GUI input, so the buttons beside the view keep working.

const AUTO_SPIN := 0.35  ## rad/s while idle
const SPIN_PER_PX := 0.01
const TILT_PER_PX := 0.005
const TILT_MIN := -0.05
const TILT_MAX := 0.6
const DIST_START := 5.4
const DIST_MIN := 2.2
const DIST_MAX := 7.0
const FIT_RADIUS := 1.1  ## bounding-sphere radius of the fitted model, in world units
const FLING_DAMP := 1.6  ## how fast a released spin eases back to AUTO_SPIN
const PLATE_RADIUS := 1.0

var _world: SubViewport
var _camera: Camera3D
var _yaw_node: Node3D
var _fit_node: Node3D
var _plate: MeshInstance3D
var _model: Node3D
var _livery: Texture2D
var _yaw := 0.0
var _yaw_vel := AUTO_SPIN
var _tilt := 0.25
var _dist := DIST_START
var _touches: Dictionary = {}  ## touch index -> position, for touches that started on this view
var _pinch_span_prev := 0.0
var _pending_id := ""
var _built := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_world()
	_built = true
	if _pending_id != "":
		show_aircraft(_pending_id)
		_pending_id = ""


func _exit_tree() -> void:
	_touches.clear()


func _process(delta: float) -> void:
	if _touches.is_empty():
		_yaw_vel = lerpf(_yaw_vel, AUTO_SPIN, 1.0 - exp(-FLING_DAMP * delta))
		_yaw += _yaw_vel * delta
	_yaw_node.rotation.y = _yaw
	_camera.position = Vector3(0.0, sin(_tilt) * _dist, cos(_tilt) * _dist)
	_camera.look_at(Vector3.ZERO)


func _input(event: InputEvent) -> void:
	if not _built or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if get_global_rect().has_point(touch.position):
				_touches[touch.index] = touch.position
				_pinch_span_prev = _pinch_span()
		else:
			_touches.erase(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var span := _pinch_span()
			if _pinch_span_prev > 1.0 and span > 1.0:
				_zoom(_pinch_span_prev / span)
			_pinch_span_prev = span
		else:
			_spin(drag.relative)
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		if get_global_rect().has_point(magnify.position):
			_zoom(1.0 / maxf(magnify.factor, 0.01))
	elif event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if wheel.pressed and get_global_rect().has_point(wheel.position):
			if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.92)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.08)


## Shows an aircraft: its GLB model if it has one, else its profile card, else a name label.
func show_aircraft(aircraft_id: String) -> void:
	if not _built:
		_pending_id = aircraft_id
		return
	_livery = null
	for child in _fit_node.get_children():
		_fit_node.remove_child(child)
		child.queue_free()
	_model = null
	var data := AircraftData.load_id(aircraft_id)
	if data != null and data.model != "" and ResourceLoader.exists(data.model):
		var packed := load(data.model) as PackedScene
		if packed != null:
			_model = packed.instantiate() as Node3D
	if _model != null:
		_model.name = "Model"
		_model.scale = Vector3.ONE * data.model_scale
		_model.rotation_degrees = data.model_rotation_deg
		_model.position = data.model_offset
		_fit_node.add_child(_model)
		_fit_to_model()
	else:
		_add_profile(aircraft_id)


## Puts a livery on the model as a triplanar overlay. Null clears it back to the factory paint.
func set_livery(tex: Texture2D) -> void:
	if tex == _livery:
		return
	_livery = tex
	if _model == null:
		return
	if tex == null:
		LiveryOverlay.clear(_model)
	else:
		LiveryOverlay.apply(_model, tex)


func _spin(rel: Vector2) -> void:
	_yaw += rel.x * SPIN_PER_PX
	_yaw_vel = rel.x * SPIN_PER_PX * 60.0
	_tilt = clampf(_tilt + rel.y * TILT_PER_PX, TILT_MIN, TILT_MAX)


func _zoom(factor: float) -> void:
	_dist = clampf(_dist * factor, DIST_MIN, DIST_MAX)


func _pinch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _fit_to_model() -> void:
	var boxes: Array[AABB] = []
	_collect_boxes(_model, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return
	var box := boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	var s := FIT_RADIUS / maxf(box.size.length() * 0.5, 0.001)
	_fit_node.scale = Vector3.ONE * s
	_fit_node.position = -box.get_center() * s
	_plate.position = Vector3(0.0, (box.position.y - box.get_center().y) * s - 0.02, 0.0)
	_plate.visible = true


func _collect_boxes(node: Node3D, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf := parent_xf * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(xf * (node as MeshInstance3D).mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect_boxes(child as Node3D, xf, out)


func _add_profile(aircraft_id: String) -> void:
	var tex := Progression.art_texture("aircraft/" + aircraft_id)
	if tex != null:
		var card := Sprite3D.new()
		card.texture = tex
		card.pixel_size = 1.9 / float(maxi(tex.get_width(), tex.get_height()))
		card.shaded = false
		card.double_sided = true
		card.position = Vector3(0.0, tex.get_height() * card.pixel_size * 0.5, 0.0)
		_fit_node.add_child(card)
	else:
		var label := Label3D.new()
		label.text = str(Progression.entry(aircraft_id).get("name", aircraft_id))
		label.font_size = 96
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 0.8, 0.0)
		_fit_node.add_child(label)
	_plate.position = Vector3(0.0, -0.02, 0.0)
	_plate.visible = true


func _build_world() -> void:
	_world = SubViewport.new()
	_world.own_world_3d = true
	_world.transparent_bg = true
	add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)

	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.near = 0.05
	_camera.far = 60.0
	_camera.current = true
	_world.add_child(_camera)

	_add_light(Vector3(-35.0, -40.0, 0.0), 1.1, Color(1.0, 0.97, 0.92))  # key
	_add_light(Vector3(-10.0, 140.0, 0.0), 0.4, Color(0.7, 0.85, 1.0))  # fill
	_add_light(Vector3(-20.0, 180.0, 0.0), 0.6, Color.WHITE)  # rim

	_yaw_node = Node3D.new()
	_world.add_child(_yaw_node)
	_fit_node = Node3D.new()
	_yaw_node.add_child(_fit_node)

	var disc := CylinderMesh.new()
	disc.top_radius = PLATE_RADIUS
	disc.bottom_radius = PLATE_RADIUS
	disc.height = 0.03
	disc.radial_segments = 48
	# Unshaded: a lit plate picked up the key light and turned into a bright white slab on the mobile renderer
	var plate_mat := StandardMaterial3D.new()
	plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate_mat.albedo_color = Color(0.03, 0.08, 0.12, 0.7)
	plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plate = MeshInstance3D.new()
	_plate.mesh = disc
	_plate.material_override = plate_mat
	_plate.visible = false
	_yaw_node.add_child(_plate)

	var rim := TorusMesh.new()
	rim.inner_radius = PLATE_RADIUS - 0.012
	rim.outer_radius = PLATE_RADIUS + 0.004
	rim.rings = 64
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = Color(0.25, 0.82, 1.0, 0.8)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rim_node := MeshInstance3D.new()
	rim_node.mesh = rim
	rim_node.material_override = rim_mat
	rim_node.position.y = 0.016
	_plate.add_child(rim_node)


func _add_light(rot_deg: Vector3, energy: float, color: Color) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rot_deg
	light.light_energy = energy
	light.light_color = color
	_world.add_child(light)
