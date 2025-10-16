-- Create the Search Results tab
function Grouper:CreateResultsTab(container)
    local ResultsScrollFrame = AceGUI:Create("ScrollFrame")
    ResultsScrollFrame:SetFullWidth(true)
    ResultsScrollFrame:SetFullHeight(true)
    ResultsScrollFrame:SetLayout("List")
    container:AddChild(ResultsScrollFrame)

    self.ResultsScrollFrame = ResultsScrollFrame
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [CreateResultsTab] ResultsScrollFrame set: " .. tostring(self.ResultsScrollFrame) .. "\n" .. debugstack(2, 10, 10))
    end
    self:RefreshGroupListResults()
end

-- Create group frames in the results tab
function Grouper:CreateGroupFrame(group, tabType)
    local frame = AceGUI:Create("InlineGroup")
    frame:SetTitle(group.title)
    frame:SetFullWidth(true)
    frame:SetLayout("Flow")

    -- Group info
    local infoLabel = AceGUI:Create("Label")
    if group.type == "dungeon" then
        -- Show dungeons for dungeon groups
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
    else
        -- Hide dungeons column for quest/other groups
        infoLabel:SetText(string.format("Type: %s | Level: %d-%d\nMeeting Point: %s",
            group.type, group.minLevel, group.maxLevel,
            group.location ~= "" and group.location or "Not specified"))
    end
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
            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetLayout("Flow")
            rowGroup:SetFullWidth(true)
            local member = sortedMembers[i]
            if member then
                local className = member.class or (member.classId and CLASS_NAMES[member.classId]) or "PRIEST"
                className = CamelCaseClass(className)
                local raceName = member.race or (member.raceId and RACE_NAMES[member.raceId]) or "Human"
                local color = CLASS_COLORS[string.upper(className)] or "FFFFFF"
                local roleText = member.role or "?"
                local crown = ""
                if member.leader == "yes" or (Grouper.GetFullPlayerName and group.leader and Grouper.GetFullPlayerName(member.name, member.realm) == Grouper.GetFullPlayerName(group.leader)) then
                    crown = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:16:16:0:4|t "
                end
                local label = AceGUI:Create("Label")
                label:SetWidth(470)
                label:SetText(string.format("%s|cff%s%s|r | %s | %s | %s | %d", crown, color, member.name or "?", className, roleText, raceName, member.level or 0))
                rowGroup:AddChild(label)
            else
                local label = AceGUI:Create("Label")
                label:SetWidth(470)
                local slotText = "- Empty Slot -"
                if i == 1 then
                    slotText = "<Tank>"
                elseif i == 2 then
                    slotText = "<Healer>"
                elseif i >= 3 and i <= 5 then
                    slotText = "<DPS>"
                end
                label:SetText(slotText)
                rowGroup:AddChild(label)
            end
            membersGroup:AddChild(rowGroup)
        end
    else
        -- Original logic for non-dungeon types
        local function CamelCaseClass(class)
            if not class or class == "?" then return class end
            return class:sub(1,1):upper() .. class:sub(2):lower()
        end
        if group.members and #group.members > 0 then
            for _, member in ipairs(group.members) do
                local rowGroup = AceGUI:Create("SimpleGroup")
                rowGroup:SetLayout("Flow")
                rowGroup:SetFullWidth(true)
                local className = member.class or (member.classId and CLASS_NAMES[member.classId]) or "PRIEST"
                className = CamelCaseClass(className)
                local raceName = member.race or (member.raceId and RACE_NAMES[member.raceId]) or "Human"
                local color = CLASS_COLORS[string.upper(className)] or "FFFFFF"
                local roleText = member.role or "?"
                local label = AceGUI:Create("Label")
                label:SetWidth(470)
                local crown = ""
                if member.leader == "yes" or (Grouper.GetFullPlayerName and group.leader and Grouper.GetFullPlayerName(member.name, member.realm) == Grouper.GetFullPlayerName(group.leader)) then
                    crown = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:16:16:0:0|t "
                end
                label:SetText(string.format("%s|cff%s%s|r | %s | %s | %s | %d", crown, color, member.name or "?", className, roleText, raceName, member.level or 0))
                rowGroup:AddChild(label)
                membersGroup:AddChild(rowGroup)
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

    if tabType == "results" then
        local whisperButton = AceGUI:Create("Button")
        whisperButton:SetText("Whisper Leader")
        whisperButton:SetWidth(120)
        whisperButton:SetCallback("OnClick", function()
            local normalizedLeader = Grouper.NormalizeFullPlayerName(group.leader)
            local whisperText = "/tell " .. normalizedLeader .. " "
            if ChatFrame_OpenChat then
                ChatFrame_OpenChat(whisperText)
            elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
                local editBox = DEFAULT_CHAT_FRAME.editBox
                if editBox then
                    editBox:SetText(whisperText)
                    editBox:Show()
                    editBox:SetFocus()
                end
            end
        end)
        buttonGroup:AddChild(whisperButton)

        -- Role dropdown to the right of Auto-Join button
        local groupRoleDropdown = AceGUI:Create("Dropdown")
        groupRoleDropdown:SetLabel("Role")
        groupRoleDropdown:SetList({
            tank = "Tank",
            healer = "Healer",
            dps = "DPS"
        })
        -- Restore last selected role from SV if available
        local lastRole = self.db and self.db.profile and self.db.profile.lastRole
        if lastRole and (lastRole == "tank" or lastRole == "healer" or lastRole == "dps") then
            groupRoleDropdown:SetValue(lastRole)
        else
            groupRoleDropdown:SetValue("dps")
        end
        groupRoleDropdown:SetWidth(100)
        groupRoleDropdown:SetCallback("OnValueChanged", function(widget, event, value)
            if self.db and self.db.profile then
                self.db.profile.lastRole = value
            end
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: Group frame role set to " .. tostring(value))
            end
        end)
        buttonGroup:AddChild(groupRoleDropdown)

        local autoJoinButton = AceGUI:Create("Button")
        autoJoinButton:SetText("Auto-Join")
        autoJoinButton:SetWidth(120)
        autoJoinButton:SetCallback("OnClick", function()
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: Auto-Join button clicked!")
                self:Print(string.format("DEBUG: Group leader: %s", group.leader))
            end
            local playerName = UnitName("player")
            local fullPlayerName = Grouper.GetFullPlayerName(playerName)
            local normPlayerName = Grouper.NormalizeFullPlayerName(playerName)
            local normFullPlayerName = Grouper.NormalizeFullPlayerName(fullPlayerName)
            -- Set role from dropdown into cache before anything else
            local role = groupRoleDropdown:GetValue()
            -- Persist last selected role in SV
            if self.db and self.db.profile then
                self.db.profile.lastRole = role
            end
            -- Ensure self.playerInfo exists and update role
            if not self.playerInfo then
                self.playerInfo = {
                    fullName = fullPlayerName,
                    name = playerName,
                    class = select(2, UnitClass("player")) or "?",
                    race = select(2, UnitRace("player")) or "?",
                    level = UnitLevel("player") or 0,
                    role = role
                }
            else
                self.playerInfo.role = role
            end
            -- Update both Name and FullName keys in self.players (normalized)
            if self.players then
                -- Update by normalized Name
                if self.players[normPlayerName] then
                    self.players[normPlayerName].role = role
                    self.players[normPlayerName].fullName = normFullPlayerName
                end
                -- Update by normalized FullName
                if self.players[normFullPlayerName] then
                    self.players[normFullPlayerName].role = role
                    self.players[normFullPlayerName].name = normPlayerName
                end
            end
            -- Update non-leader cache on join
            self:HandleNonLeaderCache("join", fullPlayerName, group.id)
            -- Ensure both normalized keys are set after join logic
            if self.players then
                if self.players[normPlayerName] then
                    self.players[normPlayerName].role = role
                    self.players[normPlayerName].fullName = normFullPlayerName
                end
                if self.players[normFullPlayerName] then
                    self.players[normFullPlayerName].role = role
                    self.players[normFullPlayerName].name = normPlayerName
                end
            end
            -- Build a string payload: "INVITE_REQUEST|requester|timestamp|race|class|level|fullName|myRole"
            local inviteRequest = {
                type = "INVITE_REQUEST",
                requester = tostring(playerName),
                timestamp = time(),
                race = tostring(self.playerInfo.race or ""),
                class = tostring(self.playerInfo.class or ""),
                level = tonumber(self.playerInfo.level) or 0,
                fullName = tostring(self.playerInfo.fullName or playerName),
                groupId = group.id,
                myRole = role
            }
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: InviteRequest table:")
                for k, v in pairs(inviteRequest) do
                    self:Print("  " .. k .. "=" .. tostring(v))
                end
            end
            local AceSerializer = LibStub("AceSerializer-3.0")
            local payload = AceSerializer:Serialize(inviteRequest)
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: Sending invite request via AceComm to " .. group.leader)
            end
            -- Always normalize whisper target (remove spaces from realm)
            self:SendComm("AUTOJOIN", payload, "WHISPER", Grouper.NormalizeFullPlayerName(group.leader))
               -- Also refresh My Groups tab if currently selected
               if self.tabGroup and type(self.tabGroup.GetSelectedTab) == "function" then
                   local selectedTab = self.tabGroup:GetSelectedTab()
                   if selectedTab == "manage" then
                       self:RefreshGroupListManage()
                       -- Force full UI redraw of My Groups tab
                       if self.mainFrame then
                           self:ShowTab(self.mainFrame, "manage")
                       end
                   end
               end
        end)
        buttonGroup:AddChild(autoJoinButton)
    end

    return frame
