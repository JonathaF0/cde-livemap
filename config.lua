Config = {}
-- ========================================
-- CAD BACKEND CONFIGURATION
-- ========================================
Config.CADEndpoint = "https://cdecad.com/api/dispatch/location-update" -- Your CAD backend URL for location updates
Config.CommunityID = "" -- Your community ID
Config.APIKey = "" -- API key, get this from CDE CAD Support

-- ========================================
-- UPDATE SETTINGS
-- ========================================
Config.UpdateInterval = 10000 -- Update interval in milliseconds (10 seconds)
Config.MaxDistance = 50.0 -- Minimum distance player must move to trigger update (in GTA units)
Config.EnableDebug = false -- Enable debug logging

-- ========================================
-- PLAYER FILTERING
-- ========================================
Config.Framework = {
    Standalone = true, -- Use CDE Duty System for tracking (no ESX/QBCore)
    ESX = false, -- ESX Framework
    QBCore = false, -- QB-Core Framework
}

-- ========================================
-- STANDALONE/CDE DUTY SETTINGS
-- ========================================
-- These settings only apply when Config.Framework.Standalone = true

-- Only track LEO units (police/sheriff), not Fire/EMS
-- Set to false to track all on-duty units (LEO + Fire/EMS)
Config.TrackLEOOnly = true

-- ========================================
-- ESX/QBCORE SETTINGS
-- ========================================
-- These settings only apply when using ESX or QBCore frameworks

-- Jobs that should be tracked on the livemap (ESX/QBCore only)
Config.TrackedJobs = {
    "police",
    "sheriff",
    "trooper", 
    "statepolice",
    "ambulance",
    "ems",
    "fire",
    "dispatch"
}

-- Only track players with these statuses (ESX/QBCore only)
Config.TrackedStatuses = {
    "10-8", -- In Service
    "In Service",
    "Busy",
    "Enroute", 
    "On Scene",
    "Traffic Stop",
    "10-6", -- Busy
    "10-97", -- On Scene
    "10-23", -- Traffic Stop
    "10-11" -- Traffic Stop
}

-- ========================================
-- MAP COORDINATE TRANSFORMATION
-- ========================================
-- These settings transform GTA V coordinates to Leaflet map coordinates
-- Based on calibration: Map center found at Leaflet [-130, 116]
-- 
-- GTA V Coordinate System:
--   X: West (-) to East (+), roughly -4000 to +4500
--   Y: South (-) to North (+), roughly -4000 to +8000
--   Origin (0,0) is in central Los Santos
--
-- Leaflet CRS.Simple Coordinate System:
--   Uses [lat, lng] format
--   Your tile map origin needs these offsets

Config.CoordinateTransform = {
    OriginLat = -155.11,
    OriginLng = 121.73,
    ScaleX = 0.012758,
    ScaleY = 0.012626,
}
Config.MapBounds = {
    MinX = -4000,
    MaxX = 4500,
    MinY = -4000, 
    MaxY = 8000
}

Config.GTABounds = {
    MinX = -4000,
    MaxX = 4500,
    MinY = -4000,
    MaxY = 8000
}

-- ========================================
-- ADVANCED SETTINGS
-- ========================================
Config.SendOfflineOnDisconnect = true -- Send offline status when player disconnects
Config.CleanupInterval = 60000 -- Clean up old positions every 60 seconds
Config.MaxRetries = 3 -- Max retries for failed HTTP requests
Config.RetryDelay = 2000 -- Delay between retries in milliseconds

-- ========================================
-- PERMISSIONS
-- ========================================
Config.RequirePermission = false -- Require specific permission to be tracked
Config.Permission = "livemap.track" -- Permission name (if using a permission system)

-- Admin commands
Config.EnableAdminCommands = true -- Enable admin commands for testing

-- ========================================
-- COORDINATE TRANSFORMATION NOTES
-- ========================================
--[[
    HOW TO CALIBRATE:
    
    1. The LiveMap page has a Config panel - use it to fine-tune these values
    
    2. Test with known GTA locations:
       - LSPD Mission Row: GTA (428, -981) - should appear in central LS
       - Sandy Shores PD: GTA (1853, 3686) - should appear in northern desert
       - Paleto Bay PD: GTA (-448, 6014) - should appear at the top of the map
       - LS Airport: GTA (-1034, -2733) - should appear at bottom of map
    
    3. If markers appear in wrong locations:
       - Wrong North/South: Flip the sign of ScaleY
       - Wrong East/West: Flip the sign of ScaleX  
       - Everything offset: Adjust OriginLat and OriginLng
       - Scale too big/small: Adjust ScaleX and ScaleY magnitude
    
    4. The transformation formula is:
       leafletLat = OriginLat + (gtaY * ScaleY)
       leafletLng = OriginLng + (gtaX * ScaleX)
    
    5. Save working values in the LiveMap Config panel, then update this file
    
    ========================================
    CDE DUTY SYSTEM INTEGRATION NOTES
    ========================================
    
    When Config.Framework.Standalone = true:
    - LiveMap uses CDE_Duty exports to check if player is on duty
    - Tracking starts when player uses /d [department] command
    - Tracking stops when player uses /d off command
    - The job field will be set to the department code (thp, kcso, kpd, etc.)
    
    Required CDE_Duty exports (already available):
    - exports.CDE_Duty:GetDutyStatus() -> {onDuty, job, department}
    - exports.CDE_Duty:IsOnDutyLEO() -> boolean
    
    If TrackLEOOnly = true:
    - Only tracks players where job == "leo" (police departments)
    - Fire/EMS units will not be tracked
    
    If TrackLEOOnly = false:
    - Tracks all on-duty units (LEO + Fire/EMS)
]]
