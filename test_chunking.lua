-- Test chunking functionality
print("Testing chunking functionality...")

-- Simulate a large GROUP_UPDATE message (like what was causing the 530 char issue)
local testData = {
    type = "GROUP_UPDATE",
    name = "TestPlayerName",
    group = {
        name = "WC Dungeon Run - Need Tank and DPS",
        description = "Looking for experienced players for Wailing Caverns. Need 1 tank (warrior preferred) and 2 DPS. PST with class and level. Will be doing full clear with all quests. Should take about 2 hours. Discord preferred for voice chat.",
        level = 20,
        dungeonType = "dungeon",
        roles = {tank = 1, healer = 0, dps = 2},
        timestamp = time(),
        leader = "TestPlayerName"
    }
}

-- Serialize the data (simulating what SendComm does)
local serialized = "GROUP_UPDATE:" .. 
    testData.name .. ":" .. 
    testData.group.name .. ":" .. 
    testData.group.description .. ":" .. 
    tostring(testData.group.level) .. ":" .. 
    testData.group.dungeonType .. ":" .. 
    tostring(testData.group.roles.tank) .. ":" .. 
    tostring(testData.group.roles.healer) .. ":" .. 
    tostring(testData.group.roles.dps) .. ":" .. 
    tostring(testData.group.timestamp) .. ":" .. 
    testData.group.leader

print("Serialized message length:", string.len(serialized))
print("Serialized message:", serialized)

-- Test chunking logic
local maxChunkSize = 150
if string.len(serialized) > 200 then
    print("Message needs chunking!")
    
    local messageId = math.random(10000, 99999)
    local chunks = {}
    local totalChunks = math.ceil(string.len(serialized) / maxChunkSize)
    
    for i = 1, totalChunks do
        local startPos = (i - 1) * maxChunkSize + 1
        local endPos = math.min(i * maxChunkSize, string.len(serialized))
        local chunk = string.sub(serialized, startPos, endPos)
        local chunkMessage = string.format("GRPR_MP%d:%d:%d:%s", messageId, i, totalChunks, chunk)
        
        table.insert(chunks, chunkMessage)
        print(string.format("Chunk %d/%d (length %d): %s", i, totalChunks, string.len(chunkMessage), chunkMessage))
    end
    
    print(string.format("Total chunks created: %d", #chunks))
else
    print("Message fits in single transmission")
end