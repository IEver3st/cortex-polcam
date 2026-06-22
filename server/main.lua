local GetPlayerPed = GetPlayerPed
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetPedInVehicleSeat = GetPedInVehicleSeat
local DoesEntityExist = DoesEntityExist
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local GetGameTimer = GetGameTimer
local GetCurrentResourceName = GetCurrentResourceName
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local GetEntityType = GetEntityType
local GetEntityModel = GetEntityModel
local GetVehicleNumberPlateText = GetVehicleNumberPlateText
local GetPlayerName = GetPlayerName
local TriggerClientEvent = TriggerClientEvent
local CreateThread = CreateThread
local Wait = Wait
local os_time = os.time
local math_sqrt = math.sqrt
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local type = type
local table_sort = table.sort

local ServerPOIs = {}

local ActiveHeliCameras = {}
local CameraWaitlists = {}

local SharedCameraState = {}

local ActiveSpotlights = {}
local HeliTracking = {}
local ActiveAirFeeds = {}
local ActiveRappels = {}
local SyncedMarkers = {}

local AIR_FEED_STALE_MS = 1200
local AIR_FEED_MAINTENANCE_INTERVAL_MS = 250
local AIR_FEED_ID_PREFIX = 'air:'

local BroadcastHeliTracking
local ClearHeliTracking

local function DebugLog(message)
    if Config and Config.Debug and Config.Debug.Enabled then
        print(message)
    end
end

local function TrimString(value, fallback)
    if value == nil then
        return fallback
    end

    local text = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then
        return fallback
    end

    return text
end

