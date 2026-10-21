# Dungeon Crawl Elite: legacy quest lines, the Balance, and designed gear (Robert, 2026-10-13)

Robert's words, kept as the spec's source:
- Inheritances must not be easy to earn. Each needs a quest line to unlock. The better the inheritance, the longer the line. The more it synergizes with the player's build, the shorter the line.
- The quest line can run in parallel to the main quest.
- Guidance for balancing every aspect of the game may be part of the ultimate legacy inheritance. The ultimate quest can give an easy passage through danger to reach the same end. Both lines must be worked on: a gap of more than 50% between them starts hurting play, but it can still be done by a maximiser.
- Gear looks bland on the character. Blacksmithing lets the player design the look of the gear, and the design can raise or lower bonuses in unique ways. Every craft gets a design side.
- The first quest ignition gives the recipe for the first item; finishing each step gives the recipe for the next item. The chain eventually needs every other craft in the game. The finished set can grow with its wearer.

Rules for Dev: small steps, back up before changing, add data in data/*.json (numbers there, words by Dev), no new file replaces a working one (backup stays reachable), stress bot must stay clean, tests added per step. Build on what exists: scripts/systems/Legacies.gd (minor/major/heavenly), Quests.gd (quest kinds), Synergy.gd, Game.gd craft/forge functions, data/legacies.json, data/crafting.json, data/recipes.json.

## Part 1. Legacy quest lines (replaces "find it and take it")
1. Every inheritance (minor craft master, major dead master, heavenly) starts as a *sign* the player finds (current hidden spot logic stays), but touching it only opens a quest line ("legacy" kind in Quests.KINDS). The inheritance is granted by the line's last step.
2. Length by tier (base steps): minor 3, major 6, heavenly 10, ultimate 14. Step kinds: gather, craft a named item, defeat a named foe, reach a floor/place, teach (bring an item to an NPC), endure a trial (the existing echo fight is the last step of a heavenly line).
3. Synergy shortens it: synergy = 0..1 from how much the master's tags overlap the player's build (techniques known, craft skills, equipped set, realm path). Steps needed = ceil(base * (1 - 0.5*synergy)), never fewer than half the base. Steps the build already satisfies auto-complete with a line of text saying why ("your hands already know this").
4. Steps are generated per game from the game seed, using the same seed discipline as Legacies.gd, and are saved. A line can be started on any floor, worked beside the main quest, and a quest log entry shows the next step only (no spoilers beyond one step).
5. Numbers in data/legacy_quests.json: base steps per tier, synergy weights, step pools per master, rewards per step (small: materials, gold, a recipe hint, never the inheritance itself).

## Part 2. The Ultimate Legacy: the Balance
1. A rare legacy (found like a heavenly one, the longest line) that unlocks the Balance page: a gauge for each aspect (body, qi, craft, lore, standing, wealth, exploration) and a one-line hint naming the weakest aspect and where to work on it.
2. Two tracks: the Main Road (main quest progress) and the Legacy Road (total legacy-line progress, counted as a share of the lines the player has started). Gap = |main% - legacy%|.
3. Gap up to 50 points: no effect. Past 50: "Imbalance" scales in with the excess (qi regeneration and experience gain lower by up to 30%, foes slightly stronger), removed as soon as the gap closes. A maximiser who finishes both can ignore it.
4. The Balance's reward when both tracks are within the limit: "the Even Road", an easy passage through danger (less damage taken, no ambushes, safer traps) that gives the same outcome as grinding the hard way. It lapses if the gap breaks the limit.
5. Numbers in data/balance.json: limit 50, penalty caps, passage strengths.

## Part 3. Designed gear and every craft's design side
1. Blacksmith design screen (after choosing the stock): pick silhouette (shoulders, plates, hem), motif/engraving, trim metal, patina/dye, gem inlay spots. Each choice has a visible effect on the character (code-drawn parts, no outside art) and a data-driven stat effect that can be plus or minus (a heavy flared pauldron: more ward, slower; fine filigree: more qi, less ward). A design is saved with the piece.
2. Same for the other crafts: alchemy (vial shape, colour, seal: potency, side effects, duration), jewelcrafting (cut and setting: which stat it feeds), herbalism (bundle and tincture: reagent traits), medicine (preparation: healing and risk), cooking/tailoring if present. Effects live in data/design_traits.json using the existing material traits (Game.material_traits).
3. Gear on the character: more silhouette variety per slot, per-class accents, a two-colour scheme from the design, a visible glow for high quality; readable at 64 px.

## Part 4. Heirloom set quest (the crafting chain)
1. Ignition: a designed piece that hits a rare combination (or a smith NPC reading a design) starts the Heirloom quest. The quest gives the recipe for piece 1 only.
2. Finishing each piece's step gives the recipe for the next. Pieces demand different crafts in turn: smith the plates, alchemy for the treatment oil, jewelcrafting for the stones, herbalism for the dye, medicine for the binding tonic, etc. By the last piece every craft in the game has been used.
3. The set grows with the wearer: stages Dormant, Awakened, Ascendant. Each piece levels with use and with feeding rare materials; the set bonus scales with the wearer's realm. Growth never replaces the player's own designed look.
4. A legacy master's synergy with the set shortens the Heirloom line the same way as Part 1.

## Order of work (each step ends with the stress bot clean and tests passing)
A. data/legacy_quests.json + Legacy quest kind + convert minor legacies (shortest) first, then major, then heavenly.
B. Synergy shortening and auto-complete of satisfied steps.
C. data/balance.json + the Balance page, gap meter, Imbalance, the Even Road.
D. Smith design screen + design_traits + the visible gear parts.
E. Design for the other crafts.
F. Heirloom set chain and set growth.
