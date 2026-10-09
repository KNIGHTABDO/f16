class_name HUD
extends Control
## Knight Wings In-Flight Head-Up Display (HUD).
## Supports Realistic F-16 collimated green HUD and clean modern Arcade overlay.
## Includes RWR tactical scope, voice/tone warnings, rotating minimap,
## weapon inventory, damage indicators, radio ticker and the respawn banner.
## Mission objectives and messages are drawn by MissionOverlay, not here.
## Scales with Settings.hud_scale and places everything inside HUDLayout.safe_rect.

const BAND_H := 36.0  ## bottom band (integrity bar and weapons panel) height, above the screen edge

var respawn_in := -1.0  ## Seconds remaining until respawn when down

var _controller: PlayerController
var _camera: FlightCamera
var _aircraft: Aircraft

# Sub-components
var _hud_realistic: HUDRealistic
var _hud_arcade: HUDArcade
var _hud_rwr: HUDRWR
var _hud_warnings: HUDWarnings
var _hud_minimap: HUDMinimap
var _hud_weapons: HUDWeapons
var _hud_damage: HUDDamage
var _hud_radio_ticker: HUDRadioTicker
var _touch_controls: TouchControls

# Targets & Ballistics cache
var _target: Node3D
var _visible_targets: Array[Node3D] = []
var _incoming_missiles: Array[Node3D] = []
var _target_scan_timer := 0.0
var _font: Font


func setup(controller: PlayerController, camera: FlightCamera) -> void:
	_controller = controller
	_camera = camera
	if _controller != null:
		_aircraft = _controller.aircraft
	if _touch_controls != null:
		_touch_controls.setup(controller, camera)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

	# Build child components
	_hud_realistic = HUDRealistic.new()
	_hud_realistic.name = "HUDRealistic"
	_hud_realistic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud_realistic)

	_hud_arcade = HUDArcade.new()
	_hud_arcade.name = "HUDArcade"
	_hud_arcade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud_arcade)

	_touch_controls = TouchControls.new()
	_touch_controls.name = "TouchControls"
	if _controller != null:
		_touch_controls.setup(_controller, _camera)
	add_child(_touch_controls)

	_hud_damage = HUDDamage.new()
	_hud_damage.name = "HUDDamage"
	_hud_damage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud_damage)

	_hud_warnings = HUDWarnings.new()
	_hud_warnings.name = "HUDWarnings"
	_hud_warnings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud_warnings)

	_hud_rwr = HUDRWR.new()
	_hud_rwr.name = "HUDRWR"
	add_child(_hud_rwr)

	_hud_minimap = HUDMinimap.new()
	_hud_minimap.name = "HUDMinimap"
	add_child(_hud_minimap)

	_hud_weapons = HUDWeapons.new()
	_hud_weapons.name = "HUDWeapons"
	add_child(_hud_weapons)

	_hud_radio_ticker = HUDRadioTicker.new()
	_hud_radio_ticker.name = "HUDRadioTicker"
	add_child(_hud_radio_ticker)

	# Event listeners
	Events.damaged.connect(_on_damaged)
	Events.aircraft_destroyed.connect(_on_target_destroyed)
	Events.target_destroyed.connect(_on_target_destroyed)
	Events.missile_warning.connect(_on_missile_warning)
	Events.missile_launched.connect(_on_missile_launched)
	Settings.changed.connect(_on_settings_changed)

	_apply_settings()


func _exit_tree() -> void:
	if Events.damaged.is_connected(_on_damaged):
		Events.damaged.disconnect(_on_damaged)
	if Events.aircraft_destroyed.is_connected(_on_target_destroyed):
		Events.aircraft_destroyed.disconnect(_on_target_destroyed)
	if Events.target_destroyed.is_connected(_on_target_destroyed):
		Events.target_destroyed.disconnect(_on_target_destroyed)
	if Events.missile_warning.is_connected(_on_missile_warning):
		Events.missile_warning.disconnect(_on_missile_warning)
	if Events.missile_launched.is_connected(_on_missile_launched):
		Events.missile_launched.disconnect(_on_missile_launched)
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _process(delta: float) -> void:
	if _controller != null and _aircraft == null:
		_aircraft = _controller.aircraft

	# Periodic target scan (5 Hz)
	_target_scan_timer -= delta
	if _target_scan_timer <= 0.0:
		_target_scan_timer = 0.2
		_update_targets_and_ballistics()

	_layout_subviews()
	_update_subviews(delta)
	queue_redraw()


