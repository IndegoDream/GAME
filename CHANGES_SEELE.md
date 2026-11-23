# PC and phone presentation update

## Project identity
- Game: Dungeon Crawl Elite, v0.63, clean build.
- Engine: Godot 4.6.3, GDScript, 3D.
- Entry: `project.godot` -> `Main.tscn` / `Main.gd`.
- PC: Forward+ with the existing detailed art set.
- Android and Web: Compatibility, protected Low art/effects.
- Source revision reviewed: GAME/main, `0a27f69`.
- Content: Eliet Village, 50 dungeon floors, valley/towers/frontier, cultivation, crafting, companions and online systems.

## Changes
- Shared expedition-ledger title menu, more readable inventory item cards, rarity labels and keyboard-selectable item slots.
- Grouped keyboard help uses actual configured bindings; existing bindings are preserved.
- PC camera reveals more distance; reduced outdoor haze and smaller village inscription leave more world visible. Map geometry and collision scale are unchanged.
- Phones cannot restore or select PC-only high graphics/custom effects. Low effects and 30/60 FPS choices are protected; inventory MSAA and glow respect Low.
- Low/Medium/High visual effects control on PC, with reduced burst density and expensive dissolve disabled at lower levels.
- World Auto no longer removes regions just because the device is a phone. Explicit Lite remains an opt-in setting.
- Android/Web resource filters exclude realistic, Poly Haven, character and HDR sky art. Warm-up avoids those resources on Low.
- Normal Quit no longer produces a false crash warning on the next launch.
- Browser-safe key labels and a locally bundled OFL multilingual font. Android retains system fonts rather than downloading the browser fallback.
- Release tests now handle host locale and the project's clean-build rules; hostile-client fuzzing reconnects after valid flood-protection disconnects to continue coverage. The threaded-loader test uses a real-time deadline so accelerated simulation cannot outrun disk reads.

## Deliberate limits
- This is a presentation and device-safety pass, not a balance/content rewrite. Floor 9 boss tuning and new rest havens for floors 35/45 from the broader README remain future work.
- Native Android installation, mid-phone FPS, total process RAM, thermal behavior, first-load time and crash-free operation have not been certified. Desktop Low checks are not handset benchmarks.
- No GitHub commit or push, store upload, or signing credential change was performed.
- Existing Android Beta export has an AdMob/Gradle configuration warning. Google Play resource export is the verified lightweight pack route; a signed APK/AAB still requires the Android build/signing setup.
- Windows custom-template paths remain the repository's machine-specific values; select installed Godot 4.6.3 templates when building on another PC.

See `VALIDATION.md` for checked outcomes and remaining release status.