end



-- Update group members when player joins a group
function Grouper:HandleJoinedGroupResults()
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: HandleJoinedGroupResults - updating group members and ResultsScrollFrame.")
        self:Print("DEBUG: HandleJoinedGroupResults stack trace:")
        self:Print(debugstack(2, 10, 10))
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

    -- Now update the results tab's scroll frame and group frames
    if self.ResultsScrollFrame then
        self.ResultsScrollFrame:ReleaseChildren()
        for _, group in pairs(self.groups) do
            local groupFrame = self:CreateGroupFrame(group, "results")
            self.ResultsScrollFrame:AddChild(groupFrame)
        end
    end
end


-- Refresh the group list display for Results tab
function Grouper:RefreshGroupListResults(tabType)
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.rep("-", 40))
        self:Print("DEBUG: [RefreshGroupListResults] called")
        self:Print("DEBUG: [RefreshGroupListResults] stack trace:\n" .. debugstack(2, 10, 10))
        self:Print("DEBUG: [RefreshGroupListResults] ResultsScrollFrame at entry: " .. tostring(self.ResultsScrollFrame) .. "\n" .. debugstack(2, 10, 10))
    end
    if not self.ResultsScrollFrame then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RefreshGroupListResults] ResultsScrollFrame is nil\n" .. debugstack(2, 10, 10))
        end
        return
    end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: 🔄 Groups in memory:")
        for id, group in pairs(self.groups) do
            self:Print(string.format("DEBUG:   - %s: %s (leader: %s)", id, group.title, group.leader))
        end
        self:Print("DEBUG: [RefreshGroupListResults] about to ReleaseChildren on ResultsScrollFrame: " .. tostring(self.ResultsScrollFrame))
    end
    self.ResultsScrollFrame:ReleaseChildren()
    local filteredGroups = self:GetFilteredGroups()
    if #filteredGroups == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No groups found matching your filters.")
        label:SetFullWidth(true)
        self.ResultsScrollFrame:AddChild(label)
        return
    end
    for _, group in ipairs(filteredGroups) do
        local groupFrame = self:CreateGroupFrame(group, "results")
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RefreshGroupListResults] about to AddChild to ResultsScrollFrame: " .. tostring(self.ResultsScrollFrame))
        end
        if groupFrame then
            self.ResultsScrollFrame:AddChild(groupFrame)
        end
    end
end
