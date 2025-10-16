-- Table to track Grouper-initiated invites
Grouper.pendingGrouperInvites = Grouper.pendingGrouperInvites or {}

-- Call this when Grouper sends an invite
function Grouper:TrackGrouperInvite(name)
    if name then
        local fullName = Grouper.GetFullPlayerName(name)
        self.pendingGrouperInvites[fullName] = true
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: TrackGrouperInvite - added " .. tostring(fullName) .. " to pendingGrouperInvites.")
            self:Print("DEBUG: Current pendingGrouperInvites: " .. table.concat(self:ListPendingGrouperInvites(), ", "))
        end
    end
end

function Grouper:ListPendingGrouperInvites()
    local t = {}
    for k in pairs(self.pendingGrouperInvites) do
        table.insert(t, k)
    end
    return t
end

-- Call this to clear a tracked invite (e.g., after join or timeout)
function Grouper:ClearGrouperInvite(name)
    if name then
        local fullName = Grouper.GetFullPlayerName(name)
        self.pendingGrouperInvites[fullName] = nil
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: ClearGrouperInvite - removed " .. tostring(fullName) .. " from pendingGrouperInvites.")
            self:Print("DEBUG: Current pendingGrouperInvites: " .. table.concat(self:ListPendingGrouperInvites(), ", "))
        end
    end
end

-- Called when a player joins the party but not through Grouper
function Grouper:ExternalInvite(name)
    self:Print("DEBUG: External invite detected for " .. tostring(name))
    -- Only proceed if a Grouper group exists and player is leader
    if not self.groups or not next(self.groups) then
        self:Print("DEBUG: No Grouper group exists. External invite workflow skipped.")
        return
    end
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    local leaderGroupId, group = nil, nil
    for groupId, g in pairs(self.groups) do
        if Grouper.NormalizeFullPlayerName(g.leader) == Grouper.NormalizeFullPlayerName(playerFullName) then
            leaderGroupId = groupId
            group = g
            break
        end
    end
    if not group then
        self:Print("DEBUG: You are not the Grouper group leader. External invite workflow skipped.")
        return
    end
    -- Build member info for the new player
    local foundUnit = nil
    local numGroupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    local isRaid = IsInRaid and IsInRaid()
    for i = 1, numGroupMembers do
        local unit = isRaid and ("raid"..i) or (i == 1 and "player" or "party"..(i-1))
        local n, r = UnitName(unit)
        if n and Grouper.GetFullPlayerName(n, r) == Grouper.GetFullPlayerName(name) then
            foundUnit = unit
            break
        end
    end
    if not foundUnit then
        self:Print("DEBUG: Could not find unit for external joiner " .. tostring(name))
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [ExternalInvite] Raw WoW API UnitName: foundUnit is nil, cannot print API info.")
        end
        return
    end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        local apiName, apiRealm = UnitName(foundUnit)
        local apiLevel = UnitLevel and UnitLevel(foundUnit) or nil
        self:Print(string.format("DEBUG: [ExternalInvite] Raw WoW API UnitName('%s'): name=%s, realm=%s, level=%s", tostring(foundUnit), tostring(apiName), tostring(apiRealm), tostring(apiLevel)))
    end
    -- ...existing code...
    local n, r = UnitName(foundUnit)
    local fullName = Grouper.GetFullPlayerName(n, r)
    local classLocalized, class = UnitClass(foundUnit)
    local raceLocalized, race = UnitRace(foundUnit)
    local normRace = (race == "Scourge" or raceLocalized == "Scourge") and "Undead" or (race or raceLocalized or "?")
    local function TitleCase(str)
        if not str then return str end
        return str:sub(1,1):upper() .. str:sub(2):lower()
    end
    -- Get the player's level using the WoW API
    local level = UnitLevel and UnitLevel(foundUnit) or nil
    if not level or level == 0 then
        -- fallback: try to get level from group roster if available (future-proofing)
        if C_PlayerInfo and C_PlayerInfo.GetPlayerLevel then
            level = C_PlayerInfo.GetPlayerLevel(fullName) or level
        end
    end
    local function showRolePopupWithLevel(member)
        self:ShowRoleAssignmentPopup({member}, function(roleSelections)
            local selectedRole = roleSelections[fullName]
            if not selectedRole or selectedRole == "None" then
                self:Print("DEBUG: No role selected for " .. fullName .. ". Skipping add to Grouper group.")
                return
            end
            -- Add to self.players
            self.players = self.players or {}
            self.players[fullName] = self.players[fullName] or {}
            self.players[fullName].fullName = fullName
            self.players[fullName].name = fullName
            self.players[fullName].class = member.class
            self.players[fullName].race = member.race
            self.players[fullName].level = member.level
            self.players[fullName].role = selectedRole
            self.players[fullName].groupId = leaderGroupId
            self.players[fullName].leader = false
            -- Add to group.members if not already present
            local alreadyInGroup = false
            for _, m in ipairs(group.members) do
                if Grouper.NormalizeFullPlayerName(m.name) == Grouper.NormalizeFullPlayerName(fullName) then
                    alreadyInGroup = true
                    break
                end
            end
            if not alreadyInGroup then
                table.insert(group.members, {
                    name = fullName,
                    class = member.class,
                    race = member.race,
                    level = member.level,
                    role = selectedRole,
                    leader = false
                })
            end
            -- Broadcast group update and refresh UI
            self:SendComm("GROUP_UPDATE", group)
            if self.RefreshGroupListManage then self:RefreshGroupListManage() end
            if self.RefreshGroupListResults then self:RefreshGroupListResults() end
            self:Print("DEBUG: Added external joiner " .. fullName .. " to Grouper group and broadcast update.")
        end)
    end

    if not level or level == 0 then
        -- Show a popup to input level
        local AceGUI = LibStub("AceGUI-3.0")
        local frame = AceGUI:Create("Frame")
        frame:SetTitle("Enter Player Level")
        frame:SetWidth(250)
        frame:SetHeight(120)
        frame:SetLayout("List")
        frame:EnableResize(false)
        local label = AceGUI:Create("Label")
        label:SetText("Enter the player's level (1-60):")
        frame:AddChild(label)
        local editBox = AceGUI:Create("EditBox")
        editBox:SetMaxLetters(2)
        editBox:SetWidth(60)
        editBox:SetLabel("Level")
        editBox:SetText("")
        editBox:SetCallback("OnTextChanged", function(widget, event, text)
            -- Only allow numbers and cap at 60
            local filtered = text:gsub("[^0-9]", "")
            local num = tonumber(filtered)
            if num and num > 60 then
                filtered = "60"
            end
            if filtered ~= text then
                widget:SetText(filtered)
            end
        end)
        frame:AddChild(editBox)
        local errorLabel = AceGUI:Create("Label")
        errorLabel:SetText("")
        errorLabel:SetColor(1, 0, 0)
        frame:AddChild(errorLabel)

        local confirmBtn = AceGUI:Create("Button")
        confirmBtn:SetText("OK")
        confirmBtn:SetFullWidth(true)
        confirmBtn:SetCallback("OnClick", function()
            local val = tonumber(editBox:GetText())
            if val and val >= 1 and val <= 60 then
                member = {
                    name = fullName,
                    class = TitleCase(class or classLocalized or "?"),
                    race = TitleCase(normRace),
                    level = val
                }
                frame:Hide()
                showRolePopupWithLevel(member)
            else
                errorLabel:SetText("Please enter a level from 1 to 60.")
            end
        end)
        frame:AddChild(confirmBtn)
    else
        member = {
            name = fullName,
            class = TitleCase(class or classLocalized or "?"),
            race = TitleCase(normRace),
            level = level
        }
        showRolePopupWithLevel(member)
    end
