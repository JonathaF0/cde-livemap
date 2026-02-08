-- server/main.lua
-- LiveMap Server Script
-- UPDATED: Works with CDE Duty System when Standalone mode is enabled
-- The server doesn't need to know about CDE - it just receives position data from clients

local trackedPlayers = {}
local lastCleanup = 0
local sendLocationUpdate

-- Debug logging function
local function debugLog(message)
    if Config.EnableDebug then
        print("^3[LIVEMAP-SERVER] " .. message .. "^0")
    end
end

-- Get player character name
local function getPlayerName(source)
    if Config.Framework.ESX then
        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getName()
        end
    elseif Config.Framework.QBCore then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
        end
    end
    
    -- Standalone/CDE mode - just use the player's name
    return GetPlayerName(source)
end

-- Get player identifier
local function getPlayerIdentifier(source)
    local identifiers = GetPlayerIdentifiers(source)
    
    for _, id in pairs(identifiers) do
        if string.find(id, "steam:") then
            return id
        end
    end
    
    return identifiers[1] or "unknown:" .. source
end

-- Handle postal response from client
RegisterNetEvent('livemap:postalResponse')
AddEventHandler('livemap:postalResponse', function(postal)
    local source = source
    
    if trackedPlayers[source] then
        trackedPlayers[source].postal = postal or "Unknown"
        debugLog("Updated postal for " .. trackedPlayers[source].name .. ": " .. postal)
        sendLocationUpdate(trackedPlayers[source])
    end
end)

-- Send location update to CAD
-- IMPORTANT: Sends RAW GTA coordinates
sendLocationUpdate = function(playerData)
    local postData = {
        unitId = playerData.identifier,
        unitName = playerData.name,
        -- SEND RAW GTA COORDINATES
        x = playerData.x,
        y = playerData.y,
        z = playerData.z,
        -- Also send as lat/lng for compatibility (but using RAW values)
        lat = playerData.y,
        lng = playerData.x,
        heading = playerData.heading,
        job = playerData.job,
        status = playerData.status,
        timestamp = os.time(),
        communityId = Config.CommunityID,
        postal = playerData.postal or "Unknown",
        postalVerified = playerData.postal ~= nil and playerData.postal ~= "Unknown"
    }
    
    local jsonData = json.encode(postData)
    
    debugLog("Sending RAW coords for " .. playerData.name .. ": X=" .. playerData.x .. ", Y=" .. playerData.y .. " | Job: " .. tostring(playerData.job))
    
    PerformHttpRequest(Config.CADEndpoint, function(statusCode, response, headers)
        if statusCode == 200 or statusCode == 201 then
            debugLog("Successfully sent location for " .. playerData.name)
        else
            print("^1[LIVEMAP-SERVER] Failed to send location for " .. playerData.name .. ". Status: " .. statusCode .. "^0")
            if response then
                debugLog("Response: " .. response)
            end
        end
    end, 'POST', jsonData, {
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json',
        ['X-API-Key'] = Config.APIKey
    })
end

-- Send offline status to CAD backend
local function sendOfflineStatus(playerData)
    local postData = {
        unitId = playerData.identifier,
        unitName = playerData.name,
        status = "offline",
        timestamp = os.time(),
        communityId = Config.CommunityID
    }
    
    local jsonData = json.encode(postData)
    
    debugLog("Sending offline status for " .. playerData.name)
    
    PerformHttpRequest(Config.CADEndpoint, function(statusCode, response, headers)
        if statusCode == 200 or statusCode == 201 then
            debugLog("Successfully sent offline status for " .. playerData.name)
        else
            print("^1[LIVEMAP-SERVER] Failed to send offline status for " .. playerData.name .. ". Status: " .. tostring(statusCode) .. "^0")
            if response then
                debugLog("Response: " .. response)
            end
        end
    end, 'POST', jsonData, {
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json',
        ['X-API-Key'] = Config.APIKey
    })