local function CloneVec3(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' then
        return nil
    end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if not x or not y or not z then
        return nil
    end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function CloneRotation(value)
    if type(value) ~= 'table' then
        return nil
    end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if not x or not y or not z then
        return nil
    end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function BuildFeedId(vehicleNetId)
    return AIR_FEED_ID_PREFIX .. tostring(vehicleNetId)
end

local function IsServerVehicleEntity(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function IsServerPedEntity(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 1
end

local function ParseFeedId(feedId)
    if type(feedId) == 'number' then
        return math.floor(feedId)
    end

    if type(feedId) ~= 'string' then
        return nil
    end

    local suffix = feedId:match('^' .. AIR_FEED_ID_PREFIX .. '(%d+)$')
    if not suffix then
        return nil
    end

    return tonumber(suffix)
end

local function ResolveAirFeedCallsign(src)
    if not src or src <= 0 then
        return 'AIR'
    end

    local fallback = ('AIR-%02d'):format(src)
    local stateOwner
    local ok = pcall(function()
        stateOwner = Player(src)
    end)
    if ok and stateOwner and stateOwner.state then
        local callsign = TrimString(stateOwner.state.callsign, nil)
            or TrimString(stateOwner.state.callSign, nil)
            or TrimString(stateOwner.state.radioCallsign, nil)
        if callsign then
            return callsign
        end

        local mdt = stateOwner.state.mdt
        if type(mdt) == 'table' then
            callsign = TrimString(mdt.callsign or mdt.callSign, nil)
            if callsign then
                return callsign
            end
        end
    end

    return fallback
end

local function ResolvePilotSource(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local ped = GetPedInVehicleSeat(vehicle, -1)
    if not ped or ped == 0 then
        return nil
    end

    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local src = tonumber(playerId)
        if src and src > 0 and GetPlayerPed(src) == ped then
            return src
        end
    end

    return nil
end

local function BuildAirFeedPreview(feed)
    local preview = type(feed.preview) == 'table' and feed.preview or {}
    return {
        coords = CloneVec3(preview.coords),
        rotation = CloneRotation(preview.rotation),
        fov = tonumber(preview.fov) or 0.0,
        visionMode = TrimString(preview.visionMode, 'normal'),
        status = TrimString(preview.status, 'Online'),
    }
end

local function BuildAirFeedTracking(feed)
    local tracking = type(feed.tracking) == 'table' and feed.tracking or {}
    return {
        active = tracking.active == true,
        targetNetId = tonumber(tracking.targetNetId),
        targetType = tracking.targetType,
        targetCoords = CloneVec3(tracking.targetCoords),
        heading = tonumber(tracking.heading),
        plate = TrimString(tracking.plate, nil),
        vehicleLabel = TrimString(tracking.vehicleLabel, nil),
    }
end

local function BuildAirFeedPublic(feed)
    if type(feed) ~= 'table' then
        return nil
    end

    return {
        feedId = feed.feedId,
        heliNetId = tonumber(feed.heliNetId),
        label = TrimString(feed.label, 'AIR SUPPORT'),
        callsign = TrimString(feed.callsign, 'AIR'),
        pilotSource = tonumber(feed.pilotSource),
        operatorSource = tonumber(feed.operatorSource),
        cameraActive = feed.cameraActive == true,
        preview = BuildAirFeedPreview(feed),
        tracking = BuildAirFeedTracking(feed),
        lastSeenAt = tonumber(feed.lastSeenAt) or 0,
    }
end

local function UpsertAirFeed(vehicleNetId, payload)
    local feed = ActiveAirFeeds[vehicleNetId] or {
        feedId = BuildFeedId(vehicleNetId),
        heliNetId = vehicleNetId,
    }

    feed.feedId = BuildFeedId(vehicleNetId)
    feed.heliNetId = vehicleNetId
    feed.operatorSource = tonumber(payload.operatorSource) or nil
    feed.label = TrimString(payload.label, feed.label or ('AIR-%s'):format(tostring(vehicleNetId)))
    feed.callsign = ResolveAirFeedCallsign(feed.operatorSource)
    feed.cameraActive = true
    feed.lastSeenAt = GetGameTimer()
    feed.preview = {
        coords = CloneVec3(payload.camCoords),
        rotation = CloneRotation(payload.camRot),
        fov = tonumber(payload.fov) or 0.0,
        visionMode = TrimString(payload.visionMode, 'normal'),
        status = 'Online',
    }
    feed.tracking = feed.tracking or {}

    ActiveAirFeeds[vehicleNetId] = feed
    return feed
end

local function RefreshAirFeedTracking(vehicleNetId, feed)
    if not vehicleNetId or type(feed) ~= 'table' then
        return
    end

    local trackingState = HeliTracking[vehicleNetId]
    local tracking = {
        active = false,
        targetNetId = nil,
        targetType = nil,
        targetCoords = nil,
        heading = nil,
        plate = nil,
        vehicleLabel = nil,
    }

    if trackingState and trackingState.active == true then
        tracking.active = true
        tracking.targetNetId = tonumber(trackingState.targetNetId)
        tracking.targetType = trackingState.targetType

        local targetEntity = tracking.targetNetId and NetworkGetEntityFromNetworkId(tracking.targetNetId) or 0
        if targetEntity and targetEntity ~= 0 and DoesEntityExist(targetEntity) then
            tracking.targetCoords = CloneVec3(GetEntityCoords(targetEntity))
            tracking.heading = tonumber(GetEntityHeading(targetEntity)) or 0.0

            if tracking.targetType == 'vehicle' then
                tracking.plate = TrimString(GetVehicleNumberPlateText(targetEntity), nil)
                tracking.vehicleLabel = tracking.plate or ('Vehicle %s'):format(tostring(tracking.targetNetId))
            else
                tracking.vehicleLabel = ('Ped %s'):format(tostring(tracking.targetNetId))
            end
        else
            tracking.active = false
        end
    end

    feed.tracking = tracking
end

local function RemoveAirFeed(vehicleNetId)
    ActiveAirFeeds[vehicleNetId] = nil
end

local function GetActiveAirFeeds()
    local feeds = {}
    for _, feed in pairs(ActiveAirFeeds) do
        if type(feed) == 'table' and feed.cameraActive == true then
            feeds[#feeds + 1] = BuildAirFeedPublic(feed)
        end
    end

    table_sort(feeds, function(a, b)
        local left = tonumber(a and a.lastSeenAt) or 0
        local right = tonumber(b and b.lastSeenAt) or 0
        if left == right then
            return (tonumber(a and a.heliNetId) or 0) < (tonumber(b and b.heliNetId) or 0)
        end
        return left > right
    end)

    return feeds
end

local function GetAirFeedById(feedId)
    local vehicleNetId = ParseFeedId(feedId)
    if not vehicleNetId then
        return nil
    end

    return BuildAirFeedPublic(ActiveAirFeeds[vehicleNetId])
end

local function GetTrackedDatalinkTargets()
    local targets = {}

    for _, feed in pairs(ActiveAirFeeds) do
        local publicFeed = BuildAirFeedPublic(feed)
        local tracking = publicFeed and publicFeed.tracking
        if publicFeed
            and tracking
            and tracking.active == true
            and tracking.targetType == 'vehicle'
            and type(tracking.targetCoords) == 'table' then
            targets[#targets + 1] = {
                feedId = publicFeed.feedId,
                heliNetId = publicFeed.heliNetId,
                heliLabel = publicFeed.label,
                coords = tracking.targetCoords,
                heading = tracking.heading,
                plate = tracking.plate,
                vehicleLabel = tracking.vehicleLabel,
                updatedAt = publicFeed.lastSeenAt,
            }
        end
    end

    table_sort(targets, function(a, b)
        local left = tonumber(a and a.updatedAt) or 0
        local right = tonumber(b and b.updatedAt) or 0
        if left == right then
            return (tostring(a and a.feedId or '')) < (tostring(b and b.feedId or ''))
        end
        return left > right
    end)

    return targets
end

exports('GetActiveAirFeeds', GetActiveAirFeeds)
exports('GetAirFeedById', GetAirFeedById)
exports('GetTrackedDatalinkTargets', GetTrackedDatalinkTargets)

local LastSpotlightBroadcastAt = {}
local LastSpotlightPositionAt = {}
local LastSpotlightRadiusAt = {}

local LastTrackingStartAt = {}
local LastTrackingStopAt = {}
local LastTrackingStateAt = {}

local function RateLimitTracking(src, eventName, now)
    local minIntervalMs = 0

    if eventName == 'start' then
        minIntervalMs = 350
        local last = LastTrackingStartAt[src] or 0
        if (now - last) < minIntervalMs then return false end
        LastTrackingStartAt[src] = now
        return true
    end

    if eventName == 'stop' then
        minIntervalMs = 250
        local last = LastTrackingStopAt[src] or 0
        if (now - last) < minIntervalMs then return false end
        LastTrackingStopAt[src] = now
        return true
    end

    if eventName == 'state' then
        minIntervalMs = 600
        local last = LastTrackingStateAt[src] or 0
        if (now - last) < minIntervalMs then return false end
        LastTrackingStateAt[src] = now
        return true
    end

    return true
end

local function GetNetSyncConfig()
    local net = Config and Config.Spotlight and Config.Spotlight.NetSync
    local posInterval = 150
    local broadcastInterval = 150
    local minMove = 0.25

    if net then
        posInterval = net.PositionIntervalMs or posInterval
        broadcastInterval = net.BroadcastIntervalMs or broadcastInterval
        minMove = net.MinMoveDistance or minMove
    end

    return posInterval, broadcastInterval, minMove
end

local function CoordsDistance(a, b)
    if not a or not b then return math.huge end
    local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
    local bx, by, bz = b.x or b[1], b.y or b[2], b.z or b[3]
    if not ax or not ay or not az or not bx or not by or not bz then
        return math.huge
    end
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function MaybeBroadcastSpotlight(vehicleNetId)
    local _, broadcastInterval = GetNetSyncConfig()
    local now = GetGameTimer()
    local last = LastSpotlightBroadcastAt[vehicleNetId] or 0
    if (now - last) < broadcastInterval then
        return
    end
    LastSpotlightBroadcastAt[vehicleNetId] = now
    TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, ActiveSpotlights[vehicleNetId])
end

RegisterNetEvent('polcam:createPOI')
AddEventHandler('polcam:createPOI', function(poi)
    local source = source

    if not poi or not poi.id or not poi.coords then
        return
    end

    poi.serverTime = os.time()
    poi.creator = source

    ServerPOIs[poi.id] = poi

    TriggerClientEvent('polcam:receivePOI', -1, poi)

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] POI created by player " .. source .. ": " .. poi.id)
    end
end)

RegisterNetEvent('polcam:removePOI')
AddEventHandler('polcam:removePOI', function(poiId)
    local source = source

    local poi = ServerPOIs[poiId]
    if poi and poi.creator == source then
        ServerPOIs[poiId] = nil

        TriggerClientEvent('polcam:poiRemoved', -1, poiId)

        if Config and Config.Debug and Config.Debug.Enabled then
            print("[PolCam] POI removed by player " .. source .. ": " .. poiId)
        end
    end
end)

RegisterNetEvent('polcam:requestPOIs')
AddEventHandler('polcam:requestPOIs', function()
    local source = source

    TriggerClientEvent('polcam:syncAllPOIs', source, ServerPOIs)

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Synced POIs to player " .. source)
    end
end)

local function PickNextCameraOwner(vehicleNetId, excludingSrc)
    local waitlist = CameraWaitlists[vehicleNetId]
    if not waitlist then return nil end

    local bestSrc = nil
    local bestAt = 0
    for src, lastAt in pairs(waitlist) do
        if src ~= excludingSrc and type(lastAt) == 'number' and lastAt > bestAt then
            bestSrc = src
            bestAt = lastAt
        end
    end
    return bestSrc
end

local function HandoffCamera(vehicleNetId, oldOwner)
    DebugLog("[PolCam Server DEBUG] HandoffCamera called - vehicleNetId: " .. tostring(vehicleNetId) .. ", oldOwner: " .. tostring(oldOwner))

    local nextOwner = PickNextCameraOwner(vehicleNetId, oldOwner)
    if not nextOwner then

        DebugLog("[PolCam Server DEBUG] No next owner in waitlist, skipping forceReleaseAll")

        local spotlight = ActiveSpotlights[vehicleNetId]
        if spotlight and spotlight.owner == oldOwner then
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
            TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, nil)
        end

        return
    end

    TriggerClientEvent('polcam:forceReleaseAll', oldOwner)
    DebugLog("[PolCam Server DEBUG] Sent polcam:forceReleaseAll to oldOwner: " .. tostring(oldOwner))

    ActiveHeliCameras[vehicleNetId] = nextOwner
    CameraWaitlists[vehicleNetId] = nil

    TriggerClientEvent('polcam:cameraClaimResult', nextOwner, true)

    local sharedState = SharedCameraState[vehicleNetId]
    if sharedState then
        TriggerClientEvent('polcam:receiveCameraState', nextOwner, vehicleNetId, sharedState)

        if Config and Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Handed off camera state for heli %d from player %d to player %d", vehicleNetId, oldOwner, nextOwner))
        end
    end

    local tracking = HeliTracking[vehicleNetId]
    if tracking and tracking.active then
        tracking.ownerSrc = nextOwner

        BroadcastHeliTracking(vehicleNetId)
        DebugLog("[PolCam Server DEBUG] Transferred tracking ownership to new owner: " .. tostring(nextOwner))
    end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.active then
        spotlight.owner = nextOwner
        TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, spotlight)

        TriggerClientEvent('polcam:spotlightEnsureOn', nextOwner, spotlight.radius, spotlight.color)
    end
end

RegisterNetEvent('polcam:cameraClaim')
AddEventHandler('polcam:cameraClaim', function(vehicleNetId)
    local src = source
    if not vehicleNetId then
        TriggerClientEvent('polcam:cameraClaimResult', src, false)
        return
    end

    local owner = ActiveHeliCameras[vehicleNetId]
    if owner == nil or owner == src then
        ActiveHeliCameras[vehicleNetId] = src
        CameraWaitlists[vehicleNetId] = nil
        TriggerClientEvent('polcam:cameraClaimResult', src, true)
        return
    end

    CameraWaitlists[vehicleNetId] = CameraWaitlists[vehicleNetId] or {}
    CameraWaitlists[vehicleNetId][src] = GetGameTimer()

    TriggerClientEvent('polcam:cameraClaimResult', src, false, owner)
end)

RegisterNetEvent('polcam:cameraRelease')
AddEventHandler('polcam:cameraRelease', function(vehicleNetId)
    local src = source
    if not vehicleNetId then return end

    if CameraWaitlists[vehicleNetId] then
        CameraWaitlists[vehicleNetId][src] = nil
    end

    if ActiveHeliCameras[vehicleNetId] == src then
        ActiveHeliCameras[vehicleNetId] = nil
        HandoffCamera(vehicleNetId, src)
    end
end)

local function HandlePlayerDropped(src)
    LastTrackingStartAt[src] = nil
    LastTrackingStopAt[src] = nil
    LastTrackingStateAt[src] = nil

    for vehNetId, owner in pairs(ActiveHeliCameras) do
        if owner == src then
            ActiveHeliCameras[vehNetId] = nil
            HandoffCamera(vehNetId, src)
        end
    end

    for vehNetId, waitlist in pairs(CameraWaitlists) do
        if waitlist and waitlist[src] then
            waitlist[src] = nil
        end
    end

    for vehNetId, feed in pairs(ActiveAirFeeds) do
        if type(feed) == 'table' and tonumber(feed.operatorSource) == src then
            RemoveAirFeed(vehNetId)
        end
    end

    for vehicleNetId, spotlight in pairs(ActiveSpotlights) do
        if spotlight and spotlight.owner == src then
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
            TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, nil)
        end
    end

    for vehicleNetId, tracking in pairs(HeliTracking) do
        if tracking and tracking.ownerSrc == src then

            local hasOtherOccupants = false
            local players = GetPlayers()
            for _, playerId in ipairs(players) do
                local playerSrc = tonumber(playerId)
                if playerSrc and playerSrc ~= src then
                    local ped = GetPlayerPed(playerSrc)
                    if ped and ped ~= 0 then
                        local playerVeh = GetVehiclePedIsIn(ped, false)
                        if playerVeh and playerVeh ~= 0 then
                            local playerVehNetId = (DoesEntityExist(playerVeh) and NetworkGetNetworkIdFromEntity(playerVeh) or nil)
                            if playerVehNetId == vehicleNetId then
                                hasOtherOccupants = true
                                break
                            end
                        end
                    end
                end
            end

            if hasOtherOccupants then

                for _, playerId in ipairs(players) do
                    local playerSrc = tonumber(playerId)
                    if playerSrc and playerSrc ~= src then
                        local ped = GetPlayerPed(playerSrc)
                        if ped and ped ~= 0 then
                            local playerVeh = GetVehiclePedIsIn(ped, false)
                            if playerVeh and playerVeh ~= 0 then
                                local playerVehNetId = (DoesEntityExist(playerVeh) and NetworkGetNetworkIdFromEntity(playerVeh) or nil)
                                if playerVehNetId == vehicleNetId then
                                    tracking.ownerSrc = playerSrc
                                    BroadcastHeliTracking(vehicleNetId)
                                    DebugLog("[PolCam Server DEBUG] Transferred tracking ownership from disconnected player to: " .. tostring(playerSrc))
                                    break
                                end
                            end
                        end
                    end
                end
            else

                ClearHeliTracking(vehicleNetId)
                HeliTracking[vehicleNetId] = nil
                DebugLog("[PolCam Server DEBUG] Cleared HeliTracking for empty heli: " .. tostring(vehicleNetId))
            end
        end
    end

    if ActiveRappels[src] then
        ActiveRappels[src] = nil
    end

    for id, marker in pairs(SyncedMarkers or {}) do
        if type(marker) == 'table' and marker.creator == src then
            SyncedMarkers[id] = nil
            TriggerClientEvent('polcam:syncedMarkerRemoved', -1, id)
        end
    end

