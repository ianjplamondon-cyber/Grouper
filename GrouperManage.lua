-- Create the My Groups tab
function Grouper:CreateManageTab(container)
    local ManageScrollFrame = AceGUI:Create("ScrollFrame")
    ManageScrollFrame:SetFullWidth(true)
    ManageScrollFrame:SetFullHeight(true)
    -- AceGUI widget pool bug workaround: clear any fixed height
    if ManageScrollFrame.frame and ManageScrollFrame.frame.SetHeight then
        ManageScrollFrame.frame:SetHeight(0)
    end
    ManageScrollFrame:SetLayout("List")
    container:AddChild(ManageScrollFrame)
        
    local myGroups = {}
    local localPlayer = Grouper.GetFullPlayerName(UnitName("player"))
    local normLocalPlayer = Grouper.NormalizeFullPlayerName(localPlayer)
    for _, group in pairs(self.groups) do
        if group.members and type(group.members) == "table" then
            for _, member in ipairs(group.members) do
                local normMember = Grouper.NormalizeFullPlayerName(member.name)
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print("DEBUG: [CreateManageTab] Comparing member '" .. tostring(normMember) .. "' to local '" .. tostring(normLocalPlayer) .. "' for group " .. tostring(group.id))
                end
                if Grouper.NormalizeFullPlayerName(member.name) == normLocalPlayer then
                    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                        self:Print("DEBUG: [CreateManageTab] Matched! Adding group " .. tostring(group.id))
                    end
                    table.insert(myGroups, group)
                    break
                end
            end
        end
    end

    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [CreateManageTab] myGroups count after filtering: " .. tostring(#myGroups))
        for i, group in ipairs(myGroups) do
            self:Print("DEBUG: [CreateManageTab] myGroups[" .. i .. "]: " .. tostring(group.id) .. " - " .. tostring(group.title))
        end
    end
    
    if #myGroups == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("You haven't created any groups yet. Use the 'Create Group' tab to make one!")
        label:SetFullWidth(true)
        ManageScrollFrame:AddChild(label)
    else
        for _, group in ipairs(myGroups) do
            local groupFrame = self:CreateGroupManageFrame(group, "manage")
            ManageScrollFrame:AddChild(groupFrame)
        end
    end

    self.ManageScrollFrame = ManageScrollFrame
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [CreateManageTab] ManageScrollFrame set: " .. tostring(self.ManageScrollFrame) .. "\n" .. debugstack(2, 10, 10))
    end
    self:RefreshGroupListManage()

end