end
--  
function Grouper:LeaderRemoveMemberFromCache(leftName)
    local playerName = UnitName("player")
    local fullPlayerName = Grouper.GetFullPlayerName(playerName)
    local normFullPlayerName = Grouper.NormalizeFullPlayerName(fullPlayerName)
    -- Only act if current player is the party leader
    local isLeader = false
    for groupId, group in pairs(self.groups) do
    if Grouper.NormalizeFullPlayerName(group.leader) == normFullPlayerName then
            isLeader = true
            break
        end
    end
    -- Check if player is leader in self.groups
    if not isLeader then
    
    end
    -- Remove from cache (self.players)
    local leaderName = Grouper.GetFullPlayerName(UnitName("player"))
    local leaderGroupId = nil
    -- Find the groupId for which the current player is leader
    for groupId, group in pairs(self.groups) do
        if Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(leaderName) then
            leaderGroupId = groupId
            break
        end
    end
    for cacheName, info in pairs(self.players) do
        -- Only consider entries with the same groupId as the leader
        if info.groupId == leaderGroupId then
            local normCacheName = Grouper.NormalizeFullPlayerName(cacheName)
            local normLeftName = Grouper.NormalizeFullPlayerName(leftName)
            local normInfoFullName = info.fullName and Grouper.NormalizeFullPlayerName(info.fullName) or nil
            local normLeftNameFull = Grouper.NormalizeFullPlayerName(Grouper.GetFullPlayerName(leftName))
            local isDeparted = (normCacheName == normLeftName or normCacheName == normLeftNameFull or (normInfoFullName and normInfoFullName == normLeftName) or (normInfoFullName and normInfoFullName == normLeftNameFull))
            local normLeaderName = Grouper.NormalizeFullPlayerName(leaderName)
            local isLeader = (normCacheName == normLeaderName or (normInfoFullName and normInfoFullName == normLeaderName))
            if isDeparted and not isLeader then
                self.players[cacheName] = nil
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print("DEBUG: [LeaderRemoveMemberFromCache] Removed " .. cacheName .. " from cache after leaving party.")
                end
            end
        end
    end

    -- Update group member count only
    for groupId, group in pairs(self.groups) do
        if Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(Grouper.GetFullPlayerName(UnitName("player"))) and group.members then
            -- If disband event, set to 1 (just leader)
            if leftName == "DISBAND" then
                -- Remove all non-leader members from cache
                local leaderName = Grouper.GetFullPlayerName(UnitName("player"))
                local normLeaderName = Grouper.NormalizeFullPlayerName(leaderName)
                for cacheName, info in pairs(self.players) do
                    local normCacheName = Grouper.NormalizeFullPlayerName(cacheName)
                    local normInfoFullName = info.fullName and Grouper.NormalizeFullPlayerName(info.fullName) or nil
                    local isLeader = (normCacheName == normLeaderName or (normInfoFullName and normInfoFullName == normLeaderName))
                    if not isLeader then
                        self.players[cacheName] = nil
                        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                            self:Print("DEBUG: [LeaderRemoveMemberFromCache] Removed " .. cacheName .. " from cache after disband.")
                        end
                    end
                end
                -- Rebuild group.members as a table with only the leader's full info
                local leaderInfo = self.players[normLeaderName]
                group.members = {}
                if leaderInfo then
                    table.insert(group.members, {
                        name = leaderInfo.fullName or leaderName,
                        class = leaderInfo.class or "?",
                        race = leaderInfo.race or "?",
                        level = leaderInfo.level or "?",
                        role = leaderInfo.role or "?",
                        leader = true
                    })
                else
                    table.insert(group.members, {
                        name = leaderName,
                        class = "?",
                        race = "?",
                        level = "?",
                        role = "?",
                        leader = true
                    })
                end
            else
                -- Remove the departed member from self.players and group.members by groupId and member fullName
                local normLeftName = Grouper.NormalizeFullPlayerName(leftName)
                -- Remove from self.players (already handled above, but safe to repeat)
                for cacheName, info in pairs(self.players) do
                    local normCacheName = Grouper.NormalizeFullPlayerName(cacheName)
                    local normInfoFullName = info.fullName and Grouper.NormalizeFullPlayerName(info.fullName) or nil
                    if normCacheName == normLeftName or (normInfoFullName and normInfoFullName == normLeftName) then
                        self.players[cacheName] = nil
                        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                            self:Print("DEBUG: [LeaderRemoveMemberFromCache] Explicitly removed " .. cacheName .. " from cache after member left.")
                        end
                    end
                end
                -- Remove from group.members by fullName for this groupId only
                if group.members then
                    local i = 1
                    while i <= #group.members do
                        local m = group.members[i]
                        local mFullName = m.fullName or m.name or m
                        local normMFullName = Grouper.NormalizeFullPlayerName(mFullName)
                        if normMFullName == normLeftName then
                            table.remove(group.members, i)
                            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                                self:Print("DEBUG: [LeaderRemoveMemberFromCache] Explicitly removed " .. tostring(mFullName) .. " from group.members for groupId " .. tostring(groupId) .. ".")
                            end
                        else
                            i = i + 1
                        end
                    end
                end
            end
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: [LeaderRemoveMemberFromCache] Updated group " .. tostring(groupId) .. " member count: " .. tostring(#group.members))
            end
        end
    end
end

-- AceDB defaults: ensure debug.enabled is false by default
local GrouperDBDefaults = {
    profile = {
        debug = { enabled = false },
        filters = {
            minLevel = 1,
            maxLevel = 60,
        },
        notifications = {
            newGroups = true,
        },
        -- add other default settings here as needed
    }
}


-- Update state when player leaves a group
function Grouper:HandleLeftGroup()
    -- Player left a group - they can post new groups again
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: Player left a group")
    end
 end

 -- System message event handler for group join