end

-- Handle position update from client
RegisterNetEvent('livemap:updatePosition')
AddEventHandler('livemap:updatePosition', function(positionData)
    local source = source
    local playerName = getPlayerName(source)
    local identifier = getPlayerIdentifier(source)
    
    if not playerName or not identifier then
        debugLog("Could not get player info for source " .. source)
        return
    end
    
    -- Store RAW coordinates
    -- Note: In Standalone/CDE mode, positionData.job will be the department code (thp, kcso, etc.)
    local playerData = {
        source = source,
        identifier = identifier,
        name = playerName,
        x = positionData.x,
        y = positionData.y,
        z = positionData.z,
        heading = positionData.heading,
        job = positionData.job,
        status = positionData.status,
        postal = positionData.postal or "Getting...",
        lastUpdate = os.time()
    }
    
    trackedPlayers[source] = playerData
    
    debugLog("Received RAW position from " .. playerName .. ": X=" .. positionData.x .. ", Y=" .. positionData.y .. " | Job: " .. tostring(positionData.job))
    
    -- Request postal from client if not provided
    if not positionData.postal or positionData.postal == "Unknown" then
        TriggerClientEvent('livemap:getPostal', source)
    end
    
    sendLocationUpdate(playerData)
end)

-- Handle stop tracking from client
RegisterNetEvent('livemap:stopTracking')
AddEventHandler('livemap:stopTracking', function()
    local source = source
    
    if trackedPlayers[source] then
        local playerData = trackedPlayers[source]
        debugLog("Player " .. playerData.name .. " stopped tracking (went off duty or left)")
        
        if Config.SendOfflineOnDisconnect then
            sendOfflineStatus(playerData)
        end
        
        trackedPlayers[source] = nil
    end
end)

-- Handle player disconnection
AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if trackedPlayers[source] then
        local playerData = trackedPlayers[source]
        debugLog("Player " .. playerData.name .. " disconnected: " .. reason)
        
        if Config.SendOfflineOnDisconnect then
            sendOfflineStatus(playerData)
        end
        
        trackedPlayers[source] = nil
    end
end)

-- Cleanup old positions
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.CleanupInterval)
        
        local currentTime = os.time()
        local cleanedCount = 0
        
        for source, playerData in pairs(trackedPlayers) do
            if not GetPlayerName(source) then
                debugLog("Cleaning up disconnected player: " .. playerData.name)
                
                if Config.SendOfflineOnDisconnect then
                    sendOfflineStatus(playerData)
                end
                
                trackedPlayers[source] = nil
                cleanedCount = cleanedCount + 1
            end
            
            if currentTime - playerData.lastUpdate > 1800 then
                debugLog("Cleaning up old position for: " .. playerData.name)
                
                if Config.SendOfflineOnDisconnect then
                    sendOfflineStatus(playerData)
                end
                
                trackedPlayers[source] = nil
                cleanedCount = cleanedCount + 1
            end
        end
        
        if cleanedCount > 0 then
            debugLog("Cleaned up " .. cleanedCount .. " old/disconnected players")
        end
    end
end)

