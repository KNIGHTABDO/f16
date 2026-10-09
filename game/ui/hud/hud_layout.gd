class_name HUDLayout
extends RefCounted
## Shared screen layout: iPhone notch safe rect, fraction-to-pixel mapping, and touch defaults.
## HUD, touch controls and the controls editor all place things through here so they agree.

## Bump when the default touch cluster changes. Saved layouts without this version are ignored.
const TOUCH_VERSION := 2
const EDGE_PAD := 12.0

## Button positions are [fx, fy] fractions of the safe rect (mirrored in x when left-handed).
const TOUCH_DEFAULTS := {
	"stick": {"pos": [0.10, 0.74], "scale": 1.0, "opacity": 0.6},
	"throttle": {"pos": [0.035, 0.52], "scale": 1.0, "opacity": 0.6},
	"gun": {"pos": [0.925, 0.64], "scale": 1.0, "opacity": 0.75},
	"weapon": {"pos": [0.80, 0.76], "scale": 1.0, "opacity": 0.6},
	"cycle_target": {"pos": [0.665, 0.70], "scale": 1.0, "opacity": 0.6},
	"cycle_weapon": {"pos": [0.80, 0.52], "scale": 1.0, "opacity": 0.6},
	"flares": {"pos": [0.925, 0.40], "scale": 1.0, "opacity": 0.6},
	"airbrake": {"pos": [0.21, 0.84], "scale": 1.0, "opacity": 0.6},
	"gear": {"pos": [0.21, 0.62], "scale": 1.0, "opacity": 0.6},
	"camera": {"pos": [0.84, 0.09], "scale": 1.0, "opacity": 0.5},
	"look": {"pos": [0.78, 0.09], "scale": 1.0, "opacity": 0.5},
	"radio": {"pos": [0.90, 0.09], "scale": 1.0, "opacity": 0.5},
	"pause": {"pos": [0.965, 0.09], "scale": 1.0, "opacity": 0.5}
}

## Base radius in design units. Three tiers: fire, action, utility.
const TOUCH_RADIUS := {
	"stick": 56.0,
	"gun": 46.0,
	"weapon": 34.0,
	"cycle_weapon": 34.0,
	"cycle_target": 34.0,
	"flares": 34.0,
	"airbrake": 34.0,
	"gear": 34.0,
	"camera": 28.0,
	"look": 28.0,
	"radio": 28.0,
	"pause": 28.0
}

const THROTTLE_SIZE := Vector2(48.0, 150.0)


## Usable rect in logical pixels: the screen minus notch/home-indicator insets plus a small pad.
static func safe_rect(vp: Vector2) -> Rect2:
	var pad := Vector2(EDGE_PAD, EDGE_PAD)
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe_i := DisplayServer.get_display_safe_area()
	if screen.x <= 0.0 or screen.y <= 0.0 or safe_i.size.x <= 0 or safe_i.size.y <= 0:
		return Rect2(pad, vp - pad * 2.0)
	var design := Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	# Stretch "canvas_items" + "expand": logical units are pixels divided by this factor.
	var px := minf(screen.x / design.x, screen.y / design.y)
	var inset_l := maxf(float(safe_i.position.x), 0.0) / px
	var inset_t := maxf(float(safe_i.position.y), 0.0) / px
	var inset_r := maxf(screen.x - float(safe_i.end.x), 0.0) / px
	var inset_b := maxf(screen.y - float(safe_i.end.y), 0.0) / px
	var top_left := Vector2(inset_l, inset_t) + pad
	var bottom_right := vp - Vector2(inset_r, inset_b) - pad
	return Rect2(top_left, bottom_right - top_left)


static func to_px(frac: Array, rect: Rect2, mirror: bool = false) -> Vector2:
	var fx := float(frac[0])
	if mirror:
		fx = 1.0 - fx
	return rect.position + Vector2(fx, float(frac[1])) * rect.size


static func to_frac(px: Vector2, rect: Rect2, mirror: bool = false) -> Array:
	var f := (px - rect.position) / rect.size
	if mirror:
		f.x = 1.0 - f.x
	return [f.x, f.y]


static func base_size(key: String) -> Vector2:
	if key == "throttle":
		return THROTTLE_SIZE
	var r: float = TOUCH_RADIUS.get(key, 30.0)
	return Vector2(r * 2.0, r * 2.0)


## Returns a complete touch layout. Saved data is used only if it carries the current version,
## so older saved layouts (from before the new cluster) fall back to the new defaults.
static func active_touch_layout(saved: Dictionary) -> Dictionary:
	var use_saved := int(saved.get("_v", 0)) == TOUCH_VERSION
	var out := {"_v": TOUCH_VERSION}
	for k in TOUCH_DEFAULTS:
		if use_saved and saved.has(k):
			out[k] = (saved[k] as Dictionary).duplicate(true)
		else:
			out[k] = (TOUCH_DEFAULTS[k] as Dictionary).duplicate(true)
	return out
