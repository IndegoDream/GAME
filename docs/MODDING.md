# Modding Dungeon Crawl Elite (round 182)

A mod is a folder with a `mod.json` and a `data/` folder. Each file in `data/` has the same name as one of the game's
data files (`items.json`, `enemies.json`, `recipes.json`, `quests.json` ...) and is laid **over** the game's file when the
game starts.

```
mods/
  ashlight_fern/
    mod.json
    data/
      items.json
      recipes.json
```

`mod.json`:
```json
{"id": "ashlight_fern", "name": "Ashlight Fern", "version": "1.0", "author": "you", "about": "one line"}
```
`id`: 2-32 lower-case letters, digits or `_`, unique.

## How a file is laid over
- A dictionary merges key by key; deeper dictionaries merge too. A new key adds; a known key replaces.
- `null` removes a key: `{"goblin": null}` takes the goblin out.
- `{"__append": [ ... ]}` adds to the end of a list. Any other list replaces the game's list.
- Mods load in name order; a later mod wins a clash.

## Where the folder goes
- PC: Menu > Mods shows the folder (on Windows `%APPDATA%\Godot\app_userdata\Dungeon Crawl Elite\mods`).
- Steam Workshop: once the game has its Steam App ID, subscribed Workshop items are found the same way.

A mod found is **off** until you turn it on in Menu > Mods. Restart the game to apply a change.

## What mods cannot change
`store.json`, `cloud.json`, `online.json`, `online_events.json`, `build_info.json`, `build_flavor*.json`, `retail.json`
(purchases, accounts and the shared world). With any mod on, the online world (the Gate) stays shut and Steam
leaderboards take no scores: a modded game is a solo game. Saves remember which mods they were played with.

## The example
`docs/modding/ashlight_fern` adds one herb (Ashlight Fern) and a salve recipe. Copy it into your mods folder, rename the id, and change it.
