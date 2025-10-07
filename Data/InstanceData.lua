-- Dungeon/raid/battleground ID mapping for encoding
DUNGEON_IDS = {
    ["Ragefire Chasm"] = 1,
    ["The Deadmines"] = 2,
    ["Wailing Caverns"] = 3,
    ["Shadowfang Keep"] = 4,
    ["The Stockade"] = 5,
    ["Blackfathom Deeps"] = 6,
    ["Gnomeregan"] = 7,
    ["Razorfen Kraul"] = 8,
    ["Scarlet Monastery - Graveyard"] = 9,
    ["Scarlet Monastery - Library"] = 10,
    ["Scarlet Monastery - Armory"] = 11,
    ["Scarlet Monastery - Cathedral"] = 12,
    ["Razorfen Downs"] = 13,
    ["Uldaman"] = 14,
    ["Zul'Farrak"] = 15,
    ["Maraudon"] = 16,
    ["Temple of Atal'Hakkar"] = 17,
    ["Blackrock Depths"] = 18,
    ["Lower Blackrock Spire"] = 19,
    ["Upper Blackrock Spire"] = 20,
    ["Dire Maul - East"] = 21,
    ["Dire Maul - West"] = 22,
    ["Dire Maul - North"] = 23,
    ["Stratholme - Live"] = 24,
    ["Stratholme - Undead"] = 25,
    ["Scholomance"] = 26,
    -- Raids
    ["Onyxia's Lair"] = 27,
    ["Molten Core"] = 28,
    ["Blackwing Lair"] = 29,
    ["Zul'Gurub"] = 30,
    ["Ahn'Qiraj (AQ20)"] = 31,
    ["Temple of Ahn'Qiraj (AQ40)"] = 32,
    ["Naxxramas"] = 33,
    -- Battlegrounds
    ["Warsong Gulch"] = 34,
    ["Arathi Basin"] = 35,
    ["Alterac Valley"] = 36,
}

DUNGEONS = {
    -- Low level dungeons (10-25)
    {id = DUNGEON_IDS["Ragefire Chasm"], name = "Ragefire Chasm", minLevel = 13, maxLevel = 18, type = "dungeon", faction = "Horde"},
    {id = DUNGEON_IDS["The Deadmines"], name = "The Deadmines", minLevel = 17, maxLevel = 26, type = "dungeon", faction = "Alliance"},
    {id = DUNGEON_IDS["Wailing Caverns"], name = "Wailing Caverns", minLevel = 17, maxLevel = 24, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Shadowfang Keep"], name = "Shadowfang Keep", minLevel = 22, maxLevel = 30, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["The Stockade"], name = "The Stockade", minLevel = 24, maxLevel = 32, type = "dungeon", faction = "Alliance"},
    {id = DUNGEON_IDS["Blackfathom Deeps"], name = "Blackfathom Deeps", minLevel = 24, maxLevel = 32, type = "dungeon", faction = "Both"},
    
    -- Mid level dungeons (25-45)
    {id = DUNGEON_IDS["Gnomeregan"], name = "Gnomeregan", minLevel = 29, maxLevel = 38, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Razorfen Kraul"], name = "Razorfen Kraul", minLevel = 29, maxLevel = 38, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Scarlet Monastery - Graveyard"], name = "Scarlet Monastery - Graveyard", minLevel = 32, maxLevel = 42, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Scarlet Monastery - Library"], name = "Scarlet Monastery - Library", minLevel = 32, maxLevel = 42, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Scarlet Monastery - Armory"], name = "Scarlet Monastery - Armory", minLevel = 32, maxLevel = 42, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Scarlet Monastery - Cathedral"], name = "Scarlet Monastery - Cathedral", minLevel = 35, maxLevel = 45, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Razorfen Downs"], name = "Razorfen Downs", minLevel = 37, maxLevel = 46, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Uldaman"], name = "Uldaman", minLevel = 42, maxLevel = 52, type = "dungeon", faction = "Both"},
    
    -- High level dungeons (45-60)
    {id = DUNGEON_IDS["Zul'Farrak"], name = "Zul'Farrak", minLevel = 44, maxLevel = 54, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Maraudon"], name = "Maraudon", minLevel = 46, maxLevel = 55, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Temple of Atal'Hakkar"], name = "Temple of Atal'Hakkar", minLevel = 50, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Blackrock Depths"], name = "Blackrock Depths", minLevel = 52, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Lower Blackrock Spire"], name = "Lower Blackrock Spire", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Upper Blackrock Spire"], name = "Upper Blackrock Spire", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Dire Maul - East"], name = "Dire Maul - East", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Dire Maul - West"], name = "Dire Maul - West", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Dire Maul - North"], name = "Dire Maul - North", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Stratholme - Live"], name = "Stratholme - Live", minLevel = 58, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Stratholme - Undead"], name = "Stratholme - Undead", minLevel = 58, maxLevel = 60, type = "dungeon", faction = "Both"},
    {id = DUNGEON_IDS["Scholomance"], name = "Scholomance", minLevel = 58, maxLevel = 60, type = "dungeon", faction = "Both"},
    
    -- Raids
    {id = DUNGEON_IDS["Onyxia's Lair"], name = "Onyxia's Lair", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {id = DUNGEON_IDS["Molten Core"], name = "Molten Core", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {id = DUNGEON_IDS["Blackwing Lair"], name = "Blackwing Lair", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {id = DUNGEON_IDS["Zul'Gurub"], name = "Zul'Gurub", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {id = DUNGEON_IDS["Ahn'Qiraj (AQ20)"], name = "Ahn'Qiraj (AQ20)", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {id = DUNGEON_IDS["Temple of Ahn'Qiraj (AQ40)"], name = "Temple of Ahn'Qiraj (AQ40)", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {id = DUNGEON_IDS["Naxxramas"], name = "Naxxramas", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    
    -- Battlegrounds
    {id = DUNGEON_IDS["Warsong Gulch"], name = "Warsong Gulch", minLevel = 10, maxLevel = 60, type = "pvp", faction = "Both", brackets = {
        {name = "10-19", minLevel = 10, maxLevel = 19},
        {name = "20-29", minLevel = 20, maxLevel = 29},
        {name = "30-39", minLevel = 30, maxLevel = 39},
        {name = "40-49", minLevel = 40, maxLevel = 49},
        {name = "50-59", minLevel = 50, maxLevel = 59},
        {name = "60", minLevel = 60, maxLevel = 60}
    }},
    {id = DUNGEON_IDS["Arathi Basin"], name = "Arathi Basin", minLevel = 20, maxLevel = 60, type = "pvp", faction = "Both", brackets = {
        {name = "20-29", minLevel = 20, maxLevel = 29},
        {name = "30-39", minLevel = 30, maxLevel = 39},
        {name = "40-49", minLevel = 40, maxLevel = 49},
        {name = "50-59", minLevel = 50, maxLevel = 59},
        {name = "60", minLevel = 60, maxLevel = 60}
    }},
    {id = DUNGEON_IDS["Alterac Valley"], name = "Alterac Valley", minLevel = 51, maxLevel = 60, type = "pvp", faction = "Both", brackets = {
        {name = "51-60", minLevel = 51, maxLevel = 60}
    }},
}
