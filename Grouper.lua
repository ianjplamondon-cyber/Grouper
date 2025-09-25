-- Remove departed member's data from cache (party leader only)
function Grouper:LeaderRemoveMemberFromCache(leftName)
    local playerName = UnitName("player")
    local fullPlayerName = Grouper.GetFullPlayerName(playerName)
    -- Only act if current player is the party leader
    local isLeader = false
    for groupId, group in pairs(self.groups) do
        if group.leader == fullPlayerName then
            isLeader = true
            break
        end
    end
    if not isLeader then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: [LeaderRemoveMemberFromCache] Skipped: Not leader.")
        end
        return
    end
    -- Remove from cache (self.players)
    local leaderName = Grouper.GetFullPlayerName(UnitName("player"))
    for cacheName, info in pairs(self.players) do
        local isDeparted = (cacheName == leftName or cacheName == Grouper.GetFullPlayerName(leftName) or (info.fullName and info.fullName == leftName) or (info.fullName and info.fullName == Grouper.GetFullPlayerName(leftName)))
        local isLeader = (cacheName == leaderName or (info.fullName and info.fullName == leaderName))
        if isDeparted and not isLeader then
            self.players[cacheName] = nil
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: [LeaderRemoveMemberFromCache] Removed " .. cacheName .. " from cache after leaving party.")
            end
        end
    end

    -- Update group member count only
    for groupId, group in pairs(self.groups) do
        if group.leader == Grouper.GetFullPlayerName(UnitName("player")) and group.members then
            -- If disband event, set to 1 (just leader)
            if leftName == "DISBAND" then
                group.members = { group.leader }
                -- Remove all non-leader members from cache
                local leaderName = Grouper.GetFullPlayerName(UnitName("player"))
                for cacheName, info in pairs(self.players) do
                    local isLeader = (cacheName == leaderName or (info.fullName and info.fullName == leaderName))
                    if not isLeader then
                        self.players[cacheName] = nil
                        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                            self:Print("DEBUG: [LeaderRemoveMemberFromCache] Removed " .. cacheName .. " from cache after disband.")
                        end
                    end
                end
            else
                -- Otherwise, decrement by 1 (minimum 1)
                local newCount = math.max(1, #group.members - 1)
                while #group.members > newCount do
                    table.remove(group.members)
                end
            end
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: [LeaderRemoveMemberFromCache] Updated group " .. tostring(groupId) .. " member count: " .. tostring(#group.members))
            end
        end
    end
end

-- Update group members when player joins a group
function Grouper:HandleJoinedGroup()
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: HandleJoinedGroup - preparing to broadcast updated group data.")
        self:Print("DEBUG: HandleJoinedGroup stack trace:")
        self:Print(debugstack(2, 10, 10))
    end
    -- Update the members field of the correct group using its unique ID
    if self.db.profile.debug.enabled then
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
            local groupLeader = group.leader
            for playerKey, playerInfo in pairs(self.players) do
                -- Only consider FullName keys (those containing a dash)
                if type(playerKey) == "string" and string.find(playerKey, "-") then
                    if playerInfo and playerInfo.groupId == groupId and playerInfo.lastSeen then
                        -- Set leader attribute
                        if playerKey == groupLeader then
                            playerInfo.leader = true
                            leaderFound = true
                        else
                            playerInfo.leader = false
                        end
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
                local leaderInfo = self.players[groupLeader]
                if not leaderInfo then
                    for _, info in pairs(self.players) do
                        if info.fullName == groupLeader then
                            leaderInfo = info
                            break
                        end
                    end
                end
                local myRole = leaderInfo and leaderInfo.role or "?"
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
        self:RefreshGroupList("manage")
    end
    -- If the My Groups tab is open, force a tab refresh to update the Sync button and members
    if self.tabGroup and self.tabGroup.selected == "manage" then
        self.tabGroup:SelectTab("manage")
    end
end

-- Update state when player leaves a group
function Grouper:HandleLeftGroup()
    -- Player left a group - they can post new groups again
    if self.db.profile.debug.enabled then
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
            if Grouper and Grouper.HandleJoinedGroup then
                Grouper:HandleJoinedGroup()
            end
        elseif msg:find("leaves the party") then
            local leftPartyPattern = "^(.-) leaves the party%.$"
            local leftName = msg:match(leftPartyPattern)
            local playerName = UnitName("player")
            local fullPlayerName = Grouper.GetFullPlayerName(playerName)
            local isLeader = false
            for groupId, group in pairs(Grouper.groups) do
                if group.leader == fullPlayerName then
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
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
                end
            end
        elseif msg:find("You leave the group%.") or msg:find("leaves the party%.") or msg:find("You have been removed from the group%.") or msg:find("Your group has been disbanded%.") or msg:find("You have disbanded the group%.") then
            local playerName = UnitName("player")
            local fullPlayerName = Grouper.GetFullPlayerName(playerName)
            local isLeader = false
            local groupIdToRemove = nil
            for groupId, group in pairs(Grouper.groups) do
                if group.leader == fullPlayerName then
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
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
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
            if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                Grouper:Print("DEBUG: [Disband] Player cache after removal:")
                for name, info in pairs(Grouper.players) do
                    Grouper:Print("  - " .. tostring(name))
                end
            end
            if Grouper and Grouper.HandleLeftGroup then
                Grouper:HandleLeftGroup()
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
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
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
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
            if Grouper and Grouper.HandleJoinedGroup then
                Grouper:HandleJoinedGroup()
                --[[
                -- Broadcast updated group data to all users after join is processed, with a delay and retry
                if Grouper.groups then
                    local inGroup = IsInGroup and IsInGroup() or false
                    if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                        Grouper:Print(string.format("DEBUG: [SystemJoin] IsInGroup() = %s", tostring(inGroup)))
                    end
                    if inGroup then
                        for groupId, group in pairs(Grouper.groups) do
                            if group.leader == Grouper.GetFullPlayerName(UnitName("player")) and Grouper.SendGroupUpdateViaChannel then
                                if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                                    Grouper:Print(string.format("DEBUG: [SystemJoin] About to SendGroupUpdateViaChannel for groupId=%s, title=%s", group.id, group.title))
                                end
                                Grouper:SendGroupUpdateViaChannel(group)
                                if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                                    Grouper:Print("DEBUG: Broadcasted updated group data after system join event.")
                                end
                            end
                        end
                    else
                        if Grouper.db and Grouper.db.profile and Grouper.db.profile.debug and Grouper.db.profile.debug.enabled then
                            Grouper:Print("DEBUG: [SystemJoin] Group not formed yet (IsInGroup()=false), skipping broadcast.")
                        end
                    end
                end
                --]]
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
                end
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
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
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
                if Grouper.RefreshGroupList then
                    Grouper:RefreshGroupList("manage")
                end
            end
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
        end
    end
end)

