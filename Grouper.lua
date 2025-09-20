-- Utility to get full player name with realm, always using exact realm format
local function GetFullPlayerName(name)
    if not name then return "" end
    local realm = GetRealmName()
    -- Remove spaces from realm name for consistency
    realm = realm:gsub("%s", "")
    if name:find("-") then
        local base, r = name:match("^(.-)%-(.+)$")
        if base and r then
            r = r:gsub("%s", "")
            return base .. "-" .. r
        end
        return name
    end
    return name .. "-" .. realm
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


function Grouper:SendGroupRemoveViaChannel(data)
    -- Use direct channel messaging for GROUP_REMOVE
    local channelIndex = self:GetGrouperChannelIndex()
    if channelIndex <= 0 then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ✗ Cannot send GROUP_REMOVE - not in Grouper channel")
        end
        return false
    end
    
    -- Create simple GROUP_REMOVE message: GRPR_GROUP_REMOVE:groupId:leader:timestamp
    local message = string.format("GRPR_GROUP_REMOVE:%s:%s:%d",
        data.id or "",
        UnitName("player"),
        time()
    )
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ Sending GROUP_REMOVE via direct channel %d: %s", channelIndex, message))
    end
    
    -- Send via direct channel message
    SendChatMessage(message, "CHANNEL", nil, channelIndex)
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: ✓ GROUP_REMOVE sent via direct channel")
    end
    
    return true
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
        leader = GetFullPlayerName(UnitName("player")),
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
            {
                name = self.playerInfo.fullName,
                class = self.playerInfo.class,
                race = self.playerInfo.race,
                level = self.playerInfo.level
            }
        }
    }
    
    self.groups[group.id] = group
    self:SendComm("GROUP_UPDATE", group)
    self:Print(string.format("Created group: %s", group.title))
    -- Immediately refresh the UI so the new group appears
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshGroupList()
    end
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
    self:Print(string.rep("-", 40))
    self:Print("DEBUG: [HandleGroupUpdate] called")
    self:Print(string.format("DEBUG: sender: %s, leader: %s", sender, groupData and groupData.leader or "nil"))
    self:Print(string.format("DEBUG: Group ID: %s, Title: %s", groupData and groupData.id or "nil", groupData and groupData.title or "nil"))
    if groupData then
        for k, v in pairs(groupData) do
            self:Print(string.format("DEBUG: groupData.%s = %s", k, tostring(v)))
        end
    end
    
    -- Add safety check for nil groupData
    if not groupData then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ERROR - groupData is nil in HandleGroupUpdate")
        end
        return
    end
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Comparing full names - sender: %s, leader: %s", sender, groupData.leader))
    end
    
    if GetFullPlayerName(groupData.leader) == GetFullPlayerName(sender) then
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
            self:Print(string.format("DEBUG: Rejecting group update - sender mismatch (full: %s vs %s)", sender, groupData.leader))
        end
    end
    
    -- Ensure members field is always populated for both local and remote groups
    if not groupData.members or #groupData.members == 0 then
        groupData.members = {
            {
                name = self.playerInfo and self.playerInfo.fullName or GetFullPlayerName(UnitName("player")),
                class = self.playerInfo and self.playerInfo.class or "?",
                race = self.playerInfo and self.playerInfo.race or "?",
                level = self.playerInfo and self.playerInfo.level or 0
            }
        }
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

-- Main window management
function Grouper:SaveWindowPosition()
    if self.mainFrame and self.mainFrame.frame then
        local point, relativeTo, relativePoint, xOfs, yOfs = self.mainFrame.frame:GetPoint()
        if point and relativePoint then
            self.db.profile.ui.position.point = point
            self.db.profile.ui.position.relativePoint = relativePoint
            self.db.profile.ui.position.xOfs = xOfs or 0
            self.db.profile.ui.position.yOfs = yOfs or 0
            
            -- Save window size
            local width = self.mainFrame.frame:GetWidth()
            local height = self.mainFrame.frame:GetHeight()
            self.db.profile.ui.position.width = width
            self.db.profile.ui.position.height = height

            -- Force database save to ensure position and size are written to SavedVariables
            if self.db.Flush then
                self.db:Flush()
            end

            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Saved window position: %s %s %.0f %.0f, size: %.0f x %.0f", point, relativePoint, xOfs or 0, yOfs or 0, width or 0, height or 0))
            end
        end
    end
end