func _layout_subviews() -> void:
	var vp := get_viewport_rect().size
	var r := HUDLayout.safe_rect(vp)
	var s := Settings.hud_scale

	# Top left: minimap, with the RWR scope beside it (keeps the lower-left free for the stick)
	_hud_minimap.position = r.position
	_hud_rwr.position = Vector2(r.position.x + _hud_minimap.size.x + 10.0 * s, r.position.y)

	# Bottom band: weapons panel on the right shares its baseline with the integrity bar
	_hud_weapons.position = Vector2(r.end.x - _hud_weapons.size.x, r.end.y - _hud_weapons.size.y)

	# Radio ticker centered, just above the integrity bar
	_hud_radio_ticker.position = Vector2((vp.x - _hud_radio_ticker.size.x) * 0.5, r.end.y - BAND_H * s - _hud_radio_ticker.size.y - 6.0 * s)


func _update_subviews(delta: float) -> void:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return

	var is_realistic := (Settings.flight_mode == "realistic")
	_hud_realistic.visible = is_realistic
	_hud_arcade.visible = not is_realistic

	var hud_col := _get_hud_color()
	var s := Settings.hud_scale
	var cur_units: String = Settings.units

	# Cockpit view sizing
	var is_cockpit := false
	if _camera != null and _camera.get_mode() == FlightCamera.Mode.COCKPIT:
		is_cockpit = true
		var vp := get_viewport_rect().size
		var glass_w := vp.x * 0.38
		var glass_h := vp.y * 0.65
		_hud_realistic.hud_glass_rect = Rect2((vp.x - glass_w) * 0.5, vp.y * 0.16, glass_w, glass_h)
	else:
		_hud_realistic.hud_glass_rect = Rect2()

	_hud_realistic.is_cockpit = is_cockpit
	_hud_realistic.hud_color = hud_col
	_hud_realistic.hud_scale = s
	_hud_realistic.units = cur_units
	_hud_realistic.aircraft = _aircraft
	_hud_realistic.camera = _camera
	_hud_realistic.target_node = _target
	_hud_realistic.update_data(delta)

	_hud_arcade.hud_color = hud_col
	_hud_arcade.hud_scale = s
	_hud_arcade.units = cur_units
	_hud_arcade.aircraft = _aircraft
	_hud_arcade.camera = _camera
	_hud_arcade.controller = _controller
	_hud_arcade.target_node = _target
	_hud_arcade.visible_targets = _visible_targets
	_hud_arcade.incoming_missiles = _incoming_missiles
	_hud_arcade.update_data(delta)

	_hud_rwr.hud_color = hud_col
	_hud_rwr.hud_scale = s
	_hud_rwr.aircraft = _aircraft
	_hud_rwr.set_incoming_missiles(_incoming_missiles)
	_hud_rwr.visible = Settings.hud_show_rwr
	_hud_rwr.update_rwr(delta)

	_hud_minimap.hud_color = hud_col
	_hud_minimap.hud_scale = s
	_hud_minimap.aircraft = _aircraft
	_hud_minimap.update_minimap(delta)

	_hud_weapons.hud_color = hud_col
	_hud_weapons.hud_scale = s
	_hud_weapons.aircraft = _aircraft
	_hud_weapons.update_weapons()

	_hud_warnings.hud_scale = s
	_hud_warnings.aircraft = _aircraft
	_hud_warnings.incoming_missile_active = not _incoming_missiles.is_empty()
	_hud_warnings.update_warnings(delta)

	_hud_damage.hud_color = hud_col
	_hud_damage.hud_scale = s
	_hud_damage.aircraft = _aircraft
	_hud_damage.update_damage(delta)

	_hud_radio_ticker.hud_color = hud_col
	_hud_radio_ticker.hud_scale = s
	_hud_radio_ticker.update_ticker(delta)


