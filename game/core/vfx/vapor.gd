class_name VaporFx
extends MeshInstance3D
## Condensation shell around the fuselage (or a wing root) at transonic speed, high G, or high AoA in humid
## low-altitude air. Add as a child of the aircraft, call setup() once, then update() every frame.
## One MeshInstance3D with a per-instance vapor.gdshader material (one draw call, no particles).

const FADE_RATE := 4.0  # intensity per second

var _target := 0.0
var _intensity := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	if _mat == null:
		_mat = VfxAssets.shader_material("vapor.gdshader")
		material_override = _mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visible = false


## length: fuselage length to wrap (m). radius: fuselage radius (m). offset: centre in the parent's space.
## The shell is a capsule along the parent's local Z (aircraft nose is -Z).
func setup(length: float, radius: float, offset := Vector3.ZERO) -> void:
	var cap := CapsuleMesh.new()
	cap.radius = radius * 1.08
	cap.height = maxf(length, cap.radius * 2.0 + 0.1)
	mesh = cap
	rotation = Vector3(PI * 0.5, 0.0, 0.0)
	position = offset
	if _mat == null:
		_mat = VfxAssets.shader_material("vapor.gdshader")
		material_override = _mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Sets the target density. speed_mach: Mach number. g: load factor. aoa: angle of attack in radians.
## alt: altitude ASL in metres. Fades in and out in _process().
func update(speed_mach: float, g: float, aoa: float, alt: float) -> void:
	var g_term := smoothstep(4.0, 7.0, g)
	var aoa_term := smoothstep(0.21, 0.35, absf(aoa))
	var low := 1.0 - smoothstep(6000.0, 11000.0, alt)
	var mach_term := smoothstep(0.82, 0.95, speed_mach) * (1.0 - smoothstep(1.15, 1.4, speed_mach))
	_target = clampf(maxf(g_term * 0.8, aoa_term * 0.7) + mach_term * (0.4 + 0.6 * low), 0.0, 1.0)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_intensity = move_toward(_intensity, _target, FADE_RATE * delta)
	visible = _intensity > 0.01
	if visible:
		_mat.set_shader_parameter("intensity", _intensity)
