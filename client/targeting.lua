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
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
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
    scanIntervalMs = 50,
    hasLOS = true,
    lockStartTime = 0,
    cameraActivatedTime = 0,
    candidateEntity = nil,
    candidateType = nil,
    labelSmoothedDistance = nil,
    labelLastUpdateTime = 0,
    labelTargetEntity = nil,
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
        losTargetPoint = nil,
        losResult = nil,
        losStats = nil,
        occlusion = nil,
        shared = nil,
        detectionScore = nil,
        zoom = 0,
        fov = 0
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
local lastReacquireUiState = nil

local SyncedTracking = HeliTrackingState

-- Optimization Caches
local ModelNameCache = {}
local MakeNameCache = {}
local LastUpdateLockedTime = 0
local UPDATE_LOCKED_INTERVAL = 100
local LastPoolScanTime = 0
local POOL_SCAN_INTERVAL = 500
local cachedPlateThreshold = nil
local lastScanSignature = nil
local lastScanLogTime = 0
local lastLosLogHasLOS = nil
local lastLosLogOccType = nil
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

local function GetOcclusionOrigin()
    local camPos = GetCameraPosition()
    if camPos then
        return camPos
    end

    if PolCam.CurrentVehicle and DoesEntityExist(PolCam.CurrentVehicle) then
        local coords = GetEntityCoords(PolCam.CurrentVehicle)
        local minDim, maxDim = GetModelDimensions(GetEntityModel(PolCam.CurrentVehicle))
        local height = maxDim.z - minDim.z
        local zOffset = math_max(0.5, height * 0.5)
        return coords + vector3(0.0, 0.0, zOffset)
    end

    return nil
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
    
    if Config.Debug.ShowLOSRay and PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        local heliPos = GetHelicopterPosition()
        local targetPoint = GetEntityTargetPoint(PolCam.LockedTarget)
        
        if heliPos and targetPoint then
            local col
            if Tracking.hasLOS then
                col = Config.Debug.LOSColor or {0, 255, 0, 200}
            else
                col = Config.Debug.LOSBlockedColor or {255, 0, 0, 200}
            end
            DrawDebugLine(heliPos, targetPoint, col[1], col[2], col[3], col[4])
            DrawDebugSphere(heliPos, 1.0, col[1], col[2], col[3], 150)
        end
    end

    if Config.Debug.ShowOcclusionDetails and Tracking.debug.losResult and Tracking.debug.losResult.samples then
        local samples = Tracking.debug.losResult.samples
        for i = 1, #samples do
            local sample = samples[i]
            local point = sample and sample.point
            if point then
                local col = sample.clear and {0, 255, 0, 160} or {255, 0, 0, 160}
                DrawDebugSphere(point, 0.3, col[1], col[2], col[3], col[4])
            end
        end
    end
end

local DEBUG_PANEL_INTERVAL_MS = 200
local lastDebugPanelUpdate = 0
local debugPanelShown = false

local function formatVec3(v)
    if not v then return nil end
    return string_format('%.1f %.1f %.1f', v.x, v.y, v.z)
end

