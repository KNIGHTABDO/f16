extends SceneTree
## One-off packer for the shipped map binaries. Run from the repo root, then commit the results:
##   godot --headless --path game --script ../tools/perf/pack_map_binaries.gd -- atlas gibraltar
## - height.r16 / landcover.u8 are rewritten as Godot zstd containers (FileAccess.open_compressed).
##   Ground.read_map_bytes() reads them back and still accepts raw files, and packing skips files that are
##   already packed, so the step is safe to re-run. Each file is verified by reading it back before it is kept.
## - color.jpg is re-encoded as JPEG at COLOR_PX into color.jpg.bin. The .bin extension stops the editor from
##   importing it (imported colour ships as VRAM ctex, several times larger). The map JSON color_file follows.

const COLOR_PX := 4096
const COLOR_QUALITY := 0.86
const MAPS_DIR := "res://assets/maps"
const DATA_DIR := "res://data/maps"


func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		push_error("usage: godot --headless --path game --script ../tools/perf/pack_map_binaries.gd -- <map_id> ...")
		quit(1)
		return
	var ok := true
	for id in ids:
		ok = _pack_map(id) and ok
	quit(0 if ok else 1)


func _pack_map(id: String) -> bool:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [DATA_DIR, id]))
	var ok := true
	var height_n := int(meta.height_n)
	ok = _pack_binary("%s/%s/height.r16" % [MAPS_DIR, id], height_n * height_n * 2) and ok
	var landcover_n := int(meta.get("landcover_n", 0))
	if landcover_n > 0:
		ok = _pack_binary("%s/%s/landcover.u8" % [MAPS_DIR, id], landcover_n * landcover_n) and ok
	return _pack_color(id) and ok


## Rewrites a raw map binary as a zstd container and checks the round trip against the original bytes.
func _pack_binary(path: String, expected_size: int) -> bool:
	var packed := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if packed != null:
		packed.close()
		print("%s: already packed" % path)
		return true
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() != expected_size:
		push_error("%s: %d bytes, expected %d" % [path, raw.size(), expected_size])
		return false
	var out := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if out == null:
		push_error("%s: cannot open for compressed write" % path)
		return false
	out.store_buffer(raw)
	out.close()
	var back := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var same := back != null and back.get_buffer(back.get_length()) == raw
	if back != null:
		back.close()
	if not same:
		FileAccess.open(path, FileAccess.WRITE).store_buffer(raw)
		push_error("%s: round trip failed, raw file restored" % path)
		return false
	print("%s: %d -> %d bytes" % [path, raw.size(), FileAccess.open(path, FileAccess.READ).get_length()])
	return true


## Re-encodes colour to COLOR_PX JPEG as color.jpg.bin and points the map JSON at it.
func _pack_color(id: String) -> bool:
	var src := "%s/%s/color.jpg" % [MAPS_DIR, id]
	if not FileAccess.file_exists(src):
		print("%s: no raw colour to convert" % id)
		return true
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		push_error("%s: cannot decode %s" % [id, src])
		return false
	var w := img.get_width()
	var h := img.get_height()
	var scale := float(COLOR_PX) / maxi(w, h)
	if scale < 1.0:
		img.resize(roundi(w * scale), roundi(h * scale), Image.INTERPOLATE_LANCZOS)
	var dst := "%s/%s/color.jpg.bin" % [MAPS_DIR, id]
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		push_error("%s: cannot write %s" % [id, dst])
		return false
	f.store_buffer(img.save_jpg_to_buffer(COLOR_QUALITY))
	f.close()
	var check := Image.new()
	if check.load_jpg_from_buffer(FileAccess.get_file_as_bytes(dst)) != OK or check.get_width() != img.get_width():
		push_error("%s: colour round trip failed" % id)
		return false
	DirAccess.remove_absolute(src)
	var json_path := "%s/%s.json" % [DATA_DIR, id]
	var text := FileAccess.get_file_as_string(json_path)
	var old_ref := "res://assets/maps/%s/color.jpg\"" % id
	FileAccess.open(json_path, FileAccess.WRITE).store_string(text.replace(old_ref, "res://assets/maps/%s/color.jpg.bin\"" % id))
	print("%s: colour %dx%d jpg q%.2f, %d bytes" % [id, check.get_width(), check.get_height(), COLOR_QUALITY, FileAccess.open(dst, FileAccess.READ).get_length()])
	return true
