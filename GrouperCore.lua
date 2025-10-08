Grouper = LibStub("AceAddon-3.0"):NewAddon("Grouper", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
-- Global utility to update playerInfo cache
function Grouper:UpdatePlayerInfo()
    local playerName = UnitName("player")
    local race = UnitRace("player")
    local class = select(2, UnitClass("player"))
    local level = UnitLevel("player")
    local fullName = playerName and (playerName .. "-" .. (GetRealmName():gsub("%s", ""))) or ""
    self.playerInfo = {
        fullName = fullName,
        name = playerName,
        race = race,
        class = class,
        level = level
    }
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Updated playerInfo cache: Name=%s, Class=%s, Race=%s, Level=%s, FullName=%s", playerName or "", class or "", race or "", level or "", fullName or ""))
    end
end
AceGUI = LibStub("AceGUI-3.0")

-- Register AceComm prefixes to ensure message handling
AceComm = LibStub("AceComm-3.0")
AceComm:RegisterComm("GRPR_GRP_UPD", function(...) Grouper:OnCommReceived(...) end)
AceComm:RegisterComm("GRPR_AUTOJOIN", function(...) Grouper:OnCommReceived(...) end)
AceComm:RegisterComm("GRPR_TEST", function(...) Grouper:OnCommReceived(...) end)

function Grouper:OnEnable()
    -- Filter Grouper channel messages from General tab only
    local grouperChannelName = "Grouper"
    local function Grouper_GeneralChatFilter(self, event, msg, author, ...)
        local _, chanName = ...
        if self == DEFAULT_CHAT_FRAME and chanName and chanName:lower() == grouperChannelName:lower() then
            return true -- Block message in General tab
        end
        return false
    end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", Grouper_GeneralChatFilter)

    -- Remove Grouper channel from General tab on login and channel changes
    local function RemoveGrouperFromGeneral()
        ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, grouperChannelName)
    end
    RemoveGrouperFromGeneral()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHANNEL_UI_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event)
        C_Timer.After(1, RemoveGrouperFromGeneral)
    end)
    -- Always update playerInfo cache at startup
    self:UpdatePlayerInfo()
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInviteRequest")
    self:RegisterEvent("PARTY_MEMBER_ENABLE", "OnPartyChanged")
    self:RegisterEvent("PARTY_MEMBER_DISABLE", "OnPartyChanged")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "OnPartyChanged")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "OnPartyChanged")
    self:RegisterEvent("CHAT_MSG_CHANNEL_JOIN", "OnChannelJoin")
    self:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE", "OnChannelLeave")
    self:RegisterEvent("CHAT_MSG_CHANNEL", "OnChannelMessage")

    -- Register AceComm message handlers
    self:RegisterComm("GRPR_GROUP", "OnCommReceived")       -- Compact GROUP_UPDATE via channel
    self:RegisterComm("GRPR_GRP_UPD", "OnCommReceived")     -- Serialized GROUP_UPDATE via whisper
    self:RegisterComm("GRPR_GRP_RMV", "OnCommReceived")     -- GROUP_REMOVE messages
    self:RegisterComm("GRPR_CHUNK_REQ", "OnCommReceived")   -- Chunk requests
    self:RegisterComm("GRPR_CHUNK_RES", "OnCommReceived")   -- Chunk responses
    self:RegisterComm("GROUPER_TEST", "OnCommReceived")     -- Test messages
    self:RegisterComm("GRPR_AUTOJOIN", "OnCommReceived") -- Auto-join invite requests

    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: OnEnable - Registered events and AceComm prefixes for Grouper communication.")
    end
end

-- Classic Era API Compatibility Functions (scoped to Grouper)
function Grouper:GetGroupSize()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return GetNumRaidMembers()
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        return GetNumPartyMembers()
    else
        return 0 -- Solo
    end
end

function Grouper:IsInGroup()
    return self:GetGroupSize() > 0
