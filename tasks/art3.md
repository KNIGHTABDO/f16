# Task: art pass 3 — hangar profile for the B-2 Spirit and roster coverage

Read tasks/art2.md, game/data/ui_art.json, game/data/roster.json and look at 2-3 existing aircraft profile images in game/assets/ui/
(same style, same size, same file naming, same ui_art.json keys).
1. Generate the aircraft profile image for `b2` (Northrop B-2 Spirit flying wing, dark grey, matching the existing profiles'
   style, framing and background exactly; use one existing profile as a style reference image).
2. Check every aircraft id in roster.json has a profile image + ui_art.json entry; generate any that are missing the same way.
3. Register them in ui_art.json. One `godot --headless --path game --import` check. Commit. Touch nothing else.