func _update_targets_and_ballistics() -> void:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return

	# Duck-typed access to weapon system if attached
	var w_node: Node = _aircraft.get("weapons") if "weapons" in _aircraft else null
	if w_node == null:
		w_node = _aircraft.get_node_or_null("Weapons")

	# Target resolution
	if w_node != null and w_node.has_method("get_target"):
		_target = w_node.call("get_target")
	else:
		# Fallback target: nearest enemy in front
		_target = _find_nearest_enemy_target()

	# Visible targets (20 km scan)
	if w_node != null and w_node.has_method("get_visible_targets"):
		var tgts: Array = w_node.call("get_visible_targets")
		_visible_targets.assign(tgts)
	else:
		_visible_targets = _scan_visible_damageables()

	# Incoming missiles
	if w_node != null and w_node.has_method("get_incoming_missiles"):
		var msls: Array = w_node.call("get_incoming_missiles")
		_incoming_missiles.assign(msls)
	else:
		# Clean dead missiles
		var valid_m: Array[Node3D] = []
		for m in _incoming_missiles:
			if is_instance_valid(m):
				valid_m.append(m)
		_incoming_missiles = valid_m

	# Ballistics & Lead calculations
	if _target != null and is_instance_valid(_target):
		var target_vel: Vector3 = _target.get_velocity() if _target.has_method("get_velocity") else Vector3.ZERO
		var dist := _aircraft.global_position.distance_to(_target.global_position)
		var v_muzzle := 1050.0  # M61A1 Vulcan 20mm muzzle velocity
		var t_tof := dist / v_muzzle
		var future_tgt := _target.global_position + target_vel * t_tof
		var bullet_drop := Vector3(0.0, -0.5 * 9.81 * t_tof * t_tof, 0.0)

		if w_node != null and w_node.has_method("get_gun_lead_point"):
			var pt: Vector3 = w_node.call("get_gun_lead_point")
			if pt != Vector3.ZERO and pt != Vector3.INF:
				_hud_realistic.gun_lead_point = _aircraft.global_transform * pt
				_hud_arcade.gun_lead_point = _hud_realistic.gun_lead_point
			else:
				_hud_realistic.gun_lead_point = future_tgt - bullet_drop
				_hud_arcade.gun_lead_point = _hud_realistic.gun_lead_point
		else:
			_hud_realistic.gun_lead_point = future_tgt - bullet_drop
			_hud_arcade.gun_lead_point = _hud_realistic.gun_lead_point

		# Closure rate Vc
		var delta_pos := _target.global_position - _aircraft.global_position
		var delta_vel := _aircraft.get_velocity() - target_vel
		_hud_realistic.closure_rate = delta_vel.dot(delta_pos.normalized())

		# Lock state duck-typing
		if w_node != null and w_node.has_method("get_lock_state"):
			_hud_realistic.lock_state = int(w_node.call("get_lock_state"))
			_hud_arcade.lock_state = _hud_realistic.lock_state
		else:
			_hud_realistic.lock_state = 3 if dist < 8000.0 else 1
			_hud_arcade.lock_state = _hud_realistic.lock_state
	else:
		_hud_realistic.gun_lead_point = Vector3.ZERO
		_hud_arcade.gun_lead_point = Vector3.ZERO
		_hud_realistic.lock_state = 0
		_hud_arcade.lock_state = 0
		_hud_realistic.closure_rate = 0.0

	# CCIP calculation
	if w_node != null and w_node.has_method("get_ccip_point"):
		_hud_realistic.ccip_point = w_node.call("get_ccip_point")
	else:
		_hud_realistic.ccip_point = _integrate_ccip_impact()


func _integrate_ccip_impact() -> Vector3:
	var pos := _aircraft.global_position
	var vel := _aircraft.get_velocity()
	if vel.length() < 30.0 or pos.y <= 0.0:
		return Vector3.INF

	var dt := 0.1
	for step in 60:
		pos += vel * dt + Vector3(0.0, -0.5 * 9.81 * dt * dt, 0.0)
		vel += Vector3(0.0, -9.81 * dt, 0.0)
		if pos.y <= Ground.surface_at(pos.x, pos.z):
			return pos
	return Vector3.INF


