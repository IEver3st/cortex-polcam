--[[
    PolCam - Server Script
    Handles POI synchronization and spotlight sync across clients
]]

-- ============================================================================
-- NATIVE CACHING (Performance Optimization)
-- ============================================================================
local GetPlayerPed = GetPlayerPed
local GetVehiclePedIsIn = GetVehiclePedIsIn
local DoesEntityExist = DoesEntityExist
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local GetGameTimer = GetGameTimer
local GetCurrentResourceName = GetCurrentResourceName
local TriggerClientEvent = TriggerClientEvent
local CreateThread = CreateThread
local Wait = Wait
local os_time = os.time
local math_sqrt = math.sqrt
local pairs = pairs

-- ============================================================================
-- POI STORAGE
-- ============================================================================
local ServerPOIs = {}

-- ============================================================================
-- CAMERA LOCK (Per Helicopter)
-- ============================================================================
local ActiveHeliCameras = {} -- vehicleNetId -> ownerSource
local CameraWaitlists = {} -- vehicleNetId -> { [src] = lastRequestMs }

-- ============================================================================
-- SHARED CAMERA STATE (Per Helicopter)
-- ============================================================================
-- Stores the camera state per helicopter so operators can seamlessly hand off.
-- When operator A exits, operator B can continue exactly where A left off.
local SharedCameraState = {} -- vehicleNetId -> {heading, pitch, zoom, targetZoom, visionMode, lockedTargetNetId, lockedTargetType, groundLockPoint, lastUpdate}

-- ============================================================================
-- SPOTLIGHT STORAGE
-- ============================================================================
-- NOTE: This is keyed by the camera "instance" (helicopter net id), not player.
-- That way only one spotlight can exist per helicopter, and when one operator
-- exits the camera another operator can take over the same instance.
local ActiveSpotlights = {} -- vehicleNetId -> {active, radius, owner, heliCoords, groundCoords, targetNetId, trackingTarget}
local HeliTracking = {} -- vehicleNetId -> {active, targetNetId, targetType, ownerSrc, seq}

-- Rate limiting to prevent "Reliable network event overflow"
local LastSpotlightBroadcastAt = {} -- vehicleNetId -> ms
local LastSpotlightPositionAt = {} -- vehicleNetId -> ms
local LastSpotlightRadiusAt = {} -- vehicleNetId -> ms

-- Tracking request rate limiting (per-player, per-event)
local LastTrackingStartAt = {} -- src -> ms
local LastTrackingStopAt = {} -- src -> ms
local LastTrackingStateAt = {} -- src -> ms

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

-- ============================================================================
-- POI CREATION
-- ============================================================================
RegisterNetEvent('polcam:createPOI')
AddEventHandler('polcam:createPOI', function(poi)
    local source = source
    
    -- Validate POI data
    if not poi or not poi.id or not poi.coords then
        return
    end
    
    -- Add server timestamp
    poi.serverTime = os.time()
    poi.creator = source
    
    -- Store POI
    ServerPOIs[poi.id] = poi
    
    -- Broadcast to all clients
    TriggerClientEvent('polcam:receivePOI', -1, poi)
    
    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] POI created by player " .. source .. ": " .. poi.id)
    end
end)

-- ============================================================================
-- POI REMOVAL
-- ============================================================================
RegisterNetEvent('polcam:removePOI')
AddEventHandler('polcam:removePOI', function(poiId)
    local source = source
    
    -- Check if POI exists and if source is the creator
    local poi = ServerPOIs[poiId]
    if poi and poi.creator == source then
        ServerPOIs[poiId] = nil
        
        -- Broadcast removal to all clients
        TriggerClientEvent('polcam:poiRemoved', -1, poiId)
        
        if Config and Config.Debug and Config.Debug.Enabled then
            print("[PolCam] POI removed by player " .. source .. ": " .. poiId)
        end
    end
end)

-- ============================================================================
-- POI SYNC REQUEST
-- ============================================================================
RegisterNetEvent('polcam:requestPOIs')
AddEventHandler('polcam:requestPOIs', function()
    local source = source
    
    -- Send all current POIs to the requesting client
    TriggerClientEvent('polcam:syncAllPOIs', source, ServerPOIs)
    
    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Synced POIs to player " .. source)
    end
end)

