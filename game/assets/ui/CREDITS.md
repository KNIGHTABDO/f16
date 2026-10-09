# Knight Wings - Game Art Pack Credits & Generation Log

This document records the provenance, tools, and prompts used to create each game art asset in `res://assets/ui/`.

---

## 1. Menu Backgrounds (2532x1170, JPEG q85)

### `menu/bg_main.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) via agent API + `tools/resize_art.py`
- **Resolution**: 2532x1170, progressive JPEG q85
- **Prompt**:
  > "A cinematic, ultra-photorealistic wide aerial shot of a modern F-16 Fighting Falcon jet fighter banking steeply into a dramatic turn over the Strait of Gibraltar during sunset. The jet's sleek fuselage reflects warm golden-hour amber sunlight along its titanium canopy and wing edges, contrasting with deep navy shadows and the blue-gray sea below. Subtle heat shimmer and engine glow at the rear exhaust nozzle. Below, the shimmering waters of the strait stretch between Europe and Africa, with the iconic profile of the Rock of Gibraltar visible in the mid-distance on the Spanish side and the rugged coastline of Morocco visible across the water. Spectacular sunset sky with voluminous clouds illuminated in rich amber, burnished gold, and deep navy blue. Pristine aviation photography, cinematic color grading, photorealism, sharp focus, no text, no watermarks."

### `menu/bg_hangar.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) via agent API + `tools/resize_art.py`
- **Resolution**: 2532x1170, progressive JPEG q85
- **Prompt**:
  > "A cinematic, photorealistic wide shot inside a dim, ultra-modern military aircraft hangar interior at dusk. Empty polished concrete center stage with subtle floor reflections where a fighter jet would park. Dramatic amber rim lights and cool deep navy fill light, industrial architectural details, overhead gantry crane, maintenance gantries along the sides, moody atmosphere, volumetric light beams cutting through subtle atmospheric haze. No aircraft in the center, no people, no text, no watermarks."

### `menu/bg_settings.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) via agent API + `tools/resize_art.py`
- **Resolution**: 2532x1170, progressive JPEG q85
- **Prompt**:
  > "A cinematic, photorealistic shot inside a modern fighter jet cockpit looking forward at dusk. The cockpit interior, canopy frame, and multifunction displays glowing softly in cyan and amber, with the runway and twilight sky smoothly blurred in the background with shallow depth of field bokeh. Deep navy ambient lighting with warm amber accents, cinematic, ultra-clean aviation aesthetic. No pilot, no text, no watermarks."

### `menu/bg_results.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) via agent API + `tools/resize_art.py`
- **Resolution**: 2532x1170, progressive JPEG q85
- **Prompt**:
  > "A cinematic, photorealistic wide night shot of modern fighter jets taxiing slowly along an airbase taxiway under dramatic sodium amber lights and deep navy night sky. Runway edge lights glowing, heat distortion shimmer trailing from jet exhausts, wet tarmac reflecting runway lighting and dark sky. Cinematic color grade with deep navy shadows and golden-amber highlights. No text, no watermarks."

---

## 2. Loading Screens (2532x1170, JPEG q85)

### `loading/load_gibraltar.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A breathtaking, photorealistic, cinematic wide aerial landscape photograph of the Strait of Gibraltar at sunset. Dramatic sky with golden-hour amber clouds reflecting on the deep navy sea below. The iconic Rock of Gibraltar rises on the horizon with the rugged coastline of Morocco on the opposing shore. Warm amber and deep navy color grade, high altitude view, no aircraft, no text, no watermarks."

### `loading/load_atlas.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A breathtaking, photorealistic, cinematic wide aerial photograph of the High Atlas mountain range in Morocco. Majestic snow-capped peaks and jagged rocky ridges bathed in warm golden-hour late afternoon sunlight. Deep navy-blue shadows in the gorges and valleys, light atmospheric haze, dramatic cloud formation above. Rich amber and navy color grading, no aircraft, no text, no watermarks."

### `loading/load_sahara.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A breathtaking, photorealistic, cinematic wide aerial landscape photograph of the Sahara desert dunes in southern Morocco at golden hour sunset. Endless sweeping red-orange sand dunes with razor-sharp crests casting long deep blue-purple shadows. Warm golden amber sunlight glinting off sand ripples. Dramatic evening sky, pristine nature, no aircraft, no text, no watermarks."

