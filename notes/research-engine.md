# Engine / tech stack research (Linux-only dev + GitHub Actions macOS + SideStore)
Date: 2026-10-09. Search-based; items marked (UNVERIFIED) were not confirmed by a source.

## Ranked recommendation
1. **Godot 4.6.x (Mobile renderer, Metal) - recommended.** Text-based scenes (.tscn/.gd) that AI agents edit well, Linux editor + `--headless` export, full desktop play-testing on Linux, free MIT, small app. Build pipeline: do the whole export + xcodebuild on a macOS runner (safest).
2. **Unity 6.3 LTS** - best proven mobile 3D/terrain ecosystem, but Linux-editor iOS support is doubtful, scenes are YAML but editor-centric, heavier. Fall back if Godot terrain perf fails the prototype.
3. **Bevy (Rust)** - fully code/text, Linux desktop iteration, iOS officially tested, but no editor, immature mobile tooling, long compile times; hard for a zero-experience dev.
4. **Native Swift + Metal / RealityKit** - cannot test on Linux at all (every iteration = CI + sideload); SceneKit is deprecated. Only if wanting Apple-only.
5. **Unreal 5** - iOS packaging needs a Mac, huge size, heavy for A15. Not viable.

Recommended de-risking step: before committing, build a 1-day Godot prototype (big heightmap terrain + one jet + 200 instanced targets) through the full CI -> .ipa -> SideStore path and profile on the iPhone 13 Pro Max.

## (b) Godot 4.x
- Official docs: "You must export for iOS from a computer running macOS with Xcode installed." No Linux/CI workflow documented. https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html (4.5: https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_ios.html)
- Exporter has an "export project only" option (writes Xcode project without building XCArchive/.ipa), intended for Fastlane/CI pipelines. https://godot-es.readthedocs.io/es/4.x/classes/class_editorexportplatformios.html
- Practical CI design (my synthesis, not verified end to end): macOS runner -> install Godot + matching export templates -> `godot --headless --export-release "iOS"` with export-project-only -> `xcodebuild archive CODE_SIGNING_ALLOWED=NO` -> zip .app into Payload/ -> .ipa (unsigned is fine, SideStore re-signs). Running export on macOS avoids the "can Linux export" question. Linux job-only export (project files) may work but is UNVERIFIED.
- Community Mac-free route: https://mak448a.is-a.dev/blog/compile-ios-godot-without-mac (build-ios tool produces unsigned IPA via GitHub; needs Dropbox token; fragile, tested on older versions).
- GodotCon Amsterdam 2026 talk covers GitHub Actions macOS + Fastlane for Godot iOS: https://talks.godotengine.org/godotcon-ams-2026/talk/VGASKF.ics
- Renderer: Forward+ and Mobile renderers use Vulkan/D3D12/Metal via RenderingDevice; native Metal driver (added 4.4 dev cycle, Apple Silicon only; MoltenVK for Intel). Not MoltenVK on iOS. https://docs.godotengine.org/en/4.5/about/list_of_features.html , https://godotengine.org/article/dev-snapshot-godot-4-4-dev-1/
- 4.5.2/4.6: iOS Metal exports default to requiring A12+ (fine for A15/A16). https://godotengine.org/article/release-candidate-godot-4-5-2-rc-1/ , https://godotengine.org/article/dev-snapshot-godot-4-6-beta-2/
- Godot 4.6 stable: Jolt default physics for 3D, IK framework, SSR overhaul. https://godotengine.org/releases/4.6/ . A "4.7" docs tree exists; no release notes found.
- Known issue: first launch with Metal can freeze ~5 s (runtime shader translation, cached afterwards) - single report. https://developer.apple.com/forums/thread/824902
- iOS simulator supports only Compatibility renderer (irrelevant, we test on device/Linux).
- Mobile perf: community consensus is Godot is fine for mid-tier 3D, weaker for large complex open worlds on flagships; use Mobile renderer not Forward+. https://gtstu.com/godot-4-optimize-android-ios/ , https://oceanviewgames.co.uk/blog/posts/unity-vs-godot-vs-unreal-2026 , https://godotforums.org/d/40811-3d-performance-on-mobile-sucks-gridmaplong-models/20
- Terrain: Terrain3D (C++ GDExtension clipmap terrain, 4.4+) lists mobile builds, but its mobile docs are old, iOS "experimental", you may need to build the GDExtension for iOS yourself (more CI work). https://terrain3d.readthedocs.io/en/latest/docs/mobile_web.html . LiteTerrain is a mobile-tuned alternative: https://godotengine.org/asset-library/asset/5316 . A flight game can also use a custom heightmap/chunked mesh script, which an AI agent can write.
- Agent-friendliness: excellent. .tscn/.tres/.gdshader/GDScript are plain text; headless runs allow automated checks. Size: small (base iOS export roughly tens of MB; UNVERIFIED figure). Cost: free, MIT, no royalties.
- Linux iteration: full editor and F5 play on Linux (Vulkan). Phone test only needed for perf/touch.

