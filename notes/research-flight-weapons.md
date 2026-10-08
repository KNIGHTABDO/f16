# Research: Flight model + combat design (Oct 2026)

Legend: [S] = from a cited source. [K] = my own knowledge/suggestion, NOT verified by search (verify before relying).
Note: web search returned little primary-source depth; seeker FOV, ballistics tables and SAM AI had no good hits.

## 1. Flight model: arcade vs War Thunder style

### How War Thunder tiers differ [S]
- Arcade = forgiving; Realistic = fewer aids, more authentic physics; Simulator = direct control, no HUD aids. Modeled: lift, drag, stalls, energy retention, altitude effects, G effects on pilot. Even SB is not DCS-level. ([flyawaysimulation](https://flyawaysimulation.com/ask/answers/microsoft-flight-simulator-vs-war-thunder/), [Steam discussion](https://steamcommunity.com/app/236390/discussions/0/827084776213102017))
- Energy fighting = trading speed and altitude (KE/PE); heavy planes use vertical/energy, nimble ones turn. Spitfire out-turns P-51 (aircraft-specific turn radius).
- G-limiter idea: limiting G conserves energy, esp. for delta wings ([WT forum](https://forum.warthunder.com/t/how-would-you-guys-feel-if-g-limiters-were-implemented/239554/20)).

### Core model a solo dev can build [S+K]
Single rigidbody, own gravity, forces computed in one script ([gamedev.net thread](https://gamedev.net/forums/topic/656699-modeling-some-flight-physics/), [Simple Airplane Physics Toolkit](https://assetstore-fallback.unity.com/packages/tools/physics/simple-airplane-physics-toolkit-lift-drag-thrust-146915), [itch RC dogfight lift curves](https://denisglabrecque.itch.io/rc-dogfight-sim/devlog/48980/using-sliders-and-lift-curves-in-unity), [aircraft physics preset arcade](https://maloke.itch.io/aircraft-physics)).
- Lift = 0.5 rho V^2 S CL(alpha); CL from a curve (linear to stall alpha, then drop). Drag = CD0 + k CL^2 (+ wave drag bump near Mach 1 [K]). Thrust table vs altitude/Mach (afterburner on/off).
- Stall [K]: past alpha_stall, cut CL, add nose-drop + buffet, recover when alpha falls.
- G-limit [K]: load factor n = L/W; clamp commanded pitch rate so n <= n_max with soft ramp; sustained vs instantaneous turn arises naturally from drag/thrust.
- Energy [K]: Es = h + V^2/2g. Turns bleed speed via induced drag; this gives energy fighting for free, no scripting.
- Rails/assist: layer control assists (auto-level, target-assist, yaw assist) on top; do not hack the physics ([gamedev.net reply](https://gamedev.net/forums/topic/656699-modeling-some-flight-physics/)).
- Recommended structure [K]: "Arcade" = rate-command controller (stick -> desired angular rates, clamped by G/alpha) over the same force model; "Realistic" = fewer assists, more stall/energy sensitivity. One force model, two control layers, per-aircraft data file (mass, S, CLa, CLmax, CD0, k, thrust curve, max roll/pitch/yaw rate, Gmax).
- Tune by feel: SGI-era warning that G/stall limits kick in too early if set purely by theory ([thread](https://mi.rro.rs/unixarchive-usenet/comp.sys.sgi/1989-February/001462.html)).
- Physics tick [K]: fixed step 60 to 120 Hz, render 120 Hz on ProMotion w/ interpolation. Mobile touch: tilt/virtual stick + throttle slider; assisted aim is essential.

### Open-source references
- **JSBSim** (C++, LGPL 2.1, XML aircraft, data-driven tables, bundled models from textbooks/NASA/public data, no proprietary data): [jsbsim.sourceforge.net](https://jsbsim.sourceforge.net/), repo [JSBSim-Team/jsbsim](https://github.com/JSBSim-Team/jsbsim). Handles aircraft, rockets, helicopters. Bundled aircraft set includes F-16, F-15, P-51D, A-10-type etc. [K, verify in repo `aircraft/` dir]. Good as DATA source (coefficients, inertia, thrust) to extract into a simple custom model; embedding the C++ lib in an iOS app is possible (LGPL: dynamic link/relink caveats on iOS, so prefer porting numbers) [K].
- **YASim** (FlightGear): geometry-driven solver, needs only basic params, easier to start, rough, needs tuning ([JSBSim vs YASim](https://wiki.flightgear.org/JSBSim_vs_YASim), [FDM](https://wiki.flightgear.org/Flight_dynamics_model), [YASim](https://wiki.flightgear.org/YASim)). Lesson: derive from wing area/span/weight/thrust rather than tables.
- Arcade references: Unity assets above; Ace Combat-style = rate-command + generous assists [K].
- Recommendation: write own ~500-line force model in the chosen engine; use JSBSim XML as tuning reference; avoid embedding JSBSim in v1.

### Realistic for solo?
Yes for: single-body, curve-based lift/drag, thrust tables, G/alpha limiters, simple propeller (thrust decays with speed, torque/P-factor optional), helicopter as separate simplified model (arcade tilt-rotor-disc: thrust vector tilts with cyclic, collective = vertical thrust). No for v1: flexible wings, full FCS laws, per-surface aero.

## 2. Aircraft performance data (public)
- General: [GlobalSecurity F-16](https://www.globalsecurity.org/military/systems/aircraft/f-16-specs.htm), [USAF ANG F-16 fact sheet (PDF)](https://www.138fw.ang.af.mil/Portals/34/documents/F-16%20Fact%20Sheet%20Small.pdf), [MILAVIA](https://milavia.net/aircraft/f-16/f-16_specs.htm), [CMANO DB](https://cmano-db.com/aircraft/158/), Wikipedia per-aircraft specs.
- F-16C data [S]: ~Mach 2 class, ceiling ~50,000 ft, +9 g, wing area ~300 sq ft (27.87 m2), span 32 ft 8 in (9.96 m), length 49 ft 5 in (15.06 m), thrust 27,000 lb (F100) to 29,500 lb (F110-129), empty 19,700 to 20,300 lb, MTOW 37,500 to 42,300 lb (variant dependent), T/W ~1.1 loaded-clean. Sources conflict by variant; pick one block and stay consistent.
- Where to get more [K]: JSBSim aircraft XML (inertia, coefficients); NASA NTRS reports (e.g. F-16 low-speed wind tunnel model, Nguyen 1979 NASA TP-1538 used in Stevens & Lewis); Stevens & Lewis "Aircraft Control and Simulation" appendix F-16 data; USAF Standard Aircraft Characteristics; flight manuals (Dash-1, P-51D/Spitfire pilot notes, Soviet-types via Wikipedia/Russian aviation sources); War Thunder wiki (old-wiki.warthunder.com) for in-game-style stats, but do not copy their data wholesale (balance values are proprietary). Not individually verified here for MiG-29, Su-27, A-10, P-51, Spitfire, Bf 109, AH-64, B-17: for each use Wikipedia spec box + one military/manufacturer source and record: mass, wing area, span, thrust/power, Vmax, ceiling, climb, max g, turn rate.
- Minimum per-aircraft data schema [K]: mass_empty/loaded, S, b, CLmax, CD0, k (or e), Vmax(alt), thrust(alt, Mach), Gmax, roll rate, corner speed, ceiling, guns/hardpoints.

## 3. Weapons

### Guns [S partly]
- M61 Vulcan: 4,000/6,000 rpm, muzzle ~1,050 m/s (3,450 ft/s, PGU-28) ([Wikipedia](https://en.wikipedia.org/wiki/M61_Vulcan), [IMFDB](https://www.imfdb.org/wiki/M61_Vulcan)).
- WWII 20 mm Hispano: ~600-850 rpm, 840-880 m/s ([HS.404](https://en.wikipedia.org/wiki/Hispano-Suiza_HS.404)). .50 BMG ~ 2,900 ft/s [K].
- Game implementation [K]: projectile = point + velocity inherited from shooter + muzzle velocity, gravity + optional drag, hitscan-with-travel-time via swept raycast per physics step (avoid tunnelling), tracer every Nth round, pooled objects, lead indicator (gunsight "pipper") computed from target velocity; convergence at ~400-600 m. Cheat for feel: slight auto-aim cone on touch.

### Missiles
- Specs [S]: AIM-9 up to Mach 2.5+, range ~ up to 35 km quoted (variant dependent; Wikipedia flagged), IR seeker, high off-boresight on L/M/X ([Wikipedia AIM-9](https://en.wikipedia.org/wiki/AIM-9_Sidewinder)). AIM-120: Mach 4, ranges AIM-120A/B ~75 km, C ~90 km, D ~130-160 km, inertial + terminal active radar ([Wikipedia AMRAAM](https://en.wikipedia.org/wiki/AIM-120_AMRAAM), [designation-systems](https://designation-systems.net/dusrm/m-120.html)). Seeker FOV not publicly confirmed in results; use game values (IR ~ 30 deg cone for old, 90+ off-boresight for modern) [K].
- Proportional navigation [S]: a_cmd = N * Vc * LOS_rate, N ~3-5; in games LOS computed directly from missile-target vectors, noise-free ([FLINT/ModDB PN tutorial with code](https://www.moddb.com/features/flint-lead-pursuit-guidance-principles), [PN intro](https://www.moddb.com/members/blahdy/blogs/gamedev-introduction-to-proportional-navigation-part-i), [AIAA paper](https://web.itu.edu.tr/~altilar/papers/AIAA2005b.pdf)).
- Game rules [K]: boost phase then coast (speed decays with drag), max lateral g (e.g. 30-40 g) and turn-rate limit => can be outmaneuvered when energy is gone; seeker cone loss of lock; IR: flares seduce with probability (decoy within cone, closer/hotter wins); radar: chaff + notching (target beaming reduces closing velocity below threshold); fuze proximity radius ~5-10 m; fuel/time-out 20-60 s.
- Radar lock [K]: scan cone, range by RCS class, time-to-lock 1-2 s, RWR "lock" warning tone for player, "missile launched" warning; semi-active needs continued lock, active (fire-and-forget) after pitbull range.
- Bombs [K]: unguided = ballistic body with drag + CCIP pipper (solve impact point numerically); guided (JDAM-like) = steer glide to target with PN or pure pursuit; splash radius damage falloff.
- Rockets [K]: short motor burn, unguided, salvo pods, spread cone.
- Flares/chaff [K]: cooldown/ammo, spawn decoy entities with lifetime ~3-5 s.
- Damage [K]: hitpoint zones (wing, engine, tail, cockpit) with simple effects (roll, power loss, fire). Skip full War Thunder module model in v1.

## 4. Enemy AI [S limited + K]
Sources: FSM-first prototypes with states patrol/pursue/avoid ground; list TRAVELING/EVADING/DOGFIGHT; warns EVADE vs terrain-avoidance oscillation ([UU Plane AI](https://babel.speldesign.uu.se/2016/02/10/5sd033-plane-ai-states-and-behaviour/), [gamedev.net AI blog](https://gamedev.net/blogs/entry/1190732-ai-is-a-bitch), [FSM article](https://gamedeveloper.com/programming/designing-a-simple-game-ai-using-finite-state-machines), [Unity forum](https://discussions.unity.com/t/need-some-suggestions-for-innovative-air-combat-game-template/649206)). No good source found for lead/lag pursuit or SAM AI; below is my design.
- Fighter AI FSM [K]: Patrol -> Detect -> Intercept (lead pursuit toward predicted point) -> Engage (gun if inside cone+range; missile if lock) -> Defend (flares/chaff, break turn when missile warning) -> Disengage/Extend (when low energy: dive, extend, re-enter) -> Terrain avoid (highest priority override with hysteresis to avoid flip-flopping). Use the same flight model through the same control interface as player (AI outputs stick/throttle), with skill parameters: reaction time, aim error, G tolerance (e.g., 70-100% of max), fire discipline. Add "difficulty = error + reaction delay", not cheating physics.
- Pursuit: lead pursuit to close, lag pursuit to avoid overshoot when closure high, pure when in gun range; vertical "high yo-yo" when overshoot (cheap trick: if closure>x and angle-off>y, pitch up).
- Bomber gunners: turret with accuracy decay and limited arcs (B-17).
- SAM [K]: state machine Idle -> Search (radar sweep, range R_detect by altitude, terrain masking via raycast) -> Track -> Launch (cooldown, min/max range, salvo of 1-2) -> Guide (PN missile) -> Reload. Low-flying => terrain masking = player counterplay. AAA: ballistic bursts with lead error that shrinks with tracking time; tracer + flak puffs near player (visual threat) with low hit chance. Use LOD AI (far entities tick at 1-5 Hz) to save CPU on mobile.

## 5. Legal (real names/shapes) [S partial; not legal advice]
- Textron/Bell v. Electronic Arts (Battlefield 3, 2012): EA claimed First Amendment/nominative fair use; court denied motion to dismiss Bell's counterclaims; settled, dismissed with prejudice. Earlier Bell vs EA 2008 settled with license for prior titles. Lawyers cite Rogers v. Grimaldi test, but outcomes show suits get filed and survive early stages. ([Stanford Law](https://law.stanford.edu/?p=14606), [AIN](https://ainonline.com/aviation-news/2012-01-20/ain-blog-video-game-maker-lawsuit-targets-textron-trademark-claims), [HeliHub](https://www.helihub.com/2012/08/01/ea-denied-motion-to-dismiss-bells-counter-claims-in-battlefield-helicopter-lawsuit/), [Patent Arcade](https://www.patentarcade.com/?p=783), [Cardozo](https://cardozoaelj.com/2012/03/20/saved-by-the-bell-why-courts-need-to-draw-the-line-on-trademark-use-in-video-games/)).
- Lockheed Martin vs I-Magic over F-22 games (1990s) ended in a license deal with NovaLogic ([GameSpot](https://www.gamespot.com/articles/i-magics-if-22-raptor-under-fire/1100-2466674/), [Raptor Finds A Home](https://www.gamespot.com/articles/raptor-finds-a-home/1100-2467609/)).
- Licensing practice: Ace Combat 6 credits list Lockheed Martin marks (F-16, F-22, F-117, SR-71, AC-130) and "Produced under license from Boeing" ([manual](https://manuall.co.uk/microsoft-xbox-360-ace-combat-6-fires-of-liberation/)); In-Fusio F-16 Air Fighter mobile game had an official F-16 license ([press release](https://gamedeveloper.com/press-release/in-fusio-brings-f-16-air-fighter-to-mobile-phones)); Boeing licensed Apache and FSX add-ons ([Military.com](https://365.military.com/off-duty/games/very-frustrating-apache-game-boeing-licensed.html), [SimFlight](https://www.simflight.com/?p=56606)). No public per-game license policy found: case-by-case.
- Assessment [K]: Personal, non-commercial, sideloaded, never distributed => practical risk ~nil. Risk appears on any public release (App Store, TestFlight link, GitHub releases of IPA, YouTube monetised gameplay, Patreon). Mitigations if ever shared: (1) disclaimer "not affiliated"; (2) avoid logos/emblems, manufacturer names (say "Fighting Falcon-class" or generic "F-16" only as nominative; safest is fictional names like "F-16-inspired FA-16"); (3) own 3D models (never rip Sketchfab/War Thunder/Ace Combat assets; check licences e.g. CC-BY); (4) airframe shapes are not copyrightable per se, trademarks/logos/trade dress are; (5) check Apple Guideline 5.2 (IP) if App Store. Names like "F-16", "Spitfire", "P-51 Mustang" (historic) are lower risk than active-production Lockheed/Boeing/Bell marks (Apache, Black Hawk, Osprey were litigated/licensed).

## Suggested roster
**v1 (4-5 aircraft, one per feel):**
- Jet fighter: F-16C (hero; arcade-friendly, 9g).
- Prop fighter: P-51D Mustang or Spitfire (tests prop model + guns-only).
- Attack/ground: A-10C (guns + bombs/rockets, slow, tough).
- Helicopter: AH-64 (separate simplified model) — or defer to v2.
- Bomber: B-17 as AI/target first (heavy bomber player flight later).
**v2:** F-15C, MiG-29, Su-27 (Soviet jets for asymmetry + opposing faction), Bf 109, Fw 190, Zero, F/A-18, B-17 playable, Mi-24/Ka-52, Tornado/Su-25.
Tiering: pick a matchmaking-free design (PvE sorties: air superiority, ground attack, intercept bombers, SEAD).

## Recommendation
1. Build one custom force-based flight model with data-driven aircraft files and two control layers (Arcade default, Realistic option). Use JSBSim XML only as number reference.
2. Start with F-16C + P-51D + A-10C, guns + IR missile (PN) + unguided bombs/rockets + flares; add radar missiles/chaff in v1.5.
3. Enemy AI via FSM using the same flight interface; SAM/AAA as separate simple FSM with terrain masking.
4. Legal: fine for personal sideload; use generic/fictional naming and original models if there is any chance of public release.
5. Verify before coding: aircraft data per plane (not individually confirmed here), seeker FOV values, and exact JSBSim aircraft list.