### `loading/load_generic_1.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A cinematic, photorealistic wide shot of four modern fighter jets flying in tight echelon formation through dramatic towering sunset cloudscape. Warm amber golden-hour sunbeams illuminating cloud tops, deep navy sky above, condensation trails behind wingtips. High altitude, aviation photography, no text, no watermarks."

### `loading/load_generic_2.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A cinematic, photorealistic action shot of a sleek modern stealth fighter jet breaking the sound barrier, with a distinct transonic vapor cone shock collar forming around the fuselage as it flies fast over the deep blue ocean at golden hour. Warm amber reflections on the canopy and wings, dramatic spray, cinematic lighting, no text, no watermarks."

### `loading/load_generic_3.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A cinematic, photorealistic action shot of a modern fighter jet performing a high-speed low-altitude pass through a dramatic, rugged red-rock desert canyon in Morocco. Heat shimmer and shockwaves, dust kicking up from the canyon floor below, amber sunlight reflecting on the airframe against deep navy canyon shadows. High velocity dynamic motion, no text, no watermarks."

---

## 3. Map Select Thumbnails (768x432, JPEG q85)

### `maps/thumb_gibraltar.jpg`
- **Source**: Aerial reconnaissance render of Gibraltar Strait landscape generated via `gemini-3.1-flash-image`
- **Pipeline**: `tools/resize_art.py` centered 768x432 card crop

### `maps/thumb_atlas.jpg`
- **Source**: High Atlas snow peaks aerial landscape generated via `gemini-3.1-flash-image`
- **Pipeline**: `tools/resize_art.py` centered 768x432 card crop

### `maps/thumb_test.jpg`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "A high-altitude tactical satellite and aerial reconnaissance view of a military coastal airbase with intersecting concrete runways, taxiways, revetments, and radar domes along an arid coastline. Dramatic warm golden-hour lighting, deep navy sea, clear tactical aerial card style. No text, no watermarks."

---

## 4. Aircraft Profiles (1024x512, RGBA PNG)

- **Source Images**: Photoreal authentic 3/4-side and profile aviation photography of real aircraft in service with authentic liveries and accurate geometric silhouettes.
- **Pipeline**:
  1. Automated border flood-fill background keying and alpha extraction via `tools/resize_art.py` (`--key auto`).
  2. Tight foreground bounding box detection with antialiased edge preservation.
  3. Aspect-ratio containment scaling and centering within a 1024x512 transparent RGBA canvas.
  4. Optimized PNG compression.
- **Aircraft Covered (All 21 Roster & Model IDs)**:
  - `aircraft/a10c.png`: Fairchild Republic A-10C Thunderbolt II (30mm GAU-8, straight wing, twin high-bypass turbofans)
  - `aircraft/ah64.png`: Boeing AH-64 Apache Attack Helicopter (mast radar dome, tandem cockpit, chain gun)
  - `aircraft/b17.png`: Boeing B-17G Flying Fortress (WWII heavy bomber, 4 radial engines, glazed nose)
  - `aircraft/bf109.png`: Messerschmitt Bf 109 (WWII fighter, narrow-track gear, Daimler-Benz liquid-cooled V12)
  - `aircraft/ef2000.png`: Eurofighter Typhoon (canard delta wing, twin Eurojet EJ200 engines)
  - `aircraft/f14b.png`: Grumman F-14B Tomcat (twin-engine, variable-sweep wings, twin vertical stabilizers)
  - `aircraft/f15c.png`: McDonnell Douglas F-15C Eagle (air-superiority fighter, twin tails, shoulder-mounted wings)
  - `aircraft/f15e.png`: McDonnell Douglas F-15E Strike Eagle (conformal fuel tanks, dark tactical camo)
  - `aircraft/f16c.png`: General Dynamics F-16C Fighting Falcon (bubble canopy, ventral intake, blended wing-body)
  - `aircraft/f22a.png`: Lockheed Martin F-22A Raptor (stealth 5th-gen fighter, canted stabilizers, RAM coating)
  - `aircraft/f35a.png`: Lockheed Martin F-35A Lightning II (conventional takeoff stealth fighter, electro-optical EOTS)
  - `aircraft/fa18c.png`: McDonnell Douglas F/A-18C Hornet (naval strike fighter, twin canted tails, LEX)
  - `aircraft/ja37.png`: Saab JA 37 Viggen (Swedish canard delta wing, tactical camouflage)
  - `aircraft/mig21bis.png`: Mikoyan MiG-21bis Fishbed (supersonic delta fighter, conical nose shock intake)
  - `aircraft/mig29.png`: Mikoyan MiG-29 Fulcrum (twin-tail air-superiority fighter, leading-edge root extensions)
  - `aircraft/mirage2000.png`: Dassault Mirage 2000 (tailless delta wing, ventral drop tank, low-drag airframe)
  - `aircraft/p51d.png`: North American P-51D Mustang (WWII escort fighter, Packard V-1650 Merlin, teardrop canopy)
  - `aircraft/rafale.png`: Dassault Rafale (omnirole twin-engine fighter, close-coupled active canards)
  - `aircraft/spitfire.png`: Supermarine Spitfire Mk IX (WWII interceptor, iconic elliptical wings, Rolls-Royce Merlin)
  - `aircraft/su27.png`: Sukhoi Su-27 Flanker (heavy air-superiority fighter, curved LERX, tail stinger boom)
  - `aircraft/su57.png`: Sukhoi Su-57 Felon (5th-gen stealth multirole fighter, flattened fuselage, 3D vectoring)

