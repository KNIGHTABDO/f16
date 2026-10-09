class_name DummyTarget
extends Node3D
## Test target that follows the Damageable contract (docs/ARCHITECTURE.md). Kinds: "air" (drone flying circles),
## "armor" / "vehicle" / "sam" (static box on the ground), "ship" (large box at sea level). Used by test scenes only.

signal destroyed(killer: Node)

const LAYER_AIRCRAFT := 2
const LAYER_GROUND := 4

var team := 1
var alive := true
var max_health := 100.0
var health := 100.0
var kind := "air"

var circle_center := Vector3.ZERO
var circle_radius := 1500.0
var speed := 150.0
var start_angle := 0.0  # radians along the circle at spawn
var _angle := 0.0
var _vel := Vector3.ZERO
var _size := Vector3(10, 3, 10)
var _hitbox: Hitbox


static func create(target_kind: String, target_team: int, hp: float, size: Vector3) -> DummyTarget:
	var d := DummyTarget.new()
	d.kind = target_kind
	d.team = target_team
	d.max_health = hp
	d.health = hp
	d._size = size
	d.name = "Dummy_%s" % target_kind
	return d


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("floating")
	add_to_group("team_%d" % team)
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.target = self
	_hitbox.collision_layer = LAYER_AIRCRAFT if kind == "air" else LAYER_GROUND
	_hitbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _size
	shape.shape = box
	_hitbox.add_child(shape)
	add_child(_hitbox)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.15) if kind == "air" else Color(0.35, 0.4, 0.25)
	bm.material = mat
	add_child(mesh)
	if kind == "air":
		_angle = start_angle
		_place_on_circle(_angle)


func take_damage(amount: float, source: Node, hit_pos: Vector3) -> void:
	if not alive:
		return
	health = maxf(health - amount, 0.0)
	Events.damaged.emit(self, amount, source)
	if health <= 0.0:
		alive = false
		remove_from_group("damageable")
		_hitbox.monitorable = false
		Events.target_destroyed.emit(self, source)
		Events.explosion.emit(hit_pos if hit_pos != Vector3.ZERO else global_position, 1.5)
		destroyed.emit(source)
		visible = false
		get_tree().create_timer(2.0).timeout.connect(queue_free)


func get_target_kind() -> String:
	return kind


func get_velocity() -> Vector3:
	return _vel


func get_hit_radius() -> float:
	return maxf(_size.x, _size.z) * 0.5


func _place_on_circle(a: float) -> void:
	position = circle_center + Vector3(sin(a), 0.0, cos(a)) * circle_radius


func _physics_process(delta: float) -> void:
	if not alive or kind != "air":
		return
	var prev := position
	_angle += speed / circle_radius * delta
	_place_on_circle(_angle)
	_vel = (position - prev) / delta
	look_at(position + _vel, Vector3.UP)
