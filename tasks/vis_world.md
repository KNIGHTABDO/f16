# Task: world visuals look stunning in flight (fix the washed-out white screen)

In-flight screenshots are almost pure white/pale blue: at 3000 ft over Gibraltar the terrain, sea, carrier and even the player's
aircraft in chase view are invisible (see screenshots/v1/08..13, 24 night is orange, 25 storm is white, 08 "golden hour" is not
golden). Only shots very low over terrain (19, 20, 23) show the ground, and even those are flat and washed out.
Find the causes and fix them: fog (depth/height fog density, volumetric fog, aerial perspective), cloud layer placement/density
(camera inside the cloud deck?), sky/tonemap/exposure/auto-exposure/glow, sun energy, time_of_day + weather settings actually
applied (tour sets them: check they reach Sky/Weather), chase camera framing (aircraft must be clearly visible, ~1/4 screen
width, slightly above and behind), aircraft materials (hangar shows f16c/b2 pure white: are textures/materials lost?).
Target look: modern combat flight sim marketing shots: crisp horizon, deep blue sky with haze near the horizon only, terrain
detail and satellite colour visible from altitude, glittering sea, dramatic golden hour, real dark night with moon/stars and
city lights, dark stormy sky with rain. Respect quality presets (high = pretty, low = fast for iPhone).
Files: game/core/world/*, game/autoload/settings.gd graphics bits, camera (game/core/camera/*), aircraft_visual.gd, env resources.
Do NOT touch game/ui/hud/*.

## How to see your work (you CAN view images: use the Read tool on a PNG)
Rendered runs work on this PC (DISPLAY is set). Take screenshots with the tour script:
`flock /tmp/godot-headless.lock godot --path game res://tools/screenshot_tour.tscn -- --out=/tmp/<yourjob>-shots`
First add an `--only=08,14,...` user arg to game/tools/screenshot_tour.gd so you can render just the shots you need (each full
tour takes minutes on this slow PC). The current v1 shots (the problems are visible in them) are in
/home/knight/Desktop/projects/f16/screenshots/v1/ (01..25, names describe the shot). Look at them first.
Iterate: change, render the few relevant shots, Read the PNGs, repeat. Max ~8 render rounds. Commit after each improvement.
Another agent is fixing the other half (world visuals vs HUD) at the same time: stay in your files.
