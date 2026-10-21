# Asset Library

A starter set of real, license-clear 3D assets for building a more visually
complex world in Godot Studio / Game Forge 3D / the Realm -- gathered
2026-09-26 while Seele (the paid bespoke-model service) is between refresh
cycles. Everything here is **CC0 1.0 Universal (public domain)**: free to
use, modify, and redistribute, no attribution required, no license file to
ship, no credit line needed anywhere. Crediting the original artists is
appreciated but never mandatory -- see `manifest.json` for every source URL.

See `manifest.json` for the full machine-readable record (every pack/texture/
HDRI, its source URL, its file count, and its byte size). This file is the
plain-English tour.

## kenney/ -- hand-modeled props and buildings (609 files, 9.4MB)

Four packs from Kenney (kenney.nl), a long-running CC0 asset studio. Each
pack folder holds the GLB (binary glTF) models plus their own small texture
folder -- GLB loads natively in both Godot 4.x and three.js, no conversion
needed.

- **castle-kit/** -- medieval fortification pieces: walls, towers, gates,
  bridges, banners. Good for a keep, a border wall, a siege backdrop.
- **fantasy-town-kit/** -- village buildings: houses, carts, fences,
  chimneys, banners. Good for a starting town or market square.
- **mini-dungeon/** -- dungeon interior pieces: columns, chests, barrels,
  gates, floors. Also includes two basic rigged character models
  (`character-human.glb`, `character-orc.glb`) as a bonus -- useful as
  placeholder NPCs or stand-ins until Seele delivers bespoke ones.
- **nature-kit/** -- outdoor terrain and foliage: trees, rocks, bridges,
  fences, plants. The biggest pack (330 files) -- this is what makes an
  outdoor scene stop looking like a bare gray plane.

Each pack folder keeps its own `License.txt` exactly as Kenney ships it.

## polyhaven/ -- surface textures and sky HDRIs (136MB)

From Poly Haven (polyhaven.com), fetched via their public API. All CC0,
all real photographed/scanned material at 2k resolution.

### textures/ (9 sets)

Each texture set is a folder with three maps: `Diffuse.jpg` (the color/
albedo map), `nor_gl.jpg` (a normal map in OpenGL convention -- the right
one for Godot and three.js; NOT the DirectX `nor_dx` convention Unity/
Unreal use), and `arm.jpg` (a packed Ambient-Occlusion / Roughness /
Metalness map -- a single file that feeds all three PBR channels at once,
the modern glTF-style packing).

| folder | what it looks like |
|---|---|
| forest_floor | leaf-litter forest ground |
| grass_ground | open grass / meadow ground |
| mossy_cobblestone | old mossy cobblestone path |
| old_stone_wall | weathered stone/fortification surface |
| castle_brick_01 | castle brickwork wall |
| rock_face | natural rock / cliff face |
| stony_dirt_path | worn dirt path with embedded stones |
| mossy_stone_wall | moss-covered stone wall |
| old_wood_floor | worn wooden interior floor (tavern/cottage) |

### hdris/ (6 skies)

Each is a single `.hdr` file -- a full 360-degree environment map. Used as
a scene's sky/background AND as its lighting source at the same time (an
"HDRI environment" is both in one file) -- this alone is usually the single
biggest visual upgrade available for a three.js or Godot scene, because it
replaces a flat color background and a couple of fake lights with real
photographed light.

| file | mood |
|---|---|
| epping_forest_01.hdr | daytime forest canopy sky |
| misty_pines.hdr | misty pine forest morning |
| evening_meadow.hdr | golden-hour meadow sky |
| sunset_meadow_path.hdr | dramatic sunset over a meadow path |
| blaubeuren_night.hdr | clear night sky |
| kloofendal_28d_misty.hdr | overcast, misty general-purpose sky |

## What's deliberately NOT here

Character/creature packs were skipped this round -- Kenney's animated-
character pages are JS-app-driven and didn't yield a reliable direct
download link, and bespoke rigged characters are exactly what Seele is
for anyway. The two bonus character models in `mini-dungeon/` are
placeholders, not a real character pipeline.

## Using these

Nothing has been wired into Godot Studio or Game Forge 3D yet -- this is
just the raw material, downloaded and organized. To actually use a model
or texture in either, it still needs to be copied into that project's own
asset folder and referenced from a scene/script. That import step is a
reasonable next build if you want it, but it wasn't part of this ask.
