local Grouper = LibStub("AceAddon-3.0"):NewAddon("Grouper", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LibDBIcon = LibStub("LibDBIcon-1.0")

-- Constants
local ADDON_NAME = "Grouper"
local COMM_PREFIX = "GRPR"
local ADDON_CHANNEL = "Grouper"
local ADDON_VERSION = "1.0.0"

-- Dungeon data for Classic Era
local DUNGEONS = {
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
}

-- Classic Era API Compatibility Functions
local function GetGroupSize()
    -- Returns number of people in your group (including yourself)
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return GetNumRaidMembers()
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        return GetNumPartyMembers()
    else
        return 0 -- Solo
    end
end

local function IsInGroup()
    return GetGroupSize() > 0
end

local function IsInRaidGroup()
    return GetNumRaidMembers and GetNumRaidMembers() > 0 or false
end

local function IsInPartyGroup()
    return GetNumPartyMembers and GetNumPartyMembers() > 0 or false
end

local function IsGroupLeader()
    if IsInRaidGroup() then
        return IsRaidLeader and IsRaidLeader() or false
    elseif IsInPartyGroup() then
        return IsPartyLeader and IsPartyLeader() or false
    else
        return false
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
                other = true,
            },
        },
        debug = {
            enabled = false,
        },
    },
}

-- Data broker for minimap
local dataObj = {
    type = "data source",
    text = "Grouper",
    icon = "Interface\\AddOns\\Grouper\\Textures\\GrouperIcon.png",
    OnClick = function(self, button)
        if button == "LeftButton" then
            Grouper:ToggleMainWindow()
        elseif button == "RightButton" then
            Grouper:ShowConfig()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Grouper")
        tooltip:AddLine("|cffeda55fLeft-click|r to open group finder")
        tooltip:AddLine("|cffeda55fRight-click|r for options")
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("Active Groups:", #Grouper.groups)
        tooltip:AddDoubleLine("Online Players:", #Grouper.players)
    end,
}

function Grouper:OnInitialize()
    -- Initialize database
    self.db = AceDB:New("GrouperDB", defaults, true)
    
    -- Initialize storage
    self.groups = {}
    self.players = {}
    self.multiPartMessages = {} -- Storage for incomplete multi-part messages
    self.grouperChannelNumber = nil -- Cache for our Grouper channel number
    
    -- Register chat commands
    self:RegisterChatCommand("grouper", "SlashCommand")
    
    -- Initialize minimap icon
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimap)
    
    -- Create options table
    self:SetupOptions()
    
    self:Print("Loaded! Type /grouper to open the group finder.")
end

-- Helper function for debug checking
function Grouper:IsDebugEnabled()
    return self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled
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
    
    -- Register for channel messages to receive our protocol messages (keeping for backward compatibility)
    self:RegisterEvent("CHAT_MSG_CHANNEL", "OnChannelMessage")
    -- Note: WHISPER messages are now handled by AceComm automatically through OnCommReceived
    
    -- Register AceComm message handlers for new communication system (16 char limit)
    self:RegisterComm("GRPR_GROUP", "OnCommReceived")       -- Compact GROUP_UPDATE with ChatThrottleLib
    self:RegisterComm("GRPR_GRP_UPD", "OnCommReceived")     -- GROUP_UPDATE
    self:RegisterComm("GROUP_UPDATE", "OnCommReceived")     -- Direct GROUP_UPDATE for responses
    self:RegisterComm("GRPR_REQ_DATA", "OnCommReceived")    -- REQUEST_DATA  
    self:RegisterComm("GRPR_PRESENCE", "OnCommReceived")    -- PRESENCE
    self:RegisterComm("GRPR_TEST", "OnCommReceived")        -- TEST
    self:RegisterComm("GRPR_GRP_UPD", "OnCommReceived")     -- GROUP_UPDATE through SendComm (16 chars max)
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: 📡 Registered AceComm prefixes: GROUP_UPDATE, GRPR_REQ_DATA, GRPR_PRESENCE, GRPR_TEST, GRPR_GRP_UPD")
    end
    
    -- Register GROUPER_ prefixes for standard AceComm communication
    self:RegisterComm("GROUPER_TEST", "OnCommReceived")         -- Test messages (12 chars)
    self:RegisterComm("GRPR_CHUNK_REQ", "OnCommReceived")       -- Chunk requests (13 chars)
    self:RegisterComm("GRPR_CHUNK_RES", "OnCommReceived")       -- Chunk resends (13 chars)
    
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
    self.cleanupTimer = self:ScheduleRepeatingTimer("CleanupOldGroups", 60) -- Clean up every minute
    -- Disable presence timer to prevent protected function issues: self.presenceTimer = self:ScheduleRepeatingTimer("BroadcastPresence", 600)
    self.chunksCleanupTimer = self:ScheduleRepeatingTimer("CleanupOldAceCommChunks", 120) -- Clean up incomplete AceComm chunks every 2 minutes
end

function Grouper:OnDisable()
    -- Cancel specific timers when the addon is disabled
    if self.presenceTimer then
        self:CancelTimer(self.presenceTimer)
        self.presenceTimer = nil
    end
    if self.cleanupTimer then
        self:CancelTimer(self.cleanupTimer)
        self.cleanupTimer = nil
    end
    if self.chunksCleanupTimer then
        self:CancelTimer(self.chunksCleanupTimer)
        self.chunksCleanupTimer = nil
    end
    if self.flushTimer then
        self:CancelTimer(self.flushTimer)
        self.flushTimer = nil
    end
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: Addon disabled, repeating timers cancelled")
    end
end

function Grouper:CheckInitialChannelStatus()
    local channelIndex = GetChannelName(ADDON_CHANNEL)
    if channelIndex > 0 then
        self.channelJoined = true
        self.grouperChannelNumber = channelIndex  -- Initialize cache on startup
        self:Print("Connected to Grouper channel!")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Initialized channel cache to %d on startup", channelIndex))
        end
    else
        self:Print("Use /grouper show to open the group finder (will auto-join channel)")
    end
end

function Grouper:OnPlayerEnteringWorld()
    -- Just check channel status, don't auto-join
    self:ScheduleTimer("CheckInitialChannelStatus", 5)
end

function Grouper:EnsureChannelJoined()
    -- Check if we're already in the channel
    local channelIndex = GetChannelName(ADDON_CHANNEL)
    if channelIndex > 0 then
        self.channelJoined = true
        return -- Already connected
    end
    
    -- Not in channel, automatically join
    if not InCombatLockdown() then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Auto-joining Grouper channel when opening UI")
        end
        
        -- Execute the join command using the slash command system
        SlashCmdList["JOIN"]("Grouper")
        
        -- Give feedback to user
        self:Print("Joining Grouper channel for group communication...")
        
        -- Schedule a check to see if it worked
        self:ScheduleTimer("CheckChannelJoinResult", 2)
    else
        -- In combat, just inform the user
        self:Print("Cannot join channel during combat. Please try again after combat or manually type: /join Grouper")
    end
end

function Grouper:CheckChannelJoinResult()
    local channelIndex = GetChannelName(ADDON_CHANNEL)
    if channelIndex > 0 then
        self.channelJoined = true
        self.grouperChannelNumber = channelIndex  -- Cache the channel number after joining
        self:Print("Successfully connected to Grouper channel!")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Cached channel number %d after joining", channelIndex))
        end
    else
        self:Print("Failed to auto-join channel. Please manually type: /join Grouper")
    end
end

function Grouper:CheckChannelStatus()
    -- Don't check during combat
    if InCombatLockdown() then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Cannot check channel during combat, retrying in 5 seconds")
        end
        self:ScheduleTimer("CheckChannelStatus", 5)
        return
    end
    
    if not self.channelJoined then
        local success, channelIndex = pcall(GetChannelName, ADDON_CHANNEL)
        if success and channelIndex > 0 then
            self.channelJoined = true
            self:Print("Successfully connected to Grouper channel!")
            -- Request current group data from other users
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Requesting group data from other players")
            end
            self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
        else
            -- Still not connected, try again
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Still connecting to Grouper channel...")
            end
            self:ScheduleTimer("EnsureChannelJoined", 5)
        end
    end
end

function Grouper:OnChannelJoin(event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    if channelBaseName == ADDON_CHANNEL and playerName == UnitName("player") then
        self.channelJoined = true
        self.grouperChannelNumber = channelIndex -- Cache the channel number
        self:Print(string.format("Successfully joined Grouper channel %d!", channelIndex))
        -- Request current group data from other users
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Requesting group data from other players")
        end
        self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
    end
end

function Grouper:OnChannelLeave(event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName)
    if channelBaseName == ADDON_CHANNEL and playerName == UnitName("player") then
        self.channelJoined = false
        self.grouperChannelNumber = nil -- Clear cached channel number
        self:Print("Disconnected from Grouper channel. Reconnecting...")
        self:ScheduleTimer("EnsureChannelJoined", 5)
    end
end

function Grouper:OnPartyChanged(event)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Group changed event: %s", event or "unknown"))
    end
    
    -- Get current group information with Classic Era compatibility
    local inParty = IsInPartyGroup()
    local inRaid = IsInRaidGroup()
    local isLeader = IsGroupLeader()
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Party: %s, Raid: %s, Leader: %s", 
            tostring(inParty), tostring(inRaid), tostring(isLeader)))
    end
    
    -- Update our current group status
    local partySize = GetGroupSize()
    
    self.currentGroupInfo = {
        inParty = inParty,
        inRaid = inRaid,
        isLeader = isLeader,
        partySize = partySize,
        timestamp = time()
    }
    
    -- If we're no longer in a group, we can create new groups
    -- If we joined a group, we might need to remove our posted groups
    if inParty or inRaid then
        -- We're in a group - consider removing any groups we posted as LFG
        self:HandleJoinedGroup()
    else
        -- We left a group - we can post new groups again
        self:HandleLeftGroup()
    end
    
    -- Disable presence broadcast to prevent protected function issues: self:BroadcastPresence()
    
    -- Refresh UI if it's open
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshGroupList()
    end
end

