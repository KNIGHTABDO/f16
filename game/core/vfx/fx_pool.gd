class_name FxPool
extends RefCounted
## Reuses effect nodes instead of instantiating them per spawn.
## take() returns a node that is NOT in the tree (the caller adds it where it belongs).
## give() takes a node out of the tree and keeps it for reuse. Nodes stay referenced here, so they are not freed.

var _factory: Callable
var _free: Array[Node3D] = []
var _created: int = 0


func _init(factory: Callable) -> void:
	_factory = factory


func take() -> Node3D:
	while not _free.is_empty():
		var n: Node3D = _free.pop_back()
		if is_instance_valid(n):
			return n
	_created += 1
	return _factory.call() as Node3D


func give(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.visible = false
	_free.append(node)


## Number of nodes ever created by this pool (diagnostics).
func created_count() -> int:
	return _created