-- Create the party frames in my manage tab
function Grouper:CreateGroupManageFrame(group, tabType)
    local frame = AceGUI:Create("InlineGroup")
    frame:SetTitle(group.title)
    frame:SetFullWidth(true)
    frame:SetLayout("Flow")
    
    -- Group info
    local infoLabel = AceGUI:Create("Label")
    -- Show all selected dungeons (comma-separated), or blank if not a dungeon
    local dungeonNames = {}
    if group.dungeons and next(group.dungeons) then
        for name, _ in pairs(group.dungeons) do
            table.insert(dungeonNames, name)
        end
    elseif group.dungeonId and DUNGEONS then
        for _, d in ipairs(DUNGEONS) do
            if d.id == group.dungeonId then table.insert(dungeonNames, d.name) break end
        end
    end
    local dungeonsText = #dungeonNames > 0 and table.concat(dungeonNames, ", ") or "-"
    infoLabel:SetText(string.format("Type: %s | Dungeons: %s | Level: %d-%d\nMeeting Point: %s",
        group.type, dungeonsText, group.minLevel, group.maxLevel,
        group.location ~= "" and group.location or "Not specified"))
    infoLabel:SetFullWidth(true)
    frame:AddChild(infoLabel)
    
    -- Party member fields
    local membersGroup = AceGUI:Create("InlineGroup")
    membersGroup:SetTitle("Party Members")
    membersGroup:SetFullWidth(true)
    membersGroup:SetLayout("List")
    -- WoW class colors
    local CLASS_COLORS = {
        WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473", ROGUE = "FFF569", PRIEST = "FFFFFF",
        DEATHKNIGHT = "C41F3B", SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9", DRUID = "FF7D0A",
        MONK = "00FF96", DEMONHUNTER = "A330C9", EVOKER = "33937F"
    }
    local CLASS_NAMES = { [1]="WARRIOR", [2]="PALADIN", [3]="HUNTER", [4]="ROGUE", [5]="PRIEST", [6]="DEATHKNIGHT", [7]="SHAMAN", [8]="MAGE", [9]="WARLOCK", [10]="DRUID", [11]="MONK", [12]="DEMONHUNTER", [13]="EVOKER" }
    local RACE_NAMES = { [1]="Human", [2]="Orc", [3]="Dwarf", [4]="NightElf", [5]="Undead", [6]="Tauren", [7]="Gnome", [8]="Troll", [9]="Goblin", [10]="BloodElf", [11]="Draenei", [12]="Worgen", [13]="Pandaren" }
    if group.type == "dungeon" then
        -- Simple role-based slotting: tank (1), healer (2), dps (3-5), fill in order, show '?' for unknown roles
        local function CamelCaseClass(class)
            if not class or class == "?" then return class end
            return class:sub(1,1):upper() .. class:sub(2):lower()
        end
        local tanks, healers, dps, others = {}, {}, {}, {}
        if group.members and #group.members > 0 then
            for _, member in ipairs(group.members) do
                local role = member.role and string.lower(member.role) or "?"
                if role == "tank" then
                    table.insert(tanks, member)
                elseif role == "healer" then
                    table.insert(healers, member)
                elseif role == "dps" then
                    table.insert(dps, member)
                else
                    table.insert(others, member)
                end
            end
        end
        local sortedMembers = {}
        sortedMembers[1] = tanks[1]
        sortedMembers[2] = healers[1]
        sortedMembers[3] = dps[1]
        sortedMembers[4] = dps[2]
        sortedMembers[5] = dps[3]
        local maxSpots = 5
        for i = 1, maxSpots do
            local label = AceGUI:Create("Label")
            label:SetWidth(500)
            local member = sortedMembers[i]
            if member then
                local className = member.class or (member.classId and CLASS_NAMES[member.classId]) or "PRIEST"
                className = CamelCaseClass(className)
                local raceName = member.race or (member.raceId and RACE_NAMES[member.raceId]) or "Human"
                local color = CLASS_COLORS[string.upper(className)] or "FFFFFF"
                local roleText = member.role or "?"
                label:SetText(string.format("|cff%s%s|r | %s | %s | %s | %d", color, member.name or "?", className, roleText, raceName, member.level or 0))
            else
                label:SetText("- Empty Slot -")
            end
            membersGroup:AddChild(label)
        end
    else
        -- Original logic for non-dungeon types
        local function CamelCaseClass(class)
            if not class or class == "?" then return class end
            return class:sub(1,1):upper() .. class:sub(2):lower()
        end
        if group.members and #group.members > 0 then
            for _, member in ipairs(group.members) do
                local label = AceGUI:Create("Label")
                label:SetWidth(250)
                local className = member.class or (member.classId and CLASS_NAMES[member.classId]) or "PRIEST"
                className = CamelCaseClass(className)
                local raceName = member.race or (member.raceId and RACE_NAMES[member.raceId]) or "Human"
                local color = CLASS_COLORS[string.upper(className)] or "FFFFFF"
                local roleText = member.role or "?"
                label:SetText(string.format("|cff%s%s|r | %s | %s | %s | %d", color, member.name or "?", className, roleText, raceName, member.level or 0))
                membersGroup:AddChild(label)
            end
        else
            local label = AceGUI:Create("Label")
            label:SetWidth(250)
            label:SetText("No members found.")
            membersGroup:AddChild(label)
        end
    end
    frame:AddChild(membersGroup)

    -- Buttons
    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetLayout("Flow")
    buttonGroup:SetFullWidth(true)
    frame:AddChild(buttonGroup)

    if tabType == "manage" then
        local playerName = UnitName("player")
        local fullPlayerName = Grouper.GetFullPlayerName(playerName)
        if group.leader == fullPlayerName then
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
                -- Find the group key by matching group.id to the key in self.groups
                local groupKey = nil
                for k, v in pairs(self.groups) do
                    if k == group.id then
                        groupKey = k
                        break
                    end
                end
                if groupKey then
                    self:RemoveGroup(groupKey)
                else
                    self:Print("Error: Could not find group key for removal.")
                end
                if self.tabGroup then
                    self.tabGroup:SelectTab("manage")
                end
            end)
            buttonGroup:AddChild(removeButton)

            local syncButton = AceGUI:Create("Button")
            syncButton:SetText("Sync")
            syncButton:SetWidth(100)
            syncButton:SetCallback("OnClick", function()
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print("DEBUG: Sync button clicked! Broadcasting group update...")
                end
                Grouper:SendGroupUpdateViaChannel(group)
            end)
            buttonGroup:AddChild(syncButton)
        end
    end

    return frame