function Grouper:RestoreWindowPosition()
    if self.mainFrame and self.mainFrame.frame then
        local pos = self.db.profile.ui.position
        if pos.point and pos.relativePoint and pos.xOfs ~= nil and pos.yOfs ~= nil then
            self.mainFrame.frame:ClearAllPoints()
            self.mainFrame.frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
            -- Restore window size if available
            if pos.width and pos.height then
                self.mainFrame.frame:SetWidth(pos.width)
                self.mainFrame.frame:SetHeight(pos.height)
            end
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Restored window position: %s %s %.0f %.0f, size: %.0f x %.0f", pos.point, pos.relativePoint, pos.xOfs, pos.yOfs, pos.width or 0, pos.height or 0))
                -- Verify the position and size were actually set
                local actualPoint, actualRelativeTo, actualRelativePoint, actualXOfs, actualYOfs = self.mainFrame.frame:GetPoint()
                local actualWidth = self.mainFrame.frame:GetWidth()
                local actualHeight = self.mainFrame.frame:GetHeight()
                self:Print(string.format("DEBUG: Verified position after restore: %s %s %.0f %.0f, size: %.0f x %.0f", actualPoint or "nil", actualRelativePoint or "nil", actualXOfs or 0, actualYOfs or 0, actualWidth or 0, actualHeight or 0))
            end
        else
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Cannot restore position - missing data: point=%s, relativePoint=%s, xOfs=%s, yOfs=%s", 
                    tostring(pos.point), tostring(pos.relativePoint), tostring(pos.xOfs), tostring(pos.yOfs)))
            end
        end
    end
end

function Grouper:SetupPositionSaving()
    if self.mainFrame and self.mainFrame.frame then
        -- Save position when frame is dragged
        self.mainFrame.frame:SetScript("OnDragStop", function()
            self:SaveWindowPosition()
        end)
        
        -- Also save position when the frame is manually moved (backup method)
        -- Use a simple timer-based position check
        if not self.positionCheckTimer then
            self.positionCheckTimer = self:ScheduleRepeatingTimer(function()
                if self.mainFrame and self.mainFrame.frame then
                    local currentPoint, _, currentRelativePoint, currentXOfs, currentYOfs = self.mainFrame.frame:GetPoint()
                    local savedPos = self.db.profile.ui.position
                    
                    -- Check if position has changed significantly (more than 5 pixels)
                    if currentPoint and savedPos.point and (
                        currentPoint ~= savedPos.point or 
                        currentRelativePoint ~= savedPos.relativePoint or
                        math.abs((currentXOfs or 0) - (savedPos.xOfs or 0)) > 5 or
                        math.abs((currentYOfs or 0) - (savedPos.yOfs or 0)) > 5
                    ) then
                        self:SaveWindowPosition()
                    end
                else
                    -- Stop timer if frame doesn't exist
                    if self.positionCheckTimer then
                        self:CancelTimer(self.positionCheckTimer)
                        self.positionCheckTimer = nil
                    end
                end
            end, 1) -- Check every 1 second
        end
    end
end

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
    self.mainFrame:SetHeight(800) -- Increased from 600 to 800 for more scroll space
    
    -- Add drag functionality to frame borders
    local frame = self.mainFrame.frame
    if frame then
        frame:SetMovable(true)
        
        -- Create invisible drag regions on the borders
        local borderWidth = 8
        
        -- Left border
        local leftBorder = CreateFrame("Frame", nil, frame)
        leftBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        leftBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        leftBorder:SetWidth(borderWidth)
        leftBorder:EnableMouse(true)
        leftBorder:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                frame:StartMoving()
            end
        end)
        leftBorder:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                frame:StopMovingOrSizing()
            end
        end)
        
        -- Right border
        local rightBorder = CreateFrame("Frame", nil, frame)
        rightBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        rightBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        rightBorder:SetWidth(borderWidth)
        rightBorder:EnableMouse(true)
        rightBorder:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                frame:StartMoving()
            end
        end)
        rightBorder:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                frame:StopMovingOrSizing()
            end
        end)
        
        -- Bottom border
        local bottomBorder = CreateFrame("Frame", nil, frame)
        bottomBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        bottomBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        bottomBorder:SetHeight(borderWidth)
        bottomBorder:EnableMouse(true)
        bottomBorder:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                frame:StartMoving()
            end
        end)
        bottomBorder:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                frame:StopMovingOrSizing()
            end
        end)
    end
    
    -- Restore position IMMEDIATELY after frame creation to avoid snapping
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: About to restore window position...")
    end
    self:RestoreWindowPosition()
    self:SetupPositionSaving()
    
    self.mainFrame:SetCallback("OnClose", function(widget)
        -- Save position before closing
        self:SaveWindowPosition()
        
        -- Clean up position check timer
        if self.positionCheckTimer then
            self:CancelTimer(self.positionCheckTimer)
            self.positionCheckTimer = nil
        end
        
        AceGUI:Release(widget)
        self.mainFrame = nil
    end)
    
    -- Create all the UI content first
    self:CreateMainWindowContent()