function Grouper:HandleJoinedGroup()
    -- Player joined a group - they might not need their LFG posts anymore
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: Player joined a group")
    end
    
    -- Check if we have any active groups posted
    local myGroups = {}
    for i, group in ipairs(self.groups) do
        if group.leader == UnitName("player") then
            table.insert(myGroups, group)
        end
    end
    
    if #myGroups > 0 then
        -- Ask the player if they want to remove their posted groups
        -- For now, just notify them
        self:Print(string.format("You joined a group! You have %d group(s) posted. Use /grouper show to manage them.", #myGroups))
    end
end

function Grouper:HandleLeftGroup()
    -- Player left a group - they can post new groups again
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: Player left a group")
    end
    
    -- They can now create new groups if they want
    -- No automatic action needed, just update state
end

-- Communication functions using AceComm-3.0
function Grouper:SendComm(messageType, data, distribution, target, priority)
    -- For GROUP_UPDATE and REQUEST_DATA, use direct channel messaging for CHANNEL distribution
    -- But allow WHISPER and other distributions to use proper AceComm
    if messageType == "GROUP_UPDATE" and (distribution == "CHANNEL" or not distribution) then
        return self:SendGroupUpdateViaChannel(data)
    elseif messageType == "REQUEST_DATA" and (distribution == "CHANNEL" or not distribution) then
        return self:SendRequestDataViaChannel(data)
    end
    
    -- For WHISPER and other distributions, use standard AceComm which works fine
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ SendComm called with messageType='%s', distribution='%s'", messageType, distribution or "default"))
    end
    
    local message = {
        type = messageType,
        sender = UnitName("player"),
        timestamp = time(),
        version = ADDON_VERSION,
        data = data
    }
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Sending %s message via AceComm", messageType))
    end
    
    -- Use AceComm for all communication with appropriate priority
    local commPriority = priority or "NORMAL"
    if messageType == "TEST" then
        commPriority = "ALERT"  -- Use ALERT priority for immediate test message delivery
    end
    local distributionType = distribution or "CHANNEL"  -- Default to CHANNEL for server-wide communication
    local commTarget = target
    
    -- For server-wide broadcasts, use CHANNEL distribution with the Grouper channel number
    if distributionType == "CHANNEL" then
        local channelIndex = self:GetGrouperChannelIndex()
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ⚡ GetGrouperChannelIndex() returned: %d", channelIndex))
        end
        if channelIndex <= 0 then
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: ✗ Cannot send AceComm - not in Grouper channel")
            end
            return false
        end
        commTarget = channelIndex  -- Use the channel number for AceComm
    end
    
    local success, errorMsg = pcall(function()
        local prefix = "GRPR_" .. messageType
        -- Shorten GROUP_UPDATE to fit 16-char limit
        if messageType == "GROUP_UPDATE" then
            prefix = "GRPR_GRP_UPD"
        end
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ⚡ Sending AceComm with prefix='%s' to channel %d", prefix, commTarget))
        end
        self:SendCommMessage(prefix, self:Serialize(message), distributionType, commTarget, commPriority)
    end)
    
    if success then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ AceComm %s sent successfully via %s", messageType, distributionType))
        end
        return true
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✗ FAILED to send AceComm %s: %s", messageType, tostring(errorMsg)))
        end
        return false
    end
end

-- Helper function to get cached channel number with fallback
function Grouper:GetGrouperChannelIndex()
    -- Use cached value if available
    if self.grouperChannelNumber and self.grouperChannelNumber > 0 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Using cached channel number: %d", self.grouperChannelNumber))
        end
        return self.grouperChannelNumber
    end
    
    -- Fallback to lookup and cache the result
    local channelIndex = GetChannelName(ADDON_CHANNEL)
    if channelIndex > 0 then
        self.grouperChannelNumber = channelIndex
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Caching new channel number: %d", channelIndex))
        end
    end
    
    return channelIndex
end

function Grouper:SendGroupUpdateViaChannel(groupData)
    -- Use direct channel messaging like the working direct channel test
    local channelIndex = self:GetGrouperChannelIndex()
    if channelIndex <= 0 then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ✗ Cannot send GROUP_UPDATE - not in Grouper channel")
        end
        return false
    end
    
    -- Use the same encoding logic as SendGroupUpdateDirectly
    local title = groupData.title or ""
    if string.len(title) > 20 then
        title = string.sub(title, 1, 20)
    end
    
    local location = groupData.location or ""
    if string.len(location) > 20 then
        location = string.sub(location, 1, 20)
    end
    
    -- Encode the event type as a number (1=Dungeon, 2=Raid, 3=Quest, 4=PvP, 5=Other)
    local typeId = groupData.typeId or 1
    
    -- Encode the selected dungeon as a number (0 = no specific dungeon)
    local dungeonId = 0
    if groupData.dungeons and next(groupData.dungeons) then
        -- Find the first selected dungeon and use its index
        for dungeonName, selected in pairs(groupData.dungeons) do
            if selected then
                for i, dungeon in ipairs(DUNGEONS) do
                    if dungeon.name == dungeonName then
                        dungeonId = i
                        break
                    end
                end
                break -- Use first selected dungeon
            end
        end
    end
    
    -- Encode the leader's role as a number (1=Tank, 2=Healer, 3=DPS)
    local roleId = 3 -- Default to DPS
    local leaderName = groupData.leader or UnitName("player")
    local leaderRole = nil
    
    -- Get role from group members
    if groupData.members and groupData.members[leaderName] then
        leaderRole = groupData.members[leaderName].role
    end
    
    -- If not found, try groupData.role or groupData.myRole
    if not leaderRole then
        leaderRole = groupData.role or groupData.myRole
    end
    
    -- Convert role string to roleId
    if leaderRole then
        if leaderRole == "tank" then
            roleId = 1
        elseif leaderRole == "healer" then
            roleId = 2
        elseif leaderRole == "dps" then
            roleId = 3
        end
    end
    
    -- Create compact encoded message: GRPR_GROUP_UPDATE:id:title:typeId:dungeonId:currentSize:maxSize:location:timestamp:leader:roleId
    local message = string.format("GRPR_GROUP_UPDATE:%s:%s:%d:%d:%d:%d:%s:%d:%s:%d",
        groupData.id or "",
        title,
        typeId,
        dungeonId,
        groupData.currentSize or 1,
        groupData.maxSize or 5,
        location,
        groupData.timestamp or time(),
        groupData.leader or UnitName("player"),
        roleId
    )
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ Sending encoded GROUP_UPDATE via direct channel %d: %s", channelIndex, message))
    end
    
    -- Send via direct channel message (same method as working direct channel test)
    SendChatMessage(message, "CHANNEL", nil, channelIndex)
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: ✓ GROUP_UPDATE sent via direct channel")
    end
    
    return true
end

function Grouper:SendRequestDataViaChannel(data)
    -- Use direct channel messaging for REQUEST_DATA
    local channelIndex = self:GetGrouperChannelIndex()
    if channelIndex <= 0 then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ✗ Cannot send REQUEST_DATA - not in Grouper channel")
        end
        return false
    end
    
    -- Create simple REQUEST_DATA message
    local message = string.format("GRPR_REQUEST_DATA:%s:%d", 
        UnitName("player"),
        time()
    )
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ Sending REQUEST_DATA via direct channel %d: %s", channelIndex, message))
    end
    
    -- Send via direct channel message
    SendChatMessage(message, "CHANNEL", nil, channelIndex)
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: ✓ REQUEST_DATA sent via direct channel")
    end
    
    return true
end

function Grouper:HandleDirectGroupUpdate(message, sender)
    -- Parse: GRPR_GROUP_UPDATE:id:title:typeId:dungeonId:currentSize:maxSize:location:timestamp:leader:roleId
    local parts = {string.split(":", message)}
    if #parts < 11 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid direct GROUP_UPDATE format from %s (got %d parts, expected 11)", sender, #parts))
        end
        return
    end
    
    local typeId = tonumber(parts[4]) or 1
    local dungeonId = tonumber(parts[5]) or 0
    local roleId = tonumber(parts[11]) or 3
    
    -- Decode type information
    local typeNames = {
        [1] = "dungeon",
        [2] = "raid", 
        [3] = "quest",
        [4] = "pvp",
        [5] = "other"
    }
    local groupType = typeNames[typeId] or "dungeon"
    
    -- Reconstruct level ranges from DUNGEONS table
    local minLevel = 1
    local maxLevel = 60
    local dungeonName = ""
    
    if dungeonId > 0 and dungeonId <= #DUNGEONS then
        local dungeon = DUNGEONS[dungeonId]
        minLevel = dungeon.minLevel
        maxLevel = dungeon.maxLevel
        dungeonName = dungeon.name
    elseif groupType == "dungeon" then
        -- Default dungeon level range
        minLevel = 13
        maxLevel = 18
    elseif groupType == "raid" then
        -- Default raid level range
        minLevel = 50
        maxLevel = 60
    end
    
    -- Decode role information
    local roleNames = {
        [1] = "tank",
        [2] = "healer",
        [3] = "dps"
    }
    local leaderRole = roleNames[roleId] or "dps"
    
    local groupData = {
        id = parts[2],
        title = parts[3], 
        type = groupType,
        typeId = typeId,
        leader = parts[10],
        timestamp = tonumber(parts[9]) or time(),
        currentSize = tonumber(parts[6]) or 1,
        maxSize = tonumber(parts[7]) or 5,
        location = parts[8] or "",
        minLevel = minLevel,
        maxLevel = maxLevel,
        dungeons = dungeonId > 0 and {[dungeonName] = true} or {},
        members = {
            [parts[10]] = {
                name = parts[10],
                role = leaderRole
            }
        }
    }
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing encoded GROUP_UPDATE: %s (%s) type=%s, dungeon=%s, levels=%d-%d from %s", 
            groupData.id, groupData.title, groupData.type, dungeonName, minLevel, maxLevel, sender))
    end
    
    -- Use the same processing as other group updates
    self:HandleGroupUpdate(groupData, sender)
end

function Grouper:HandleDirectRequestData(message, sender)
    -- Parse: GRPR_REQUEST_DATA:requester:timestamp
    local parts = {string.split(":", message)}
    if #parts < 3 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid REQUEST_DATA format from %s", sender))
        end
        return
    end
    
    local requester = parts[2]
    local timestamp = tonumber(parts[3]) or time()
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing REQUEST_DATA from %s, sending our groups via WHISPER", requester))
    end
    
    -- Delay the response slightly to avoid rapid message sending
    self:ScheduleTimer(function()
        -- Send all our groups to the requester via WHISPER using the same encoded format as direct channel
        for groupId, group in pairs(self.groups) do
            if group.leader == UnitName("player") then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Sending our group %s (%s) via WHISPER to %s using encoded format", groupId, group.title, requester))
                end
                
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: ⚡ Sending GROUP_UPDATE via addon whisper to %s using AceComm format", requester))
                end
                
                -- Use AceComm format for addon whisper (system message, no chat tab)
                -- This will be processed by OnCommReceived and use HandleGroupUpdate
                local message = {
                    type = "GROUP_UPDATE",
                    sender = UnitName("player"),
                    timestamp = time(),
                    version = ADDON_VERSION,
                    data = group
                }
                
                local success = self:SendCommMessage("GRPR_GRP_UPD", self:Serialize(message), "WHISPER", requester, "NORMAL")
                
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: AceComm addon whisper result: %s", success and "SUCCESS" or "FAILED"))
                end
            end
        end
    end, 0.5) -- 500ms delay
end

function Grouper:SendGroupUpdateDirectly(groupData)
    -- Send GROUP_UPDATE using AceComm with ChatThrottleLib and BULK priority
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: Sending GROUP_UPDATE using AceComm with ChatThrottleLib and BULK priority")
    end
    
    -- Create a simplified compact message format with dungeon, type, and role encoding
    -- Format: GRPR_GROUP#id#title(20)#typeId#dungeonId#currentSize#maxSize#location(20)#timestamp#leader#roleId
    local title = groupData.title or ""
    if string.len(title) > 20 then
        title = string.sub(title, 1, 20)
    end
    
    local location = groupData.location or ""
    if string.len(location) > 20 then
        location = string.sub(location, 1, 20)
    end
    
    -- Encode the event type as a number (1=Dungeon, 2=Raid, 3=Quest, 4=PvP, 5=Other)
    local typeId = groupData.typeId or 1
    
    -- Encode the selected dungeon as a number (0 = no specific dungeon)
    local dungeonId = 0
    if groupData.dungeons and next(groupData.dungeons) then
        -- Find the first selected dungeon and use its index
        for dungeonName, selected in pairs(groupData.dungeons) do
            if selected then
                for i, dungeon in ipairs(DUNGEONS) do
                    if dungeon.name == dungeonName then
                        dungeonId = i
                        break
                    end
                end
                break -- Use first selected dungeon
            end
        end
    end
    
    -- Encode the leader's role as a number (1=Tank, 2=Healer, 3=DPS)
    -- Get the actual role from group members or groupData, ignoring "leader" as a role
    local roleId = 3 -- Default to DPS
    local leaderName = groupData.leader or UnitName("player")
    local leaderRole = nil
    
    -- First try to get role from group members
    if groupData.members and groupData.members[leaderName] then
        leaderRole = groupData.members[leaderName].role
    end
    
    -- If not found, try groupData.role or groupData.myRole
    if not leaderRole then
        leaderRole = groupData.role or groupData.myRole
    end
    
    -- Convert role string to roleId, ignoring "leader" since that's a status, not a role
    if leaderRole then
        if leaderRole == "tank" then
            roleId = 1
        elseif leaderRole == "healer" then
            roleId = 2
        elseif leaderRole == "dps" then
            roleId = 3
        -- If role is "leader", we keep the default DPS (3)
        end
    end
    
    local compactMessage = string.format("GRPR_GROUP#%s#%s#%d#%d#%d#%d#%s#%d#%s#%d",
        groupData.id or "",
        title,
        typeId,
        dungeonId,
        groupData.currentSize or 1,
        groupData.maxSize or 5,
        location,
        groupData.timestamp or time(),
        groupData.leader or UnitName("player"),
        roleId
    )
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Sending type+dungeon+role-encoded GROUP_UPDATE (%d chars): %s", 
            string.len(compactMessage), compactMessage))
    end
    
    -- Use AceComm with ChatThrottleLib and NORMAL priority for timely delivery
    -- This provides proper throttling while ensuring group updates arrive promptly
    local channelIndex = self:GetGrouperChannelIndex()
    if channelIndex <= 0 then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ✗ Cannot send GROUP_UPDATE - not in Grouper channel")
        end
        return false
    end
    
    local success, errorMsg = pcall(function()
        self:SendCommMessage("GRPR_GROUP", compactMessage, "CHANNEL", channelIndex, "NORMAL")
    end)
    
    if success then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ✓ AceComm GROUP_UPDATE sent successfully with NORMAL priority")
        end
        return true
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✗ FAILED to send AceComm GROUP_UPDATE: %s", tostring(errorMsg)))
        end
        return false
    end