-- ============================================================================
-- CAMERA CLAIM/RELEASE (Per Helicopter)
-- ============================================================================
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
    print("[PolCam Server DEBUG] HandoffCamera called - vehicleNetId: " .. tostring(vehicleNetId) .. ", oldOwner: " .. tostring(oldOwner))
    
    -- NOTE: Tracking is now per-helicopter and persists through handoffs.
    -- We do NOT clear tracking here - it transfers to the new owner.

    local nextOwner = PickNextCameraOwner(vehicleNetId, oldOwner)
    if not nextOwner then
        -- No next owner waiting - the old owner may re-enter the camera shortly
        -- Do NOT send forceReleaseAll here - the client already deactivated their camera
        -- and we want them to be able to resume seamlessly
        print("[PolCam Server DEBUG] No next owner in waitlist, skipping forceReleaseAll")
        
        -- Clear spotlight from this helicopter since no one is operating it
        local spotlight = ActiveSpotlights[vehicleNetId]
        if spotlight and spotlight.owner == oldOwner then
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
            TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, nil)
        end
        -- Tracking persists for remaining heli occupants even without camera operator
        return
    end

    -- There IS a next owner waiting - tell old owner to release their local state
    -- so the new owner can take over cleanly
    TriggerClientEvent('polcam:forceReleaseAll', oldOwner)
    print("[PolCam Server DEBUG] Sent polcam:forceReleaseAll to oldOwner: " .. tostring(oldOwner))

    ActiveHeliCameras[vehicleNetId] = nextOwner
    CameraWaitlists[vehicleNetId] = nil

    TriggerClientEvent('polcam:cameraClaimResult', nextOwner, true)
    
    -- Send the shared camera state to the new owner so they can continue seamlessly
    local sharedState = SharedCameraState[vehicleNetId]
    if sharedState then
        TriggerClientEvent('polcam:receiveCameraState', nextOwner, vehicleNetId, sharedState)
        
        if Config and Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Handed off camera state for heli %d from player %d to player %d", vehicleNetId, oldOwner, nextOwner))
        end
    end

    -- Transfer tracking ownership to new owner if tracking is active
    local tracking = HeliTracking[vehicleNetId]
    if tracking and tracking.active then
        tracking.ownerSrc = nextOwner
        -- Broadcast so all occupants know tracking transferred
        BroadcastHeliTracking(vehicleNetId)
        print("[PolCam Server DEBUG] Transferred tracking ownership to new owner: " .. tostring(nextOwner))
    end

    local spotlight = ActiveSpotlights[vehicleNetId]
    if spotlight and spotlight.active then
        spotlight.owner = nextOwner
        TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, spotlight)

        -- Ask new owner to ensure their local spotlight is enabled (without creating a new instance)
        TriggerClientEvent('polcam:spotlightEnsureOn', nextOwner, spotlight.radius)
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

    -- Someone else owns it: remember interest for auto-handoff.
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

AddEventHandler('playerDropped', function()
    local src = source
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
end)

-- ============================================================================
-- SHARED CAMERA STATE SYNC
-- ============================================================================
-- Receive continuous camera state updates from the active operator
RegisterNetEvent('polcam:cameraStateSync')
AddEventHandler('polcam:cameraStateSync', function(vehicleNetId, state)
    local src = source
    if not vehicleNetId then return end
    
    -- Only accept updates from the current camera owner
    if ActiveHeliCameras[vehicleNetId] ~= src then return end
    
    -- Store/update shared state
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

-- Client requests current shared state when taking over camera
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
        -- No existing state, send nil so client uses defaults
        TriggerClientEvent('polcam:receiveCameraState', src, vehicleNetId, nil)
    end
end)

-- Clear shared state when helicopter is abandoned (no occupants) or after timeout
local function CleanupStaleStates()
    local now = GetGameTimer()
    local staleThreshold = 300000 -- 5 minutes of no updates
    
    for vehicleNetId, state in pairs(SharedCameraState) do
        if state.lastUpdate and (now - state.lastUpdate) > staleThreshold then
            -- No one has used this camera in 5 minutes, clear it
            SharedCameraState[vehicleNetId] = nil
            if Config and Config.Debug and Config.Debug.Enabled then
                print(string.format("[PolCam] Cleared stale camera state for heli %d", vehicleNetId))
            end
        end
    end
