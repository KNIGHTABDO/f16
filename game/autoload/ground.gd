extends Node
## CPU-side terrain queries for the loaded map (height, water, land cover). All functions take
## LOCAL scene coordinates (see WorldOrigin) unless the name says world.
##
## Map files (written by tools/build_map.py), in res://assets/maps/<id>/:
## - height.r16  : N*N little-endian uint16, row-major, row 0 = north edge, col 0 = west edge.
##                 height_m = height_min + v / 65535 * (height_max - height_min)
## - landcover.u8: L*L uint8 land-cover classes (Ground.LC_*), same orientation.
## - color.png   : satellite colour for the whole map (used by the terrain shader only).
## Map metadata in res://data/maps/<id>.json (see Ground.load_map).

const LC_WATER := 0
const LC_TREES := 1
const LC_SHRUB := 2
const LC_GRASS := 3
const LC_CROP := 4
const LC_URBAN := 5
const LC_BARE := 6  # sand / rock / desert
const LC_SNOW := 7
const LC_WETLAND := 8

var map_id := ""
var meta: Dictionary = {}
var size_m := 0.0  # map edge length, meters; map spans [-size_m/2, size_m/2] on X and Z (world)
var sea_level := 0.0
var height_min := 0.0
var height_max := 1.0
var height_n := 0
var landcover_n := 0
var _heights := PackedByteArray()
var _landcover := PackedByteArray()


func is_loaded() -> bool:
	return height_n > 0


## Loads data/maps/<id>.json and the binary files it references. Returns false on error.
func load_map(id: String) -> bool:
	var f := FileAccess.open("res://data/maps/%s.json" % id, FileAccess.READ)
	if f == null:
		push_error("Ground: missing map %s" % id)
		return false
	meta = JSON.parse_string(f.get_as_text())
	map_id = id
	size_m = float(meta.size_m)
	sea_level = float(meta.get("sea_level", 0.0))
	height_min = float(meta.height_min)
	height_max = float(meta.height_max)
	height_n = int(meta.height_n)
	landcover_n = int(meta.get("landcover_n", 0))
	_heights = FileAccess.get_file_as_bytes(meta.height_file)
	if _heights.size() != height_n * height_n * 2:
		push_error("Ground: height file size mismatch")
		height_n = 0
		return false
	if landcover_n > 0:
		_landcover = FileAccess.get_file_as_bytes(meta.landcover_file)
	return true


## Terrain height ASL in meters at a local position (bilinear). Below sea_level means sea floor.
func height_at(local_x: float, local_z: float) -> float:
	return world_height_at(WorldOrigin.world_x(local_x), WorldOrigin.world_z(local_z))


func world_height_at(wx: float, wz: float) -> float:
	if height_n == 0:
		return 0.0
	var n1 := height_n - 1
	var u := clampf((wx / size_m + 0.5) * n1, 0.0, n1)
	var v := clampf((wz / size_m + 0.5) * n1, 0.0, n1)
	var x0 := mini(int(u), n1 - 1)
	var y0 := mini(int(v), n1 - 1)
	var fx := u - x0
	var fy := v - y0
	var i := (y0 * height_n + x0) * 2
	var h00 := _heights.decode_u16(i)
	var h10 := _heights.decode_u16(i + 2)
	var j := i + height_n * 2
	var h01 := _heights.decode_u16(j)
	var h11 := _heights.decode_u16(j + 2)
	var hv := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)
	return height_min + hv / 65535.0 * (height_max - height_min)


## Height of the surface you can collide with: max(terrain, sea level).
func surface_at(local_x: float, local_z: float) -> float:
	return maxf(height_at(local_x, local_z), sea_level)


func normal_at(local_x: float, local_z: float, step := 30.0) -> Vector3:
	var hl := height_at(local_x - step, local_z)
	var hr := height_at(local_x + step, local_z)
	var hd := height_at(local_x, local_z - step)
	var hu := height_at(local_x, local_z + step)
	return Vector3(hl - hr, 2.0 * step, hd - hu).normalized()


func is_water(local_x: float, local_z: float) -> bool:
	return height_at(local_x, local_z) <= sea_level or landcover_at(local_x, local_z) == LC_WATER


func landcover_at(local_x: float, local_z: float) -> int:
	if landcover_n == 0:
		return LC_GRASS
	var wx := WorldOrigin.world_x(local_x)
	var wz := WorldOrigin.world_z(local_z)
	var n1 := landcover_n - 1
	var u := clampi(int(round((wx / size_m + 0.5) * n1)), 0, n1)
	var v := clampi(int(round((wz / size_m + 0.5) * n1)), 0, n1)
	return _landcover[v * landcover_n + u]


## True if `local_pos` is inside the playable map square (with margin in meters).
func in_bounds(local_pos: Vector3, margin := 0.0) -> bool:
	var half := size_m * 0.5 - margin
	return absf(WorldOrigin.world_x(local_pos.x)) < half and absf(WorldOrigin.world_z(local_pos.z)) < half


## Segment vs terrain/sea. Returns {} or {"position": Vector3, "normal": Vector3}. Coarse march + refine.
func raycast(from: Vector3, to: Vector3, step := 25.0) -> Dictionary:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return {}
	var steps := maxi(1, int(ceil(length / step)))
	var prev := from
	var prev_above := from.y - surface_at(from.x, from.z)
	for k in range(1, steps + 1):
		var p := from + dir * (float(k) / steps)
		var above := p.y - surface_at(p.x, p.z)
		if above <= 0.0:
			var t := prev_above / maxf(prev_above - above, 0.0001)
			var hit := prev.lerp(p, t)
			hit.y = surface_at(hit.x, hit.z)
			return {"position": hit, "normal": normal_at(hit.x, hit.z)}
		prev = p
		prev_above = above
	return {}
