extends SceneTree
## Writes steam/achievements.md: every achievement the game can unlock on
## Steam (API name, display name, description) -- the list to enter in
## Steamworks (App Admin > Stats & Achievements), and the stats and
## leaderboards SteamLink.gd uses. Run:
##   godot --headless --path . --script res://tools/steam_achievements.gd
## (Round 30. The game's own achievements come from data/achievements.json,
## so when Dev adds one, run this again.)

const EXTRA := [
	["BLOOD_FOUND", "Old Blood", "A bloodline enters your blood."],
	["BLOOD_AWAKEN", "The Blood Wakes", "Go deep enough for your blood to wake."],
	["BLOOD_10", "Stirring", "A bloodline reaches 10% purity."],
	["BLOOD_25", "Awakened Blood", "A bloodline reaches 25% purity."],
	["BLOOD_50", "Manifest", "A bloodline reaches 50% purity -- its power shows."],
	["BLOOD_75", "Ascendant Blood", "A bloodline reaches 75% purity."],
	["BLOOD_100", "Pure Blood", "A bloodline reaches 100% purity."],
	["TRIAL_FIRST", "Tried", "Clear a daily trial."],
	["TRIAL_STREAK_7", "Seven Days", "Reach a seven-day trial streak."],
	["WEEK_ALL", "A Week Well Spent", "Finish all three of a week's sect trials."],
	["ASCEND_1", "Begin Again", "Ascend for the first time."],
	# round 32: the story and the home
	["story_seeding", "What the Deep Put in You", "Answer Elder Mo after your second floor."],
	["story_first_master", "The Keeper's Keys", "Settle the third floor's share with Smith Hale."],
	["story_wens_debt", "What the Mine Remembers", "Hear Trader Wen out."],
	["story_envoy", "The Sects Take Notice", "Answer the sects' letter."],
	["story_blood", "What Runs in You", "Answer Apothecary Lin when your blood wakes."],
	["story_rival", "The One Who Counts Your Wins", "Decide about Shen."],
	["story_pagoda", "The Elder's Confession", "Hear what Elder Mo did forty years ago."],
	["story_mirror", "The Mirror", "Choose how the story ends."],
	["home_cottage", "Four Walls", "Build the cottage."],
	["home_courtyard", "A Yard of Your Own", "Build the courtyard."],
	["home_compound", "The Compound", "Build the compound."],
	["FINISHED", "The Heart of the Deep", "Walk into the Heart of the Deep, fifty floors under Eliet."],
	["story_expedition", "The Lodge Goes Down", "Answer Captain Rhee at floor 30."],
	["story_last_steel", "The Last Steel", "Answer Smith Hale at floor 35."],
	["story_sickness", "What the Deep Gives Back", "Answer Apothecary Lin at floor 40."],
	["story_last_letter", "The Last Letter", "Answer Trader Wen at floor 45."],
	["story_after", "After the Heart", "Choose what comes after."],
	# round 34: the road down, the gates, the hidden masters
	["CHAPTER_FIRST_STEPS", "The Road Down", "Finish the chapter: The Road Down."],
	["CHAPTER_THREE_FLOORS", "What the Mine Keeps", "Finish the chapter: What the Mine Keeps."],
	["CHAPTER_CONDENSE", "Condense", "Finish the chapter: Condense."],
	["CHAPTER_DEEP_BREATH", "Deep Breath", "Finish the chapter: Deep Breath."],
	["CHAPTER_FOUNDATION", "Nascent", "Finish the chapter: Nascent."],
	["CHAPTER_BLOOD_AND_DARK", "Blood and Dark", "Finish the chapter: Blood and Dark."],
	["CHAPTER_CORE", "Body and Qi as One", "Finish the chapter: Body and Qi as One."],
	["CHAPTER_THIN_AIR", "Thin Air", "Finish the chapter: Thin Air."],
	["CHAPTER_NASCENT", "Tribulation", "Finish the chapter: Tribulation."],
	["CHAPTER_STAR_IRON_DOOR", "The Star Iron Door", "Finish the chapter: The Star Iron Door."],
	["CHAPTER_THE_LETTER", "Knock Politely", "Finish the chapter: Knock Politely."],
	["CHAPTER_THE_HEART", "The Heart of the Deep", "Finish the chapter: The Heart of the Deep."],
	["GATE_6", "The Way to Floor 6", "Pass the gate to floor 6."],
	["GATE_11", "The Way to Floor 11", "Pass the gate to floor 11."],
	["GATE_16", "The Way to Floor 16", "Pass the gate to floor 16."],
	["GATE_21", "The Way to Floor 21", "Pass the gate to floor 21."],
	["GATE_26", "The Way to Floor 26", "Pass the gate to floor 26."],
	["GATE_31", "The Way to Floor 31", "Pass the gate to floor 31."],
	["GATE_36", "The Way to Floor 36", "Pass the gate to floor 36."],
	["GATE_41", "The Way to Floor 41", "Pass the gate to floor 41."],
	["GATE_46", "The Way to Floor 46", "Pass the gate to floor 46."],
	["MASTER_FOUND", "Not What They Seem", "Find a hidden master."],
	["MASTER_SWEEPER", "Grandmother Su", "Learn from Grandmother Su, the Broom Saint."],
	["MASTER_FISHER", "Old Bao of the Still Water", "Learn from Old Bao of the Still Water."],
	["MASTER_RATCATCHER", "Hollow Jin", "Learn from Hollow Jin, the Last Monk of the Warrens."],
	["MASTER_COOK", "Ma Lian", "Learn from Ma Lian, the Cauldron Sage."],
	["MASTER_BONEPICKER", "Sister Ivory of the Ossuary", "Learn from Sister Ivory of the Ossuary."],
	["MASTER_BLIND_SMITH", "Tie the Unseeing Hammer", "Learn from Tie the Unseeing Hammer."],
	["MASTER_BEGGAR", "The Ninth Man's Brother", "Learn from The Ninth Man's Brother."],
	["MASTER_CHILD", "Little Hu", "Learn from Little Hu, Who Is Older Than the Mountain."],
	["MASTER_HERMIT", "Master Wu of No Sect", "Learn from Master Wu of No Sect."],
	["MASTER_WIDOW", "Lady Rui", "Learn from Lady Rui, the Last of the First Expedition."],
	["MASTER_CLOCKMAKER", "Ticktock Fen", "Learn from Ticktock Fen, the Engine Immortal."],
	["MASTER_MIRROR", "The One Who Went Down Before You", "Learn from The One Who Went Down Before You."],
	["ALL_MASTERS", "Twelve Teachers", "Learn from every hidden master."],
]


