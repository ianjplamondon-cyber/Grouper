-- Normalize a full player name for robust comparison (removes spaces from realm part only)
function Grouper.NormalizeFullPlayerName(name)
    if not name then return "" end
    if name:find("-") then
        local base, r = name:match("^(.-)%-(.+)$")
        if base and r then
            r = r:gsub("%s", "")
            return base .. "-" .. r
        end
        return name
    end
    return name
end
-- Debug command to list all cached groups
Grouper:RegisterChatCommand("groupercg", function()
    local groups = Grouper.groups
    local count = 0
    for groupId, group in pairs(groups) do
        local memberRoles = {}
        if group.members then
            for _, member in ipairs(group.members) do
                table.insert(memberRoles, string.format("%s:%s", member.name or "?", member.role or "None"))
            end
        end
        Grouper:Print(string.format("Group Cache: ID: %s | Title: %s | Leader: %s | Type: %s | Members: %s | Roles: [%s]", groupId, group.title or "", group.leader or "", group.type or "", group.members and #group.members or 0, table.concat(memberRoles, ", ")))
        count = count + 1
    end
    if count == 0 then
        Grouper:Print("No groups cached.")
    end
end)

-- Debug command to list all dungeons in all groups
Grouper:RegisterChatCommand("groupercd", function()
    local groups = Grouper.groups
    local count = 0
    for groupId, group in pairs(groups) do
        Grouper:Print(string.format("Group ID: %s | Title: %s", groupId, group.title or ""))
        if group.dungeons and next(group.dungeons) then
            for name, dungeon in pairs(group.dungeons) do
                if type(dungeon) == "table" then
                    Grouper:Print(string.format("  Dungeon: %s | ID: %s | MinLevel: %s | MaxLevel: %s | Type: %s | Faction: %s", dungeon.name or name, tostring(dungeon.id), tostring(dungeon.minLevel), tostring(dungeon.maxLevel), tostring(dungeon.type), tostring(dungeon.faction)))
                else
                    Grouper:Print(string.format("  Dungeon: %s | Data: %s", name, tostring(dungeon)))
                end
            end
        else
            Grouper:Print("  No dungeons in this group.")
        end
        count = count + 1
    end
    if count == 0 then
        Grouper:Print("No groups cached.")
    end
end)


-- Force clear all non-leader members from cache
function Grouper:ForceClearNonLeaderCache()
    local leaderName = GetFullPlayerName(UnitName("player"))
    local removed = false
    for name, _ in pairs(self.players) do
        if name ~= leaderName then
            self.players[name] = nil
            removed = true
            if self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
                self:Print("DEBUG: [ForceClearNonLeaderCache] Removed " .. name .. " from cache.")
            end
        end
    end
    if not removed and self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled then
        self:Print("DEBUG: [ForceClearNonLeaderCache] No non-leader members found in cache.")
    end
end
-- Data broker for minimap
dataObj = {
    type = "data source",
    text = "Grouper",
    icon = "Interface\\AddOns\\Grouper\\Textures\\GrouperIcon.tga",
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

-- Helper function for debug checking
function Grouper:IsDebugEnabled()
    return self.db and self.db.profile and self.db.profile.debug and self.db.profile.debug.enabled
end

function Grouper:GenerateGroupID()
    return string.format("%s_%d", UnitName("player"), time())
end


-- Handles cache updates for non-group leaders when joining or leaving groups
-- action: "join" or "leave"
-- playerName: full name (e.g., "Pickyminer-Old Blanchy")
-- groupId: id of the group
function Grouper:HandleNonLeaderCache(action, playerName, groupId)
    -- Extract short name from full name
    local shortName = playerName:match("^([^%-]+)") or playerName
    local keys = { shortName, playerName }
    if action == "join" then
        for _, key in ipairs(keys) do
            if self.players[key] then
                self.players[key].groupId = groupId
                self.players[key].lastSeen = time()
                if self:IsDebugEnabled() then
                    self:Print("DEBUG: [HandleNonLeaderCache] Updated " .. key .. " in cache with groupId " .. tostring(groupId))
                end
            end
        end
    elseif action == "leave" then
        for _, key in ipairs(keys) do
            if self.players[key] then
                local oldGroupId = self.players[key].groupId
                self.players[key].groupId = nil
                if self:IsDebugEnabled() then
                    self:Print("DEBUG: [HandleNonLeaderCache] Cleared groupId (was " .. tostring(oldGroupId) .. ") from " .. key .. " in cache.")
                end
            end
        end
        -- Remove player from group members list
        if self.groups[groupId] then
            self.groups[groupId] = nil
            if self:IsDebugEnabled() then
                self:Print("DEBUG: [HandleNonLeaderCache] Removed group " .. tostring(groupId) .. " from group cache (non-leader left)")
            end
        end
    end
end

function Grouper:CleanupOldGroups()
    local currentTime = time()
    local expireTime = 3600 -- 1 hour
    local removedCount = 0
    
    for id, group in pairs(self.groups) do
        if currentTime - group.timestamp > expireTime then
            if self.db.profile.debug.enabled then
                self:Print(string.format("DEBUG: Expired group: %s (age: %d seconds)", group.title or "Unknown", currentTime - group.timestamp))
            end
            self.groups[id] = nil
            removedCount = removedCount + 1
        end
    end
    
    -- Cleanup offline players
    local playerExpireTime = expireTime * 2 -- Keep player data longer than groups
    for name, player in pairs(self.players) do
        if currentTime - player.lastSeen > playerExpireTime then
            self.players[name] = nil
        end
    end
    
    if removedCount > 0 and self.db.profile.debug.enabled then
        self:Print(string.format("DEBUG: Cleaned up %d expired groups", removedCount))
    end
end

function Grouper:CleanupOldAceCommChunks()
    local currentTime = time()
    local expireTime = 300 -- 5 minutes
    
    -- Clean up AceComm chunks
    if self.aceCommChunks then
        for messageId, messageData in pairs(self.aceCommChunks) do
            if currentTime - messageData.timestamp > expireTime then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Cleaning up expired AceComm chunks for message %s", messageId))
                end
                self.aceCommChunks[messageId] = nil
            end
        end
    end
    
    -- Clean up legacy chunks
    if self.legacyChunks then
        for messageId, messageData in pairs(self.legacyChunks) do
            if currentTime - messageData.timestamp > expireTime then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Cleaning up expired legacy chunks for message %s", messageId))
                end
                self.legacyChunks[messageId] = nil
            end
        end
    end
    
    -- Clean up sent chunks (for resend capability)
    if self.sentChunks then
        for messageId, messageData in pairs(self.sentChunks) do
            if currentTime - messageData.timestamp > expireTime then
                if self.db.profile.debug.enabled then
                    self:Print(string.format("DEBUG: Cleaning up expired sent chunks for message %s", messageId))
                end
                self.sentChunks[messageId] = nil
            end
        end
    end
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
        self:EnsureChannelJoined()
    elseif command == "status" then
        local channelIndex = GetChannelName(ADDON_CHANNEL)
        local actuallyInChannel = channelIndex > 0
        self:Print(string.format("Groups: %d, Players: %d", self:CountGroups(), #self.players))
        self:Print(string.format("My Channel Status: %s (Index: %d)", 
            actuallyInChannel and "Connected" or "Disconnected", channelIndex))
        self:Print(string.format("Cached Channel: %s", 
            self.grouperChannelNumber and tostring(self.grouperChannelNumber) or "None"))
        self:Print(string.format("Channel Name: '%s'", ADDON_CHANNEL))
        self:Print(string.format("Internal Status: %s", 
            self.channelJoined and "Connected" or "Disconnected"))
        self:Print(string.format("Debug Mode: %s", 
            self.db.profile.debug.enabled and "ON" or "OFF"))
        
        -- Validate and fix cache
        if self.grouperChannelNumber and channelIndex ~= self.grouperChannelNumber then
            self:Print("WARNING: Cached channel number doesn't match current!")
            self.grouperChannelNumber = channelIndex -- Fix it
        elseif not self.grouperChannelNumber and channelIndex > 0 then
            self:Print("Initializing missing channel cache...")
            self.grouperChannelNumber = channelIndex -- Initialize it
        end
        
        -- Auto-fix if there's a mismatch
        if actuallyInChannel and not self.channelJoined then
            self:Print("Fixing channel status...")
            self.channelJoined = true
        elseif not actuallyInChannel and self.channelJoined then
            self:Print("Reconnecting to channel...")
            self.channelJoined = false
            self:EnsureChannelJoined()
        end
    elseif command == "test" then
        self:Print("Testing AceComm communication...")
        
        local channelIndex = self:GetGrouperChannelIndex()
        if channelIndex <= 0 then
            self:Print("✗ Not in Grouper channel - cannot test AceComm")
            return
        end
        
        self:Print(string.format("Using Grouper channel %d for tests", channelIndex))
        
        -- Test 1: Simple AceComm message
        local testData1 = {message = "Simple test", sender = UnitName("player"), timestamp = time()}
        local success1, err1 = pcall(function()
            self:SendCommMessage("GROUPER_TEST", self:Serialize(testData1), "CHANNEL", channelIndex, "ALERT")
        end)
        self:Print(string.format("Simple AceComm test: %s %s", success1 and "SUCCESS" or "FAILED", err1 or ""))
        
        -- Test 2: Our SendComm protocol
        local success2, err2 = pcall(function()
            self:SendComm("TEST", {message = "Hello from " .. UnitName("player")})
        end)
        self:Print(string.format("SendComm protocol test: %s %s", success2 and "SUCCESS" or "FAILED", err2 or ""))
        
        -- Test 3: Group update message (skip to avoid creating fake groups)
        -- local success3, err3 = pcall(function()
        --     self:SendComm("GROUP_UPDATE", {test = true, sender = UnitName("player")})
        -- end)
        -- self:Print(string.format("Group update test: %s %s", success3 and "SUCCESS" or "FAILED", err3 or ""))
        self:Print("Group update test: SKIPPED (to avoid fake groups)")
        
        -- Test 4: Direct GRPR_GRP_UPD test to verify registration
        local success4, err4 = pcall(function()
            local testMessage = {type = "GROUP_UPDATE", sender = UnitName("player"), timestamp = time(), version = ADDON_VERSION, data = {test = true}}
            self:SendCommMessage("GRPR_GRP_UPD", self:Serialize(testMessage), "CHANNEL", channelIndex, "ALERT")
        end)
        self:Print(string.format("Direct GRPR_GRP_UPD test: %s %s", success4 and "SUCCESS" or "FAILED", err4 or ""))
        
        -- Test 5: WHISPER test to self
        local success5, err5 = pcall(function()
            self:SendComm("TEST", {message = "WHISPER test from " .. UnitName("player")}, "WHISPER", UnitName("player"), "NORMAL")
        end)
        self:Print(string.format("WHISPER test to self: %s %s", success5 and "SUCCESS" or "FAILED", err5 or ""))
        
        -- Test 6: Direct channel test (visible)
        local success4, err4 = pcall(function()
            SendChatMessage("GRPR_DIRECT_TEST:" .. UnitName("player"), "CHANNEL", nil, channelIndex)
        end)
        self:Print(string.format("Direct channel test: %s %s", success4 and "SUCCESS" or "FAILED", err4 or ""))
        
        self:Print("First 3 tests use AceComm, Test 4 uses direct channel (visible)")
        self:Print("If Test 4 works but others don't, AceComm has an issue with CHANNEL distribution")
    elseif command == "debug" then
        if args[2] and args[2]:lower() == "off" then
            self.db.profile.debug.enabled = false
            self:Print("Debug mode disabled")
        else
            self.db.profile.debug.enabled = true
            self:Print("Debug mode enabled")
        end
        self:Print(string.format("Debug is now %s", self.db.profile.debug.enabled and "ON" or "OFF"))
    elseif command == "whisper" then
        if not args[2] then
            self:Print("Usage: /grouper whisper <playername>")
            self:Print("Sends a test whisper to verify WHISPER communication works")
            return
        end
        
        local targetPlayer = args[2]
        self:Print(string.format("Testing WHISPER communication to %s...", targetPlayer))
        
        local success, err = pcall(function()
            self:SendComm("TEST", {message = "WHISPER test from " .. UnitName("player")}, "WHISPER", targetPlayer, "NORMAL")
        end)
        self:Print(string.format("WHISPER test to %s: %s %s", targetPlayer, success and "SUCCESS" or "FAILED", err or ""))
    elseif command == "presence" then
        if args[2] and args[2]:lower() == "off" then
            self.db.profile.disablePresence = true
            self:Print("Presence broadcasting disabled")
        else
            self.db.profile.disablePresence = false
            self:Print("Presence broadcasting enabled")
        end
        self:Print(string.format("Presence broadcasting is now %s", self.db.profile.disablePresence and "OFF" or "ON"))
    elseif command == "chunks" then
        -- Debug command to show chunk status
        self:Print("Chunk status:")
        
        if self.legacyChunks then
            local count = 0
            for messageId, messageData in pairs(self.legacyChunks) do
                count = count + 1
                local receivedChunks = 0
                for i = 1, messageData.totalChunks do
                    if messageData.chunks[i] then
                        receivedChunks = receivedChunks + 1
                    end
                end
                local age = time() - messageData.timestamp
                self:Print(string.format("  Receiving %s: %d/%d chunks from %s (age: %ds)", 
                    messageId, receivedChunks, messageData.totalChunks, messageData.sender, age))
            end
            if count == 0 then
                self:Print("  No pending received chunks")
            end
        else
            self:Print("  No pending received chunks")
        end
        
        if self.sentChunks then
            local count = 0
            for messageId, messageData in pairs(self.sentChunks) do
                count = count + 1
                local age = time() - messageData.timestamp
                self:Print(string.format("  Sent %s: %d chunks (%s, age: %ds)", 
                    messageId, #messageData.chunks, messageData.messageType, age))
            end
            if count == 0 then
                self:Print("  No pending sent chunks")
            end
        else
            self:Print("  No pending sent chunks")
        end
    elseif command == "request" then
        self:Print("Requesting group data from other players...")
        if self.db.profile.debug.enabled then
            self:Print(string.format("DEBUG: Manual group data request (current groups: %d)", self:CountGroups()))
        end
        self:SendComm("REQUEST_DATA", {type = "request", timestamp = time()})
    elseif command == "list" then
        self:Print(string.format("Current groups (%d):", self:CountGroups()))
        for id, group in pairs(self.groups) do
            local age = math.floor((time() - group.timestamp) / 60)
            self:Print(string.format("  %s: %s (Leader: %s, Age: %d min)", id, group.title, group.leader, age))
        end
        if self:CountGroups() == 0 then
            self:Print("  No groups currently stored")
        end
    elseif command == "players" then
        local playerCount = 0
        for _ in pairs(self.players) do
            playerCount = playerCount + 1
        end
        self:Print(string.format("Known players (%d):", playerCount))
        for name, player in pairs(self.players) do
            local lastSeen = math.floor((time() - player.lastSeen) / 60)
            self:Print(string.format("  %s (Version: %s, Last seen: %d min ago)", name, player.version or "unknown", lastSeen))
        end
        if playerCount == 0 then
            self:Print("  No players currently known")
        end
    elseif command == "position" then
        local pos = self.db.profile.ui.position
        self:Print(string.format("Saved window position: %s %s %.0f %.0f", 
            pos.point or "nil", pos.relativePoint or "nil", pos.xOfs or 0, pos.yOfs or 0))
        if self.mainFrame and self.mainFrame.frame then
            local point, relativeTo, relativePoint, xOfs, yOfs = self.mainFrame.frame:GetPoint()
            self:Print(string.format("Current window position: %s %s %.0f %.0f", 
                point or "nil", relativePoint or "nil", xOfs or 0, yOfs or 0))
        else
            self:Print("Window is not currently open")
        end
    elseif command == "savepos" then
        if self.mainFrame and self.mainFrame.frame then
            self:SaveWindowPosition()
            self:Print("Window position saved manually")
        else
            self:Print("Window must be open to save position")
        end
    elseif command == "autojoin" then
        local subcommand = args[2] and args[2]:lower()
        if subcommand == "status" then
            self:Print(string.format("Auto-Join: %s", 
                self.db.profile.autoJoin.enabled and "ENABLED" or "DISABLED"))
            self:Print(string.format("Auto-Accept Invites: %s", 
                self.db.profile.autoJoin.autoAccept and "AUTO-ACCEPT" or "MANUAL ACCEPT"))
            self:Print("Auto-Join uses direct invite requests (no whispers needed)")
        elseif subcommand == "toggle" then
            self.db.profile.autoJoin.enabled = not self.db.profile.autoJoin.enabled
            self:Print(string.format("Auto-Join %s", 
                self.db.profile.autoJoin.enabled and "ENABLED" or "DISABLED"))
            
            -- Auto-enable debug mode when enabling auto-join for troubleshooting
            if self.db.profile.autoJoin.enabled and not self.db.profile.debug.enabled then
                self.db.profile.debug.enabled = true
                self:Print("DEBUG: Enabled debug mode for troubleshooting")
            end
        elseif subcommand == "accept" then
            self.db.profile.autoJoin.autoAccept = not self.db.profile.autoJoin.autoAccept
            self:Print(string.format("Auto-Accept Invites %s", 
                self.db.profile.autoJoin.autoAccept and "ENABLED" or "DISABLED (will show popup)"))
        elseif subcommand == "test" then
            local targetPlayer = args[3]
            if not targetPlayer then
                self:Print("Usage: /grouper autojoin test <playername>")
                return
            end
            self:Print(string.format("Testing invite request to %s", targetPlayer))
            
            local success, errorMessage = pcall(function()
                if RequestInviteFromUnit then
                    RequestInviteFromUnit(targetPlayer)
                    self:Print("DEBUG: Used RequestInviteFromUnit")
                elseif C_PartyInfo and C_PartyInfo.RequestInviteFromUnit then
                    C_PartyInfo.RequestInviteFromUnit(targetPlayer)
                    self:Print("DEBUG: Used C_PartyInfo.RequestInviteFromUnit")
                else
                    SendChatMessage("Test invite request from Grouper Auto-Join", "WHISPER", nil, targetPlayer)
                    self:Print("DEBUG: Used whisper fallback")
                end
            end)
            
            if success then
                self:Print(string.format("✓ Test invite request sent to %s", targetPlayer))
            else
                self:Print(string.format("✗ Test failed: %s", errorMessage or "Unknown error"))
            end
        else
            self:Print("Auto-Join Commands:")
            self:Print("  /grouper autojoin status - Show auto-join status")
            self:Print("  /grouper autojoin toggle - Toggle auto-join on/off")
            self:Print("  /grouper autojoin accept - Toggle auto-accept invites")
            self:Print("  /grouper autojoin test <player> - Test invite request")
        end
    else
        self:Print("Usage: /grouper [show|config|join|status|test|debug|presence|chunks|request|list|players|position|savepos|autojoin]")
        self:Print("Use '/grouper autojoin' for Auto-Join commands")
    end
end

-- Slash command to print group leader info
SLASH_GROUPERCL1 = "/groupercl"
function SlashCmdList.GROUPERCL(msg)
    local foundLeader = false
    for id, group in pairs(Grouper.groups) do
        if group.leader then
            Grouper:Print("Group ID: " .. tostring(id) .. " | Leader: " .. tostring(group.leader))
            foundLeader = true
        end
    end
    if not foundLeader then
        Grouper:Print("No group leader information found.")
    end
end

-- Register slash command to show current player's cached data (place at end of file)
Grouper:RegisterChatCommand("groupercp", function()
    Grouper:Print("==== Grouper Debug Cache Print ====")
    -- Print self.player
    if Grouper.player then
        Grouper:Print("self.player:")
        for k, v in pairs(Grouper.player) do
            Grouper:Print(string.format("  %s: %s", tostring(k), tostring(v)))
        end
    else
        Grouper:Print("self.player: nil")
    end

    -- Print self.players
    if Grouper.players then
        Grouper:Print("self.players:")
        local count = 0
        for name, info in pairs(Grouper.players) do
            local leaderStr = (info.leader == true) and "yes" or "no"
            Grouper:Print(string.format(
                "  Name: %s | Class: %s | Race: %s | Level: %s | FullName: %s | GroupID: %s | Leader: %s | Role: %s",
                info.name or name,
                info.class or "",
                info.race or "",
                info.level or "",
                info.fullName or name,
                info.groupId or "None",
                leaderStr,
                info.role or "None"
            ))
            count = count + 1
        end
        if count == 0 then
            Grouper:Print("  No player data cached in self.players.")
        end
    else
        Grouper:Print("self.players: nil")
    end

    -- Print self.playerInfo (if present)
    if Grouper.playerInfo then
        Grouper:Print("self.playerInfo:")
        for k, v in pairs(Grouper.playerInfo) do
            Grouper:Print(string.format("  %s: %s", tostring(k), tostring(v)))
        end
    else
        Grouper:Print("self.playerInfo: nil")
    end
    Grouper:Print("==== End Grouper Debug Cache Print ====")
end)

-- Slash command to test AceComm WHISPER delivery
SLASH_GROUPERTESTCOMM1 = "/groupertestcomm"
function SlashCmdList.GROUPERTESTCOMM(msg)
    local target = msg:match("^%s*(.-)%s*$")
    if not target or target == "" then
        Grouper:Print("Usage: /grouper testcomm <player>")
        return
    end
    Grouper:Print("DEBUG: Sending test AceComm WHISPER to " .. target)
    local testMessage = {
        type = "TEST",
        sender = UnitName("player"),
        timestamp = time(),
        version = Grouper.ADDON_VERSION or "unknown",
        data = { text = "Hello from Grouper testcomm!" }
    }
    Grouper:SendComm("TEST", testMessage, "WHISPER", target, "ALERT")
end

-- Persistent debug log using SavedVariables
Grouper.DebugLog = Grouper.DebugLog or {}
function Grouper:LogDebug(msg)
    if type(msg) == "table" then
        msg = tostring(msg)
    end
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    table.insert(self.DebugLog, string.format("[%s] %s", timestamp, msg))
end

-- Utility to get full player name with realm, always using exact realm format
function Grouper.GetFullPlayerName(name)
    if not name then return "" end
    local realm = GetRealmName()
    if name:find("-") then
        local base, r = name:match("^(.-)%-(.+)$")
        if base and r then
            return base .. "-" .. r
        end
        return name
    end
    return name .. "-" .. realm
end

-- Cancel repeating timers when the addon is disabled
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

-- Get the Grouper channel index, caching it for future use  
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

-- determine number of groups stored
function Grouper:CountGroups()
    local count = 0
    for _ in pairs(self.groups) do
        count = count + 1
    end
    return count
end

-- determine number of fields in a table
function Grouper:CountTableFields(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Saves window position and size to the database
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

-- Restores window position and size from the database
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

-- Save window position to DB
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




Grouper.DebugLog = Grouper.DebugLog or {}
Grouper.FunctionName = FunctionName
Grouper.OnDisable = OnDisable
GrouperUtilities = GrouperUtilities or {}