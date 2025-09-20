function Grouper:OnPartyChanged(event)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Group changed event: %s", event or "unknown"))
    end
    
    -- Get current group information with Classic Era compatibility
    inParty = IsInPartyGroup()
    inRaid = IsInRaidGroup()
    isLeader = IsGroupLeader()
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Party: %s, Raid: %s, Leader: %s", 
            tostring(inParty), tostring(inRaid), tostring(isLeader)))
    end
    
    -- Update our current group status
    partySize = GetGroupSize()
    
    self.currentGroupInfo = {
        inParty = inParty,
        inRaid = inRaid,
        isLeader = isLeader,
        partySize = partySize,
        timestamp = time()
    }
    
    -- If we're no longer in a group, we can create new groups
    -- If we joined a group, we might need to remove our posted groups
    if inParty or inRaid then
        -- We're in a group - consider removing any groups we posted as LFG
        self:HandleJoinedGroup()
    else
        -- We left a group - we can post new groups again
        self:HandleLeftGroup()
    end
    
    -- Disable presence broadcast to prevent protected function issues: self:BroadcastPresence()
    
    -- Repopulate group data using leader's cache logic
    if IsGroupLeader() then
        -- If we're the leader, ensure our cache is used to repopulate
        if self.groups then
            for _, group in pairs(self.groups) do
                if group.leader == UnitName("player") then
                    self:CreateGroup({
                        title = group.title,
                        description = group.description,
                        type = group.type,
                        minLevel = group.minLevel,
                        maxLevel = group.maxLevel,
                        currentSize = group.currentSize,
                        maxSize = group.maxSize,
                        location = group.location,
                        dungeons = group.dungeons
                    })
                end
            end
        end
    end
    -- Refresh UI if it's open
    if self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshGroupList()
    end
end

-- Classic Era API Compatibility Functions
function GetGroupSize()
    -- Returns number of people in your group (including yourself)
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return GetNumRaidMembers()
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        return GetNumPartyMembers()
    else
        return 0 -- Solo
    end
end

function IsInGroup()
    return GetGroupSize() > 0
end

function IsInRaidGroup()
    return GetNumRaidMembers and GetNumRaidMembers() > 0 or false
end

function IsInPartyGroup()
    return GetNumPartyMembers and GetNumPartyMembers() > 0 or false
end

function IsGroupLeader()
    if IsInRaidGroup() then
        return IsRaidLeader and IsRaidLeader() or false
    elseif IsInPartyGroup() then
        return IsPartyLeader and IsPartyLeader() or false
    else
        return false
    end
end