local GrouperEventFrame = CreateFrame("Frame")
GrouperEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
GrouperEventFrame:SetScript("OnEvent", function(self, event, msg)
    if event == "CHAT_MSG_SYSTEM" and type(msg) == "string" then
        if Grouper and Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
            Grouper:Print("DEBUG: [SystemMessageEvent] Received: " .. tostring(msg))
        end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [LeaderRemoveMemberFromCache] Called for " .. tostring(leftName))
    end
        -- Player joins the party
        local joinedPartyPattern = "^(.-) joins the party%.$"
        local invitedPattern = "^You have invited (.-) to join your group%.$"
        local joinedName = msg:match(joinedPartyPattern)
        local invitedName = msg:match(invitedPattern)
        if joinedName and not invitedName then
            local fullName = Grouper.GetFullPlayerName(joinedName)
            -- Store player data in cache (if needed, can expand here)
            -- Check if joined through Grouper
            if Grouper.pendingGrouperInvites and Grouper.pendingGrouperInvites[fullName] then
                Grouper:ClearGrouperInvite(joinedName)
                if Grouper and Grouper.HandleJoinedGroupManage then
                    Grouper:HandleJoinedGroupManage()
                end
                if Grouper and Grouper.HandleJoinedGroupResults then
                    Grouper:HandleJoinedGroupResults()
                end
            else
                if Grouper and Grouper.ExternalInvite then
                    Grouper:ExternalInvite(joinedName)
                end
            end
        elseif msg:find("leaves the party") then
            local leftPartyPattern = "^(.-) leaves the party%.$"
            local leftName = msg:match(leftPartyPattern)
            local playerName = UnitName("player")
            local fullPlayerName = Grouper.GetFullPlayerName(playerName)
            local isLeader = false
            for groupId, group in pairs(Grouper.groups) do
                if Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(fullPlayerName) then
                    isLeader = true
                    break
                end
            end
            if leftName and Grouper and Grouper.LeaderRemoveMemberFromCache and isLeader then
                Grouper:LeaderRemoveMemberFromCache(leftName)
            end
            -- If the current player is NOT the leader and leftName matches the current player, remove the group from their UI using groupId from cache
            if not isLeader and leftName == fullPlayerName then
                local cacheInfo = Grouper.players and Grouper.players[fullPlayerName]
                local groupIdToRemove = cacheInfo and cacheInfo.groupId
                if groupIdToRemove and Grouper.groups[groupIdToRemove] then
                    Grouper.groups[groupIdToRemove] = nil
                    if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                        Grouper:Print("DEBUG: [LeaveGroup] Removed group " .. tostring(groupIdToRemove) .. " from UI for non-leader.")
                    end
                end
                if Grouper.RefreshGroupListResults then
                    Grouper:RefreshGroupListResults()
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupListResults then
                    Grouper:RefreshGroupListResults()
                end
            end
        elseif msg:find("You leave the group%.") or msg:find("leaves the party%.") or msg:find("You have been removed from the group%.") or msg:find("Your group has been disbanded%.") or msg:find("You have disbanded the group%.") then
            local playerName = UnitName("player")
            local fullPlayerName = Grouper.GetFullPlayerName(playerName)
            local isLeader = false
            for groupId, group in pairs(Grouper.groups) do
                if Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(fullPlayerName) then
                    isLeader = true
                end
            end
            -- Always use groupId from player cache for leave
            if Grouper and Grouper.players then
                local cacheInfo = Grouper.players[fullPlayerName] or Grouper.players[playerName]
                if not isLeader and Grouper.HandleNonLeaderCache and cacheInfo and cacheInfo.groupId then
                    Grouper:HandleNonLeaderCache("leave", fullPlayerName, cacheInfo.groupId)
                elseif isLeader and Grouper.LeaderRemoveMemberFromCache then
                    Grouper:LeaderRemoveMemberFromCache(playerName)
                end
            end
            -- Fallback: only remove group for non-leaders
            if not isLeader then
                local toRemove = {}
                for groupId, group in pairs(Grouper.groups) do
                    if group.members then
                        for _, member in ipairs(group.members) do
                            if member.name == fullPlayerName or member.name == playerName then
                                table.insert(toRemove, groupId)
                                break
                            end
                        end
                    end
                end
                for _, groupId in ipairs(toRemove) do
                    Grouper.groups[groupId] = nil
                    if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                        Grouper:Print("DEBUG: [LeaveGroup Fallback] Removed group " .. tostring(groupId) .. " from UI (fallback cleanup, non-leader).")
                    end
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupListManage then
                    Grouper:RefreshGroupListManage()
                end
            end
        end
        -- Always check for group disband and run cache removal logic
        if msg:find("You have disbanded the group") or msg:find("Your group has been disbanded%.") then
            if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                Grouper:Print("DEBUG: [Disband] TOP-LEVEL: Cache removal logic triggered by event handler.")
            end
            local leaderName = Grouper.GetFullPlayerName(UnitName("player"))
            local toRemove = {}
            if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                Grouper:Print("DEBUG: [Disband] Leader name: " .. tostring(leaderName))
                Grouper:Print("DEBUG: [Disband] Player cache before removal:")
                for name, info in pairs(Grouper.players) do
                    Grouper:Print("  - " .. tostring(name))
                end
            end
            for name, info in pairs(Grouper.players) do
                local isLeader = (name == leaderName) or (info and info.fullName == leaderName)
                if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                    Grouper:Print("DEBUG: [Disband] Comparing for removal:")
                    Grouper:Print("  - cache key: " .. tostring(name))
                    Grouper:Print("  - info.fullName: " .. tostring(info and info.fullName or "nil"))
                    Grouper:Print("  - leaderName: " .. tostring(leaderName))
                    Grouper:Print("  - isLeader: " .. tostring(isLeader))
                end
                if not isLeader then
                    table.insert(toRemove, name)
                end
            end
            for _, name in ipairs(toRemove) do
                Grouper.players[name] = nil
                if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                    Grouper:Print("DEBUG: [Disband] Removed " .. name .. " from cache after disband.")
                end
            end
            -- Rebuild group.members for the group(s) led by the player to only contain the leader
            local normLeaderName = Grouper.NormalizeFullPlayerName(leaderName)
            for groupId, group in pairs(Grouper.groups) do
                if Grouper.NormalizeFullPlayerName(group.leader) == normLeaderName then
                    local leaderInfo = Grouper.players[normLeaderName]
                    group.members = {}
                    if leaderInfo then
                        table.insert(group.members, {
                            name = leaderInfo.fullName or leaderName,
                            class = leaderInfo.class or "?",
                            race = leaderInfo.race or "?",
                            level = leaderInfo.level or "?",
                            role = leaderInfo.role or "?",
                            leader = true
                        })
                    else
                        table.insert(group.members, {
                            name = leaderName,
                            class = "?",
                            race = "?",
                            level = "?",
                            role = "?",
                            leader = true
                        })
                    end
                end
            end
            if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                Grouper:Print("DEBUG: [Disband] Player cache after removal:")
                for name, info in pairs(Grouper.players) do
                    Grouper:Print("  - " .. tostring(name))
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupListManage then
                    Grouper:RefreshGroupListManage()
                end
            end
        elseif msg:find("You leave the group%.") then
            -- When the leader leaves the group, clear all members from cache except self
            if Grouper and Grouper.LeaderRemoveMemberFromCache then
                local playerName = UnitName("player")
                for cacheName, _ in pairs(Grouper.players) do
                    if cacheName ~= playerName and cacheName ~= Grouper.GetFullPlayerName(playerName) then
                        Grouper:LeaderRemoveMemberFromCache(cacheName)
                    end
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupListManage then
                    Grouper:RefreshGroupListManage()
                end
            end
        end
    end
    if Grouper and Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
        Grouper:Print(string.format("DEBUG: [SystemMessageEvent] Event='%s', msg='%s'", tostring(event), tostring(msg)))
        Grouper:LogDebug(string.format("[SystemMessageEvent] Event='%s', msg='%s'", tostring(event), tostring(msg)))
    end
    if event == "CHAT_MSG_SYSTEM" and type(msg) == "string" then
        -- Player joins the party
    local joinedPartyPattern = "^(.-) joins the party%.$"
    local invitedPattern = "^You have invited (.-) to join your group%.$"
    local joinedName = msg:match(joinedPartyPattern)
    local invitedName = msg:match(invitedPattern)
    if joinedName and not invitedName then
        if Grouper and Grouper.HandleJoinedGroupManage then
            Grouper:HandleJoinedGroupManage()
        end
        if Grouper and Grouper.HandleJoinedGroupResults then
            Grouper:HandleJoinedGroupResults()
        end
        -- Player leaves the party
        elseif msg:find("leaves the party") then
            local leftPartyPattern = "^(.-) leaves the party%.$"
            local leftName = msg:match(leftPartyPattern)
            if leftName and Grouper and Grouper.LeaderRemoveMemberFromCache then
                Grouper:LeaderRemoveMemberFromCache(leftName)
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupListManage then
                    Grouper:RefreshGroupListManage()
                end
            end
        elseif msg:find("You have disbanded the group") then
            -- When the leader disbands the group, clear all members from cache
            if Grouper and Grouper.LeaderRemoveMemberFromCache then
                -- Remove all members except self
                local playerName = UnitName("player")
                for cacheName, _ in pairs(Grouper.players) do
                    if cacheName ~= playerName and cacheName ~= Grouper.GetFullPlayerName(playerName) then
                        Grouper:LeaderRemoveMemberFromCache(cacheName)
                    end
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupListManage then
                    Grouper:RefreshGroupListManage()
                end
            end

        end
    end
end)

