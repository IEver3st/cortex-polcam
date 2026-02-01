--[[
    PolCam Targeting System
    Line-of-sight based vehicle/ped tracking with persistent tracking support
]]

-- Native Caching
local DoesEntityExist = DoesEntityExist
local GetEntityCoords = GetEntityCoords
local GetEntityModel = GetEntityModel
local GetEntityHeading = GetEntityHeading
local GetEntitySpeed = GetEntitySpeed
local GetEntityForwardVector = GetEntityForwardVector
local IsEntityAPed = IsEntityAPed
local IsEntityAVehicle = IsEntityAVehicle
local IsPedInAnyVehicle = IsPedInAnyVehicle
local IsPedAPlayer = IsPedAPlayer
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetPedInVehicleSeat = GetPedInVehicleSeat
local NetworkGetPlayerIndexFromPed = NetworkGetPlayerIndexFromPed
local GetPlayerName = GetPlayerName
local GetVehicleNumberPlateText = GetVehicleNumberPlateText
local GetDisplayNameFromVehicleModel = GetDisplayNameFromVehicleModel
local GetMakeNameFromVehicleModel = GetMakeNameFromVehicleModel
local GetLabelText = GetLabelText
local GetVehicleClass = GetVehicleClass
local GetModelDimensions = GetModelDimensions
local GetCamMatrix = GetCamMatrix
local DoesCamExist = DoesCamExist
local GetEntityAttachedTo = GetEntityAttachedTo
local StartShapeTestRay = StartShapeTestRay
local StartShapeTestCapsule = StartShapeTestCapsule
local GetShapeTestResult = GetShapeTestResult
local GetGameTimer = GetGameTimer
local GetGamePool = GetGamePool
local PlayerPedId = PlayerPedId
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local GetPlayerServerId = GetPlayerServerId
local PlayerId = PlayerId
local SendNUIMessage = SendNUIMessage
local DrawLine = DrawLine
local GetResourceState = GetResourceState
local DrawMarker = DrawMarker
local SetTextFont = SetTextFont
local SetTextProportional = SetTextProportional
local SetTextScale = SetTextScale
local SetTextColour = SetTextColour
local SetTextDropshadow = SetTextDropshadow
local SetTextEdge = SetTextEdge
local SetTextDropShadow = SetTextDropShadow
local SetTextOutline = SetTextOutline
local SetTextEntry = SetTextEntry
local AddTextComponentString = AddTextComponentString
local DrawText = DrawText
local BeginTextCommandDisplayText = BeginTextCommandDisplayText
local AddTextComponentSubstringPlayerName = AddTextComponentSubstringPlayerName
local SetDrawOrigin = SetDrawOrigin
local ClearDrawOrigin = ClearDrawOrigin
local CreateThread = CreateThread
local Wait = Wait

-- Safe wrapper to get network ID from entity
-- Returns nil if entity doesn't exist or isn't networked (prevents warning spam)
local function SafeGetNetworkId(entity)
    if not entity or entity == 0 then
        return nil
    end
    if not DoesEntityExist(entity) then
        return nil
    end
    if not NetworkGetEntityIsNetworked(entity) then
        return nil
    end
    return NetworkGetNetworkIdFromEntity(entity)
end

local function isEsLibStarted()
    return GetResourceState('es_lib') == 'started'
end

local function canUseEsLibDebugPanel()
    return isEsLibStarted()
        and type(exports) == 'table'
        and exports.es_lib
        and type(exports.es_lib.showDebugPanel) == 'function'
        and type(exports.es_lib.updateDebugPanel) == 'function'
        and type(exports.es_lib.hideDebugPanel) == 'function'
end

-- Math Caching
local math_sqrt = math.sqrt
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_floor = math.floor
local math_cos = math.cos
local math_rad = math.rad
local math_deg = math.deg
local math_acos = math.acos
local math_exp = math.exp
local math_huge = math.huge
local string_format = string.format
local table_concat = table.concat
local ipairs = ipairs
local pairs = pairs
local tostring = tostring

local function math_clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

-- Tracking State
local Tracking = {
    lastScanTime = 0,
    scanIntervalMs = 75,
    lockStartTime = 0,
    cameraActivatedTime = 0,
    candidateEntity = nil,
    candidateType = nil,
    labelSmoothedDistance = nil,
    labelLastUpdateTime = 0,
    labelTargetEntity = nil,
    occludedSince = nil,
    lastOcclusionCheck = 0,
    debug = {
        camPos = nil,
        camDir = nil,
        endPos = nil,
        probeHitPos = nil,
        probeHit = false,
        distanceToLookPoint = 0,
        calculatedRadius = 0,
        scanRange = 0,
        capsuleFlags = 0,
        scanSource = "none",
        entityHitPos = nil,
        entityHit = false,
        hitEntityType = "none",
        hitEntity = nil,
        candidateNetId = nil,
        candidateType = nil,
        heliPos = nil,
        shared = nil,
        detectionScore = nil,
        zoom = 0,
        fov = 0,
        occluded = false,
        occlusionAgeMs = 0,
        occlusionHitType = "none",
        occlusionHitModel = nil,
        occlusionHitPos = nil,
        occlusionHitEntity = nil
    }
}

-- Persistent Tracking State
local PersistentTracking = {
    Active = false,
    LoopRunning = false,
    RenderLoopRunning = false,
    MaxDistance = 500.0,
    UpdateIntervalMs = 100,
    LastSyncTime = 0,
    SyncIntervalMs = 200
}

-- Unified Heli Tracking State
local HeliTrackingState = {
    active = false,
    targetNetId = nil,
    targetType = nil,
    ownerSrc = nil,
    vehicleNetId = nil,
    seq = 0,
    lastUpdateTime = 0
}

local lastLockedTargetNetId = nil
local lastCandidateNetId = nil
local lastCandidateEntity = nil
local lastCandidateType = nil
local lastCandidateTime = 0

local SyncedTracking = HeliTrackingState

-- Optimization Caches
local ModelNameCache = {}
local MakeNameCache = {}
local LastUpdateLockedTime = 0
local UPDATE_LOCKED_INTERVAL = 100
local LastPoolScanTime = 0
local POOL_SCAN_INTERVAL = 200
local cachedPlateThreshold = nil
local lastScanSignature = nil
local lastScanLogTime = 0
local lastSharedLogSeq = nil
local lastSharedLogTarget = nil
local lastSharedLogActive = nil
local lastSharedLogOwner = nil

local function shouldLogEvents()
    return Config and Config.Debug and Config.Debug.LogEvents
end

local function shouldLogScans()
    return Config and Config.Debug and Config.Debug.LogScans
end

-- Utility Functions
local function GetHelicopterPosition()
    if not PolCam.CurrentVehicle or not DoesEntityExist(PolCam.CurrentVehicle) then
        return nil
    end
    return GetEntityCoords(PolCam.CurrentVehicle)
end

local function GetCameraPosition()
    if not PolCam.Camera or not DoesCamExist(PolCam.Camera) then
        return nil
    end
    return PolCam.CameraCoords
end

local function GetCameraDirection()
    if not PolCam.Camera or not DoesCamExist(PolCam.Camera) then
        return nil
    end
    local _, forwardVector, _, _ = GetCamMatrix(PolCam.Camera)
    return forwardVector
end

local function Normalize(v)
    local len = math_sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len == 0 then return vector3(0, 0, 0) end
    local invLen = 1 / len
    return vector3(v.x * invLen, v.y * invLen, v.z * invLen)
end

local GetEntityTargetPoint

local function GetMaxAcquireDistance(entityType)
    local tracking = Config.Tracking
    local camera = Config.Camera
    local defaultDist = (camera and camera.RenderDistance) or 1000.0
    
    if not tracking then return defaultDist end
    
    if entityType == "vehicle" then
        return tracking.TargetingMaxDistanceVehicles or defaultDist
    elseif entityType == "ped" then
        return tracking.TargetingMaxDistancePeds or defaultDist
    end
    return defaultDist
end

local function IsWithinAcquireDistance(entity, entityType, camPos)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local maxDist = GetMaxAcquireDistance(entityType)
    local coords = GetEntityCoords(entity)
    local dx = camPos.x - coords.x
    local dy = camPos.y - coords.y
    local dz = camPos.z - coords.z
    return (dx*dx + dy*dy + dz*dz) <= (maxDist * maxDist)
end