-- Handle party invite requests for auto-accept functionality
function Grouper:OnPartyInviteRequest(event, inviter)
    if not self.db.profile.autoJoin.enabled then
        return
    end
        -- Strip realm name from inviter for display
    local inviterName = self:StripRealmName(inviter)
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Received party invite request from %s", inviterName))
    end
    if self.db.profile.autoJoin.autoAccept then
        -- Auto-accept the invite
        AcceptGroup()
        self:Print(string.format("Auto-accepted invite from %s", inviterName))
    else
        -- Show popup for confirmation (WoW will show default invite popup)
        self:Print(string.format("Invite request from %s (check invite popup)", inviterName))
    end
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
        return self:SendGroupUpdateViaChannel(data)
    elseif messageType == "GROUP_REMOVE" and (distribution == "CHANNEL" or not distribution) then
        return self:SendGroupRemoveViaChannel(data)
    elseif messageType == "REQUEST_DATA" and (distribution == "CHANNEL" or not distribution) then
        return self:SendRequestDataViaChannel(data)
    end
    
    -- For WHISPER and other distributions, use standard AceComm which works fine
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ SendComm called with messageType='%s', distribution='%s'", messageType, distribution or "default"))
    end
    
    local message = {
        type = messageType,
        sender = UnitName("player"),
        timestamp = time(),
        version = ADDON_VERSION,
        data = data
    }
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Sending %s message via AceComm", messageType))
    end
    
    -- Use AceComm for all communication with appropriate priority
    local commPriority = priority or "NORMAL"
    if messageType == "TEST" then
        commPriority = "ALERT"  -- Use ALERT priority for immediate test message delivery
    end
    local distributionType = distribution or "CHANNEL"  -- Default to CHANNEL for server-wide communication
    local commTarget = target
    
    -- For server-wide broadcasts, use CHANNEL distribution with the Grouper channel number
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
        commTarget = channelIndex  -- Use the channel number for AceComm
    end
    
    local success, errorMsg = pcall(function()
        local prefix = "GRPR_" .. messageType
        -- Shorten prefixes to fit 16-char limit
        if messageType == "GROUP_UPDATE" then
            prefix = "GRPR_GRP_UPD"
        elseif messageType == "GROUP_REMOVE" then
            prefix = "GRPR_GRP_RMV"
        end
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ⚡ Sending AceComm with prefix='%s' to channel %d", prefix, commTarget))
        end
        self:SendCommMessage(prefix, self:Serialize(message), distributionType, commTarget, commPriority)
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
    -- Use direct channel messaging like the working direct channel test
    local channelIndex = self:GetGrouperChannelIndex()
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
    
    -- Create compact encoded message: GRPR_GROUP_UPDATE:id:title:typeId:dungeonId:currentSize:maxSize:location:timestamp:leader:roleId
    local message = string.format("GRPR_GROUP_UPDATE:%s:%s:%d:%d:%d:%d:%s:%d:%s:%d",
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
        self:Print(string.format("DEBUG: ⚡ Sending encoded GROUP_UPDATE via direct channel %d: %s", channelIndex, message))
    end
    
    -- Send via direct channel message (same method as working direct channel test)
    SendChatMessage(message, "CHANNEL", nil, channelIndex)
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: ✓ GROUP_UPDATE sent via direct channel")
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
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: ⚡ Sending REQUEST_DATA via direct channel %d: %s", channelIndex, message))
    end
    
    -- Send via direct channel message
    SendChatMessage(message, "CHANNEL", nil, channelIndex)
    
    if self.db.profile.debug.enabled then
        self:Print("DEBUG: ✓ REQUEST_DATA sent via direct channel")
    end
    
    return true
end

function Grouper:HandleDirectGroupUpdate(message, sender)
    -- Parse: GRPR_GROUP_UPDATE:id:title:typeId:dungeonId:currentSize:maxSize:location:timestamp:leader:roleId
    local parts = {string.split(":", message)}
    if #parts < 11 then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Invalid direct GROUP_UPDATE format from %s (got %d parts, expected 11)", sender, #parts))
        end
        return
    end
    
    local typeId = tonumber(parts[4]) or 1
    local dungeonId = tonumber(parts[5]) or 0
    local roleId = tonumber(parts[11]) or 3
    
    -- Decode type information
    local typeNames = {
        [1] = "dungeon",
        [2] = "raid", 
        [3] = "quest",
        [4] = "pvp",
        [5] = "other"
    }
    local groupType = typeNames[typeId] or "dungeon"
    
    -- Reconstruct level ranges from DUNGEONS table
    local minLevel = 1
    local maxLevel = 60
    local dungeonName = ""
    
    if dungeonId > 0 and dungeonId <= #DUNGEONS then
        local dungeon = DUNGEONS[dungeonId]
        minLevel = dungeon.minLevel
        maxLevel = dungeon.maxLevel
        dungeonName = dungeon.name
    elseif groupType == "dungeon" then
        -- Default dungeon level range
        minLevel = 13
        maxLevel = 18
    elseif groupType == "raid" then
        -- Default raid level range
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
        dungeons = dungeonId > 0 and {[dungeonName] = true} or {},
        members = {
            [parts[10]] = {
                name = parts[10],
                role = leaderRole
            }
        }
    }
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing encoded GROUP_UPDATE: %s (%s) type=%s, dungeon=%s, levels=%d-%d from %s", 
            groupData.id, groupData.title, groupData.type, dungeonName, minLevel, maxLevel, sender))
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
    
    -- Normalize names for comparison (remove server names)
    local senderName = sender:match("^([^-]+)") or sender  -- Get name before first dash
    local groupLeaderName = group and (group.leader:match("^([^-]+)") or group.leader)
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Name comparison - senderName='%s', groupLeaderName='%s'", 
            senderName, groupLeaderName or "nil"))
    end
    
    if group and groupLeaderName == senderName then
        self.groups[groupId] = nil
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ Removed group %s by leader %s", groupId, senderName))
        end
        -- Refresh the UI to reflect the removal
        self:RefreshGroupList()
    else
        if self.db.profile.debug.enabled then
            if not group then
                self:Print(string.format("DEBUG: ✗ Cannot remove - group %s not found", groupId))
            else
                self:Print(string.format("DEBUG: ✗ Cannot remove - %s is not leader of group %s (leader: %s)", 
                    senderName, groupId, groupLeaderName))
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
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing REQUEST_DATA from %s, sending our groups via WHISPER", requester))
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
                
                -- Use AceComm format for addon whisper (system message, no chat tab)
                -- This will be processed by OnCommReceived and use HandleGroupUpdate
                local message = {
                    type = "GROUP_UPDATE",
                    sender = UnitName("player"),
                    timestamp = time(),
                    version = ADDON_VERSION,
                    data = group
                }
                
                local success = self:SendCommMessage("GRPR_GRP_UPD", self:Serialize(message), "WHISPER", requester, "NORMAL")
                
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
    
    -- Check for direct test messages
    if message:match("^GRPR_DIRECT_TEST:") then
        local testSender = message:match("^GRPR_DIRECT_TEST:(.+)")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL TEST from %s (sent by %s)", sender, testSender))
        end
        return
    end
    
    -- Check for direct GROUP_UPDATE messages
    if message:match("^GRPR_GROUP_UPDATE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_UPDATE from %s", sender))
        end
        self:HandleDirectGroupUpdate(message, sender)
        return
    end
    
    -- Check for direct GROUP_REMOVE messages
    if message:match("^GRPR_GROUP_REMOVE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_REMOVE from %s", sender))
        end
        self:HandleDirectGroupRemove(message, sender)
        return
    end
    
    -- Check for direct REQUEST_DATA messages
    if message:match("^GRPR_REQUEST_DATA:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL REQUEST_DATA from %s", sender))
        end
        self:HandleDirectRequestData(message, sender)
        return
    end
    
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
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: OnCommReceived called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    end
    
    -- Add specific debug for GRPR_GRP_UPD
    if prefix == "GRPR_GRP_UPD" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: 🎯 GRPR_GRP_UPD message received from %s!", sender))
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
    if prefix == "GRPR_GRP_UPD" then
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
    self:Print(string.format("DEBUG: OnAutoJoinRequest called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    
    -- Always auto-accept: deserialize and invite
    local deserializeSuccess, deserializedMessage = self:Deserialize(message)
    if not deserializeSuccess or not deserializedMessage then
        self:Print(string.format("DEBUG: Failed to deserialize auto-join request from %s - success: %s", sender, tostring(deserializeSuccess)))
        return
    end
    if deserializedMessage.type ~= "INVITE_REQUEST" or not deserializedMessage.requester then
        self:Print(string.format("DEBUG: Invalid auto-join request format - type: %s, requester: %s", tostring(deserializedMessage.type), tostring(deserializedMessage.requester)))
        return
    end
    local requester = sender
    -- Cache the playerInfo if present
    if deserializedMessage.playerInfo and type(deserializedMessage.playerInfo) == "table" then
        local info = deserializedMessage.playerInfo
        -- Ensure lastSeen and version are set for cache compatibility
        info.lastSeen = time()
        info.version = deserializedMessage.version or ADDON_VERSION
        self.players[requester] = info
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Cached playerInfo for %s from autojoin: %s | Class: %s | Race: %s | Level: %s | FullName: %s", requester, info.name or "", info.class or "", info.race or "", info.level or "", info.fullName or requester))
        end
        -- Refresh party frame if open
        if self.mainFrame and self.mainFrame:IsShown() then
            self:RefreshGroupList()
        end
    end
    if InviteUnit then
        InviteUnit(requester)
        self:Print(string.format("✓ Auto-invited %s via Grouper Auto-Join", requester))
    else
        self:Print("ERROR: InviteUnit function not available")
        return -- Exit here after showing popup
    end
end

-- Common message processing function
function Grouper:ProcessReceivedMessage(messageType, data, sender)
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
    
    -- Normalize names for comparison (remove server names)
    local senderName = sender:match("^([^-]+)") or sender  -- Get name before first dash
    local groupLeaderName = group and (group.leader:match("^([^-]+)") or group.leader)
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Name comparison - senderName='%s', groupLeaderName='%s'", 
            senderName, groupLeaderName or "nil"))
    end
    
    if group and groupLeaderName == senderName then
        self.groups[groupId] = nil
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ Removed group %s by leader %s", groupId, senderName))
        end
        -- Refresh the UI to reflect the removal
        self:RefreshGroupList()
    else
        if self.db.profile.debug.enabled then
            if not group then
                self:Print(string.format("DEBUG: ✗ Cannot remove - group %s not found", groupId))
            else
                self:Print(string.format("DEBUG: ✗ Cannot remove - %s is not leader of group %s (leader: %s)", 
                    senderName, groupId, groupLeaderName))
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
    
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Processing REQUEST_DATA from %s, sending our groups via WHISPER", requester))
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
                
                -- Use AceComm format for addon whisper (system message, no chat tab)
                -- This will be processed by OnCommReceived and use HandleGroupUpdate
                local message = {
                    type = "GROUP_UPDATE",
                    sender = UnitName("player"),
                    timestamp = time(),
                    version = ADDON_VERSION,
                    data = group
                }
                
                local success = self:SendCommMessage("GRPR_GRP_UPD", self:Serialize(message), "WHISPER", requester, "NORMAL")
                
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
    
    -- Check for direct test messages
    if message:match("^GRPR_DIRECT_TEST:") then
        local testSender = message:match("^GRPR_DIRECT_TEST:(.+)")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL TEST from %s (sent by %s)", sender, testSender))
        end
        return
    end
    
    -- Check for direct GROUP_UPDATE messages
    if message:match("^GRPR_GROUP_UPDATE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_UPDATE from %s", sender))
        end
        self:HandleDirectGroupUpdate(message, sender)
        return
    end
    
    -- Check for direct GROUP_REMOVE messages
    if message:match("^GRPR_GROUP_REMOVE:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL GROUP_REMOVE from %s", sender))
        end
        self:HandleDirectGroupRemove(message, sender)
        return
    end
    
    -- Check for direct REQUEST_DATA messages
    if message:match("^GRPR_REQUEST_DATA:") then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: ✓ RECEIVED DIRECT CHANNEL REQUEST_DATA from %s", sender))
        end
        self:HandleDirectRequestData(message, sender)
        return
    end
    
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
    if self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: OnCommReceived called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    end
    
    -- Add specific debug for GRPR_GRP_UPD
    if prefix == "GRPR_GRP_UPD" then
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: 🎯 GRPR_GRP_UPD message received from %s!", sender))
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
    if prefix == "GRPR_GRP_UPD" then
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
    self:Print(string.format("DEBUG: OnAutoJoinRequest called - prefix: %s, sender: %s, distribution: %s", prefix, sender, distribution))
    
    -- Always auto-accept: deserialize and invite
    local deserializeSuccess, deserializedMessage = self:Deserialize(message)
    if not deserializeSuccess or not deserializedMessage then
        self:Print(string.format("DEBUG: Failed to deserialize auto-join request from %s - success: %s", sender, tostring(deserializeSuccess)))
        return
    end
    if deserializedMessage.type ~= "INVITE_REQUEST" or not deserializedMessage.requester then
        self:Print(string.format("DEBUG: Invalid auto-join request format - type: %s, requester: %s", tostring(deserializedMessage.type), tostring(deserializedMessage.requester)))
        return
    end
    local requester = sender
    -- Cache the playerInfo if present
    if deserializedMessage.playerInfo and type(deserializedMessage.playerInfo) == "table" then
        local info = deserializedMessage.playerInfo
        -- Ensure lastSeen and version are set for cache compatibility
        info.lastSeen = time()
        info.version = deserializedMessage.version or ADDON_VERSION
        self.players[requester] = info
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Cached playerInfo for %s from autojoin: %s | Class: %s | Race: %s | Level: %s | FullName: %s", requester, info.name or "", info.class or "", info.race or "", info.level or "", info.fullName or requester))
        end
        -- Refresh party frame if open
        if self.mainFrame and self.mainFrame:IsShown() then
            self:RefreshGroupList()
        end
    end
    if InviteUnit then
        InviteUnit(requester)
        self:Print(string.format("✓ Auto-invited %s via Grouper Auto-Join", requester))
    else
        self:Print("ERROR: InviteUnit function not available")
        return -- Exit here after showing popup
    end
end

-- Common message processing function
function Grouper:ProcessReceivedMessage(messageType, data, sender)
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

