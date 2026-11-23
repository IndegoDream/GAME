# Validation record

## Release status
`tools/release_gate.sh`: **PASS**, exit code 0, with no timeout. All gate stages completed, including the 65-level smoke check, clean-build protections and server checks. The serial headless run used Godot 4.6.3 with `--fixed-fps 60`, isolated user data and Low settings. The threaded-loader regression also passed separately at normal and accelerated speed.

This approves the scoped presentation/device-policy update, not physical-phone performance certification or completion of the broader balance/content requests.

## Established checks
- Godot 4.6.3: 169 scripts compile, zero failures.
- Device-policy regression: 71 checks pass, including restored high/ultra/custom settings, effect downgrade, full-world Auto and lightweight export filters.
- Touch layout: 483 checks pass.
- Native PC High and Compatibility Low: Continue click, W movement, primary attack state, inventory open and Enter item selection pass.
- Low inventory uses no MSAA; the final touch-help panel follows the status panel instead of overlapping it.
- All 65 level definitions/generated regions pass the real headless build/collision smoke check.
- Clean-build tests reject saved god mode, unlimited materials and cheat teleport. Production cheat protections were not relaxed.
- Multilingual font import: 26 representative Chinese, Japanese, Korean and Cyrillic glyphs available. Chinese title rendering visually checked in Web.
- Browser WebGL2: normal character creation/Quick Start reaches village; movement, attack input and inventory exercised. Local HTML/JS/WASM/PCK/icon requests succeeded; no external game-asset downloads.
- Browser keyboard-label display-server errors fixed. A synthetic Escape event caused a browser pointer-lock user-gesture rejection; real click entry and movement remained functional. This is recorded rather than described as a fully error-free automation run.
- Orderly native exit produces `clean:true` in MemLog, preventing the prior false crash banner.
- `git diff --check` passed for source changes.

## Phone-profile observations (desktop host only)
The headless Low profile uses the same content access as PC (`world:auto`). These numbers come from a desktop process, not an Android phone. FPS is a single Godot monitor sample during scripted loading, not a sustained rendering benchmark; static memory is not total process RAM.

| Scene | Build call (ms) | Sample headless FPS | Static memory (MiB) | Peak static memory (MiB) |
| --- | ---: | ---: | ---: | ---: |
| Village | 5,993 | 60 | 129.0 | 186.4 |
| Floor 1 | 3,154 | 21 | 168.4 | 212.6 |
| Floor 25 | 3,822 | 41 | 209.8 | 309.7 |
| Floor 50 | 4,957 | 43 | 263.2 | 425.5 |

Rendered Low village in the final desktop interaction run: about 56.2 MiB texture memory and 67.9 MiB video memory. These do not certify Android GPU/RAM limits. The several-second synchronous build calls also show that the README's strict main-thread/loading budget has NOT been established.

## Export and delivery
- Final Web and Google Play resource exports completed with exit code 0 and no logged export errors.
- Android resource pack: 123.0 MiB, 4,717 entries, ZIP integrity checked; the four PC-art folders are absent and floor 50 is present. This is a resource pack, not an installable APK/AAB.
- Browser-only CJK fallback is excluded from Android, which retains its existing system-font approach.
- Final Web menu verified in Chinese and after switching to Spanish: title/subtitle update correctly, no missing glyphs, no engine/script errors during that check. A browser snapshot command timed out once; subsequent session continuity, diagnostics and visual checks succeeded.
- All final browser asset requests were local to the nested export directory and returned HTTP 200.
- Published to frontend Preview: https://static.seeles.ai/media/web-games/9f133620-f316-4cdf-852e-56f025984fe8/index.html . Public HTML, WASM MIME type and resource-pack availability verified.
- Source archive includes editable scripts, all game data/levels/assets, tools, project settings and change/validation notes. Rebuildable caches, Git history, test user data and editor/session metadata are excluded.

## Remaining limitations
- No physical Android device, ADB performance run, signed APK/AAB install or thermal/crash-duration test was available. The 60 FPS / 1.5 GB / first-load targets are not certified.
- Native Compatibility shutdown still reports two small GL texture leaks also seen before this pass; native High may report ObjectDB cleanup warnings and SSS on the transparent inventory viewport. No new gameplay script exception was observed in the focused rendered runs.
- Audio playback cannot be assessed on this host; native checks use Dummy audio.
- Android Beta's prebuilt-APK preset conflicts with the installed AdMob plugin's Gradle requirement. Google Play resource-pack export passes, but native packaging/signing remains separate.
- Existing machine-specific Windows custom template paths require local setup for a new computer.
- The broader README's floor 9 balance and floor 35/45 rest-haven requests are not part of this completed presentation/device-policy pass.
