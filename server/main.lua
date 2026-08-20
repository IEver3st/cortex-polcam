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
local GetVehicleClass = GetVehicleClass
local GetVehicleNumberPlateText = GetVehicleNumberPlateText
local GetPlayerRoutingBucket = GetPlayerRoutingBucket
local GetEntityRoutingBucket = GetEntityRoutingBucket
local GetPlayers = GetPlayers
local TriggerClientEvent = TriggerClientEvent
local CreateThread = CreateThread
local Wait = Wait
local math_abs = math.abs
local math_floor = math.floor
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

local IsAllowedHelicopterEntity
local IsAllowedSeatForPed
local GetMaxTrackingDistanceForType

local EventRateState = {}
local MAX_COORD_ABS = 20000.0
local MAX_SYNC_DISTANCE = 2000.0

local function IsFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function ClampNumber(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not IsFiniteNumber(number) then
        return fallback
    end
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function PositiveInteger(value)
    local number = tonumber(value)
    if not IsFiniteNumber(number) or number <= 0 or number ~= math_floor(number) then
        return nil
    end
    return number
end

local function BoundedString(value, maximumLength, fallback)
    if type(value) ~= 'string' then
        return fallback
    end
    local text = value:gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' or #text > maximumLength then
        return fallback
    end
    return text
end

local function AllowEvent(src, key, minimumIntervalMs)
    local now = GetGameTimer()
    local playerState = EventRateState[src]
    if not playerState then
        playerState = {}
        EventRateState[src] = playerState
    end

    local lastAt = playerState[key] or 0
    if (now - lastAt) < minimumIntervalMs then
        return false
    end

    playerState[key] = now
    return true
end

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
    if not IsFiniteNumber(x) or not IsFiniteNumber(y) or not IsFiniteNumber(z) then
        return nil
    end

    if math_abs(x) > MAX_COORD_ABS or math_abs(y) > MAX_COORD_ABS or math_abs(z) > MAX_COORD_ABS then
        return nil
    end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function CloneRotation(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' then
        return nil
    end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if not IsFiniteNumber(x) or not IsFiniteNumber(y) or not IsFiniteNumber(z) then
        return nil
    end

    if math_abs(x) > 3600.0 or math_abs(y) > 3600.0 or math_abs(z) > 3600.0 then
        return nil
    end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function BroadcastToBucket(eventName, routingBucket, ...)
    if type(routingBucket) ~= 'number' then return end

    for _, playerId in ipairs(GetPlayers()) do
        local playerSrc = tonumber(playerId)
        if playerSrc and GetPlayerRoutingBucket(playerSrc) == routingBucket then
            TriggerClientEvent(eventName, playerSrc, ...)
        end
    end
end

local function SanitizeColor(value)
    if type(value) ~= 'table' then
        return nil
    end

    local r = ClampNumber(value.r or value[1], 0, 255, nil)
    local g = ClampNumber(value.g or value[2], 0, 255, nil)
    local b = ClampNumber(value.b or value[3], 0, 255, nil)
    if not r or not g or not b then
        return nil
    end

    return { math_floor(r + 0.5), math_floor(g + 0.5), math_floor(b + 0.5) }
end

local function ResolveAuthorizedVehicle(src, expectedNetId)
    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, nil, nil
    end

    if not IsAllowedHelicopterEntity(vehicle) or not IsAllowedSeatForPed(ped, vehicle) then
        return nil, nil, nil
    end

    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleNetId or vehicleNetId <= 0 then
        return nil, nil, nil
    end

    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(vehicle) then
        return nil, nil, nil
    end

    if expectedNetId ~= nil and PositiveInteger(expectedNetId) ~= vehicleNetId then
        return nil, nil, nil
    end

    return ped, vehicle, vehicleNetId
end

local function ValidateTargetForVehicle(vehicle, targetNetId, targetType, maximumDistance)
    targetNetId = PositiveInteger(targetNetId)
    if not targetNetId or (targetType ~= 'vehicle' and targetType ~= 'ped') then
        return nil, nil
    end

    local targetEntity = NetworkGetEntityFromNetworkId(targetNetId)
    if not targetEntity or targetEntity == 0 or not DoesEntityExist(targetEntity) then
        return nil, nil
    end

    local expectedEntityType = targetType == 'vehicle' and 2 or 1
    if GetEntityType(targetEntity) ~= expectedEntityType then
        return nil, nil
    end

    if GetEntityRoutingBucket(vehicle) ~= GetEntityRoutingBucket(targetEntity) then
        return nil, nil
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local targetCoords = GetEntityCoords(targetEntity)
    local dx = vehicleCoords.x - targetCoords.x
    local dy = vehicleCoords.y - targetCoords.y
    local dz = vehicleCoords.z - targetCoords.z
    local maxDistance = ClampNumber(maximumDistance, 1.0, MAX_SYNC_DISTANCE, 1000.0)
    if (dx * dx + dy * dy + dz * dz) > (maxDistance * maxDistance) then
        return nil, nil
    end

    return targetNetId, targetEntity
end

local function CoordsWithinVehicleRange(vehicle, coords, maximumDistance)
    local clean = CloneVec3(coords)
    if not clean then return nil end

    local vehicleCoords = GetEntityCoords(vehicle)
    local dx = clean.x - vehicleCoords.x
    local dy = clean.y - vehicleCoords.y
    local dz = clean.z - vehicleCoords.z
    local maxDistance = maximumDistance or MAX_SYNC_DISTANCE
    if (dx * dx + dy * dy + dz * dz) > (maxDistance * maxDistance) then
        return nil
    end

    return clean
end

local function BuildFeedId(vehicleNetId)
    return AIR_FEED_ID_PREFIX .. tostring(vehicleNetId)
end

local function ParseFeedId(feedId)
    if type(feedId) == 'number' then
        return PositiveInteger(feedId)
    end

    if type(feedId) ~= 'string' then
        return nil
    end

    local suffix = feedId:match('^' .. AIR_FEED_ID_PREFIX .. '(%d+)$')
    if not suffix then
        return nil
    end

    return PositiveInteger(suffix)
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
        fov = ClampNumber(preview.fov, 1.0, 130.0, 50.0),
        visionMode = BoundedString(preview.visionMode, 24, 'normal'),
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
    feed.label = BoundedString(payload.label, 48, feed.label or ('AIR-%s'):format(tostring(vehicleNetId)))
    feed.callsign = ResolveAirFeedCallsign(feed.operatorSource)
    feed.cameraActive = true
    feed.lastSeenAt = GetGameTimer()
    feed.preview = {
        coords = CloneVec3(payload.camCoords),
        rotation = CloneRotation(payload.camRot),
        fov = ClampNumber(payload.fov, 1.0, 130.0, 50.0),
        visionMode = BoundedString(payload.visionMode, 24, 'normal'),
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

local function IsAirFeedExportAuthorized(feed)
    local integration = rawget(_G, 'CortexPolCamMdtIntegration')
    if type(integration) ~= 'table' or type(integration.isFeedAuthorized) ~= 'function' then
        return true
    end

    local ok, authorized = pcall(integration.isFeedAuthorized, feed)
    return ok and authorized == true
end

local function GetActiveAirFeeds()
    local feeds = {}
    for _, feed in pairs(ActiveAirFeeds) do
        if type(feed) == 'table'
            and feed.cameraActive == true
            and IsAirFeedExportAuthorized(feed) then
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

    local feed = ActiveAirFeeds[vehicleNetId]
    if not IsAirFeedExportAuthorized(feed) then
        return nil
    end

    return BuildAirFeedPublic(feed)
end

local function GetTrackedDatalinkTargets()
    local targets = {}

    for _, feed in pairs(ActiveAirFeeds) do
        local publicFeed = IsAirFeedExportAuthorized(feed) and BuildAirFeedPublic(feed) or nil
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
    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight then
        BroadcastToBucket('polcam:spotlightUpdate', spotlight.routingBucket, vehicleNetId, spotlight)
    end
end

RegisterNetEvent('polcam:createPOI')
AddEventHandler('polcam:createPOI', function(poi)
    local src = source
    if type(poi) ~= 'table' or not AllowEvent(src, 'createPOI', 500) then
        return
    end

    local _, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicle or ActiveHeliCameras[vehicleNetId] ~= src then return end

    local coords = CoordsWithinVehicleRange(vehicle, poi.coords)
    if not coords then return end

    local maxPois = ClampNumber(Config and Config.POI and Config.POI.MaxPOIs, 1, 50, 10)
    local ownedCount = 0
    for _, existing in pairs(ServerPOIs) do
        if type(existing) == 'table' and existing.creator == src then
            ownedCount = ownedCount + 1
        end
    end
    if ownedCount >= maxPois then return end

    local poiId = BoundedString(poi.id, 64, nil)
    local expectedPrefix = '^' .. tostring(src) .. '_%d+$'
    if not poiId or not poiId:match(expectedPrefix) or ServerPOIs[poiId] then return end
    local routingBucket = GetPlayerRoutingBucket(src)
    local sanitized = {
        id = poiId,
        coords = coords,
        type = BoundedString(poi.type, 24, 'waypoint'),
        serverTime = os.time(),
        creator = src,
        owner = src,
        routingBucket = routingBucket,
    }

    ServerPOIs[poiId] = sanitized

    BroadcastToBucket('polcam:receivePOI', routingBucket, sanitized)

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] POI created by player " .. src .. ": " .. poiId)
    end
end)

RegisterNetEvent('polcam:removePOI')
AddEventHandler('polcam:removePOI', function(poiId)
    local src = source
    poiId = BoundedString(poiId, 64, nil)
    if not poiId or not AllowEvent(src, 'removePOI', 250) then return end

    local poi = ServerPOIs[poiId]
    if poi and poi.creator == src then
        ServerPOIs[poiId] = nil

        BroadcastToBucket('polcam:poiRemoved', poi.routingBucket, poiId)

        if Config and Config.Debug and Config.Debug.Enabled then
            print("[PolCam] POI removed by player " .. src .. ": " .. poiId)
        end
    end
end)

RegisterNetEvent('polcam:requestPOIs')
AddEventHandler('polcam:requestPOIs', function()
    local src = source
    local _, _, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId or ActiveHeliCameras[vehicleNetId] ~= src or not AllowEvent(src, 'requestPOIs', 1000) then return end

    local routingBucket = GetPlayerRoutingBucket(src)
    local bucketPois = {}
    for id, poi in pairs(ServerPOIs) do
        if type(poi) == 'table' and poi.routingBucket == routingBucket then
            bucketPois[id] = poi
        end
    end
    TriggerClientEvent('polcam:syncAllPOIs', src, bucketPois)

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Synced POIs to player " .. src)
    end
end)

local function PickNextCameraOwner(vehicleNetId, excludingSrc)
    local waitlist = CameraWaitlists[vehicleNetId]
    if not waitlist then return nil end

    local bestSrc = nil
    local bestAt = 0
    for src, lastAt in pairs(waitlist) do
        local _, _, authorizedNetId = ResolveAuthorizedVehicle(src, vehicleNetId)
        if src ~= excludingSrc and authorizedNetId and type(lastAt) == 'number' and lastAt > bestAt then
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
            local routingBucket = spotlight.routingBucket
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
            BroadcastToBucket('polcam:spotlightUpdate', routingBucket, vehicleNetId, nil)
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
        spotlight.routingBucket = GetPlayerRoutingBucket(nextOwner)
        BroadcastToBucket('polcam:spotlightUpdate', spotlight.routingBucket, vehicleNetId, spotlight)

        TriggerClientEvent('polcam:spotlightEnsureOn', nextOwner, spotlight.radius, spotlight.color)
    end
end

RegisterNetEvent('polcam:cameraClaim')
AddEventHandler('polcam:cameraClaim', function(vehicleNetId)
    local src = source
    local _, _, authorizedNetId = ResolveAuthorizedVehicle(src, vehicleNetId)
    if not authorizedNetId or not AllowEvent(src, 'cameraClaim', 250) then
        TriggerClientEvent('polcam:cameraClaimResult', src, false)
        return
    end
    vehicleNetId = authorizedNetId

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
    vehicleNetId = PositiveInteger(vehicleNetId)
    if not vehicleNetId or not AllowEvent(src, 'cameraRelease', 150) then return end

    if CameraWaitlists[vehicleNetId] then
        CameraWaitlists[vehicleNetId][src] = nil
    end

    if ActiveHeliCameras[vehicleNetId] == src then
        ActiveHeliCameras[vehicleNetId] = nil
        HandoffCamera(vehicleNetId, src)
    end
end)

local function HandlePlayerDropped(src)
    EventRateState[src] = nil
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
            local routingBucket = spotlight.routingBucket
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
            BroadcastToBucket('polcam:spotlightUpdate', routingBucket, vehicleNetId, nil)
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
        local activeRappel = ActiveRappels[src]
        ActiveRappels[src] = nil
        BroadcastToBucket('polcam:syncRappel', activeRappel.routingBucket, {
            source = src,
            action = 'end',
            duration = (GetGameTimer() - (activeRappel.startTime or 0)) / 1000,
        })
    end

    for id, marker in pairs(SyncedMarkers or {}) do
        if type(marker) == 'table' and marker.creator == src then
            SyncedMarkers[id] = nil
            BroadcastToBucket('polcam:syncedMarkerRemoved', marker.routingBucket, id)
        end
    end

end

RegisterNetEvent('polcam:cameraStateSync')
AddEventHandler('polcam:cameraStateSync', function(vehicleNetId, state)
    local src = source
    local _, vehicle, authorizedNetId = ResolveAuthorizedVehicle(src, vehicleNetId)
    if not vehicle or not authorizedNetId or type(state) ~= 'table' then return end
    vehicleNetId = authorizedNetId

    if ActiveHeliCameras[vehicleNetId] ~= src then return end

    local syncInterval = ClampNumber(Config and Config.SharedCamera and Config.SharedCamera.SyncIntervalMs, 100, 5000, 200)
    if not AllowEvent(src, 'cameraStateSync', syncInterval) then return end

    local heading = ClampNumber(state.heading, -3600.0, 3600.0, nil)
    local pitch = ClampNumber(state.pitch, -90.0, 90.0, nil)
    local zoom = ClampNumber(state.zoom, 0.1, 100.0, nil)
    local targetZoom = ClampNumber(state.targetZoom, 0.1, 100.0, zoom)
    local visionMode = BoundedString(state.visionMode, 24, 'normal')
    if not heading or not pitch or not zoom then return end

    local groundLockPoint = nil
    if state.groundLockPoint ~= nil then
        groundLockPoint = CoordsWithinVehicleRange(vehicle, state.groundLockPoint, MAX_SYNC_DISTANCE)
        if not groundLockPoint then return end
    end

    local lockedTargetNetId = state.lockedTargetNetId ~= nil and PositiveInteger(state.lockedTargetNetId) or nil
    local lockedTargetType = state.lockedTargetType
    if state.lockedTargetNetId ~= nil then
        local validatedTargetNetId = ValidateTargetForVehicle(
            vehicle,
            lockedTargetNetId,
            lockedTargetType,
            GetMaxTrackingDistanceForType(lockedTargetType)
        )
        if not validatedTargetNetId then return end
        lockedTargetNetId = validatedTargetNetId
    else
        lockedTargetType = nil
    end

    SharedCameraState[vehicleNetId] = {
        heading = heading,
        pitch = pitch,
        zoom = zoom,
        targetZoom = targetZoom,
        visionMode = visionMode,
        lockedTargetNetId = lockedTargetNetId,
        lockedTargetType = lockedTargetType,
        groundLockPoint = groundLockPoint,
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
    local _, _, authorizedNetId = ResolveAuthorizedVehicle(src, vehicleNetId)
    if not authorizedNetId or not AllowEvent(src, 'requestCameraState', 500) then return end
    vehicleNetId = authorizedNetId

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
    if type(active) ~= 'boolean' or not AllowEvent(src, 'spotlightSync', 150) then return end
    local _, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId then return end

    if active then
        if ActiveHeliCameras[vehicleNetId] ~= src then return end

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
            radius = ClampNumber(radius, 1.0, 25.0, 5.0),
            color = SanitizeColor(color) or (existingSpotlight and existingSpotlight.color) or { 255, 255, 255 },
            owner = src,
            vehicleNetId = vehicleNetId,
            routingBucket = GetPlayerRoutingBucket(src),
            heliCoords = CoordsWithinVehicleRange(vehicle, initialHeliCoords, 25.0) or (existingSpotlight and existingSpotlight.heliCoords) or nil,
            groundCoords = CoordsWithinVehicleRange(vehicle, initialGroundCoords, MAX_SYNC_DISTANCE) or (existingSpotlight and existingSpotlight.groundCoords) or nil,
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

    local activeSpotlight = ActiveSpotlights[vehicleNetId]
    local routingBucket = activeSpotlight and activeSpotlight.routingBucket or GetPlayerRoutingBucket(src)
    BroadcastToBucket('polcam:spotlightUpdate', routingBucket, vehicleNetId, activeSpotlight)
end)

RegisterNetEvent('polcam:spotlightRadius')
AddEventHandler('polcam:spotlightRadius', function(radius)
    local src = source
    local _, _, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local now = GetGameTimer()
        local last = LastSpotlightRadiusAt[vehicleNetId] or 0

        if (now - last) < 100 then
            return
        end
        LastSpotlightRadiusAt[vehicleNetId] = now

        spotlight.radius = ClampNumber(radius, 1.0, 25.0, spotlight.radius or 5.0)
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:spotlightColor')
AddEventHandler('polcam:spotlightColor', function(color)
    local src = source
    local _, _, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local cleanColor = SanitizeColor(color)
        if not cleanColor then return end
        spotlight.color = cleanColor
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:spotlightPosition')
AddEventHandler('polcam:spotlightPosition', function(groundCoords, heliCoords)
    local src = source
    local _, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local posInterval, _, minMove = GetNetSyncConfig()
        local now = GetGameTimer()
        local lastPos = LastSpotlightPositionAt[vehicleNetId] or 0
        if (now - lastPos) < posInterval then
            return
        end

        groundCoords = CoordsWithinVehicleRange(vehicle, groundCoords, MAX_SYNC_DISTANCE)
        heliCoords = CoordsWithinVehicleRange(vehicle, heliCoords, 25.0)
        if not groundCoords or not heliCoords then return end

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

IsAllowedHelicopterEntity = function(vehicle)
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

IsAllowedSeatForPed = function(ped, vehicle)
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
    if type(payload) ~= 'table' or not AllowEvent(src, 'feedHeartbeat', 100) then
        return
    end

    local vehicleNetId = PositiveInteger(payload.heliNetId)
    if not vehicleNetId then
        return
    end

    local operatorSource = PositiveInteger(payload.operatorSource)
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

    local coords = CoordsWithinVehicleRange(vehicle, payload.camCoords, MAX_SYNC_DISTANCE)
    local rotation = CloneRotation(payload.camRot)
    if not coords or not rotation then
        return
    end

    payload.camCoords = coords
    payload.camRot = rotation
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

GetMaxTrackingDistanceForType = function(targetType)
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
    local _, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId or ActiveHeliCameras[vehicleNetId] ~= src then return nil end

    local validatedTargetNetId = ValidateTargetForVehicle(
        vehicle,
        targetNetId,
        targetType,
        GetMaxTrackingDistanceForType(targetType)
    )
    if not validatedTargetNetId then return nil end

    return vehicleNetId, validatedTargetNetId
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

    local vehicleNetId, validatedTargetNetId = ValidateTrackingTargetRequest(src, targetNetId, targetType)
    if not vehicleNetId then
        return
    end

    SetHeliTracking(vehicleNetId, src, validatedTargetNetId, targetType)
end)

RegisterNetEvent('polcam:trackingRequestStop')
AddEventHandler('polcam:trackingRequestStop', function()
    local src = source
    local now = GetGameTimer()
    if not RateLimitTracking(src, 'stop', now) then
        return
    end

    local _, _, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId then
        return
    end

    local tracking = HeliTracking[vehicleNetId]
    if tracking and tracking.ownerSrc and tracking.ownerSrc ~= src then
        return
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

        local validatedVehicleNetId, validatedTargetNetId = ValidateTrackingTargetRequest(src, targetNetId, targetType)
        if not validatedVehicleNetId then
            return
        end

        SetHeliTracking(validatedVehicleNetId, src, validatedTargetNetId, targetType)
    else
        if not RateLimitTracking(src, 'stop', now) then
            return
        end

        if not IsAllowedHelicopterEntity(vehicle) or not IsAllowedSeatForPed(ped, vehicle) then
            return
        end

        local tracking = HeliTracking[vehicleNetId]
        if tracking and tracking.ownerSrc and tracking.ownerSrc ~= src then
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

    local _, _, myVehicleNetId = ResolveAuthorizedVehicle(src, vehicleNetId)
    if not myVehicleNetId then return end
    vehicleNetId = myVehicleNetId

    local state = HeliTracking[vehicleNetId] or { active = false, seq = 0 }
    state.vehicleNetId = vehicleNetId
    TriggerClientEvent('polcam:heliTrackingState', src, vehicleNetId, state)
end)

RegisterNetEvent('polcam:trackingPosition')
AddEventHandler('polcam:trackingPosition', function(targetCoords, heliCoords, targetNetId)
    local src = source
    local _, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId then return end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.owner == src then
        local posInterval, _, _ = GetNetSyncConfig()
        local now = GetGameTimer()
        local lastPos = LastSpotlightPositionAt[vehicleNetId] or 0
        if (now - lastPos) < posInterval then
            return
        end

        local cleanGround = CoordsWithinVehicleRange(vehicle, targetCoords, MAX_SYNC_DISTANCE)
        local cleanHeli = CoordsWithinVehicleRange(vehicle, heliCoords, 25.0)
        local tracking = HeliTracking[vehicleNetId]
        if not tracking or tracking.active ~= true or tracking.ownerSrc ~= src then return end
        local cleanTargetNetId = PositiveInteger(targetNetId)
        if not cleanGround or not cleanHeli or cleanTargetNetId ~= tracking.targetNetId then return end
        if not ValidateTargetForVehicle(vehicle, cleanTargetNetId, tracking.targetType, GetMaxTrackingDistanceForType(tracking.targetType)) then return end

        LastSpotlightPositionAt[vehicleNetId] = now
        spotlight.groundCoords = cleanGround
        spotlight.heliCoords = cleanHeli
        spotlight.targetNetId = cleanTargetNetId
        spotlight.trackingTarget = true
        MaybeBroadcastSpotlight(vehicleNetId)
    end
end)

RegisterNetEvent('polcam:rappelStart')
AddEventHandler('polcam:rappelStart', function(data)
    local src = source
    if type(data) ~= 'table' or not AllowEvent(src, 'rappelStart', 1000) then return end
    if ActiveRappels[src] then return end

    local ped, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src, data.vehicle)
    if not ped or not vehicle or GetVehicleClass(vehicle) ~= 15 then return end

    local allowedRappelSeat = false
    local rappelSeats = Config and Config.Rappel and Config.Rappel.AllowedSeats or { 1, 2 }
    for _, seat in ipairs(rappelSeats) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            allowedRappelSeat = true
            break
        end
    end
    if not allowedRappelSeat then return end

    local altitude = ClampNumber(data.altitude, 0.0, 1000.0, nil)
    local minAltitude = ClampNumber(Config and Config.Rappel and Config.Rappel.MinAltitude, 0.0, 1000.0, 15.0)
    local maxAltitude = ClampNumber(Config and Config.Rappel and Config.Rappel.MaxAltitude, minAltitude, 1000.0, 150.0)
    if not altitude or altitude < minAltitude or altitude > maxAltitude then return end

    local model = GetEntityModel(vehicle)
    if tonumber(data.model) ~= model then return end

    ActiveRappels[src] = {
        startTime = GetGameTimer(),
        vehicleNetId = vehicleNetId,
        altitude = altitude,
        model = model,
        routingBucket = GetPlayerRoutingBucket(src),
    }

    BroadcastToBucket('polcam:syncRappel', ActiveRappels[src].routingBucket, {
        source = src,
        vehicle = vehicleNetId,
        altitude = altitude,
        model = model,
        action = 'start'
    })

    if Config and Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Player %d started rappeling from %.0f ft", src, altitude))
    end
end)

RegisterNetEvent('polcam:rappelEnd')
AddEventHandler('polcam:rappelEnd', function(data)
    local src = source
    if data ~= nil and type(data) ~= 'table' then return end
    if not AllowEvent(src, 'rappelEnd', 500) then return end

    if ActiveRappels[src] then
        local activeRappel = ActiveRappels[src]
        local duration = (GetGameTimer() - (activeRappel.startTime or 0)) / 1000
        ActiveRappels[src] = nil

        BroadcastToBucket('polcam:syncRappel', activeRappel.routingBucket, {
            source = src,
            action = 'end',
            duration = duration
        })

        if Config and Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Player %d finished rappeling (%.1fs)", src, duration))
        end
    end
end)

RegisterNetEvent('polcam:createSyncedMarker')
AddEventHandler('polcam:createSyncedMarker', function(markerData)
    local src = source
    if type(markerData) ~= 'table' or not AllowEvent(src, 'createMarker', 300) then return end
    local _, vehicle, vehicleNetId = ResolveAuthorizedVehicle(src)
    if not vehicleNetId or ActiveHeliCameras[vehicleNetId] ~= src then return end

    local coords = CoordsWithinVehicleRange(vehicle, markerData.coords, MAX_SYNC_DISTANCE)
    if not coords then return end

    SyncedMarkers = SyncedMarkers or {}

    local ownedCount = 0
    for _, marker in pairs(SyncedMarkers) do
        if type(marker) == 'table' and marker.creator == src then ownedCount = ownedCount + 1 end
    end
    if ownedCount >= 25 then return end

    local markerId = ('marker:%d:%d'):format(src, GetGameTimer())

    SyncedMarkers[markerId] = {
        id = markerId,
        coords = coords,
        type = BoundedString(markerData.type, 24, 'waypoint'),
        color = SanitizeColor(markerData.color),
        creator = src,
        vehicleNetId = vehicleNetId,
        createdAt = GetGameTimer(),
        routingBucket = GetPlayerRoutingBucket(src),
    }

    BroadcastToBucket('polcam:receiveSyncedMarker', SyncedMarkers[markerId].routingBucket, SyncedMarkers[markerId])

    if Config and Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Synced marker created by player %d", src))
    end
end)

RegisterNetEvent('polcam:removeSyncedMarker')
AddEventHandler('polcam:removeSyncedMarker', function(markerId)
    local src = source
    markerId = BoundedString(markerId, 64, nil)
    if not markerId or not AllowEvent(src, 'removeMarker', 200) then return end

    SyncedMarkers = SyncedMarkers or {}

    local marker = SyncedMarkers[markerId]
    if marker and marker.creator == src then
        SyncedMarkers[markerId] = nil
        BroadcastToBucket('polcam:syncedMarkerRemoved', marker.routingBucket, markerId)
    end
end)

RegisterNetEvent('polcam:requestSyncedMarkers')
AddEventHandler('polcam:requestSyncedMarkers', function(vehicleNetId)
    local src = source
    local _, _, authorizedNetId = ResolveAuthorizedVehicle(src, vehicleNetId)
    if not authorizedNetId or ActiveHeliCameras[authorizedNetId] ~= src or not AllowEvent(src, 'requestMarkers', 500) then return end
    vehicleNetId = authorizedNetId

    SyncedMarkers = SyncedMarkers or {}

    local vehicleMarkers = {}
    for id, marker in pairs(SyncedMarkers) do
        if type(marker) == 'table' and marker.vehicleNetId == vehicleNetId then
            vehicleMarkers[id] = marker
        end
    end

    TriggerClientEvent('polcam:syncAllMarkers', src, vehicleMarkers)
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
                    BroadcastToBucket('polcam:poiRemoved', poi.routingBucket, id)

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
