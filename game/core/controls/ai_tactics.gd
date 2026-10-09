class_name AITactics
extends RefCounted
## Stateless helpers for AIPilot: skill curves, terrain look-ahead, formation slots and weapon classification.

const REACTION_SLOW := 0.8  ## s, skill 0
const REACTION_FAST := 0.15  ## s, skill 1
const G_TOL_LOW := 6.0
const G_TOL_HIGH := 9.0
const GUN_TOL_LOW_DEG := 5.0  ## lead pip tolerance at skill 0
const GUN_TOL_HIGH_DEG := 1.4  ## and at skill 1
const SKILL_EASY := 0.2
const SKILL_NORMAL := 0.5
const SKILL_HARD := 0.75
const SKILL_ACE := 1.0
const FORMATION_MIN_SPACING := 45.0

const AIR_KINDS := ["air", "helicopter"]
const GROUND_KINDS := ["vehicle", "armor", "sam", "aaa", "ship", "structure"]
const AIR_MISSILES := ["ir_missile", "radar_missile"]


## GameState.difficulty ("easy", "normal", "hard", "ace") -> skill 0..1.
static func skill_for_difficulty(difficulty: String) -> float:
	match difficulty:
		"easy":
			return SKILL_EASY
		"hard":
			return SKILL_HARD
		"ace":
			return SKILL_ACE
	return SKILL_NORMAL


static func reaction_time(skill: float) -> float:
	return lerpf(REACTION_SLOW, REACTION_FAST, skill)


static func g_tolerance(skill: float) -> float:
	return lerpf(G_TOL_LOW, G_TOL_HIGH, skill)


static func gun_tolerance_rad(skill: float) -> float:
	return deg_to_rad(lerpf(GUN_TOL_LOW_DEG, GUN_TOL_HIGH_DEG, skill))


static func is_air_kind(kind: String) -> bool:
	return AIR_KINDS.has(kind)


static func is_ground_kind(kind: String) -> bool:
	return GROUND_KINDS.has(kind)


static func flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	if f.length_squared() < 1e-6:
		return Vector3(0.0, 0.0, -1.0)
	return f.normalized()


## Seconds until a straight flight along `vel` hits terrain or sea within `look_s`, and the surface normal
## there. Returns Vector4(time, nx, ny, nz); time is INF when the way is clear.
static func terrain_ahead(pos: Vector3, vel: Vector3, look_s: float, step: float) -> Vector4:
	var speed := vel.length()
	if speed < 1.0:
		return Vector4(INF, 0.0, 1.0, 0.0)
	var hit := Ground.raycast(pos, pos + vel * look_s, step)
	if hit.is_empty():
		return Vector4(INF, 0.0, 1.0, 0.0)
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	return Vector4(pos.distance_to(p) / speed, n.x, n.y, n.z)


## Climb direction that clears terrain: keeps the heading, bends away from the slope, pitched up by `pitch`.
static func climb_direction(vel: Vector3, normal: Vector3, pitch: float) -> Vector3:
	var h := flat(vel)
	var away := Vector3(normal.x, 0.0, normal.z)
	if away.length_squared() > 1e-4:
		h = (h + away.normalized() * 0.35).normalized()
	return h * cos(pitch) + Vector3.UP * sin(pitch)


## Formation slot offset in the leader's level frame: x right, y up, z back. Even slots on the right wing,
## odd on the left, each rank one spacing further out and back.
static func slot_offset(slot: int, spacing: float) -> Vector3:
	var side := 1.0 if slot % 2 == 0 else -1.0
	var rank := float((slot >> 1) + 1)
	return Vector3(side * rank * spacing, -2.0 * rank, rank * spacing * 0.9)


static func air_missile_type(t: String) -> bool:
	return AIR_MISSILES.has(t)


## Ground weapon preference: standoff first, then dive weapons.
static func ground_weapon_rank(t: String) -> int:
	match t:
		"ag_missile":
			return 0
		"guided_bomb":
			return 1
		"bomb":
			return 2
		"rocket":
			return 3
	return 99