end

function Grouper:OnChannelMessage(event, message, sender, language, channelString, target, flags, unknown, channelNumber, channelName, instanceID)
    -- Process messages from any "Grouper" channel regardless of number
    if channelName ~= ADDON_CHANNEL then
        -- Only show debug for non-Grouper channels if specifically requested
        if self.db.profile.debug.enabled and self.db.profile.debug.showAllChannels then
            self:Print(string.format("DEBUG: [OTHER CHANNEL] Ignoring message from channel '%s' (not '%s')", channelName or "nil", ADDON_CHANNEL))
        end
        return
    end
    
    -- Ignore messages from ourselves to prevent self-processing
    local playerName = UnitName("player")
    local playerServer = GetRealmName()
    -- Normalize realm name by removing spaces (WoW chat shows "OldBlanchy" but GetRealmName() returns "Old Blanchy")
    if playerServer then
        playerServer = playerServer:gsub("%s+", "")
    end
    local fullPlayerName = playerName .. "-" .. playerServer
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Self-check - playerName: '%s', playerServer: '%s', fullPlayerName: '%s', sender: '%s'", 
            playerName or "nil", playerServer or "nil", fullPlayerName or "nil", sender or "nil"))
    end
    
    if sender == playerName or sender == fullPlayerName then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Ignoring message from self (%s)", sender))
        end
        return
    end
    
    -- Debug: Log Grouper channel messages only
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: [RAW EVENT] CHAT_MSG_CHANNEL fired - Channel: %d (%s), Sender: %s", channelNumber or 0, channelName or "nil", sender or "nil"))
    end
    
    -- Check for direct test messages
    if message:match("^GRPR_DIRECT_TEST:") then
        local testSender = message:match("^GRPR_DIRECT_TEST:(.+)")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL TEST from %s (sent by %s)", sender, testSender))
        end
        return
    end
    
    -- Check for direct GROUP_UPDATE messages
    if message:match("^GRPR_GROUP_UPDATE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_UPDATE from %s", sender))
        end
        self:HandleDirectGroupUpdate(message, sender)
        return
    end
    
    -- Check for direct REQUEST_DATA messages
    if message:match("^GRPR_REQUEST_DATA:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL REQUEST_DATA from %s", sender))
        end
        self:HandleDirectRequestData(message, sender)
        return
    end
    
    -- Check if this is our protocol message (legacy GRPR# or GRPR_GROUP# or GRPR_MP# or GRPR_REQ# or new AceComm-style GROUPER_)
    if not message:match("^GRPR#") and not message:match("^GRPR_GROUP#") and not message:match("^GRPR_MP#") and not message:match("^GRPR_REQ#") and not message:match("^GROUPER_") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Message doesn't match any protocol: %s", string.sub(message, 1, 50)))
        end
        return -- Not our protocol
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: [CHANNEL] Received message from %s: %s", sender, string.sub(message, 1, 100) .. "..."))
    end
    
    -- Handle AceComm-style messages
    if message:match("^GROUPER_") then
        self:HandleAceCommStyleMessage(message, sender)
    elseif message:match("^GRPR_GROUP#") then
        -- Handle compact group updates
        self:HandleCompactGroupUpdate(message, sender)
    elseif message:match("^GRPR_REQ#") then
        -- Handle chunk resend requests
        self:HandleChunkRequest(message, sender)
    elseif message:match("^GRPR_MP#") then
        -- Handle legacy multi-part messages
        self:HandleLegacyMultiPartMessage(message, sender)
    else
        -- Handle legacy GRPR# messages
        self:HandleLegacyMessage(message, sender)
    end
end

-- Handle AceComm-style messages sent via channel
function Grouper:HandleAceCommStyleMessage(message, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing AceComm-style channel message from %s", sender))
    end
    
    -- Parse AceComm-style message: GROUPER_TYPE#data or GROUPER_TYPE#msgid#chunk#total#data
    local parts = {strsplit("#", message)}
    local prefix = parts[1] -- GROUPER_MESSAGE_TYPE
    
    if not prefix then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Invalid AceComm-style message format")
        end
        return
    end
    
    -- Extract message type from prefix
    local messageType = prefix:match("^GROUPER_(.+)$")
    if not messageType then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid AceComm prefix: %s", prefix))
        end
        return
    end
    
    if #parts == 2 then
        -- Single message: GROUPER_TYPE#data
        local serializedData = parts[2]
        local success, data = self:Deserialize(serializedData)
        if success then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Successfully processed single AceComm-style message"))
            end
            self:ProcessReceivedMessage(messageType, data, sender)
        else
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Failed to deserialize AceComm-style message")
            end
        end
    elseif #parts == 5 then
        -- Multi-part message: GROUPER_TYPE#msgid#chunk#total#data
        local messageId = parts[2]
        local chunkNum = tonumber(parts[3])
        local totalChunks = tonumber(parts[4])
        local chunkData = parts[5]
        
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Received AceComm chunk %d/%d of message %s", chunkNum, totalChunks, messageId))
        end
        
        -- Initialize chunk storage if needed
        if not self.aceCommChunks then
            self.aceCommChunks = {}
        end
        
        if not self.aceCommChunks[messageId] then
            self.aceCommChunks[messageId] = {
                chunks = {},
                totalChunks = totalChunks,
                messageType = messageType,
                sender = sender,
                timestamp = time()
            }
        end
        
        -- Store this chunk
        self.aceCommChunks[messageId].chunks[chunkNum] = chunkData
        
        -- Check if we have all chunks
        local receivedChunks = 0
        for i = 1, totalChunks do
            if self.aceCommChunks[messageId].chunks[i] then
                receivedChunks = receivedChunks + 1
            end
        end
        
        if receivedChunks == totalChunks then
            -- Reassemble the message
            local reassembledData = ""
            for i = 1, totalChunks do
                reassembledData = reassembledData .. self.aceCommChunks[messageId].chunks[i]
            end
            
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Reassembled complete AceComm message %s (%d chars)", messageId, string.len(reassembledData)))
            end
            
            -- Process the reassembled message
            local success, data = self:Deserialize(reassembledData)
            if success then
                self:ProcessReceivedMessage(messageType, data, sender)
            else
                if self.db.profile.debug.enabled then
                    self:Print("DEBUG: Failed to deserialize reassembled AceComm message")
                end
            end
            
            -- Clean up
            self.aceCommChunks[messageId] = nil
        else
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Waiting for more AceComm chunks, have %d/%d", receivedChunks, totalChunks))
            end
        end
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid AceComm-style message format (%d parts)", #parts))
        end
    end
end

-- Handle legacy GRPR# messages
function Grouper:HandleLegacyMessage(message, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing legacy message from %s", sender))
    end
    
    -- Parse legacy protocol: GRPR#messageType#serializedData
    local _, messageType, serializedData = strsplit("#", message, 3)
    if not messageType or not serializedData then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Invalid legacy protocol message format")
        end
        return
    end
    
    local success, data = self:Deserialize(serializedData)
    if not success then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Failed to deserialize legacy message data")
        end
        return
    end
    
    -- Forward to the common processor
    self:ProcessReceivedMessage(messageType, data, sender)
end

-- Handle legacy multi-part GRPR_MP# messages
function Grouper:HandleLegacyMultiPartMessage(message, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing legacy multi-part message from %s", sender))
    end
    
    -- Parse legacy multi-part: GRPR_MP#messageId#chunkNum#totalChunks#messageType#chunk
    local _, messageId, chunkNumStr, totalChunksStr, messageType, chunk = strsplit("#", message, 6)
    if not messageId or not chunkNumStr or not totalChunksStr or not messageType or not chunk then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Invalid legacy multi-part message format")
        end
        return
    end
    
    local chunkNum = tonumber(chunkNumStr)
    local totalChunks = tonumber(totalChunksStr)
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Received legacy chunk %d/%d of message %s", chunkNum, totalChunks, messageId))
    end
    
    -- Initialize chunk storage if needed
    if not self.legacyChunks then
        self.legacyChunks = {}
    end
    
    if not self.legacyChunks[messageId] then
        self.legacyChunks[messageId] = {
            chunks = {},
            totalChunks = totalChunks,
            messageType = messageType,
            sender = sender,
            timestamp = time()
        }
    end
    
    -- Store this chunk
    self.legacyChunks[messageId].chunks[chunkNum] = chunk
    
    -- Check if we have all chunks
    local receivedChunks = 0
    for i = 1, totalChunks do
        if self.legacyChunks[messageId].chunks[i] then
            receivedChunks = receivedChunks + 1
        end
    end
    
    if receivedChunks == totalChunks then
        -- Reassemble the message
        local reassembledData = ""
        for i = 1, totalChunks do
            reassembledData = reassembledData .. self.legacyChunks[messageId].chunks[i]
        end
        
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Reassembled complete legacy message %s (%d chars)", messageId, string.len(reassembledData)))
        end
        
        -- Process the reassembled message
        local success, data = self:Deserialize(reassembledData)
        if success then
            self:ProcessReceivedMessage(messageType, data, sender)
        else
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Failed to deserialize reassembled legacy message")
            end
        end
        
        -- Clean up
        self.legacyChunks[messageId] = nil
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Waiting for more legacy chunks, have %d/%d", receivedChunks, totalChunks))
        end
        
        -- Schedule a timeout check for missing chunks (shorter timeout for faster detection)
        self:ScheduleTimer(function()
            self:CheckForMissingChunks(messageId)
        end, 5) -- Check after 5 seconds instead of 10
        
        -- Schedule a more aggressive check
        self:ScheduleTimer(function()
            self:CheckForMissingChunks(messageId)
        end, 15) -- Second check after 15 seconds
    end
end

function Grouper:HandleCompactGroupUpdate(message, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing type+dungeon+role-encoded GROUP_UPDATE from %s", sender))
    end
    
    -- Parse type+dungeon+role-encoded format: GRPR_GROUP#id#title(20)#typeId#dungeonId#currentSize#maxSize#location(20)#timestamp#leader#roleId
    local parts = {strsplit("#", message)}
    if #parts < 10 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid encoded GROUP_UPDATE format (got %d parts, expected 10-11)", #parts))
        end
        return
    end
    
    local typeId = tonumber(parts[4]) or 1
    local dungeonId = tonumber(parts[5]) or 0
    local roleId = tonumber(parts[11]) or 3 -- Default to DPS if roleId not present (backward compatibility)
    
    -- Decode type information
    local typeNames = {
        [1] = "dungeon",
        [2] = "raid", 
        [3] = "quest",
        [4] = "pvp",
        [5] = "other"
    }
    local groupType = typeNames[typeId] or "other"
    
    -- Decode role information
    local roleNames = {
        [1] = "tank",
        [2] = "healer",
        [3] = "dps"
    }
    local leaderRole = roleNames[roleId] or "dps"
    
    local dungeonName = ""
    local minLevel = 1
    local maxLevel = 60
    
    -- Decode dungeon information if specified
    if dungeonId > 0 and dungeonId <= #DUNGEONS then
        local dungeon = DUNGEONS[dungeonId]
        dungeonName = dungeon.name
        minLevel = dungeon.minLevel
        maxLevel = dungeon.maxLevel
        -- Use dungeon's actual type if specified, otherwise use the selected type
        if dungeonId > 0 then
            groupType = dungeon.type
        end
    else
        -- No specific dungeon, use default level ranges based on type
        if typeId == 1 then -- dungeon
            minLevel = 15
            maxLevel = 25
        elseif typeId == 2 then -- raid
            minLevel = 60
            maxLevel = 60
        end
    end
    
    local groupData = {
        id = parts[2],
        title = parts[3],
        description = dungeonName, -- Use dungeon name as description
        minLevel = minLevel,
        maxLevel = maxLevel,
        type = groupType,
        currentSize = tonumber(parts[6]) or 1,
        maxSize = tonumber(parts[7]) or 5,
        location = parts[8],
        timestamp = tonumber(parts[9]) or time(),
        leader = parts[10],
        leaderRole = leaderRole,
        typeId = typeId,
        dungeonId = dungeonId,
        roleId = roleId,
        members = {
            [parts[10]] = {
                name = parts[10],
                role = leaderRole
            }
        }
    }
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Parsed compact group: %s (%s) by %s", 
            groupData.title, groupData.id, groupData.leader))
    end
    
    -- Process as a GROUP_UPDATE with the expected nested structure
    local messageData = {
        type = "GROUP_UPDATE",
        data = groupData,
        sender = sender,
        timestamp = time(),
        version = "1.0.0"
    }
    
    self:ProcessReceivedMessage("GROUP_UPDATE", messageData, sender)
end

function Grouper:CheckForMissingChunks(messageId)
    if not self.legacyChunks or not self.legacyChunks[messageId] then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: No chunks to check for message %s (already completed or expired)", messageId))
        end
        return -- Message already completed or cleaned up
    end
    
    local messageData = self.legacyChunks[messageId]
    local missingChunks = {}
    local receivedChunks = {}
    
    -- Find missing chunks and track received ones
    for i = 1, messageData.totalChunks do
        if not messageData.chunks[i] then
            table.insert(missingChunks, i)
        else
            table.insert(receivedChunks, i)
        end
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Chunk status for message %s: received %s, missing %s", 
            messageId, 
            #receivedChunks > 0 and table.concat(receivedChunks, ",") or "none",
            #missingChunks > 0 and table.concat(missingChunks, ",") or "none"))
    end
    
    if #missingChunks > 0 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Requesting missing chunks %s for message %s from %s", 
                table.concat(missingChunks, ","), messageId, messageData.sender))
        end
        
        -- Send chunk request via AceComm
        local requestMessage = string.format("GRPR_REQ#%s#%s", messageId, table.concat(missingChunks, ","))
        
        local channelIndex = self:GetGrouperChannelIndex()
        if channelIndex > 0 then
            self:SendCommMessage("GRPR_CHUNK_REQ", requestMessage, "CHANNEL", channelIndex, "BULK")
        else
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: ✗ Cannot send chunk request - not in Grouper channel")
            end
        end
    end
end

function Grouper:HandleChunkRequest(message, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Handling chunk request from %s", sender))
    end
    
    -- Parse request: GRPR_REQ#messageId#chunkNumbers
    local _, messageId, chunkNumbersStr = strsplit("#", message, 3)
    if not messageId or not chunkNumbersStr then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Invalid chunk request format")
        end
        return
    end
    
    -- Check if we have stored chunks for this message
    if not self.sentChunks or not self.sentChunks[messageId] then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: No stored chunks found for message %s", messageId))
        end
        return
    end
    
    local chunkNumbers = {}
    for chunkNumStr in string.gmatch(chunkNumbersStr, "[^,]+") do
        local chunkNum = tonumber(chunkNumStr)
        if chunkNum then
            table.insert(chunkNumbers, chunkNum)
        end
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Resending chunks %s for message %s", 
            table.concat(chunkNumbers, ","), messageId))
    end
    
    -- Resend requested chunks via AceComm
    for _, chunkNum in ipairs(chunkNumbers) do
        local chunkData = self.sentChunks[messageId].chunks[chunkNum]
        if chunkData then
            local resendChunk = function()
                local channelIndex = self:GetGrouperChannelIndex()
                if channelIndex > 0 then
                    self:SendCommMessage("GRPR_CHUNK_RES", chunkData, "CHANNEL", channelIndex, "BULK")
                    if self.db.profile.debug.enabled then
                        self:Print(string.format("DEBUG: Resent chunk %d for message %s", chunkNum, messageId))
                    end
                else
                    if self.db.profile.debug.enabled then
                        self:Print(string.format("DEBUG: ✗ Cannot resend chunk %d - not in Grouper channel", chunkNum))
                    end
                end
            end
            
            -- Delay resends to avoid throttling
            self:ScheduleTimer(resendChunk, (chunkNum - 1) * 0.3)
        end
    end