end

-- ============================================================================
-- SPOTLIGHT SYNC
-- ============================================================================
RegisterNetEvent('polcam:spotlightSync')
AddEventHandler('polcam:spotlightSync', function(active, radius, initialGroundCoords, initialHeliCoords)
    local src = source
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then return end

    if active then
        -- Enforce single spotlight per helicopter; supersede any previous owner.
        -- Use provided initial coords, or fall back to existing coords if available
        local existingSpotlight = ActiveSpotlights[vehicleNetId]
        
        -- If there was a previous owner and it's not us, tell them to release spotlight
        -- NOTE: Tracking is NOT cleared here - it's per-heli and persists
        if existingSpotlight and existingSpotlight.owner and existingSpotlight.owner ~= src then
            local oldOwner = existingSpotlight.owner
            TriggerClientEvent('polcam:forceReleaseAll', oldOwner)
        end
        
        -- Preserve tracking info from existing spotlight or from HeliTracking
        local tracking = HeliTracking[vehicleNetId]
        local targetNetId = (existingSpotlight and existingSpotlight.targetNetId) or (tracking and tracking.targetNetId) or nil
        local trackingTarget = (existingSpotlight and existingSpotlight.trackingTarget) or (tracking and tracking.active) or false
        
        ActiveSpotlights[vehicleNetId] = {
            active = true,
            radius = radius or 5.0,
            owner = src,
            vehicleNetId = vehicleNetId,
            heliCoords = initialHeliCoords or (existingSpotlight and existingSpotlight.heliCoords) or nil,
            groundCoords = initialGroundCoords or (existingSpotlight and existingSpotlight.groundCoords) or nil,
            targetNetId = targetNetId,
            trackingTarget = trackingTarget
        }
        -- Reset rate limit so first position update goes through immediately
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

    -- This is a state change, so broadcast immediately.
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

-- Handle spotlight position/ground coord updates
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

-- ============================================================================
-- TARGET TRACKING SYNC (Per Helicopter - Unified)
-- ============================================================================
-- Tracking is now per-helicopter, not per-player. Anyone in the heli can start/stop.
-- Last one wins for new targets. Tracking persists through camera handoffs.

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

-- Broadcast tracking state to ALL players in the same helicopter
local function BroadcastHeliTracking(vehicleNetId)
    if not vehicleNetId then 
        print("[PolCam Server DEBUG] BroadcastHeliTracking: vehicleNetId is nil, aborting")
        return 
    end
    
    local state = HeliTracking[vehicleNetId] or { active = false, seq = 0 }
    state.vehicleNetId = vehicleNetId
    
    print("[PolCam Server DEBUG] BroadcastHeliTracking - vehicleNetId: " .. tostring(vehicleNetId))
    print("[PolCam Server DEBUG] State to broadcast - active: " .. tostring(state.active) .. ", seq: " .. tostring(state.seq))
    
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
                    print("[PolCam Server DEBUG] Checking player " .. tostring(playerSrc) .. " - playerVehNetId: " .. tostring(playerVehNetId))
                    if playerVehNetId == vehicleNetId then
                        -- This player is in the same helicopter, send them the tracking state
                        TriggerClientEvent('polcam:heliTrackingState', playerSrc, vehicleNetId, state)
                        sentCount = sentCount + 1
                        print("[PolCam Server DEBUG] Sent heliTrackingState to player " .. tostring(playerSrc))
                    end
                end
            end
        end
    end
    
    print("[PolCam Server DEBUG] BroadcastHeliTracking complete - sent to " .. tostring(sentCount) .. " players")
end

local function ClearHeliTracking(vehicleNetId)
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

    if ActiveSpotlights[vehicleNetId] then
        ActiveSpotlights[vehicleNetId].targetNetId = nil
        ActiveSpotlights[vehicleNetId].trackingTarget = false
    end

    BroadcastHeliTracking(vehicleNetId)
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

-- Client requests tracking start (server authoritative). Last request wins.
RegisterNetEvent('polcam:trackingRequestStart')
AddEventHandler('polcam:trackingRequestStart', function(targetNetId, targetType)
    local src = source
    local now = GetGameTimer()
    if not RateLimitTracking(src, 'start', now) then
        return
    end

    if type(targetNetId) ~= 'number' or targetNetId <= 0 then
        return
    end

    if targetType ~= 'vehicle' and targetType ~= 'ped' then
        return
    end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 then
        return
    end

    if not IsAllowedHelicopterEntity(vehicle) then
        return
    end

    if not IsAllowedSeatForPed(ped, vehicle) then
        return
    end

    local vehicleNetId = DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if not vehicleNetId then
        return
    end

    local targetEntity = NetworkGetEntityFromNetworkId(targetNetId)
    if not targetEntity or targetEntity == 0 or not DoesEntityExist(targetEntity) then
        return
    end

    if targetType == 'vehicle' and not IsEntityAVehicle(targetEntity) then
        return
    end

    if targetType == 'ped' and not IsEntityAPed(targetEntity) then
        return
    end

    local heliCoords = GetEntityCoords(vehicle)
    local targetCoords = GetEntityCoords(targetEntity)
    local dx = heliCoords.x - targetCoords.x
    local dy = heliCoords.y - targetCoords.y
    local dz = heliCoords.z - targetCoords.z
    local maxDist = GetMaxTrackingDistanceForType(targetType)
    if (dx * dx + dy * dy + dz * dz) > (maxDist * maxDist) then
        return
    end

    SetHeliTracking(vehicleNetId, src, targetNetId, targetType)
end)

-- Client requests tracking stop (server authoritative).
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
        -- Last-one-wins: allow stop from any occupant, but ensure they are actually in the heli.
        -- (vehicleNetId check above already guarantees same heli).
    end

    ClearHeliTracking(vehicleNetId)
end)

