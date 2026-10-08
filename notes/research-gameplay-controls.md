# Research: Gameplay and Controls (mobile flight combat, solo, no servers)

Date: 2026-10-09. Method: ~8 web searches. Search quality was poor for War Thunder Mobile specifics (no mobile-specific sources found), so items marked (design inference) are my recommendations, not sourced facts. Verify against Apple docs before relying on exact numbers.

## 1. Controls: what the genre does

Sourced observations
- War Thunder (PC) has three control schemes: Mouse Aim (with "Instructor" auto-assist), Simplified, Full-Real. Mouse Aim/Simplified do not use analog stick input. Players report the Instructor layer gives mouse-aim users an aiming advantage and adds wobble for joystick users. Return-to-center of a virtual stick auto-levels the plane (auto-roll). Players tune dead zone and non-linearity. Sources: [MOZA guide](https://support.mozaracing.com/en/support/solutions/articles/70000684211-war-thunder), [Air Simulator Battles thread](https://forum.warthunder.com/t/air-simulator-battles-general-discussion/221725?page=4), [Steam discussion](https://steamcommunity.com/app/236390/discussions/0/4198997399064676852). Takeaway: "point where you want to go, an assist flies the plane" is the proven casual scheme; it is the right default for touch.
- Mobile jet games commonly offer both tilt (gyro) and on-screen stick: [Solo Jet](https://apps.apple.com/app/id557539556) (touch + gyro), [Squadron 303](https://mwm.ai/apps/squadron-303/1276579118) (tilt or stick), [Arvoch Space Combat](https://www.starwraith.com/arvochspacecombat/index.htm) (dual sticks, tilt, swipe, controller, mirrored sticks for left/right hand, auto-aim option, 3D radar).
- A fighter-jet brief layout: throttle slider on left, invisible pitch/roll stick on right, auto-stabilize when released, big Missile and small Gun buttons bottom-right (thumb reach), radar minimap top-right, lock-on after ~2 s in reticle: [Fighter Aircraft Pilot](https://www.seeles.ai/games/action/fighter-aircraft-pilot).
- Tilt is hard for some: Infinite Flight users find tilt difficult/uncomfortable on large devices, use touch for taxi, and ask for an on-screen joystick: [IF community](https://community.infiniteflight.com/t/difficult-to-fly-using-tilt-controls-any-ipad-controllers/110889), [IF touch thread](https://community.infiniteflight.com/t/i-wish-if-were-more-accommodating-to-touch-controls/1270324). Lesson: always offer a non-gyro option, calibration, and sensitivity sliders.
- Carrier Landings Pro store reviews: want choice of tilt vs on-screen buttons, and controls cut off by notch/rounded screens on newer iPhones ([listing](https://game-solver.com/carrier-landings-pro/)). Lesson: respect safe areas.
- Ace Combat 7 offers Standard (simplified, no full roll/yaw freedom) vs Expert (full pitch/roll/yaw); lock-on missiles are common to both; chaff/flare as a defensive action: [Shacknews](https://shacknews.com/article/109486/ace-combat-7-controls-playstation-4-and-xbox-one), [Push Square](https://www.pushsquare.com/news/2019/02/guide_ace_combat_7_skies_unknown_-_tips_and_tricks_for_beginners). Lesson: ship two schemes (Arcade assist / Advanced direct).

Recommended scheme set (design inference)
1. Arcade (default): right thumb drags a "target point" or virtual stick; an assist autopilot banks and pitches toward it (War Thunder mouse-aim style). Left thumb throttle slider. Auto-level on release. Auto-aim cone assist, soft lock-on for missiles (hold reticle on target ~1-2 s with tone).
2. Gyro option: tilt for pitch/roll, with calibration, deadzone, sensitivity, invert-Y, and on-screen "recenter" button; gyro fine-aims only when firing (gyro-aim-while-touching is common in console/mobile shooters).
3. Advanced: direct pitch/roll/yaw (virtual stick + rudder), no assist, for sim fans. Later.
4. Controller: GameController framework, see below.
5. Always: left-handed mirror, adjustable control opacity/size, per-plane response curve.

Combat aids
- Lead indicator (lead pip) computed from target velocity and bullet speed: pos + vel * t, with t = distance / bulletSpeed, iterated 2-3 times. Show only within range. Make it a difficulty toggle.
- Reticle + lock box on targets, off-screen arrows, missile warning tone, flares/chaff button, countermeasures cooldown.
- Cameras: chase cam (default), cockpit, gun/target cam, free look by drag on empty area, kill-cam replay (cheap and fun).

Controller and haptics
- GameController framework supports MFi/Xbox/PlayStation controllers on iOS; `GCController.haptics` yields Core Haptics engines per locality (iOS 14+); check `supportedLocalities` for the controller, since `supportsHaptics` refers to the device. Source: [WWDC20 10614](https://developer.apple.com/videos/play/wwdc2020/10614/), [GCDeviceHaptics](https://developer.apple.com/documentation/gamecontroller/gcdevicehaptics.md), [GCController.haptics](https://developer.apple.com/documentation/gamecontroller/gccontroller/haptics.md). I found no iOS 26-specific changes (not verified; check WWDC25 notes).
- Phone haptics: Core Haptics for gun rumble, missile launch thump, hit, stall buffet. Keep gun haptics rate-limited and optional. (design inference)
- Map: left stick pitch/roll, right stick camera/aim, triggers throttle/fire, face buttons missile/flare/target cycle.

## 2. Modes for a solo, no-server game (design inference, standard genre practice)
1. Free flight (any plane, any weather/time, no enemies). Cheap, great for testing flight model and map.
2. Target range: static/moving ground targets, ring/gate courses, scored accuracy.
3. Strike missions: destroy tanks, convoys, SAM sites, ships, bases; optional escort/recon. Mission = generator with templates (objective type + location + enemy mix + difficulty) so content scales without hand-authoring.
4. Dogfight vs AI waves (survival, escalating).
5. Base/airfield defense (waves of bombers and fighters).
6. Carrier landing (trap/catch trainer) and airfield landing.
7. Time trials / canyon runs with leaderboards via Game Center (optional, no own server).
8. Later: local co-op via MultipeerConnectivity or GameKit peer-to-peer (no server).
Bomber/helicopter missions use the same mission generator with different weapons (bomb sight, gunship mode).

## 3. Progression, fair and not pay-to-win
- War Thunder criticism (grind, paid research speed, premium vehicle prices, "pay to progress") is well documented: [grind thread](https://forum.warthunder.com/t/the-excessive-grind-is-ruining-the-war-thunder-experience/342508), [pay-to-win thread](https://forum.warthunder.com/t/war-thunder-is-pay-to-win/200614?page=22), [pricing/progression feedback](https://forum.warthunder.com/t/an-honest-feedback-on-the-current-state-of-war-thunder-br-compression-progression-and-pricing/338092). Since the game is free and personal, simply avoid all of it.
- Recommendation: start with all aircraft unlocked in Free Flight and Range (sandbox). Campaign/missions give soft goals: earn currency (credits) from missions to unlock cosmetics (skins/liveries) and optional loadouts; a light research tree by era/category (props -> early jets -> modern) with generous, fixed costs and no timers or premium currency. Mastery challenges ("destroy 5 SAM sites with guns") unlock skins. No randomness, no energy, no ads. Easy to relax later: a "Unlock all" toggle.
- Balance by mission difficulty, not matchmaking (no multiplayer, so no BR compression).

## 4. HUD/UI on iPhone 13 Pro Max (landscape)
- Screen 2778x1284 px, 428x926 pt portrait (so ~926x428 pt landscape), with notch on one side and home indicator; keep controls inside safe areas, draw backgrounds edge to edge. Sources (secondary, verify against Apple HIG): [44x44 pt minimum target](https://dequeuniversity.com/rules/attest-ios/1.0/touch-target-size), [HIG summary](https://skills.cat/skills/ehmo/platform-design-skills/ios-design-guidelines). In SwiftUI/Metal use safeAreaInsets; do not put fire/throttle under notch/home bar.
- Layout (design inference): left thumb throttle slider (vertical, low-left), right thumb flight area (right half, mostly invisible, with faint ring) plus Fire (large, bottom-right), Missile, Flare/Chaff, Target-cycle above it. Top-center: compass/heading strip. Top-right: radar/minimap. Top-left: pause, health/damage, ammo. Center: reticle, lead pip, lock box. Edge arrows for off-screen threats.
- Keep thumbs from covering the view: translucent controls, small HUD font but at least 11-12 pt, high-contrast outlines, color-blind-safe colors (not just red/green).
- Draw HUD with SwiftUI overlay over the render view (cheap to build) or in the engine; avoid full SwiftUI re-render at 120 Hz: update HUD at 30-60 Hz and keep it a thin layer.
- 120 Hz: set `CADisableMinimumFrameDurationOnPhone` and use CADisplayLink preferredFrameRateRange; target 60 fps locked, 120 fps only if cheap. iPad A16: larger layouts, same code.

## 5. Phased roadmap (solo dev + AI agents)
MVP (2-3 months of evenings)
- One plane (F-16 style), arcade assist flight model, one map region (about 20x20 km terrain tile or heightmap), free flight + target range with static tanks/buildings, guns + simple missiles, HUD, Arcade control scheme with throttle slider, gyro option, safe areas, settings screen, sound, pause. CI build + SideStore install working.
v1
- Strike mission generator (tanks, convoys, SAM, ships), AI fighters for dogfight waves, lead pip, lock-on, flares, damage model (HP zones), 3 planes (jet, prop, one more), carrier/airfield landing, controller + haptics, local save/progression with unlocks and skins, bigger map streamed in tiles.
v2
- Helicopter and bomber categories (bomb sight, gunship), base defense, time trials + Game Center leaderboards, advanced flight model option, weather/time of day, more maps, local co-op (peer-to-peer), replay/kill cam, iPad layouts.

Risks / advice (design inference): scope the physics as arcade-first; build the mission generator early; test on device every week through the CI; keep draw distance and terrain tile streaming budget for A15 (6 GB RAM) in mind; do not start with multiple vehicle classes.

## Gaps
- No usable sources found on War Thunder Mobile's actual touch controls, Sky Combat, World of Warplanes Blitz, or Modern Warplanes. Lead-indicator design not sourced. Recommend checking those games hands-on (free to download) and Apple HIG pages directly.