end

-- AceComm message handler
function Grouper:OnCommReceived(prefix, message, distribution, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: OnCommReceived called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    end
    
    -- Add specific debug for GRPR_GRP_UPD
    if prefix == "GRPR_GRP_UPD" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: 🎯 GRPR_GRP_UPD message received from %s!", sender))
        end
    end
    
    -- Ignore messages from ourselves to prevent self-processing
    local playerName = UnitName("player")
    local playerServer = GetRealmName()
    -- Normalize realm name by removing spaces (WoW chat shows "OldBlanchy" but GetRealmName() returns "Old Blanchy")
    if playerServer then
        playerServer = playerServer:gsub("%s+", "")
    end
    local fullPlayerName = playerName .. "-" .. playerServer
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: AceComm Self-check - playerName: '%s', playerServer: '%s', fullPlayerName: '%s', sender: '%s'", 
            playerName or "nil", playerServer or "nil", fullPlayerName or "nil", sender or "nil"))
    end
    
    if sender == playerName or sender == fullPlayerName then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Ignoring AceComm message from self (%s)", sender))
        end
        return
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: AceComm received %s from %s via %s", prefix, sender, distribution))
    end
    
    -- Map short prefixes to full message types
    local messageType
    if prefix == "GRPR_GRP_UPD" then
        messageType = "GROUP_UPDATE"
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED GRPR_GRP_UPD from %s, deserializing", sender))
        end
        -- Handle normal serialized format like TEST messages
        local pcall_success, deserialize_success, deserializedMessage = pcall(self.Deserialize, self, message)
        if pcall_success and deserialize_success and deserializedMessage then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: ✓ Successfully deserialized GRPR_GRP_UPD message"))
                
                -- Add safe error handling for debug logging
                local success_debug, error_debug = pcall(function()
                    -- Safely check deserializedMessage.type
                    local msgType = "nil"
                    if deserializedMessage.type then
                        msgType = tostring(deserializedMessage.type)
                    end
                    self:Print(string.format("DEBUG: deserializedMessage.type = %s", msgType))
                    
                    -- Safely check deserializedMessage.data
                    if deserializedMessage.data then
                        self:Print(string.format("DEBUG: deserializedMessage.data exists, calling ProcessReceivedMessage"))
                        if type(deserializedMessage.data) == "table" then
                            local groupId = deserializedMessage.data.id or "nil"
                            local groupTitle = deserializedMessage.data.title or "nil"
                            local groupLeader = deserializedMessage.data.leader or "nil"
                            self:Print(string.format("DEBUG: Group ID: %s, Title: %s, Leader: %s", groupId, groupTitle, groupLeader))
                        end
                    else
                        self:Print("DEBUG: deserializedMessage.data is nil!")
                    end
                    
                    self:Print(string.format("DEBUG: About to call ProcessReceivedMessage..."))
                end)
                
                if not success_debug then
                    self:Print(string.format("DEBUG: ✗ Error in debug logging: %s", tostring(error_debug)))
                end
            end
            -- Pass the whole deserialized message, not just the data part
            local success2, error2 = pcall(function()
                self:ProcessReceivedMessage(deserializedMessage.type, deserializedMessage, sender)
            end)
            if not success2 then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: ✗ ProcessReceivedMessage failed: %s", tostring(error2)))
                end
            else
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: ✓ ProcessReceivedMessage completed successfully"))
                end
            end
        else
            if self.db.profile.debug.enabled then
                if not pcall_success then
                    self:Print(string.format("DEBUG: ✗ pcall failed for GRPR_GRP_UPD deserialization from %s", sender))
                    self:Print(string.format("DEBUG: pcall Error: %s", tostring(deserialize_success)))
                elseif not deserialize_success then
                    self:Print(string.format("DEBUG: ✗ Failed to deserialize GRPR_GRP_UPD from %s", sender))
                    self:Print(string.format("DEBUG: Deserialize Error: %s", tostring(deserializedMessage)))
                else
                    self:Print(string.format("DEBUG: ✗ Unexpected deserialization result from %s", sender))
                end
            end
            return
        end
        
        -- Process the successfully deserialized message
        local success2, error2 = pcall(function()
            self:ProcessReceivedMessage(deserializedMessage.type, deserializedMessage, sender)
        end)
        if not success2 then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: ✗ ProcessReceivedMessage failed: %s", tostring(error2)))
            end
        else
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: ✓ ProcessReceivedMessage completed successfully"))
            end
        end
        return
    elseif prefix == "GRPR_GROUP" then
        messageType = "GROUP_UPDATE"
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED GRPR_GROUP from %s, calling HandleCompactGroupUpdate", sender))
        end
        -- Handle compact format directly from AceComm (message already includes GRPR_GROUP# prefix)
        self:HandleCompactGroupUpdate(message, sender)
        return
    elseif prefix == "GROUP_UPDATE" then
        messageType = "GROUP_UPDATE"
        -- Handle compact format directly (no serialization needed)
        local parts = {}
        for part in string.gmatch(message, "([^|]*)") do
            table.insert(parts, part)
        end
        
        if #parts >= 13 then
            local groupData = {
                id = parts[1],
                title = parts[2],
                type = parts[3],
                playerName = parts[4],
                leader = parts[4], -- Map playerName to leader for HandleGroupUpdate compatibility
                className = parts[5],
                level = tonumber(parts[6]) or 1,
                minLevel = tonumber(parts[7]) or 1,
                maxLevel = tonumber(parts[8]) or 60,
                description = parts[9],
                quest = parts[10],
                zone = parts[11],
                timestamp = tonumber(parts[12]) or time(),
                playerCount = tonumber(parts[13]) or 1
            }
            
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Received compact GROUP_UPDATE for %s (%s) from %s", 
                    groupData.id, groupData.title, sender))
            end
            
            self:HandleGroupUpdate(groupData, sender)
            return
        else
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Invalid compact GROUP_UPDATE format from %s (got %d parts, expected 13)", sender, #parts))
            end
            return
        end
    elseif prefix == "GRPR_REQ_DATA" then
        messageType = "REQUEST_DATA"
    elseif prefix == "GRPR_PRESENCE" then
        messageType = "PRESENCE"
    elseif prefix == "GRPR_TEST" then
        messageType = "TEST"
    elseif prefix == "GROUPER_TEST" then
        messageType = "TEST"
    elseif prefix == "GRPR_CHUNK_REQ" then
        -- Handle chunk request directly
        self:HandleChunkRequest(message, sender)
        return
    elseif prefix == "GRPR_CHUNK_RES" then
        -- Handle chunk resend - treat as normal channel message for legacy compatibility
        self:HandleGrouperMessage(message, sender)
        return
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Unknown AceComm prefix: %s", prefix))
        end
        return
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ✓ RECEIVED %s from %s, checking message format", prefix, sender))
        self:Print(string.format("DEBUG: Raw message type: %s", type(message)))
        self:Print(string.format("DEBUG: Raw message length: %d", string.len(tostring(message))))
        self:Print(string.format("DEBUG: Message starts with: %s", string.sub(tostring(message), 1, 50)))
    end
    
    -- Deserialize the message (AceComm handles chunking automatically)
    local success, data = self:Deserialize(message)
    if not success then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✗ Failed to deserialize AceComm message from %s", sender))
            self:Print(string.format("DEBUG: Deserialize error: %s", tostring(data)))
            self:Print(string.format("DEBUG: Trying to treat message as already deserialized..."))
            -- Maybe the message is already the deserialized data?
            if type(message) == "table" then
                self:Print(string.format("DEBUG: Message is already a table! Processing directly."))
                self:ProcessReceivedMessage(messageType, message, sender)
                return
            end
        end
        return
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ✓ Successfully deserialized AceComm message from %s (type: %s)", sender, messageType))
        if data then
            self:Print(string.format("DEBUG: Deserialized data exists - calling ProcessReceivedMessage"))
            -- Debug the data structure
            self:Print(string.format("DEBUG: data.type = %s", tostring(data.type)))
            self:Print(string.format("DEBUG: data.sender = %s", tostring(data.sender)))
            if data.data then
                self:Print(string.format("DEBUG: data.data exists - type: %s", type(data.data)))
                if type(data.data) == "table" then
                    self:Print(string.format("DEBUG: data.data.id = %s", tostring(data.data.id)))
                    self:Print(string.format("DEBUG: data.data.title = %s", tostring(data.data.title)))
                    self:Print(string.format("DEBUG: data.data.leader = %s", tostring(data.data.leader)))
                end
            else
                self:Print("DEBUG: data.data is nil!")
            end
        else
            self:Print(string.format("DEBUG: ERROR - Deserialized data is nil!"))
        end
    end
    
    -- Process the message using the same logic as before
    self:ProcessReceivedMessage(messageType, data, sender)
end

