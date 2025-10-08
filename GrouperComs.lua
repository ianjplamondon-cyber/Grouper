-- Returns true if the given player name is in your party or raid
function IsPlayerInGroupOrRaid(targetName)
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i)
            if name and name == targetName then
                return true
            end
        end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name and name == targetName then
                return true
            end
        end
        if UnitName("player") == targetName then
            return true
        end
    end
    return false
end
-- Handle party invite requests for auto-accept functionality
function Grouper:OnPartyInviteRequest(event, inviter)
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        print("DEBUG: Grouper OnPartyInviteRequest fired! Event:", event, "Inviter:", inviter)
    end
    -- Auto-join logic commented out except for WoW API group invite initiation
    -- if not self.db.profile.autoJoin.enabled then
    --     return
    -- end
    -- local inviterName = self:StripRealmName(inviter)
    -- if self.db.profile.debug.enabled then
    --     self:Print(string.format("DEBUG: Received party invite request from %s", inviterName))
    -- end
    -- if self.db.profile.autoJoin.autoAccept then
    --     -- AcceptGroup() call disabled to prevent protected function error
    --     -- self:Print(string.format("Auto-accepted invite from %s", inviterName))
    -- else
    --     -- Show popup for confirmation (WoW will show default invite popup)
    --     self:Print(string.format("Invite request from %s (check invite popup)", inviterName))
    -- end
end

-- Check if already in the Grouper channel on startup
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

