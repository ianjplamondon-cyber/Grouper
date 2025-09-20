Grouper = LibStub("AceAddon-3.0"):NewAddon("Grouper", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
AceGUI = LibStub("AceGUI-3.0")
-- ...existing code...

-- Register CHAT_MSG_SYSTEM event to handle party join system messages (after Grouper is initialized)
function Grouper:OnChatMsgSystem(event, text)
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: CHAT_MSG_SYSTEM: " .. tostring(text))
    end
    -- Detect 'joins the party.' system message
    local joinedName = text and text:match("^(.-) joins the party%.")
    if joinedName then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: Detected party join by " .. joinedName)
        end
        -- Repopulate group data using leader's cache logic
        if IsGroupLeader() and self.groups then
            for _, group in pairs(self.groups) do
                if group.leader == UnitName("player") then
                    self:CreateGroup({
                        title = group.title,
                        description = group.description,
                        type = group.type,
                        minLevel = group.minLevel,
                        maxLevel = group.maxLevel,
                        currentSize = group.currentSize,
                        maxSize = group.maxSize,
                        location = group.location,
                        dungeons = group.dungeons
                    })
                end
            end
        end
        -- Refresh UI if open
        if self.mainFrame and self.mainFrame:IsShown() then
            self:RefreshGroupList()
        end
    end
end

-- Register event in OnInitialize
function Grouper:OnInitialize()
    -- ...existing code...
    self:RegisterEvent("CHAT_MSG_SYSTEM", "OnChatMsgSystem")
    -- ...existing code...
end

AceDB = LibStub("AceDB-3.0")
AceConfig = LibStub("AceConfig-3.0")
AceConfigDialog = LibStub("AceConfigDialog-3.0")
LibDBIcon = LibStub("LibDBIcon-1.0")

-- Constants
ADDON_NAME = "Grouper"
COMM_PREFIX = "GRPR"
ADDON_CHANNEL = "Grouper"
ADDON_VERSION = "1.0.0"

-- String utility functions
if not string.trim then
    function string:trim()
        return self:match("^%s*(.-)%s*$")
    end
end

-- Data structures
Grouper.groups = {}
Grouper.players = {}
Grouper.channelJoined = false
Grouper.currentGroupInfo = {
    inParty = false,
    inRaid = false,
    isLeader = false,
    partySize = 0,
    timestamp = 0
}

-- Default database structure
local defaults = {
    profile = {
        minimap = {
            hide = false,
        },
        notifications = {
            newGroups = true,
            groupUpdates = true,
            soundEnabled = true,
        },
        filters = {
            minLevel = 1,
            maxLevel = 60,
            dungeonTypes = {
                dungeon = true,
                raid = true,
                quest = true,
                pvp = true,
                other = true,
            },
        },
        debug = {
            enabled = false,
        },
        ui = {
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                xOfs = 0,
                yOfs = 0,
            },
        },
        autoJoin = {
            enabled = false,
            autoAccept = false,
        },
    },
 
}

                 

function Grouper:OnInitialize()
    -- Initialize database
    self.db = AceDB:New("GrouperDB", defaults, true)

    -- Initialize storage
    self.groups = {}
    self.players = {}
    self.multiPartMessages = {} -- Storage for incomplete multi-part messages
    self.grouperChannelNumber = nil -- Cache for our Grouper channel number

    -- Cache local player info at startup
    self.playerInfo = {}
    if UnitName and UnitClass and UnitRace and UnitLevel and GetRealmName then
        local name = UnitName("player")
        local class = UnitClass("player")
        local race = UnitRace("player")
        local level = UnitLevel("player")
        local realm = GetRealmName() or ""
        local fullName = name .. "-" .. realm
        local info = {
            name = name,
            class = class,
            race = race,
            level = level,
            fullName = fullName,
            lastSeen = time(),
            version = ADDON_VERSION
        }
        self.playerInfo = info
        self.players[name] = info
    end

    -- Register chat commands
    self:RegisterChatCommand("grouper", "SlashCommand")

    -- Initialize minimap icon
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimap)

    -- Create options table
    self:SetupOptions()

    self:Print("Loaded! Type /grouper to open the group finder.")
end

function Grouper:OnEnable()
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Classic Era event names for group changes
    self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyChanged")
    self:RegisterEvent("PARTY_MEMBER_ENABLE", "OnPartyChanged")
    self:RegisterEvent("PARTY_MEMBER_DISABLE", "OnPartyChanged")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "OnPartyChanged")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "OnPartyChanged")
    
    self:RegisterEvent("CHAT_MSG_CHANNEL_JOIN", "OnChannelJoin")
    self:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE", "OnChannelLeave")
    
    -- Register for party invite requests to handle auto-accept functionality
    self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInviteRequest")
    
    -- Register for channel messages to receive our protocol messages (keeping for backward compatibility)
    self:RegisterEvent("CHAT_MSG_CHANNEL", "OnChannelMessage")
    -- Note: WHISPER messages are now handled by AceComm automatically through OnCommReceived
    
    -- Register AceComm message handlers for new communication system (16 char limit)
    self:RegisterComm("GRPR_GROUP", "OnCommReceived")       -- Compact GROUP_UPDATE via channel
    self:RegisterComm("GRPR_GRP_UPD", "OnCommReceived")     -- Serialized GROUP_UPDATE via whisper
    self:RegisterComm("GRPR_GRP_RMV", "OnCommReceived")     -- GROUP_REMOVE messages
    self:RegisterComm("GRPR_CHUNK_REQ", "OnCommReceived")   -- Chunk requests
    self:RegisterComm("GRPR_CHUNK_RES", "OnCommReceived")   -- Chunk responses
    self:RegisterComm("GROUPER_TEST", "OnCommReceived")     -- Test messages
    self:RegisterComm("GrouperAutoJoin", "OnAutoJoinRequest") -- Auto-join invite requests
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: 📡 Registered AceComm prefixes: GRPR_GROUP, GRPR_GRP_UPD, GRPR_GRP_RMV, GRPR_CHUNK_REQ, GRPR_CHUNK_RES, GROUPER_TEST")
    end
    
    -- Check if already in channel, but don't auto-join
    self:ScheduleTimer("CheckInitialChannelStatus", 3)
    
    -- Cancel any existing repeating timers to prevent conflicts after reload
    -- (Don't cancel all timers as it would cancel the CheckInitialChannelStatus timer above)
    if self.presenceTimer then
        self:CancelTimer(self.presenceTimer)
    end
    if self.cleanupTimer then
        self:CancelTimer(self.cleanupTimer)
    end
    if self.chunksCleanupTimer then
        self:CancelTimer(self.chunksCleanupTimer)
    end
    
    -- Start periodic tasks and store timer handles
    self.cleanupTimer = self:ScheduleRepeatingTimer("CleanupOldGroups", 300) -- 5 minutes
    -- Disable presence timer to prevent protected function issues: self.presenceTimer = self:ScheduleRepeatingTimer("BroadcastPresence", 600)
    self.chunksCleanupTimer = self:ScheduleRepeatingTimer("CleanupOldAceCommChunks", 120) -- Clean up incomplete AceComm chunks every 2 minutes
    
    -- Auto-join is always enabled
    self:ScheduleTimer(function()
        self:Print("Auto-Join enabled: Use Auto-Join buttons for instant invite requests")
    end, 2)
end

