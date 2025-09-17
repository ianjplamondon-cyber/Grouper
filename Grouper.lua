local Grouper = LibStub("AceAddon-3.0"):NewAddon("Grouper", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LibDBIcon = LibStub("LibDBIcon-1.0")

-- Constants
local ADDON_NAME = "Grouper"
local COMM_PREFIX = "Grouper"
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

-- Data structures
Grouper.groups = {}
Grouper.players = {}
Grouper.channelJoined = false

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
    
    -- Register chat commands
    self:RegisterChatCommand("grouper", "SlashCommand")
    
    -- Register for communication
    self:RegisterComm(COMM_PREFIX)
    
    -- Initialize minimap icon
    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimap)
    
    -- Create options table
    self:SetupOptions()
    
    self:Print("Loaded! Type /grouper to open the group finder.")
end

function Grouper:OnEnable()
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED", "OnPartyChanged")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "OnPartyChanged")
    self:RegisterEvent("CHAT_MSG_CHANNEL_JOIN", "OnChannelJoin")
    self:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE", "OnChannelLeave")
    
    -- Try to join the Grouper channel
    self:ScheduleTimer("JoinGrouperChannel", 2)
    
    -- Start periodic tasks
    self:ScheduleRepeatingTimer("CleanupOldGroups", 60) -- Clean up every minute
    self:ScheduleRepeatingTimer("BroadcastPresence", 300) -- Broadcast presence every 5 minutes
end

function Grouper:OnPlayerEnteringWorld()
    -- Join Grouper channel when entering world
    self:ScheduleTimer("JoinGrouperChannel", 5)
end

function Grouper:JoinGrouperChannel()
    if not self.channelJoined then
        local channelIndex = GetChannelName(ADDON_CHANNEL)
        if channelIndex == 0 then
            -- Channel doesn't exist, try to join/create it
            local success = JoinChannelByName(ADDON_CHANNEL)
            if success then
                self:Print("Joining Grouper channel for group communication...")
                -- Check again in a moment to see if we joined
                self:ScheduleTimer("CheckChannelStatus", 2)
            else
                self:Print("Failed to join Grouper channel. Retrying in 10 seconds...")
                self:ScheduleTimer("JoinGrouperChannel", 10)
            end
        else
            -- Channel exists, mark as joined
            self.channelJoined = true
            self:Print("Connected to Grouper channel. You can now see groups from other addon users!")
            -- Request current group data from other users
            self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
        end
    end
end

function Grouper:CheckChannelStatus()
    if not self.channelJoined then
        local channelIndex = GetChannelName(ADDON_CHANNEL)
        if channelIndex > 0 then
            self.channelJoined = true
            self:Print("Successfully connected to Grouper channel!")
            -- Request current group data from other users
            self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
        else
            -- Still not connected, try again
            self:Print("Still connecting to Grouper channel...")
            self:ScheduleTimer("JoinGrouperChannel", 5)
        end
    end
end