local function FindBestEntityOnRay(camPos, camDir, radius, scanRange)
    local tracking = Config.Tracking
    if not (tracking and tracking.UsePoolFallbackTargeting) then return nil, nil end
    if type(GetGamePool) ~= "function" then return nil, nil end

    local now = GetGameTimer()
    if now - LastPoolScanTime < POOL_SCAN_INTERVAL then return nil, nil end
    LastPoolScanTime = now

    local dir = Normalize(camDir)
    local dirX, dirY, dirZ = dir.x, dir.y, dir.z
    local bestEntity, bestType
    local bestPerp = math_huge
    local bestAlong = math_huge
    local radiusSq = radius * radius
    
    local playerPed = PlayerPedId()
    local currentVehicle = PolCam.CurrentVehicle

    local function consider(entity, entityType)
        if not entity or entity == 0 or not DoesEntityExist(entity) then return end
        if entity == playerPed then return end
        if currentVehicle and entity == currentVehicle then return end
        if not IsWithinAcquireDistance(entity, entityType, camPos) then return end

        local targetPoint = GetEntityTargetPoint(entity) or GetEntityCoords(entity)
        local toEntX = targetPoint.x - camPos.x
        local toEntY = targetPoint.y - camPos.y
        local toEntZ = targetPoint.z - camPos.z
        local along = (toEntX * dirX) + (toEntY * dirY) + (toEntZ * dirZ)
        
        if along <= 0.0 or along > scanRange then return end

        local closestX = camPos.x + dirX * along
        local closestY = camPos.y + dirY * along
        local closestZ = camPos.z + dirZ * along
        local perpX = targetPoint.x - closestX
        local perpY = targetPoint.y - closestY
        local perpZ = targetPoint.z - closestZ
        local perpSq = perpX*perpX + perpY*perpY + perpZ*perpZ
        
        if perpSq > radiusSq then return end
        
        local perp = math_sqrt(perpSq)

        if perp < bestPerp or (math_abs(perp - bestPerp) < 0.05 and along < bestAlong) then
            bestPerp = perp
            bestAlong = along
            bestEntity = entity
            bestType = entityType
        end
    end

    if tracking.TrackVehicles then
        local vehicles = GetGamePool('CVehicle')
        for i = 1, #vehicles do
            consider(vehicles[i], "vehicle")
        end
    end

    if tracking.TrackPeds then
        local peds = GetGamePool('CPed')
        for i = 1, #peds do
            consider(peds[i], "ped")
        end
    end

    return bestEntity, bestType
end