end

RegisterNetEvent('polcam:cameraStateSync')
AddEventHandler('polcam:cameraStateSync', function(vehicleNetId, state)
    local src = source
    if not vehicleNetId then return end
    if type(state) ~= 'table' then return end

    if ActiveHeliCameras[vehicleNetId] ~= src then return end

    SharedCameraState[vehicleNetId] = {
        heading = state.heading,
        pitch = state.pitch,
        zoom = state.zoom,
        targetZoom = state.targetZoom,
        visionMode = state.visionMode,
        lockedTargetNetId = state.lockedTargetNetId,
        lockedTargetType = state.lockedTargetType,
        groundLockPoint = state.groundLockPoint,
        lastUpdate = GetGameTimer(),
        lastOwner = src
    }

    if Config and Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Camera state synced for heli %d by player %d", vehicleNetId, src))
    end
end)

RegisterNetEvent('polcam:requestCameraState')
AddEventHandler('polcam:requestCameraState', function(vehicleNetId)
    local src = source
    if not vehicleNetId then return end

    local state = SharedCameraState[vehicleNetId]
    if state then
        TriggerClientEvent('polcam:receiveCameraState', src, vehicleNetId, state)

        if Config and Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Sent camera state for heli %d to player %d", vehicleNetId, src))
        end
    else

        TriggerClientEvent('polcam:receiveCameraState', src, vehicleNetId, nil)
    end
end)

