-- client/main.lua
-- LiveMap Client Script with Postal Integration
-- UPDATED: CDE Duty System integration for Standalone mode

local lastPosition = nil
local lastUpdate = 0
local isTracking = false
local playerJob = nil
local playerStatus = nil

-- Debug logging function
local function debugLog(message)
    if Config.EnableDebug then
        print("^3[LIVEMAP-CLIENT] " .. message .. "^0")
    end
end

-- Get postal code using nearest-postal export
local function getPostalCode()
    local postal = "Unknown"
    
    if GetResourceState('nearest-postal') == 'started' then
        local success, result = pcall(function()
            return exports.npostal:npostal()
        end)
        
        if success and result then
            postal = tostring(result)
        else
            local variations = {
                function() return exports['nearest-postal']:npostal() end,
                function() return exports['nearest-postal']:getPostal() end,
                function() return exports.npostal:getPostal() end
            }
            
            for _, variation in ipairs(variations) do
                local success2, result2 = pcall(variation)
                if success2 and result2 then
                    postal = tostring(result2)
                    break
                end
            end
        end
    end
    
    return postal
end

-- Get player job information (for ESX/QBCore)
local function getPlayerJob()
    if Config.Framework.ESX then
        local ESX = exports['es_extended']:getSharedObject()
        local PlayerData = ESX.GetPlayerData()
        if PlayerData and PlayerData.job then
            return PlayerData.job.name, PlayerData.job.grade_name
        end
    elseif Config.Framework.QBCore then
        local QBCore = exports['qb-core']:GetCoreObject()
        local PlayerData = QBCore.Functions.GetPlayerData()
        if PlayerData and PlayerData.job then
            return PlayerData.job.name, PlayerData.job.grade.name
        end
    end
    
    return "civilian", "none"
end

-- Check if player is on duty using CDE Duty System
local function isOnDutyCDE()
    -- Check if CDE_Duty resource is running
    if GetResourceState('CDE_Duty') ~= 'started' then
        debugLog("CDE_Duty resource not running")
        return false, nil, nil
    end
    
    -- Try to get duty status from CDE Duty System export
    local success, result = pcall(function()
        return exports.CDE_Duty:GetDutyStatus()
    end)
    
    if success and result then
        debugLog("CDE Duty Status - OnDuty: " .. tostring(result.onDuty) .. ", Job: " .. tostring(result.job) .. ", Dept: " .. tostring(result.department))
        return result.onDuty, result.job, result.department
    end
    
    -- Fallback: Try IsOnDutyLEO export
    local success2, isLEO = pcall(function()
        return exports.CDE_Duty:IsOnDutyLEO()
    end)
    
    if success2 and isLEO then
        debugLog("CDE IsOnDutyLEO: true")
        return true, "leo", nil
    end
    
    debugLog("CDE Duty check failed or player not on duty")
    return false, nil, nil
end

-- Get player status
local function getPlayerStatus()
    -- For standalone with CDE, use duty status
    if Config.Framework.Standalone then
        local onDuty, job, department = isOnDutyCDE()
        if onDuty then
            return "In Service"
        else
            return "Off Duty"
        end
    end
    
    -- For ESX/QBCore, check dispatch resource
    if GetResourceState('dispatch') == 'started' then
        local success, status = pcall(function()
            return exports['dispatch']:GetPlayerStatus()
        end)
        if success and status then
            return status
        end
    end
    
    return "In Service"
end

-- Check if player should be tracked
local function shouldTrackPlayer()
    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) then
        return false
    end
    
    -- STANDALONE MODE - Use CDE Duty System
    if Config.Framework.Standalone then
        local onDuty, job, department = isOnDutyCDE()
        
        if not onDuty then
            debugLog("Standalone: Player not on duty (CDE)")
            return false
        end
        
        -- Only track LEO units (not fire/ems) unless configured otherwise
        if Config.TrackLEOOnly then
            if job ~= "leo" then
                debugLog("Standalone: Player on duty but not LEO (job: " .. tostring(job) .. ")")
                return false
            end
        end
        
        -- Set playerJob and playerStatus for the update
        playerJob = department or job or "leo"
        playerStatus = "In Service"
        
        debugLog("Standalone: Tracking player - Dept: " .. tostring(department) .. ", Job: " .. tostring(job))
        return true
    end
    
    -- ESX/QBCORE MODE - Use existing job-based tracking
    local job, grade = getPlayerJob()
    playerJob = job
    
    local jobTracked = false
    for _, trackedJob in ipairs(Config.TrackedJobs) do
        if job == trackedJob then
            jobTracked = true
            break
        end
    end
    
    if not jobTracked then
        debugLog("Job not tracked: " .. (job or "nil"))
        return false
    end
    
    playerStatus = getPlayerStatus()
    
    local statusTracked = false
    for _, trackedStatus in ipairs(Config.TrackedStatuses) do
        if playerStatus == trackedStatus then
            statusTracked = true
            break
        end
    end
    
    if not statusTracked then
        debugLog("Status not tracked: " .. (playerStatus or "nil"))
        return false
    end
    
    return true
