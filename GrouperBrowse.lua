-- Create the Search Filters tabself:RefreshGroupList()
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
        self:RefreshGroupListResults()
    end)
    -- Add tooltip to min level slider label
    if minLevelSlider.label then
        minLevelSlider.label:EnableMouse(true)
        minLevelSlider.label:SetScript("OnEnter", function()
            GameTooltip:SetOwner(minLevelSlider.label, "ANCHOR_RIGHT")
            GameTooltip:SetText("Set the minimum player level for group search results.", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        minLevelSlider.label:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    filterGroup:AddChild(minLevelSlider)
    
    local maxLevelSlider = AceGUI:Create("Slider")
    maxLevelSlider:SetLabel("Max Level")
    maxLevelSlider:SetSliderValues(1, 60, 1)
    maxLevelSlider:SetValue(self.db.profile.filters.maxLevel)
    maxLevelSlider:SetWidth(120) -- Reduced from 150
    maxLevelSlider:SetCallback("OnValueChanged", function(widget, event, value)
        self.db.profile.filters.maxLevel = value
        self:RefreshGroupListResults()
    end)
    -- Add tooltip to max level slider label
    if maxLevelSlider.label then
        maxLevelSlider.label:EnableMouse(true)
        maxLevelSlider.label:SetScript("OnEnter", function()
            GameTooltip:SetOwner(maxLevelSlider.label, "ANCHOR_RIGHT")
            GameTooltip:SetText("Set the maximum player level for group search results.", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        maxLevelSlider.label:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
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
        if typeInfo.key == "raid" or typeInfo.key == "pvp" then
            checkbox:SetDisabled(true)
        end
        -- Add tooltips for Dungeon, Quest, and Other
        if typeInfo.key == "dungeon" then
            checkbox.frame:EnableMouse(true)
            checkbox.frame:SetScript("OnEnter", function()
                GameTooltip:SetOwner(checkbox.frame, "ANCHOR_RIGHT")
                GameTooltip:SetText("Show dungeon groups.", 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkbox.frame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        elseif typeInfo.key == "quest" then
            checkbox.frame:EnableMouse(true)
            checkbox.frame:SetScript("OnEnter", function()
                GameTooltip:SetOwner(checkbox.frame, "ANCHOR_RIGHT")
                GameTooltip:SetText("Show quest groups.", 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkbox.frame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        elseif typeInfo.key == "other" then
            checkbox.frame:EnableMouse(true)
            checkbox.frame:SetScript("OnEnter", function()
                GameTooltip:SetOwner(checkbox.frame, "ANCHOR_RIGHT")
                GameTooltip:SetText("Show other (miscellaneous) groups.", 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkbox.frame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        checkbox:SetCallback("OnValueChanged", function(widget, event, value)
            self.db.profile.filters.dungeonTypes[typeInfo.key] = value
            self:RefreshGroupListResults()
        end)
        typeGroup:AddChild(checkbox)
    end
    
    -- Role filter dropdown
    local roleFilterDropdown = AceGUI:Create("Dropdown")
    roleFilterDropdown:SetLabel("Filter by Role")
    if roleFilterDropdown.label then
        if roleFilterDropdown.label.SetJustifyH then
            roleFilterDropdown.label:SetJustifyH("CENTER")
        elseif roleFilterDropdown.label.SetTextAlign then
            roleFilterDropdown.label:SetTextAlign("CENTER")
        end
    end
    roleFilterDropdown:SetList({
        any = "Any",
        tank = "Tank",
        healer = "Healer",
        dps = "DPS"
    })
    roleFilterDropdown:SetValue(self.db.profile.filters.role or "any")
    roleFilterDropdown:SetWidth(120)
    roleFilterDropdown:SetCallback("OnValueChanged", function(widget, event, value)
        self.db.profile.filters.role = value
        self:RefreshGroupListResults()
    end)
    -- Add tooltip for role filter dropdown
    roleFilterDropdown.frame:EnableMouse(true)
    roleFilterDropdown.frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(roleFilterDropdown.frame, "ANCHOR_RIGHT")
        GameTooltip:SetText("Filter results to only show groups seeking this role.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    roleFilterDropdown.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    filterGroup:AddChild(roleFilterDropdown)
    -- Dungeon filter dropdown
    local dungeonFilter = AceGUI:Create("Dropdown")
    dungeonFilter:SetLabel("Filter by Dungeon")
    if dungeonFilter.label then
        if dungeonFilter.label.SetJustifyH then
            dungeonFilter.label:SetJustifyH("CENTER")
        elseif dungeonFilter.label.SetTextAlign then
            dungeonFilter.label:SetTextAlign("CENTER")
        end
    end
    dungeonFilter:SetWidth(180) -- Reduced from 200
    
    -- Build dungeon list for dropdown
    local dungeonList = {[""] = "All Dungeons"}
    for _, dungeon in ipairs(DUNGEONS) do
        if dungeon.id and dungeon.id >= 1 and dungeon.id <= 26 then
            dungeonList[dungeon.name] = dungeon.name
        end
    end
    dungeonFilter:SetList(dungeonList)
    dungeonFilter:SetValue("")
    dungeonFilter:SetCallback("OnValueChanged", function(widget, event, value)
        self.selectedDungeonFilter = value
        self:RefreshGroupListResults()
    end)
    -- Add tooltip for dungeon filter dropdown
    dungeonFilter.frame:EnableMouse(true)
    dungeonFilter.frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(dungeonFilter.frame, "ANCHOR_RIGHT")
        GameTooltip:SetText("Filter results to only show groups for a specific dungeon.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    dungeonFilter.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    filterGroup:AddChild(dungeonFilter)
    
    -- Refresh button
    local refreshButton = AceGUI:Create("Button")
    refreshButton:SetText("Search")
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
            --[[
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
            --]]
        end
        
        --[[
        -- Also schedule a delayed refresh
        self:ScheduleTimer(function()
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: Delayed refresh after REQUEST_DATA timeout")
            end
            self:RefreshGroupListResults()
        end, 15)
        --]]
    end)
    -- Add tooltip to Search button
    refreshButton.frame:EnableMouse(true)
    refreshButton.frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(refreshButton.frame, "ANCHOR_RIGHT")
        GameTooltip:SetText("Request updated group listings from other players.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refreshButton.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    filterGroup:AddChild(refreshButton)
    --[[
    -- Groups list
    local groupsScrollFrame = AceGUI:Create("ScrollFrame")
    groupsScrollFrame:SetFullWidth(true)
    groupsScrollFrame:SetFullHeight(true)
    groupsScrollFrame:SetLayout("List")
    container:AddChild(groupsScrollFrame)

    self.groupsScrollFrame = groupsScrollFrame
    self:RefreshGroupListResults()
    ]]
end