-- Handle direct tracking sync from client (used by CompleteLock/ClearLock)
RegisterNetEvent('polcam:trackingSync')
AddEventHandler('polcam:trackingSync', function(active, targetNetId, targetType)
    local src = source
    
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
        -- Setting or updating tracking
        if type(targetNetId) ~= 'number' or targetNetId <= 0 then
            return
        end
        SetHeliTracking(vehicleNetId, src, targetNetId, targetType)
    else
        -- Clearing tracking
        ClearHeliTracking(vehicleNetId)
    end
end)

-- Client can request current tracking state for a heli.
RegisterNetEvent('polcam:trackingRequestState')
AddEventHandler('polcam:trackingRequestState', function(vehicleNetId)
    local src = source
    local now = GetGameTimer()
    if not RateLimitTracking(src, 'state', now) then
        return
    end

    if type(vehicleNetId) ~= 'number' then return end

    -- Only allow requesting state for the heli the player is currently in.
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

-- Handle tracking position updates (for persistent tracking)
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

-- ============================================================================
-- RAPPEL SYNC
-- ============================================================================
local ActiveRappels = {} -- playerId -> {startTime, vehicleNetId, altitude, model}


-- Handle rappel start
RegisterNetEvent('polcam:rappelStart')
AddEventHandler('polcam:rappelStart', function(data)
    local source = source
    
    ActiveRappels[source] = {
        startTime = GetGameTimer(),
        vehicleNetId = data.vehicle,
        altitude = data.altitude,
        model = data.model
    }
    
    -- Broadcast to all clients for visual sync
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


-- Handle rappel end
RegisterNetEvent('polcam:rappelEnd')
AddEventHandler('polcam:rappelEnd', function(data)
    local source = source
    
    if ActiveRappels[source] then
        local duration = (GetGameTimer() - (ActiveRappels[source].startTime or 0)) / 1000
        ActiveRappels[source] = nil
        
        -- Broadcast completion to all clients
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

-- ============================================================================
-- SYNCED MARKERS (Shared between helicopter crew)
-- ============================================================================
local SyncedMarkers = {} -- markerId -> {coords, type, creator, vehicleNetId, visibleTo}

-- Create a synced marker visible to players in the same helicopter
RegisterNetEvent('polcam:createSyncedMarker')
AddEventHandler('polcam:createSyncedMarker', function(markerData)
    local source = source
    local ped = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle == 0 then return end
    if not DoesEntityExist(vehicle) then return end

    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleNetId then return end

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
    
    -- Broadcast to all clients - they will filter based on vehicle
    TriggerClientEvent('polcam:receiveSyncedMarker', -1, SyncedMarkers[markerId])
    
    if Config and Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Synced marker created by player %d", source))
    end
end)

-- Remove a synced marker
RegisterNetEvent('polcam:removeSyncedMarker')
AddEventHandler('polcam:removeSyncedMarker', function(markerId)
    local source = source
    
    local marker = SyncedMarkers[markerId]
    if marker and marker.creator == source then
        SyncedMarkers[markerId] = nil
        TriggerClientEvent('polcam:syncedMarkerRemoved', -1, markerId)
    end
end)

-- Request all synced markers for a vehicle
RegisterNetEvent('polcam:requestSyncedMarkers')
AddEventHandler('polcam:requestSyncedMarkers', function(vehicleNetId)
    local source = source
    
    local vehicleMarkers = {}
    for id, marker in pairs(SyncedMarkers) do
        if marker.vehicleNetId == vehicleNetId then
            vehicleMarkers[id] = marker
        end
    end
    
    TriggerClientEvent('polcam:syncAllMarkers', source, vehicleMarkers)
end)

-- ============================================================================
-- POI CLEANUP (Expired POIs) & CAMERA STATE CLEANUP
-- ============================================================================
CreateThread(function()
    while true do
        Wait(60000) -- Check every minute
        
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
        
        -- Clean up stale camera states
        CleanupStaleStates()
    end
end)

-- ============================================================================
-- TRACKING CLEANUP (Hard clear when heli empty)
-- ============================================================================
CreateThread(function()
    while true do
        Wait(1000)

        for vehicleNetId, tracking in pairs(HeliTracking) do
            if tracking and tracking.active then
                if not IsVehicleOccupiedByAnyPlayer(vehicleNetId) then
                    ClearHeliTracking(vehicleNetId)
                    HeliTracking[vehicleNetId] = nil
                end
            end
        end
    end
end)

-- ============================================================================
-- PLAYER DISCONNECT CLEANUP
-- ============================================================================
AddEventHandler('playerDropped', function(reason)

    local src = source
    LastTrackingStartAt[src] = nil
    LastTrackingStopAt[src] = nil
    LastTrackingStateAt[src] = nil


    -- Remove any spotlight instance owned by this player
    for vehicleNetId, spotlight in pairs(ActiveSpotlights) do
        if spotlight and spotlight.owner == src then
            ActiveSpotlights[vehicleNetId] = nil
            LastSpotlightBroadcastAt[vehicleNetId] = nil
            LastSpotlightPositionAt[vehicleNetId] = nil
            LastSpotlightRadiusAt[vehicleNetId] = nil
            TriggerClientEvent('polcam:spotlightUpdate', -1, vehicleNetId, nil)
        end
    end

    -- Handle per-heli tracking cleanup
    -- Only clear tracking if heli becomes empty (no other occupants)
    for vehicleNetId, tracking in pairs(HeliTracking) do
        if tracking and tracking.ownerSrc == src then
            -- Check if anyone else is still in this heli
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
                -- Transfer tracking to another occupant (pick any)
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
                                    print("[PolCam Server DEBUG] Transferred tracking ownership from disconnected player to: " .. tostring(playerSrc))
                                    break
                                end
                            end
                        end
                    end
                end
            else
                -- Heli is empty, clear tracking
                ClearHeliTracking(vehicleNetId)
                HeliTracking[vehicleNetId] = nil
                print("[PolCam Server DEBUG] Cleared HeliTracking for empty heli: " .. tostring(vehicleNetId))
            end
        end
    end

    -- Remove rappel state when player disconnects
    if ActiveRappels[src] then
        ActiveRappels[src] = nil
    end

    -- Remove synced markers created by this player
    for id, marker in pairs(SyncedMarkers) do
        if marker.creator == src then
            SyncedMarkers[id] = nil
            TriggerClientEvent('polcam:syncedMarkerRemoved', -1, id)
        end
    end
    
    -- Note: We DO NOT clear SharedCameraState here - it should persist
    -- so that another passenger can take over the camera with the same state
end)

-- ============================================================================
-- RESOURCE START
-- ============================================================================
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    print("[PolCam] Server-side initialized")
    print("[PolCam] POI and spotlight synchronization active")
end)