end

-- Edit group in manage tab
function Grouper:ShowEditGroupDialog(group)
    -- Create a simple edit dialog using AceGUI
    local AceGUI = LibStub("AceGUI-3.0")
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Edit Group")
    frame:SetWidth(400)
    frame:SetHeight(400)
    frame:SetLayout("List")

    -- Type
    local typeDropdown = AceGUI:Create("Dropdown")
    typeDropdown:SetLabel("Type")
    typeDropdown:SetList({ dungeon = "Dungeon", quest = "Quest", other = "Other" })
    typeDropdown:SetValue(group.type or "other")
    typeDropdown:SetFullWidth(true)
    frame:AddChild(typeDropdown)

    -- Dungeon selection (multi-select, only if type is dungeon)
    local selectedDungeons = {}
    if group.dungeons then
        for name, dungeon in pairs(group.dungeons) do
            selectedDungeons[name] = dungeon
        end
    end
    local dungeonGroup = AceGUI:Create("InlineGroup")
    dungeonGroup:SetTitle("Select Dungeon(s)")
    dungeonGroup:SetFullWidth(true)
    dungeonGroup:SetLayout("Fill")
    frame:AddChild(dungeonGroup)

    local editDungeonScroll = AceGUI:Create("ScrollFrame")
    editDungeonScroll:SetLayout("List")
    editDungeonScroll:SetFullWidth(true)
    editDungeonScroll:SetFullHeight(true)
    dungeonGroup:AddChild(editDungeonScroll)

    local function updateDungeonCheckboxes()
        editDungeonScroll:ReleaseChildren()
        if typeDropdown:GetValue() ~= "dungeon" then return end
        if not DUNGEONS then return end
        for _, dungeon in ipairs(DUNGEONS) do
            if dungeon.id and dungeon.id >= 1 and dungeon.id <= 26 then
                local checkbox = AceGUI:Create("CheckBox")
                checkbox:SetLabel(dungeon.name)
                checkbox:SetWidth(300)
                checkbox:SetValue(selectedDungeons[dungeon.name] ~= nil)
                checkbox:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        selectedDungeons[dungeon.name] = dungeon
                    else
                        selectedDungeons[dungeon.name] = nil
                    end
                end)
                editDungeonScroll:AddChild(checkbox)
            end
        end
    end
    typeDropdown:SetCallback("OnValueChanged", function()
        updateDungeonCheckboxes()
    end)
    updateDungeonCheckboxes()

    -- Title
    local titleEdit = AceGUI:Create("EditBox")
    titleEdit:SetLabel("Title")
    titleEdit:SetText(group.title or "")
    titleEdit:SetFullWidth(true)
    frame:AddChild(titleEdit)

    -- Location
    local locationEdit = AceGUI:Create("EditBox")
    locationEdit:SetLabel("Meeting Point")
    locationEdit:SetText(group.location or "")
    locationEdit:SetFullWidth(true)
    frame:AddChild(locationEdit)

    -- Save button
    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save Changes")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        group.title = titleEdit:GetText()
        group.type = typeDropdown:GetValue()
        group.location = locationEdit:GetText()
        if typeDropdown:GetValue() == "dungeon" then
            group.dungeons = next(selectedDungeons) and selectedDungeons or nil
            -- Recalculate minLevel and maxLevel from selected dungeons
            local minLevel, maxLevel
            for _, dungeon in pairs(selectedDungeons) do
                local dMin = dungeon.minLevel
                local dMax = dungeon.maxLevel
                if dungeon.bracket then
                    dMin = dungeon.bracket.minLevel
                    dMax = dungeon.bracket.maxLevel
                end
                if not minLevel or dMin < minLevel then minLevel = dMin end
                if not maxLevel or dMax > maxLevel then maxLevel = dMax end
            end
            group.minLevel = minLevel
            group.maxLevel = maxLevel
        else
            group.dungeons = nil
        end
        self:SendComm("GROUP_UPDATE", group)
        self:Print("Group updated!")
        frame:Release()
        if self.tabGroup then
            self.tabGroup:SelectTab("manage")
        end
    end)
    frame:AddChild(saveBtn)

    -- Cancel button
    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetFullWidth(true)
    cancelBtn:SetCallback("OnClick", function()
        frame:Release()
    end)
    frame:AddChild(cancelBtn)