-- Communication functions using AceComm-3.0
function Grouper:SendComm(messageType, data, distribution, target, priority)
    -- For GROUP_UPDATE, GROUP_REMOVE, and REQUEST_DATA, use direct channel messaging for CHANNEL distribution
    -- But allow WHISPER and other distributions to use proper AceComm
    if messageType == "GROUP_UPDATE" and (distribution == "CHANNEL" or not distribution) then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: SendComm GROUP_UPDATE stack trace:")
            self:Print(debugstack(2, 10, 10))
        end
        return self:SendGroupUpdateViaChannel(data)
    elseif messageType == "GROUP_REMOVE" and (distribution == "CHANNEL" or not distribution) then
        return self:SendGroupRemoveViaChannel(data)
    elseif messageType == "REQUEST_DATA" and (distribution == "CHANNEL" or not distribution) then
        return self:SendRequestDataViaChannel(data)
    end
    
    -- For WHISPER and other distributions, use standard AceComm which works fine
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ SendComm called with messageType='%s', distribution='%s', target='%s'", messageType, distribution or "default", tostring(target)))
        if messageType == "AUTOJOIN" and type(data) == "string" then
            self:Print(string.format("DEBUG: AUTOJOIN payload: %s", data))
        end
    end

    local commPriority = priority or "NORMAL"
    if messageType == "TEST" then
        commPriority = "ALERT"
    end
    local distributionType = distribution or "CHANNEL"
    local commTarget = target
    -- Always normalize whisper target (remove spaces from realm)
    if distributionType == "WHISPER" and commTarget then
        local before = tostring(commTarget)
        -- If the target does not include a realm, append the sender's realm
        if not commTarget:find("-") then
            local _, senderRealm = UnitName("player")
            if senderRealm and senderRealm ~= "" then
                commTarget = commTarget .. "-" .. senderRealm
            end
        end
        commTarget = Grouper.NormalizeFullPlayerName(commTarget)
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: [SendComm] WHISPER target before='%s', after normalization='%s'", before, tostring(commTarget)))
        end
    end

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
        commTarget = channelIndex
    end

    local success, errorMsg = pcall(function()
        local prefix = "GRPR_" .. messageType
        if messageType == "GROUP_UPDATE" then
            prefix = "GRPR_GRP_UPD"
        elseif messageType == "GROUP_REMOVE" then
            prefix = "GRPR_GRP_RMV"
        end
        if self.db.profile.debug.enabled then
            if distributionType == "WHISPER" then
                self:Print(string.format("DEBUG: ⚡ Sending AceComm with prefix='%s' via WHISPER to '%s'", prefix, tostring(commTarget)))
            else
                self:Print(string.format("DEBUG: ⚡ Sending AceComm with prefix='%s' to channel %d", prefix, commTarget))
            end
        end
        if messageType == "AUTOJOIN" and type(data) == "string" then
            self:SendCommMessage(prefix, data, distributionType, commTarget, commPriority)
        else
            local message = {
                type = messageType,
                sender = UnitName("player"),
                timestamp = time(),
                version = ADDON_VERSION
            }
            if data ~= nil then
                message.data = data
            end
            self:SendCommMessage(prefix, self:Serialize(message), distributionType, commTarget, commPriority)
        end
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


function Grouper:SendGroupUpdateViaChannel(groupData)
    if self.db.profile.debug.enabled then
        local groupExists = Grouper.groups and Grouper.groups[groupData.id]
        if groupExists then
            Grouper:Print(string.format("DEBUG: Sending GROUP_UPDATE for existing group ID %s (update)", groupData.id))
        else
            Grouper:Print(string.format("DEBUG: Sending GROUP_UPDATE for new group ID %s", groupData.id))
        end
    end
    -- Use direct channel messaging like the working direct channel test
    local channelIndex = self:GetGrouperChannelIndex()
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Channel index before broadcast: %d", channelIndex))
        self:Print(string.format("DEBUG: InCombatLockdown: %s", tostring(InCombatLockdown())))
        self:Print(string.format("DEBUG: UnitAffectingCombat('player'): %s", tostring(UnitAffectingCombat("player"))))
        self:Print(string.format("DEBUG: GetTime(): %s", tostring(GetTime())))
        self:Print(string.format("DEBUG: IsLoggedIn(): %s", tostring(IsLoggedIn())))
        if LoadingScreenFrame and LoadingScreenFrame:IsShown() then
            self:Print("DEBUG: LoadingScreen: SHOWN")
        else
            self:Print("DEBUG: LoadingScreen: HIDDEN")
        end
        self:Print(string.format("DEBUG: Event/context: SendGroupUpdateViaChannel called from %s", tostring(debugstack(2, 1, 1))))
    end
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
    
    -- Encode all selected dungeons as a comma-separated string of IDs
    local dungeonIdsStr = ""
    if groupData.dungeons and next(groupData.dungeons) then
        local ids = {}
        for dungeonName, selected in pairs(groupData.dungeons) do
            if selected and DUNGEON_IDS and DUNGEON_IDS[dungeonName] then
                table.insert(ids, tostring(DUNGEON_IDS[dungeonName]))
            end
        end
        dungeonIdsStr = table.concat(ids, ",")
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
    
    -- Encode all members: shortName,classId,raceId,level|...
    local CLASS_IDS = { WARRIOR=1, PALADIN=2, HUNTER=3, ROGUE=4, PRIEST=5, DEATHKNIGHT=6, SHAMAN=7, MAGE=8, WARLOCK=9, DRUID=10, MONK=11, DEMONHUNTER=12, EVOKER=13 }
    local RACE_IDS = { Human=1, Orc=2, Dwarf=3, NightElf=4, Undead=5, Tauren=6, Gnome=7, Troll=8, Goblin=9, BloodElf=10, Draenei=11, Worgen=12, Pandaren=13 }
    local memberStrings = {}
    if groupData.members then
        for _, m in ipairs(groupData.members) do
            local classId = m.classId or (m.class and CLASS_IDS[string.upper(m.class)]) or 0
            local raceId = m.raceId or (m.race and RACE_IDS[m.race]) or 0
            local roleStr = m.role or "?"
            table.insert(memberStrings, string.format("%s,%d,%d,%d,%s",
                m.name or "?",
                classId,
                raceId,
                m.level or 0,
                roleStr))
        end
    end
    local membersEncoded = table.concat(memberStrings, ";")
    local message = string.format("GRPR_GROUP_UPDATE:%s:%s:%d:%s:%d:%d:%s:%d:%s:%d:%s",
        groupData.id or "",
        title,
        typeId,
        dungeonIdsStr,
        groupData.currentSize or 1,
        groupData.maxSize or 5,
        location,
        groupData.timestamp or time(),
        groupData.leader or UnitName("player"),
        roleId,
        membersEncoded
    )
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ Sending encoded GROUP_UPDATE via direct channel %d: %s", channelIndex, message))
    end

    -- Debug print before sending the message to AceComm handler
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: About to send GROUP_UPDATE via SendChatMessage")
        self:Print("Payload:")
        self:Print(message)
        self:Print(string.format("Communication Info: type=CHANNEL, language=nil, channelIndex=%s", tostring(channelIndex)))
    end

    local maxRetries = 5
    local retryDelay = 3
    local attempt = 1
    local function trySend()
        -- Protected checks before sending
        if InCombatLockdown() or UnitAffectingCombat("player") then
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: [SendChatMessage] BLOCKED by combat lockdown (InCombatLockdown=%s, UnitAffectingCombat=%s) - delaying retry", tostring(InCombatLockdown()), tostring(UnitAffectingCombat("player"))))
            end
            if attempt <= maxRetries then
                attempt = attempt + 1
                C_Timer.After(retryDelay, trySend)
            else
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print("DEBUG: [SendChatMessage] Max retries reached due to combat lockdown, giving up.")
                end
            end
            return
        end
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: [SendChatMessage] Attempt %d/%d for GROUP_UPDATE", attempt, maxRetries))
            self:Print(string.format("Args: message='%s', type='CHANNEL', language=nil, channelIndex=%s", message, tostring(channelIndex)))
            self:Print("DEBUG: [SendChatMessage] Stack trace:")
            self:Print(debugstack(2, 10, 10))
        end
        local success, err = pcall(function()
            SendChatMessage(message, "CHANNEL", nil, channelIndex)
        end)
        if success then
            if self.db.profile.debug.enabled then
                self:Print("DEBUG: ✓ GROUP_UPDATE sent via direct channel")
            end
            return true
        else
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: [SendChatMessage] Failed attempt %d/%d: %s", attempt, maxRetries, tostring(err)))
            end
            attempt = attempt + 1
            if attempt <= maxRetries then
                C_Timer.After(retryDelay, trySend)
            else
                if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                    self:Print("DEBUG: [SendChatMessage] Max retries reached, giving up.")
                end
            end
        end
    end
    -- Initial protected check before first send
    if InCombatLockdown() or UnitAffectingCombat("player") then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: [SendChatMessage] Initial BLOCKED by combat lockdown (InCombatLockdown=%s, UnitAffectingCombat=%s) - delaying first send", tostring(InCombatLockdown()), tostring(UnitAffectingCombat("player"))))
        end
        C_Timer.After(retryDelay, trySend)
    else
        trySend()
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

    -- Always send REQUEST_DATA in standard protocol format, do not prefix with DEL
    local debugEnabled = self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled
    if debugEnabled then
        self:Print(string.format("DEBUG: ⚡ Sending REQUEST_DATA via direct channel %d: %s", channelIndex, message))
        self:Print("DEBUG: [SendChatMessage] About to call SendChatMessage for REQUEST_DATA")
        self:Print(string.format("Args: message='%s', type='CHANNEL', language=nil, channelIndex=%s", message, tostring(channelIndex)))
        self:Print("DEBUG: [SendChatMessage] Stack trace:")
        self:Print(debugstack(2, 10, 10))
    end
    SendChatMessage(message, "CHANNEL", nil, channelIndex)
    if debugEnabled then
        self:Print("DEBUG: ✓ REQUEST_DATA sent via direct channel")
    end
    return true
end

function Grouper:HandleDirectGroupUpdate(message, sender)
    -- Debug: Show raw membersEncoded and parsed member count
    local parts = {string.split(":", message)}
    local membersEncoded = parts[12] or ""
    if self.db.profile.debug.enabled then
        Grouper:Print(string.format("DEBUG: [HandleDirectGroupUpdate] raw membersEncoded: '%s'", membersEncoded))
        local memberCount = 0
        for _ in string.gmatch(membersEncoded, "[^;]+") do memberCount = memberCount + 1 end
        Grouper:Print(string.format("DEBUG: [HandleDirectGroupUpdate] parsed member count: %d", memberCount))
    end
    if self.db.profile.debug.enabled then
            local parts = {string.split(":", message)}
            local groupId = parts[2]
            local isUpdate = Grouper.groups and Grouper.groups[groupId]
            if isUpdate then
                Grouper:Print(string.format("DEBUG: Received GROUP_UPDATE for existing group ID %s (update) from %s", groupId, sender))
            else
                Grouper:Print(string.format("DEBUG: Received GROUP_UPDATE for new group ID %s from %s", groupId, sender))
            end
    end
    -- Parse: GRPR_GROUP_UPDATE:id:title:typeId:dungeonIds:currentSize:maxSize:location:timestamp:leader:roleId
    local parts = {string.split(":", message)}
    if #parts < 11 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid direct GROUP_UPDATE format from %s (got %d parts, expected 11)", sender, #parts))
        end
        return
    end
    local typeId = tonumber(parts[4]) or 1
    local dungeonIdsStr = parts[5] or ""
    local roleId = tonumber(parts[11]) or 3
    local typeNames = {
        [1] = "dungeon",
        [2] = "raid", 
        [3] = "quest",
        [4] = "pvp",
        [5] = "other"
    }
    local groupType = typeNames[typeId] or "dungeon"
    -- Parse dungeon IDs and reconstruct dungeons table
    local dungeons = {}
    local minLevel, maxLevel = 1, 60
    if dungeonIdsStr ~= "" then
        for idStr in string.gmatch(dungeonIdsStr, "[^,]+") do
            local id = tonumber(idStr)
            for _, dungeon in ipairs(DUNGEONS) do
                if dungeon.id == id then
                    dungeons[dungeon.name] = true
                    -- Use the first dungeon's level range for min/max
                    if minLevel == 1 and maxLevel == 60 then
                        minLevel = dungeon.minLevel
                        maxLevel = dungeon.maxLevel
                    end
                end
            end
        end
    elseif groupType == "dungeon" then
        minLevel = 13
        maxLevel = 18
    elseif groupType == "raid" then
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
    -- Decode members
    local CLASS_NAMES = { [1]="WARRIOR", [2]="PALADIN", [3]="HUNTER", [4]="ROGUE", [5]="PRIEST", [6]="DEATHKNIGHT", [7]="SHAMAN", [8]="MAGE", [9]="WARLOCK", [10]="DRUID", [11]="MONK", [12]="DEMONHUNTER", [13]="EVOKER" }
    local RACE_NAMES = { [1]="Human", [2]="Orc", [3]="Dwarf", [4]="NightElf", [5]="Undead", [6]="Tauren", [7]="Gnome", [8]="Troll", [9]="Goblin", [10]="BloodElf", [11]="Draenei", [12]="Worgen", [13]="Pandaren" }
    local members = {}
    local membersEncoded = parts[12] or ""
    for memberStr in string.gmatch(membersEncoded, "[^;]+") do
        local mName, mClassId, mRaceId, mLevel, mRole = string.match(memberStr, "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        local classId = tonumber(mClassId)
        local raceId = tonumber(mRaceId)
        table.insert(members, {
            name = mName,
            classId = classId,
            raceId = raceId,
            class = classId and CLASS_NAMES[classId] or "PRIEST",
            race = raceId and RACE_NAMES[raceId] or "Human",
            level = tonumber(mLevel),
            role = mRole or "?"
        })
    end
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
        dungeons = dungeons,
        members = members
    }
    
    if self.db.profile.debug.enabled then
        self:Print(string.format(
            "DEBUG: Processing encoded GROUP_UPDATE: id=%s, title=%s, typeId=%s, dungeonIds=%s, currentSize=%s, maxSize=%s, location=%s, timestamp=%s, leader=%s, roleId=%s, members=%s from %s",
            parts[2] or '',
            parts[3] or '',
            parts[4] or '',
            parts[5] or '',
            parts[6] or '',
            parts[7] or '',
            parts[8] or '',
            parts[9] or '',
            parts[10] or '',
            parts[11] or '',
            parts[12] or '',
            sender
        ))
    end
    
    -- Use the same processing as other group updates
    self:HandleGroupUpdate(groupData, sender)
end


function Grouper:HandleDirectGroupRemove(message, sender)
    -- Parse: GRPR_GROUP_REMOVE:groupId:leader:timestamp
    local parts = {string.split(":", message)}
    if #parts < 4 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid GROUP_REMOVE format from %s", sender))
        end
        return
    end
    
    local groupId = parts[2]
    local leader = parts[3]
    local timestamp = tonumber(parts[4])
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing direct GROUP_REMOVE: groupId=%s, leader=%s from %s", 
            groupId, leader, sender))
    end
    
    -- Only allow the group leader to remove their own group
    local group = self.groups[groupId]
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Name comparison - sender='%s', groupLeader='%s'", sender, group and group.leader or "nil"))
    end
    
    if group and group.leader == sender then
        self.groups[groupId] = nil
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ Removed group %s by leader %s", groupId, sender))
        end
        -- Refresh the UI to reflect the removal
        self:RefreshGroupList()
    else
        if self.db.profile.debug.enabled then
            if not group then
                self:Print(string.format("DEBUG: ✗ Cannot remove - group %s not found", groupId))
            else
                self:Print(string.format("DEBUG: ✗ Cannot remove - %s is not leader of group %s (leader: %s)", sender, groupId, group and group.leader or "nil"))
            end
        end
    end
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
    
    -- Always send GROUP_UPDATE whisper response immediately, regardless of debug setting
    if self.groups then
        local foundLeader = false
        for groupId, group in pairs(self.groups) do
            local playerName = UnitName("player")
            local playerServer = GetRealmName()
            if playerServer then
                playerServer = playerServer:gsub("%s+", "")
            end
            local fullPlayerName = playerName .. "-" .. playerServer
            local normGroupLeader = Grouper.NormalizeFullPlayerName(group.leader)
            local normPlayerName = Grouper.NormalizeFullPlayerName(playerName)
            local normFullPlayerName = Grouper.NormalizeFullPlayerName(fullPlayerName)
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: groupId=%s, leader=%s, title=%s", tostring(groupId), tostring(group.leader), tostring(group.title)))
                self:Print(string.format("DEBUG: Leader compare: group.leader='%s', playerName='%s', fullPlayerName='%s' (normalized: group.leader='%s', playerName='%s', fullPlayerName='%s')", tostring(group.leader), tostring(playerName), tostring(fullPlayerName), normGroupLeader, normPlayerName, normFullPlayerName))
            end
            if normGroupLeader == normPlayerName or normGroupLeader == normFullPlayerName then
                if self.db.profile.debug.enabled then
                    self:Print("DEBUG: Entered leader match block for WHISPER response.")
                    self:Print(string.format("DEBUG: Sending our group %s (%s) via WHISPER to %s using encoded format", groupId, group.title, sender))
                    self:Print(string.format("DEBUG: ⚡ Sending GROUP_UPDATE via addon whisper to %s using AceComm format", sender))
                end
                local message = {
                    type = "GROUP_UPDATE",
                    sender = UnitName("player"),
                    timestamp = time(),
                    version = ADDON_VERSION,
                    data = group
                }
                local serialized = self:Serialize(message)
                if self.db.profile.debug.enabled then
                    self:Print("DEBUG: Serialized whisper GROUP_UPDATE message:")
                    self:Print(serialized)
                end
                local success = self:SendCommMessage("GRPR_GRP_UPD", serialized, "WHISPER", sender, "NORMAL")
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: AceComm addon whisper result: %s", success and "SUCCESS" or "FAILED"))
                end
                foundLeader = true
            end
        end
        if self.db.profile.debug.enabled and not foundLeader then
            self:Print("DEBUG: No group found with current player as leader.")
        end
    else
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: self.groups is nil.")
        end
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
                local message = {
                    type = "GROUP_UPDATE",
                    sender = UnitName("player"),
                    timestamp = time(),
                    version = ADDON_VERSION,
                    data = group
                }
                local serialized = self:Serialize(message)
                if self.db.profile.debug.enabled then
                    self:Print("DEBUG: Serialized whisper GROUP_UPDATE message:")
                    self:Print(serialized)
                end
                local success = self:SendCommMessage("GRPR_GRP_UPD", serialized, "WHISPER", requester, "NORMAL")
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
    
    -- Strip leading non-printing characters (DEL, TAB, etc.) from message for protocol matching
    local cleanMessage = message:gsub("^[\127\t\n\r ]+", "")

    -- Check for direct test messages
    if cleanMessage:match("^GRPR_DIRECT_TEST:") then
        local testSender = cleanMessage:match("^GRPR_DIRECT_TEST:(.+)")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL TEST from %s (sent by %s)", sender, testSender))
        end
        return
    end

    -- Check for direct GROUP_UPDATE messages
    if cleanMessage:match("^GRPR_GROUP_UPDATE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_UPDATE from %s", sender))
        end
        self:HandleDirectGroupUpdate(cleanMessage, sender)
        return
    end

    -- Check for direct GROUP_REMOVE messages
    if cleanMessage:match("^GRPR_GROUP_REMOVE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_REMOVE from %s", sender))
        end
        self:HandleDirectGroupRemove(cleanMessage, sender)
        return
    end

    -- Check for direct REQUEST_DATA messages
    local debugEnabled = self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled
    if cleanMessage:match("^GRPR_REQUEST_DATA:") then
        if debugEnabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL REQUEST_DATA from %s", sender))
            self:Print(string.format("[Grouper] [%s]: %s", sender, cleanMessage))
        end
        -- Extra guard: never print protocol message unless debug is enabled
        -- (in case self:Print is overridden or called elsewhere)
        -- Do NOT print [Grouper] protocol message here unless debug is on
        self:HandleDirectRequestData(cleanMessage, sender)
        return
    end
    --]]
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
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        print("DEBUG: Grouper OnCommReceived fired! Prefix:", prefix, "Sender:", sender, "Distribution:", distribution)
        self:Print("DEBUG: [RECEIVER] OnCommReceived fired!")
        self:Print(string.format("DEBUG: [RECEIVER] prefix='%s', sender='%s', distribution='%s', message='%s'", prefix, sender, distribution, tostring(message)))
        self:Print(string.format("DEBUG: [GLOBAL] OnCommReceived - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    end
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: OnCommReceived called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    end
    
    -- Add specific debug for GRPR_GRP_UPD
    if prefix == "GRPR_GRP_UPD" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: 🎯 GRPR_GRP_UPD message received from %s!", sender))
            self:Print("DEBUG: Raw incoming whisper message:")
            self:Print(message)
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
    if prefix == "GRPR_AUTOJOIN" then
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Routing GRPR_AUTOJOIN to OnAutoJoinRequest")
        end
        self:OnAutoJoinRequest(prefix, message, distribution, sender)
        return
    elseif prefix == "GRPR_GRP_UPD" then
        messageType = "GROUP_UPDATE"
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED GRPR_GRP_UPD from %s, deserializing", sender))
        end
        -- Handle normal serialized format like TEST messages
        local pcall_success, deserialize_success, deserializedMessage = pcall(self.Deserialize, self, message)
        if pcall_success and deserialize_success and deserializedMessage then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: ✓ Successfully deserialized GRPR_GRP_UPD message"))
                
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
    elseif prefix == "GRPR_GRP_RMV" then
        messageType = "GROUP_REMOVE"
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED GRPR_GRP_RMV from %s, deserializing", sender))
        end
        -- Handle serialized GROUP_REMOVE message
        local pcall_success, deserialize_success, deserializedMessage = pcall(self.Deserialize, self, message)
        if pcall_success and deserialize_success and deserializedMessage then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: ✓ Successfully deserialized GRPR_GRP_RMV message"))
            end
            local success2, error2 = pcall(function()
                self:ProcessReceivedMessage(deserializedMessage.type, deserializedMessage, sender)
            end)
            if not success2 then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: ✗ ProcessReceivedMessage failed: %s", tostring(error2)))
                end
            end
        else
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: ✗ Failed to deserialize GRPR_GRP_RMV from %s", sender))
            end
        end
        return
    elseif prefix == "GRPR_CHUNK_REQ" then
        -- Handle chunk request directly
        self:HandleChunkRequest(message, sender)
        return
    elseif prefix == "GRPR_CHUNK_RES" then
        -- Handle chunk resend - process like a regular AceComm message
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Received GRPR_CHUNK_RES from %s, processing as AceComm message", sender))
        end
        -- Don't return early - let it fall through to normal processing
        messageType = "CHUNK_RESPONSE"
    elseif prefix == "GROUPER_TEST" then
        messageType = "TEST"
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

-- Handle Auto-Join invite requests via AceComm
function Grouper:OnAutoJoinRequest(prefix, message, distribution, sender)
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [RECEIVER] OnAutoJoinRequest fired!")
        self:Print(string.format("DEBUG: [RECEIVER] prefix='%s', sender='%s', distribution='%s', message='%s'", prefix, sender, distribution, tostring(message)))
        self:Print(string.format("DEBUG: OnAutoJoinRequest called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
        self:Print(string.format("DEBUG: Raw auto-join payload: %s", tostring(message)))
    end
    local AceSerializer = LibStub("AceSerializer-3.0")
    local success, inviteRequest = AceSerializer:Deserialize(message)
    if not success or type(inviteRequest) ~= "table" or inviteRequest.type ~= "INVITE_REQUEST" then
        self:Print("DEBUG: Invalid auto-join AceSerializer payload format")
        return
    end
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: Deserialized inviteRequest table:")
        for k, v in pairs(inviteRequest) do
            self:Print("  " .. k .. "=" .. tostring(v))
        end
    end

    -- Check for duplicate tank or healer in group
    local groupId = inviteRequest.groupId or inviteRequest.groupID or inviteRequest.group_id
    local requestedRole = (inviteRequest.myRole or inviteRequest.role or ""):lower()
    local group = self.groups and groupId and self.groups[groupId] or nil
    local tankExists, healerExists = false, false
    if group and group.members then
        for _, member in ipairs(group.members) do
            local roleLower = member.role and member.role:lower() or ""
            if roleLower == "tank" then
                tankExists = true
            elseif roleLower == "healer" then
                healerExists = true
            end
        end
    end
    if requestedRole == "tank" and tankExists then
        -- Send error message to requester, do not invite
        if distribution == "WHISPER" and inviteRequest.requester then
            SendChatMessage("Error: This group already has a tank. Did you think this was Alterac Valley?", "WHISPER", nil, inviteRequest.requester)
        end
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Blocked duplicate tank invite for " .. tostring(inviteRequest.requester))
        end
        return
    end
    if requestedRole == "healer" and healerExists then
        -- Send error message to requester, do not invite
        if distribution == "WHISPER" and inviteRequest.requester then
            SendChatMessage("Error: This group already has a healer. Two healers in a 5-man? What is this, Molten Core?", "WHISPER", nil, inviteRequest.requester)
        end
        if self.db.profile.debug.enabled then
            self:Print("DEBUG: Blocked duplicate healer invite for " .. tostring(inviteRequest.requester))
        end
        return
    end
    -- Cache the playerInfo
    local info = {
        name = inviteRequest.requester,
        race = inviteRequest.race,
        class = inviteRequest.class,
        level = inviteRequest.level,
        fullName = inviteRequest.fullName,
        lastSeen = inviteRequest.timestamp,
        version = ADDON_VERSION,
        groupId = inviteRequest.groupId or inviteRequest.groupID or inviteRequest.group_id or nil,
        role = inviteRequest.myRole or inviteRequest.role or nil,
        leader = false
    }
    -- Only update the canonical fullName key
    if inviteRequest.fullName then
        self.players[inviteRequest.fullName] = info
    end
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Cached playerInfo for %s from autojoin: Class: %s | Race: %s | Level: %s | FullName: %s", info.name or "", info.class or "", info.race or "", info.level or "", info.fullName or inviteRequest.requester))
    end
    -- Force full UI rebuild of the 'manage' tab after auto-join
    if self.mainFrame and self.mainFrame:IsShown() and self.tabGroup then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: About to call self.tabGroup:SelectTab('manage') after auto-join")
        end
        local success, err = pcall(function()
            self.tabGroup:SelectTab("manage")
        end)
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            if success then
                self:Print("DEBUG: self.tabGroup:SelectTab('manage') called successfully")
            else
                self:Print("ERROR: self.tabGroup:SelectTab('manage') failed: " .. tostring(err))
            end
        end
    else
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: mainFrame or tabGroup not ready for SelectTab('manage') after auto-join")
        end
    end
    local inviteName = inviteRequest.fullName or inviteRequest.requester
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: InviteUnit will use: requester='%s', fullName='%s', chosen='%s'", tostring(inviteRequest.requester), tostring(inviteRequest.fullName), tostring(inviteName)))
    end
    if type(inviteName) == "string" and inviteName ~= "" then
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: About to call InviteUnit('%s')", inviteName))
        end
        local inviteSuccess, inviteError = pcall(function()
            InviteUnit(inviteName)
        end)
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("DEBUG: Returned from InviteUnit")
            if inviteSuccess then
                self:Print(string.format("✓ Auto-invited %s via Grouper Auto-Join", inviteName))
            else
                self:Print(string.format("ERROR: InviteUnit failed for '%s': %s", tostring(inviteName), tostring(inviteError)))
            end
        end
    else
        if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
            self:Print("ERROR: Invalid inviteName for InviteUnit")
        end
    end
end

-- Common message processing function
function Grouper:ProcessReceivedMessage(messageType, data, sender)
    if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        print("DEBUG: Grouper ProcessReceivedMessage fired! Type:", messageType, "Sender:", sender)
        -- The following lines reference variables that may not be in scope; only print if available
        if type(prefix) ~= "nil" then print("DEBUG: Grouper OnAutoJoinRequest fired! Prefix:", prefix, "Sender:", sender, "Distribution:", distribution) end
        if type(groupData) ~= "nil" then print("DEBUG: Grouper SendGroupUpdateViaChannel fired! GroupData:", groupData and groupData.id) end
        print("DEBUG: Grouper SendRequestDataViaChannel fired! Data:", data)
    end
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
    elseif messageType == "GROUP_REMOVE" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Processing GROUP_REMOVE from %s", sender))
        end
        self:HandleGroupRemove(data.data, sender)
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
--[[
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
--]]
function Grouper:ShowConfig()
    AceConfigDialog:Open(ADDON_NAME)
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
-- Overriding some functions to use full player name with realm
local originalHandleDirectGroupUpdate = Grouper.HandleDirectGroupUpdate
function Grouper:HandleDirectGroupUpdate(message, sender)
    -- Prepend realm to sender for consistency
    local fullSender = GetFullPlayerName(sender)
    return originalHandleDirectGroupUpdate(self, message, fullSender)
end

local originalHandleDirectGroupRemove = Grouper.HandleDirectGroupRemove
function Grouper:HandleDirectGroupRemove(message, sender)
    -- Prepend realm to sender for consistency
    local fullSender = GetFullPlayerName(sender)
    return originalHandleDirectGroupRemove(self, message, fullSender)
end

local originalProcessReceivedMessage = Grouper.ProcessReceivedMessage
function Grouper:ProcessReceivedMessage(messageType, data, sender)
    -- Prepend realm to sender for consistency
    local fullSender = GetFullPlayerName(sender)
    return originalProcessReceivedMessage(self, messageType, data, fullSender)
end

local originalSendComm = Grouper.SendComm
function Grouper:SendComm(messageType, data, distribution, target, priority)
    -- For consistency, ensure target is always a full player name with realm
    if target and type(target) == "string" then
        target = GetFullPlayerName(target)
    end
    return originalSendComm(self, messageType, data, distribution, target, priority)
end

-- Send GROUP_REMOVE message via direct channel
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