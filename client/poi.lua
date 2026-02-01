--[[
    PolCam - POI (Point of Interest) System
    Handles marker placement, removal, and syncing
]]

-- ============================================================================
-- NATIVE CACHING (Performance Optimization)
-- ============================================================================
local GetPlayerServerId = GetPlayerServerId
local PlayerId = PlayerId
local GetGameTimer = GetGameTimer
local AddBlipForCoord = AddBlipForCoord
local SetBlipSprite = SetBlipSprite
local SetBlipColour = SetBlipColour
local SetBlipScale = SetBlipScale
local SetBlipAsShortRange = SetBlipAsShortRange
local BeginTextCommandSetBlipName = BeginTextCommandSetBlipName
local AddTextComponentString = AddTextComponentString
local EndTextCommandSetBlipName = EndTextCommandSetBlipName
local DoesBlipExist = DoesBlipExist
local RemoveBlip = RemoveBlip
local TriggerServerEvent = TriggerServerEvent
local GetCurrentResourceName = GetCurrentResourceName
local CreateThread = CreateThread
local Wait = Wait
local table_insert = table.insert
local table_remove = table.remove
local ipairs = ipairs

-- ============================================================================
-- LOCAL STATE
-- ============================================================================
local POIData = {
    Markers = {},  -- Local markers placed by this client
    AllMarkers = {}, -- All synced markers
    SelectedMarker = nil,
    MarkerCounter = 0
}

local function FindMarkerIndex(list, markerId)
    for i, marker in ipairs(list) do
        if marker.id == markerId then
            return i
        end
    end
    return nil
end

-- ============================================================================
-- PLACE MARKER
-- ============================================================================
function PlaceMarker()
    if not PolCam.Active then return end
    if not Config.POI.Enabled then return end
    
    -- Check marker limit
    local myMarkerCount = 0
    for _, marker in ipairs(POIData.Markers) do
        if marker.owner == GetPlayerServerId(PlayerId()) then
            myMarkerCount = myMarkerCount + 1
        end
    end
    
    if myMarkerCount >= Config.POI.MaxPOIs then
        PlayPolCamSound("Alert")
        return
    end
    
    -- Create marker at ground coords
    local coords = PolCam.GroundCoords
    if not coords or coords.x == 0 and coords.y == 0 and coords.z == 0 then
        return
    end
    
    POIData.MarkerCounter = POIData.MarkerCounter + 1
    
    local marker = {
        id = GetPlayerServerId(PlayerId()) .. "_" .. POIData.MarkerCounter,
        owner = GetPlayerServerId(PlayerId()),
        coords = coords,
        type = "waypoint",
        createdAt = GetGameTimer(),
        expiresAt = Config.POI.ExpiryTime > 0 and (GetGameTimer() + Config.POI.ExpiryTime * 1000) or nil
    }
    
    table.insert(POIData.Markers, marker)
    
    -- Sync to server if enabled
    if Config.POI.SyncToOthers then
        TriggerServerEvent('polcam:createPOI', marker)
    end
    
    -- Play sound
    PlayPolCamSound("MarkerPlaced")
    
    -- Set blip on map
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 5) -- Yellow
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("PolCam Marker")
    EndTextCommandSetBlipName(blip)
    
    marker.blip = blip
    
    if Config.Debug.Enabled then
        print("[PolCam] Marker placed at " .. tostring(coords))
    end
end

-- ============================================================================
-- DELETE MARKER (Delete most recent marker)
-- ============================================================================
function DeleteLastMarker()
    if #POIData.Markers == 0 then
        return
    end
    
    -- Remove last marker
    local marker = table.remove(POIData.Markers)
    
    -- Remove blip
    if marker.blip and DoesBlipExist(marker.blip) then
        RemoveBlip(marker.blip)
    end
    
    -- Sync removal to server
    if Config.POI.SyncToOthers then
        TriggerServerEvent('polcam:removePOI', marker.id)
    end
    
    PlayPolCamSound("Click")
    
    if Config.Debug.Enabled then
        print("[PolCam] Marker deleted: " .. marker.id)
    end
end

-- ============================================================================
-- DELETE ALL MARKERS
-- ============================================================================
function DeleteAllMarkers()
    for _, marker in ipairs(POIData.Markers) do
        if marker.blip and DoesBlipExist(marker.blip) then
            RemoveBlip(marker.blip)
        end
        
        if Config.POI.SyncToOthers then
            TriggerServerEvent('polcam:removePOI', marker.id)
        end
    end
    
    POIData.Markers = {}
    PlayPolCamSound("Confirm")
    
    if Config.Debug.Enabled then
        print("[PolCam] All markers deleted")
    end
