extends Node
## Global signal bus. Emit from gameplay code, listen from HUD / audio / missions.

signal aircraft_destroyed(aircraft: Node3D, killer: Node)
signal target_destroyed(target: Node3D, killer: Node)
signal damaged(victim: Node3D, amount: float, source: Node)
signal weapon_fired(shooter: Node3D, weapon_id: String)
signal missile_launched(missile: Node3D, shooter: Node3D, target: Node3D)
## A missile is guiding on `target` (HUD shows a launch warning when target is the player).
signal missile_warning(missile: Node3D, target: Node3D)
signal flares_dropped(aircraft: Node3D)
signal explosion(world_local_pos: Vector3, size: float)
## Text shown in the HUD message strip.
signal mission_message(text: String, duration: float)
signal objective_updated(objectives: Array)
signal mission_ended(success: bool, stats: Dictionary)
signal player_spawned(aircraft: Node3D)
signal player_landed(on_carrier: bool)