GetEntityTargetPoint = function(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end
    
    local coords = GetEntityCoords(entity)
    
    if IsEntityAPed(entity) then
        return coords + vector3(0.0, 0.0, 0.7)
    end
    
    if IsEntityAVehicle(entity) then
        local minDim, maxDim = GetModelDimensions(GetEntityModel(entity))
        local z = coords.z + ((maxDim.z - minDim.z) * 0.75)
        return vector3(coords.x, coords.y, z)
    end
    
    return coords
end

-- Debug Visualization
local function DrawDebugLine(startPos, endPos, r, g, b, a)
    DrawLine(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, r, g, b, a)
end

local function DrawDebugSphere(pos, radius, r, g, b, a)
    DrawMarker(28, pos.x, pos.y, pos.z, 
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
        radius * 2, radius * 2, radius * 2, 
        r, g, b, a, 
        false, false, 2, nil, nil, false)
end

local function DrawDebugBox(entity, r, g, b, a)
    if not entity or not DoesEntityExist(entity) then return end
    
    local pos = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    local minDim, maxDim = GetModelDimensions(model)
    
    local sizeX = maxDim.x - minDim.x
    local sizeY = maxDim.y - minDim.y
    local sizeZ = maxDim.z - minDim.z
    
    local heading = GetEntityHeading(entity)
    DrawMarker(1, pos.x, pos.y, pos.z + sizeZ/2, 
        0.0, 0.0, 0.0, 0.0, 0.0, heading, 
        sizeX + 0.5, sizeY + 0.5, sizeZ + 0.5, 
        r, g, b, a, 
        false, false, 2, nil, nil, false)
end

local function DrawDebugText(text, x, y, scale, r, g, b, a)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function RenderDebugPanel()
    -- Native DrawText debug panel replaced by es_lib debug panel.
    -- Kept as a no-op to avoid changing other call sites.
    return
end

local function RenderDebugVisuals()
    if not Config.Debug or not Config.Debug.Enabled then return end
    if not PolCam.Active then return end
    
    local dbg = Tracking.debug
    
    if Config.Debug.ShowRaycast and dbg.camPos and dbg.endPos then
        local col = Config.Debug.RaycastColor or {0, 255, 255, 200}
        DrawDebugLine(dbg.camPos, dbg.endPos, col[1], col[2], col[3], col[4])
    end
    
    if Config.Debug.ShowDetectionRadius and dbg.probeHitPos and dbg.calculatedRadius then
        local col = Config.Debug.DetectionColor or {255, 255, 0, 100}
        DrawDebugSphere(dbg.probeHitPos, dbg.calculatedRadius, col[1], col[2], col[3], col[4])
    end
    
    if Config.Debug.ShowHitPoint and dbg.entityHitPos then
        local col = Config.Debug.HitPointColor or {0, 255, 0, 255}
        DrawDebugSphere(dbg.entityHitPos, 0.5, col[1], col[2], col[3], col[4])
    end
    
    if Config.Debug.ShowTargetBox and Tracking.candidateEntity and DoesEntityExist(Tracking.candidateEntity) then
        local col = Config.Debug.TargetBoxColor or {255, 128, 0, 200}
        DrawDebugBox(Tracking.candidateEntity, col[1], col[2], col[3], col[4])
    end
end

local DEBUG_PANEL_INTERVAL_MS = 200
local lastDebugPanelUpdate = 0
local debugPanelShown = false

local function formatVec3(v)
    if not v then return nil end
    return string_format('%.1f %.1f %.1f', v.x, v.y, v.z)
end

local function buildDebugPanelLines()
    local dbg = Tracking.debug
    local cfg = Config.Debug or {}
    local now = GetGameTimer()

    local lines = {
        { label = 'Active', value = PolCam and PolCam.Active or false },
        { label = 'Locked', value = PolCam and PolCam.LockedTarget and true or false },
        { label = 'Locking', value = LockingInProgress or false },
        { label = 'Persistent', value = PersistentTracking.Active or false },
        { label = 'Candidate', value = Tracking.candidateType or 'none' },
    }

    if cfg.ShowDistanceInfo then
        lines[#lines + 1] = { label = 'LookDist (m)', value = string_format('%.1f', dbg.distanceToLookPoint or 0) }
        lines[#lines + 1] = { label = 'ScanRange (m)', value = string_format('%.1f', dbg.scanRange or 0) }
    end

    if cfg.ShowRadiusInfo then
        lines[#lines + 1] = { label = 'Radius (m)', value = string_format('%.1f', dbg.calculatedRadius or 0) }
        lines[#lines + 1] = { label = 'CapsuleFlags', value = tostring(dbg.capsuleFlags or 0) }
    end

    if cfg.ShowScanDetails then
        lines[#lines + 1] = { label = 'ProbeHit', value = dbg.probeHit or false }
        lines[#lines + 1] = { label = 'ScanSource', value = dbg.scanSource or 'none' }
        lines[#lines + 1] = { label = 'Occluded', value = dbg.occluded or false }
        lines[#lines + 1] = { label = 'OccAgeMs', value = tostring(dbg.occlusionAgeMs or 0) }
        lines[#lines + 1] = { label = 'OccHit', value = dbg.occlusionHitType or 'none' }
        if dbg.occlusionHitModel then
            lines[#lines + 1] = { label = 'OccModel', value = tostring(dbg.occlusionHitModel) }
        end
        lines[#lines + 1] = { label = 'DetScore', value = string_format('%.3f', dbg.detectionScore or 0) }
        lines[#lines + 1] = { label = 'Zoom', value = string_format('%.2f', dbg.zoom or 0) }
        lines[#lines + 1] = { label = 'FOV', value = string_format('%.2f', dbg.fov or 0) }
        local camText = formatVec3(dbg.camPos)
        if camText then
            lines[#lines + 1] = { label = 'Cam', value = camText }
        end
        local heliText = formatVec3(dbg.heliPos)
        if heliText then
            lines[#lines + 1] = { label = 'Heli', value = heliText }
        end
        local probeText = formatVec3(dbg.probeHitPos)
        if probeText then
            lines[#lines + 1] = { label = 'Probe', value = probeText }
        end
        local hitText = formatVec3(dbg.entityHitPos)
        if hitText then
            lines[#lines + 1] = { label = 'Hit', value = hitText }
        end
    end

    if cfg.ShowEntityInfo then
        local lockedNet = lastLockedTargetNetId
        if not lockedNet and PolCam and PolCam.LockedTarget then
            lockedNet = SafeGetNetworkId(PolCam.LockedTarget)
        end
        lines[#lines + 1] = { label = 'HitType', value = dbg.hitEntityType or 'none' }
        lines[#lines + 1] = { label = 'CandidateNet', value = tostring(dbg.candidateNetId) }
        lines[#lines + 1] = { label = 'LockedNet', value = tostring(lockedNet) }
    end

    if cfg.ShowSharedState then
        local sharedAge = HeliTrackingState.lastUpdateTime and HeliTrackingState.lastUpdateTime > 0 and (now - HeliTrackingState.lastUpdateTime) or -1
        lines[#lines + 1] = { label = 'SharedActive', value = HeliTrackingState.active or false }
        lines[#lines + 1] = { label = 'SharedNet', value = tostring(HeliTrackingState.targetNetId) }
        lines[#lines + 1] = { label = 'SharedType', value = tostring(HeliTrackingState.targetType) }
        lines[#lines + 1] = { label = 'SharedOwner', value = tostring(HeliTrackingState.ownerSrc) }
        lines[#lines + 1] = { label = 'SharedSeq', value = tostring(HeliTrackingState.seq) }
        lines[#lines + 1] = { label = 'SharedAgeMs', value = string_format('%.0f', sharedAge) }

        local debugState = PolCam and PolCam.DebugState or nil
        if debugState then
            local syncAge = debugState.lastCameraStateSync > 0 and (now - debugState.lastCameraStateSync) or -1
            local recvAge = debugState.lastCameraStateReceive > 0 and (now - debugState.lastCameraStateReceive) or -1
            lines[#lines + 1] = { label = 'CamSyncAge', value = string_format('%.0f', syncAge) }
            lines[#lines + 1] = { label = 'CamRecvAge', value = string_format('%.0f', recvAge) }
            lines[#lines + 1] = { label = 'CamSyncVeh', value = tostring(debugState.lastCameraStateVehicle) }
            lines[#lines + 1] = { label = 'CamRecvVeh', value = tostring(debugState.lastSharedStateVehicle) }
        end
    end

    return lines
end

local function buildDebugPanelData()
    if not Config.Debug or not (Config.Debug.LogScans or Config.Debug.LogEvents) then
        return nil
    end

    local debugState = PolCam and PolCam.DebugState or nil
    local shared = {
        active = HeliTrackingState.active,
        targetNetId = HeliTrackingState.targetNetId,
        targetType = HeliTrackingState.targetType,
        ownerSrc = HeliTrackingState.ownerSrc,
        vehicleNetId = HeliTrackingState.vehicleNetId,
        seq = HeliTrackingState.seq,
        lastUpdateTime = HeliTrackingState.lastUpdateTime
    }

    local camera = nil
    if debugState then
        camera = {
            lastSync = debugState.lastCameraStateSync,
            lastReceive = debugState.lastCameraStateReceive,
            lastSyncVehicle = debugState.lastCameraStateVehicle,
            lastReceiveVehicle = debugState.lastSharedStateVehicle,
            lastSyncPayload = debugState.lastCameraStatePayload,
            lastReceivePayload = debugState.lastSharedStatePayload,
            syncCount = debugState.lastCameraStateSyncCount,
            receiveCount = debugState.lastCameraStateReceiveCount
        }
    end

    local scan = {
        scanRange = Tracking.debug.scanRange,
        distanceToLookPoint = Tracking.debug.distanceToLookPoint,
        radius = Tracking.debug.calculatedRadius,
        capsuleFlags = Tracking.debug.capsuleFlags,
        scanSource = Tracking.debug.scanSource,
        probeHit = Tracking.debug.probeHit,
        hitEntity = Tracking.debug.hitEntity,
        hitEntityType = Tracking.debug.hitEntityType,
        occluded = Tracking.debug.occluded,
        occlusionAgeMs = Tracking.debug.occlusionAgeMs,
        occlusionHitType = Tracking.debug.occlusionHitType,
        occlusionHitModel = Tracking.debug.occlusionHitModel,
        candidateNetId = Tracking.debug.candidateNetId,
        detectionScore = Tracking.debug.detectionScore,
        candidateType = Tracking.candidateType,
        zoom = Tracking.debug.zoom,
        fov = Tracking.debug.fov
    }

    Tracking.debug.shared = shared

    return {
        scan = scan,
        shared = shared,
        camera = camera
    }
end

local function forceDisableAllDebug()
    if not Config then return end
    Config.Debug = Config.Debug or {}
    Config.Debug.Enabled = false
    Config.Debug.ShowDebugPanel = false
    Config.Debug.LogEvents = false
    Config.Debug.LogScans = false
end

local function updateEsLibDebugPanel(force)
    if not Config.Debug or not Config.Debug.Enabled or not Config.Debug.ShowDebugPanel then
        if debugPanelShown and canUseEsLibDebugPanel() then
            exports.es_lib:hideDebugPanel()
        end
        debugPanelShown = false
        return
    end

    -- Requirement: no es_lib installed/running -> disable all PolCam debug features
    if GetResourceState('es_lib') ~= 'started' then
        forceDisableAllDebug()
        return
    end

    if not PolCam.Active then
        if debugPanelShown and canUseEsLibDebugPanel() then
            exports.es_lib:hideDebugPanel()
        end
        debugPanelShown = false
        return
    end

    if not canUseEsLibDebugPanel() then
        return
    end

    local now = GetGameTimer()
    if not force and now - lastDebugPanelUpdate < DEBUG_PANEL_INTERVAL_MS then
        return
    end

    lastDebugPanelUpdate = now

    local payload = {
        title = 'POLCAM DEBUG',
        subtitle = 'Targeting',
        position = 'top-right',
        accentColor = '#7cc7ff',
        lines = buildDebugPanelLines(),
        data = buildDebugPanelData()
    }

    if not debugPanelShown then
        exports.es_lib:showDebugPanel(payload)
        debugPanelShown = true
    else
        exports.es_lib:updateDebugPanel(payload)
    end
end

function RenderTargetingDebug()
    RenderDebugVisuals()
    updateEsLibDebugPanel(false)
end

local function IsHeliEntity(entity)
    if not entity or entity == 0 then return false end
    if not PolCam.CurrentVehicle then return false end
    if entity == PolCam.CurrentVehicle then return true end
    if GetEntityAttachedTo then
        local attachedTo = GetEntityAttachedTo(entity)
        if attachedTo and attachedTo ~= 0 and attachedTo == PolCam.CurrentVehicle then
            return true
        end
    end
    return false
end

local function GetCandidateFromHit(hitEntity, trackVehicles, trackPeds)
    if not hitEntity or hitEntity == 0 or not DoesEntityExist(hitEntity) then return nil end
    if hitEntity == PlayerPedId() then return nil end
    if IsHeliEntity(hitEntity) then return nil end
    if IsEntityAVehicle(hitEntity) then
        if trackVehicles then
            return hitEntity, "vehicle", "vehicle"
        end
        return nil
    end
    if IsEntityAPed(hitEntity) then
        if IsPedInAnyVehicle(hitEntity, false) and trackVehicles then
            local veh = GetVehiclePedIsIn(hitEntity, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                return veh, "vehicle", "ped->vehicle"
            end
        end
        if trackPeds then
            return hitEntity, "ped", "ped"
        end
        return nil
    end
    return nil
end

local function ScoreCandidate(entity, entityType, camPos, camDir, scanRange, radius)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if not IsWithinAcquireDistance(entity, entityType, camPos) then return nil end

    local targetPoint = GetEntityTargetPoint(entity) or GetEntityCoords(entity)
    local toEntX = targetPoint.x - camPos.x
    local toEntY = targetPoint.y - camPos.y
    local toEntZ = targetPoint.z - camPos.z
    local along = (toEntX * camDir.x) + (toEntY * camDir.y) + (toEntZ * camDir.z)
    if along <= 0.0 or along > scanRange then return nil end

    local closestX = camPos.x + camDir.x * along
    local closestY = camPos.y + camDir.y * along
    local closestZ = camPos.z + camDir.z * along
    local perpX = targetPoint.x - closestX
    local perpY = targetPoint.y - closestY
    local perpZ = targetPoint.z - closestZ
    local perpSq = perpX * perpX + perpY * perpY + perpZ * perpZ
    local perp = math_sqrt(perpSq)
    local denom = math_max(radius, 0.05)
    local screenScore = math_clamp(1 - (perp / (denom * 1.5)), 0.0, 1.0)

    local typeScore = entityType == "vehicle" and 1.0 or 0.85
    local minDim, maxDim = GetModelDimensions(GetEntityModel(entity))
    local sizeX = maxDim.x - minDim.x
    local sizeY = maxDim.y - minDim.y
    local sizeZ = maxDim.z - minDim.z
    local sizeMag = math_sqrt(sizeX * sizeX + sizeY * sizeY + sizeZ * sizeZ)
    local sizeScore = math_clamp(sizeMag / 10.0, 0.0, 1.0)

    local netId = SafeGetNetworkId(entity)
    local prevScore = 0.0
    if netId and (netId == lastCandidateNetId or netId == lastLockedTargetNetId) then
        prevScore = 0.18
    end

    local distPenalty = math_clamp(along / scanRange, 0.0, 1.0) * 0.05
    local score = (screenScore * 0.6) + (typeScore * 0.2) + (sizeScore * 0.1) + prevScore - distPenalty
    return score, targetPoint, netId, perp
end

-- Target Scanning
local function ScanForTarget()
    Tracking.candidateEntity = nil
    Tracking.candidateType = nil
    
    Tracking.debug.entityHit = false
    Tracking.debug.entityHitPos = nil
    Tracking.debug.hitEntityType = "none"
    Tracking.debug.hitEntity = nil
    Tracking.debug.scanSource = "none"
    Tracking.debug.candidateNetId = nil
    Tracking.debug.candidateType = nil
    Tracking.debug.detectionScore = nil

    local camPos = GetCameraPosition()
    if not camPos or not PolCam.Camera or not DoesCamExist(PolCam.Camera) then return end

    local camRight, camDir, camUp = GetCamMatrix(PolCam.Camera)
    if not camDir or not camRight or not camUp then return end

    Tracking.debug.camPos = camPos
    Tracking.debug.camDir = camDir
    Tracking.debug.heliPos = GetHelicopterPosition()
    
    local scanRange = Config.Camera.RenderDistance or 1000.0
    local endPos = camPos + (camDir * scanRange)
    Tracking.debug.scanRange = scanRange
    Tracking.debug.endPos = endPos
    
    local probeHandle = StartShapeTestRay(
        camPos.x, camPos.y, camPos.z,
        endPos.x, endPos.y, endPos.z,
        1 + 16,
        PolCam.CurrentVehicle,
        7
    )
    local _, probeHit, probeCoords, _, _ = GetShapeTestResult(probeHandle)

    Tracking.debug.probeHit = probeHit
    Tracking.debug.probeHitPos = probeHit and probeCoords or endPos

    local distanceToLookPoint = scanRange
    if probeHit and probeCoords then
        distanceToLookPoint = #(camPos - probeCoords)
    end
    Tracking.debug.distanceToLookPoint = distanceToLookPoint

    local baseRadius = Config.Tracking.DetectionBaseRadius or 3.0
    local radiusScaling = Config.Tracking.DetectionScaling or 0.05
    local maxRadius = Config.Tracking.DetectionMaxRadius or 75.0

    local minLookDistance = scanRange * 0.35
    local effectiveDistance = distanceToLookPoint
    if effectiveDistance < minLookDistance then
        effectiveDistance = minLookDistance
    end

    local radius = math_max(baseRadius, effectiveDistance * radiusScaling)
    local heightDelta = math_abs(camPos.z - (Tracking.debug.probeHitPos and Tracking.debug.probeHitPos.z or camPos.z))
    local heightScale = 1 + math_clamp(heightDelta / 800.0, 0.0, 0.75)
    radius = math_min(radius * heightScale, maxRadius)
    Tracking.debug.calculatedRadius = radius

    local trackVehicles = Config.Tracking.TrackVehicles
    local trackPeds = Config.Tracking.TrackPeds
    local capsuleFlags = 0
    if trackVehicles then capsuleFlags = capsuleFlags + 2 end
    if trackPeds then capsuleFlags = capsuleFlags + 4 end
    Tracking.debug.capsuleFlags = capsuleFlags
    if capsuleFlags == 0 then
        SendNUIMessage({ action = "noPotentialTarget" })
        return
    end

    local probeRadius = math_max(baseRadius * 0.7, radius * 0.45)
    local offsetDistance = math_max(baseRadius * 1.0, radius * 0.5)

    -- 5 probes for comprehensive coverage (Center + cardinal directions)
    local probes = {
        { label = "center", offset = vector3(0.0, 0.0, 0.0) },
        { label = "up", offset = camUp * offsetDistance },
        { label = "down", offset = -camUp * offsetDistance },
        { label = "right", offset = camRight * offsetDistance },
        { label = "left", offset = -camRight * offsetDistance }
    }

    local candidates = {}

    local function considerCandidate(hitEntity, hitCoords, source)
        local candidateEntity, candidateType, hitType = GetCandidateFromHit(hitEntity, trackVehicles, trackPeds)
        if not candidateEntity then return end

        local score, targetPoint, netId = ScoreCandidate(candidateEntity, candidateType, camPos, camDir, scanRange, radius)
        if not score then return end

        local existing = candidates[candidateEntity]
        if not existing or score > existing.score then
            candidates[candidateEntity] = {
                score = score,
                type = candidateType,
                hitType = hitType,
                hitCoords = hitCoords,
                source = source,
                netId = netId,
                targetPoint = targetPoint
            }
        end
    end

    for i = 1, #probes do
        local startPos = camPos + probes[i].offset
        local probeEnd = startPos + (camDir * scanRange)
        local rayHandle = StartShapeTestCapsule(
            startPos.x, startPos.y, startPos.z,
            probeEnd.x, probeEnd.y, probeEnd.z,
            probeRadius,
            capsuleFlags,
            PolCam.CurrentVehicle,
            7
        )
        local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(rayHandle)
        if hit and hitEntity and hitEntity ~= 0 and DoesEntityExist(hitEntity) then
            considerCandidate(hitEntity, hitCoords, "probe")
        end
    end

    if next(candidates) == nil then
        local fbEntity, fbType = FindBestEntityOnRay(camPos, camDir, radius, scanRange)
        if fbEntity and fbType then
            local score, _, netId = ScoreCandidate(fbEntity, fbType, camPos, camDir, scanRange, radius)
            if score then
                candidates[fbEntity] = {
                    score = score,
                    type = fbType,
                    hitType = fbType,
                    hitCoords = GetEntityCoords(fbEntity),
                    source = "pool",
                    netId = netId
                }
            end
        end
    end

    local bestEntity = nil
    local best = nil
    for entity, data in pairs(candidates) do
        if not best or data.score > best.score then
            best = data
            bestEntity = entity
        end
    end

    local nowSticky = GetGameTimer()
    local stickyAllowed = lastCandidateEntity and (nowSticky - lastCandidateTime) <= 1200
    local maxStickyDistance = scanRange * 0.6
    if stickyAllowed and lastCandidateEntity and candidates[lastCandidateEntity] then
        local stickyCoords = GetEntityCoords(lastCandidateEntity)
        local dx = camPos.x - stickyCoords.x
        local dy = camPos.y - stickyCoords.y
        local dz = camPos.z - stickyCoords.z
        local withinStickyDistance = (dx * dx + dy * dy + dz * dz) <= (maxStickyDistance * maxStickyDistance)
        if not best or bestEntity ~= lastCandidateEntity then
            local sticky = candidates[lastCandidateEntity]
            if withinStickyDistance and (not best or (best.score - sticky.score) <= 0.08) then
                best = sticky
                bestEntity = lastCandidateEntity
            end
        end
    end

    if not bestEntity and stickyAllowed and lastCandidateEntity and lastCandidateType and DoesEntityExist(lastCandidateEntity) then
        local stickyCoords = GetEntityCoords(lastCandidateEntity)
        local dx = camPos.x - stickyCoords.x
        local dy = camPos.y - stickyCoords.y
        local dz = camPos.z - stickyCoords.z
        if (dx * dx + dy * dy + dz * dz) <= (maxStickyDistance * maxStickyDistance) then
        local stickyScore, stickyPoint, stickyNetId = ScoreCandidate(lastCandidateEntity, lastCandidateType, camPos, camDir, scanRange, radius)
        if stickyScore and stickyScore >= 0.15 then
            bestEntity = lastCandidateEntity
            best = {
                score = stickyScore,
                type = lastCandidateType,
                hitType = lastCandidateType,
                hitCoords = GetEntityCoords(lastCandidateEntity),
                source = "sticky",
                netId = stickyNetId,
                targetPoint = stickyPoint
            }
        end
        end
    end

    if not bestEntity or not best then
        Tracking.debug.scanSource = "none"
        SendNUIMessage({ action = "noPotentialTarget" })
        lastCandidateEntity = nil
        lastCandidateType = nil
        return
    end

    Tracking.candidateEntity = bestEntity
    Tracking.candidateType = best.type
    Tracking.debug.scanSource = best.source or "probe"
    Tracking.debug.entityHit = true
    Tracking.debug.entityHitPos = best.hitCoords or Tracking.debug.probeHitPos
    Tracking.debug.hitEntity = bestEntity
    Tracking.debug.hitEntityType = best.hitType or "unknown"
    Tracking.debug.detectionScore = best.score

    if Tracking.candidateEntity and Tracking.candidateType then
        local targetInfo = GetTargetInfo(Tracking.candidateEntity, Tracking.candidateType)
        SendNUIMessage({
            action = "potentialTarget",
            info = targetInfo
        })
    else
        SendNUIMessage({ action = "noPotentialTarget" })
    end

    if Tracking.candidateEntity and Tracking.candidateType then
        Tracking.debug.candidateNetId = SafeGetNetworkId(Tracking.candidateEntity)
        Tracking.debug.candidateType = Tracking.candidateType
        lastCandidateNetId = Tracking.debug.candidateNetId
        lastCandidateEntity = Tracking.candidateEntity
        lastCandidateType = Tracking.candidateType
        lastCandidateTime = GetGameTimer()
    end

    if shouldLogScans() then
        local now = GetGameTimer()
        local candidateNetId = Tracking.debug.candidateNetId
        local signature = string_format('%s|%s|%s|%s', tostring(Tracking.candidateType), tostring(candidateNetId), tostring(Tracking.debug.scanSource), tostring(Tracking.debug.hitEntityType))
        if signature ~= lastScanSignature or (now - lastScanLogTime) > 1000 then
            print(('[PolCam] scan source=%s hit=%s cand=%s net=%s radius=%.2f dist=%.1f'):format(
                tostring(Tracking.debug.scanSource),
                tostring(Tracking.debug.hitEntityType),
                tostring(Tracking.candidateType or 'none'),
                tostring(candidateNetId),
                tonumber(Tracking.debug.calculatedRadius) or 0.0,
                tonumber(Tracking.debug.distanceToLookPoint) or 0.0
            ))
            lastScanSignature = signature
            lastScanLogTime = now
        end
    end
end

-- Tracking Control
local function ResetTrackingState()
    Tracking.candidateEntity = nil
    Tracking.candidateType = nil
    Tracking.lockStartTime = 0
end

local function ClearHeliTrackingState()
    HeliTrackingState.active = false
    HeliTrackingState.targetNetId = nil
    HeliTrackingState.targetType = nil
    HeliTrackingState.ownerSrc = nil
    HeliTrackingState.vehicleNetId = nil
end

local function SendLockClearedToNUI()
    SendNUIMessage({ action = "lockCleared" })
    SendNUIMessage({ action = "hidePilotHUD" })
end

local function IsTargetInfoCompatible(cachedInfo, newInfo)
    if not cachedInfo or not newInfo then
        return true
    end

    if cachedInfo.type ~= newInfo.type then
        return false
    end

    if cachedInfo.type == "vehicle" then
        if cachedInfo.plate and cachedInfo.plate ~= "OBSCURED"
            and newInfo.plate and newInfo.plate ~= "OBSCURED"
            and cachedInfo.plate ~= newInfo.plate then
            return false
        end

        if cachedInfo.model and cachedInfo.model ~= "" and cachedInfo.model ~= "Unknown Vehicle"
            and newInfo.model and newInfo.model ~= "" and newInfo.model ~= "Unknown Vehicle"
            and cachedInfo.model ~= newInfo.model then
            return false
        end
    elseif cachedInfo.type == "ped" then
        if cachedInfo.isPlayer and newInfo.isPlayer
            and cachedInfo.name and newInfo.name
            and cachedInfo.name ~= newInfo.name then
            return false
        end
    end

    return true
end

function ClearLock()
    local hadLock = PolCam.LockedTarget ~= nil
    
    lastLockedTargetNetId = nil
    Tracking.occludedSince = nil

    PolCam.LockedTarget = nil
    PolCam.LockedTargetType = nil
    PolCam.TargetInfo = nil
    PersistentTracking.Active = false

    ResetTrackingState()
    ClearHeliTrackingState()

    if hadLock then
        TriggerServerEvent('polcam:trackingSync', false, nil, nil)
    end

    SendLockClearedToNUI()

    if hadLock and shouldLogEvents() then
        print('[PolCam] lock cleared')
    end
end

-- Called when the camera is activated to set the timestamp for grace period calculations
function OnCameraActivated_Tracking()
    Tracking.cameraActivatedTime = GetGameTimer()
end

-- Lock acquisition state
local LockingInProgress = false

-- Helper to check if es_lib is available
local function IsEsLibAvailable()
    return GetResourceState('es_lib') == 'started' 
        and type(exports) == 'table' 
        and exports.es_lib 
        and exports.es_lib.progress
end

-- Internal function to complete the lock after validation/progress
local function CompleteLock(entity, entityType)
    if not entity or not DoesEntityExist(entity) then
        LockingInProgress = false
        return false
    end
    
    PolCam.LockedTarget = entity
    PolCam.LockedTargetType = entityType
    PolCam.TargetInfo = GetTargetInfo(entity, entityType)

    Tracking.lockStartTime = GetGameTimer()

    local targetNetId = SafeGetNetworkId(PolCam.LockedTarget)
    if not targetNetId then
        LockingInProgress = false
        return false
    end

    lastLockedTargetNetId = targetNetId

    -- For the player's own vehicle, use direct native (always networked)
    local vehicleNetId = nil

    if PolCam.CurrentVehicle and DoesEntityExist(PolCam.CurrentVehicle) then
        vehicleNetId = NetworkGetNetworkIdFromEntity(PolCam.CurrentVehicle)
    end

    HeliTrackingState.active = true
    HeliTrackingState.targetNetId = targetNetId
    HeliTrackingState.targetType = PolCam.LockedTargetType
    HeliTrackingState.ownerSrc = GetPlayerServerId(PlayerId())
    HeliTrackingState.vehicleNetId = vehicleNetId
    HeliTrackingState.lastUpdateTime = GetGameTimer()

    TriggerServerEvent('polcam:trackingSync', true, targetNetId, PolCam.LockedTargetType)

    PlayPolCamSound("TargetLocked")

    SendNUIMessage({
        action = "targetLocked",
        info = PolCam.TargetInfo
    })

    if shouldLogEvents() then
        print(('[PolCam] lock complete net=%s type=%s'):format(tostring(targetNetId), tostring(entityType)))
    end
    
    LockingInProgress = false
    return true
end

-- Grace period (ms) after camera activation where we won't toggle off an existing lock
local REENTRY_GRACE_PERIOD_MS = 500

function StartLocking()
    -- If we already have a locked target, this is a toggle-off request
    if PolCam.LockedTarget then
        -- Don't toggle off if we just re-entered the camera with an existing lock
        -- This prevents accidental unlocks when re-entering with a persistent track
        local now = GetGameTimer()
        local timeSinceActivation = now - (Tracking.cameraActivatedTime or 0)
        if timeSinceActivation < REENTRY_GRACE_PERIOD_MS then
            -- Within grace period, ignore this toggle-off attempt
            return
        end
        
        ClearLock()
        PlayPolCamSound("TargetLost")
        return
    end
    
    if LockingInProgress then
        return
    end
    
    if not Tracking.candidateEntity or not DoesEntityExist(Tracking.candidateEntity) then
        return
    end
    
    if not Tracking.candidateType then
        return
    end
    
    -- Capture the candidate before async operation
    local targetEntity = Tracking.candidateEntity
    local targetType = Tracking.candidateType
    
    -- Instant lock mode - lock immediately
    if Config.InstantLock then
        CompleteLock(targetEntity, targetType)
        return
    end
    
    -- Non-instant mode - use es_lib progress bar
    if not IsEsLibAvailable() then
        -- Fallback to instant lock if es_lib not available
        CompleteLock(targetEntity, targetType)
        return
    end
    
    LockingInProgress = true
    
    -- Get the lock duration from config (default 2000ms)
    local lockDuration = (Config.Tracking and Config.Tracking.LockDurationMs) or 2000
    
    -- Run the progress bar in a thread to avoid blocking
    CreateThread(function()
        local completed = exports.es_lib:progress({
            duration = lockDuration,
            label = "ACQUIRING TARGET",
            position = "bottom",
            style = "bar",
            canCancel = true,
            useWhileDead = false,
            disable = {
                move = false,
                car = false,
                combat = false,
                mouse = false
            }
        })
        
        if not completed then
            -- Cancelled by user
            LockingInProgress = false
            return
        end
        
        -- Verify target still exists and is still the same candidate
        if not DoesEntityExist(targetEntity) then
            LockingInProgress = false
            return
        end
        
        -- Verify we still have a valid camera
        if not PolCam.Active then
            LockingInProgress = false
            return
        end
        
        -- Complete the lock
        CompleteLock(targetEntity, targetType)
    end)
end

-- Occlusion Check
local function BuildOcclusionSamplePoints(target, targetPoint, targetType)
    local points = { targetPoint }
    if targetType == "vehicle" then
        local minDim, maxDim = GetModelDimensions(GetEntityModel(target))
        local height = math_max(0.5, maxDim.z - minDim.z)
        local up = math_min(1.2, height * 0.35)
        local down = math_min(0.9, height * 0.25)
        points[#points + 1] = vector3(targetPoint.x, targetPoint.y, targetPoint.z + up)
        points[#points + 1] = vector3(targetPoint.x, targetPoint.y, targetPoint.z - down)
    elseif targetType == "ped" then
        points[#points + 1] = vector3(targetPoint.x, targetPoint.y, targetPoint.z + 0.35)
        points[#points + 1] = vector3(targetPoint.x, targetPoint.y, targetPoint.z - 0.25)
    end
    return points
end

local function IsOccludedFrom(origin, point, toleranceSq)
    local rayHandle = StartShapeTestRay(
        origin.x, origin.y, origin.z,
        point.x, point.y, point.z,
        1,
        PolCam.CurrentVehicle,
        7
    )
    local _, hit, hitCoords, _, _ = GetShapeTestResult(rayHandle)
    if not hit then
        return false
    end
    if hitCoords then
        local tolSq = toleranceSq or 0.0
        local tdx = point.x - origin.x
        local tdy = point.y - origin.y
        local tdz = point.z - origin.z
        local targetDistSq = (tdx * tdx + tdy * tdy + tdz * tdz)
        local hdx = hitCoords.x - origin.x
        local hdy = hitCoords.y - origin.y
        local hdz = hitCoords.z - origin.z
        local hitDistSq = (hdx * hdx + hdy * hdy + hdz * hdz)

        if hitDistSq >= (targetDistSq - tolSq) then
            return false
        end

        if tolSq > 0.0 then
            local dx = hitCoords.x - point.x
            local dy = hitCoords.y - point.y
            local dz = hitCoords.z - point.z
            if (dx * dx + dy * dy + dz * dz) <= tolSq then
                return false
            end
        end
    end
    return true
end

local function CheckTargetOcclusion(now)
    local tracking = Config.Tracking
    if not tracking or not tracking.OcclusionEnabled then return end

    local target = PolCam.LockedTarget
    if not target or not DoesEntityExist(target) then return end

    local intervalMs = tracking.OcclusionCheckIntervalMs or 150
    if (now - Tracking.lastOcclusionCheck) < intervalMs then return end
    Tracking.lastOcclusionCheck = now

    -- Determine ray origin: use camera coords when active, otherwise helicopter position
    local origin = PolCam.Active and PolCam.CameraCoords or GetHelicopterPosition()
    if not origin then return end

    local targetPoint = GetEntityTargetPoint(target) or GetEntityCoords(target)
    local targetType = PolCam.LockedTargetType
    local samplePoints = BuildOcclusionSamplePoints(target, targetPoint, targetType)
    local tolerance = tracking.OcclusionNearTargetTolerance or 2.0
    local toleranceSq = tolerance * tolerance
    local occluded = true

    for i = 1, #samplePoints do
        if not IsOccludedFrom(origin, samplePoints[i], toleranceSq) then
            occluded = false
            break
        end
    end

    if Config.Debug and Config.Debug.Enabled and Config.Debug.ShowScanDetails then
        Tracking.debug.occluded = occluded
        Tracking.debug.occlusionAgeMs = Tracking.occludedSince and (now - Tracking.occludedSince) or 0
        Tracking.debug.occlusionHitType = "none"
        Tracking.debug.occlusionHitModel = nil
        Tracking.debug.occlusionHitPos = nil
        Tracking.debug.occlusionHitEntity = nil

        if occluded then
            local rayHandle = StartShapeTestRay(
                origin.x, origin.y, origin.z,
                targetPoint.x, targetPoint.y, targetPoint.z,
                -1,
                PolCam.CurrentVehicle,
                7
            )
            local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(rayHandle)
            if hit then
                Tracking.debug.occlusionHitPos = hitCoords
                Tracking.debug.occlusionHitEntity = hitEntity
                if hitEntity and hitEntity ~= 0 and DoesEntityExist(hitEntity) then
                    if IsEntityAVehicle(hitEntity) then
                        local modelHash = GetEntityModel(hitEntity)
                        local modelName = GetDisplayNameFromVehicleModel(modelHash)
                        Tracking.debug.occlusionHitType = "vehicle"
                        Tracking.debug.occlusionHitModel = modelName ~= "" and modelName or tostring(modelHash)
                    elseif IsEntityAPed(hitEntity) then
                        Tracking.debug.occlusionHitType = IsPedAPlayer(hitEntity) and "player" or "ped"
                    else
                        Tracking.debug.occlusionHitType = "entity"
                    end
                else
                    Tracking.debug.occlusionHitType = "world"
                end
            end
        end
    end

    if occluded then
        -- Target is occluded
        if not Tracking.occludedSince then
            Tracking.occludedSince = now
        end
        local graceMs = tracking.OcclusionGracePeriodMs or 3000
        if (now - Tracking.occludedSince) >= graceMs then
            ClearLock()
            PlayPolCamSound("TargetLost")
        end
    else
        -- Line of sight is clear
        Tracking.occludedSince = nil
    end
end

-- Active Tracking Update
local function UpdateActiveTracking(now)
    if not PolCam.LockedTarget or not DoesEntityExist(PolCam.LockedTarget) then
        ClearLock()
        PlayPolCamSound("TargetLost")
        return
    end

    CheckTargetOcclusion(now)

    -- Target may have been cleared by occlusion check
    if not PolCam.LockedTarget then return end

    UpdateLockedTargetInfo()
end

-- Tracking Update (called every frame)
local function ShouldDrawTargetLabel(cfg)
    if not cfg or not cfg.Enabled then return false end
    if PolCam.Active then
        return cfg.ShowWhenCameraActive ~= false
    end
    if PersistentTracking.Active then
        return cfg.ShowWhilePersistent ~= false
    end
    return cfg.ShowWhenCameraOff ~= false
end

local function GetHighContrastColor()
    if not Config.UI or not Config.UI.HighContrast or not Config.UI.HighContrast.Enabled then
        return nil
    end

    local theme = Config.UI.HighContrast.Theme or "green"
    
    -- Handle Hex Colors (e.g. "#FF00FF")
    if theme:sub(1,1) == "#" then
        local r = tonumber(theme:sub(2,3), 16) or 255
        local g = tonumber(theme:sub(4,5), 16) or 255
        local b = tonumber(theme:sub(6,7), 16) or 255
        return {r, g, b, 230}
    end

    local themes = {
        ["green"]  = {0, 255, 0, 230},
        ["black"]  = {0, 0, 0, 230},
        ["orange"] = {255, 170, 0, 230},
        ["red"]    = {255, 0, 0, 230},
        ["purple"] = {191, 0, 255, 230},
        ["blue"]   = {0, 136, 255, 230},
        ["pink"]   = {255, 0, 255, 230},
    }

    return themes[theme:lower()] or themes["green"]
end

local function DrawWorldTargetLabel()
    local cfg = Config.UI and Config.UI.TargetLabel
    if not ShouldDrawTargetLabel(cfg) then return end

    local target = PolCam.LockedTarget
    local info = PolCam.TargetInfo
    if not target or not DoesEntityExist(target) or not info or not info.coords then return end

    local camCoords = PolCam.Active and PolCam.CameraCoords or GetEntityCoords(PlayerPedId())
    if not camCoords then return end

    local currentTargetCoords = GetEntityCoords(target)
    if not currentTargetCoords or currentTargetCoords == vector3(0,0,0) then
        currentTargetCoords = info.coords
    end

    local distance = #(camCoords - currentTargetCoords)
    if cfg.MaxDistance and distance > cfg.MaxDistance then return end

    local now = GetGameTimer()
    if Tracking.labelTargetEntity ~= target then
        Tracking.labelTargetEntity = target
        Tracking.labelSmoothedDistance = distance
        Tracking.labelLastUpdateTime = now
    end

    local lastUpdate = Tracking.labelLastUpdateTime or now
    local dt = math_max(0.0, (now - lastUpdate) / 1000)
    Tracking.labelLastUpdateTime = now

    local smoothingSpeed = (cfg and cfg.LabelSmoothingSpeed) or 12.0
    local t = 1.0
    if dt < 1.0 then
        t = 1.0 - math_exp(-smoothingSpeed * dt)
    end
    
    local smoothedDistance = Tracking.labelSmoothedDistance or distance
    smoothedDistance = smoothedDistance + (distance - smoothedDistance) * t
    Tracking.labelSmoothedDistance = smoothedDistance

    local zOffset = cfg.HeightOffsetVehicle or 1.6
    if info.type == "ped" then
        zOffset = cfg.HeightOffsetPed or 1.0
    end

    local pos = currentTargetCoords + vector3(0.0, 0.0, zOffset)

    local scale = 0.35
    if distance and distance > 0.0 then
        scale = math_clamp(1.2 / distance, 0.25, 0.5)
    end

    local text = string_format("TRACK %d M", math_floor(smoothedDistance + 0.5))

    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextScale(scale, scale)
    local color = cfg.Color or {0, 255, 0, 230}
    if cfg.FollowHighContrast then
        local themeColor = GetHighContrastColor()
        if themeColor then
            color = themeColor
        end
    end
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

function UpdateTargeting()
    if not Config.Tracking or not Config.Tracking.Enabled then return end
    
    local now = GetGameTimer()

    Tracking.debug.zoom = PolCam and PolCam.Zoom or 0
    Tracking.debug.fov = PolCam and PolCam.FOV or 0
    
    if now - Tracking.lastScanTime >= Tracking.scanIntervalMs then
        Tracking.lastScanTime = now
        
        if not PolCam.LockedTarget then
            ScanForTarget()
        end
    end

    Tracking.debug.candidateType = Tracking.candidateType
    
    if PolCam.LockedTarget then
        UpdateActiveTracking(now)
        DrawWorldTargetLabel()
    end
end

-- Unified Heli Tracking Sync
local function GetCurrentVehicleNetId()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    -- For the player's own vehicle, use direct native (always networked)
    return NetworkGetNetworkIdFromEntity(vehicle)
end

local function SyncLocalLockToHeliState()
    if HeliTrackingState.active and HeliTrackingState.targetNetId then
        local entity = NetworkGetEntityFromNetworkId(HeliTrackingState.targetNetId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local myId = GetPlayerServerId(PlayerId())
            local wasAlreadyLocked = PolCam.LockedTarget == entity
            local cachedInfo = PolCam.TargetInfo
            local targetInfo = GetTargetInfo(entity, HeliTrackingState.targetType)

            if not targetInfo then
                ClearLock()
                return
            end

            if lastLockedTargetNetId
                and lastLockedTargetNetId == HeliTrackingState.targetNetId
                and cachedInfo
                and not IsTargetInfoCompatible(cachedInfo, targetInfo) then
                ClearLock()
                return
            end

            PolCam.LockedTarget = entity
            PolCam.LockedTargetType = HeliTrackingState.targetType
            PolCam.TargetInfo = targetInfo
            PersistentTracking.Active = true
            lastLockedTargetNetId = HeliTrackingState.targetNetId
            
            if not wasAlreadyLocked and HeliTrackingState.ownerSrc ~= myId then
                if PlayPolCamSound then
                    PlayPolCamSound("TargetLocked")
                end
                SendNUIMessage({
                    action = "targetLocked",
                    info = PolCam.TargetInfo
                })
                if shouldLogEvents() then
                    print(('[PolCam] shared lock applied net=%s type=%s owner=%s'):format(
                        tostring(HeliTrackingState.targetNetId),
                        tostring(HeliTrackingState.targetType),
                        tostring(HeliTrackingState.ownerSrc)
                    ))
                end
            end
        else
            lastLockedTargetNetId = nil
            PolCam.LockedTarget = nil
            PolCam.LockedTargetType = nil
            PolCam.TargetInfo = nil
            PersistentTracking.Active = false
            SendNUIMessage({ action = "lockCleared" })
            if shouldLogEvents() then
                print('[PolCam] shared lock cleared (missing entity)')
            end
        end
    else
        local hadLock = PolCam.LockedTarget ~= nil
        local hadPersistent = PersistentTracking.Active

        lastLockedTargetNetId = nil
        PolCam.LockedTarget = nil
        PolCam.LockedTargetType = nil
        PolCam.TargetInfo = nil
        PersistentTracking.Active = false
        
        ResetTrackingState()
        SendLockClearedToNUI()
        
        if hadLock or hadPersistent then
            if PlayPolCamSound then
                PlayPolCamSound("TargetLost")
            end
            if shouldLogEvents() then
                print('[PolCam] shared lock cleared (state inactive)')
            end
        end
    end
end

RegisterNetEvent('polcam:heliTrackingState')
AddEventHandler('polcam:heliTrackingState', function(vehicleNetId, state)
    local myVehicleNetId = GetCurrentVehicleNetId()
    
    if myVehicleNetId ~= vehicleNetId then
        return
    end
    
    if state.seq and HeliTrackingState.seq and state.seq < HeliTrackingState.seq then
        return
    end
    
    HeliTrackingState.active = state.active or false
    HeliTrackingState.targetNetId = state.targetNetId
    HeliTrackingState.targetType = state.targetType
    HeliTrackingState.ownerSrc = state.ownerSrc
    HeliTrackingState.vehicleNetId = vehicleNetId
    HeliTrackingState.seq = state.seq or 0
    HeliTrackingState.lastUpdateTime = GetGameTimer()

    if shouldLogEvents() then
        if lastSharedLogSeq ~= HeliTrackingState.seq
            or lastSharedLogTarget ~= HeliTrackingState.targetNetId
            or lastSharedLogActive ~= HeliTrackingState.active
            or lastSharedLogOwner ~= HeliTrackingState.ownerSrc then
            print(('[PolCam] heliTrackingState active=%s net=%s type=%s owner=%s seq=%s'):format(
                tostring(HeliTrackingState.active),
                tostring(HeliTrackingState.targetNetId),
                tostring(HeliTrackingState.targetType),
                tostring(HeliTrackingState.ownerSrc),
                tostring(HeliTrackingState.seq)
            ))
            lastSharedLogSeq = HeliTrackingState.seq
            lastSharedLogTarget = HeliTrackingState.targetNetId
            lastSharedLogActive = HeliTrackingState.active
            lastSharedLogOwner = HeliTrackingState.ownerSrc
        end
    end
    
    SyncLocalLockToHeliState()
end)

RegisterNetEvent('polcam:trackingUpdate')
AddEventHandler('polcam:trackingUpdate', function(sourcePlayerId, data)
    local myServerId = GetPlayerServerId(PlayerId())
    if sourcePlayerId == myServerId then
        return
    end

    if data and data.active and data.targetNetId then
        HeliTrackingState.active = true
        HeliTrackingState.targetNetId = data.targetNetId
        HeliTrackingState.targetType = data.targetType
        HeliTrackingState.ownerSrc = sourcePlayerId
        HeliTrackingState.vehicleNetId = data.vehicleNetId or GetCurrentVehicleNetId()
        HeliTrackingState.lastUpdateTime = GetGameTimer()
        if shouldLogEvents() then
            if lastSharedLogSeq ~= HeliTrackingState.seq
                or lastSharedLogTarget ~= HeliTrackingState.targetNetId
                or lastSharedLogActive ~= HeliTrackingState.active
                or lastSharedLogOwner ~= HeliTrackingState.ownerSrc then
                print(('[PolCam] trackingUpdate active=%s net=%s type=%s owner=%s'):format(
                    tostring(HeliTrackingState.active),
                    tostring(HeliTrackingState.targetNetId),
                    tostring(HeliTrackingState.targetType),
                    tostring(HeliTrackingState.ownerSrc)
                ))
                lastSharedLogSeq = HeliTrackingState.seq
                lastSharedLogTarget = HeliTrackingState.targetNetId
                lastSharedLogActive = HeliTrackingState.active
                lastSharedLogOwner = HeliTrackingState.ownerSrc
            end
        end
        SyncLocalLockToHeliState()
    else
        if HeliTrackingState.ownerSrc == sourcePlayerId then
            HeliTrackingState.active = false
            HeliTrackingState.targetNetId = nil
            HeliTrackingState.targetType = nil
            HeliTrackingState.ownerSrc = nil
            HeliTrackingState.lastUpdateTime = GetGameTimer()
            if shouldLogEvents() then
                print('[PolCam] trackingUpdate cleared by owner')
                lastSharedLogSeq = HeliTrackingState.seq
                lastSharedLogTarget = HeliTrackingState.targetNetId
                lastSharedLogActive = HeliTrackingState.active
                lastSharedLogOwner = HeliTrackingState.ownerSrc
            end
            SyncLocalLockToHeliState()
        end
    end
end)

-- Plate Visibility Check
function IsPlateVisible(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    local camCoords = PolCam.Active and PolCam.CameraCoords or GetEntityCoords(PolCam.CurrentVehicle)
    if not camCoords then return false end
    
    local vehCoords = GetEntityCoords(vehicle)
    local vehForward = GetEntityForwardVector(vehicle)
    
    local toCamX = camCoords.x - vehCoords.x
    local toCamY = camCoords.y - vehCoords.y
    local toCamZ = camCoords.z - vehCoords.z
    local len = math_sqrt(toCamX*toCamX + toCamY*toCamY + toCamZ*toCamZ)
    if len == 0 then return false end
    
    local invLen = 1 / len
    toCamX = toCamX * invLen
    toCamY = toCamY * invLen
    toCamZ = toCamZ * invLen
    
    local dot = vehForward.x * toCamX + vehForward.y * toCamY + vehForward.z * toCamZ
    
    if not cachedPlateThreshold then
        local angle = (Config.Tracking and Config.Tracking.PlateVisibilityAngle) or 45.0
        cachedPlateThreshold = math_cos(math_rad(angle))
    end
    
    return math_abs(dot) >= cachedPlateThreshold
end

-- Target Info Extraction
function GetTargetInfo(entity, entityType)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end
    
    local coords = GetEntityCoords(entity)
    local heliPos = GetHelicopterPosition()
    
    local info = {
        type = entityType,
        coords = coords,
        speed = math_floor(GetEntitySpeed(entity) * 2.236936),
        heading = math_floor(GetEntityHeading(entity)),
        distance = heliPos and #(heliPos - coords) or 0,
    }
    
    if entityType == "vehicle" then
        local modelHash = GetEntityModel(entity)
        
        if not MakeNameCache[modelHash] then
            local makeStr = GetLabelText(GetMakeNameFromVehicleModel(modelHash))
            MakeNameCache[modelHash] = (makeStr == "NULL") and "UNKNOWN" or makeStr
        end
        info.make = MakeNameCache[modelHash]
        
        if not ModelNameCache[modelHash] then
            local modelStr = GetLabelText(GetDisplayNameFromVehicleModel(modelHash))
            if modelStr == "NULL" then 
                modelStr = GetDisplayNameFromVehicleModel(modelHash) 
            end
            ModelNameCache[modelHash] = modelStr
        end
        info.model = ModelNameCache[modelHash]
        
        if IsPlateVisible(entity) then
            info.plate = GetVehicleNumberPlateText(entity)
        else
            info.plate = "OBSCURED"
        end
        
        info.class = GetVehicleClass(entity)
        
        local driver = GetPedInVehicleSeat(entity, -1)
        if driver and driver ~= 0 and DoesEntityExist(driver) then
            if IsPedAPlayer(driver) then
                info.driver = GetPlayerName(NetworkGetPlayerIndexFromPed(driver))
                info.isPlayerVehicle = true
            else
                info.driver = "NPC"
                info.isPlayerVehicle = false
            end
        end
        
    elseif entityType == "ped" then
        if IsPedAPlayer(entity) then
            info.name = GetPlayerName(NetworkGetPlayerIndexFromPed(entity))
            info.isPlayer = true
        else
            info.name = "Civilian"
            info.isPlayer = false
        end
        
        if IsPedInAnyVehicle(entity, false) then
            local veh = GetVehiclePedIsIn(entity, false)
            info.inVehicle = true
            info.vehicleModel = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
            
            if IsPlateVisible(veh) then
                info.vehiclePlate = GetVehicleNumberPlateText(veh)
            else
                info.vehiclePlate = "OBSCURED"
            end
        end
    end
    
    return info
end

-- Update Locked Target Info
function UpdateLockedTargetInfo()
    if not PolCam.LockedTarget or not DoesEntityExist(PolCam.LockedTarget) then
        return
    end
    
    if not PolCam.LockedTargetType then
        ClearLock()
        PlayPolCamSound("TargetLost")
        return
    end
    
    local now = GetGameTimer()
    if now - LastUpdateLockedTime < UPDATE_LOCKED_INTERVAL then
        return
    end
    LastUpdateLockedTime = now
    
    PolCam.TargetInfo = GetTargetInfo(PolCam.LockedTarget, PolCam.LockedTargetType)
    
    if not PolCam.TargetInfo then
        ClearLock()
        PlayPolCamSound("TargetLost")
        return
    end
end

-- Persistent Tracking
function GetLockedTargetCoords()
    if not PolCam.LockedTarget or not DoesEntityExist(PolCam.LockedTarget) then
        return nil
    end
    return GetEntityCoords(PolCam.LockedTarget)
end

function IsPersistentTrackingActive()
    return PersistentTracking.Active and PolCam.LockedTarget ~= nil
end

function IsHeliTrackingActive()
    return HeliTrackingState.active == true
end

function OnCameraDeactivated_Tracking()
    if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        PersistentTracking.Active = true
        
        if not PersistentTracking.LoopRunning then
            PersistentTracking.LoopRunning = true
            CreateThread(PersistentTrackingLoop)
        end
    else
        PersistentTracking.Active = false
    end
end

function PersistentTrackingLoop()
    if not PersistentTracking.RenderLoopRunning then
        PersistentTracking.RenderLoopRunning = true
        CreateThread(PersistentTrackingRenderLoop)
    end
    
    while PersistentTracking.Active or PolCam.Active do
        if PolCam.Active then
            Wait(500)
        else
            if PersistentTracking.Active and PolCam.LockedTarget and HeliTrackingState.active then
                if not DoesEntityExist(PolCam.LockedTarget) then
                    ClearLock()
                    PlayPolCamSound("TargetLost")
                else
                    local now = GetGameTimer()
                    CheckTargetOcclusion(now)

                    if not PolCam.LockedTarget then
                        goto continue
                    end

                    UpdateActiveTracking(now)

                    if PolCam.LockedTarget then
                        local heliPos = GetHelicopterPosition()
                        if heliPos then
                            local targetPos = GetEntityCoords(PolCam.LockedTarget)
                            local dx = heliPos.x - targetPos.x
                            local dy = heliPos.y - targetPos.y
                            local dz = heliPos.z - targetPos.z
                            local distSq = dx*dx + dy*dy + dz*dz
                            local maxDistSq = PersistentTracking.MaxDistance * PersistentTracking.MaxDistance
                            
                            if distSq > maxDistSq then
                                ClearLock()
                                PlayPolCamSound("TargetLost")
                            else
                                if (now - PersistentTracking.LastSyncTime) >= PersistentTracking.SyncIntervalMs then
                                    PersistentTracking.LastSyncTime = now
                                    if lastLockedTargetNetId then
                                        TriggerServerEvent('polcam:trackingPosition', targetPos, heliPos, lastLockedTargetNetId)
                                    end
                                end
                            end
                        else
                            ClearLock()
                        end
                    end
                end
            elseif (PersistentTracking.Active or PolCam.LockedTarget) and not HeliTrackingState.active then
                PolCam.LockedTarget = nil
                PolCam.LockedTargetType = nil
                PolCam.TargetInfo = nil
                PersistentTracking.Active = false
                SendLockClearedToNUI()
                if PlayPolCamSound then
                    PlayPolCamSound("TargetLost")
                end
            end

            ::continue::
            Wait(PersistentTracking.UpdateIntervalMs)
        end
    end

    PersistentTracking.LoopRunning = false
end

function PersistentTrackingRenderLoop()
    while true do
        if not PolCam.Active and PersistentTracking.Active and PolCam.LockedTarget and HeliTrackingState.active then
            DrawWorldTargetLabel()
            Wait(0)
        else
            Wait(100)
        end
    end
end