---

## 5. Game Mode Cards (768x432, JPEG q85)

- **Art Pass 2 Update**: Every one of the 11 mode cards is a dedicated, unique action scene tailored to that specific game mode (no reuse of menu/loading screens).
- **Processing**: Sourced from high-definition public-domain military and combat captures + DeepMind Imagen generation, color-graded to the game's deep-navy/warm-amber palette, and processed via `tools/resize_art.py`.
- **Modes**:
  - `modes/free_flight.jpg`: Lone supersonic fighter jet cruising smoothly over snow-capped mountain peaks at golden hour
  - `modes/instant_action.jpg`: Intense close air-combat furball with multiple jets deploying arching golden flares into twilight (Generated via Google DeepMind Imagen `gemini-3.1-flash-image`)
  - `modes/dogfight.jpg`: Close-quarters air combat maneuvering with wingtip vortex condensation vapor streaming off lifting surfaces
  - `modes/strike.jpg`: Precision strike ordnance explosion detonating on target with violent fireball and dark smoke plume
  - `modes/sead.jpg`: Surface-to-air missile (SAM) battery launch and tactical engagement site at twilight
  - `modes/anti_ship.jpg`: Anti-ship cruise missile launch skimming low toward a maritime target in open waters
  - `modes/convoy_hunt.jpg`: A-10 Thunderbolt II low-angle strafing run firing high-explosive 30mm cannon burst
  - `modes/base_defense.jpg`: Interceptor jet scramble immediate takeoff from military airbase runway with afterburners ablaze
  - `modes/carrier_landing.jpg`: Naval strike fighter catching the arresting wire (tailhook trap) on an aircraft carrier flight deck
  - `modes/time_trial.jpg`: High-speed low-altitude navigation sprint through mountain pass and canyon terrain
  - `modes/target_range.jpg`: Aerial overview of a military weapons test and bombing target range with concentric rings and craters

---

## 6. Icons (256x256, RGBA PNG)

- **Tool**: Procedural anti-aliased vector generator `tools/generate_ui_glyphs.py`
- **Style**: Flat, clean white `#FFFFFF` glyphs on transparent background, 4x supersampling downscaled via Lanczos filter. Tested and verified for sharp, instantaneous legibility down to 48px.
- **Weapon Icons Redesign (Art Pass 2)**:
  - `icons/bomb.png`: Completely redesigned from the previous teardrop shape into an authentic aerial general-purpose bomb (heavy cylindrical body, rounded ballistic ogive nose, conical boat-tail, cruciform box stabilizer fins and outer box ring) angled 45° downward to unmistakably read as a gravity ordnance drop and eliminate fish-like appearance at 48px.
  - `icons/missile.png`: Redesigned with higher fineness ratio, sharp needle radome nose, forward delta canard control surfaces, large swept rear stabilizing fins, and rocket motor nozzle, angled 45° upward.
  - `icons/rocket.png`: Redesigned with conical warhead, narrow motor tube, straight stabilizing fins, and dynamic triple exhaust thrust plume for clear differentiation from missiles.
