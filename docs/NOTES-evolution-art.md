# Note: improve the animals and their graphics when they evolve

Robert, 2026-10-31: "make a note to improve the animals and the graphics for them when they are evolving."

Where evolution lives now
- Stages: data/companions.json `familiar.stages` (bond 0 / 40 / 100 / 170: scale 1.0 / 1.3 / 1.6 / 1.9, "glow" at spirit beast).
- Forms: data/forms.json (per role: title2, title3, colour, awaken gift); Menagerie.form_of(); moment = Game.familiar_stage_check().
- Today an evolution is a SCALE change and a tint/glow on the same model. That is the thing to improve.

To do (in order)
1. A real change of body at "fierce" and "spirit beast": new silhouette (horns, mane, extra tail, wings or plates by role),
   not only a bigger copy of the same animal.
2. An evolution moment: a short transformation animation (glow, rise, shed shape, settle) before the new form shows.
3. Per-role look: each of the 20 roles in data/menagerie.json gets its own awakened look and effect colour.
4. Show barding (data/items.json type "pet_armor", Game.pet_armor_id) on the model, per stage, so armour scales and fits.
5. Better animation set per stage: idle, walk, bite, deed, down. Faster, heavier, more confident as it grows.
6. Keep it code-drawn / free assets only (Robert's art rule), and keep the phone version light (swap in a simpler form).

Related shipped 2026-10-31: pet armour (barding), pet tricks by bond, more taming tiers, new companion styles.
