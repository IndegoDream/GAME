import json
F={}
F[31]={
"A":("Heat Under the Boots","The steps here are scale, not stone. They are warm. Rhee's second scout wrote on the wall: do not stand still on them. He did not say why. I stood still. I know why."),
"Y":("Priest's Tablet, Cracked","BREATH COMES AFTER THE ROAR, NOT BEFORE. When you hear her gather air, you have two heartbeats. Get behind a rib. Stone does not cook as fast as skin."),
"R":("Scratched Under a Rib","Her breath ran along the spine, rib to rib, the way ours runs through the body. The priests learned to send theirs the same road, in order, and burned what they struck. Sit and follow it down."),
"G":("A Map Note, Pencil","Spinal Bridge is narrow and the bats like it. Take the Hall of Guardians instead. It is longer, but the guardians only walk one way, and it is not toward you."),
"M":("Smith Hale's Mark","Hale's old tally mark, three bars and a hook. He came this far with the first lot, forty years back. Under it: a loose scale in the wall leads toward the heart. Quiet niche, east side."),
"O":("Hunters' Count","Drakelings hatch in the pools. The big ones guard the hatchery. We burned two nests and thought we were clever. The next day there were four. Leave the eggs alone."),
"U":("Last Words, Vertebra Hall","I counted her ribs to keep my head. Forty-one. Then she breathed and the count did not matter. If you found this, tell the Lodge that the brute at the hall's end does not tire."),
"X":("A Child's Rhyme","One for the scale and two for the bone, three for the flame that will take you home. Four for the dream you must not wake. Five is the heart, for goodness' sake. Scratched low, where a child could reach."),
}
F[32]={
"A":("Sand Without Footprints","The slope is ash over glass. Wind erases your trail in a minute. Cut a mark in the rock at every turn. I did not, and I walked past this stone three times."),
"Y":("Count the Colossi","Colossus pens are east of the gallery. Each beast is as tall as a house and slow to turn. Strike the leg, step back, strike again. They forget you if you stay behind them."),
"R":("Half-Buried, Half-Burnt","A glassmaker's note. Fire does not only cut. If you let the heat come and do not flinch, the skin learns it. It goes hard like a pot in the kiln. Stand in the glow and breathe slow."),
"G":("Caravan Ledger, Last Line","Forty camels. Twenty-two men. Salt, glass, two jars of lamp oil. Water: none. We took the wind corridor to save a day. It cost us the rest. Do not trust a short road."),
"M":("A Scrawl in the Shade","Do not drink from the Flooded Grotto. It looks clean. My brother drank. He talked to the wall for a night and then he stopped talking. Boil nothing; carry your own."),
"O":("Ash Whirl Rule","When the ash starts to turn, stop. Hold your sleeve to your face and wait. It passes in a dozen breaths. If you run, you run into the pits. I saw a man do it."),
"U":("Mirage Warning","If the water shines, it is not water. Real water does not shine, it sits. The Ashen Mirage has taken three of ours. It is a room, not a lake. Walk through the glare and it ends."),
"X":("The Ash King's Court","They say a king ruled here before the sand. His court is at the bottom, still sitting. One of the old Lodge men saw it. He said they all looked up when he came in. That was all he said."),
}
F[33]={
"A":("Mind the Ninth One","The hall has many of you. Eight of them copy you. The ninth does not. Go slow. Raise your left hand and see who is slow to answer. Strike that one."),
"Y":("Infinite Room, Notice","Nobody has walked this room to the end, because it has none. A man tied a rope to the door and played it out. He came back with the rope and no memory of why. Keep your hand on the wall."),
"R":("Under the Silver, a Line","The surface only shows what stands in front of it. The thing that looks back is not you, so it cannot hurt you the way you fear. Look past it, and what is beneath you holds. Sit with your eyes open."),
"G":("Silversmith's Receipt","Received: six mirrors, quicksilver backed, one cracked in transit. Paid in full. The seller says the cracks were there before the glass was made. We did not argue. Store unsold stock below."),
"M":("Quicksilver Vein, Keep Out","Do not touch the vein with bare hands. It looks like silver and moves like water. Smiths who ignored this shook for a month. Hale says wear gloves, and wash after."),
"O":("Hall of Doors Note","Most doors are painted on. Knock first. A painted door rings like a plate. A real door sounds like a closet. I learned this after the third bruise."),
"U":("The Room With No Reflection","Step into it and you will see the room but not yourself. Stay calm. It is only the glass that is missing. Elder Mo said some come out different. I came out the same, I think."),
"X":("Cat's Corner","A cat lives here. It is not a real cat. It sits on the broken frame and watches us fight ourselves. It is the only thing on the floor that is exactly one thing."),
}
F[34]={
"A":("Stair That Hums","Every step rings a small note. Walk heavy and the notes pile up, and then the cave answers. Walk soft, on the edge of the step, and the cave lets you pass."),
"Y":("Tuning Fork Rule","Do not strike the forks. Crystal here wants to ring, and the more it rings the louder the wisps get. Leave them be. Carry no metal in your hand if you can help it."),
"R":("The Cracked Lens","Hold a shard to the lamp and the light splits in seven. One strand is yours. Follow it back and you find where you started, and who. The old delvers called it the road home."),
"G":("Names on the Wall","Someone scratched a name a hundred times. Another has scratched the same name beneath. The first is the woman who walked in. The second is her daughter, who came to look. Neither has a third."),
"M":("Quiet Chamber Law","The vault is dead silent. If you speak low, the cave repeats it back a moment late. Say a name aloud and you will hear it answered. I advise you not to say a name."),
"O":("The Choir Barracks","The barracks hold stone figures in rows, mouths open. When one cracks, the sound wakes the others. Break them one by one, not in a pile. Sound carries here."),
"U":("Wisp Hatchery Note","Wisps are born in the geode and drift out. They are drawn to noise. Be quiet and they pass you by. A loud man gets a ring of them. They do not bite. They only follow."),
"X":("Queen's Resonance","At the bottom the queen sings one note, low, under your feet. It is not a song. It is more like a tooth being pulled. Plug your ears if you have wax. I had none."),
}
F[35]={
"A":("What Remains of the Stair","A stair of metal, bent like a hair pin. Immortals once climbed it to a gate. The gate is gone. A rhyme: step on the bolts, never the plates. The plates give."),
"Y":("Hall of Winds, Plainly","The wind here never stops. It pushes toward the edge. Lean into it and keep your back to a wall. A strong gust takes a person off the terrace. The Lodge lost a man that way."),
"R":("Breath of the Cloud Court","They did not eat much, the immortals. They breathed. In through the nose to the count of eight, out in twelve. That is how the palace was held up. Do it here and the fall slows."),
"G":("Pill Pavilion Inventory","Jars labeled with a single character. Most are empty. A few hold dust that was once a pill. Immortals took them to live forever. They stopped when the jars ran dry."),
"M":("The Fallen Throne","A throne sits at the bottom with no one in it. The legs are cut cleanly. This was not an earthquake. Someone wanted the immortal to come down, and he did."),
"O":("Crane Terrace Marker","Cranes were kept here, white ones, for riding. They are gone but their nests are not. Check each nest. Some hold a feather the length of your arm. Worth the climb."),
"U":("Edict of Heaven, Torn","The edict reads: LET NO ONE ASCEND WITHOUT BALANCE. The rest is burned. Somebody wanted to ascend without it, and tore the edict to make a point. The terraces fell soon after."),
"X":("A Scholar's Last Page","I came to read the old words. I stayed to read the wind. The jade has them in its veins if you hold it to the light. There is a lot about the Accord. Mostly about how little of it was kept."),
}
F[36]={
"A":("Hair on End","The steps hum. Your hair will stand up on your arms. That is the stair warning you. Move on before the next strike. The strikes come in threes."),
"Y":("Stormwarden's Warning","A stormcaller made this floor, and she is still angry. When the sky goes white, get off the iron. Lightning loves metal. Drop your sword if you must. A sword can be bought."),
"R":("Between Two Thunderclaps","There is a space after the flash and before the sound. A heartbeat long. The wardens learned to live in it. Slow your breath until you can feel it. Then step."),
"G":("Rod-Maker's Account","Forty rods sold. Nine for the tower, six for the barracks, the rest to miners who lost their nerve. The grounding chamber at the base is where the rods meet earth. Stand there in a bad storm."),
"M":("Stormwatch Post, Log","Day 14. Lightning at dusk, twice. Winds from the north. The imps are nesting on the east ledge. Day 15. No log keeper. Day 16, in another hand: calm room is safe."),
"O":("Calm Room Notice","Between the storms there is a quiet room. No wind and no strikes. Rest here. Heal here. It has never been touched by lightning, and I do not know why."),
"U":("Goat Ledge Rule","The ledges are narrow and the goats are mean. Do not fight on a ledge. Lure them to flat ground. A man fell off the east ledge. We counted to nine before he stopped falling."),
"X":("The Tyrant's Crown","At the top of the spire sits the Tyrant. It wears a crown of rods that draws every strike. Cut the rods and he is just a big man. Let them hit him and he laughs."),
}
F[37]={
"A":("Thread Under the Boot","Each step plucks a thread. Somewhere below, something feels it. Walk slow and the web lets you. Run and it knows. I ran, once."),
"Y":("The Loom Hall Ledger","Thirty looms, bone frames, black thread. The weavers made cloth for the dead. They were paid in grain. The last bolt on the oldest loom was never cut. Do not cut it."),
"R":("A Second Pulse","Spun silk carries a beat, if you press it to your wrist. Slower than yours. Match it and your own heart slows too. The weavers sat like this for hours. Try it before a fight."),
"G":("Silkworm Shelves","Shelves of worms, still alive, still eating. Someone feeds them. We never found who. Take nothing from the shelves. The cocoon store is the safe place for supplies."),
"M":("Weavers' Rest, Cot Count","Eleven cots, ten blankets. One cot unmade. One weaver did not rest. She went down to the pattern room and did not come back."),
"O":("Pattern Library Shelf","The library holds the patterns of the web. Each is a map of one floor. A weaver who reads them could walk without waking the Queen. I tried. I woke the Queen."),
"U":("Clean Corner","There is a corner with no web. Every other corner is thick. Somebody sweeps it. Do not ask who. Sleep there if you must, and keep one hand on a blade."),
"X":("The Weaver Queen","She is not a spider. She was a woman once, a weaver of the first age, and she wove herself in. She still sings while she works. Do not listen to the end of the song."),
}
F[38]={
"A":("Grit on the Rails","The crater stair is slick with iron dust. Wipe your hands. Wipe your boots. A man named Garrett slipped here in the first year and the Lodge still says his name."),
"Y":("Foreman's Rule, Main Shaft","Three whistles means leave the shaft. One means collapse. The shaft is twenty paces wide and nothing holds the roof but luck. Keep to the carts, not the wall."),
"R":("Astronomer's Note","A star fell here and the iron in it was alive with weight. Eat a little of the dust, the old miners said, and the body forges itself. It is a bad idea. The right way is breath and patience."),
"G":("Ore Cart Tally","Fourteen carts full on day one. Nine on day thirty. Two on day sixty. We dug right up to the shaft and found nothing after. The seam was gone. Perhaps the star took it back."),
"M":("Golem Pit Warning","The golems are the miners' own. They were built to carry. Something told them to stop carrying and start crushing. They do not tire. Fight near the exits."),
"O":("The Miners' Chapel","A small chapel with a bell, no clapper. The miners prayed here before a shift. Candle stubs by the hundred. Light one if you like. It costs nothing, and the next delver will be glad of the light."),
"U":("Starlight Scriptorium","The astronomers copied the sky onto the walls, each dot a star in its place. The pattern ends at the Heart. Fewer dots than there should be. They stopped counting."),
"X":("The Last Seam","Strange lights hover over the true seam. I followed them, and I found it. Then I ran out of breath, and the lights waited. They did not seem unkind. They seemed to be counting."),
}
F[39]={
"A":("Lantern Stair Custom","Take a lantern from the hook as you enter. Leave one lit at the bottom. That is the rule, and the market keeps accounts. Come in with no lantern and you owe a debt."),
"Y":("Paper Bridge, Fire","The bridge is paper over rope. It takes one person at a time. No open flame, no torch. If you carry a lantern, hold it low and away. I saw it go up in a breath."),
"R":("A Door Half Seen","Some doors in the Mask Gallery are only half there. Look at them from the corner of the eye and they firm up. Look straight and they fade. The dead walk through them like a dream."),
"G":("Broker's Ledger, Page One","Debts owed: forty-one. Debts paid: one. The one is marked in red. The ledger does not say who paid. It says only, thank you."),
"M":("The Rules of the Market","One: no haggling after dark. Two: no looking at the faces behind the masks. Three: if a ghost offers a price, take it. Four: you do not leave until the bell. Five: the bell does not ring."),
"O":("Pawnshop Notice","We buy anything. Boots, names, years. A man pawned a year of his life for a lamp. He was twenty. He looked forty when he came out. Check what you sell."),
"U":("Hungry Alley, Careful","The alley is narrow and the hungry things are quick. They are not ghosts. They are people who stayed too long at the bazaar. Shove them and run. Do not give them food."),
"X":("The Ghost Broker","He sits at the counter with a ledger and no face. He will buy and sell anything. He has been at it since before the Accord. He has never once been cheated, and neither has he cheated anyone."),
}
import os
out={}
for n,d in F.items():
    json.dump({k:{"title":t,"text":x} for k,(t,x) in d.items()},open(f'floor{n}.json','w'),indent=1,ensure_ascii=False)