- **General Icons**:
  - `icons/settings.png`: 8-tooth mechanical gear
  - `icons/radio.png`: Broadcast antenna tower with radiating radio wave arcs
  - `icons/hangar.png`: Military aircraft hangar arched structure with tarmac line
  - `icons/map.png`: Three-panel folded tactical navigation map
  - `icons/play.png`: Triangle play glyph
  - `icons/pause.png`: Twin vertical rounded pause bars
  - `icons/gun.png`: Crosshair with rotary cannon radial bores
  - `icons/flare.png`: 8-point countermeasure burst flare
  - `icons/radar.png`: Concentric radar sweeps with 45° scanline
  - `icons/fuel.png`: Fuel drop fluid symbol
  - `icons/gear.png`: Retractable landing gear with strut and wheel
  - `icons/camera.png`: Rangefinder camera with optical lens
  - `icons/trophy.png`: Victory cup with pedestal and handles
  - `icons/credits.png`: Pilot identity card badge
  - `icons/lock.png`: Padlock shackle and body
  - `icons/back.png`: Navigation return chevron

---

## 7. HUD Symbols (128x128, RGBA PNG)

- **Tool**: Procedural vector renderer `tools/generate_ui_glyphs.py`
- **Color**: Military avionics green `#3CFF6A`
- **Symbols**:
  - `hud/rwr_threat_air.png`: Chevron threat bracket with 'A' marker
  - `hud/rwr_threat_sam.png`: Hexagonal surface-to-air threat icon with 'S'
  - `hud/target_box.png`: Segmented 4-corner targeting box with center pipper
  - `hud/lock_diamond.png`: Radar missile lock diamond with crosshair ticks
  - `hud/missile_warning.png`: Threat hazard triangle with exclamation mark

---

## 8. Tileable Livery Textures (1024x1024, JPEG q85)

- **Tool**: `tools/generate_liveries.py` using periodic Fourier harmonic toroidal synthesis and anisotropic Voronoi tessellation.
- **Specifications**: 100% mathematically seamless across horizontal and vertical edges, optimized for Godot triplanar/overlay shader projection.
- **Liveries**:
  - `liveries/f16c_rmaf_grey.jpg`: Royal Moroccan Air Force tactical grey camouflage
  - `liveries/f16c_desert_camo.jpg`: Moroccan Sahara 4-tone desert camouflage
  - `liveries/ef2000_nato_grey.jpg`: NATO low-visibility airframe pattern
  - `liveries/ef2000_splinter.jpg`: Aggressor sharp geometric angular splinter pattern
  - `liveries/f35a_stealth_ram.jpg`: Radar-absorbent material stealth panel facets
  - `liveries/f35a_aggressor.jpg`: Maritime naval aggressor splinter pattern
  - `liveries/mirage2000_desert.jpg`: Tactical desert ochre and sand pattern
  - `liveries/mirage2000_air_superiority.jpg`: Horizon blue-grey air-superiority scheme
  - `liveries/rafale_ocean_camo.jpg`: French Navy deep ocean maritime camouflage
  - `liveries/rafale_tiger_meet.jpg`: NATO Tiger Meet amber and carbon tiger striping

---

## 9. App Icon (1024x1024, PNG)

- **Files**: `game/assets/ui/icon/app_icon_1024.png` and `game/assets/icon_1024.png`
- **Tool**: Google DeepMind / Imagen (`gemini-3.1-flash-image`) + `tools/resize_art.py`
- **Prompt**:
  > "App icon for a modern combat flight simulator game named 'Knight Wings'. Bold, graphic, minimalist design. A sleek supersonic fighter jet silhouette ascending steeply at an angle, integrated with a clean modern geometric 'KW' monogram emblem. Deep navy background (#0B192C) with sharp cyan (#3FD0FF) neon rim lighting and a vibrant warm amber afterburner exhaust glow. High contrast, iconic, instantly recognizable and readable at 60px size on an iPhone home screen. Square composition, no text other than the stylized KW emblem, no watermarks, no rounded app store corners."