func _find_nearest_enemy_target() -> Node3D:
	var best_node: Node3D = null
	var best_dist := 18000.0
	var own_pos := _aircraft.global_position
	var fwd := _aircraft.get_nose()

	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node) or node == _aircraft:
			continue
		var alive: bool = node.get("alive") if "alive" in node else true
		if not alive:
			continue
		if "team" in node and int(node.get("team")) == _aircraft.team:
			continue

		var n3d := node as Node3D
		if n3d == null:
			continue

		var dir: Vector3 = (n3d.global_position - own_pos).normalized()
		if fwd.dot(dir) < 0.35:
			continue  # Not in forward cone

		var dist: float = own_pos.distance_to(n3d.global_position)
		if dist < best_dist:
			best_dist = dist
			best_node = n3d

	return best_node


func _scan_visible_damageables() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var own_pos := _aircraft.global_position
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node) or node == _aircraft:
			continue
		var alive: bool = node.get("alive") if "alive" in node else true
		if not alive:
			continue
		var n3d := node as Node3D
		if n3d != null and own_pos.distance_to(n3d.global_position) <= 22000.0:
			out.append(n3d)
	return out


func _draw() -> void:
	var vp_size := size
	var s := Settings.hud_scale

	# Respawn Countdown Banner
	if respawn_in >= 0.0:
		var c := vp_size * 0.5
		var fs_down := int(38.0 * s)
		var fs_sub := int(22.0 * s)
		draw_rect(Rect2(c.x - 180 * s, c.y - 70 * s, 360 * s, 110 * s), Color(0.05, 0.01, 0.01, 0.9), true)
		draw_rect(Rect2(c.x - 180 * s, c.y - 70 * s, 360 * s, 110 * s), Color("#FF3838"), false, 2.0)
		draw_string(_font, Vector2(c.x, c.y - 20 * s), "AIRCRAFT DESTROYED", HORIZONTAL_ALIGNMENT_CENTER, int(340 * s), fs_down, Color("#FF3838"))
		draw_string(_font, Vector2(c.x, c.y + 25 * s), "RESPAWN IN %d" % ceili(respawn_in), HORIZONTAL_ALIGNMENT_CENTER, int(340 * s), fs_sub, Color("#FFFFFF"))


func _get_hud_color() -> Color:
	match Settings.hud_color:
		"green": return Color("#3CFF6A")
		"cyan": return Color("#3FD0FF")
		"amber": return Color("#FFB020")
		"white": return Color("#E8F0F8")
		"red": return Color("#FF3838")
		_: return Color("#3CFF6A")


func _on_damaged(victim: Node3D, _amount: float, source: Node) -> void:
	if source == _aircraft and victim != _aircraft:
		_hud_arcade.trigger_hit_marker(false)
		Sfx.play_2d("hit_marker", -2.0)


func _on_target_destroyed(target: Node3D, killer: Node) -> void:
	if killer == _aircraft:
		_hud_arcade.trigger_hit_marker(true)
		Sfx.play_2d("kill_confirm", 0.0)
		var tgt_name := target.name
		if target.has_method("get_target_kind"):
			tgt_name = target.get_target_kind()
		_hud_arcade.add_kill_feed("YOU", tgt_name, _hud_weapons.selected_name)


func _on_missile_launched(missile: Node3D, _shooter: Node3D, target: Node3D) -> void:
	if target == _aircraft and is_instance_valid(missile):
		if not _incoming_missiles.has(missile):
			_incoming_missiles.append(missile)


func _on_missile_warning(missile: Node3D, target: Node3D) -> void:
	if target == _aircraft and is_instance_valid(missile):
		if not _incoming_missiles.has(missile):
			_incoming_missiles.append(missile)


func _on_settings_changed(_key: String) -> void:
	_apply_settings()


func _apply_settings() -> void:
	modulate.a = Settings.hud_opacity
