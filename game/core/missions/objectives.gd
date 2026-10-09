class_name Objectives
extends RefCounted
## Ordered mission objectives. Each entry has an id, text, done flag and an optional marker: a world position, or a live
## node that the marker follows (the stored position is the fallback once the node is gone). to_array() is the payload for
## Events.objective_updated. Open objectives come first, because the HUD strip shows the first entry's text.

var _items: Array[Dictionary] = []


func add(id: String, text: String, pos := Vector3.ZERO, node: Node3D = null, has_marker := true) -> void:
	_items.append({"id": id, "text": text, "done": false, "pos": pos, "node": node, "marker": has_marker or node != null})


func clear() -> void:
	_items.clear()


func remove(id: String) -> void:
	for i in range(_items.size() - 1, -1, -1):
		if _items[i]["id"] == id:
			_items.remove_at(i)


func set_text(id: String, text: String) -> void:
	var item := find(id)
	if not item.is_empty():
		item["text"] = text


func set_marker(id: String, pos: Vector3, node: Node3D) -> void:
	var item := find(id)
	if not item.is_empty():
		item["pos"] = pos
		item["node"] = node
		item["marker"] = true


func complete(id: String) -> void:
	var item := find(id)
	if not item.is_empty():
		item["done"] = true


func find(id: String) -> Dictionary:
	for item in _items:
		if item["id"] == id:
			return item
	return {}


func is_done(id: String) -> bool:
	var item := find(id)
	return not item.is_empty() and bool(item["done"])


func open_count() -> int:
	var n := 0
	for item in _items:
		if not bool(item["done"]):
			n += 1
	return n


## Open objectives first, then done ones, each in the order they were added. Entries are copies.
func to_array() -> Array:
	var out: Array = []
	for want_done in [false, true]:
		for item in _items:
			if bool(item["done"]) == want_done:
				out.append(item.duplicate())
	return out


## Changes whenever an objective's text or done state changes. Used to emit the payload only when it differs.
func signature() -> String:
	var parts := PackedStringArray()
	for item in _items:
		parts.append("%s:%s" % [item["text"], item["done"]])
	return "|".join(parts)