end

function Grouper:CreateMainWindowContent()
    if not self.mainFrame then
        return
    end
    
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
    minLevelSlider:SetWidth(120) -- Reduced from 150
    minLevelSlider:SetCallback("OnValueChanged", function(widget, event, value)
        self.db.profile.filters.minLevel = value
        self:RefreshGroupList()
    end)
    filterGroup:AddChild(minLevelSlider)
    
    local maxLevelSlider = AceGUI:Create("Slider")
    maxLevelSlider:SetLabel("Max Level")
    maxLevelSlider:SetSliderValues(1, 60, 1)
    maxLevelSlider:SetValue(self.db.profile.filters.maxLevel)
    maxLevelSlider:SetWidth(120) -- Reduced from 150
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
        {key = "pvp", label = "PvP"},
        {key = "other", label = "Other"}
    }
    
    for _, typeInfo in ipairs(groupTypes) do
        local checkbox = AceGUI:Create("CheckBox")
        checkbox:SetLabel(typeInfo.label)
        checkbox:SetValue(self.db.profile.filters.dungeonTypes[typeInfo.key])
        checkbox:SetWidth(85) -- Reduced from 100 to make more compact
        checkbox:SetCallback("OnValueChanged", function(widget, event, value)
            self.db.profile.filters.dungeonTypes[typeInfo.key] = value
            self:RefreshGroupList()
        end)
        typeGroup:AddChild(checkbox)
    end
    
    -- Dungeon filter dropdown
    local dungeonFilter = AceGUI:Create("Dropdown")
    dungeonFilter:SetLabel("Filter by Dungeon")
    dungeonFilter:SetWidth(180) -- Reduced from 200
    
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
    refreshButton:SetWidth(80)
    refreshButton:SetCallback("OnClick", function()
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Refresh button clicked - requesting fresh data from other players")
        end
        self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})

        -- Track pending responses for each group
        if not self.pendingGroupResponses then self.pendingGroupResponses = {} end
        local now = time()
        for groupId, group in pairs(self.groups or {}) do
            local leader = group.leader
            self.pendingGroupResponses[leader] = now
            -- Schedule removal if no response
            self:ScheduleTimer(function()
                if self.pendingGroupResponses[leader] == now then
                    if self.db.profile.debug.enabled then
                        self:Print("DEBUG: No response from " .. leader .. " after 10s, removing group.")
                    end
                    self:RemoveGroupByLeader(leader)
                    self.pendingGroupResponses[leader] = nil
                end
            end, 10)
        end
        -- Also schedule a delayed refresh
        self:ScheduleTimer(function()
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Delayed refresh after REQUEST_DATA timeout")
            end
            self:RefreshGroupList()
        end, 15)
    end)
    filterGroup:AddChild(refreshButton)
-- Remove group by leader name
function Grouper:RemoveGroupByLeader(leader)
    if not self.groups then return end
    local toRemove = {}
    for groupId, group in pairs(self.groups) do
        if group.leader == leader then
            table.insert(toRemove, groupId)
        end
    end
    for _, groupId in ipairs(toRemove) do
        self.groups[groupId] = nil
    end
    self:RefreshGroupList()
end
-- When a response is received from a party leader, clear pending removal
function Grouper:OnGroupLeaderResponse(leader)
    if self.pendingGroupResponses then
        self.pendingGroupResponses[leader] = nil
    end
