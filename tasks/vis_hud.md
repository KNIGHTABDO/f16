# Task: clean, professional in-flight HUD and touch layout

In-flight screenshots (screenshots/v1/08..25, look at 08 at full size) show a cluttered HUD:
- the mission briefing box stays in the middle of the screen over the speed/altitude readouts forever: show it for ~6 s at
  mission start (or in the loading screen / pause menu), then fade it out;
- the objective text appears twice (top banner + top-left line overlapping the minimap): keep one, clean placement;
- two control circles overlap bottom-left (virtual stick + another widget); touch buttons are scattered randomly on the right;
  arrange them in a tidy thumb-friendly cluster (fire/missile/flare/target/weapon-cycle on the right, throttle left, camera/look/
  radio/pause small along the top-right), consistent sizes, subtle translucent style, safe areas for iPhone notch;
- speed/alt readouts: proper ladder/tape style like a fighter HUD, green or cyan monochrome, crisp, not overlapping anything;
- top status line (mode, lives, time, score) small and unobtrusive; integrity bar + weapon panel aligned.
Keep everything readable on an iPhone 13 Pro Max (2778x1284) and iPad, and respect the controls editor layout data if one exists
(game/ui/controls_editor/*: default positions must match your new layout). Arcade HUD variant too.
Files: game/ui/hud/*, game/ui/controls_editor/* defaults, game/core/missions/mission_overlay.gd. Do NOT touch world/camera files.

## How to see your work (you CAN view images: use the Read tool on a PNG)
Rendered runs work on this PC (DISPLAY is set). Take screenshots with the tour script:
`flock /tmp/godot-headless.lock godot --path game res://tools/screenshot_tour.tscn -- --out=/tmp/<yourjob>-shots`
First add an `--only=08,14,...` user arg to game/tools/screenshot_tour.gd so you can render just the shots you need (each full
tour takes minutes on this slow PC). The current v1 shots (the problems are visible in them) are in
/home/knight/Desktop/projects/f16/screenshots/v1/ (01..25, names describe the shot). Look at them first.
Iterate: change, render the few relevant shots, Read the PNGs, repeat. Max ~8 render rounds. Commit after each improvement.
Another agent is fixing the other half (world visuals vs HUD) at the same time: stay in your files.
