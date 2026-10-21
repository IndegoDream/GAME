# Dungeon Crawl Elite -- package for Seele (visual + mechanical upgrade)

**What it is:** a 3D cultivation dungeon crawler in Godot 4.6.3 (GDScript). Third/first person, PC + phone from one project.
Eliet Village hub, 50 floors, 26+ fighting styles (melee, ranged, ki arts, poison, beasts, constructs), Dao/cultivation
progression, bonds with NPCs, a menagerie you breed and train, crafting, cooking, riddles and lore on every floor,
daily boons, a season ladder, and an online world. 10 languages (English, zh_CN, es, pt_BR, ru, de, fr, ja, ko, tr).
This is the CLEAN build: no test kit, no god mode, no cheats (data/build_flavor.json {"clean": true}). Build number: data/build_info.json.

**Open:** project.godot in Godot 4.6.3 (Forward+). Main scene Main.tscn. Everything needed (code, levels, data, art, audio) is in this file.

**Layout:** scripts/ engine (core/Game.gd is the hub), levels/ + data/ are JSON content (a level is a text map), assets/ art+audio,
tools/ test scripts (release_gate.sh runs ~100 checks), DEV_GUIDE.md explains the data-driven design.

**What we want from you**
1. Visuals: lighting, materials, shaders, post-processing, particles/special effects (hit feel, ki arts per element, boss telegraphs,
   level-up/loot beams), UI polish. Keep a Low/Medium/High effects setting; phones must stay smooth.
2. Mechanics: smooth combat feel, camera, controls (keyboard+mouse, gamepad, touch), balance across floors 1-50 and across play styles.
   Known: floor 9 boss too hard; floors 35/45 need a rest haven.
3. Performance: frame rate on mid phones, load times, memory.

**PHONE: read PHONE_RULES.md.** Phone keeps its current basic look and must be fast; all non-art updates apply to both.

**Rules to keep**
- Fair pay: nothing sold may give power. Convenience only.
- No cheats/test-kit in this build. Phone and PC get the same features.
- Keep content in the JSON data files; keep saves compatible (don't rename save keys without a migration).
- New player-facing text goes through tr()/I18n so it can be translated.
- Run tools/release_gate.sh (needs GODOT=path-to-godot) before handing back; it must pass.
- Please return the full project as one file, plus a short change list.
