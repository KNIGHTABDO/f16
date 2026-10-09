# Job queue (the lead tick reads and updates this file)
Format: `- [ ] <name> | gemini|claude | <brief> | <base or worktree> | needs: <names merged first>`. Mark [~] running, [x] merged.
Run Gemini AND Haiku (job.sh haiku = Haiku 5.5 xhigh) in parallel; both are primary. Gemini: image generation + bulky multi-file jobs. Haiku: focused code jobs. Claude Sonnet (medium, sparingly) only for weapons/combat-AI work. Check Gemini quota with /usage in the agy TUI.

- [x] settings-menus | gemini | tasks/settings_menus.md | main | needs: -
- [x] roster | gemini | tasks/aircraft_roster.md | main | needs: -
- [x] world | gemini | tasks/cont_world_dressing.md | worktree-agent-aebba58123a873c40 | needs: -
- [x] models2 (merged partial) 
- [x] models3 | haiku | tasks/cont2_models.md | .claude/worktrees/gem-gem-models2 | needs: -
- [x] weapons | claude | tasks/cont_weapons.md | .claude/worktrees/agent-ad75bf9a6376f65fc | needs: -
- [x] integration | haiku | tasks/cont2_integration.md | .claude/worktrees/gem-gem-integration | needs: -
- [x] art | gemini | tasks/art.md | main | needs: -
- [x] art2 | gemini | tasks/art2.md | main | needs: art
- [~] combat-units | gemini | tasks/combat_units.md | main | needs: weapons, integration
- [~] ai | gemini | tasks/ai.md | main | needs: combat-units
- [x] hud-touch | gemini | tasks/hud_touch.md | main | needs: weapons, integration, settings-menus
- [x] terrain-polish | haiku | tasks/cont_terrain_polish.md | .claude/worktrees/gem-gem-terrain-polish | needs: -
- [~] modes-missions | haiku | tasks/modes_missions.md | main | needs: ai, hud-touch
- [x] hangar-progression | haiku | tasks/hangar.md | .claude/worktrees/hk-hangar (branch hk/hangar) | needs: roster, models2, settings-menus, art
- [x] b2 | haiku | tasks/b2.md | .claude/worktrees/hk-b2 (branch hk/b2) | needs: -
- [~] art3 | gemini | tasks/art3.md | main | needs: b2
- [~] perf-ipa | haiku | tasks/perf_ipa.md | main | needs: - (parallel)
- [ ] playtest-v1 | lead | full headless playthrough, fix, tag v1.0 | main | needs: everything

NOTE 2026-10-09: agy is on abdo.knight7@gmail.com; Gemini weekly quota 95% left (check with /usage in agy TUI; "AI credits" in the status bar is unrelated). If 429 again: Use `scripts/job.sh haiku` (non-weapons) / `claude` (weapons) until `agy -p "Reply with just OK"` works again.
