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

local POIData = {
    Markers = {},
    AllMarkers = {},
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

local function AddSharedMarker(marker, label)
    if not marker or not marker.id or not marker.coords then
        return
    end

    if FindMarkerIndex(POIData.AllMarkers, marker.id) then
        return
    end

    local blip = AddBlipForCoord(marker.coords.x, marker.coords.y, marker.coords.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 4)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(label or "PolCam Marker (Shared)")
    EndTextCommandSetBlipName(blip)

    marker.blip = blip
    table.insert(POIData.AllMarkers, marker)
end

function PlaceMarker()
    if not PolCam.Active then return end
    if not Config.POI.Enabled then return end

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

    if Config.POI.SyncToOthers then
        TriggerServerEvent('polcam:createPOI', marker)
    end

    PlayPolCamSound("MarkerPlaced")

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 5)
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

function DeleteLastMarker()
    if #POIData.Markers == 0 then
        return
    end

    local marker = table.remove(POIData.Markers)

    if marker.blip and DoesBlipExist(marker.blip) then
        RemoveBlip(marker.blip)
    end

    if Config.POI.SyncToOthers then
        TriggerServerEvent('polcam:removePOI', marker.id)
    end

    PlayPolCamSound("Click")

    if Config.Debug.Enabled then
        print("[PolCam] Marker deleted: " .. marker.id)
    end
end

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

CreateThread(function()
    while true do
        Wait(5000)

        local now = GetGameTimer()
        local toRemove = {}

        for i, marker in ipairs(POIData.Markers) do
            if marker.expiresAt and now > marker.expiresAt then
                table.insert(toRemove, i)
            end
        end

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

RegisterNetEvent('polcam:receivePOI')
AddEventHandler('polcam:receivePOI', function(marker)
    if not marker or not marker.id or not marker.coords then return end
    if marker.owner == GetPlayerServerId(PlayerId()) then return end

    AddSharedMarker(marker, "PolCam Marker (Shared)")
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
            AddSharedMarker(marker, "PolCam Marker (Shared)")
        end
    end
end)

RegisterNetEvent('polcam:receiveSyncedMarker')
AddEventHandler('polcam:receiveSyncedMarker', function(marker)
    if not marker or not marker.id or not marker.coords then return end
    if marker.creator == GetPlayerServerId(PlayerId()) then return end

    AddSharedMarker(marker, "PolCam Marker (Crew)")
end)

RegisterNetEvent('polcam:syncedMarkerRemoved')
AddEventHandler('polcam:syncedMarkerRemoved', function(markerId)
    local index = FindMarkerIndex(POIData.AllMarkers, markerId)
    if not index then return end

    local marker = POIData.AllMarkers[index]
    if marker and marker.blip and DoesBlipExist(marker.blip) then
        RemoveBlip(marker.blip)
    end

    table.remove(POIData.AllMarkers, index)
end)

RegisterNetEvent('polcam:syncAllMarkers')
AddEventHandler('polcam:syncAllMarkers', function(serverMarkers)
    if type(serverMarkers) ~= "table" then return end

    for _, marker in pairs(serverMarkers) do
        if marker and marker.id and marker.coords and marker.creator ~= GetPlayerServerId(PlayerId()) then
            AddSharedMarker(marker, "PolCam Marker (Crew)")
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

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

function GetMarkerCount()
    return #POIData.Markers
end

function GetAllMarkers()
    return POIData.Markers
end
