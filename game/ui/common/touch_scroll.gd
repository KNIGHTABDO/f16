extends Node
## Finger-drag scrolling for every ScrollContainer in the game. Godot only scrolls a ScrollContainer when the drag
## starts on empty space; on a phone the rows are buttons and sliders, so the list could not be scrolled at all.
## Each ScrollContainer that enters the tree gets this as a child; it reads raw touches in _input, scrolls once the
## finger moved past DEADZONE, and swallows the release so the button under the finger doesn't fire after a scroll.

const DEADZONE := 14.0

var _scroll: ScrollContainer
var _start := Vector2.ZERO
var _index := -1
var _dragging := false


static func install(tree: SceneTree) -> void:
	tree.node_added.connect(func(n: Node) -> void:
		if n is ScrollContainer and not n.has_meta(&"touch_scroll"):
			n.set_meta(&"touch_scroll", true)
			var s := new()
			s.name = "TouchScroll"
			n.add_child.call_deferred(s, false, Node.INTERNAL_MODE_BACK))


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer


func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return
	# While a scroll drag is active, the touch's emulated mouse events must not reach the buttons/sliders below.
	if _dragging and (event is InputEventMouseMotion or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed and _index < 0 and _scroll.get_global_rect().has_point(event.position):
			_index = event.index
			_start = event.position
		elif not event.pressed and event.index == _index:
			_index = -1
			if _dragging:
				get_viewport().set_input_as_handled()
				# The emulated mouse release may arrive right after this touch release; keep eating it this frame.
				await get_tree().process_frame
				_dragging = false
	elif event is InputEventScreenDrag and event.index == _index:
		if not _dragging:
			var d: Vector2 = event.position - _start
			if d.length() <= DEADZONE:
				return
			var can_v := _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			var can_h := _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			# A sideways drag in a vertical list belongs to the slider under the finger, not to the scroll.
			if (can_v and absf(d.y) >= absf(d.x)) or (can_h and absf(d.x) > absf(d.y)):
				_dragging = true
			else:
				_index = -1
				return
		if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_scroll.scroll_vertical -= int(event.relative.y)
		if _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_scroll.scroll_horizontal -= int(event.relative.x)
		get_viewport().set_input_as_handled()