-- Remove departed member's data from cache (only for party leader)
function Grouper:HandlePartyMemberLeft(leftName)
    -- Remove from cache (self.players)
    for cacheName, _ in pairs(self.players) do
    if cacheName == leftName or cacheName == Grouper.GetFullPlayerName(leftName) then
            self.players[cacheName] = nil
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: Removed " .. cacheName .. " from cache after leaving party.")
            end
        end
    end
end

-- Group management functions
function Grouper:CreateGroup(groupData)
    -- Prevent creating a second group if player already has one
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    for _, group in pairs(self.groups or {}) do
        if Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(playerFullName) then
            self:Print("Error: You’ve already formed a group. This isn’t Orgrimmar Trade Chat — you can’t just spam invites forever.")
            return nil
        end
    end
    -- Check if player is already in a WoW group using the WoW API
    local inWoWGroup = IsInGroup and IsInGroup()
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
    
    -- Class and race encoding tables
    local CLASS_IDS = { WARRIOR=1, PALADIN=2, HUNTER=3, ROGUE=4, PRIEST=5, DEATHKNIGHT=6, SHAMAN=7, MAGE=8, WARLOCK=9, DRUID=10, MONK=11, DEMONHUNTER=12, EVOKER=13 }
    local RACE_IDS = { Human=1, Orc=2, Dwarf=3, NightElf=4, Undead=5, Tauren=6, Gnome=7, Troll=8, Goblin=9, BloodElf=10, Draenei=11, Worgen=12, Pandaren=13 }
    local ROLE_IDS = { dps=1, tank=2, healer=3 }
    local function ShortName(fullName)
        return fullName:match("^([^-]+)") or fullName
    end
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    local role = groupData.myRole
    if inWoWGroup then
        -- Build member list from WoW group
        local members = {}
        local numGroupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
        local isRaid = IsInRaid and IsInRaid()
        for i = 1, numGroupMembers do
            local unit = isRaid and ("raid"..i) or (i == 1 and "player" or "party"..(i-1))
            local name, realm = UnitName(unit)
            if name then
                if not realm or realm == "" then
                    realm = GetRealmName() or ""
                    realm = realm:gsub("%s+", "")
                end
                local fullName = Grouper.GetFullPlayerName(name, realm)
                local isLeader = (fullName == playerFullName)
                local classLocalized, class = UnitClass(unit)
                local raceLocalized, race = UnitRace(unit)
                -- Normalize Scourge to Undead for display and cache
                local normRace = (race == "Scourge" or raceLocalized == "Scourge") and "Undead" or (race or raceLocalized or "?")
                local function TitleCase(str)
                    if not str then return str end
                    return str:sub(1,1):upper() .. str:sub(2):lower()
                end
                local level = UnitLevel(unit)
                table.insert(members, {
                    name = fullName,
                    isLeader = isLeader,
                    class = TitleCase(class or classLocalized or "?"),
                    race = TitleCase(normRace),
                    level = level or "?"
                })
            end
        end
        self:BuildPlayersCacheFromNames(members)
        -- Show popup for role assignment
        local groupDataCopy = groupData -- capture for closure
        self:ShowRoleAssignmentPopup(members, function(roleSelections)
            for _, member in ipairs(members) do
                local fullName = Grouper.GetFullPlayerName(member.name, member.realm)
                local selectedRole = roleSelections[fullName]
                if selectedRole and selectedRole ~= "None" then
                    self.players[fullName].role = selectedRole
                    member.role = selectedRole -- Ensure the members array is updated too
                    if fullName == playerFullName then
                        self.playerInfo = self.players[fullName]
                        self.playerInfo.role = selectedRole
                    end
                end
            end
            -- Assign members to groupDataCopy so FinalizeGroupCreation can process them
            groupDataCopy.members = members
            -- Actually create the group after roles are assigned, bypassing WoW import logic
            Grouper:FinalizeGroupCreation(groupDataCopy)
        end)
        return -- Wait for popup confirmation before proceeding

    else
        -- Solo/normal creation path (existing logic, but ensure normalization)
        if self.players then
            -- Normalize all keys in self.players
            local normalizedPlayers = {}
            for cacheName, info in pairs(self.players) do
                local normKey = Grouper.GetFullPlayerName(cacheName)
                normalizedPlayers[normKey] = info
            end
            self.players = normalizedPlayers
            -- Now update the local player's entry
            local normPlayerFullName = Grouper.NormalizeFullPlayerName(playerFullName)
            self.players[normPlayerFullName] = self.players[normPlayerFullName] or {}
            local name, realm = UnitName("player")
            self.players[normPlayerFullName].name = Grouper.GetFullPlayerName(name, realm)
            self.players[normPlayerFullName].realm = realm
            self.players[normPlayerFullName].fullName = Grouper.GetFullPlayerName(name, realm)
            self.players[normPlayerFullName].groupId = self:GenerateGroupID() -- Will be overwritten below, but ensures it's set
            if role then
                self.players[normPlayerFullName].role = role
                self.playerInfo = self.players[normPlayerFullName]
                self.playerInfo.role = role
            end
        end
    end
    -- Update self.players cache with live party/raid data for non-leader members only
    local function CamelCaseRole(role)
        if not role or role == "None" or role == "?" then return role end
        if role:lower() == "dps" then return "DPS" end
        return role:sub(1,1):upper() .. role:sub(2):lower()
    end
    if not self.players then self.players = {} end
    local leaderFullName = Grouper.GetFullPlayerName(UnitName("player"))
    local numGroupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    local isRaid = IsInRaid and IsInRaid()
    if numGroupMembers > 0 then
        for i = 1, numGroupMembers do
            local unit = isRaid and ("raid"..i) or (i == 1 and "player" or "party"..(i-1))
            local name, realm = UnitName(unit)
            if name then
                if not realm or realm == "" then
                    realm = GetRealmName() or ""
                    realm = realm:gsub("%s+", "")
                end
                local fullName = Grouper.GetFullPlayerName(name, realm)
                if fullName ~= leaderFullName then
                    local classLocalized, class = UnitClass(unit)
                    local raceLocalized, race = UnitRace(unit)
                    local level = UnitLevel(unit)
                    local blizzRole = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "?"
                    local role
                    if blizzRole == "TANK" then
                        role = "tank"
                    elseif blizzRole == "HEALER" then
                        role = "healer"
                    elseif blizzRole == "DAMAGER" then
                        role = "dps"
                    else
                        role = "?"
                    end
                    local normFullName = Grouper.NormalizeFullPlayerName(fullName)
                    self.players[normFullName] = self.players[normFullName] or {}
                    self.players[normFullName].name = fullName
                    self.players[normFullName].realm = realm
                    self.players[normFullName].fullName = fullName
                    self.players[normFullName].class = class or classLocalized or "?"
                    self.players[normFullName].race = race or raceLocalized or "?"
                    self.players[normFullName].level = level or "?"
                    self.players[normFullName].role = role
                    self.players[normFullName].lastSeen = time()
                    self.players[normFullName].leader = false -- Always set to false for non-leader
                    self.players[normFullName].groupId = group and group.id or nil -- Track group membership
                    -- Sync to self.playerInfo if this is the local player
                    if fullName == Grouper.GetFullPlayerName(UnitName("player")) then
                        self.playerInfo = self.playerInfo or {}
                        self.playerInfo.fullName = self.players[normFullName].fullName
                        self.playerInfo.class = self.players[normFullName].class
                        self.playerInfo.race = self.players[normFullName].race
                        self.playerInfo.level = self.players[normFullName].level
                        self.playerInfo.role = self.players[normFullName].role
                        self.playerInfo.lastSeen = self.players[normFullName].lastSeen
                        self.playerInfo.leader = self.players[normFullName].leader
                        self.playerInfo.groupId = self.players[normFullName].groupId
                    end
                end
            end
        end
    end
    
    -- Immediately refresh the manage tab UI after syncing all cache updates
    if self.mainFrame and self.mainFrame:IsShown() and self.tabGroup then
        self.tabGroup:SelectTab("manage")
    end
    
    -- For local display, use full cache data
    local members = {}
    local leaderFullName = Grouper.GetFullPlayerName(UnitName("player"))
    local leaderGroupId = nil
    if self.players and self.players[leaderFullName] then
        leaderGroupId = self.players[leaderFullName].groupId
    end
    for playerName, playerInfo in pairs(self.players) do
        if playerInfo and playerInfo.lastSeen and playerInfo.groupId and leaderGroupId and playerInfo.groupId == leaderGroupId then
            -- Always use the correct full name for each member (not just the leader's realm)
            local memberFullName = playerInfo.fullName
            if not memberFullName and playerInfo.name and playerInfo.realm then
                memberFullName = Grouper.GetFullPlayerName(playerInfo.name, playerInfo.realm)
            end
            table.insert(members, {
                name = memberFullName or playerName,
                class = playerInfo.class or "?",
                race = playerInfo.race or "?",
                level = playerInfo.level or "?",
                role = CamelCaseRole(playerInfo.role or "None")
            })
        end
    end
        -- Add min/max level to each entry in group.dungeons
    local enrichedDungeons = {}
    if groupData.dungeons and next(groupData.dungeons) and DUNGEONS then
        for name, dungeon in pairs(groupData.dungeons) do
            local found = nil
            for _, d in ipairs(DUNGEONS) do
                if d.name == name then
                    found = d
                    break
                end
            end
            if found then
                enrichedDungeons[name] = {
                    id = found.id,
                    name = found.name,
                    minLevel = found.minLevel,
                    maxLevel = found.maxLevel,
                    type = found.type,
                    faction = found.faction,
                    brackets = found.brackets
                }
            else
                enrichedDungeons[name] = dungeon -- fallback to original
            end
        end
    else
        enrichedDungeons = groupData.dungeons or {}
    end
    local group = {
        id = self:GenerateGroupID(),
        leader = Grouper.GetFullPlayerName(UnitName("player")),
        title = groupData.title or "Untitled Group",
        description = groupData.description or "",
        type = groupData.type or "other",
        typeId = typeId,
        minLevel = groupData.minLevel or 1,
        maxLevel = groupData.maxLevel or 60,
        currentSize = groupData.currentSize or 1,
        maxSize = groupData.maxSize or 5,
        location = groupData.location or "",
        dungeons = enrichedDungeons,
        timestamp = time(),
        members = members,
        myRole = role
    }
    
    self.groups[group.id] = group
    -- Write group ID to player cache, only update existing entry
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    if self.players then
        local found = false
        for cacheName, info in pairs(self.players) do
            if cacheName == playerFullName or info.fullName == playerFullName then
                found = true
                info.groupId = nil -- Clear any previous groupId
                info.groupId = group.id
                -- Ensure role is set in cache
                if groupData.myRole then
                    info.role = groupData.myRole
                    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                        self:Print(string.format("DEBUG: [CreateGroup] Wrote role '%s' to cache for %s (key: %s)", tostring(info.role), playerFullName, cacheName))
                    end
                else
                    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                        self:Print(string.format("DEBUG: [CreateGroup] groupData.myRole missing for %s (key: %s)", playerFullName, cacheName))
                    end
                end
                -- Always set leader to true for the leader
                info.leader = true
            else
                -- Always set leader to false for non-leaders
                info.leader = false
            end
        end
        if not found and self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: [CreateGroup] No cache entry found for %s when writing role", playerFullName))
        end
    end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: [CreateGroup] About to SendComm GROUP_UPDATE for groupId=%s, title=%s", group.id, group.title))
    end
    self:SendComm("GROUP_UPDATE", group)
    -- self:Print(string.format("Created group: %s", group.title))
    -- Immediately refresh the UI so the new group appears
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshGroupListManage()
    end
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    return group
end

-- Internal helper to finalize group creation after role assignment popup
function Grouper:FinalizeGroupCreation(groupData)
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [FinalizeGroupCreation] Starting group creation for title: " .. tostring(groupData.title))
        self:Print("DEBUG: [FinalizeGroupCreation] Members to add:")
        for i, member in ipairs(groupData.members or {}) do
            self:Print(string.format("  %d: name=%s, realm=%s, class=%s, role=%s, leader=%s", i, tostring(member.name), tostring(member.realm), tostring(member.class), tostring(member.role), tostring(member.leader)))
        end
    end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [FinalizeGroupCreation] Populating self.players cache:")
    end
    -- This logic is similar to the normal solo/creation path, but skips WoW import
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    -- Remove any existing group for this player
    for groupId, group in pairs(self.groups or {}) do
        if Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(playerFullName) then
            self.groups[groupId] = nil
        end
    end
    -- Generate a new groupId
    local groupId = self:GenerateGroupID()
    local now = time()
    local group = {
        id = groupId,
        title = groupData.title,
        leader = playerFullName,
        type = groupData.type or "dungeon",
        typeId = groupData.typeId,
        minLevel = groupData.minLevel,
        maxLevel = groupData.maxLevel,
        location = groupData.location,
        dungeons = groupData.dungeons,
        members = {},
        created = now,
        lastUpdated = now,
        timestamp = now,
    }
    -- Only add/update the intended members from groupData.members
    for _, member in ipairs(groupData.members or {}) do
        local key = Grouper.GetFullPlayerName(member.name, member.realm)
        if not self.players[key] then
            self.players[key] = {}
        end
        local info = self.players[key]
        info.fullName = Grouper.GetFullPlayerName(member.name, member.realm)
        info.name = Grouper.GetFullPlayerName(member.name, member.realm)
        info.class = member.class or "?"
        info.race = member.race or "?"
        info.level = member.level or "?"
        info.role = member.role or "?"
        info.leader = (member.leader == true or member.leader == "yes") and "yes" or "no"
        info.groupId = groupId
        info.groupType = groupData.type or "dungeon"
        info.minLevel = groupData.minLevel
        info.maxLevel = groupData.maxLevel
        info.comment = groupData.comment
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print(string.format("  -> self.players[%s]: class=%s, role=%s, leader=%s, groupId=%s", tostring(key), tostring(info.class), tostring(info.role), tostring(info.leader), tostring(info.groupId)))
        end
        -- Sync to self.playerInfo if this is the local player
        if Grouper.NormalizeFullPlayerName(key) == Grouper.NormalizeFullPlayerName(self.localPlayerFullName) then
            for field, value in pairs(info) do
                self.playerInfo[field] = value
            end
        end
        table.insert(group.members, {
            name = info.fullName or key,
            class = info.class or "?",
            race = info.race or "?",
            level = info.level or "?",
            role = info.role or "?",
            leader = (key == playerFullName) and "yes" or "no"
        })
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [FinalizeGroupCreation] Final group.members table:")
        for i, m in ipairs(group.members) do
            self:Print(string.format("  %d: name=%s, class=%s, role=%s, leader=%s", i, tostring(m.name), tostring(m.class), tostring(m.role), tostring(m.leader)))
        end
        self:Print("DEBUG: [FinalizeGroupCreation] self.groups updated with new groupId: " .. tostring(groupId))
    end
    end
    self.groups = self.groups or {}
    self.groups[groupId] = group
    -- Set local player's groupId and leader flag
    if self.playerInfo then
        self.playerInfo.groupId = groupId
        self.playerInfo.leader = true
    end
    -- UI refresh
    if self.mainFrame and self.mainFrame:IsShown() and self.tabGroup then
        self:RefreshGroupListManage()
        self:RefreshGroupListResults()
    end
    self:Print("Group created: " .. (group.title or "(no title)"))
end

-- Update group details (only leader can update)
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
    -- Always update myRole if present in updates
    if updates.myRole then group.myRole = updates.myRole end
    
    group.timestamp = time()
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: [UpdateGroup] About to SendComm GROUP_UPDATE for groupId=%s, title=%s", group.id, group.title))
    end
    self:SendComm("GROUP_UPDATE", group)
    
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    return true
end

-- Remove group (only leader can remove)
function Grouper:RemoveGroup(groupId)
    local group = self.groups[groupId]
    if not group or group.leader ~= Grouper.GetFullPlayerName(UnitName("player")) then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RemoveGroup] Not found or not leader for groupId " .. tostring(groupId) .. ". group.leader=" .. tostring(group and group.leader) .. ", player=" .. Grouper.GetFullPlayerName(UnitName("player")))
        end
        return false
    end

    self.groups[groupId] = nil
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [RemoveGroup] Removed groupId from self.groups: " .. tostring(groupId))
    end
    self:SendComm("GROUP_REMOVE", {id = groupId})

    -- Also update self.players: clear groupId, leader, and role for local player
    local localPlayer = Grouper.GetFullPlayerName(UnitName("player"))
    local normLocalPlayer = Grouper.NormalizeFullPlayerName(localPlayer)
    self.players = self.players or {}
    if self.players[normLocalPlayer] then
        self.players[normLocalPlayer].groupId = "none"
        self.players[normLocalPlayer].leader = false
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RemoveGroup] Set groupId='none' and leader=false for " .. tostring(localPlayer) .. " in self.players")
        end
    end
    if self.playerInfo then
        self.playerInfo.groupId = "none"
        self.playerInfo.leader = false
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [RemoveGroup] Set groupId='none' and leader=false for self.playerInfo as well")
        end
    end

    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.format("Removed group: %s", group.title))
    end
    -- Print all group keys left in cache (debug only)
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        local count = 0
        for k, v in pairs(self.groups) do
            self:Print("DEBUG: [RemoveGroup] Remaining group in cache: " .. tostring(k))
            count = count + 1
        end
        self:Print("DEBUG: [RemoveGroup] Total groups left in cache: " .. count)
    end
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    return true
end

