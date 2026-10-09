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

## 4. Aircraft Renders (1024x512, RGBA PNG)

- **Source Models**: Official in-game GLB models from `res://assets/models/aircraft/<id>/<id>.glb`
- **Tool**: Blender 4.0.2 EEVEE offscreen renderer (`tools/render_aircraft.py`)
- **Pipeline**:
  1. Automated bounding box calculation and center normalization.
  2. Gear meshes hidden for streamlined in-flight profile.
  3. 3-quarter front perspective camera (72mm focal length, 62° azimuth, 15° elevation).
  4. Three-point cinematic lighting:
     - Warm amber key sunlight (`#FFEAC6`, 5.0 energy)
     - Cool naval ambient fill (`#66A6F2`, 2.5 energy)
     - Vivid cyan accent rim light (`#3FD0FF`, 4.0 energy)
  5. Antialiased rendering direct to 1024x512 with transparent background.
- **Aircraft Covered**:
  - `aircraft/f16c.png`: F-16C Fighting Falcon
  - `aircraft/ef2000.png`: Eurofighter Typhoon
  - `aircraft/f35a.png`: F-35A Lightning II
  - `aircraft/su27.png`: Sukhoi Su-27 Flanker
  - `aircraft/mig29.png`: Mikoyan MiG-29 Fulcrum
  - `aircraft/f15c.png`: F-15C Eagle
  - `aircraft/mig21bis.png`: MiG-21bis Fishbed

---

## 5. Game Mode Cards (768x432, JPEG q85)

- **Tool**: `tools/generate_mode_cards.py` with custom framing, contrast, and color grading from high-resolution cinematic aviation captures.
- **Modes**:
  - `modes/free_flight.jpg`: Serene solo/echelon cruise above golden cloud layer
  - `modes/instant_action.jpg`: Aggressive high-G bank into contested airspace
  - `modes/dogfight.jpg`: Close-quarters air combat scissors maneuver with afterburners
  - `modes/strike.jpg`: Low-altitude supersonic strike through red rock canyon
  - `modes/sead.jpg`: Transonic stealth penetration run with shockwave cone
  - `modes/anti_ship.jpg`: Sea-skimming maritime strike over deep ocean waters
  - `modes/convoy_hunt.jpg`: Desert canyon terrain-following attack vector
  - `modes/base_defense.jpg`: Night scramble interception from airbase taxiway
  - `modes/carrier_landing.jpg`: Twilight approach over coastal waters
  - `modes/time_trial.jpg`: High-speed navigation through Atlas mountain ridges
  - `modes/target_range.jpg`: Tactical reconnaissance bombing range overview

---

## 6. Icons (256x256, RGBA PNG)

- **Tool**: Procedural anti-aliased vector generator `tools/generate_ui_glyphs.py`
- **Style**: Flat, clean white `#FFFFFF` glyphs on transparent background, 4x supersampling downscaled via Lanczos filter.
- **Icons**:
  - `icons/settings.png`: 8-tooth mechanical gear
  - `icons/radio.png`: Broadcast antenna tower with radiating radio wave arcs
  - `icons/hangar.png`: Military aircraft hangar arched structure with tarmac line
  - `icons/map.png`: Three-panel folded tactical navigation map
  - `icons/play.png`: Triangle play glyph
  - `icons/pause.png`: Twin vertical rounded pause bars
  - `icons/missile.png`: 45-degree guided missile with fins
  - `icons/bomb.png`: Tear-drop aerial ordnance bomb
  - `icons/gun.png`: Crosshair with rotary cannon radial bores
  - `icons/flare.png`: 8-point countermeasure burst flare
  - `icons/rocket.png`: Unguided rocket with exhaust plume
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