end

-- Calculate distance between two points
local function getDistance(pos1, pos2)
    if not pos1 or not pos2 then return 999999 end
    
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    
    return math.sqrt(dx * dx + dy * dy)
end

-- Send position update to server
-- IMPORTANT: Sends RAW GTA coordinates - transformation happens on frontend
local function sendPositionUpdate(coords)
    local postal = getPostalCode()
    
    -- SEND RAW GTA COORDINATES - NO CONVERSION!
    local positionData = {
        x = coords.x,           -- Raw GTA X
        y = coords.y,           -- Raw GTA Y
        z = coords.z,           -- Raw GTA Z
        heading = GetEntityHeading(PlayerPedId()),
        job = playerJob,
        status = playerStatus,
        postal = postal,
        timestamp = GetGameTimer()
    }
    
    debugLog("Sending RAW position: X=" .. coords.x .. ", Y=" .. coords.y .. ", Z=" .. coords.z)
    debugLog("Job: " .. tostring(playerJob) .. ", Status: " .. tostring(playerStatus) .. ", Postal: " .. postal)
    
    TriggerServerEvent('livemap:updatePosition', positionData)
    
    lastPosition = coords
    lastUpdate = GetGameTimer()
end

-- Handle postal requests from server
RegisterNetEvent('livemap:getPostal')
AddEventHandler('livemap:getPostal', function()
    local postal = getPostalCode()
    debugLog("Server requested postal, sending: " .. postal)
    TriggerServerEvent('livemap:postalResponse', postal)
end)

-- Main tracking loop
Citizen.CreateThread(function()
    while true do
        local currentTime = GetGameTimer()
        
        if currentTime - lastUpdate >= Config.UpdateInterval then
            if shouldTrackPlayer() then
                local playerPed = PlayerPedId()
                local coords = GetEntityCoords(playerPed)
                
                if not lastPosition or getDistance(coords, lastPosition) >= Config.MaxDistance then
                    sendPositionUpdate(coords)
                    
                    if not isTracking then
                        isTracking = true
                        debugLog("Started tracking player")
                    end
                else
                    debugLog("Player hasn't moved enough, skipping update")
                end
            else
                if isTracking then
                    isTracking = false
                    debugLog("Stopped tracking player")
                    TriggerServerEvent('livemap:stopTracking')
                end
            end
        end
        
        Citizen.Wait(1000)
    end
end)

-- Handle job changes (ESX)
if Config.Framework.ESX then
    RegisterNetEvent('esx:setJob')
    AddEventHandler('esx:setJob', function(job)
        debugLog("Job changed to: " .. (job.name or "nil"))
        playerJob = job.name
    end)
end

-- Handle job changes (QBCore)
if Config.Framework.QBCore then
    RegisterNetEvent('QBCore:Client:OnJobUpdate')
    AddEventHandler('QBCore:Client:OnJobUpdate', function(JobInfo)
        debugLog("Job changed to: " .. (JobInfo.name or "nil"))
        playerJob = JobInfo.name
    end)
end

-- Handle CDE Duty changes (Standalone)
if Config.Framework.Standalone then
    -- Listen for duty confirmation from CDE
    RegisterNetEvent('CDE:ConfirmOnDutyDepartment')
    AddEventHandler('CDE:ConfirmOnDutyDepartment', function(department, deptConfig)
        debugLog("CDE: Went on duty as " .. tostring(department))
        playerJob = department
        playerStatus = "In Service"
        
        -- Force an immediate position update
        Citizen.SetTimeout(1000, function()
            if shouldTrackPlayer() then
                local playerPed = PlayerPedId()
                local coords = GetEntityCoords(playerPed)
                sendPositionUpdate(coords)
                isTracking = true
                debugLog("Forced position update after going on duty")
            end
        end)
    end)
    
    -- Listen for off duty from CDE
    RegisterNetEvent('CDE:ConfirmOffDuty')
    AddEventHandler('CDE:ConfirmOffDuty', function()
        debugLog("CDE: Went off duty")
        playerJob = nil
        playerStatus = "Off Duty"
        
        if isTracking then
            isTracking = false
            TriggerServerEvent('livemap:stopTracking')
            debugLog("Stopped tracking - went off duty")
        end
    end)