local function CleanupStaleStates()
    local now = GetGameTimer()
    local staleThreshold = (Config and Config.SharedCamera and Config.SharedCamera.StateTimeoutMs) or 300000

    for vehicleNetId, state in pairs(SharedCameraState) do
        if state.lastUpdate and (now - state.lastUpdate) > staleThreshold then

            SharedCameraState[vehicleNetId] = nil
            if Config and Config.Debug and Config.Debug.Enabled then
                print(string.format("[PolCam] Cleared stale camera state for heli %d", vehicleNetId))
            end
        end
    end
end

RegisterNetEvent('polcam:spotlightSync')
AddEventHandler('polcam:spotlightSync', function(active, radius, initialGroundCoords, initialHeliCoords, color)
    local src = source
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then return end

    if active then

        local existingSpotlight = ActiveSpotlights[vehicleNetId]

        if existingSpotlight and existingSpotlight.owner and existingSpotlight.owner ~= src then
            local oldOwner = existingSpotlight.owner
            TriggerClientEvent('polcam:forceReleaseAll', oldOwner)
        end

        local tracking = HeliTracking[vehicleNetId]
        local targetNetId = (existingSpotlight and existingSpotlight.targetNetId) or (tracking and tracking.targetNetId) or nil
        local trackingTarget = (existingSpotlight and existingSpotlight.trackingTarget) or (tracking and tracking.active) or false

        ActiveSpotlights[vehicleNetId] = {
            active = true,
            radius = radius or 5.0,
            color = color or (existingSpotlight and existingSpotlight.color) or nil,
            owner = src,
            vehicleNetId = vehicleNetId,
            heliCoords = initialHeliCoords or (existingSpotlight and existingSpotlight.heliCoords) or nil,
            groundCoords = initialGroundCoords or (existingSpotlight and existingSpotlight.groundCoords) or nil,
            targetNetId = targetNetId,
            trackingTarget = trackingTarget
        }

        LastSpotlightPositionAt[vehicleNetId] = nil
    else
        local existing = ActiveSpotlights[vehicleNetId]
        if existing and existing.owner == src then
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
        end
    end

    TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, ActiveSpotlights[vehicleNetId])
