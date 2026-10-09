class_name Targeting
extends RefCounted
## Static helpers for target selection and gun lead computation (game logic only, LOCAL scene coordinates).


const DRAG_SCALE := 0.0003  ## bomb drag: acceleration = drag * DRAG_SCALE * speed^2 (weapons.json drag)
const AIR_BLAST_RADIUS := 25.0


static func velocity_of(n: Node3D) -> Vector3:
	if n != null and is_instance_valid(n) and n.has_method("get_velocity"):
		return n.call("get_velocity")
	return Vector3.ZERO


static func kind_of(n: Node3D) -> String:
	if n != null and is_instance_valid(n) and n.has_method("get_target_kind"):
		return n.call("get_target_kind")
	return ""


static func is_valid_target(n: Node3D, team: int) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	if not n.is_in_group("damageable"):
		return false
	if "alive" in n and not n.alive:
		return false
	if "team" in n and n.team == team:
		return false
	return true


static func angle_off(origin: Vector3, forward: Vector3, point: Vector3) -> float:
	var d := point - origin
	if d.length_squared() < 0.01:
		return 0.0
	return forward.angle_to(d)


## Point to aim at so a round of speed `muzzle_speed` (plus shooter velocity) meets the target. Includes drop.
static func lead_point(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3,
		muzzle_speed: float) -> Vector3:
	var rel_v := target_vel - shooter_vel
	var t := shooter_pos.distance_to(target_pos) / maxf(muzzle_speed, 1.0)
	for _i in 4:
		var p := target_pos + rel_v * t
		t = shooter_pos.distance_to(p) / (muzzle_speed * 0.96)
	var aim := target_pos + rel_v * t
	aim.y += 0.5 * 9.81 * t * t
	return aim


## Ballistic impact point of a bomb released from `pos` with `vel` (drag as acceleration k*v^2/mass-scaled).
## Returns Vector3.INF when nothing is hit within 60 s.
static func bomb_impact(pos: Vector3, vel: Vector3, drag: float, step := 0.2) -> Vector3:
	var p := pos
	var v := vel
	var h0 := p.y - Ground.surface_at(p.x, p.z)
	for _i in 400:
		var speed := v.length()
		v += (Vector3(0, -9.81, 0) - v * (drag * DRAG_SCALE * speed)) * step
		var np := p + v * step
		var surf := Ground.surface_at(np.x, np.z)
		var h1 := np.y - surf
		if h1 <= 0.0:
			var f := h0 / maxf(h0 - h1, 0.0001)
			var out := p.lerp(np, clampf(f, 0.0, 1.0))
			out.y = Ground.surface_at(out.x, out.z)
			return out
		p = np
		h0 = h1
	return Vector3.INF


## Area damage: every enemy damageable within `radius` takes damage * (1 - (d/radius)^2). Same-team nodes are spared.
## Emits Events.explosion (Vfx picks the ground/water/air look, Sfx the sound). Returns the number of nodes hurt.
static func blast(tree: SceneTree, origin: Vector3, radius: float, damage: float, source: Node, team: int,
		size: float) -> int:
	Events.explosion.emit(origin, size)
	var hurt := 0
	for n in tree.get_nodes_in_group("damageable"):
		var node := n as Node3D
		if node == null or not is_valid_target(node, team):
			continue
		var reach := radius
		var hit_r := 0.0
		if node.has_method("get_hit_radius"):
			hit_r = float(node.call("get_hit_radius"))
		var d := maxf(node.global_position.distance_to(origin) - hit_r * 0.5, 0.0)
		if d >= reach:
			continue
		var f := 1.0 - (d / reach) * (d / reach)
		node.call("take_damage", damage * f, source, origin)
		hurt += 1
	return hurt