end

-- Handle status changes
RegisterNetEvent('livemap:statusChanged')
AddEventHandler('livemap:statusChanged', function(newStatus)
    debugLog("Status changed to: " .. newStatus)
    playerStatus = newStatus
end)

-- Send offline status when resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if isTracking then
            TriggerServerEvent('livemap:stopTracking')
        end
    end
end)

-- Admin commands
if Config.EnableAdminCommands then
    RegisterCommand('livemapstatus', function()
        local tracking = shouldTrackPlayer()
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        local postal = getPostalCode()
        
        print("^3[LIVEMAP] === STATUS ===^0")
        print("^3[LIVEMAP] Framework: " .. (Config.Framework.Standalone and "Standalone/CDE" or (Config.Framework.ESX and "ESX" or (Config.Framework.QBCore and "QBCore" or "Unknown"))) .. "^0")
        print("^3[LIVEMAP] Should Track: " .. tostring(tracking) .. "^0")
        print("^3[LIVEMAP] Job: " .. (playerJob or "nil") .. "^0")
        print("^3[LIVEMAP] Status: " .. (playerStatus or "nil") .. "^0")
        print("^3[LIVEMAP] RAW GTA Coords: X=" .. coords.x .. ", Y=" .. coords.y .. ", Z=" .. coords.z .. "^0")
        print("^3[LIVEMAP] Postal: " .. postal .. "^0")
        print("^3[LIVEMAP] Is Tracking: " .. tostring(isTracking) .. "^0")
        
        -- Show CDE duty status if standalone
        if Config.Framework.Standalone then
            local onDuty, job, dept = isOnDutyCDE()
            print("^3[LIVEMAP] CDE OnDuty: " .. tostring(onDuty) .. "^0")
            print("^3[LIVEMAP] CDE Job: " .. tostring(job) .. "^0")
            print("^3[LIVEMAP] CDE Dept: " .. tostring(dept) .. "^0")
        end
        
        TriggerEvent('chat:addMessage', {
            args = {"[LIVEMAP]", "RAW Coords: X=" .. math.floor(coords.x) .. ", Y=" .. math.floor(coords.y) .. " | Tracking: " .. tostring(tracking)}
        })
    end, false)
    
    RegisterCommand('livemapforce', function()
        if shouldTrackPlayer() then
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            sendPositionUpdate(coords)
            TriggerEvent('chat:addMessage', {
                args = {"[LIVEMAP]", "Force sent: X=" .. math.floor(coords.x) .. ", Y=" .. math.floor(coords.y)}
            })
        else
            TriggerEvent('chat:addMessage', {
                args = {"[LIVEMAP]", "Cannot track - check duty status"}
            })
        end
    end, false)
    
    RegisterCommand('testpostal', function()
        local postal = getPostalCode()
        print("^2[LIVEMAP] Current postal: " .. postal .. "^0")
        TriggerEvent('chat:addMessage', {
            args = {"[LIVEMAP]", "Current postal: " .. postal}
        })
    end, false)
end

-- Initialize
Citizen.CreateThread(function()
    Citizen.Wait(5000)
    
    local frameworkName = "Unknown"
    if Config.Framework.Standalone then
        frameworkName = "Standalone (CDE Duty)"
    elseif Config.Framework.ESX then
        frameworkName = "ESX"
    elseif Config.Framework.QBCore then
        frameworkName = "QBCore"
    end
    
    print("^2[LIVEMAP-CLIENT] Initialized - Sending RAW GTA coordinates^0")
    print("^2[LIVEMAP-CLIENT] Framework: " .. frameworkName .. "^0")
    
    if Config.Framework.Standalone then
        -- Check CDE Duty status on init
        local onDuty, job, dept = isOnDutyCDE()
        if onDuty then
            playerJob = dept or job
            playerStatus = "In Service"
            debugLog("Initial CDE status: On Duty as " .. tostring(playerJob))
        else
            debugLog("Initial CDE status: Off Duty")
        end
    else
        local job, grade = getPlayerJob()
        playerJob = job
        playerStatus = getPlayerStatus()
        debugLog("Initial job: " .. (playerJob or "nil"))
        debugLog("Initial status: " .. (playerStatus or "nil"))
    end
end)