function Grouper:OnChannelJoin(event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    if channelBaseName == ADDON_CHANNEL and playerName == UnitName("player") then
        self.channelJoined = true
        self:Print("Successfully joined Grouper channel!")
        -- Request current group data from other users
        self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
    end
end

function Grouper:OnChannelLeave(event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName)
    if channelBaseName == ADDON_CHANNEL and playerName == UnitName("player") then
        self.channelJoined = false
        self:Print("Disconnected from Grouper channel. Reconnecting...")
        self:ScheduleTimer("JoinGrouperChannel", 5)
    end
end

function Grouper:OnPartyChanged()
    -- Update our group status and broadcast if needed
    self:BroadcastPresence()
end

-- Communication functions
function Grouper:SendComm(messageType, data, distribution, target)
    if not self.channelJoined then
        return
    end
    
    local message = {
        type = messageType,
        sender = UnitName("player"),
        timestamp = time(),
        version = ADDON_VERSION,
        data = data
    }
    
    local serializedData = self:Serialize(message)
    
    -- Default to channel communication
    distribution = distribution or "CHANNEL"
    target = target or ADDON_CHANNEL
    
    self:SendCommMessage(COMM_PREFIX, serializedData, distribution, target)
end

function Grouper:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= COMM_PREFIX or sender == UnitName("player") then
        return
    end
    
    local success, data = self:Deserialize(message)
    if not success then
        return
    end
    
    -- Update player list
    self.players[sender] = {
        name = sender,
        lastSeen = time(),
        version = data.version or "unknown"
    }
    
    -- Handle different message types
    if data.type == "GROUP_UPDATE" then
        self:HandleGroupUpdate(data.data, sender)
    elseif data.type == "GROUP_REMOVE" then
        self:HandleGroupRemove(data.data, sender)
    elseif data.type == "REQUEST_DATA" then
        self:HandleDataRequest(sender)
    elseif data.type == "PRESENCE" then
        self:HandlePresence(data.data, sender)
    end
    
    -- Refresh UI if it's open
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshGroupList()
    end
end

-- Group management functions
function Grouper:CreateGroup(groupData)
    local group = {
        id = self:GenerateGroupID(),
        leader = UnitName("player"),
        title = groupData.title or "Untitled Group",
        description = groupData.description or "",
        type = groupData.type or "other",
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

function Grouper:HandleGroupUpdate(groupData, sender)
    if groupData.leader == sender then
        self.groups[groupData.id] = groupData
        
        if self.db.profile.notifications.newGroups then
            self:Print(string.format("New group available: %s", groupData.title))
        end
    end
end

function Grouper:HandleGroupRemove(data, sender)
    local group = self.groups[data.id]
    if group and group.leader == sender then
        self.groups[data.id] = nil
    end
end

function Grouper:HandleDataRequest(sender)
    -- Send our groups to the requesting player
    for _, group in pairs(self.groups) do
        if group.leader == UnitName("player") then
            self:SendComm("GROUP_UPDATE", group, "WHISPER", sender)
        end
    end
end

function Grouper:HandlePresence(data, sender)
    -- Update player presence information
    self.players[sender].status = data.status
    self.players[sender].groupId = data.groupId
end

function Grouper:BroadcastPresence()
    local status = "available"
    local groupId = nil
    
    if IsInRaid() then
        status = "in_raid"
    elseif IsInGroup() then
        status = "in_party"
    end
    
    self:SendComm("PRESENCE", {
        status = status,
        groupId = groupId,
        level = UnitLevel("player"),
        class = UnitClass("player")
    })
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

function Grouper:GetFilteredGroups()
    local filtered = {}
    local filters = self.db.profile.filters
    
    for _, group in pairs(self.groups) do
        local include = true
        
        -- Level filter
        if group.minLevel > filters.maxLevel or group.maxLevel < filters.minLevel then
            include = false
        end
        
        -- Type filter
        if not filters.dungeonTypes[group.type] then
            include = false
        end
        
        -- Dungeon filter
        if self.selectedDungeonFilter and self.selectedDungeonFilter ~= "" then
            if not group.dungeons or not group.dungeons[self.selectedDungeonFilter] then
                include = false
            end
        end
        
        if include then
            table.insert(filtered, group)
        end
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
        self.channelJoined = false -- Force a rejoin attempt
        self:JoinGrouperChannel()
    elseif command == "status" then
        local channelIndex = GetChannelName(ADDON_CHANNEL)
        local actuallyInChannel = channelIndex > 0
        self:Print(string.format("Groups: %d, Players: %d", #self.groups, #self.players))
        self:Print(string.format("Channel Status: %s (Index: %d)", 
            actuallyInChannel and "Connected" or "Disconnected", channelIndex))
        self:Print(string.format("Internal Status: %s", 
            self.channelJoined and "Connected" or "Disconnected"))
        
        -- Auto-fix if there's a mismatch
        if actuallyInChannel and not self.channelJoined then
            self:Print("Fixing channel status...")
            self.channelJoined = true
        elseif not actuallyInChannel and self.channelJoined then
            self:Print("Reconnecting to channel...")
            self.channelJoined = false
            self:JoinGrouperChannel()
        end
    else
        self:Print("Usage: /grouper [show|config|join|status]")
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
        self:CreateMainWindow()
        self.mainFrame:Show()
        self:RefreshGroupList()
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
        self:RefreshGroupList()
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
    titleEdit:SetLabel("Group Title")
    titleEdit:SetFullWidth(true)
    titleEdit:SetText("")
    scrollFrame:AddChild(titleEdit)
    
    -- Description
    local descEdit = AceGUI:Create("MultiLineEditBox")
    descEdit:SetLabel("Description")
    descEdit:SetFullWidth(true)
    descEdit:SetNumLines(3)
    descEdit:SetText("")
    scrollFrame:AddChild(descEdit)
    
    -- Group type dropdown
    local typeDropdown = AceGUI:Create("Dropdown")
    typeDropdown:SetLabel("Group Type")
    typeDropdown:SetList({
        dungeon = "Dungeon",
        raid = "Raid", 
        quest = "Quest",
        other = "Other"
    })
    typeDropdown:SetValue("dungeon")
    typeDropdown:SetFullWidth(true)
    scrollFrame:AddChild(typeDropdown)
    
    -- Dungeon selection (multi-select)
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
        
        for i, dungeon in ipairs(DUNGEONS) do
            if selectedType == "other" or dungeon.type == selectedType then
                local checkbox = AceGUI:Create("CheckBox")
                checkbox:SetLabel(string.format("%s (%d-%d)", dungeon.name, dungeon.minLevel, dungeon.maxLevel))
                checkbox:SetWidth(300)
                checkbox:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        selectedDungeons[dungeon.name] = dungeon
                    else
                        selectedDungeons[dungeon.name] = nil
                    end
                end)
                dungeonGroup:AddChild(checkbox)
                dungeonCheckboxes[dungeon.name] = checkbox
            end
        end
    end
    
    -- Update dungeon list when type changes
    typeDropdown:SetCallback("OnValueChanged", function()
        updateDungeonList()
    end)
    
    -- Initialize dungeon list
    updateDungeonList()
    
    -- Level range
    local levelGroup = AceGUI:Create("SimpleGroup")
    levelGroup:SetLayout("Flow")
    levelGroup:SetFullWidth(true)
    scrollFrame:AddChild(levelGroup)
    
    local minLevelEdit = AceGUI:Create("EditBox")
    minLevelEdit:SetLabel("Min Level")
    minLevelEdit:SetText("1")
    minLevelEdit:SetWidth(100)
    levelGroup:AddChild(minLevelEdit)
    
    local maxLevelEdit = AceGUI:Create("EditBox")
    maxLevelEdit:SetLabel("Max Level") 
    maxLevelEdit:SetText("60")
    maxLevelEdit:SetWidth(100)
    levelGroup:AddChild(maxLevelEdit)
    
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
    locationEdit:SetLabel("Location/Meeting Point")
    locationEdit:SetFullWidth(true)
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
        local groupData = {
            title = titleEdit:GetText(),
            description = descEdit:GetText(),
            type = typeDropdown:GetValue(),
            minLevel = tonumber(minLevelEdit:GetText()) or 1,
            maxLevel = tonumber(maxLevelEdit:GetText()) or 60,
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
    detailsLabel:SetText(string.format("|cffFFD700Leader:|r %s  |cffFFD700Type:|r %s  |cffFFD700Level:|r %d-%d\n|cffFFD700Location:|r %s%s\n|cffFFD700Description:|r %s",
        group.leader,
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
        ChatFrame_SendTell(group.leader)
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