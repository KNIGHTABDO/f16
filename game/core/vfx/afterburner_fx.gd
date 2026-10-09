class_name AfterburnerFx
extends Node3D
## Afterburner plume for one jet nozzle. Add as a child of the nozzle node. The nozzle's local +Z must point
## aft (exhaust direction). The plume starts at the nozzle origin and grows aft. Shock diamonds show near Mach 1
## at full afterburner. Build with setup(), then set_intensity(throttle_ab) and update() every frame.
## One MeshInstance3D (cylinder, afterburner.gdshader), one draw call.

const SHOCK_SPACING := 1.4  # metres between shock diamonds
const LENGTH_MIN := 2.5
const LENGTH_MAX := 8.0

var _mesh_inst: MeshInstance3D
var _mat: ShaderMaterial
var _radius := 0.9
var _length := LENGTH_MAX
var _intensity := 0.0
var _built := false


func _ready() -> void:
	if not _built:
		_build()


## radius: nozzle exit radius (m). length: full-throttle plume length (m).
func setup(radius: float = 0.9, length: float = LENGTH_MAX) -> void:
	_radius = maxf(radius, 0.1)
	_length = clampf(length, LENGTH_MIN, LENGTH_MAX)
	if not _built:
		_build()
	_apply()


func _build() -> void:
	_built = true
	var cyl := CylinderMesh.new()
	# Unit height: the length is applied with the node scale, so the shader's cone_length is 1.0.
	cyl.height = 1.0
	cyl.top_radius = 0.42  # narrow end at local +Y (the nozzle)
	cyl.bottom_radius = 1.0  # wide far end at -Y
	cyl.radial_segments = 14
	cyl.rings = 4
	_mat = VfxAssets.shader_material("afterburner.gdshader")
	_mat.set_shader_parameter("cone_length", 1.0)
	_mat.set_shader_parameter("intensity", 0.0)
	_mat.set_shader_parameter("shock_strength", 0.0)
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = cyl
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Mesh +Y maps to -Z, so the narrow end sits at the nozzle and the plume extends aft (+Z).
	_mesh_inst.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	add_child(_mesh_inst)
	visible = false


## Throttle-driven afterburner amount, 0 (off) .. 1 (full).
func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("intensity", _intensity)
	visible = _intensity > 0.01
	_apply()


## Per-frame state. speed_mach: Mach number (diamonds and length). g and aoa are accepted for the shared
## aircraft-effect signature; not used here. alt: altitude ASL in metres (plume shortens and thins above 4 km).
func update(speed_mach: float, _g: float, _aoa: float, alt: float) -> void:
	if _mat == null:
		return
	var thin := 1.0 - 0.3 * smoothstep(4000.0, 14000.0, alt)
	var shock := smoothstep(0.85, 1.05, speed_mach) * _intensity
	_mat.set_shader_parameter("shock_strength", shock)
	_length = clampf(lerpf(LENGTH_MIN, LENGTH_MAX, _intensity) * thin, LENGTH_MIN, LENGTH_MAX)
	_apply()


func _apply() -> void:
	if _mesh_inst == null:
		return
	var length := _length * (0.7 + 0.3 * _intensity)
	_mesh_inst.position = Vector3(0.0, 0.0, length * 0.5)
	_mesh_inst.scale = Vector3(_radius, length, _radius)
	if _mat != null:
		_mat.set_shader_parameter("shock_spacing", SHOCK_SPACING / maxf(length, 0.1))
