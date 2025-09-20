-- Dungeon data for Classic Era
DUNGEONS = {
    -- Low level dungeons (10-25)
    {name = "Ragefire Chasm", minLevel = 13, maxLevel = 18, type = "dungeon", faction = "Horde"},
    {name = "The Deadmines", minLevel = 17, maxLevel = 26, type = "dungeon", faction = "Alliance"},
    {name = "Wailing Caverns", minLevel = 17, maxLevel = 24, type = "dungeon", faction = "Both"},
    {name = "Shadowfang Keep", minLevel = 22, maxLevel = 30, type = "dungeon", faction = "Both"},
    {name = "The Stockade", minLevel = 24, maxLevel = 32, type = "dungeon", faction = "Alliance"},
    {name = "Blackfathom Deeps", minLevel = 24, maxLevel = 32, type = "dungeon", faction = "Both"},
    
    -- Mid level dungeons (25-45)
    {name = "Gnomeregan", minLevel = 29, maxLevel = 38, type = "dungeon", faction = "Both"},
    {name = "Razorfen Kraul", minLevel = 29, maxLevel = 38, type = "dungeon", faction = "Both"},
    {name = "Scarlet Monastery - Graveyard", minLevel = 32, maxLevel = 42, type = "dungeon", faction = "Both"},
    {name = "Scarlet Monastery - Library", minLevel = 32, maxLevel = 42, type = "dungeon", faction = "Both"},
    {name = "Scarlet Monastery - Armory", minLevel = 32, maxLevel = 42, type = "dungeon", faction = "Both"},
    {name = "Scarlet Monastery - Cathedral", minLevel = 35, maxLevel = 45, type = "dungeon", faction = "Both"},
    {name = "Razorfen Downs", minLevel = 37, maxLevel = 46, type = "dungeon", faction = "Both"},
    {name = "Uldaman", minLevel = 42, maxLevel = 52, type = "dungeon", faction = "Both"},
    
    -- High level dungeons (45-60)
    {name = "Zul'Farrak", minLevel = 44, maxLevel = 54, type = "dungeon", faction = "Both"},
    {name = "Maraudon", minLevel = 46, maxLevel = 55, type = "dungeon", faction = "Both"},
    {name = "Temple of Atal'Hakkar", minLevel = 50, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Blackrock Depths", minLevel = 52, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Lower Blackrock Spire", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Upper Blackrock Spire", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Dire Maul - East", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Dire Maul - West", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Dire Maul - North", minLevel = 55, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Stratholme - Live", minLevel = 58, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Stratholme - Undead", minLevel = 58, maxLevel = 60, type = "dungeon", faction = "Both"},
    {name = "Scholomance", minLevel = 58, maxLevel = 60, type = "dungeon", faction = "Both"},
    
    -- Raids
    {name = "Onyxia's Lair", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {name = "Molten Core", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {name = "Blackwing Lair", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {name = "Zul'Gurub", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {name = "Ahn'Qiraj (AQ20)", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {name = "Temple of Ahn'Qiraj (AQ40)", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    {name = "Naxxramas", minLevel = 60, maxLevel = 60, type = "raid", faction = "Both"},
    
    -- Battlegrounds
    {name = "Warsong Gulch", minLevel = 10, maxLevel = 60, type = "pvp", faction = "Both", brackets = {
        {name = "10-19", minLevel = 10, maxLevel = 19},
        {name = "20-29", minLevel = 20, maxLevel = 29},
        {name = "30-39", minLevel = 30, maxLevel = 39},
        {name = "40-49", minLevel = 40, maxLevel = 49},
        {name = "50-59", minLevel = 50, maxLevel = 59},
        {name = "60", minLevel = 60, maxLevel = 60}
    }},
    {name = "Arathi Basin", minLevel = 20, maxLevel = 60, type = "pvp", faction = "Both", brackets = {
        {name = "20-29", minLevel = 20, maxLevel = 29},
        {name = "30-39", minLevel = 30, maxLevel = 39},
        {name = "40-49", minLevel = 40, maxLevel = 49},
        {name = "50-59", minLevel = 50, maxLevel = 59},
        {name = "60", minLevel = 60, maxLevel = 60}
    }},
    {name = "Alterac Valley", minLevel = 51, maxLevel = 60, type = "pvp", faction = "Both", brackets = {
        {name = "51-60", minLevel = 51, maxLevel = 60}
    }},
}