-- Group management functions
function Grouper:CreateGroup(groupData)
    -- Prevent creating a second group if player already has one
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    for _, group in pairs(self.groups or {}) do
        if group.leader == playerFullName then
            self:Print("Error: You’ve already formed a group. This isn’t Orgrimmar Trade Chat — you can’t just spam invites forever.")
            return nil
        end
    end
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
    -- First, update leader's cache entry with role from dropdown
    local playerFullName = Grouper.GetFullPlayerName(UnitName("player"))
    local role = groupData.myRole
    if self.players then
        for cacheName, info in pairs(self.players) do
            if cacheName == playerFullName or info.fullName == playerFullName then
                info.groupId = nil -- Clear any previous groupId
                info.groupId = self:GenerateGroupID() -- Will be overwritten below, but ensures it's set
                -- Ensure name and fullName are set for player.self
                local name, realm = UnitName("player")
                info.name = name
                info.fullName = playerFullName
                if role then
                    info.role = role
                    self.playerInfo = info
                    self.playerInfo.role = role
                end
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
                local fullName = realm and realm ~= "" and (name.."-"..realm) or name
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
                    if not self.players[fullName] then self.players[fullName] = {} end
                    self.players[fullName].fullName = fullName
                    self.players[fullName].class = class or classLocalized or "?"
                    self.players[fullName].race = race or raceLocalized or "?"
                    self.players[fullName].level = level or "?"
                    self.players[fullName].role = role
                    self.players[fullName].lastSeen = time()
                    self.players[fullName].leader = false -- Always set to false for non-leader
                end
            end
        end
    end
    -- For local display, use full cache data
    local members = {}
    for playerName, playerInfo in pairs(self.players) do
        if playerInfo and playerInfo.lastSeen then
            table.insert(members, {
                name = playerInfo.fullName or playerName,
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
    --[[
    self:SendComm("GROUP_UPDATE", group)
    self:Print(string.format("Created group: %s", group.title))
    -- Immediately refresh the UI so the new group appears
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshGroupList()
    end
    --]]
    return group
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
    
    return true
end

-- Remove group (only leader can remove)
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

-- Handle incoming group updates
function Grouper:HandleGroupUpdate(groupData, sender)
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
    
    -- Always update player info cache from groupData.members before any filtering or group logic
    local RACE_NAMES_BY_ID = {
        [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Undead", [6] = "Tauren", [7] = "Gnome", [8] = "Troll", [9] = "Goblin", [10] = "BloodElf", [11] = "Draenei", [12] = "Worgen", [13] = "Pandaren"
    }
    if groupData.members then
        for _, m in ipairs(groupData.members) do
            local fullName = m.name
            if fullName then
                if not self.players[fullName] then self.players[fullName] = {} end
                self.players[fullName].fullName = fullName
                self.players[fullName].class = m.class or m.classId or "?"
                -- Decode raceId to race name if needed
                if m.race and type(m.race) == "number" then
                    self.players[fullName].race = RACE_NAMES_BY_ID[m.race] or tostring(m.race)
                else
                    self.players[fullName].race = m.race or "?"
                end
                self.players[fullName].level = m.level or "?"
                self.players[fullName].role = m.role or m.myRole or "?"
            end
        end
    end
    -- Now proceed with group filtering and storage
    if Grouper.GetFullPlayerName(groupData.leader) == Grouper.GetFullPlayerName(sender) then
        self.groups[groupData.id] = groupData
        -- Update player cache with groupId if local player is the leader
        local localPlayer = Grouper.GetFullPlayerName(UnitName("player"))
        if self.players and self.players[localPlayer] and localPlayer == groupData.leader then
            self.players[localPlayer].groupId = groupData.id
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: [HandleGroupUpdate] Set groupId=%s for player %s in cache", groupData.id, localPlayer))
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
    local group = self.groups[data.id]
    if group and group.leader == sender then
        self.groups[data.id] = nil
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
    self:RefreshGroupList()
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
            local leaderInfo = self.players and self.players[group.leader]
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
        if include and (group.minLevel > filters.maxLevel or group.maxLevel < filters.minLevel) then
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
        self:RefreshGroupList()
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

-- Create the main window content with tabs
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

    -- Initialize groupsScrollFrame so it's available for RefreshGroupList
    if not self.groupsScrollFrame then
        local groupsScrollFrame = AceGUI:Create("ScrollFrame")
        groupsScrollFrame:SetFullWidth(true)
        groupsScrollFrame:SetFullHeight(true)
        groupsScrollFrame:SetLayout("List")
        self.groupsScrollFrame = groupsScrollFrame
    end
end

-- Show the selected tab content
function Grouper:ShowTab(container, tabName)
    container:ReleaseChildren()
    
    if tabName == "browse" then
        self:CreateBrowseTab(container)
    elseif tabName == "create" then
        self:CreateCreateTab(container)
    elseif tabName == "manage" then
        self:CreateManageTab(container)
    elseif tabName == "results" then
        self:CreateResultsTab(container) -- New case for results tab
    end
end

-- Creat the Search Filters tab
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
        if typeInfo.key == "raid" or typeInfo.key == "pvp" then
            checkbox:SetDisabled(true)
            --checkbox:SetDescription("Not implemented yet")
        end
        checkbox:SetCallback("OnValueChanged", function(widget, event, value)
            self.db.profile.filters.dungeonTypes[typeInfo.key] = value
            self:RefreshGroupList()
        end)
        typeGroup:AddChild(checkbox)
    end
    
    -- Role filter dropdown
    local roleFilterDropdown = AceGUI:Create("Dropdown")
    roleFilterDropdown:SetLabel("Filter by Role")
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
        self:RefreshGroupList()
    end)
    filterGroup:AddChild(roleFilterDropdown)
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
  
    
end

-- Create the Search Results tab content
function Grouper:CreateResultsTab(container)
    -- Groups list
    local groupsScrollFrame = AceGUI:Create("ScrollFrame")
    groupsScrollFrame:SetFullWidth(true)
    groupsScrollFrame:SetFullHeight(true)
    groupsScrollFrame:SetLayout("List")
    container:AddChild(groupsScrollFrame)
    
    self.groupsScrollFrame = groupsScrollFrame
    self:RefreshGroupList()
end

-- Create the "Create Group" tab UI
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

-- Builds the "My Groups" tab where the player can manage their created groups
function Grouper:CreateManageTab(container)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    scrollFrame:SetLayout("List")
    container:AddChild(scrollFrame)
    
    local myGroups = {}
    for _, group in pairs(self.groups) do
    if group.leader == Grouper.GetFullPlayerName(UnitName("player")) then
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
            local groupFrame = self:CreateGroupManageFrame(group, "manage")
            scrollFrame:AddChild(groupFrame)
        end
    end
end

-- Create a frame for managing a specific group
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
    infoLabel:SetText(string.format("Type: %s | Dungeons: %s | Level: %d-%d | Size: %d/%d\nMeeting Point: %s",
        group.type, dungeonsText, group.minLevel, group.maxLevel, group.currentSize, group.maxSize,
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

    if tabType == "browse" then
        local whisperButton = AceGUI:Create("Button")
        whisperButton:SetText("Whisper Leader")
        whisperButton:SetWidth(120)
        whisperButton:SetCallback("OnClick", function()
            local whisperText = "/tell " .. group.leader .. " "
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
            self:Print("DEBUG: Group frame role set to " .. tostring(value))
        end)
        buttonGroup:AddChild(groupRoleDropdown)

        local autoJoinButton = AceGUI:Create("Button")
        autoJoinButton:SetText("Auto-Join")
        autoJoinButton:SetWidth(120)
        autoJoinButton:SetCallback("OnClick", function()
            self:Print("DEBUG: Auto-Join button clicked!")
            self:Print(string.format("DEBUG: Group leader: %s", group.leader))
            local playerName = UnitName("player")
            local fullPlayerName = Grouper.GetFullPlayerName(playerName)
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
            -- Update both Name and FullName keys in self.players
            if self.players then
                -- Update by Name
                if self.players[playerName] then
                    self.players[playerName].role = role
                    self.players[playerName].fullName = fullPlayerName
                end
                -- Update by FullName
                if self.players[fullName] then
                    self.players[fullName].role = role
                    self.players[fullName].name = playerName
                end
            end
            -- Update non-leader cache on join
            self:HandleNonLeaderCache("join", fullPlayerName, group.id)
            -- Ensure both keys are set after join logic
            if self.players then
                if self.players[playerName] then
                    self.players[playerName].role = role
                    self.players[playerName].fullName = fullPlayerName
                end
                if self.players[fullName] then
                    self.players[fullName].role = role
                    self.players[fullName].name = playerName
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
            self:Print("DEBUG: InviteRequest table:")
            for k, v in pairs(inviteRequest) do
                self:Print("  " .. k .. "=" .. tostring(v))
            end
            local AceSerializer = LibStub("AceSerializer-3.0")
            local payload = AceSerializer:Serialize(inviteRequest)
            self:Print("DEBUG: Sending invite request via AceComm to " .. group.leader)
            self:SendComm("AUTOJOIN", payload, "WHISPER", group.leader)
               -- Also refresh My Groups tab if currently selected
               if self.tabGroup and self.tabGroup:GetSelectedTab() == "manage" then
                   self:RefreshGroupList("manage")
                   -- Force full UI redraw of My Groups tab
                   if self.mainFrame then
                       self:ShowTab(self.mainFrame, "manage")
                   end
               end
               -- Refresh My Groups tab if currently selected
               if self.tabGroup and self.tabGroup:GetSelectedTab() == "manage" then
                   self:RefreshGroupList("manage")
               end
        end)
        buttonGroup:AddChild(autoJoinButton)
    else
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
                self.tabGroup:SelectTab("manage")
            end
        end)
        buttonGroup:AddChild(removeButton)

        local syncButton = AceGUI:Create("Button")
        syncButton:SetText("Sync")
        syncButton:SetWidth(100)
        syncButton:SetCallback("OnClick", function()
            self:Print("DEBUG: Sync button clicked! Broadcasting group update...")
            Grouper:SendGroupUpdateViaChannel(group)
               -- Also refresh My Groups tab if currently selected
               if self.tabGroup and self.tabGroup:GetSelectedTab() == "manage" then
                   self:RefreshGroupList("manage")
               end
               -- Refresh My Groups tab if currently selected
               if self.tabGroup and self.tabGroup:GetSelectedTab() == "manage" then
                   self:RefreshGroupList("manage")
               end
        end)
        buttonGroup:AddChild(syncButton)
    end

    return frame
end

-- Refresh the group list in the browse tab based on current filters
function Grouper:RefreshGroupList(tabType)
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
        local groupFrame = self:CreateGroupManageFrame(group, tabType or "browse")
        self.groupsScrollFrame:AddChild(groupFrame)
    end
end




function Grouper:ShowEditGroupDialog(group)
    -- This is a placeholder for the edit dialog
    self:Print("Edit functionality coming soon!")
end


