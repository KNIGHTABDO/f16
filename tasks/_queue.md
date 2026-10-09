# Job queue (the lead tick reads and updates this file)
Format: `- [ ] <name> | gemini|claude | <brief> | <base or worktree> | needs: <names merged first>`. Mark [~] running, [x] merged.
Gemini is the primary coder (check quota: scripts/job.sh gemini fails fast if agy errors -> use `job.sh haiku`). Claude Sonnet (medium effort, use sparingly) only for weapons-related work.

- [x] settings-menus | gemini | tasks/settings_menus.md | main | needs: -
- [~] roster | gemini | tasks/aircraft_roster.md | main | needs: -
- [x] world | gemini | tasks/cont_world_dressing.md | worktree-agent-aebba58123a873c40 | needs: -
- [x] models2 (merged partial) 
- [~] models3 | haiku | tasks/cont2_models.md | .claude/worktrees/gem-gem-models2 | needs: -
- [~] weapons | claude | tasks/cont_weapons.md | .claude/worktrees/agent-ad75bf9a6376f65fc | needs: -
- [~] integration | haiku | tasks/cont2_integration.md | .claude/worktrees/gem-gem-integration | needs: -
- [x] art | gemini | tasks/art.md | main | needs: -
- [ ] art2 | gemini ONLY (image generation) | tasks/art2.md | main | needs: Gemini quota back (429 at 11:19 2026-10-09)
- [ ] combat-units | gemini | tasks/combat_units.md | main | needs: weapons, integration
- [ ] ai | claude | tasks/ai.md | main | needs: combat-units
- [ ] hud-touch | gemini | tasks/hud_touch.md | main | needs: weapons, integration, settings-menus
- [~] terrain-polish | gemini | tasks/terrain_polish.md | main | needs: -
- [ ] modes-missions | gemini | tasks/modes_missions.md | main | needs: ai, hud-touch
- [ ] hangar-progression | gemini | tasks/hangar.md | main | needs: roster, models2, settings-menus, art
- [ ] perf-ipa | claude | tasks/perf_ipa.md | main | needs: modes-missions
- [ ] playtest-v1 | lead | full headless playthrough, fix, tag v1.0 | main | needs: everything

NOTE 2026-10-09 11:20: Gemini credits exhausted (429). Use `scripts/job.sh haiku` (non-weapons) / `claude` (weapons) until `agy -p "Reply with just OK"` works again.