end
    
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
    dungeonGroup:SetTitle("Select Dungeons/Raids/Battlegrounds")
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
        
        -- Only show dungeon/battleground list if dungeon, raid, or pvp is selected
        if selectedType ~= "dungeon" and selectedType ~= "raid" and selectedType ~= "pvp" then
            return
        end
        
        for i, dungeon in ipairs(DUNGEONS) do
            -- Show dungeons/raids/battlegrounds that match the selected type
            if selectedType == "other" or dungeon.type == selectedType then
                local checkbox = AceGUI:Create("CheckBox")
                checkbox:SetLabel(string.format("%s (%d-%d)", dungeon.name, dungeon.minLevel, dungeon.maxLevel))
                checkbox:SetWidth(300)
                
                -- Store bracket group for this battleground
                local bracketGroup = nil
                local bracketCheckboxes = {}
                
                checkbox:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        selectedDungeons[dungeon.name] = dungeon
                        
                        -- If this is a battleground with brackets, show bracket selection
                        if dungeon.type == "pvp" and dungeon.brackets then
                            -- Create bracket selection group
                            bracketGroup = AceGUI:Create("InlineGroup")
                            bracketGroup:SetTitle(dungeon.name .. " Level Brackets")
                            bracketGroup:SetFullWidth(true)
                            bracketGroup:SetLayout("Flow")
                            dungeonGroup:AddChild(bracketGroup)
                            
                            -- Add bracket checkboxes
                            for _, bracket in ipairs(dungeon.brackets) do
                                local bracketCheckbox = AceGUI:Create("CheckBox")
                                bracketCheckbox:SetLabel(bracket.name)
                                bracketCheckbox:SetWidth(80)
                                bracketCheckbox:SetCallback("OnValueChanged", function(bracketWidget, bracketEvent, bracketValue)
                                    if bracketValue then
                                        -- Update level range to this bracket's range
                                        minLevelEdit:SetText(tostring(bracket.minLevel))
                                        maxLevelEdit:SetText(tostring(bracket.maxLevel))
                                        
                                        -- Uncheck other brackets for this battleground
                                        for otherBracket, otherCheckbox in pairs(bracketCheckboxes) do
                                            if otherCheckbox ~= bracketWidget then
                                                otherCheckbox:SetValue(false)
                                            end
                                        end
                                        
                                        -- Store selected bracket info
                                        selectedDungeons[dungeon.name] = {
                                            name = dungeon.name,
                                            type = dungeon.type,
                                            bracket = bracket,
                                            minLevel = bracket.minLevel,
                                            maxLevel = bracket.maxLevel
                                        }
                                    else
                                        -- If unchecking, revert to general battleground selection
                                        selectedDungeons[dungeon.name] = dungeon
                                        minLevelEdit:SetText(tostring(dungeon.minLevel))
                                        maxLevelEdit:SetText(tostring(dungeon.maxLevel))
                                    end
                                end)
                                bracketGroup:AddChild(bracketCheckbox)
                                bracketCheckboxes[bracket.name] = bracketCheckbox
                            end
                        else
                            -- For non-battlegrounds, just update level range normally
                            minLevelEdit:SetText(tostring(dungeon.minLevel))
                            maxLevelEdit:SetText(tostring(dungeon.maxLevel))
                        end
                    else
                        selectedDungeons[dungeon.name] = nil
                        
                        -- Remove bracket selection if it exists
                        if bracketGroup then
                            dungeonGroup:ReleaseChildren()
                            bracketGroup = nil
                            bracketCheckboxes = {}
                            -- Rebuild the main checkbox list
                            updateDungeonList()
                            return
                        end
                        
                        -- Reset level range if no dungeons selected
                        local anySelected = false
                        for name, selected in pairs(selectedDungeons) do
                            if selected then
                                anySelected = true
                                break
                            end
                        end
                        if not anySelected then
                            if selectedType == "dungeon" then
                                minLevelEdit:SetText("15")
                                maxLevelEdit:SetText("25")
                            elseif selectedType == "raid" then
                                minLevelEdit:SetText("60")
                                maxLevelEdit:SetText("60")
                            elseif selectedType == "pvp" then
                                minLevelEdit:SetText("10")
                                maxLevelEdit:SetText("60")
                            end
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
        elseif value == "pvp" then
            minLevelEdit:SetText("10")
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
        if group.leader == GetFullPlayerName(UnitName("player")) then
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
    
    -- Party member fields
    local membersGroup = AceGUI:Create("InlineGroup")
    membersGroup:SetTitle("Party Members")
    membersGroup:SetFullWidth(true)
    membersGroup:SetLayout("Flow")
    -- WoW class colors
    local CLASS_COLORS = {
        WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473", ROGUE = "FFF569", PRIEST = "FFFFFF",
        DEATHKNIGHT = "C41F3B", SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9", DRUID = "FF7D0A",
        MONK = "00FF96", DEMONHUNTER = "A330C9", EVOKER = "33937F"
    }
    -- Always use Grouper.players cache for party member info
    local partyMembers = {}
    local selfName = UnitName("player")
    if selfName and type(selfName) == "string" and selfName ~= "" then table.insert(partyMembers, selfName) end

    -- Use Grouper.players cache for member info
    for i = 1, 5 do
        local label = AceGUI:Create("Label")
        label:SetWidth(250)
        local memberName = partyMembers[i]
        local info = memberName and Grouper.players[memberName]
        if info then
            local color = CLASS_COLORS[string.upper(info.class or "PRIEST")] or "FFFFFF"
            label:SetText(string.format("|cff%s%s|r | %s | %d", color, info.name or memberName, info.class or "?", info.level or 0))
        elseif memberName then
            label:SetText(string.format("%s (no cache)", memberName))
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: No cache for party member '%s' in Grouper.players", memberName))
            end
        else
            label:SetText("(empty)")
        end
        membersGroup:AddChild(label)
    end
    frame:AddChild(membersGroup)

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
    self:Print(string.rep("-", 40))
    self:Print("DEBUG: [RefreshGroupList] called")
    if not self.groupsScrollFrame then
        self:Print("DEBUG: [RefreshGroupList] groupsScrollFrame is nil")
        return
    end
    self:Print("DEBUG: 🔄 Groups in memory:")
    for id, group in pairs(self.groups) do
        self:Print(string.format("DEBUG:   - %s: %s (leader: %s)", id, group.title, group.leader))
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
        local groupFrame = self:CreateGroupManageFrame(group)
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
        -- Classic Era compatible whisper initiation
        local whisperText = "/tell " .. group.leader .. " "
        
        -- Try multiple methods to activate chat with the whisper command
        local success = false
        
        -- Method 1: Try ChatFrame_OpenChat (most reliable for Classic Era)
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat(whisperText)
            success = true
        -- Method 2: Try DEFAULT_CHAT_FRAME editBox
        elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
            local editBox = DEFAULT_CHAT_FRAME.editBox
            if editBox then
                editBox:SetText(whisperText)
                editBox:Show()
                editBox:SetFocus()
                success = true
            end
        -- Method 3: Try ChatEdit_ActivateChat with current active window
        elseif ChatEdit_GetActiveWindow then
            local editBox = ChatEdit_GetActiveWindow()
            if editBox then
                editBox:SetText(whisperText)
                ChatEdit_ActivateChat(editBox)
                success = true
            end
        end
        
        -- Debug feedback
        if self.db.profile.debug.enabled then
            if success then
                self:Print(string.format("DEBUG: ✓ Opened whisper to %s", group.leader))
            else
                self:Print(string.format("DEBUG: ✗ Failed to open whisper to %s", group.leader))
            end
        end
    end)
    buttonGroup:AddChild(whisperButton)
    
    local inviteButton = AceGUI:Create("Button")
    
    -- Always use Auto-Join button
    inviteButton:SetText("Auto-Join")
    inviteButton:SetWidth(120)
    inviteButton:SetCallback("OnClick", function()
        self:Print("DEBUG: Auto-Join button clicked!")
        self:Print(string.format("DEBUG: Group leader: %s", group.leader))
        local success, errorMessage = pcall(function()
            local playerName = UnitName("player")
            local message = {
                type = "INVITE_REQUEST",
                requester = playerName,
                timestamp = time(),
                playerInfo = self.playerInfo -- Include cached local player data
            }
            self:Print("DEBUG: Sending invite request via AceComm to " .. group.leader)
            self:SendCommMessage("GrouperAutoJoin", self:Serialize(message), "WHISPER", group.leader)
            self:Print("DEBUG: AceComm invite request sent")
        end)
        if success then
            self:Print(string.format("✓ Sent invite request to %s via AceComm", group.leader))
        else
            self:Print(string.format("✗ Failed to send invite request: %s", errorMessage or "Unknown error"))
            -- Fallback: try with realm-stripped name
            local strippedName = self:StripRealmName(group.leader)
            if strippedName ~= group.leader then
                self:Print(string.format("DEBUG: Trying with stripped name: %s", strippedName))
                local success2, errorMessage2 = pcall(function()
                    local playerName = UnitName("player")
                    local message = {
                        type = "INVITE_REQUEST",
                        requester = playerName,
                        timestamp = time(),
                        playerInfo = self.playerInfo -- Include cached local player data
                    }
                    self:SendCommMessage("GrouperAutoJoin", self:Serialize(message), "WHISPER", strippedName)
                end)
                if success2 then
                    self:Print(string.format("✓ Sent invite request to %s via AceComm (stripped)", strippedName))
                else
                    self:Print(string.format("✗ Also failed with stripped name: %s", errorMessage2 or "Unknown error"))
                    -- Final fallback: traditional whisper
                    SendChatMessage("Hi! I'd like to join your group (sent via Grouper Auto-Join)", "WHISPER", nil, group.leader)
                    self:Print("DEBUG: Used traditional whisper as final fallback")
                end
            end
        end
    end)
    
    buttonGroup:AddChild(inviteButton)
    
    return frame
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
