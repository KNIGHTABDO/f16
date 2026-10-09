# Task: fix round v1 (bugs found by the smoke pass)

Read tasks/_integration_todo.md (section "smoke-v1") and game/tools/smoke_modes.gd (the headless runner; reuse it to verify).
1. AI pilots die on their own: in dogfight all enemy fighters are "down" after ~12 s with 0 player kills and no hits. Find out why
   (terrain/ground collision on spawn, spawn altitude below terrain, bad initial speed -> stall, AIPilot control sign error,
   self-collision with wingmen...). Add a debug print of each AI's death cause in the smoke runner. Fix the root cause in
   ai_pilot.gd / spawner.gd / mission_generator.gd. AI must keep a safe altitude above Ground height (terrain avoidance:
   look-ahead raycast/height sample along velocity, pull up), and spawn at a sane speed/altitude. Re-run the dogfight smoke:
   enemies must survive >= 60 s when nobody shoots them.
2. A crash into terrain/collision by an AI should count as a kill for the player only if the player was engaging it
   within the last 10 s (common in flight games); otherwise it just removes the enemy.
3. time_trial: honour the START option (runway vs airborne) like the other modes.
4. Exit-time leaks: free what the level creates on unload (static pools / caches / signal connections to autoloads). Low priority:
   do the obvious ones only.
One import check + the smoke runner at the end. Commit after each fix. Do not add features.