-- Common message processing function
function Grouper:ProcessReceivedMessage(messageType, data, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: 🎯 ProcessReceivedMessage called: messageType=%s, sender=%s", tostring(messageType), tostring(sender)))
        self:Print(string.format("DEBUG: data type: %s", type(data)))
    end
    
    -- Allow TEST messages from ourselves for debugging, but ignore other messages from ourselves
    if sender == UnitName("player") and messageType ~= "TEST" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Ignoring own message: %s (type: %s)", sender, messageType))
        end
        return
    end
    
    -- Update player list (for presence tracking)
    if not self.players[sender] then
        self.players[sender] = {
            name = sender,
            lastSeen = time(),
            version = data.version or "unknown"
        }
        
        if self.db.profile.debug.enabled then
            local playerCount = 0
            for _ in pairs(self.players) do
                playerCount = playerCount + 1
            end
            self:Print(string.format("DEBUG: Added player %s to tracking (total players: %d)", sender, playerCount))
        end
    else
        self.players[sender].lastSeen = time()
        if data.version then
            self.players[sender].version = data.version
        end
    end
    
    -- Handle different message types
    if messageType == "GROUP_UPDATE" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: 🎯 Processing GROUP_UPDATE from %s", sender))
            if data and data.data then
                self:Print(string.format("DEBUG: ✓ Group data exists - ID: %s, Title: %s, Leader: %s", 
                    data.data.id or "nil",
                    data.data.title or "nil", 
                    data.data.leader or "nil"))
                self:Print(string.format("DEBUG: ⚡ Calling HandleGroupUpdate..."))
            else
                self:Print("DEBUG: ✗ ERROR - data.data is nil or missing!")
                if data then
                    self:Print("DEBUG: data exists but data.data is missing")
                    -- Print data structure for debugging
                    for k, v in pairs(data) do
                        self:Print(string.format("DEBUG: data.%s = %s", k, tostring(v)))
                    end
                else
                    self:Print("DEBUG: data itself is nil")
                end
            end
        end
        
        -- Safety check before calling HandleGroupUpdate
        if data and data.data then
            self:HandleGroupUpdate(data.data, sender)
        else
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: ✗ ERROR - Cannot call HandleGroupUpdate, data.data is nil")
            end
        end
    elseif messageType == "REQUEST_DATA" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Processing REQUEST_DATA from %s", sender))
        end
        self:HandleDataRequest(sender)
    elseif messageType == "PRESENCE" then
        self:HandlePresence(data.data, sender)
    elseif messageType == "TEST" then
        if self.db.profile.debug.enabled then
            if sender ~= UnitName("player") then
                self:Print(string.format("DEBUG: ✓ RECEIVED TEST MESSAGE from %s: %s", sender, data.data and data.data.message or "no message"))
            else
                self:Print(string.format("DEBUG: Received test message: %s", data.data and data.data.message or "no message"))
            end
        end
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Unknown message type: %s", messageType))
        end
    end
    
    -- Refresh UI if it's open
    if self.mainFrame and self.mainFrame:IsShown() then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Refreshing UI after processing AceComm message (total groups: %d)", self:CountGroups()))
        end
        self:RefreshGroupList()
    end
end

-- Group management functions
function Grouper:CreateGroup(groupData)
    -- Encode type as number if not already encoded: 1=Dungeon, 2=Raid, 3=Quest, 4=PvP, 5=Other
    local typeId = groupData.typeId
    if not typeId then
        local groupType = groupData.type or "dungeon"
        if groupType == "dungeon" then typeId = 1
        elseif groupType == "raid" then typeId = 2
        elseif groupType == "quest" then typeId = 3
        elseif groupType == "pvp" then typeId = 4
        elseif groupType == "other" then typeId = 5
        else typeId = 1 -- Default to dungeon
        end
    end
    
    local group = {
        id = self:GenerateGroupID(),
        leader = UnitName("player"),
        title = groupData.title or "Untitled Group",
        description = groupData.description or "",
        type = groupData.type or "other",
        typeId = typeId,
        minLevel = groupData.minLevel or 1,
        maxLevel = groupData.maxLevel or 60,
        currentSize = groupData.currentSize or 1,
        maxSize = groupData.maxSize or 5,
        location = groupData.location or "",
        dungeons = groupData.dungeons or {},
        timestamp = time(),
        members = {
            [UnitName("player")] = {
                name = UnitName("player"),
                class = UnitClass("player"),
                level = UnitLevel("player"),
                role = groupData.myRole or "DPS"
            }
        }
    }
    
    self.groups[group.id] = group
    self:SendComm("GROUP_UPDATE", group)
    
    self:Print(string.format("Created group: %s", group.title))
    return group
end

function Grouper:UpdateGroup(groupId, updates)
    local group = self.groups[groupId]
    if not group or group.leader ~= UnitName("player") then
        return false
    end
    
    for key, value in pairs(updates) do
        if key ~= "id" and key ~= "leader" and key ~= "timestamp" then
            group[key] = value
        end
    end
    
    group.timestamp = time()
    self:SendComm("GROUP_UPDATE", group)
    
    return true
end

function Grouper:RemoveGroup(groupId)
    local group = self.groups[groupId]
    if not group or group.leader ~= UnitName("player") then
        return false
    end
    
    self.groups[groupId] = nil
    self:SendComm("GROUP_REMOVE", {id = groupId})
    
    self:Print(string.format("Removed group: %s", group.title))
    return true
end

-- Helper function to strip realm name from player names for comparison
function Grouper:StripRealmName(playerName)
    if not playerName then
        return playerName
    end
    
    local name = strsplit("-", playerName)
    return name
end

-- Helper function to get table keys for debugging
function Grouper:GetTableKeys(tbl)
    local keys = {}
    if type(tbl) == "table" then
        for key, _ in pairs(tbl) do
            table.insert(keys, tostring(key))
        end
    end
    return keys
end

function Grouper:HandleGroupUpdate(groupData, sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: HandleGroupUpdate called - sender: %s, leader: %s", sender, groupData and groupData.leader or "nil"))
        self:Print(string.format("DEBUG: Group ID: %s, Title: %s", groupData and groupData.id or "nil", groupData and groupData.title or "nil"))
    end
    
    -- Add safety check for nil groupData
    if not groupData then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ERROR - groupData is nil in HandleGroupUpdate")
        end
        return
    end
    
    -- Strip realm names for comparison
    local senderName = self:StripRealmName(sender)
    local leaderName = self:StripRealmName(groupData.leader)
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Comparing stripped names - sender: %s, leader: %s", senderName, leaderName))
    end
    
    if leaderName == senderName then
        self.groups[groupData.id] = groupData
        
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Added group to list. Total groups: %d", self:CountGroups()))
            self:Print(string.format("DEBUG: 💾 Stored group %s in self.groups[%s]", groupData.title, groupData.id))
            -- Verify it was actually stored
            if self.groups[groupData.id] then
                self:Print(string.format("DEBUG: ✅ Verification: group %s exists in memory", groupData.id))
            else
                self:Print(string.format("DEBUG: ❌ ERROR: group %s NOT found in memory after storage!", groupData.id))
            end
        end
        
        if self.db.profile.notifications.newGroups then
            self:Print(string.format("New group available: %s", groupData.title))
        end
        
        -- Refresh UI if it's open (this happens after adding a group)
        if self.mainFrame and self.mainFrame:IsShown() then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Refreshing UI after adding group %s (total groups: %d)", groupData.id, self:CountGroups()))
            end
            self:RefreshGroupList()
        end
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Rejecting group update - sender mismatch (stripped: %s vs %s)", senderName, leaderName))
        end
    end
end

function Grouper:CountGroups()
    local count = 0
    for _ in pairs(self.groups) do
        count = count + 1
    end
    return count
end

function Grouper:CountTableFields(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Grouper:HandleGroupRemove(data, sender)
    local group = self.groups[data.id]
    if group and group.leader == sender then
        self.groups[data.id] = nil
    end
end

function Grouper:HandleDataRequest(sender)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: HandleDataRequest from %s - queuing for delayed response", sender))
    end
    
    -- Queue the response and schedule a delayed flush to avoid protected context
    self:QueueDataRequestResponse(sender)
    self:ScheduleDelayedFlush()
end

function Grouper:ScheduleDelayedFlush()
    -- Cancel any existing flush timer
    if self.flushTimer then
        self:CancelTimer(self.flushTimer)
    end
    
    -- Schedule a delayed flush to ensure we're out of protected context
    -- Use a 0.1 second delay for automated responses (AceComm best practice)
    self.flushTimer = self:ScheduleTimer(function()
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Executing delayed response flush")
        end
        
        self:FlushResponseQueue()
        self.flushTimer = nil
    end, 0.1)
end

function Grouper:QueueDataRequestResponse(sender)
    -- Initialize response queue if it doesn't exist
    if not self.responseQueue then
        self.responseQueue = {}
    end
    
    local playerName = UnitName("player")
    
    -- Queue each group this player created for sending
    for groupId, group in pairs(self.groups) do
        if group.leader == playerName then
            local groupAge = time() - group.timestamp
            if groupAge < 3600 then -- Only queue groups less than 1 hour old
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Queuing group %s (%s) for response to %s", groupId, group.title, sender))
                end
                -- Queue the group for sending
                table.insert(self.responseQueue, {
                    type = "GROUP_UPDATE",
                    data = group,
                    requestedBy = sender
                })
            else
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Skipping expired group %s (age: %d min)", groupId, math.floor(groupAge/60)))
                end
            end
        end
    end
end

function Grouper:FlushResponseQueue()
    if not self.responseQueue or #self.responseQueue == 0 then
        return 0
    end
    
    local sent = 0
    while #self.responseQueue > 0 do
        local response = table.remove(self.responseQueue, 1)
        if response then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Flushing queued response: %s for %s", response.type, response.requestedBy))
            end
            
            -- Send directly without timers - same as Greenwall approach
            self:SendComm(response.type, response.data)
            sent = sent + 1
        end
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Flushed %d queued responses", sent))
    end
    
    return sent
end

function Grouper:SendDataRequestResponse(sender)
    -- Keep this function for compatibility but make it call the new queue-based system
    self:QueueDataRequestResponse(sender)
    return self:FlushResponseQueue()
end

function Grouper:HandlePresence(data, sender)
    -- Update player presence information - make sure player exists first
    if not self.players[sender] then
        self.players[sender] = {
            name = sender,
            lastSeen = time(),
            version = "unknown"
        }
    end
    
    self.players[sender].status = data.status
    self.players[sender].groupId = data.groupId
    self.players[sender].lastSeen = time() -- Update last seen time
end

function Grouper:BroadcastPresence()
    -- Wrap the entire function in a protected call to catch any protected function errors
    local success, errorMsg = pcall(function()
        -- Diagnostic information to help identify protected function issues
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            local diagnostics = {}
            
            -- Check various WoW states that can cause protected function issues
            pcall(function()
                table.insert(diagnostics, string.format("InCombatLockdown: %s", tostring(InCombatLockdown())))
                table.insert(diagnostics, string.format("UnitAffectingCombat('player'): %s", tostring(UnitAffectingCombat("player"))))
                table.insert(diagnostics, string.format("GetTime(): %s", tostring(GetTime())))
                table.insert(diagnostics, string.format("IsLoggedIn(): %s", tostring(IsLoggedIn())))
                table.insert(diagnostics, string.format("GetFramerate(): %s", tostring(GetFramerate())))
                
                -- Check if we're in a loading screen or transition
                if LoadingScreenFrame and LoadingScreenFrame:IsShown() then
                    table.insert(diagnostics, "LoadingScreen: SHOWN")
                else
                    table.insert(diagnostics, "LoadingScreen: HIDDEN")
                end
                
                -- Check addon taint status
                local taintMsg = ""
                if issecurevariable then
                    local secure, taintSource = issecurevariable("UnitName")
                    if not secure then
                        taintMsg = string.format("UnitName tainted by: %s", taintSource or "unknown")
                    else
                        taintMsg = "UnitName secure"
                    end
                end
                table.insert(diagnostics, taintMsg)
                
                -- Check channel state
                local channelIndex = GetChannelName(ADDON_CHANNEL)
                table.insert(diagnostics, string.format("Channel '%s' index: %d", ADDON_CHANNEL, channelIndex))
                
            end)
            
            self:Print("DEBUG: BroadcastPresence diagnostics: " .. table.concat(diagnostics, ", "))
        end
        
        -- Allow disabling presence broadcast to avoid protected function issues
        if self.db and self.db.profile and self.db.profile.disablePresence then
            return
        end
        
        -- Skip presence broadcasting when handling data requests to prevent conflicts
        if self.suppressPresence then
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Skipping presence broadcast - data request processing in progress")
            end
            return
        end
        
        -- Multiple layers of protection to prevent protected function call errors
        
        -- Don't broadcast during combat to avoid protected function issues
        if InCombatLockdown() then
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Skipping presence broadcast - in combat")
            end
            return
        end
        
        -- Don't broadcast if game is still loading
        if not GetTime() or GetTime() < 5 then
            return -- Too early in the loading process
        end
        
        -- Don't broadcast if addon is not fully loaded
        if not self.db or not self.db.profile then
            return
        end
        
        -- Additional safety checks for protected function calls
        if not UnitName("player") or UnitName("player") == "" then
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Skipping presence broadcast - player name not available")
            end
            return
        end
        
        -- Check if we're in a valid state to send chat messages
        local channelIndex = GetChannelName(ADDON_CHANNEL)
    if channelIndex <= 0 then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Skipping presence broadcast - not in channel")
        end
        return
    end
    
    -- Wrap all potentially protected function calls in a protected environment
    local success, result = pcall(function()
        local status = "available"
        local groupId = nil
        
        -- These function calls might be protected in some contexts
        if IsInRaid() then
            status = "in_raid"
        elseif IsInGroup() then
            status = "in_party"
        end
        
        -- Get player info safely
        local playerLevel = UnitLevel("player") or 1
        local playerClass = UnitClass("player") or "Unknown"
        
        return {
            status = status,
            groupId = groupId,
            level = playerLevel,
            class = playerClass
        }
    end)
    
    if not success then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Failed to get player data for presence: %s", tostring(result)))
        end
        return
    end
    
    -- Use protected call to prevent addon blocking errors
    local commSuccess, errorMsg = pcall(function()
        self:SendComm("PRESENCE", result)
    end)
    
    if not commSuccess then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Failed to broadcast presence: %s", tostring(errorMsg)))
        end
    end
    end) -- Close the outer pcall function
    
    -- Handle any protected function errors from the entire BroadcastPresence function
    if not success then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            -- Try to extract more information about the error
            local errorInfo = {}
            table.insert(errorInfo, string.format("Error: %s", tostring(errorMsg)))
            
            -- Check if it's a specific type of protected function error
            if errorMsg and type(errorMsg) == "string" then
                if errorMsg:find("ADDON_ACTION_BLOCKED") then
                    table.insert(errorInfo, "Type: ADDON_ACTION_BLOCKED")
                elseif errorMsg:find("Interface action failed") then
                    table.insert(errorInfo, "Type: Interface action failed")
                elseif errorMsg:find("script ran too long") then
                    table.insert(errorInfo, "Type: Script timeout")
                end
                
                -- Try to identify which function call caused the issue
                if errorMsg:find("SendChatMessage") then
                    table.insert(errorInfo, "Suspect: SendChatMessage")
                elseif errorMsg:find("UnitName") then
                    table.insert(errorInfo, "Suspect: UnitName")
                elseif errorMsg:find("UnitClass") then
                    table.insert(errorInfo, "Suspect: UnitClass")
                elseif errorMsg:find("UnitLevel") then
                    table.insert(errorInfo, "Suspect: UnitLevel")
                elseif errorMsg:find("IsInRaid") then
                    table.insert(errorInfo, "Suspect: IsInRaid")
                elseif errorMsg:find("IsInGroup") then
                    table.insert(errorInfo, "Suspect: IsInGroup")
                elseif errorMsg:find("GetChannelName") then
                    table.insert(errorInfo, "Suspect: GetChannelName")
                end
            end
            
            -- Get current stack trace if possible
            pcall(function()
                local stack = debugstack(2, 5, 5) -- Get limited stack trace
                if stack then
                    table.insert(errorInfo, string.format("Stack: %s", stack:gsub("\n", " | ")))
                end
            end)
            
            self:Print("DEBUG: BroadcastPresence protected function error details: " .. table.concat(errorInfo, " | "))
        end
        -- Don't re-throw the error, just log it and continue
    end
end

-- Utility functions
function Grouper:GenerateGroupID()
    return string.format("%s_%d", UnitName("player"), time())
end

function Grouper:CleanupOldGroups()
    local currentTime = time()
    local expireTime = 3600 -- 1 hour
    
    for id, group in pairs(self.groups) do
        if currentTime - group.timestamp > expireTime then
            self.groups[id] = nil
        end
    end
    
    -- Cleanup offline players
    for name, player in pairs(self.players) do
        if currentTime - player.lastSeen > expireTime then
            self.players[name] = nil
        end
    end
end

function Grouper:CleanupOldAceCommChunks()
    local currentTime = time()
    local expireTime = 300 -- 5 minutes
    
    -- Clean up AceComm chunks
    if self.aceCommChunks then
        for messageId, messageData in pairs(self.aceCommChunks) do
            if currentTime - messageData.timestamp > expireTime then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Cleaning up expired AceComm chunks for message %s", messageId))
                end
                self.aceCommChunks[messageId] = nil
            end
        end
    end
    
    -- Clean up legacy chunks
    if self.legacyChunks then
        for messageId, messageData in pairs(self.legacyChunks) do
            if currentTime - messageData.timestamp > expireTime then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Cleaning up expired legacy chunks for message %s", messageId))
                end
                self.legacyChunks[messageId] = nil
            end
        end
    end
    
    -- Clean up sent chunks (for resend capability)
    if self.sentChunks then
        for messageId, messageData in pairs(self.sentChunks) do
            if currentTime - messageData.timestamp > expireTime then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Cleaning up expired sent chunks for message %s", messageId))
                end
                self.sentChunks[messageId] = nil
            end
        end
    end
end

function Grouper:GetFilteredGroups()
    local filtered = {}
    local filters = self.db.profile.filters
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: 🔍 Filtering %d total groups", self:CountGroups()))
        self:Print(string.format("DEBUG: Filter settings - minLevel: %d, maxLevel: %d", filters.minLevel, filters.maxLevel))
    end
    
    for _, group in pairs(self.groups) do
        local include = true
        local reason = ""
        
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Checking group '%s' (type: %s, minLevel: %d, maxLevel: %d)", 
                group.title, group.type, group.minLevel or 0, group.maxLevel or 60))
        end
        
        -- Level filter
        if group.minLevel > filters.maxLevel or group.maxLevel < filters.minLevel then
            include = false
            reason = string.format("level mismatch (group: %d-%d, filter: %d-%d)", 
                group.minLevel or 0, group.maxLevel or 60, filters.minLevel, filters.maxLevel)
        end
        
        -- Type filter
        if include and not filters.dungeonTypes[group.type] then
            include = false
            reason = string.format("type '%s' not enabled in filters", group.type)
        end
        
        -- Dungeon filter
        if include and self.selectedDungeonFilter and self.selectedDungeonFilter ~= "" then
            if not group.dungeons or not group.dungeons[self.selectedDungeonFilter] then
                include = false
                reason = string.format("dungeon filter '%s' doesn't match", self.selectedDungeonFilter)
            end
        end
        
        if self.db.profile.debug.enabled then
            if include then
                self:Print(string.format("DEBUG: ✅ Including group '%s'", group.title))
            else
                self:Print(string.format("DEBUG: ❌ Excluding group '%s' - %s", group.title, reason))
            end
        end
        
        if include then
            table.insert(filtered, group)
        end
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: 🔍 Filtered result: %d groups passed filters", #filtered))
    end
    
    -- Sort by timestamp (newest first)
    table.sort(filtered, function(a, b)
        return a.timestamp > b.timestamp
    end)
    
    return filtered
end

-- Slash command handler
function Grouper:SlashCommand(input)
    local args = {self:GetArgs(input, 10)}
    local command = args[1] and args[1]:lower()
    
    if command == "show" or command == "" then
        self:ToggleMainWindow()
    elseif command == "config" or command == "options" then
        self:ShowConfig()
    elseif command == "join" then
        self:EnsureChannelJoined()
    elseif command == "status" then
        local channelIndex = GetChannelName(ADDON_CHANNEL)
        local actuallyInChannel = channelIndex > 0
        self:Print(string.format("Groups: %d, Players: %d", self:CountGroups(), #self.players))
        self:Print(string.format("My Channel Status: %s (Index: %d)", 
            actuallyInChannel and "Connected" or "Disconnected", channelIndex))
        self:Print(string.format("Cached Channel: %s", 
            self.grouperChannelNumber and tostring(self.grouperChannelNumber) or "None"))
        self:Print(string.format("Channel Name: '%s'", ADDON_CHANNEL))
        self:Print(string.format("Internal Status: %s", 
            self.channelJoined and "Connected" or "Disconnected"))
        self:Print(string.format("Debug Mode: %s", 
            self.db.profile.debug.enabled and "ON" or "OFF"))
        
        -- Validate and fix cache
        if self.grouperChannelNumber and channelIndex ~= self.grouperChannelNumber then
            self:Print("WARNING: Cached channel number doesn't match current!")
            self.grouperChannelNumber = channelIndex -- Fix it
        elseif not self.grouperChannelNumber and channelIndex > 0 then
            self:Print("Initializing missing channel cache...")
            self.grouperChannelNumber = channelIndex -- Initialize it
        end
        
        -- Auto-fix if there's a mismatch
        if actuallyInChannel and not self.channelJoined then
            self:Print("Fixing channel status...")
            self.channelJoined = true
        elseif not actuallyInChannel and self.channelJoined then
            self:Print("Reconnecting to channel...")
            self.channelJoined = false
            self:EnsureChannelJoined()
        end
    elseif command == "test" then
        self:Print("Testing AceComm communication...")
        
        local channelIndex = self:GetGrouperChannelIndex()
        if channelIndex <= 0 then
            self:Print("✗ Not in Grouper channel - cannot test AceComm")
            return
        end
        
        self:Print(string.format("Using Grouper channel %d for tests", channelIndex))
        
        -- Test 1: Simple AceComm message
        local testData1 = {message = "Simple test", sender = UnitName("player"), timestamp = time()}
        local success1, err1 = pcall(function()
            self:SendCommMessage("GROUPER_TEST", self:Serialize(testData1), "CHANNEL", channelIndex, "ALERT")
        end)
        self:Print(string.format("Simple AceComm test: %s %s", success1 and "SUCCESS" or "FAILED", err1 or ""))
        
        -- Test 2: Our SendComm protocol
        local success2, err2 = pcall(function()
            self:SendComm("TEST", {message = "Hello from " .. UnitName("player")})
        end)
        self:Print(string.format("SendComm protocol test: %s %s", success2 and "SUCCESS" or "FAILED", err2 or ""))
        
        -- Test 3: Group update message (skip to avoid creating fake groups)
        -- local success3, err3 = pcall(function()
        --     self:SendComm("GROUP_UPDATE", {test = true, sender = UnitName("player")})
        -- end)
        -- self:Print(string.format("Group update test: %s %s", success3 and "SUCCESS" or "FAILED", err3 or ""))
        self:Print("Group update test: SKIPPED (to avoid fake groups)")
        
        -- Test 4: Direct GRPR_GRP_UPD test to verify registration
        local success4, err4 = pcall(function()
            local testMessage = {type = "GROUP_UPDATE", sender = UnitName("player"), timestamp = time(), version = ADDON_VERSION, data = {test = true}}
            self:SendCommMessage("GRPR_GRP_UPD", self:Serialize(testMessage), "CHANNEL", channelIndex, "ALERT")
        end)
        self:Print(string.format("Direct GRPR_GRP_UPD test: %s %s", success4 and "SUCCESS" or "FAILED", err4 or ""))
        
        -- Test 5: WHISPER test to self
        local success5, err5 = pcall(function()
            self:SendComm("TEST", {message = "WHISPER test from " .. UnitName("player")}, "WHISPER", UnitName("player"), "NORMAL")
        end)
        self:Print(string.format("WHISPER test to self: %s %s", success5 and "SUCCESS" or "FAILED", err5 or ""))
        
        -- Test 6: Direct channel test (visible)
        local success4, err4 = pcall(function()
            SendChatMessage("GRPR_DIRECT_TEST:" .. UnitName("player"), "CHANNEL", nil, channelIndex)
        end)
        self:Print(string.format("Direct channel test: %s %s", success4 and "SUCCESS" or "FAILED", err4 or ""))
        
        self:Print("First 3 tests use AceComm, Test 4 uses direct channel (visible)")
        self:Print("If Test 4 works but others don't, AceComm has an issue with CHANNEL distribution")
    elseif command == "debug" then
        if args[2] and args[2]:lower() == "off" then
            self.db.profile.debug.enabled = false
            self:Print("Debug mode disabled")
        else
            self.db.profile.debug.enabled = true
            self:Print("Debug mode enabled")
        end
        self:Print(string.format("Debug is now %s", self.db.profile.debug.enabled and "ON" or "OFF"))
    elseif command == "whisper" then
        if not args[2] then
            self:Print("Usage: /grouper whisper <playername>")
            self:Print("Sends a test whisper to verify WHISPER communication works")
            return
        end
        
        local targetPlayer = args[2]
        self:Print(string.format("Testing WHISPER communication to %s...", targetPlayer))
        
        local success, err = pcall(function()
            self:SendComm("TEST", {message = "WHISPER test from " .. UnitName("player")}, "WHISPER", targetPlayer, "NORMAL")
        end)
        self:Print(string.format("WHISPER test to %s: %s %s", targetPlayer, success and "SUCCESS" or "FAILED", err or ""))
    elseif command == "presence" then
        if args[2] and args[2]:lower() == "off" then
            self.db.profile.disablePresence = true
            self:Print("Presence broadcasting disabled")
        else
            self.db.profile.disablePresence = false
            self:Print("Presence broadcasting enabled")
        end
        self:Print(string.format("Presence broadcasting is now %s", self.db.profile.disablePresence and "OFF" or "ON"))
    elseif command == "chunks" then
        -- Debug command to show chunk status
        self:Print("Chunk status:")
        
        if self.legacyChunks then
            local count = 0
            for messageId, messageData in pairs(self.legacyChunks) do
                count = count + 1
                local receivedChunks = 0
                for i = 1, messageData.totalChunks do
                    if messageData.chunks[i] then
                        receivedChunks = receivedChunks + 1
                    end
                end
                local age = time() - messageData.timestamp
                self:Print(string.format("  Receiving %s: %d/%d chunks from %s (age: %ds)", 
                    messageId, receivedChunks, messageData.totalChunks, messageData.sender, age))
            end
            if count == 0 then
                self:Print("  No pending received chunks")
            end
        else
            self:Print("  No pending received chunks")
        end
        
        if self.sentChunks then
            local count = 0
            for messageId, messageData in pairs(self.sentChunks) do
                count = count + 1
                local age = time() - messageData.timestamp
                self:Print(string.format("  Sent %s: %d chunks (%s, age: %ds)", 
                    messageId, #messageData.chunks, messageData.messageType, age))
            end
            if count == 0 then
                self:Print("  No pending sent chunks")
            end
        else
            self:Print("  No pending sent chunks")
        end
    elseif command == "request" then
        self:Print("Requesting group data from other players...")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Manual group data request (current groups: %d)", self:CountGroups()))
        end
        self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
    elseif command == "list" then
        self:Print(string.format("Current groups (%d):", self:CountGroups()))
        for id, group in pairs(self.groups) do
            local age = math.floor((time() - group.timestamp) / 60)
            self:Print(string.format("  %s: %s (Leader: %s, Age: %d min)", id, group.title, group.leader, age))
        end
        if self:CountGroups() == 0 then
            self:Print("  No groups currently stored")
        end
    elseif command == "players" then
        local playerCount = 0
        for _ in pairs(self.players) do
            playerCount = playerCount + 1
        end
        self:Print(string.format("Known players (%d):", playerCount))
        for name, player in pairs(self.players) do
            local lastSeen = math.floor((time() - player.lastSeen) / 60)
            self:Print(string.format("  %s (Version: %s, Last seen: %d min ago)", name, player.version or "unknown", lastSeen))
        end
        if playerCount == 0 then
            self:Print("  No players currently known")
        end
    else
        self:Print("Usage: /grouper [show|config|join|status|test|debug|presence|chunks|request|list|players]")
    end
end

function Grouper:ShowConfig()
    AceConfigDialog:Open(ADDON_NAME)
end

-- Main window management
function Grouper:ToggleMainWindow()
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        -- Check if we need to join the channel when opening UI
        self:EnsureChannelJoined()
        
        self:CreateMainWindow()
        self:RefreshGroupList()
        self.mainFrame:Show()
    end
end

function Grouper:CreateMainWindow()
    if self.mainFrame then
        self.mainFrame:Show()
        return
    end
    
    self.mainFrame = AceGUI:Create("Frame")
    self.mainFrame:SetTitle("Grouper")
    -- Check actual channel status
    local channelIndex = GetChannelName(ADDON_CHANNEL)
    local actuallyInChannel = channelIndex > 0
    if actuallyInChannel and not self.channelJoined then
        self.channelJoined = true -- Fix status if needed
    end
    self.mainFrame:SetStatusText(actuallyInChannel and "Connected to Grouper channel" or "Not connected to Grouper channel")
    self.mainFrame:SetLayout("Fill")
    self.mainFrame:SetWidth(700)
    self.mainFrame:SetHeight(600)
    self.mainFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.mainFrame = nil
    end)
    
    -- Create main container
    local mainContainer = AceGUI:Create("SimpleGroup")
    mainContainer:SetFullWidth(true)
    mainContainer:SetFullHeight(true)
    mainContainer:SetLayout("Flow")
    self.mainFrame:AddChild(mainContainer)
    
    -- Create tab group
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetTabs({
        {text = "Browse Groups", value = "browse"},
        {text = "Create Group", value = "create"},
        {text = "My Groups", value = "manage"}
    })
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        self:ShowTab(container, group)
    end)
    tabGroup:SelectTab("browse")
    mainContainer:AddChild(tabGroup)
    
    self.tabGroup = tabGroup
end

function Grouper:ShowTab(container, tabName)
    container:ReleaseChildren()
    
    if tabName == "browse" then
        self:CreateBrowseTab(container)
    elseif tabName == "create" then
        self:CreateCreateTab(container)
    elseif tabName == "manage" then
        self:CreateManageTab(container)
    end
end

function Grouper:CreateBrowseTab(container)
    -- Filter section
    local filterGroup = AceGUI:Create("InlineGroup")
    filterGroup:SetTitle("Filters")
    filterGroup:SetFullWidth(true)
    filterGroup:SetLayout("Flow")
    container:AddChild(filterGroup)
    
    -- Level range
    local minLevelSlider = AceGUI:Create("Slider")
    minLevelSlider:SetLabel("Min Level")
    minLevelSlider:SetSliderValues(1, 60, 1)
    minLevelSlider:SetValue(self.db.profile.filters.minLevel)
    minLevelSlider:SetWidth(150)
    minLevelSlider:SetCallback("OnValueChanged", function(widget, event, value)
        self.db.profile.filters.minLevel = value
        self:RefreshGroupList()
    end)
    filterGroup:AddChild(minLevelSlider)
    
    local maxLevelSlider = AceGUI:Create("Slider")
    maxLevelSlider:SetLabel("Max Level")
    maxLevelSlider:SetSliderValues(1, 60, 1)
    maxLevelSlider:SetValue(self.db.profile.filters.maxLevel)
    maxLevelSlider:SetWidth(150)
    maxLevelSlider:SetCallback("OnValueChanged", function(widget, event, value)
        self.db.profile.filters.maxLevel = value
        self:RefreshGroupList()
    end)
    filterGroup:AddChild(maxLevelSlider)
    
    -- Group type checkboxes
    local typeGroup = AceGUI:Create("SimpleGroup")
    typeGroup:SetLayout("Flow")
    typeGroup:SetFullWidth(true)
    filterGroup:AddChild(typeGroup)
    
    local groupTypes = {
        {key = "dungeon", label = "Dungeon"},
        {key = "raid", label = "Raid"},
        {key = "quest", label = "Quest"},
        {key = "other", label = "Other"}
    }
    
    for _, typeInfo in ipairs(groupTypes) do
        local checkbox = AceGUI:Create("CheckBox")
        checkbox:SetLabel(typeInfo.label)
        checkbox:SetValue(self.db.profile.filters.dungeonTypes[typeInfo.key])
        checkbox:SetWidth(100)
        checkbox:SetCallback("OnValueChanged", function(widget, event, value)
            self.db.profile.filters.dungeonTypes[typeInfo.key] = value
            self:RefreshGroupList()
        end)
        typeGroup:AddChild(checkbox)
    end
    
    -- Dungeon filter dropdown
    local dungeonFilter = AceGUI:Create("Dropdown")
    dungeonFilter:SetLabel("Filter by Dungeon")
    dungeonFilter:SetWidth(200)
    
    -- Build dungeon list for dropdown
    local dungeonList = {[""] = "All Dungeons"}
    for _, dungeon in ipairs(DUNGEONS) do
        dungeonList[dungeon.name] = dungeon.name
    end
    dungeonFilter:SetList(dungeonList)
    dungeonFilter:SetValue("")
    dungeonFilter:SetCallback("OnValueChanged", function(widget, event, value)
        self.selectedDungeonFilter = value
        self:RefreshGroupList()
    end)
    filterGroup:AddChild(dungeonFilter)
    
    -- Refresh button
    local refreshButton = AceGUI:Create("Button")
    refreshButton:SetText("Refresh")
    refreshButton:SetWidth(100)
    refreshButton:SetCallback("OnClick", function()
        -- Request fresh data from other players
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Refresh button clicked - requesting fresh data from other players")
        end
        self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
        
        -- Schedule a delayed refresh in case no responses come back
        self:ScheduleTimer(function()
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Delayed refresh after REQUEST_DATA timeout")
            end
            self:RefreshGroupList()
        end, 15) -- Wait 15 seconds for responses
    end)
    filterGroup:AddChild(refreshButton)
    
    -- Groups list
    local groupsScrollFrame = AceGUI:Create("ScrollFrame")
    groupsScrollFrame:SetFullWidth(true)
    groupsScrollFrame:SetFullHeight(true)
    groupsScrollFrame:SetLayout("List")
    container:AddChild(groupsScrollFrame)
    
    self.groupsScrollFrame = groupsScrollFrame
    self:RefreshGroupList()
end

function Grouper:CreateCreateTab(container)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    scrollFrame:SetLayout("Flow")
    container:AddChild(scrollFrame)
    
    -- Group title
    local titleEdit = AceGUI:Create("EditBox")
    titleEdit:SetLabel("Group Title (max 20 chars)")
    titleEdit:SetFullWidth(true)
    titleEdit:SetMaxLetters(20)
    titleEdit:SetText("")
    scrollFrame:AddChild(titleEdit)
    
    -- Event type dropdown (encoded as numbers when sent)
    local typeDropdown = AceGUI:Create("Dropdown")
    typeDropdown:SetLabel("Event Type")
    typeDropdown:SetList({
        dungeon = "Dungeon",
        raid = "Raid",
        quest = "Quest",
        pvp = "PvP",
        other = "Other"
    })
    typeDropdown:SetValue("dungeon") -- Default to dungeon
    typeDropdown:SetFullWidth(true)
    scrollFrame:AddChild(typeDropdown)
    
    -- Level range (move before dungeon selection so it's in scope)
    local levelGroup = AceGUI:Create("SimpleGroup")
    levelGroup:SetLayout("Flow")
    levelGroup:SetFullWidth(true)
    scrollFrame:AddChild(levelGroup)
    
    local minLevelEdit = AceGUI:Create("EditBox")
    minLevelEdit:SetLabel("Min Level")
    minLevelEdit:SetText("15") -- Default for dungeons
    minLevelEdit:SetWidth(100)
    levelGroup:AddChild(minLevelEdit)
    
    local maxLevelEdit = AceGUI:Create("EditBox")
    maxLevelEdit:SetLabel("Max Level")
    maxLevelEdit:SetText("25") -- Default for dungeons  
    maxLevelEdit:SetWidth(100)
    levelGroup:AddChild(maxLevelEdit)
    
    -- Dungeon selection (multi-select) - filtered by type dropdown
    local dungeonGroup = AceGUI:Create("InlineGroup")
    dungeonGroup:SetTitle("Select Dungeons/Raids")
    dungeonGroup:SetFullWidth(true)
    dungeonGroup:SetLayout("Flow")
    scrollFrame:AddChild(dungeonGroup)
    
    local selectedDungeons = {}
    local dungeonCheckboxes = {}
    
    -- Function to filter dungeons based on selected type
    local function updateDungeonList()
        local selectedType = typeDropdown:GetValue()
        dungeonGroup:ReleaseChildren()
        selectedDungeons = {}
        dungeonCheckboxes = {}
        
        -- Only show dungeon list if dungeon or raid is selected
        if selectedType ~= "dungeon" and selectedType ~= "raid" then
            return
        end
        
        for i, dungeon in ipairs(DUNGEONS) do
            -- Show dungeons/raids that match the selected type, or show all if "other"
            if selectedType == "other" or dungeon.type == selectedType then
                local checkbox = AceGUI:Create("CheckBox")
            checkbox:SetLabel(string.format("%s (%d-%d)", dungeon.name, dungeon.minLevel, dungeon.maxLevel))
            checkbox:SetWidth(300)
            checkbox:SetCallback("OnValueChanged", function(widget, event, value)
                if value then
                    selectedDungeons[dungeon.name] = dungeon
                    -- Auto-update level range to this dungeon's range
                    minLevelEdit:SetText(tostring(dungeon.minLevel))
                    maxLevelEdit:SetText(tostring(dungeon.maxLevel))
                else
                    selectedDungeons[dungeon.name] = nil
                    -- If no dungeons selected, reset to default dungeon range
                    local anySelected = false
                    for name, selected in pairs(selectedDungeons) do
                        if selected then
                            anySelected = true
                            break
                        end
                    end
                    if not anySelected then
                        minLevelEdit:SetText("15")
                        maxLevelEdit:SetText("25")
                    end
                end
            end)
            dungeonGroup:AddChild(checkbox)
            dungeonCheckboxes[dungeon.name] = checkbox
            end
        end
    end
    
    -- Update dungeon list when type dropdown changes
    typeDropdown:SetCallback("OnValueChanged", function(widget, event, value)
        -- Set appropriate level defaults based on type
        if value == "dungeon" then
            minLevelEdit:SetText("15")
            maxLevelEdit:SetText("25")
        elseif value == "raid" then
            minLevelEdit:SetText("60")
            maxLevelEdit:SetText("60")
        else
            minLevelEdit:SetText("1")
            maxLevelEdit:SetText("60")
        end
        updateDungeonList()
    end)
    
    -- Initialize dungeon list
    updateDungeonList()
    
    -- Group size
    local sizeGroup = AceGUI:Create("SimpleGroup")
    sizeGroup:SetLayout("Flow")
    sizeGroup:SetFullWidth(true)
    scrollFrame:AddChild(sizeGroup)
    
    local currentSizeEdit = AceGUI:Create("EditBox")
    currentSizeEdit:SetLabel("Current Size")
    currentSizeEdit:SetText("1")
    currentSizeEdit:SetWidth(100)
    sizeGroup:AddChild(currentSizeEdit)
    
    local maxSizeEdit = AceGUI:Create("EditBox")
    maxSizeEdit:SetLabel("Max Size")
    maxSizeEdit:SetText("5")
    maxSizeEdit:SetWidth(100)
    sizeGroup:AddChild(maxSizeEdit)
    
    -- Location
    local locationEdit = AceGUI:Create("EditBox")
    locationEdit:SetLabel("Location/Meeting Point (max 20 chars)")
    locationEdit:SetFullWidth(true)
    locationEdit:SetMaxLetters(20)
    locationEdit:SetText("")
    scrollFrame:AddChild(locationEdit)
    
    -- My role dropdown
    local roleDropdown = AceGUI:Create("Dropdown")
    roleDropdown:SetLabel("My Role")
    roleDropdown:SetList({
        tank = "Tank",
        healer = "Healer",
        dps = "DPS",
        leader = "Leader"
    })
    roleDropdown:SetValue("dps")
    roleDropdown:SetFullWidth(true)
    scrollFrame:AddChild(roleDropdown)
    
    -- Create button
    local createButton = AceGUI:Create("Button")
    createButton:SetText("Create Group")
    createButton:SetFullWidth(true)
    createButton:SetCallback("OnClick", function()
        local selectedType = typeDropdown:GetValue()
        
        -- Encode type as number: 1=Dungeon, 2=Raid, 3=Quest, 4=PvP, 5=Other
        local typeId = 1 -- Default to dungeon
        if selectedType == "dungeon" then typeId = 1
        elseif selectedType == "raid" then typeId = 2
        elseif selectedType == "quest" then typeId = 3
        elseif selectedType == "pvp" then typeId = 4
        elseif selectedType == "other" then typeId = 5
        end
        
        local groupData = {
            title = titleEdit:GetText(),
            description = "", -- No longer used
            type = selectedType or "dungeon",
            typeId = typeId,
            minLevel = tonumber(minLevelEdit:GetText()) or 15,
            maxLevel = tonumber(maxLevelEdit:GetText()) or 25,
            currentSize = tonumber(currentSizeEdit:GetText()) or 1,
            maxSize = tonumber(maxSizeEdit:GetText()) or 5,
            location = locationEdit:GetText(),
            myRole = roleDropdown:GetValue(),
            dungeons = selectedDungeons
        }
        
        if groupData.title == "" then
            self:Print("Please enter a group title!")
            return
        end
        
        self:CreateGroup(groupData)
        
        -- Switch to manage tab
        if self.tabGroup then
            self.tabGroup:SelectTab("manage")
        end
    end)
    scrollFrame:AddChild(createButton)
end

function Grouper:CreateManageTab(container)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    scrollFrame:SetLayout("List")
    container:AddChild(scrollFrame)
    
    local myGroups = {}
    for _, group in pairs(self.groups) do
        if group.leader == UnitName("player") then
            table.insert(myGroups, group)
        end
    end
    
    if #myGroups == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("You haven't created any groups yet. Use the 'Create Group' tab to make one!")
        label:SetFullWidth(true)
        scrollFrame:AddChild(label)
    else
        for _, group in ipairs(myGroups) do
            local groupFrame = self:CreateGroupManageFrame(group)
            scrollFrame:AddChild(groupFrame)
        end
    end
end

function Grouper:CreateGroupManageFrame(group)
    local frame = AceGUI:Create("InlineGroup")
    frame:SetTitle(group.title)
    frame:SetFullWidth(true)
    frame:SetLayout("Flow")
    
    -- Group info
    local infoLabel = AceGUI:Create("Label")
    infoLabel:SetText(string.format("Type: %s | Level: %d-%d | Size: %d/%d\nLocation: %s\nDescription: %s",
        group.type, group.minLevel, group.maxLevel, group.currentSize, group.maxSize,
        group.location ~= "" and group.location or "Not specified",
        group.description ~= "" and group.description or "No description"))
    infoLabel:SetFullWidth(true)
    frame:AddChild(infoLabel)
    
    -- Buttons
    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetLayout("Flow")
    buttonGroup:SetFullWidth(true)
    frame:AddChild(buttonGroup)
    
    local editButton = AceGUI:Create("Button")
    editButton:SetText("Edit")
    editButton:SetWidth(100)
    editButton:SetCallback("OnClick", function()
        self:ShowEditGroupDialog(group)
    end)
    buttonGroup:AddChild(editButton)
    
    local removeButton = AceGUI:Create("Button")
    removeButton:SetText("Remove")
    removeButton:SetWidth(100)
    removeButton:SetCallback("OnClick", function()
        self:RemoveGroup(group.id)
        if self.tabGroup then
            self.tabGroup:SelectTab("manage") -- Refresh the tab
        end
    end)
    buttonGroup:AddChild(removeButton)
    
    return frame
end

function Grouper:RefreshGroupList()
    if not self.groupsScrollFrame then
        return
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: 🔄 RefreshGroupList called. Groups in memory:"))
        for id, group in pairs(self.groups) do
            self:Print(string.format("DEBUG:   - %s: %s (leader: %s)", id, group.title, group.leader))
        end
    end
    
    self.groupsScrollFrame:ReleaseChildren()
    
    local filteredGroups = self:GetFilteredGroups()
    
    if #filteredGroups == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No groups found matching your filters.")
        label:SetFullWidth(true)
        self.groupsScrollFrame:AddChild(label)
        return
    end
    
    for _, group in ipairs(filteredGroups) do
        local groupFrame = self:CreateGroupFrame(group)
        self.groupsScrollFrame:AddChild(groupFrame)
    end
end

function Grouper:CreateGroupFrame(group)
    local frame = AceGUI:Create("InlineGroup")
    frame:SetTitle(string.format("%s (%d/%d)", group.title, group.currentSize, group.maxSize))
    frame:SetFullWidth(true)
    frame:SetLayout("Flow")
    
    -- Group details
    local dungeonsList = ""
    if group.dungeons and next(group.dungeons) then
        local dungeonNames = {}
        for dungeonName, _ in pairs(group.dungeons) do
            table.insert(dungeonNames, dungeonName)
        end
        dungeonsList = "\n|cffFFD700Dungeons:|r " .. table.concat(dungeonNames, ", ")
    end
    
    local detailsLabel = AceGUI:Create("Label")
    
    -- Format leader name with role if available
    local leaderText = group.leader
    if group.leaderRole then
        local roleColors = {
            tank = "|cff0070DD", -- Blue for tank
            healer = "|cff40FF40", -- Green for healer
            dps = "|cffFF4040" -- Red for DPS
        }
        local roleColor = roleColors[group.leaderRole] or "|cffFFFFFF"
        local roleCapitalized = group.leaderRole:gsub("^%l", string.upper) -- Capitalize first letter
        leaderText = string.format("%s (%s%s|r)", group.leader, roleColor, roleCapitalized)
    end
    
    detailsLabel:SetText(string.format("|cffFFD700Leader:|r %s  |cffFFD700Type:|r %s  |cffFFD700Level:|r %d-%d\n|cffFFD700Location:|r %s%s\n|cffFFD700Description:|r %s",
        leaderText,
        group.type,
        group.minLevel, group.maxLevel,
        group.location ~= "" and group.location or "Not specified",
        dungeonsList,
        group.description ~= "" and group.description or "No description"))
    detailsLabel:SetFullWidth(true)
    frame:AddChild(detailsLabel)
    
    -- Timestamp
    local timeLabel = AceGUI:Create("Label")
    timeLabel:SetText(string.format("|cff808080Posted: %s ago|r", self:FormatTimestamp(group.timestamp)))
    timeLabel:SetFullWidth(true)
    frame:AddChild(timeLabel)
    
    -- Action buttons
    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetLayout("Flow")
    buttonGroup:SetFullWidth(true)
    frame:AddChild(buttonGroup)
    
    local whisperButton = AceGUI:Create("Button")
    whisperButton:SetText("Whisper Leader")
    whisperButton:SetWidth(120)
    whisperButton:SetCallback("OnClick", function()
        -- Classic-compatible whisper initiation
        if ChatEdit_GetActiveWindow then
            local editBox = ChatEdit_GetActiveWindow()
            if editBox then
                ChatEdit_ActivateChat(editBox)
                editBox:SetText("/tell " .. group.leader .. " ")
            end
        else
            -- Fallback for different Classic versions
            DEFAULT_CHAT_FRAME.editBox:SetText("/tell " .. group.leader .. " ")
            ChatEdit_ActivateChat(DEFAULT_CHAT_FRAME.editBox)
        end
    end)
    buttonGroup:AddChild(whisperButton)
    
    local inviteButton = AceGUI:Create("Button")
    inviteButton:SetText("Request Invite")
    inviteButton:SetWidth(120)
    inviteButton:SetCallback("OnClick", function()
        SendChatMessage(string.format("Hi! I'd like to join your group: %s", group.title), "WHISPER", nil, group.leader)
    end)
    buttonGroup:AddChild(inviteButton)
    
    return frame
end

function Grouper:FormatTimestamp(timestamp)
    local diff = time() - timestamp
    if diff < 60 then
        return string.format("%ds", diff)
    elseif diff < 3600 then
        return string.format("%dm", math.floor(diff / 60))
    else
        return string.format("%dh", math.floor(diff / 3600))
    end
end

function Grouper:ShowEditGroupDialog(group)
    -- This is a placeholder for the edit dialog
    self:Print("Edit functionality coming soon!")
end

-- Setup options/config
function Grouper:SetupOptions()
    local options = {
        name = ADDON_NAME,
        type = "group",
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    minimap = {
                        name = "Minimap Icon",
                        desc = "Toggle the minimap icon",
                        type = "toggle",
                        set = function(info, val)
                            self.db.profile.minimap.hide = not val
                            if val then
                                LibDBIcon:Show(ADDON_NAME)
                            else
                                LibDBIcon:Hide(ADDON_NAME)
                            end
                        end,
                        get = function(info) return not self.db.profile.minimap.hide end,
                    },
                },
            },
            notifications = {
                name = "Notifications",
                type = "group",
                order = 2,
                args = {
                    newGroups = {
                        name = "New Groups",
                        desc = "Show notification when new groups are posted",
                        type = "toggle",
                        set = function(info, val) self.db.profile.notifications.newGroups = val end,
                        get = function(info) return self.db.profile.notifications.newGroups end,
                    },
                },
            },
        },
    }
    
    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    AceConfigDialog:AddToBlizOptions(ADDON_NAME)
end