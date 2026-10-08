# Task: audio (SFX engine, sound library, Navidrome radio)

## Read first
`docs/ARCHITECTURE.md`, `game/autoload/sfx.gd`, `game/autoload/radio.gd` (stubs: keep every signature, implement them),
`game/autoload/settings.gd`, `game/autoload/events.gd`, `game/default_bus_layout.tres`.

## Files you own
- `game/autoload/sfx.gd`, `game/autoload/radio.gd` (replace the stubs, keep the public API, you may add functions)
- `game/core/aircraft/engine_audio.gd` (`class_name EngineAudio extends Node3D`): engine sound for one aircraft
- `game/assets/sounds/*` (the sound library), `game/assets/sounds/CREDITS.md` (source URL + license per file)
- `game/default_bus_layout.tres` (buses: Master, SFX, Music, Cockpit; add effects you need)
- `game/scenes/test_audio.tscn` + `game/core/missions/test_audio.gd`

## 1. Sound library (download real recordings; this is a personal-use game, quality matters most)
Find and download good free sounds from sources that need no login: Mixkit (`mixkit.co/free-sound-effects/`), OpenGameArt (CC0),
Pixabay sound effects, BBC Sound Effects (personal/education use: `sound-effects.bbcrewind.co.uk`, has real jets/aircraft),
SoundBible, the Internet Archive, Kenney. Trim, normalise (-1 dBFS peak, consistent loudness), loop seamlessly where needed with
ffmpeg (installed), save as `.ogg` (q 5) mono for 3D sounds, stereo for 2D. Required names (exact):
- engines (seamless loops): `engine_jet` (turbofan, steady high whine+roar), `engine_jet_ab` (afterburner roar layer),
  `engine_jet_far` (distant rumble), `engine_prop` (piston/radial), `engine_heli` (rotor), `wind` (cockpit airflow loop)
- guns: `gun_vulcan` (M61 brrrt loop), `gun_30mm` (loop), `gun_gau8` (loop), `gun_50cal` (loop), `gun_tail` (gun spin-down)
- weapons: `missile_launch`, `missile_flyby`, `rocket_launch`, `bomb_release`, `flare_launch`
- impacts: `explosion_small`, `explosion_large`, `explosion_far` (distant boom), `bullet_hit_metal`, `bullet_hit_ground`, `water_splash`
- cockpit / warnings: `lock_tone` (AIM-9 growl, loop), `lock_solid` (high tone loop), `rwr_ping`, `missile_warning` (fast beep loop),
  `stall_warning`, `gear`, `canopy`, `ui_click`, `ui_confirm`, `ui_back`, `hit_marker`, `kill_confirm`.
- voice warnings (female "Betty" style, 2D): `voice_pull_up`, `voice_altitude`, `voice_missile`, `voice_bingo_fuel`, `voice_overg`.
  If you cannot find real ones, synthesise them with a TTS available offline (`espeak-ng` if installed) or skip them and report it.
If a required sound is impossible to find, synthesise a decent substitute with numpy/ffmpeg (e.g. tones), and list it in your report.

## 2. Sfx autoload
- Pools: 24 `AudioStreamPlayer3D` + 12 `AudioStreamPlayer`; stream cache (load once). Unknown names: warn once, no crash.
- `play_3d`: attenuation inverse-square-ish, `max_distance`, doppler (camera doppler tracking on), low-pass with distance
  (distant explosions are muffled), random pitch +/-5%. Distant big explosions play `explosion_far` delayed by distance/340 m/s.
- `attach_loop` / `loop_2d` create dedicated players (not from the pool).
- Subscribe to `Events.explosion`, `Events.missile_launched`, `Events.flares_dropped` to play sounds automatically.
- `haptic()` -> `Input.vibrate_handheld(duration_ms, strength)` when `Settings.haptics`.
- Bus "Cockpit": when the camera is in cockpit mode (`Sfx.set_cockpit(true)`) apply a low-pass on SFX bus world sounds.

## 3. EngineAudio
For one Aircraft (read `aircraft.get_throttle()`, `is_afterburner()`, `get_speed_kmh()`, `data.engine`), layered loops: core engine
(pitch 0.8..1.4 with spool), afterburner layer, wind layer with speed, distant layer crossfade by distance to camera.
Volume/pitch smoothed. `setup(aircraft)`. The flight-core agent will add it to Aircraft later; do not edit aircraft.gd.

## 4. Radio (Navidrome / OpenSubsonic)
- Server from `Settings.navidrome_url/user/password`. Auth: `u`, `t = md5(password + salt)` (`String.md5_text()`), `s = salt`
  (random 12 chars), `v=1.16.1`, `c=KnightWings`, `f=json`. Endpoints: `/rest/ping.view`, `/rest/getRandomSongs.view?size=50`,
  `/rest/getStarred2.view`, `/rest/getPlaylists.view`, `/rest/getPlaylist.view?id=`, `/rest/getSongsByGenre.view?genre=&count=100`,
  `/rest/getGenres.view`, `/rest/stream.view?id=<id>&format=mp3&maxBitRate=192`.
- Godot cannot stream HTTP audio: download the whole MP3 with `HTTPRequest` (body size limit off, use `download_chunk_size` 64k),
  then `AudioStreamMP3.data = bytes`, play on the Music bus via an `AudioStreamPlayer`. Prefetch the next track while one plays;
  crossfade 2 s between tracks. Keep at most 2 tracks in memory.
- `Settings.radio_source`: "random", "starred", "playlist:<id>", "genre:<name>". Public helpers for the menu: `test_connection()`
  (async, emits `status_changed`), `fetch_playlists()` / `fetch_genres()` returning Arrays via signals `playlists_loaded(list)`,
  `genres_loaded(list)`, `cover_art_url(id)`.
- Graceful offline behaviour: if no server or errors, status "error: ..." and silence (no crash, no spam). Retry next track on failure.
- "Cockpit radio" flavour: optional subtle band-pass + noise on the Music bus when `Settings.radio_cockpit_fx` (add the setting via
  `set_meta` is NOT allowed; instead expose `Radio.cockpit_fx: bool` var).
- Duck music -6 dB while warnings play (`Sfx` voice warnings call `Radio.duck(seconds)`).

## Test scene
`test_audio.tscn`: plays each library sound in sequence (headless just checks they load), a moving AudioStreamPlayer3D flyby for
doppler, and if env vars `NAVIDROME_URL/USER/PASS` are set, connects and plays 10 s of a random song. Headless run: zero errors.
