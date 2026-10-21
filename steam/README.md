# Putting Dungeon Crawl Eliet on Steam

The game is wired for Steam with GodotSteam (`addons/godotsteam/`, MIT, GDExtension 4.22.1 with Steamworks SDK 1.65 and Valve's redistributable `steam_api` libraries). Under Steam it does the following:

- **Achievements.** The game unlocks every achievement in `data/achievements.json`, plus the bloodline, trial and ascension ones. See `achievements.md` for the full list.
- **Stats.** The game tracks these stats: deepest_floor, realm, blood_purity and ascensions.
- **Leaderboards.** There is a deepest-floor board, plus one board per day for the daily trial.
- **Rich presence.** Friends see where you are, your cultivation and your blood.
- **Steam Cloud.** Your save goes up on every save. On load, whichever save is newer (this PC's or the cloud's) wins.

Outside Steam, none of this runs and the game plays the same. That covers the box, the phone version and the engine checks.

## Testing it now, before you have an App ID

The App ID is `steam/app_id` in `project.godot`. It is currently **480**, Valve's public test app ("Spacewar"), which is what every Steamworks developer tests against.

1. Have the Steam client running and logged in.
2. In the game, open the menu and set **Steam: on**. This setting is only shown when the plug-in is present.
3. Steam's overlay works (Shift+Tab). Your friends list shows you "playing Spacewar". Achievements and leaderboards go to Spacewar's test entries; most of the game's own entries won't exist there, and that's expected.

## When you decide to publish

1. Join Steamworks (partner.steamgames.com) and pay the Steam Direct fee for the game. It is $100 per game at the time of writing; check Valve's current terms. You get an App ID.
2. Put that number in `project.godot` under `[steam]`: `app_id=<yours>`.
3. In Steamworks, under App Admin > Stats & Achievements, enter the achievements and stats from `achievements.md`. Run `tools/steam_achievements.gd` again whenever Dev adds achievements. Leaderboards create themselves.
4. In Steamworks, turn on Steam Cloud for the app. Give it a few MB and 1 file, `eliet_save.json`.
5. Export with the **"Windows (Steam)"** preset in `export_presets.cfg`. It has the `steam` feature, which turns Steam on and makes the game relaunch through Steam if it was started outside it.
   - The Windows export templates must be installed in Godot first. Use Editor > Manage Export Templates, version 4.6.3.
   - The export copies the GodotSteam DLL and `steam_api64.dll` next to the .exe by itself.
6. Upload the `build/steam/` folder with SteamPipe. The Steamworks "Upload" docs walk through it.

Valve reviews the store page and the build before release. Plan on a few weeks between "I have an App ID" and "it's on sale".
