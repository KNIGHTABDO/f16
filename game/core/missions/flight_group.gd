class_name FlightGroup
extends Node
## A leader and its wingmen. Gives each AIPilot a formation slot, spreads target picking over the members and
## promotes a wingman when the leader dies. The leader may be the player's aircraft or an AI aircraft.
## Add the node to the tree (any parent) so it can watch the leader.

const CHECK_PERIOD := 1.0

var leader: Node3D
var members: Array[AIPilot] = []

var _check_t := 0.0


func setup(leader_node: Node3D) -> void:
	leader = leader_node


## Adds a pilot as a wingman of the leader: assigns the next slot and makes the leader its escort.
func add_member(pilot: AIPilot) -> void:
	if members.has(pilot):
		return
	pilot.group = self
	pilot.formation_slot = members.size()
	pilot.set_escort(leader)
	members.append(pilot)


## Orders every member ("attack_my_target", "cover_me", "engage_free", "rejoin").
func order_all(cmd: String) -> void:
	for m in members:
		if is_instance_valid(m):
			m.order(cmd)


## Number of other members already assigned to `target`; AIPilot adds a penalty per assignee so the flight spreads out.
func load_of(target: Node3D, except: AIPilot) -> int:
	var n := 0
	for m in members:
		if m != except and is_instance_valid(m) and m.get_target() == target:
			n += 1
	return n


## Convenience for missions: the target `pilot` should attack next, or null.
func pick_target(pilot: AIPilot) -> Node3D:
	pilot.set_target(null)
	return pilot.get_target()


func alive_members() -> int:
	var n := 0
	for m in members:
		if is_instance_valid(m) and m.aircraft != null and m.aircraft.alive:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = CHECK_PERIOD
	if leader != null and is_instance_valid(leader) and (not ("alive" in leader) or leader.alive):
		return
	_promote()


func _promote() -> void:
	var new_leader: AIPilot = null
	var i := members.size() - 1
	while i >= 0:
		var m := members[i]
		if not is_instance_valid(m) or m.aircraft == null or not m.aircraft.alive:
			members.remove_at(i)
		i -= 1
	if members.is_empty():
		leader = null
		return
	new_leader = members[0]
	members.remove_at(0)
	leader = new_leader.aircraft
	new_leader.set_escort(null)
	new_leader.role = "fighter" if new_leader.role == "wingman" else new_leader.role
	for k in members.size():
		members[k].formation_slot = k
		members[k].set_escort(leader)