func _init() -> void:
	var lines := ["# Steam achievements, stats and leaderboards", "",
		"Generated by tools/steam_achievements.gd -- enter these in Steamworks (App Admin > Stats & Achievements) once the game has its App ID.", "",
		"| API name | Name | Description |", "|---|---|---|"]
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	var n := 0
	if d is Dictionary:
		for a in d.get("list", []):
			lines.append("| %s | %s | %s |" % [str(a.get("id", "")).to_upper(), a.get("name", ""), a.get("desc", "")])
			n += 1
	for e in EXTRA:
		lines.append("| %s | %s | %s |" % e)
		n += 1
	var r = JSON.parse_string(FileAccess.get_file_as_string("res://data/retention.json"))
	for c in ["bestiary", "beasts", "materials", "landmarks", "discoveries", "bloodlines"]:
		lines.append("| COLL_%s | Complete: %s | Complete the %s collection. |" % [c.to_upper(), c.capitalize(), c])
		n += 1
	lines += ["", "## Stats (INT)", "", "deepest_floor, realm, blood_purity, ascensions", "",
		"## Leaderboards", "", "- deepest_floor -- descending, numeric (created by the game if missing)",
		"- daily_YYYYMMDD -- one per day for the daily trial's score (created by the game)", ""]
	var f := FileAccess.open("res://steam/achievements.md", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	print("wrote %d achievements to steam/achievements.md" % n)
	quit()