end)

RegisterNetEvent('polcam:spotlightRadius')
AddEventHandler('polcam:spotlightRadius', function(radius)
    local src = source
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local now = GetGameTimer()
        local last = LastSpotlightRadiusAt[vehicleNetId] or 0

        if (now - last) < 100 then
            return
        end
        LastSpotlightRadiusAt[vehicleNetId] = now

        spotlight.radius = radius
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:spotlightColor')
AddEventHandler('polcam:spotlightColor', function(color)
    local src = source
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        spotlight.color = color
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:spotlightPosition')
AddEventHandler('polcam:spotlightPosition', function(groundCoords, heliCoords)
    local src = source
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local posInterval, _, minMove = GetNetSyncConfig()
        local now = GetGameTimer()
        local lastPos = LastSpotlightPositionAt[vehicleNetId] or 0
        if (now - lastPos) < posInterval then
            return
        end

        local prevGround = spotlight.groundCoords
        local prevHeli = spotlight.heliCoords
        local movedGround = CoordsDistance(groundCoords, prevGround) >= minMove
        local movedHeli = CoordsDistance(heliCoords, prevHeli) >= minMove

        if not prevGround or not prevHeli then
            movedGround = true
            movedHeli = true
        end

        if not (movedGround or movedHeli) then
            return
        end

        LastSpotlightPositionAt[vehicleNetId] = now
        spotlight.groundCoords = groundCoords
        spotlight.heliCoords = heliCoords
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

local function IsVehicleOccupiedByAnyPlayer(vehicleNetId)
    if not vehicleNetId then return false end

    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local playerSrc = tonumber(playerId)
        if playerSrc then
            local ped = GetPlayerPed(playerSrc)
            if ped and ped ~= 0 then
                local playerVeh = GetVehiclePedIsIn(ped, false)
                if playerVeh and playerVeh ~= 0 then
                    local playerVehNetId = (DoesEntityExist(playerVeh) and NetworkGetNetworkIdFromEntity(playerVeh) or nil)
                    if playerVehNetId == vehicleNetId then
                        return true
                    end
                end
            end
        end
    end

    return false
end

BroadcastHeliTracking = function(vehicleNetId)
    if not vehicleNetId then
        if Config and Config.Debug and Config.Debug.Enabled then
            print("[PolCam Server DEBUG] BroadcastHeliTracking: vehicleNetId is nil, aborting")
        end
        return
    end

    local state = HeliTracking[vehicleNetId] or { active = false, seq = 0 }
    state.vehicleNetId = vehicleNetId

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam Server DEBUG] BroadcastHeliTracking - vehicleNetId: " .. tostring(vehicleNetId))
        print("[PolCam Server DEBUG] State to broadcast - active: " .. tostring(state.active) .. ", seq: " .. tostring(state.seq))
    end

    local players = GetPlayers()
    local sentCount = 0
    for _, playerId in ipairs(players) do
        local playerSrc = tonumber(playerId)
        if playerSrc then
            local ped = GetPlayerPed(playerSrc)
            if ped and ped ~= 0 then
                local playerVeh = GetVehiclePedIsIn(ped, false)
                if playerVeh and playerVeh ~= 0 then
                    local playerVehNetId = (DoesEntityExist(playerVeh) and NetworkGetNetworkIdFromEntity(playerVeh) or nil)
                    if Config and Config.Debug and Config.Debug.Enabled then
                        print("[PolCam Server DEBUG] Checking player " .. tostring(playerSrc) .. " - playerVehNetId: " .. tostring(playerVehNetId))
                    end
                    if playerVehNetId == vehicleNetId then

                        TriggerClientEvent('polcam:heliTrackingState', playerSrc, vehicleNetId, state)
                        sentCount = sentCount + 1
                        if Config and Config.Debug and Config.Debug.Enabled then
                            print("[PolCam Server DEBUG] Sent heliTrackingState to player " .. tostring(playerSrc))
                        end
                    end
                end
            end
        end
    end

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam Server DEBUG] BroadcastHeliTracking complete - sent to " .. tostring(sentCount) .. " players")
    end
end

ClearHeliTracking = function(vehicleNetId)
    if not vehicleNetId then return end

    local currentState = HeliTracking[vehicleNetId] or { seq = 0 }
    local newSeq = (currentState.seq or 0) + 1

    HeliTracking[vehicleNetId] = {
        active = false,
        targetNetId = nil,
        targetType = nil,
        ownerSrc = nil,
        seq = newSeq
    }

    local tracking = HeliTracking[vehicleNetId]

    if ActiveSpotlights[vehicleNetId] then
        ActiveSpotlights[vehicleNetId].targetNetId = nil
        ActiveSpotlights[vehicleNetId].trackingTarget = false
    end

    BroadcastHeliTracking(vehicleNetId)

    if tracking and not tracking.active and not IsVehicleOccupiedByAnyPlayer(vehicleNetId) then
        HeliTracking[vehicleNetId] = nil
    end
end

local function IsAllowedHelicopterEntity(vehicle)
    if not vehicle or vehicle == 0 then return false end

    local allowed = Config and Config.AllowedHelicopters
    if type(allowed) ~= 'table' then return true end

    local modelHash = GetEntityModel(vehicle)
    for _, name in ipairs(allowed) do
        if GetHashKey(name) == modelHash then
            return true
        end
    end

    return false
end

local function IsAllowedSeatForPed(ped, vehicle)
    local allowedSeats = (Config and Config.AllowedSeats)
    if type(allowedSeats) ~= 'table' then return true end

    for _, seat in ipairs(allowedSeats) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return true
        end
    end

    return false
end

RegisterNetEvent('polcam:feedHeartbeat')
AddEventHandler('polcam:feedHeartbeat', function(payload)
    local src = source
    if type(payload) ~= 'table' then
        return
    end

    local vehicleNetId = tonumber(payload.heliNetId)
    if not vehicleNetId or vehicleNetId <= 0 then
        return
    end

    local operatorSource = tonumber(payload.operatorSource)
    if operatorSource ~= src then
        return
    end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    if not IsAllowedHelicopterEntity(vehicle) or not IsAllowedSeatForPed(ped, vehicle) then
        return
    end

    local currentVehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if currentVehicleNetId ~= vehicleNetId then
        return
    end

    if ActiveHeliCameras[vehicleNetId] ~= src then
        return
    end

    local coords = CloneVec3(payload.camCoords)
    local rotation = CloneRotation(payload.camRot)
    if not coords or not rotation then
        return
    end

    local feed = UpsertAirFeed(vehicleNetId, payload)
    feed.pilotSource = ResolvePilotSource(vehicle)
    feed.callsign = ResolveAirFeedCallsign(src)
    RefreshAirFeedTracking(vehicleNetId, feed)
end)

local function MaintainAirFeeds()
    local now = GetGameTimer()

    for vehicleNetId, feed in pairs(ActiveAirFeeds) do
        if type(feed) ~= 'table' then
            ActiveAirFeeds[vehicleNetId] = nil
        else
            local age = now - (tonumber(feed.lastSeenAt) or 0)
            if age > AIR_FEED_STALE_MS then
                RemoveAirFeed(vehicleNetId)
            else
                local ownerSrc = tonumber(feed.operatorSource) or 0
                local ownerPed = ownerSrc > 0 and GetPlayerPed(ownerSrc) or 0
                local ownerVehicle = ownerPed and ownerPed ~= 0 and GetVehiclePedIsIn(ownerPed, false) or 0
                local ownerVehicleNetId = ownerVehicle ~= 0 and DoesEntityExist(ownerVehicle) and NetworkGetNetworkIdFromEntity(ownerVehicle) or nil

                if ActiveHeliCameras[vehicleNetId] ~= ownerSrc or ownerVehicleNetId ~= vehicleNetId then
                    RemoveAirFeed(vehicleNetId)
                else
                    feed.cameraActive = true
                    feed.pilotSource = ResolvePilotSource(ownerVehicle)
                    feed.callsign = ResolveAirFeedCallsign(ownerSrc)
                    RefreshAirFeedTracking(vehicleNetId, feed)
                end
            end
        end
    end
end

local function GetMaxTrackingDistanceForType(targetType)
    local tracking = Config and Config.Tracking
    if type(tracking) ~= 'table' then return 1000.0 end

    if targetType == 'vehicle' then
        return tracking.TargetingMaxDistanceVehicles or 1000.0
    end

    if targetType == 'ped' then
        return tracking.TargetingMaxDistancePeds or 1000.0
    end

    return 1000.0
end

local function ValidateTrackingTargetRequest(src, targetNetId, targetType)
    if type(targetNetId) ~= 'number' or targetNetId <= 0 then
        return nil
    end

    if targetType ~= 'vehicle' and targetType ~= 'ped' then
        return nil
    end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 then
        return nil
    end

    if not IsAllowedHelicopterEntity(vehicle) then
        return nil
    end

    if not IsAllowedSeatForPed(ped, vehicle) then
        return nil
    end

    local vehicleNetId = DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then
        return nil
    end

    local targetEntity = NetworkGetEntityFromNetworkId(targetNetId)
    if not targetEntity or targetEntity == 0 or not DoesEntityExist(targetEntity) then
        return nil
    end

    if targetType == 'vehicle' and not IsServerVehicleEntity(targetEntity) then
        return nil
    end

    if targetType == 'ped' and not IsServerPedEntity(targetEntity) then
        return nil
    end

    local heliCoords = GetEntityCoords(vehicle)
    local targetCoords = GetEntityCoords(targetEntity)
    local dx = heliCoords.x - targetCoords.x
    local dy = heliCoords.y - targetCoords.y
    local dz = heliCoords.z - targetCoords.z
    local maxDist = GetMaxTrackingDistanceForType(targetType)
    if (dx * dx + dy * dy + dz * dz) > (maxDist * maxDist) then
        return nil
    end

    return vehicleNetId
end

local function SetHeliTracking(vehicleNetId, src, targetNetId, targetType)
    if not vehicleNetId then return end

    local currentState = HeliTracking[vehicleNetId] or { seq = 0 }
    local newSeq = (currentState.seq or 0) + 1

    HeliTracking[vehicleNetId] = {
        active = true,
        targetNetId = targetNetId,
        targetType = targetType,
        ownerSrc = src,
        seq = newSeq
    }

    if ActiveSpotlights[vehicleNetId] then
        ActiveSpotlights[vehicleNetId].targetNetId = targetNetId
        ActiveSpotlights[vehicleNetId].trackingTarget = true
    end

    BroadcastHeliTracking(vehicleNetId)
end

RegisterNetEvent('polcam:trackingRequestStart')
AddEventHandler('polcam:trackingRequestStart', function(targetNetId, targetType)
    local src = source
    local now = GetGameTimer()
    if not RateLimitTracking(src, 'start', now) then
        return
    end

    local vehicleNetId = ValidateTrackingTargetRequest(src, targetNetId, targetType)
    if not vehicleNetId then
        return
    end

    SetHeliTracking(vehicleNetId, src, targetNetId, targetType)
end)

RegisterNetEvent('polcam:trackingRequestStop')
AddEventHandler('polcam:trackingRequestStop', function()
    local src = source
    local now = GetGameTimer()
    if not RateLimitTracking(src, 'stop', now) then
        return
    end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 then
        return
    end

    local vehicleNetId = DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then
        return
    end

    local tracking = HeliTracking[vehicleNetId]
    if tracking and tracking.ownerSrc and tracking.ownerSrc ~= src then

    end

    ClearHeliTracking(vehicleNetId)
end)

RegisterNetEvent('polcam:trackingSync')
AddEventHandler('polcam:trackingSync', function(active, targetNetId, targetType)
    local src = source
    local now = GetGameTimer()

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 then
        return
    end

    local vehicleNetId = DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then
        return
    end

    if active then
        if not RateLimitTracking(src, 'start', now) then
            return
        end

        local validatedVehicleNetId = ValidateTrackingTargetRequest(src, targetNetId, targetType)
        if not validatedVehicleNetId then
            return
        end

        SetHeliTracking(validatedVehicleNetId, src, targetNetId, targetType)
    else
        if not RateLimitTracking(src, 'stop', now) then
            return
        end

        if not IsAllowedHelicopterEntity(vehicle) or not IsAllowedSeatForPed(ped, vehicle) then
            return
        end

        ClearHeliTracking(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:trackingRequestState')
AddEventHandler('polcam:trackingRequestState', function(vehicleNetId)
    local src = source
    local now = GetGameTimer()
    if not RateLimitTracking(src, 'state', now) then
        return
    end

    if type(vehicleNetId) ~= 'number' then return end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 then
        return
    end

    local myVehicleNetId = DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if myVehicleNetId ~= vehicleNetId then
        return
    end

    local state = HeliTracking[vehicleNetId] or { active = false, seq = 0 }
    state.vehicleNetId = vehicleNetId
    TriggerClientEvent('polcam:heliTrackingState', src, vehicleNetId, state)
end)

RegisterNetEvent('polcam:trackingPosition')
AddEventHandler('polcam:trackingPosition', function(targetCoords, heliCoords, targetNetId)
    local src = source
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local posInterval, _, _ = GetNetSyncConfig()
        local now = GetGameTimer()
        local lastPos = LastSpotlightPositionAt[vehicleNetId] or 0
        if (now - lastPos) < posInterval then
            return
        end

        LastSpotlightPositionAt[vehicleNetId] = now
        spotlight.groundCoords = targetCoords
        spotlight.heliCoords = heliCoords
        spotlight.targetNetId = targetNetId
        spotlight.trackingTarget = true
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:rappelStart')
AddEventHandler('polcam:rappelStart', function(data)
    local source = source

    ActiveRappels[source] = {
        startTime = GetGameTimer(),
        vehicleNetId = data.vehicle,
        altitude = data.altitude,
        model = data.model
    }

    TriggerClientEvent('polcam:syncRappel', -1, {
        source = source,
        vehicle = data.vehicle,
        altitude = data.altitude,
        model = data.model,
        action = 'start'
    })

    if Config and Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Player %d started rappeling from %.0f ft", source, data.altitude or 0))
    end
end)

RegisterNetEvent('polcam:rappelEnd')
AddEventHandler('polcam:rappelEnd', function(data)
    local source = source

    if ActiveRappels[source] then
        local duration = (GetGameTimer() - (ActiveRappels[source].startTime or 0)) / 1000
        ActiveRappels[source] = nil

        TriggerClientEvent('polcam:syncRappel', -1, {
            source = source,
            action = 'end',
            duration = duration
        })

        if Config and Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Player %d finished rappeling (%.1fs)", source, duration))
        end
    end
end)

RegisterNetEvent('polcam:createSyncedMarker')
AddEventHandler('polcam:createSyncedMarker', function(markerData)
    local source = source
    local ped = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then return end
    if not DoesEntityExist(vehicle) then return end

    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleNetId then return end

    SyncedMarkers = SyncedMarkers or {}

    local markerId = markerData.id or tostring(source) .. '_' .. tostring(GetGameTimer())

    SyncedMarkers[markerId] = {
        id = markerId,
        coords = markerData.coords,
        type = markerData.type or 'waypoint',
        color = markerData.color,
        creator = source,
        vehicleNetId = vehicleNetId,
        createdAt = GetGameTimer()
    }

    TriggerClientEvent('polcam:receiveSyncedMarker', -1, SyncedMarkers[markerId])

    if Config and Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Synced marker created by player %d", source))
    end
end)

RegisterNetEvent('polcam:removeSyncedMarker')
AddEventHandler('polcam:removeSyncedMarker', function(markerId)
    local source = source

    SyncedMarkers = SyncedMarkers or {}

    local marker = SyncedMarkers[markerId]
    if marker and marker.creator == source then
        SyncedMarkers[markerId] = nil
        TriggerClientEvent('polcam:syncedMarkerRemoved', -1, markerId)
    end
end)

RegisterNetEvent('polcam:requestSyncedMarkers')
AddEventHandler('polcam:requestSyncedMarkers', function(vehicleNetId)
    local source = source

    SyncedMarkers = SyncedMarkers or {}

    local vehicleMarkers = {}
    for id, marker in pairs(SyncedMarkers) do
        if type(marker) == 'table' and marker.vehicleNetId == vehicleNetId then
            vehicleMarkers[id] = marker
        end
    end

    TriggerClientEvent('polcam:syncAllMarkers', source, vehicleMarkers)
end)

CreateThread(function()
    while true do
        MaintainAirFeeds()
        Wait(AIR_FEED_MAINTENANCE_INTERVAL_MS)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)

        local currentTime = os.time()
        local expiryTime = Config and Config.POI and Config.POI.ExpiryTime or 300

        if expiryTime > 0 then
            for id, poi in pairs(ServerPOIs) do
                local age = currentTime - (poi.serverTime or 0)
                if age > expiryTime then
                    ServerPOIs[id] = nil
                    TriggerClientEvent('polcam:poiRemoved', -1, id)

                    if Config and Config.Debug and Config.Debug.Enabled then
                        print("[PolCam] POI expired: " .. id)
                    end
                end
            end
        end

        CleanupStaleStates()
    end
end)

CreateThread(function()
    while true do
        Wait(1000)

        for vehicleNetId, tracking in pairs(HeliTracking) do
            if tracking and tracking.active then
                if not IsVehicleOccupiedByAnyPlayer(vehicleNetId) then
                    ClearHeliTracking(vehicleNetId)
                    HeliTracking[vehicleNetId] = nil
                end
            elseif tracking and not tracking.active then
                if not IsVehicleOccupiedByAnyPlayer(vehicleNetId) then
                    HeliTracking[vehicleNetId] = nil
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    HandlePlayerDropped(source)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Server-side initialized")
        print("[PolCam] POI and spotlight synchronization active")
    end
end)