end

function Grouper:IsInRaidGroup()
    return GetNumRaidMembers and GetNumRaidMembers() > 0 or false
end

function Grouper:IsInPartyGroup()
    return GetNumPartyMembers and GetNumPartyMembers() > 0 or false
end

function Grouper:IsGroupLeader()
    if self:IsInRaidGroup() then
        return IsRaidLeader and IsRaidLeader() or false
    elseif self:IsInPartyGroup() then
        return IsPartyLeader and IsPartyLeader() or false
    else
        return false
    end
end

-- Handles group/raid changes and refreshes UI
function Grouper:OnPartyChanged(event)
    -- Group join/change logic commented out by request
    -- if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
    --     self:Print(string.format("DEBUG: Group changed event: %s", event or "unknown"))
    -- end
    -- -- Repopulate group data using leader's cache logic
    -- if self:IsGroupLeader() and self.groups then
    --     for _, group in pairs(self.groups) do
    --         if group.leader == UnitName("player") then
    --             self:CreateGroup({
    --                 title = group.title,
    --                 description = group.description,
    --                 type = group.type,
    --                 minLevel = group.minLevel,
    --                 maxLevel = group.maxLevel,
    --                 currentSize = group.currentSize,
    --                 maxSize = group.maxSize,
    --                 location = group.location,
    --                 dungeons = group.dungeons
    --             })
    --         end
    --     end
    -- end
    -- -- Refresh UI if open
    -- if self.mainFrame and self.mainFrame:IsShown() then
    --     self:RefreshGroupList()
    -- end
end

-- Register CHAT_MSG_SYSTEM event to handle party join system messages (after Grouper is initialized)
function Grouper:OnChatMsgSystem(event, text)
    -- System message group join logic commented out by request
    -- if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
    --     self:Print("DEBUG: CHAT_MSG_SYSTEM: " .. tostring(text))
    -- end
    -- -- Detect 'joins the party.' system message
    -- local joinedName = text and text:match("^(.-) joins the party%.")
    -- if joinedName then
    --     if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
    --         self:Print("DEBUG: Detected party join by " .. joinedName)
    --     end
    --     -- Repopulate group data using leader's cache logic
    --     if self:IsGroupLeader() and self.groups then
    --         for _, group in pairs(self.groups) do
    --             if group.leader == UnitName("player") then
    --                 self:CreateGroup({
    --                     title = group.title,
    --                     description = group.description,
    --                     type = group.type,
    --                     minLevel = group.minLevel,
    --                     maxLevel = group.maxLevel,
    --                     currentSize = group.currentSize,
    --                     maxSize = group.maxSize,
    --                     location = group.location,
    --                     dungeons = group.dungeons
    --                 })
    --             end
    --         end
    --     end
    --     -- Refresh UI if open
    --     if self.mainFrame and self.mainFrame:IsShown() then
    --         self:RefreshGroupList()
    --     end
    -- end
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