-- Handle incoming group updates
function Grouper:HandleGroupUpdate(groupData, sender)
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    -- Table to track printed group ids (persist for session)
    Grouper.printedGroupIds = Grouper.printedGroupIds or {}
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
    local localPlayer = Grouper.GetFullPlayerName(UnitName("player"))
        if localPlayer == groupData.leader then
            self:Print("DEBUG: [HandleGroupUpdate] (local leader) - using cache for members.")
        else
            self:Print("DEBUG: [HandleGroupUpdate] (remote user) - using received members.")
            self:Print(string.format("DEBUG: [HandleGroupUpdate] (remote user) - sender: %s, groupId: %s, title: %s", tostring(sender), tostring(groupData.id), tostring(groupData.title)))
            if groupData.members then
                for i, m in ipairs(groupData.members) do
                    self:Print(string.format("DEBUG: [HandleGroupUpdate] member %d: %s, class=%s, race=%s, level=%s", i, m.name or "?", m.class or tostring(m.classId), m.race or tostring(m.raceId), tostring(m.level)))
                end
                self:Print("DEBUG: [HandleGroupUpdate] (remote user) - received members: " .. table.concat(self:GetTableKeys(groupData.members), ", "))
            else
                self:Print("DEBUG: [HandleGroupUpdate] No members found in groupData.members for remote user!")
            end
            if groupData and groupData.timestamp then
                self:Print("DEBUG: [HandleGroupUpdate] (remote user) - group timestamp: " .. tostring(groupData.timestamp))
            end
            if groupData and groupData.type then
                self:Print("DEBUG: [HandleGroupUpdate] (remote user) - group type: " .. tostring(groupData.type))
            end
            self:Print("DEBUG: [HandleGroupUpdate] (remote user) - full groupData: " .. self:Serialize(groupData))
        end
    end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.rep("-", 40))
        self:Print("DEBUG: [HandleGroupUpdate] called")
        self:Print(string.format("DEBUG: sender: %s, leader: %s", sender, groupData and groupData.leader or "nil"))
        self:Print(string.format("DEBUG: Group ID: %s, Title: %s", groupData and groupData.id or "nil", groupData and groupData.title or "nil"))
        if groupData then
            for k, v in pairs(groupData) do
                self:Print(string.format("DEBUG: groupData.%s = %s", k, tostring(v)))
            end
        end
    end
    
    -- Debug: Print tabGroup, selected tab, and groupsScrollFrame before UI refresh
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [HandleGroupUpdate] tabGroup: " .. tostring(self.tabGroup))
        if self.tabGroup and self.tabGroup.GetSelectedTab then
            local selectedTab = self.tabGroup:GetSelectedTab()
            self:Print("DEBUG: [HandleGroupUpdate] selectedTab: " .. tostring(selectedTab))
        else
            self:Print("DEBUG: [HandleGroupUpdate] selectedTab: nil (tabGroup missing or no GetSelectedTab)")
        end
        self:Print("DEBUG: [HandleGroupUpdate] groupsScrollFrame: " .. tostring(self.groupsScrollFrame))
    end

    -- If the results tab is active, ensure groupsScrollFrame is set to the results tab's scroll frame
    if self.tabGroup and self.tabGroup.GetSelectedTab and self.tabGroup:GetSelectedTab() == "results" then
        local container = self.tabGroup
        if container and container.children then
            for _, child in ipairs(container.children) do
                if child.type == "ScrollFrame" then
                    self.groupsScrollFrame = child
                    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                        self:Print("DEBUG: [HandleGroupUpdate] groupsScrollFrame set to results tab's scroll frame: " .. tostring(child) .. "\\n" .. debugstack(2, 10, 10))
                    end
                    break
                end
            end
        end
    end

    -- Add safety check for nil groupData
    if not groupData then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: ERROR - groupData is nil in HandleGroupUpdate")
        end
        return
    end
    
    local normSender = Grouper.NormalizeFullPlayerName(sender)
    local normLeader = Grouper.NormalizeFullPlayerName(groupData.leader)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Comparing full names (normalized) - sender: %s, leader: %s", normSender, normLeader))
    end
    if normSender ~= normLeader then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Rejecting group update - sender mismatch (normalized: %s vs %s)", normSender, normLeader))
        end
        return
    end
    
    -- Always update player info cache from groupData.members before any filtering or group logic
    local RACE_NAMES_BY_ID = {
        [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Undead", [6] = "Tauren", [7] = "Gnome", [8] = "Troll", [9] = "Goblin", [10] = "BloodElf", [11] = "Draenei", [12] = "Worgen", [13] = "Pandaren"
    }
    if groupData.members then
        local normLeader = groupData.leader and Grouper.NormalizeFullPlayerName(groupData.leader)
        for _, m in ipairs(groupData.members) do
            local fullName = m.name
            if fullName then
                local normFullName = Grouper.NormalizeFullPlayerName(fullName)
                -- Merge: If a non-normalized version exists, update and remove it
                for k, v in pairs(self.players) do
                    if Grouper.NormalizeFullPlayerName(k) == normFullName and k ~= normFullName then
                        for field, val in pairs(v) do
                            self.players[normFullName] = self.players[normFullName] or {}
                            if self.players[normFullName][field] == nil then
                                self.players[normFullName][field] = val
                            end
                        end
                        self.players[k] = nil
                    end
                end
                if not self.players[normFullName] then self.players[normFullName] = {} end
                -- Set fullName to Grouper.GetFullPlayerName to preserve original capitalization and normalized realm
                self.players[normFullName].fullName = Grouper.GetFullPlayerName(fullName)
                self.players[normFullName].class = m.class or m.classId or "?"
                -- Decode raceId to race name if needed
                if m.race and type(m.race) == "number" then
                    self.players[normFullName].race = RACE_NAMES_BY_ID[m.race] or tostring(m.race)
                else
                    self.players[normFullName].race = m.race or "?"
                end
                self.players[normFullName].level = m.level or "?"
                self.players[normFullName].role = m.role or m.myRole or "?"
                -- Always set groupId and leader fields for every member
                self.players[normFullName].groupId = groupData.id
                if normLeader and normFullName == normLeader then
                    self.players[normFullName].leader = true
                else
                    self.players[normFullName].leader = false
                end
                -- Sync to self.playerInfo if this is the local player
                if fullName == Grouper.GetFullPlayerName(UnitName("player")) then
                    self.playerInfo = self.playerInfo or {}
                    self.playerInfo.fullName = self.players[normFullName].fullName
                    self.playerInfo.class = self.players[normFullName].class
                    self.playerInfo.race = self.players[normFullName].race
                    self.playerInfo.level = self.players[normFullName].level
                    self.playerInfo.role = self.players[normFullName].role
                    self.playerInfo.lastSeen = self.players[normFullName].lastSeen
                    self.playerInfo.leader = self.players[normFullName].leader
                    self.playerInfo.groupId = self.players[normFullName].groupId
                end
            end
        end
    end
    -- Now proceed with group filtering and storage
    if Grouper.NormalizeFullPlayerName(Grouper.GetFullPlayerName(groupData.leader)) == Grouper.NormalizeFullPlayerName(Grouper.GetFullPlayerName(sender)) then
        -- Remove stale groups led by the same leader before adding the new group
        for groupId, group in pairs(self.groups) do
            if group.leader == groupData.leader and groupId ~= groupData.id then
                self.groups[groupId] = nil
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: [HandleGroupUpdate] Removed stale group %s led by %s", groupId, groupData.leader))
                end
            end
        end
        self.groups[groupData.id] = groupData
        -- Update player cache with groupId if local player is the leader
        local localPlayer = Grouper.GetFullPlayerName(UnitName("player"))
        if self.players then
            local normLocalPlayer = Grouper.NormalizeFullPlayerName(localPlayer)
            if self.players[normLocalPlayer] and normLocalPlayer == Grouper.NormalizeFullPlayerName(groupData.leader) then
                self.players[normLocalPlayer].groupId = groupData.id
                -- Sync to self.playerInfo
                self.playerInfo = self.playerInfo or {}
                self.playerInfo.groupId = self.players[normLocalPlayer].groupId
                self.playerInfo.leader = self.players[normLocalPlayer].leader
                self.playerInfo.role = self.players[normLocalPlayer].role
                self.playerInfo.class = self.players[normLocalPlayer].class
                self.playerInfo.race = self.players[normLocalPlayer].race
                self.playerInfo.level = self.players[normLocalPlayer].level
                self.playerInfo.fullName = self.players[normLocalPlayer].fullName
                self.playerInfo.lastSeen = self.players[normLocalPlayer].lastSeen
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: [HandleGroupUpdate] Set groupId=%s for player %s in cache and synced to self.playerInfo", groupData.id, localPlayer))
                end
            end
        end
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
        if self.db.profile.notifications.newGroups and groupData.id then
            if not Grouper.printedGroupIds[groupData.id] then
                self:Print(string.format("New group available: %s", groupData.title))
                Grouper.printedGroupIds[groupData.id] = true
            end
        end
        -- Refresh UI if it's open (this happens after adding a group)
        if self.mainFrame and self.mainFrame:IsShown() then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Refreshing UI after adding group %s (total groups: %d)", groupData.id, self:CountGroups()))
            end
            -- If the Search Results tab is active, ensure self.groupsScrollFrame is set to the current results tab's scroll frame before refreshing
            if self.tabGroup and self.tabGroup.selected == "results" then
                local container = self.tabGroup
                if container and container.children then
                    for _, child in ipairs(container.children) do
                        if child.type == "ScrollFrame" then
                            self.groupsScrollFrame = child
                            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                                self:Print("DEBUG: [HandleGroupUpdate] Set groupsScrollFrame to active results tab scroll frame\n" .. debugstack(2, 10, 10))
                            end
                            break
                        end
                    end
                end
                self:RefreshGroupListResults()
            end
        end
    else
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Rejecting group update - sender mismatch (normalized: %s vs %s)", Grouper.NormalizeFullPlayerName(sender), Grouper.NormalizeFullPlayerName(groupData.leader)))
        end
    end
    
    -- Populate members for leader and remote users
    if Grouper.GetFullPlayerName(UnitName("player")) == groupData.leader then
        -- Party leader: use cache
        groupData.members = {}
        if self.players then
            for playerName, playerInfo in pairs(self.players) do
                if playerInfo and playerInfo.lastSeen then
                    table.insert(groupData.members, {
                        name = playerInfo.fullName or playerName,
                        class = playerInfo.class or "?",
                        race = playerInfo.race or "?",
                        level = playerInfo.level or "?"
                    })
                end
            end
        end
        if #groupData.members == 0 and self.db and self.db.profile and self.db.profile.debug.enabled then
            self:Print("DEBUG: No cached members found for leader group update!")
        end
    else
        -- Remote user: use groupData.members from message
        if not groupData.members or #groupData.members == 0 then
            if self.db and self.db.profile and self.db.profile.debug.enabled then
                self:Print("DEBUG: No members found in groupData.members for remote user!")
            end
        end
        -- No overwrite, use as received
    end
end

-- Handle incoming group removals
function Grouper:HandleGroupRemove(data, sender)
    if Grouper.UpdateLDBGroupCount then Grouper:UpdateLDBGroupCount() end
    local group = self.groups[data.id]
    if group and Grouper.NormalizeFullPlayerName(group.leader) == Grouper.NormalizeFullPlayerName(sender) then
        self.groups[data.id] = nil
    end
end

-- Remove group by leader name
function Grouper:RemoveGroupByLeader(leader)
    if not self.groups then return end
    local normLeader = Grouper.NormalizeFullPlayerName(leader)
    local toRemove = {}
    for groupId, group in pairs(self.groups) do
        if Grouper.NormalizeFullPlayerName(group.leader) == normLeader then
            table.insert(toRemove, groupId)
        end
    end
    for _, groupId in ipairs(toRemove) do
        self.groups[groupId] = nil
    end
    self:RefreshGroupListResults()
    self:RefreshGroupListManage()
end

-- When a response is received from a party leader, clear pending removal
function Grouper:OnGroupLeaderResponse(leader)
    if self.pendingGroupResponses then
        self.pendingGroupResponses[leader] = nil
    end
end

-- Filter and return groups based on current settings
function Grouper:GetFilteredGroups()
    -- Faction lookup tables
    local HORDE_RACES = {
        Orc=true, Troll=true, Tauren=true, Undead=true, BloodElf=true, Goblin=true, Pandaren=true
    }
    local ALLIANCE_RACES = {
        Human=true, Dwarf=true, NightElf=true, Gnome=true, Draenei=true, Worgen=true, Pandaren=true
    }
    -- Determine player's faction by their race
    local playerRace = UnitRace("player")
    local playerFaction = nil
    if HORDE_RACES[playerRace] and not ALLIANCE_RACES[playerRace] then
        playerFaction = "Horde"
    elseif ALLIANCE_RACES[playerRace] and not HORDE_RACES[playerRace] then
        playerFaction = "Alliance"
    elseif HORDE_RACES[playerRace] and ALLIANCE_RACES[playerRace] then
        playerFaction = "Neutral"
    end
    local filtered = {}
    local filters = self.db.profile.filters
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: 🔍 Filtering %d total groups", self:CountGroups()))
        self:Print(string.format("DEBUG: Filter settings - minLevel: %d, maxLevel: %d", filters.minLevel, filters.maxLevel))
    end
    
    for _, group in pairs(self.groups) do
        local include = true
        local reason = ""
        -- ...existing code...
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Checking group '%s' (type: %s, minLevel: %d, maxLevel: %d)", 
                group.title, group.type, group.minLevel or 0, group.maxLevel or 60))
        end
        -- Faction filter: Only show groups with leader of same faction
        if include and playerFaction and playerFaction ~= "Neutral" then
            local normLeader = group.leader and Grouper.NormalizeFullPlayerName(group.leader)
            local leaderInfo = self.players and normLeader and self.players[normLeader] or self.players and self.players[group.leader]
            local leaderRace = leaderInfo and leaderInfo.race
            local leaderFaction = nil
            if leaderRace then
                if HORDE_RACES[leaderRace] and not ALLIANCE_RACES[leaderRace] then
                    leaderFaction = "Horde"
                elseif ALLIANCE_RACES[leaderRace] and not HORDE_RACES[leaderRace] then
                    leaderFaction = "Alliance"
                elseif HORDE_RACES[leaderRace] and ALLIANCE_RACES[leaderRace] then
                    leaderFaction = "Neutral"
                end
            end
            if leaderFaction ~= playerFaction then
                include = false
                reason = string.format("faction mismatch (player: %s, leader: %s)", playerFaction, leaderFaction or "unknown")
            end
        end
        -- ...existing code...
        -- Level filter
        local groupMin = group.minLevel or 0
        local groupMax = group.maxLevel or 60
        local filterMin = filters.minLevel or 0
        local filterMax = filters.maxLevel or 60
        if include and (groupMin > filterMax or groupMax < filterMin) then
            include = false
            reason = string.format("level mismatch (group: %d-%d, filter: %d-%d)", 
                groupMin, groupMax, filterMin, filterMax)
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
        -- Role filter: Only show groups with open spots for the selected role
        local filterRole = filters.role or "any"
        if include and filterRole ~= "any" and group.type == "dungeon" then
            -- Count members by role
            local roleCounts = {tank=0, healer=0, dps=0}
            if group.members and #group.members > 0 then
                for _, member in ipairs(group.members) do
                    local role = member.role and string.lower(member.role)
                    if role == "tank" then roleCounts.tank = roleCounts.tank + 1
                    elseif role == "healer" then roleCounts.healer = roleCounts.healer + 1
                    elseif role == "dps" then roleCounts.dps = roleCounts.dps + 1
                    end
                end
            end
            local maxSpots = {tank=1, healer=1, dps=3}
            if roleCounts[filterRole] >= maxSpots[filterRole] then
                include = false
                reason = string.format("no open %s spot", filterRole)
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

