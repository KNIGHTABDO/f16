# Job queue (the lead tick reads and updates this file)
Format: `- [ ] <name> | gemini|claude | <brief> | <base or worktree> | needs: <names merged first>`. Mark [~] running, [x] merged.
Gemini is the primary coder (check quota: scripts/job.sh gemini fails fast if agy errors -> use claude). Claude Sonnet for weapons-related work.

- [~] settings-menus | gemini | tasks/settings_menus.md | main | needs: -
- [~] roster | gemini | tasks/aircraft_roster.md | main | needs: -
- [~] world | gemini | tasks/cont_world_dressing.md | worktree-agent-aebba58123a873c40 | needs: -
- [~] models2 | gemini | tasks/cont_models2.md | worktree-agent-a5708db0613eb7421 | needs: -
- [~] weapons | claude | tasks/cont_weapons.md | .claude/worktrees/agent-ad75bf9a6376f65fc | needs: -
- [~] integration | claude | tasks/cont_aircraft_integration.md | .claude/worktrees/agent-a6259d2058290c99b | needs: -
- [ ] combat-units | gemini | tasks/combat_units.md | main | needs: weapons, integration
- [ ] ai | claude | tasks/ai.md | main | needs: combat-units
- [ ] hud-touch | gemini | tasks/hud_touch.md (lead writes it) | main | needs: weapons, integration, settings-menus
- [ ] terrain-polish | gemini | tasks/terrain_polish.md (lead writes it, from _integration_todo.md) | main | needs: integration
- [ ] modes-missions | gemini | tasks/modes_missions.md (lead writes it: Free Flight, Arcade/Realistic, missions on gibraltar+atlas) | main | needs: ai, hud-touch
- [ ] hangar-progression | gemini | tasks/hangar.md (lead writes it) | main | needs: roster, models2, settings-menus
- [ ] perf-ipa | claude | tasks/perf_ipa.md (lead writes it: A15 60fps, map compression, IPA < 150 MB) | main | needs: modes-missions
- [ ] playtest-v1 | lead | full headless playthrough, fix, tag v1.0 | main | needs: everything
