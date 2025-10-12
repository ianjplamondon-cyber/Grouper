-- Create the Create Group tab
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
    if titleEdit.DisableButton then titleEdit:DisableButton(true) end
    scrollFrame:AddChild(titleEdit)
    
    -- Event type dropdown (encoded as numbers when sent)
    local typeDropdown = AceGUI:Create("Dropdown")
    typeDropdown:SetLabel("Event Type")
    typeDropdown:SetList({
        dungeon = "Dungeon",
        --raid = "Raid",
        quest = "Quest",
        --pvp = "PvP",
        other = "Other"
    })
    typeDropdown:SetValue("dungeon") -- Default to dungeon
    typeDropdown:SetFullWidth(true)
    scrollFrame:AddChild(typeDropdown)
    --[[
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
    --]]
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
                            --minLevelEdit:SetText(tostring(dungeon.minLevel))
                            --maxLevelEdit:SetText(tostring(dungeon.maxLevel))
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
    
    --[[
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
    ]]
    -- Initialize dungeon list
    updateDungeonList()
    --[[
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
    --]]
    -- Location
    local locationEdit = AceGUI:Create("EditBox")
    locationEdit:SetLabel("Location/Meeting Point (max 20 chars)")
    locationEdit:SetFullWidth(true)
    locationEdit:SetMaxLetters(20)
    locationEdit:SetText("")
    if locationEdit.DisableButton then locationEdit:DisableButton(true) end
    scrollFrame:AddChild(locationEdit)
    
    -- My role dropdown
    local roleDropdown = AceGUI:Create("Dropdown")
    roleDropdown:SetLabel("My Role")
    roleDropdown:SetList({
        tank = "Tank",
        healer = "Healer",
        dps = "DPS"
    })
    -- Restore last selected role from SV if available
    local lastRole = self.db and self.db.profile and self.db.profile.lastRole
    if lastRole and (lastRole == "tank" or lastRole == "healer" or lastRole == "dps") then
        roleDropdown:SetValue(lastRole)
    else
        roleDropdown:SetValue("dps")
    end
    roleDropdown:SetFullWidth(true)
    scrollFrame:AddChild(roleDropdown)
    -- Save role to SV on change
    roleDropdown:SetCallback("OnValueChanged", function(widget, event, value)
        if self.db and self.db.profile then
            self.db.profile.lastRole = value
        end
    end)
    
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

        -- Determine min/max level from selected dungeons
        local minLevel, maxLevel
        for _, dungeon in pairs(selectedDungeons) do
            local dMin = dungeon.minLevel
            local dMax = dungeon.maxLevel
            -- If battleground bracket is selected, use bracket min/max
            if dungeon.bracket then
                dMin = dungeon.bracket.minLevel
                dMax = dungeon.bracket.maxLevel
            end
            if not minLevel or dMin < minLevel then minLevel = dMin end
            if not maxLevel or dMax > maxLevel then maxLevel = dMax end
        end

        local groupData = {
            title = titleEdit:GetText(),
            description = "", -- No longer used
            type = selectedType or "dungeon",
            typeId = typeId,
            minLevel = minLevel,
            maxLevel = maxLevel,
            location = locationEdit:GetText(),
            myRole = roleDropdown:GetValue(),
            dungeons = selectedDungeons
        }
        -- Persist last selected role in SV if available
        if self.db and self.db.profile then
            self.db.profile.lastRole = roleDropdown:GetValue()
        end

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