## (a) Unity 6
- Unity builds iOS in two steps (generate Xcode project, then Xcode builds app); Xcode needs macOS. Unity docs say non-macOS devs can use Unity Build Automation (paid cloud). https://docs.unity3d.com/Manual/ios-environment-setup.html , https://docs.unity3d.com/Manual/iphone-BuildProcess.html
- Docs do not state whether the Linux editor has the iOS Build Support module (UNVERIFIED; my recollection is Hub offers it only on Windows/macOS editors). Check Unity Hub on Linux before choosing Unity.
- GameCI unity-builder (ubuntu runners) supports containers for Linux/Windows; iOS appears in its example matrix but docs say SDK-dependent targets need a compatible host. Pattern in other docs: Linux/other job exports Xcode project, macOS job runs xcodebuild. https://game.ci/docs/github/builder/ , https://circleci.com/blog/unity-mobile-cicd , https://dev.to/virtualmaker/automating-unity-builds-to-ios-macos-and-visionos-14km , unity-xcode-builder action: https://awesome.ecosyste.ms/projects/github.com%2Frageagainstthepixel%2Funity-xcode-builder
- Safer alternative: run the whole Unity batchmode build on a macOS runner (needs Unity license activation; Personal needs manual license file, more painful in CI).
- Licensing: Personal free under $200K revenue/funding; runtime fee cancelled Sept 2024. 6.3 LTS supported to Dec 2027. https://enginesdatabase.com/blog/state-of-unity-licensing-in-2026/ , https://unity.com/ja/releases/unity-6
- Perf: URP built for mobile, most proven for 3D mobile; large ecosystem (terrain, flight assets). Agent-friendliness: medium (C# is good, but scenes/prefabs/settings are YAML with GUIDs; much happens in the GUI editor). Size: moderate (~40-100 MB base IL2CPP, UNVERIFIED). Linux editor works for authoring/play.

## (c) Unreal Engine 5
- iOS packaging requires a Mac (remote build from Windows to a Mac); nothing found for Linux. https://docs.unrealengine.com/4.26/en-US/SharingAndReleasing/Mobile/iOS/Distribution , https://forums.unrealengine.com/t/tec-dev-studio-tds-iosremote-build/2739222
- Binary .uasset/.umap, huge editor/app size, high A15 cost, hard for AI agents. Not recommended.

## (d) Native Swift + Metal / RealityKit / SceneKit
- SceneKit: maintenance mode / soft-deprecated at WWDC25 (critical fixes only, no hard deprecation planned); SceneView deprecated in iOS 26. Apple steers to RealityKit. https://developer.apple.com/videos/play/wwdc2025/288/?time=539 , https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit.md
- Fully buildable on GitHub Actions macOS (matches the current XcodeGen/SwiftUI skeleton and the web-to-ios-sidestore workflow). Downsides: cannot run on Linux at all, so every change is a CI build + sideload cycle (minutes each, macOS minutes cost 10x on private repos; public repos free). RealityKit is not designed for large flight-sim terrain; raw Metal gives max performance but requires writing a renderer (hard for novice even with AI). Smallest app size, free.

## (e) Bevy / other
- Bevy renders via wgpu (Metal on iOS); official example tester lists iOS as supported; repo has examples/mobile Xcode project. https://example-runs.bevy.org/about.html , https://taintedcoders.com/bevy/rendering . Build requires macOS (rustc iOS target + Xcode); cargo-mobile2 Bevy templates reported broken and maintained only for Tauri. https://github.com/tauri-apps/cargo-mobile2
- Everything is code (agent-friendly), Linux desktop iteration works, tiny binaries, free. But no editor/scene tooling, API churn every release, ecosystem for flight/terrain thin, Rust compile times. Verify current iOS example in the bevy repo at the latest tag (not confirmed here).
- Other options not researched in depth: Defold/Flax/Stride (weak iOS/3D mobile on Linux).

## CI cost note
macOS runners: free minutes for public repos; private repos bill at 10x. Keep repo public or build only on tags. Pin runner (macos-15) and Xcode version. https://github.blog (runner docs), guides above.