end


-- Update group members when player joins a group
function Grouper:HandleJoinedGroupManage()
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: HandleJoinedGroup - preparing to broadcast updated group data.")
        self:Print("DEBUG: HandleJoinedGroup stack trace:")
        self:Print(debugstack(2, 10, 10))
        self:Print("DEBUG: Player joined a group - updating members list")
    end

    -- Update the members field of all relevant groups (not just those led by the player)
    local updated = false
    for groupId, group in pairs(self.groups) do
        group.members = {}
        local leaderFound = false
        local function CamelCaseRole(role)
            if not role or role == "None" or role == "?" then return role end
            if role:lower() == "dps" then return "DPS" end
            return role:sub(1,1):upper() .. role:sub(2):lower()
        end
        local function CamelCaseClass(class)
            if not class or class == "?" then return class end
            return class:sub(1,1):upper() .. class:sub(2):lower()
        end
        if self.players then
            local groupLeader = Grouper.NormalizeFullPlayerName(group.leader)
            for playerKey, playerInfo in pairs(self.players) do
                -- Only consider FullName keys (those containing a dash)
                if type(playerKey) == "string" and string.find(playerKey, "-") then
                    local normKey = Grouper.NormalizeFullPlayerName(playerKey)
                    if normKey ~= playerKey then
                        -- Merge and remove old key
                        for field, val in pairs(playerInfo) do
                            self.players[normKey] = self.players[normKey] or {}
                            if self.players[normKey][field] == nil then
                                self.players[normKey][field] = val
                            end
                        end
                        self.players[playerKey] = nil
                        playerInfo = self.players[normKey]
                    end
                    if playerInfo and playerInfo.groupId == groupId and playerInfo.lastSeen then
                        -- Set leader attribute
                        if normKey == groupLeader then
                            playerInfo.leader = true
                            leaderFound = true
                        else
                            playerInfo.leader = false
                        end
                        -- Ensure leader status is saved in cache
                        self.players[normKey] = self.players[normKey] or {}
                        self.players[normKey].leader = playerInfo.leader
                        table.insert(group.members, {
                            name = playerInfo.fullName,
                            class = CamelCaseClass(playerInfo.class or "?"),
                            role = CamelCaseRole(playerInfo.role or "?"),
                            race = playerInfo.race or "?",
                            level = playerInfo.level or "?",
                            leader = playerInfo.leader
                        })
                    end
                end
            end
            -- If leader not found in self.players, add them explicitly
            if not leaderFound and groupLeader then
                local normLeader = groupLeader
                local leaderInfo = self.players[normLeader]
                if not leaderInfo then
                    for k, info in pairs(self.players) do
                        if Grouper.NormalizeFullPlayerName(k) == normLeader then
                            -- Merge and remove old key
                            for field, val in pairs(info) do
                                self.players[normLeader] = self.players[normLeader] or {}
                                if self.players[normLeader][field] == nil then
                                    self.players[normLeader][field] = val
                                end
                            end
                            self.players[k] = nil
                            leaderInfo = self.players[normLeader]
                            break
                        end
                    end
                end
                local myRole = leaderInfo and leaderInfo.role or "?"
                -- Ensure leader status is saved in cache
                self.players[normLeader] = self.players[normLeader] or {}
                self.players[normLeader].leader = true
                table.insert(group.members, {
                    name = groupLeader,
                    class = CamelCaseClass(leaderInfo and leaderInfo.class or UnitClass("player") or "?"),
                    role = CamelCaseRole(myRole or "?"),
                    race = leaderInfo and leaderInfo.race or UnitRace("player") or "?",
                    level = leaderInfo and leaderInfo.level or UnitLevel("player") or "?",
                    leader = true
                })
            end
        end
        updated = true
    end
    if updated then
        self:RefreshGroupListManage()
    end
    -- If the My Groups tab is open, force a tab refresh to update the Sync button and members
    if self.tabGroup and self.tabGroup.selected == "manage" then
        self.tabGroup:SelectTab("manage")
    end
