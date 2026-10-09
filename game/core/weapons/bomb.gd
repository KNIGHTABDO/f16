class_name Bomb
extends Node3D
## Free-fall bomb (Mk 82) or laser guided bomb (GBU-12) for the combat game. Ballistic with drag, nose follows
## the velocity, ground / water impact causes blast damage. Guided bombs steer gently toward their target.

const GRAVITY := 9.81
const NOSE_FOLLOW := 3.0  ## 1/s, how fast the nose settles onto the velocity vector
const GUIDE_DELAY := 0.8  ## seconds after release before the guidance wakes up
const GLIDE_LIFT := 0.35  ## fraction of gravity a guided bomb can cancel with its wings
const MAX_LIFE := 90.0
const BLAST_SIZE_SCALE := 1.0 / 14.0

signal detonated(bomb: Bomb)

var weapon_id := ""
var data: Dictionary = {}
var shooter: Node3D
var target: Node3D
var team := 0
var velocity := Vector3.ZERO

var _age := 0.0
var _guided := false
var _drag := 0.1
var _dead := false


static func launch(world: Node, shooter_node: Node3D, id: String, wdata: Dictionary, tgt: Node3D,
		xform: Transform3D, start_velocity: Vector3) -> Bomb:
	var b := Bomb.new()
	b.weapon_id = id
	b.data = wdata
	b.shooter = shooter_node
	b.team = int(shooter_node.get("team")) if shooter_node != null else 0
	b.target = tgt
	b.velocity = start_velocity
	b._guided = str(wdata.get("type", "")) == "guided_bomb"
	b._drag = float(wdata.get("drag", 0.1))
	world.add_child(b)
	b.global_transform = xform
	b.reset_physics_interpolation()
	Sfx.play_3d("bomb_release", xform.origin, -2.0)
	return b


func _ready() -> void:
	add_to_group("floating")
	add_child(WeaponModels.build(weapon_id, data))


func get_velocity() -> Vector3:
	return velocity


func _physics_process(dt: float) -> void:
	if _dead:
		return
	_age += dt
	var prev := global_position
	var speed := velocity.length()
	var a := Vector3(0, -GRAVITY, 0) - velocity * (_drag * Targeting.DRAG_SCALE * speed)
	if _guided and _age > GUIDE_DELAY and target != null and is_instance_valid(target) and target.is_inside_tree():
		a += _guidance(speed)
	velocity += a * dt
	var pos := prev + velocity * dt
	global_position = pos
	if velocity.length_squared() > 1.0:
		var want := Basis.looking_at(velocity.normalized(), Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
		global_transform.basis = global_transform.basis.slerp(want, clampf(NOSE_FOLLOW * dt, 0.0, 1.0)).orthonormalized()
	var hit := Ground.raycast(prev, pos, 60.0)
	if not hit.is_empty():
		_detonate(hit.position)
		return
	if _age > MAX_LIFE:
		queue_free()


## Steering toward the target: proportional navigation limited to max_g, plus some wing lift.
func _guidance(speed: float) -> Vector3:
	var pos := global_position
	var r := target.global_position - pos
	var dist := r.length()
	if dist < 1.0 or speed < 1.0:
		return Vector3.ZERO
	var fwd := velocity / speed
	var los := r / dist
	var tvel := Targeting.velocity_of(target)
	var vrel := tvel - velocity
	var omega := r.cross(vrel) / (dist * dist)
	var vc := maxf(-los.dot(vrel), speed * 0.5)
	var a := omega.cross(fwd) * (float(data.get("nav_gain", 3.0)) * vc)
	a -= fwd * a.dot(fwd)
	# Wings: counter some of gravity and bias toward the target in the vertical plane.
	a += (Vector3.UP - fwd * Vector3.UP.dot(fwd)) * GRAVITY * GLIDE_LIFT
	var lim := float(data.get("max_g", 3.0)) * GRAVITY
	if a.length() > lim:
		a = a.normalized() * lim
	return a


func _detonate(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	var radius := float(data.get("blast_radius", 40.0))
	Targeting.blast(get_tree(), at, radius, float(data.get("damage", 500.0)), shooter, team,
			clampf(radius * BLAST_SIZE_SCALE, 0.8, 3.0))
	detonated.emit(self)
	queue_free()
