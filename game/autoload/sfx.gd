extends Node
## Sound effects. STUB: replaced by the audio task. Keep these function signatures.
## Sounds live in res://assets/sounds/<name>.(ogg|wav|mp3); `name` is the file name without extension.


## One-shot non-positional sound (UI, cockpit, warnings).
func play_2d(_name: String, _volume_db := 0.0, _pitch := 1.0) -> void:
	pass


## One-shot positional sound at a LOCAL position (explosions, impacts, launches).
func play_3d(_name: String, _local_pos: Vector3, _volume_db := 0.0, _pitch := 1.0, _max_distance := 4000.0) -> void:
	pass


## Looping positional sound attached to `parent` (engines, guns, wind). Caller controls volume/pitch
## and frees it. Returns null in the stub.
func attach_loop(_name: String, _parent: Node3D, _volume_db := 0.0) -> AudioStreamPlayer3D:
	return null


## Looping non-positional sound (cockpit wind, missile lock tone). Caller controls/frees it.
func loop_2d(_name: String, _volume_db := 0.0) -> AudioStreamPlayer:
	return null


## Short phone vibration if Settings.haptics. strength 0..1.
func haptic(_strength := 0.5, _duration_ms := 30) -> void:
	pass