end

-- Refresh the group list display (browse or manage)
function Grouper:RefreshGroupListManage(tabType)
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.rep("-", 40))
        self:Print("DEBUG: [RefreshGroupListManage] called")
        self:Print("DEBUG: [RefreshGroupListManage] stack trace:\n" .. debugstack(2, 10, 10))
        self:Print("DEBUG: [RefreshGroupListManage] ManageScrollFrame at entry: " .. tostring(self.ManageScrollFrame) .. "\n" .. debugstack(2, 10, 10))
    end
    if not self.ManageScrollFrame then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RefreshGroupListManage] ManageScrollFrame is nil\n" .. debugstack(2, 10, 10))
        end
        return
    end
    -- Only show groups the player is a member of (myGroups logic from CreateManageTab)
    local myGroups = {}
    local localPlayer = Grouper.GetFullPlayerName(UnitName("player"))
    local normLocalPlayer = Grouper.NormalizeFullPlayerName(localPlayer)
    for _, group in pairs(self.groups) do
        if group.members and type(group.members) == "table" then
            for _, member in ipairs(group.members) do
                local normMember = Grouper.NormalizeFullPlayerName(member.name)
                if normMember == normLocalPlayer then
                    table.insert(myGroups, group)
                    break
                end
            end
        end
    end
    self.ManageScrollFrame:ReleaseChildren()
    if #myGroups == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("You haven't created any groups yet. Use the 'Create Group' tab to make one!")
        label:SetFullWidth(true)
        self.ManageScrollFrame:AddChild(label)
        return
    end
    for _, group in ipairs(myGroups) do
        local groupFrame = self:CreateGroupManageFrame(group, "manage")
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RefreshGroupListManage] about to AddChild to ManageScrollFrame: " .. tostring(self.ManageScrollFrame))
        end
        if groupFrame then
            self.ManageScrollFrame:AddChild(groupFrame)
        end
    end
end