-- Admin commands
if Config.EnableAdminCommands then
    RegisterCommand('livemaptest', function(source, args, rawCommand)
        if source ~= 0 then 
            print("^1[LIVEMAP-SERVER] This command can only be used from the server console^0")
            return 
        end
        
        print("^3[LIVEMAP-SERVER] Testing CAD connection...^0")
        print("^3[LIVEMAP-SERVER] Endpoint: " .. Config.CADEndpoint .. "^0")
        print("^3[LIVEMAP-SERVER] Community ID: " .. Config.CommunityID .. "^0")
        print("^3[LIVEMAP-SERVER] Framework: " .. (Config.Framework.Standalone and "Standalone/CDE" or (Config.Framework.ESX and "ESX" or "QBCore")) .. "^0")
        
        -- Test with actual GTA coordinates (LSPD Mission Row)
        local testData = {
            unitId = "test-unit-123",
            unitName = "Test Unit",
            x = 428,
            y = -981,
            z = 30,
            lat = -981,
            lng = 428,
            heading = 0,
            job = "kcso", -- Test with a CDE department code
            status = "In Service",
            timestamp = os.time(),
            communityId = Config.CommunityID,
            postal = "TEST"
        }
        
        PerformHttpRequest(Config.CADEndpoint, function(statusCode, response, headers)
            if statusCode == 200 or statusCode == 201 then
                print("^2[LIVEMAP-SERVER] SUCCESS: CAD connection working!^0")
                if response then
                    print("^2[LIVEMAP-SERVER] Response: " .. response .. "^0")
                end
            else
                print("^1[LIVEMAP-SERVER] FAILED: Status Code: " .. statusCode .. "^0")
                if response then
                    print("^1[LIVEMAP-SERVER] Response: " .. response .. "^0")
                end
            end
        end, 'POST', json.encode(testData), {
            ['Content-Type'] = 'application/json',
            ['Accept'] = 'application/json',
            ['X-API-Key'] = Config.APIKey
        })
    end, true)
    
    RegisterCommand('livemapstats', function(source, args, rawCommand)
        if source ~= 0 then 
            print("^1[LIVEMAP-SERVER] This command can only be used from the server console^0")
            return 
        end
        
        print("^3[LIVEMAP-SERVER] === TRACKED PLAYERS ===^0")
        print("^3[LIVEMAP-SERVER] Framework: " .. (Config.Framework.Standalone and "Standalone/CDE" or (Config.Framework.ESX and "ESX" or "QBCore")) .. "^0")
        
        local count = 0
        for _ in pairs(trackedPlayers) do count = count + 1 end
        print("^3[LIVEMAP-SERVER] Total tracked: " .. count .. "^0")
        
        for source, playerData in pairs(trackedPlayers) do
            local timeSince = os.time() - playerData.lastUpdate
            print("^3[LIVEMAP-SERVER] " .. playerData.name .. " | Job: " .. tostring(playerData.job) .. " | X=" .. math.floor(playerData.x) .. ", Y=" .. math.floor(playerData.y) .. " | Postal: " .. (playerData.postal or "Unknown") .. " | " .. timeSince .. "s ago^0")
        end
        
        print("^3[LIVEMAP-SERVER] ========================^0")
    end, true)
end

-- Startup message
Citizen.CreateThread(function()
    Citizen.Wait(2000)
    
    local frameworkName = "Unknown"
    if Config.Framework.Standalone then
        frameworkName = "Standalone (CDE Duty System)"
    elseif Config.Framework.ESX then
        frameworkName = "ESX"
    elseif Config.Framework.QBCore then
        frameworkName = "QBCore"
    end
    
    print("^2[LIVEMAP-SERVER] ================================^0")
    print("^2[LIVEMAP-SERVER] LiveMap server started^0")
    print("^2[LIVEMAP-SERVER] Mode: RAW GTA COORDINATES^0")
    print("^2[LIVEMAP-SERVER] Framework: " .. frameworkName .. "^0")
    print("^2[LIVEMAP-SERVER] CAD Endpoint: " .. Config.CADEndpoint .. "^0")
    print("^2[LIVEMAP-SERVER] Update Interval: " .. (Config.UpdateInterval / 1000) .. " seconds^0")
    if Config.Framework.Standalone then
        print("^2[LIVEMAP-SERVER] Track LEO Only: " .. tostring(Config.TrackLEOOnly) .. "^0")
    end
    print("^2[LIVEMAP-SERVER] ================================^0")
    
    if Config.EnableAdminCommands then
        print("^2[LIVEMAP-SERVER] Admin commands: livemaptest, livemapstats^0")
    end
end)