end

-- ============================================================================
-- MARKER EXPIRY CHECK
-- ============================================================================
CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds
        
        local now = GetGameTimer()
        local toRemove = {}
        
        for i, marker in ipairs(POIData.Markers) do
            if marker.expiresAt and now > marker.expiresAt then
                table.insert(toRemove, i)
            end
        end
        
        -- Remove expired markers (in reverse order)
        for i = #toRemove, 1, -1 do
            local idx = toRemove[i]
            local marker = POIData.Markers[idx]
            
            if marker.blip and DoesBlipExist(marker.blip) then
                RemoveBlip(marker.blip)
            end
            
            table.remove(POIData.Markers, idx)
        end
    end
end)

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================
RegisterNetEvent('polcam:syncPOI')
AddEventHandler('polcam:syncPOI', function(marker)
    -- Don't add our own markers twice
    if marker.owner == GetPlayerServerId(PlayerId()) then return end
    
    -- Add synced marker
    local blip = AddBlipForCoord(marker.coords.x, marker.coords.y, marker.coords.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 4) -- Orange for others' markers
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("PolCam Marker (Shared)")
    EndTextCommandSetBlipName(blip)
    
    marker.blip = blip
    table.insert(POIData.AllMarkers, marker)
end)

RegisterNetEvent('polcam:receivePOI')
AddEventHandler('polcam:receivePOI', function(marker)
    if not marker or not marker.id or not marker.coords then return end
    if marker.owner == GetPlayerServerId(PlayerId()) then return end

    local existingIndex = FindMarkerIndex(POIData.AllMarkers, marker.id)
    if existingIndex then
        return
    end

    local blip = AddBlipForCoord(marker.coords.x, marker.coords.y, marker.coords.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 4)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("PolCam Marker (Shared)")
    EndTextCommandSetBlipName(blip)

    marker.blip = blip
    table.insert(POIData.AllMarkers, marker)
end)

RegisterNetEvent('polcam:removeSyncedPOI')
AddEventHandler('polcam:removeSyncedPOI', function(markerId)
    for i, marker in ipairs(POIData.AllMarkers) do
        if marker.id == markerId then
            if marker.blip and DoesBlipExist(marker.blip) then
                RemoveBlip(marker.blip)
            end
            table.remove(POIData.AllMarkers, i)
            break
        end
    end
end)

RegisterNetEvent('polcam:poiRemoved')
AddEventHandler('polcam:poiRemoved', function(markerId)
    local index = FindMarkerIndex(POIData.AllMarkers, markerId)
    if not index then return end
    local marker = POIData.AllMarkers[index]
    if marker and marker.blip and DoesBlipExist(marker.blip) then
        RemoveBlip(marker.blip)
    end
    table.remove(POIData.AllMarkers, index)
end)

RegisterNetEvent('polcam:syncAllPOIs')
AddEventHandler('polcam:syncAllPOIs', function(serverMarkers)
    for _, marker in ipairs(POIData.AllMarkers) do
        if marker.blip and DoesBlipExist(marker.blip) then
            RemoveBlip(marker.blip)
        end
    end
    POIData.AllMarkers = {}

    if type(serverMarkers) ~= "table" then return end

    for _, marker in pairs(serverMarkers) do
        if marker and marker.coords and marker.id and marker.owner ~= GetPlayerServerId(PlayerId()) then
            local blip = AddBlipForCoord(marker.coords.x, marker.coords.y, marker.coords.z)
            SetBlipSprite(blip, 1)
            SetBlipColour(blip, 4)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("PolCam Marker (Shared)")
            EndTextCommandSetBlipName(blip)

            marker.blip = blip
            table.insert(POIData.AllMarkers, marker)
        end
    end
end)

-- ============================================================================
-- CLEANUP
-- ============================================================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Remove all blips
    for _, marker in ipairs(POIData.Markers) do
        if marker.blip and DoesBlipExist(marker.blip) then
            RemoveBlip(marker.blip)
        end
    end
    
    for _, marker in ipairs(POIData.AllMarkers) do
        if marker.blip and DoesBlipExist(marker.blip) then
            RemoveBlip(marker.blip)
        end
    end
end)

-- ============================================================================
-- GETTERS
-- ============================================================================
function GetMarkerCount()
    return #POIData.Markers
end

function GetAllMarkers()
    return POIData.Markers
end