local function formatHeights(heights)
    if type(heights) ~= 'table' or #heights == 0 then return 'none' end
    local out = {}
    for i = 1, #heights do
        out[#out + 1] = string_format('%.2f', heights[i])
    end
    return table_concat(out, ',')
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

    if cfg.ShowLOSStatus then
        lines[#lines + 1] = { label = 'LOS', value = Tracking.hasLOS and 'OK' or 'BLOCKED', color = Tracking.hasLOS and '#10b981' or '#ff4444' }
    end

    if cfg.ShowOcclusionDetails then
        local occ = dbg.occlusion or {}
        lines[#lines + 1] = { label = 'OccType', value = tostring(occ.occlusionType or 'none') }
        lines[#lines + 1] = { label = 'OccMs', value = string_format('%.0f', occ.occludedMs or 0) }
        lines[#lines + 1] = { label = 'OccMax', value = string_format('%.0f', occ.maxOccludedMs or 0) }
        lines[#lines + 1] = { label = 'OccExtra', value = string_format('%.0f', occ.extraGraceMs or 0) }
        lines[#lines + 1] = { label = 'CrosshairOK', value = occ.crosshairOk or false }
        lines[#lines + 1] = { label = 'Reacquiring', value = occ.reacquiring or false }
        local stats = dbg.losStats or {}
        lines[#lines + 1] = { label = 'RayRadius', value = string_format('%.2f', stats.rayRadius or 0) }
        lines[#lines + 1] = { label = 'Samples', value = string_format('%d/%d', stats.clearCount or 0, stats.sampleCount or 0) }
        lines[#lines + 1] = { label = 'Heights', value = formatHeights(stats.sampleHeights) }
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
        candidateNetId = Tracking.debug.candidateNetId,
        detectionScore = Tracking.debug.detectionScore,
        candidateType = Tracking.candidateType,
        zoom = Tracking.debug.zoom,
        fov = Tracking.debug.fov
    }

    Tracking.debug.shared = shared

    return {
        scan = scan,
        los = Tracking.debug.losResult,
        losStats = Tracking.debug.losStats,
        occlusion = Tracking.debug.occlusion,
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

-- Line of Sight / Occlusion Checking
local OCCLUSION_DEFAULT_SAMPLE_HEIGHTS = { 0.55, 0.9 }
local OCCLUSION_RAY_FLAGS = 1 + 2 + 4 + 8 + 16
local OCCLUSION_RAY_P9 = 7

local OcclusionState = {
    lastCheckTime = 0,
    occludedSince = 0,
    occlusionType = nil,
    reacquiring = false,
    reacquireStartTime = 0
}

local OCCLUSION_TYPE_NONE = "none"
local OCCLUSION_TYPE_TERRAIN = "terrain"
local OCCLUSION_TYPE_BUILDING = "building"
local OCCLUSION_TYPE_VEGETATION = "vegetation"

local GetShapeTestResultIncludingMaterial = GetShapeTestResultIncludingMaterial

local TERRAIN_MATERIAL_HASHES = {
    [1109728704] = true,
    [-1286696947] = true,
    [-1885547121] = true,
    [-461750719] = true,
    [-1942898710] = true,
    [-700658213] = true,
    [510490462] = true,
    [1635937914] = true,
    [-1286696947] = true,
    [581794674] = true,
    [-1595148316] = true,
    [-1833527165] = true,
    [-1942898710] = true,
    [223086562] = true,
    [1109728704] = true,
}

local VEGETATION_MATERIAL_HASHES = {
    [-461750719] = true,
    [1064636955] = true,
    [-1885547121] = true,
    [581794674] = true,
}

local function ClassifyHitMaterial(materialHash, hitEntity, hitCoords, origin)
    if hitEntity and hitEntity ~= 0 then
        local exists = false
        local success = pcall(function()
            exists = DoesEntityExist(hitEntity)
        end)
        
        if success and exists then
            -- Ignore our own helicopter entirely
            if PolCam.CurrentVehicle and hitEntity == PolCam.CurrentVehicle then
                return OCCLUSION_TYPE_VEGETATION -- Treat as ignorable
            end

            if PolCam.CurrentVehicle and GetEntityAttachedTo then
                local attachedTo = GetEntityAttachedTo(hitEntity)
                if attachedTo and attachedTo ~= 0 and attachedTo == PolCam.CurrentVehicle then
                    return OCCLUSION_TYPE_VEGETATION
                end
            end
            
            if IsEntityAVehicle(hitEntity) then
                return OCCLUSION_TYPE_VEGETATION
            end
            
            if IsEntityAPed(hitEntity) then
                return OCCLUSION_TYPE_VEGETATION
            end
        end
    end
    
    if VEGETATION_MATERIAL_HASHES[materialHash] then
        return OCCLUSION_TYPE_VEGETATION
    end
    
    if TERRAIN_MATERIAL_HASHES[materialHash] then
        if hitCoords and origin then
            local heightDiff = origin.z - hitCoords.z
            if heightDiff > 5.0 then
                return OCCLUSION_TYPE_TERRAIN
            end
        end
        return OCCLUSION_TYPE_TERRAIN
    end
    
    return OCCLUSION_TYPE_BUILDING
end

local function GetOcclusionConfig()
    local trackingCfg = Config and Config.Tracking
    local occ = trackingCfg and trackingCfg.Occlusion

    local defaults = {
        Enabled = true,
        CheckIntervalMs = 150,
        MaxOccludedMs = 2000,
        AcquireGraceMs = 0,
        RayRadius = 0.35,
        SampleHeights = OCCLUSION_DEFAULT_SAMPLE_HEIGHTS,
        CrosshairGraceMs = 0,
        CrosshairMaxAngleDeg = 0,
        TerrainAware = true,
        TerrainMaxOccludedMs = 0,
        BuildingMaxOccludedMs = 2500,
        VegetationIgnored = true
    }

    if not occ then
        return defaults
    end

    return {
        Enabled = occ.Enabled ~= false,
        CheckIntervalMs = occ.CheckIntervalMs or defaults.CheckIntervalMs,
        MaxOccludedMs = occ.MaxOccludedMs or defaults.MaxOccludedMs,
        AcquireGraceMs = occ.AcquireGraceMs or defaults.AcquireGraceMs,
        RayRadius = occ.RayRadius or defaults.RayRadius,
        SampleHeights = occ.SampleHeights or defaults.SampleHeights,
        CrosshairGraceMs = occ.CrosshairGraceMs or defaults.CrosshairGraceMs,
        CrosshairMaxAngleDeg = occ.CrosshairMaxAngleDeg or defaults.CrosshairMaxAngleDeg,
        TerrainAware = occ.TerrainAware ~= false,
        TerrainMaxOccludedMs = occ.TerrainMaxOccludedMs or defaults.TerrainMaxOccludedMs,
        BuildingMaxOccludedMs = occ.BuildingMaxOccludedMs or defaults.BuildingMaxOccludedMs,
        VegetationIgnored = occ.VegetationIgnored ~= false
    }
end

local function ResetOcclusionState()
    OcclusionState.lastCheckTime = 0
    OcclusionState.occludedSince = 0
    OcclusionState.occlusionType = nil
    OcclusionState.reacquiring = false
    OcclusionState.reacquireStartTime = 0
    Tracking.hasLOS = true
    Tracking.debug.losResult = nil
    Tracking.debug.losTargetPoint = nil
    Tracking.debug.losStats = nil
    Tracking.debug.occlusion = nil
end

local function NormalizeSampleHeights(sampleHeights)
    if type(sampleHeights) ~= "table" or #sampleHeights == 0 then
        return OCCLUSION_DEFAULT_SAMPLE_HEIGHTS
    end

    local normalized = {}
    for i = 1, #sampleHeights do
        local value = tonumber(sampleHeights[i])
        if value then
            normalized[#normalized + 1] = value
        end
    end

    if #normalized == 0 then
        return OCCLUSION_DEFAULT_SAMPLE_HEIGHTS
    end

    return normalized
end

local function BuildOcclusionSamplePoints(entity, sampleHeights)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return {}, nil
    end

    local heights = NormalizeSampleHeights(sampleHeights)
    local model = GetEntityModel(entity)
    local minDim, maxDim = GetModelDimensions(model)
    local height = maxDim.z - minDim.z

    if height <= 0.01 then
        local coords = GetEntityCoords(entity)
        return { coords }, coords
    end

    local points = {}
    for i = 1, #heights do
        local ratio = math_clamp(heights[i], 0.0, 1.0)
        local zOffset = minDim.z + height * ratio
        points[#points + 1] = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, zOffset)
    end

    local primaryPoint = points[1] or GetEntityTargetPoint(entity) or GetEntityCoords(entity)
    return points, primaryPoint
end

local function RaycastOcclusion(origin, targetPoint, radius, target, targetVehicle, settings)
    local handle = StartShapeTestCapsule(
        origin.x, origin.y, origin.z,
        targetPoint.x, targetPoint.y, targetPoint.z,
        radius,
        OCCLUSION_RAY_FLAGS,
        PolCam.CurrentVehicle,
        OCCLUSION_RAY_P9
    )

    local _, hit, hitCoords, surfaceNormal, materialHash, hitEntity = GetShapeTestResultIncludingMaterial(handle)

    if not hit then
        return true, { hit = hit, hitEntity = hitEntity, hitCoords = hitCoords, occlusionType = OCCLUSION_TYPE_NONE }
    end

    if hitEntity == nil or hitEntity == 0 then
        local occType = ClassifyHitMaterial(materialHash, nil, hitCoords, origin)
        
        if settings and settings.VegetationIgnored and occType == OCCLUSION_TYPE_VEGETATION then
            return true, { hit = hit, hitEntity = hitEntity, hitCoords = hitCoords, occlusionType = OCCLUSION_TYPE_VEGETATION, ignored = true }
        end
        
        return false, { hit = hit, hitEntity = hitEntity, hitCoords = hitCoords, occlusionType = occType, materialHash = materialHash }
    end

    -- Treat hits on target, target's vehicle, or our own helicopter as clear LOS
    local clear = (hitEntity == target) 
        or (targetVehicle ~= nil and hitEntity == targetVehicle)
        or (PolCam.CurrentVehicle ~= nil and hitEntity == PolCam.CurrentVehicle)
    
    if clear then
        return true, { hit = hit, hitEntity = hitEntity, hitCoords = hitCoords, occlusionType = OCCLUSION_TYPE_NONE }
    end
    
    local occType = ClassifyHitMaterial(materialHash, hitEntity, hitCoords, origin)
    
    if settings and settings.VegetationIgnored and occType == OCCLUSION_TYPE_VEGETATION then
        return true, { hit = hit, hitEntity = hitEntity, hitCoords = hitCoords, occlusionType = OCCLUSION_TYPE_VEGETATION, ignored = true }
    end
    
    return false, { hit = hit, hitEntity = hitEntity, hitCoords = hitCoords, occlusionType = occType, materialHash = materialHash }
end

local function HasCameraLineOfSight(target, settings)
    if not target or not DoesEntityExist(target) then return true, nil, OCCLUSION_TYPE_NONE end

    local origin = GetOcclusionOrigin()
    if not origin then return true, nil, OCCLUSION_TYPE_NONE end

    local targetVehicle = nil
    if IsEntityAPed(target) and IsPedInAnyVehicle(target, false) then
        targetVehicle = GetVehiclePedIsIn(target, false)
    end

    local normalizedHeights = NormalizeSampleHeights(settings.SampleHeights)
    local samplePoints, primaryPoint = BuildOcclusionSamplePoints(target, normalizedHeights)
    if #samplePoints == 0 then
        primaryPoint = GetEntityTargetPoint(target) or GetEntityCoords(target)
        samplePoints = { primaryPoint }
    end

    Tracking.debug.losTargetPoint = primaryPoint

    local samples = {}
    local hasLOS = false
    local clearCount = 0
    local blockedCount = 0
    local worstOcclusionType = OCCLUSION_TYPE_NONE
    local occlusionPriority = { [OCCLUSION_TYPE_NONE] = 0, [OCCLUSION_TYPE_VEGETATION] = 1, [OCCLUSION_TYPE_BUILDING] = 2, [OCCLUSION_TYPE_TERRAIN] = 3 }

    for i = 1, #samplePoints do
        local point = samplePoints[i]
        local clear, rayInfo = RaycastOcclusion(origin, point, settings.RayRadius, target, targetVehicle, settings)
        samples[#samples + 1] = {
            point = point,
            ray = rayInfo,
            clear = clear
        }
        if clear then
            hasLOS = true
            clearCount = clearCount + 1
        else
            blockedCount = blockedCount + 1
            local occType = rayInfo.occlusionType or OCCLUSION_TYPE_BUILDING
            if occlusionPriority[occType] > occlusionPriority[worstOcclusionType] then
                worstOcclusionType = occType
            end
        end
    end

    Tracking.debug.losStats = {
        sampleCount = #samplePoints,
        clearCount = clearCount,
        blockedCount = blockedCount,
        rayRadius = settings.RayRadius,
        sampleHeights = normalizedHeights
    }

    Tracking.debug.losResult = {
        origin = origin,
        targetVehicle = targetVehicle,
        samples = samples,
        hasLOS = hasLOS,
        occlusionType = worstOcclusionType
    }

    return hasLOS, primaryPoint, worstOcclusionType
end

local function IsTargetWithinCrosshair(targetPoint, maxAngleDeg)
    if not targetPoint or maxAngleDeg <= 0 then return false end

    local camPos = GetCameraPosition()
    local camDir = GetCameraDirection()
    if not camPos or not camDir then return false end

    local toTarget = Normalize(targetPoint - camPos)
    local dot = (camDir.x * toTarget.x) + (camDir.y * toTarget.y) + (camDir.z * toTarget.z)
    local clamped = math_clamp(dot, -1.0, 1.0)
    local angleDeg = math_deg(math_acos(clamped))
    return angleDeg <= maxAngleDeg
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
    local screenScore = math_clamp(1 - (perp / denom), 0.0, 1.0)

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
    local score = (screenScore * 1.0) + (typeScore * 0.2) + (sizeScore * 0.1) + prevScore - distPenalty
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

    local radius = math_max(baseRadius, distanceToLookPoint * radiusScaling)
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

    local probeRadius = math_max(baseRadius * 0.6, radius * 0.35)
    local offsetDistance = math_max(baseRadius * 1.2, radius * 0.35)

    local probes = {
        { label = "center", offset = vector3(0.0, 0.0, 0.0) },
        { label = "top", offset = camUp * offsetDistance },
        { label = "bottom", offset = camUp * -offsetDistance },
        { label = "left", offset = camRight * -offsetDistance },
        { label = "right", offset = camRight * offsetDistance }
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

    if not bestEntity or not best then
        Tracking.debug.scanSource = "none"
        SendNUIMessage({ action = "noPotentialTarget" })
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
    ResetOcclusionState()
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

local function SetReacquirePulse(active)
    if lastReacquireUiState == active then return end
    lastReacquireUiState = active
    SendNUIMessage({ action = "reacquirePulse", active = active })
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

    PolCam.LockedTarget = nil
    PolCam.LockedTargetType = nil
    PolCam.TargetInfo = nil
    PersistentTracking.Active = false

    ResetTrackingState()
    ClearHeliTrackingState()
    SetReacquirePulse(false)

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

    ResetOcclusionState()
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

-- Active Tracking Update
local function UpdateActiveTracking(now)
    if not PolCam.LockedTarget or not DoesEntityExist(PolCam.LockedTarget) then
        ClearLock()
        PlayPolCamSound("TargetLost")
        return
    end

    local occ = GetOcclusionConfig()

    if occ.Enabled and (PolCam.Active or PersistentTracking.Active) then
        if occ.AcquireGraceMs and occ.AcquireGraceMs > 0 and Tracking.lockStartTime and Tracking.lockStartTime > 0 then
            if (now - Tracking.lockStartTime) < occ.AcquireGraceMs then
                Tracking.hasLOS = true
                OcclusionState.occludedSince = 0
                OcclusionState.occlusionType = nil
                OcclusionState.lastCheckTime = 0
                UpdateLockedTargetInfo()
                return
            end
        end

        local checkInterval = occ.CheckIntervalMs
        if not PolCam.Active and PersistentTracking.Active and OcclusionState.occludedSince ~= 0 then
            checkInterval = 0
        end
        local shouldCheck = (OcclusionState.lastCheckTime == 0) or (now - OcclusionState.lastCheckTime >= checkInterval)
        if shouldCheck then
            OcclusionState.lastCheckTime = now

            local hasLOS, targetPoint, occlusionType = HasCameraLineOfSight(PolCam.LockedTarget, occ)
            Tracking.hasLOS = hasLOS

            local maxOccluded = occ.MaxOccludedMs
            local extraGrace = 0
            local crosshairOk = false
            local ignoreOcclusion = false
            local shouldClear = false

            if hasLOS then
                OcclusionState.occludedSince = 0
                OcclusionState.occlusionType = nil
                OcclusionState.reacquiring = false
                OcclusionState.reacquireStartTime = 0
            else
                if OcclusionState.occludedSince == 0 then
                    OcclusionState.occludedSince = now
                    OcclusionState.occlusionType = occlusionType
                else
                    if occlusionType and OcclusionState.occlusionType then
                        local priority = { [OCCLUSION_TYPE_NONE] = 0, [OCCLUSION_TYPE_VEGETATION] = 1, [OCCLUSION_TYPE_BUILDING] = 2, [OCCLUSION_TYPE_TERRAIN] = 3 }
                        if priority[occlusionType] > priority[OcclusionState.occlusionType] then
                            OcclusionState.occlusionType = occlusionType
                        end
                    end
                end

                if occ.TerrainAware and OcclusionState.occlusionType then
                    if OcclusionState.occlusionType == OCCLUSION_TYPE_TERRAIN then
                        maxOccluded = occ.TerrainMaxOccludedMs or 0
                    elseif OcclusionState.occlusionType == OCCLUSION_TYPE_BUILDING then
                        maxOccluded = occ.BuildingMaxOccludedMs or occ.MaxOccludedMs
                    elseif OcclusionState.occlusionType == OCCLUSION_TYPE_VEGETATION then
                        if occ.VegetationIgnored then
                            OcclusionState.occludedSince = 0
                            OcclusionState.occlusionType = nil
                            OcclusionState.reacquiring = false
                            OcclusionState.reacquireStartTime = 0
                            ignoreOcclusion = true
                        end
                    end
                end

                if occ.CrosshairGraceMs and occ.CrosshairGraceMs > 0 and occ.CrosshairMaxAngleDeg and occ.CrosshairMaxAngleDeg > 0 then
                    if targetPoint and IsTargetWithinCrosshair(targetPoint, occ.CrosshairMaxAngleDeg) then
                        extraGrace = occ.CrosshairGraceMs
                        crosshairOk = true
                    end
                end

                maxOccluded = maxOccluded + extraGrace

                -- Baked-in reacquisition: instead of clearing immediately, enter reacquisition phase
                local REACQUIRE_GRACE_MS = 3000 -- 3 seconds of reacquisition attempts
                
                if (now - OcclusionState.occludedSince) >= maxOccluded then
                    -- Time to enter or continue reacquisition phase
                    if not OcclusionState.reacquiring then
                        OcclusionState.reacquiring = true
                        OcclusionState.reacquireStartTime = now
                        if shouldLogEvents() then
                            print('[PolCam] Entering reacquisition phase')
                        end
                    end
                    
                    -- Check if reacquisition grace period also expired
                    if (now - OcclusionState.reacquireStartTime) >= REACQUIRE_GRACE_MS then
                        shouldClear = true
                        if shouldLogEvents() then
                            print('[PolCam] Reacquisition failed - clearing lock')
                        end
                    end
                end
            end

            local occludedMs = 0
            if OcclusionState.occludedSince ~= 0 then
                occludedMs = now - OcclusionState.occludedSince
            end
            
            local reacquireMs = 0
            if OcclusionState.reacquiring and OcclusionState.reacquireStartTime > 0 then
                reacquireMs = now - OcclusionState.reacquireStartTime
            end

            local occlusionTypeFinal = OcclusionState.occlusionType or occlusionType or OCCLUSION_TYPE_NONE
            Tracking.debug.losTargetPoint = targetPoint
            Tracking.debug.occlusion = {
                hasLOS = Tracking.hasLOS,
                occlusionType = occlusionTypeFinal,
                occludedMs = occludedMs,
                maxOccludedMs = maxOccluded,
                extraGraceMs = extraGrace,
                crosshairOk = crosshairOk,
                lastCheckTime = OcclusionState.lastCheckTime,
                ignored = ignoreOcclusion,
                reacquiring = OcclusionState.reacquiring,
                reacquireMs = reacquireMs
            }

            SetReacquirePulse(OcclusionState.reacquiring)

            if shouldLogEvents() then
                if lastLosLogHasLOS ~= Tracking.hasLOS or lastLosLogOccType ~= occlusionTypeFinal then
                    print(('[PolCam] LOS=%s occ=%s occludedMs=%d maxMs=%d extra=%d crosshair=%s reacquiring=%s'):format(
                        tostring(Tracking.hasLOS),
                        tostring(occlusionTypeFinal),
                        tonumber(occludedMs) or 0,
                        tonumber(maxOccluded) or 0,
                        tonumber(extraGrace) or 0,
                        tostring(crosshairOk),
                        tostring(OcclusionState.reacquiring)
                    ))
                    lastLosLogHasLOS = Tracking.hasLOS
                    lastLosLogOccType = occlusionTypeFinal
                end
            end

            if ignoreOcclusion then
                UpdateLockedTargetInfo()
                return
            end

            if shouldClear then
                SetReacquirePulse(false)
                ClearLock()
                PlayPolCamSound("TargetLost")
                return
            end
        end
    else
        SetReacquirePulse(false)
        ResetOcclusionState()
    end

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

local function DrawWorldTargetLabel()
    local cfg = Config.UI and Config.UI.TargetLabel
    if not ShouldDrawTargetLabel(cfg) then return end

    local target = PolCam.LockedTarget
    local info = PolCam.TargetInfo
    if not target or not info or not info.coords then return end

    local camCoords = PolCam.Active and PolCam.CameraCoords or GetEntityCoords(PlayerPedId())
    if not camCoords then return end

    local distance = info.distance or #(camCoords - info.coords)
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
    local t = 1 - math_exp(-smoothingSpeed * dt)
    local smoothedDistance = Tracking.labelSmoothedDistance or distance
    smoothedDistance = smoothedDistance + (distance - smoothedDistance) * t
    Tracking.labelSmoothedDistance = smoothedDistance

    local zOffset = cfg.HeightOffsetVehicle or 1.6
    if info.type == "ped" then
        zOffset = cfg.HeightOffsetPed or 1.0
    end

    local pos = info.coords + vector3(0.0, 0.0, zOffset)

    local scale = 0.35
    if distance and distance > 0.0 then
        scale = math_clamp(1.2 / distance, 0.25, 0.5)
    end

    local text = string_format("TRACK %d M", math_floor(smoothedDistance + 0.5))

    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextScale(scale, scale)
    SetTextColour(0, 255, 0, 230)
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
        hasLOS = Tracking.hasLOS
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
