
- 10:09 tick: 6 jobs still running (integration, weapons, models2, roster, settings-menus, world); nothing finished, nothing launched.
  No merges this tick, so no PLAN update, push or CI check.
  Overall % unchanged.

- 11:05 tick: 6 jobs running (integration, weapons, models2, roster, settings-menus, world, art); nothing finished.
  terrain-polish died unfinished: WIP committed on gem/gem-terrain-polish; relaunch deferred (job cap already reached).
  No merges; overall % unchanged.

- 12:15 tick: merged models3 (ah64, b17, fa18c, rafale); import + test_flight smoke OK.
  Running: weapons, art2, hud-touch (3/5); queue blocked on weapons for combat-units.
  Overall % unchanged.

- 13:06 tick: nothing finished; running ai, art3, modes-missions, perf-ipa (4/5).
  No merges/launches; only playtest-v1 left in queue (needs everything).
  Overall % unchanged.

- 14:05 tick: nothing finished; running smoke-v1, art3 (2/5), both just started.
  No merges/launches; playtest-v1 waits on them.
  Overall % unchanged.