-- Toggle main window visibility
function Grouper:ToggleMainWindow()
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        -- Check if we need to join the channel when opening UI
        self:EnsureChannelJoined()
        
        self:CreateMainWindow()
        self:RefreshGroupListResults()
        self:RefreshGroupListManage()
        self.mainFrame:Show()
    end
end

-- Create the main application window
function Grouper:CreateMainWindow()
    if self.mainFrame then
        self.mainFrame:Show()
        return
    end
    
    self.mainFrame = AceGUI:Create("Frame")
    self.mainFrame:SetTitle("Grouper")
    -- Assign a global name to the AceGUI frame for UISpecialFrames
    local frame = self.mainFrame.frame
    if frame and not frame:GetName() then
        _G["GrouperMainFrame"] = frame
    end
    tinsert(UISpecialFrames, "GrouperMainFrame")
    -- Check actual channel status
    local channelIndex = GetChannelName(ADDON_CHANNEL)
    local actuallyInChannel = channelIndex > 0
    if actuallyInChannel and not self.channelJoined then
        self.channelJoined = true -- Fix status if needed
    end
    -- Show addon version in the status bar 
    local version = GetAddOnMetadata and GetAddOnMetadata("Grouper", "Version") or "?"
    self.mainFrame:SetStatusText("Grouper Version" .. tostring(version))
    self.mainFrame:SetLayout("Fill")
    self.mainFrame:SetWidth(700)
    self.mainFrame:SetHeight(800) -- Increased from 600 to 800 for more scroll space
    
    -- Add drag functionality to frame borders
    -- frame is already set above
    -- Save window position and size on resize
    if frame and frame.SetScript then
        frame:SetScript("OnSizeChanged", function()
            self:SaveWindowPosition()
        end)
    end
    -- No custom ESC logic needed; UISpecialFrames handles ESC closing
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