function Grouper:OnInitialize()
    -- Initialize database
    self.db = AceDB:New("GrouperDB", defaults, true)

    -- Only initialize self.groups if it doesn't already exist
    if not self.groups then
        self.groups = {}
    end
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
        local lastRole = self.db and self.db.profile and self.db.profile.lastRole
        -- Only update role if entry exists, do not create duplicate
        local info = self.players[fullName]
        if info then
            if lastRole and (lastRole == "tank" or lastRole == "healer" or lastRole == "dps") then
                info.role = lastRole
            end
            self.playerInfo = info
        else
            local newInfo = {
                name = fullName, -- Always use full name (with realm) for consistency
                class = class,
                race = race,
                level = level,
                fullName = fullName,
                lastSeen = time(),
                version = ADDON_VERSION,
                role = (lastRole and (lastRole == "tank" or lastRole == "healer" or lastRole == "dps")) and lastRole or nil
            }
            self.playerInfo = newInfo
            self.players[fullName] = newInfo
        end
    end

    -- Register chat commands
    self:RegisterChatCommand("grouper", "SlashCommand")

    -- Initialize minimap icon using LibDataBroker-1.1:NewDataObject for best LDB/Titan compatibility

    local LDB = LibStub("LibDataBroker-1.1")
    self.LDBDataObject = LDB:NewDataObject("Grouper", {
        type = "launcher",
        text = "Grouper",
        icon = "Interface\\AddOns\\Grouper\\Textures\\GrouperIcon.tga",
        OnClick = function(_, button)
            if button == "LeftButton" then
                Grouper:ToggleMainWindow()
            elseif button == "RightButton" then
                -- Toggle the Blizzard AddOns options panel for Grouper
                local opened = false
                if InterfaceOptionsFrame and InterfaceOptionsFrame_OpenToCategory then
                    if InterfaceOptionsFrame:IsShown() then
                        HideUIPanel(InterfaceOptionsFrame)
                        opened = true
                    else
                        InterfaceOptionsFrame_OpenToCategory(ADDON_NAME)
                        opened = true
                    end
                elseif Settings and Settings.OpenToCategory then
                    if SettingsPanel and SettingsPanel:IsVisible() then
                        SettingsPanel:Hide()
                        opened = true
                    else
                        Settings.OpenToCategory(ADDON_NAME)
                        opened = true
                    end
                end
                if not opened then
                    Grouper:Print("Open the options via ESC > Interface > AddOns > Grouper.")
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Grouper")
            tooltip:AddLine("Left-click: Open Grouper window", 1, 1, 1)
            tooltip:AddLine("Right-click: Options", 1, 1, 1)
        end,
    })
    LibDBIcon:Register("Grouper", self.LDBDataObject, self.db.profile.minimap)

    function Grouper:UpdateLDBGroupCount()
        if not self.LDBDataObject then return end
        local available = 0
        if self.groups then
            for _, group in pairs(self.groups) do
                if group.currentSize and group.maxSize and group.currentSize < group.maxSize then
                    available = available + 1
                end
            end
        end
        self.LDBDataObject.text = string.format("Grouper: %d", available)
    end

    -- Initial update
    self:UpdateLDBGroupCount()

    -- Create options table
    self:SetupOptions()

    self:Print("Loaded! Type /grouper to open the group finder.")

    -- Register events and AceComm handlers for group/channel changes and communication
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInviteRequest")
    self:RegisterEvent("PARTY_MEMBER_ENABLE", "OnPartyChanged")
    self:RegisterEvent("PARTY_MEMBER_DISABLE", "OnPartyChanged")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "OnPartyChanged")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "OnPartyChanged")
    self:RegisterEvent("CHAT_MSG_CHANNEL_JOIN", "OnChannelJoin")
    self:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE", "OnChannelLeave")
    self:RegisterEvent("CHAT_MSG_CHANNEL", "OnChannelMessage")

    -- Register AceComm message handlers
    self:RegisterComm("GRPR_GROUP", "OnCommReceived")       -- Compact GROUP_UPDATE via channel
    self:RegisterComm("GRPR_GRP_UPD", "OnCommReceived")     -- Serialized GROUP_UPDATE via whisper
    self:RegisterComm("GRPR_GRP_RMV", "OnCommReceived")     -- GROUP_REMOVE messages
    self:RegisterComm("GRPR_CHUNK_REQ", "OnCommReceived")   -- Chunk requests
    self:RegisterComm("GRPR_CHUNK_RES", "OnCommReceived")   -- Chunk responses
    self:RegisterComm("GROUPER_TEST", "OnCommReceived")     -- Test messages
    self:RegisterComm("GrouperAutoJoin", "OnAutoJoinRequest") -- Auto-join invite requests

    if self.db.profile.debug.enabled then
        self:Print("DEBUG: Registered events and AceComm prefixes for Grouper communication.")
    end
end
