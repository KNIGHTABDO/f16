class_name CarrierLandingMission
extends Mission
## Carrier landing: land on the carrier deck when it is at sea, otherwise on the friendly runway. A touchdown on the
## centreline with a gentle sink rate wins. A bad touchdown does not end the sortie: go round and try again.

const TOUCH_M := 1.0  ## m above the deck that counts as touching it
const AIRBORNE_M := 3.0  ## m above the surface before the next touchdown can count

var _carrier: Carrier = null
var _runway_start := Vector3.ZERO
var _runway_dir := Vector2.ZERO
var _sink := 0.0  ## m/s sink rate on the last tick in the air
var _touched := false  ## a touchdown has been judged and the aircraft has not left the surface yet


func _prepare() -> void:
	if plan["surface"] == "carrier":
		_carrier = _find_carrier()
	elif plan["surface"] == "runway":
		var rw: Dictionary = plan["runway"]
		var s: Vector3 = rw["start"]
		var e: Vector3 = rw["end"]
		_runway_start = s
		_runway_dir = Vector2(e.x - s.x, e.z - s.z).normalized()
	var target := "the carrier" if _carrier != null else String(plan["site_name"])
	objectives.add("land", "Land on %s" % target, plan["site"], null, true)


func _on_begin() -> void:
	if _carrier == null and plan["surface"] != "runway":
		finish(false, "No carrier or runway to land on")


func _tick(_delta: float) -> void:
	var p = _player()
	if p == null:
		return
	var gap := _gap_m(p)
	if not _is_touching(p, gap):
		if gap > AIRBORNE_M:
			_touched = false
		_sink = -p.velocity.y
		return
	if _touched:
		return
	_touched = true
	_judge(p)


## Height above the carrier deck, or above the ground on the runway. INF when the aircraft is not over the deck.
func _gap_m(p: Aircraft) -> float:
	if _carrier == null:
		return p.get_agl_m()
	var deck_y: float = _carrier.deck_height_at(p.global_position.x, p.global_position.z)
	return INF if is_nan(deck_y) else p.global_position.y - deck_y


func _is_touching(p: Aircraft, gap: float) -> bool:
	if _carrier != null:
		return gap <= TOUCH_M
	return p.is_on_ground()


func _judge(p: Aircraft) -> void:
	var sink := maxf(_sink, 0.0)
	if sink > float(tuning["max_sink_ms"]):
		say("Too hard: %.1f m/s sink. Go round." % sink)
		return
	var off := _offset_m(p)
	if off > float(tuning["centre_m"]):
		say("Off the centreline by %d m. Go round." % roundi(off))
		return
	if _carrier == null:
		var along := _along_m(p)
		if along < 0.0 or along > float(tuning["touchdown_zone_m"]):
			say("Touched down outside the zone. Go round.")
			return
	add_score(float(tuning["landing_pts"]))
	victory("Landed")


## Metres from the carrier centreline, or from the runway centreline.
func _offset_m(p: Aircraft) -> float:
	if _carrier != null:
		return absf(_carrier.to_local(p.global_position).x)
	var d := _runway_offset(p)
	return absf(d.x * _runway_dir.y - d.y * _runway_dir.x)


## Metres along the runway from its start, positive towards the far end.
func _along_m(p: Aircraft) -> float:
	return _runway_offset(p).dot(_runway_dir)


func _runway_offset(p: Aircraft) -> Vector2:
	var wp := WorldOrigin.to_world(p.position)
	return Vector2(wp.x - _runway_start.x, wp.z - _runway_start.z)


func _find_carrier() -> Carrier:
	for child in _level.world.get_children():
		if child is Carrier:
			return child
	return null