-- Create main window content with tabs 
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
    {text = "Search Filters", value = "browse"},
    {text = "Search Results", value = "results"},
    {text = "Create Group", value = "create"},
    {text = "My Groups", value = "manage"}
    })
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        self:ShowTab(container, group)
    end)
    tabGroup:SelectTab("browse")
    mainContainer:AddChild(tabGroup)
    
    self.tabGroup = tabGroup

    -- Add tooltips to tab labels (TabGroup) immediately so they work on first load
    if self.tabGroup and not self._tabTooltipsHooked then
        self.tabGroup._tabTooltipsHooked = true
        self.tabGroup:SetCallback("OnTabEnter", function(widget, event, tabValue, frame)
            local tooltips = {
                browse = "Set filters to narrow your group search.",
                results = "View groups that match your filters.",
                create = "Create a new group and broadcast it.",
                manage = "View and manage groups you lead or have joined."
            }
            local tip = tooltips[tabValue]
            if tip and frame then
                GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        self.tabGroup:SetCallback("OnTabLeave", function(widget, event, tabValue, frame)
            GameTooltip:Hide()
        end)
    end

    -- No persistent scroll frames needed; each tab creates its own
end

-- Show the selected tab
function Grouper:ShowTab(container, tabName)
    container:ReleaseChildren()

    if tabName == "browse" then
        self:CreateBrowseTab(container)
    elseif tabName == "results" then
        self:CreateResultsTab(container)
    elseif tabName == "create" then
        self:CreateCreateTab(container)
    elseif tabName == "manage" then
        self:CreateManageTab(container)
    elseif tabName == "results" then
        self:CreateResultsTab(container) -- New case for results tab
    end


end

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
    self:RefreshGroupListResults()
    self:RefreshGroupListManage()
end

-- When a response is received from a party leader, clear pending removal
function Grouper:OnGroupLeaderResponse(leader)
    if self.pendingGroupResponses then
        self.pendingGroupResponses[leader] = nil
    end
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
                    debug = {
                        name = "Debug Mode",
                        desc = "Enable verbose debug logging for troubleshooting.",
                        type = "toggle",
                        order = 99,
                        set = function(info, val)
                            self.db.profile.debug = self.db.profile.debug or {}
                            self.db.profile.debug.enabled = val
                            if val then
                                self:Print("Debugging is now ON.")
                            else
                                self:Print("Debugging is now OFF.")
                            end
                        end,
                        get = function(info)
                            return self.db.profile.debug and self.db.profile.debug.enabled or false
                        end,
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




