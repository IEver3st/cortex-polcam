--[[
    PolCam - Main Client Script
    Core state management and initialization
]]

-- ============================================================================
-- NATIVE CACHING (Performance Optimization)
-- ============================================================================
local PlayerPedId = PlayerPedId
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetVehicleClass = GetVehicleClass
local GetEntityModel = GetEntityModel
local GetHashKey = GetHashKey
local GetPedInVehicleSeat = GetPedInVehicleSeat
local DoesEntityExist = DoesEntityExist
local GetEntityCoords = GetEntityCoords
local GetEntitySpeed = GetEntitySpeed
local GetEntityHeading = GetEntityHeading
local GetGameTimer = GetGameTimer
local GetGroundZFor_3dCoord = GetGroundZFor_3dCoord
local GetStreetNameAtCoord = GetStreetNameAtCoord
local GetStreetNameFromHashKey = GetStreetNameFromHashKey
local GetCamMatrix = GetCamMatrix
local GetEntityHeightAboveGround = GetEntityHeightAboveGround
local Wait = Wait
local CreateThread = CreateThread
local DisableControlAction = DisableControlAction
local DisplayRadar = DisplayRadar
local SendNUIMessage = SendNUIMessage
local IsControlPressed = IsControlPressed
local IsControlPressed = IsControlPressed
local IsControlJustPressed = IsControlJustPressed
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked

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

local DoesCamExist = DoesCamExist
local SetCamRot = SetCamRot
local SetCamFov = SetCamFov
local floor = math.floor
local abs = math.abs
local atan = math.atan
local acos = math.acos
local deg = math.deg
local max = math.max
local min = math.min
local sqrt = math.sqrt
local format = string.format

-- ============================================================================
-- NOTIFICATIONS (es_lib / ox_lib)
-- ============================================================================
local function getNotifyPreference()
    if type(Config) ~= 'table' or type(Config.Lib) ~= 'table' then return 'auto' end
    local pref = Config.Lib.Notify
    if type(pref) ~= 'string' then return 'auto' end
    pref = string.lower(pref)
    if pref == 'auto' or pref == 'es_lib' or pref == 'ox_lib' or pref == 'none' then
        return pref
    end
    return 'auto'
end

local function isResourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function getNotifyBackend()
    local pref = getNotifyPreference()

    local esReady = (pref == 'es_lib' or pref == 'auto')
        and isResourceStarted('es_lib')
        and type(exports) == 'table'
        and exports.es_lib
        and exports.es_lib.notify

    if esReady then return 'es_lib' end

    local oxReady = (pref == 'ox_lib' or pref == 'auto')
        and isResourceStarted('ox_lib')
        and type(exports) == 'table'
        and exports.ox_lib
        and exports.ox_lib.notify

    if oxReady then return 'ox_lib' end

    return 'none'
end

function PolCamNotify(notifyType, message)
    local backend = getNotifyBackend()

    if backend == 'es_lib' then
        exports.es_lib:notify({
            type = notifyType or 'inform',
            description = message or '',
            position = 'top-right',
            duration = 3500
        })
        return
    end

    if backend == 'ox_lib' then
        exports.ox_lib:notify({
            type = notifyType or 'inform',
            description = message or '',
            position = 'top-right',
            duration = 3500
        })
        return
    end

    if Config and Config.Debug and Config.Debug.Enabled then
        print("[PolCam Notify] " .. tostring(notifyType) .. ": " .. tostring(message))
    end
end

-- ============================================================================
-- ES_HUD INTEGRATION
-- ============================================================================
local esHudAvailable = false
local esHudChecked = false
local esHudHidden = false

local function checkEsHudAvailable()
    if esHudChecked then return esHudAvailable end
    esHudChecked = true
    
    if not Config.EsHud or not Config.EsHud.Enabled then
        esHudAvailable = false
        return false
    end
    
    if Config.EsHud.AutoDetect then
        esHudAvailable = isResourceStarted('es_hud')
            and type(exports) == 'table'
            and exports.es_hud
    else
        esHudAvailable = true
    end
    
    if Config.Debug and Config.Debug.Enabled then
        print("[PolCam] ES_HUD available: " .. tostring(esHudAvailable))
    end
    
    return esHudAvailable
end

local function hideEsHud()
    if not checkEsHudAvailable() then return end
    if esHudHidden then return end
    
    local success = pcall(function()
        exports.es_hud:hideHud('polcam')
    end)
    
    if success then
        esHudHidden = true
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] ES_HUD hidden")
        end
    end
end

local function showEsHud()
    if not checkEsHudAvailable() then return end
    if not esHudHidden then return end
    
    local success = pcall(function()
        exports.es_hud:showHud('polcam')
    end)
    
    if success then
        esHudHidden = false
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] ES_HUD shown")
        end
    end
end

local function setEsHudForceAircraftHud(enabled)
    if not checkEsHudAvailable() then return false end
    if not Config.EsHud.ShowAircraftHudForPilot then return false end
    
    local success = pcall(function()
        exports.es_hud:setForceAircraftHud(enabled)
    end)
    
    if Config.Debug and Config.Debug.Enabled then
        print("[PolCam] ES_HUD setForceAircraftHud: " .. tostring(enabled) .. " (success: " .. tostring(success) .. ")")
    end
    
    return success
end

local function isPilot()
    return PolCam.Seat == -1
end

local function shouldShowFallbackAircraftHud()
    if not Config.EsHud or not Config.EsHud.FallbackAircraftHud then
        return false
    end
    return isPilot() and not checkEsHudAvailable()
end

local GetVehicleBodyHealth = GetVehicleBodyHealth
local GetVehicleEngineHealth = GetVehicleEngineHealth
local GetVehicleFuelLevel = GetVehicleFuelLevel
local IsVehicleEngineOn = IsVehicleEngineOn
local GetLandingGearState = GetLandingGearState
local GetVehicleHeliMainRotorHealth = GetVehicleHeliMainRotorHealth
local GetVehicleHeliTailRotorHealth = GetVehicleHeliTailRotorHealth

local function collectAircraftData(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return nil
    end
    
    local coords = GetEntityCoords(vehicle)
    local speed = GetEntitySpeed(vehicle)
    local heading = GetEntityHeading(vehicle)
    
    local altitudeFeet = coords.z * 3.28084
    local airspeedKnots = speed * 1.94384
    
    local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 100.0, false)
    local altitudeAgl = (coords.z - (groundZ or 0)) * 3.28084
    if altitudeAgl < 0 then altitudeAgl = 0 end
    
    local mainRotorHealth = GetVehicleHeliMainRotorHealth(vehicle)
    local tailRotorHealth = GetVehicleHeliTailRotorHealth(vehicle)
    local fuel = GetVehicleFuelLevel(vehicle)
    
    local gearState = GetLandingGearState(vehicle)
    local gearDown = gearState == 0 or gearState == 1
    
    return {
        visible = true,
        altitude = altitudeFeet,
        altitudeAgl = altitudeAgl,
        airspeed = airspeedKnots,
        heading = heading,
        fuel = fuel,
        mainRotorHealth = mainRotorHealth,
        tailRotorHealth = tailRotorHealth,
        gearDown = gearDown
    }
end

local function updateFallbackAircraftHud()
    if not shouldShowFallbackAircraftHud() then
        SendNUIMessage({
            action = "hideAircraftHUD"
        })
        return
    end
    
    local vehicle = PolCam.CurrentVehicle
    local data = collectAircraftData(vehicle)
    
    if data then
        SendNUIMessage({
            action = "updateAircraftHUD",
            data = data
        })
    end
end

-- ============================================================================
-- STATE VARIABLES
-- ============================================================================
Config = Config or {}
Config.Camera = Config.Camera or {}
Config.Vision = Config.Vision or {}
Config.Keybinds = Config.Keybinds or {}
Config.Lib = Config.Lib or {}
Config.EsHud = Config.EsHud or {}

-- Expose notification helper for other modules
_G.PolCamNotify = PolCamNotify

PolCam = {
    -- Core state

    Active = false,
    Camera = nil,
    Scaleform = nil,
    
    -- Camera state
    Heading = 0.0,
    Pitch = -15.0,
    Zoom = Config.Camera.DefaultZoom or 5.0,
    TargetZoom = Config.Camera.DefaultZoom or 5.0,
    FOV = Config.Camera.DefaultFOV or 50.0,
    
    -- Vision mode: "normal", "nightvision", "thermal"
    VisionMode = Config.Vision.DefaultMode or "normal",
    
    -- Tracking
    LockedTarget = nil,
    LockedTargetType = nil,
    TargetInfo = nil,
    LockKeyHeld = false,
    
    -- Ground lock (for crime scenes)
    GroundLockPoint = nil,
    
    -- UI
    UIVisible = true,
    
    -- Position data
    CameraCoords = vector3(0, 0, 0),
    GroundCoords = vector3(0, 0, 0),
    
    -- Helicopter reference
    CurrentVehicle = nil,
    LastHeliZ = 0.0,
    LastHeliTime = 0,
    DebugState = {
        lastCameraStateSync = 0,
        lastCameraStateReceive = 0,
        lastCameraStateVehicle = nil,
        lastSharedStateVehicle = nil,
        lastCameraStatePayload = nil,
        lastSharedStatePayload = nil,
        lastCameraStateSyncCount = 0,
        lastCameraStateReceiveCount = 0,
        lastCameraStateLog = 0
    }
}

-- ============================================================================
-- KEY BINDINGS
-- ============================================================================
local function RegisterKeybinds()
    -- Toggle Camera
    RegisterKeyMapping('polcam_toggle', 'PolCam: Toggle Camera', 'keyboard', Config.Keybinds.ToggleCamera)
    RegisterCommand('polcam_toggle', function()
        TogglePolCam()
    end, false)
    
    -- Lock Target (hold-to-lock supported via +/− commands)
    RegisterKeyMapping('+polcam_lock', 'PolCam: Hold to Lock/Unlock Target', 'keyboard', Config.Keybinds.LockTarget)

    RegisterCommand('+polcam_lock', function()
        if PolCam and PolCam.Active then
            PolCam.LockKeyHeld = true
            StartLocking()
        end
    end, false)

    RegisterCommand('-polcam_lock', function()
        if PolCam then
            PolCam.LockKeyHeld = false
        end
    end, false)
    
    -- Cycle Vision
    RegisterKeyMapping('polcam_vision', 'PolCam: Cycle Vision Mode', 'keyboard', Config.Keybinds.CycleVision)
    RegisterCommand('polcam_vision', function()
        if PolCam.Active then
            CycleVisionMode()
        end
    end, false)
    
    -- Place Marker
    RegisterKeyMapping('polcam_marker', 'PolCam: Place Marker', 'keyboard', Config.Keybinds.PlaceMarker)
    RegisterCommand('polcam_marker', function()
        if PolCam.Active then
            PlaceMarker()
        end
    end, false)
    
    -- Delete Last Marker
    RegisterKeyMapping('polcam_delete_marker', 'PolCam: Delete Last Marker', 'keyboard', Config.Keybinds.DeleteMarker or "DELETE")
    RegisterCommand('polcam_delete_marker', function()
        if PolCam.Active then
            DeleteLastMarker()
        end
    end, false)
    
    -- Toggle UI
    RegisterKeyMapping('polcam_ui', 'PolCam: Toggle UI', 'keyboard', Config.Keybinds.ToggleUI)
    RegisterCommand('polcam_ui', function()
        if PolCam.Active then
            ToggleUI()
        end
    end, false)
    
    -- Spotlight
    if Config.Spotlight and Config.Spotlight.Enabled then
        RegisterKeyMapping('polcam_spotlight', 'PolCam: Toggle Spotlight', 'keyboard', Config.Keybinds.Spotlight)
        RegisterCommand('polcam_spotlight', function()
            if PolCam.Active and ToggleSpotlight then
                ToggleSpotlight()
            end
        end, false)
    end
    
    -- Hover Mode (pilot only)
    if Config.HeliControl and Config.HeliControl.HoverEnabled then
        RegisterKeyMapping('polcam_hover', 'PolCam: Toggle Hover Mode', 'keyboard', Config.Keybinds.ToggleHover)
        RegisterCommand('polcam_hover', function()
            if ToggleHoverMode then
                ToggleHoverMode()
            end
        end, false)
        RegisterCommand('hover', function(source, args)
            if SetHoverAltitude and args[1] then
                local alt = tonumber(args[1])
                if alt then
                    SetHoverAltitude(alt)
                else
                    print("Usage: /hover [altitude_ft]")
                end
            else
                if ToggleHoverMode then
                    ToggleHoverMode()
                end
            end
        end, false)
        RegisterCommand('hover_off', function()
            if HeliControl and HeliControl.HoverMode and DeactivateHover then
                DeactivateHover()
            end
        end, false)
    end
    
    -- Orbit Mode (pilot only)
    if Config.HeliControl and Config.HeliControl.OrbitEnabled then
        RegisterKeyMapping('polcam_orbit', 'PolCam: Toggle Orbit Mode', 'keyboard', Config.Keybinds.ToggleOrbit)
        RegisterCommand('polcam_orbit', function()
            if PolCam.Active and ToggleOrbitMode then
                ToggleOrbitMode()
            end
        end, false)
    end
    
    -- Street Overlay Toggle
    RegisterKeyMapping('polcam_streets', 'PolCam: Toggle Street Names', 'keyboard', Config.Keybinds.ToggleStreets or "N")
    RegisterCommand('polcam_streets', function()
        if PolCam.Active and ToggleStreetOverlay then
            ToggleStreetOverlay()
        end
    end, false)

    -- HUD Edit Command
    RegisterCommand('hudedit', function()
        if IsInAllowedHelicopter() then
            ToggleHUDEdit()
        end
    end, false)
    
    -- Ground Lock (for crime scenes)
    RegisterKeyMapping('polcam_groundlock', 'PolCam: Lock Camera to Ground', 'keyboard', Config.Keybinds.GroundLock or "T")
    RegisterCommand('polcam_groundlock', function()
        if PolCam.Active and ToggleGroundLock then
            ToggleGroundLock()
        end
    end, false)

    -- Debug menu (only if enabled in settings AND es_lib is present)
    if Config and Config.Debug and Config.Debug.ToolsEnabled then
        local esStarted = GetResourceState('es_lib') == 'started'
        if not esStarted then
            -- Requirement: if es_lib isn't installed/running, disable all PolCam debug features.
            Config.Debug.Enabled = false
            Config.Debug.ShowDebugPanel = false
            Config.Debug.LogEvents = false
            Config.Debug.LogScans = false
        else
            RegisterKeyMapping('polcam_debug', 'PolCam: Debug Tools', 'keyboard', Config.Keybinds.ToggleDebug or "F10")
            RegisterCommand('polcam_debug', function()
                if type(OpenPolCamDebugMenu) == 'function' then
                    OpenPolCamDebugMenu()
                end
            end, false)
        end
    end
end

-- ============================================================================
-- HUD EDITING & PERSISTENCE
-- ============================================================================
local hudEditing = false

function ToggleHUDEdit()
    hudEditing = not hudEditing
    
    if hudEditing then
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "startEditing"
        })
        PolCamNotify('inform', 'HUD Edit Mode: Drag elements to reposition. Close with /hudedit')
    else
        SetNuiFocus(false, false)
        SendNUIMessage({
            action = "stopEditing"
        })
    end
end

RegisterNUICallback('saveHUDPosition', function(data, cb)
    if not data or not data.id then return cb('ok') end
    
    local key = string.format("polcam_hud_%s", data.id)
    local posData = json.encode({x = data.x, y = data.y})
    
    SetResourceKvp(key, posData)
    cb('ok')
end)

function GetSavedHUDPositions()
    local positions = {}
    local elements = {
        "top-left", "top-right", "bottom-left", "bottom-right", 
        "compass", "gimbal", "crosshair", "pilot-hud", "passenger-hud"
    }
    
    for _, id in ipairs(elements) do
        local key = string.format("polcam_hud_%s", id)
        local data = GetResourceKvpString(key)
        if data then
            positions[id] = json.decode(data)
        end
    end
    
    return positions
end

-- ============================================================================
-- HELICOPTER VALIDATION
-- ============================================================================
-- Pre-cache allowed helicopter hashes for O(1) lookup
local AllowedHeliHashes = {}
local AllowedSeatLookup = {}
local HeliHashesCached = false

local function CacheHelicopterHashes()
    if HeliHashesCached then return end
    for _, modelName in ipairs(Config.AllowedHelicopters or {}) do
        AllowedHeliHashes[GetHashKey(modelName)] = true
    end
    for _, seat in ipairs(Config.AllowedSeats or {}) do
        AllowedSeatLookup[seat] = true
    end
    HeliHashesCached = true
end

function IsInAllowedHelicopter()
    CacheHelicopterHashes()
    
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle == 0 then return false end
    
    -- Check if it's a helicopter (class 15)
    if GetVehicleClass(vehicle) ~= 15 then return false end
    
    -- Check if model is allowed (O(1) hash lookup)
    local model = GetEntityModel(vehicle)
    if not AllowedHeliHashes[model] then return false end
    
    -- Check seat (O(1) lookup)
    local seat = -2
    for i = -1, 3 do
        if GetPedInVehicleSeat(vehicle, i) == ped then
            seat = i
            break
        end
    end

    if seat == -2 then
        return false
    end

    if not AllowedSeatLookup[seat] then
        return false
    end

    PolCam.CurrentVehicle = vehicle
    PolCam.Seat = seat
    return true
end

function UpdateHUDContext()
    local inHeli = IsInAllowedHelicopter()
    local seat = PolCam.Seat
    local role = "none"
    
    if inHeli then
        if seat == -1 then
            role = "pilot"
        else
            role = "passenger"
        end
    end
    
    SendNUIMessage({
        action = "updateContext",
        data = {
            inHeli = inHeli,
            role = role,
            seat = seat,
            positions = GetSavedHUDPositions()
        }
    })
end

CreateThread(function()
    local lastInHeli = false
    local lastSeat = -2
    
    while true do
        local inHeli = IsInAllowedHelicopter()
        local seat = PolCam.Seat or -2
        
        if inHeli ~= lastInHeli or seat ~= lastSeat then
            lastInHeli = inHeli
            lastSeat = seat
            UpdateHUDContext()
        end
        
        Wait(2000)
    end
end)

-- ============================================================================
-- CAMERA TOGGLE
-- ============================================================================
local _pendingCameraClaim = false
local _claimStartTime = 0
local _CLAIM_TIMEOUT_MS = 5000

local function GetCurrentVehicleNetId()
    if not PolCam.CurrentVehicle or PolCam.CurrentVehicle == 0 then return nil end
    if not DoesEntityExist(PolCam.CurrentVehicle) then return nil end
    return NetworkGetNetworkIdFromEntity(PolCam.CurrentVehicle)
end

local function ResetCameraClaim()
    _pendingCameraClaim = false
    _claimStartTime = 0
end

local function RequestCameraClaim(vehicleNetId)
    if _pendingCameraClaim then
        local now = GetGameTimer()
        if (now - _claimStartTime) >= _CLAIM_TIMEOUT_MS then
            ResetCameraClaim()
        else
            return
        end
    end
    if not vehicleNetId then return end
    _pendingCameraClaim = true
    _claimStartTime = GetGameTimer()
    TriggerServerEvent('polcam:cameraClaim', vehicleNetId)
end

local function ReleaseCameraClaim()
    local vehicleNetId = GetCurrentVehicleNetId()
    if not vehicleNetId then return end
    TriggerServerEvent('polcam:cameraRelease', vehicleNetId)
end

RegisterNetEvent('polcam:cameraClaimResult')
AddEventHandler('polcam:cameraClaimResult', function(allowed, ownerServerId)
    ResetCameraClaim()
    if allowed then
            -- Request shared camera state before activating
            local vehicleNetId = GetCurrentVehicleNetId()
            if vehicleNetId then
                TriggerServerEvent('polcam:requestCameraState', vehicleNetId)
                -- Also request tracking state for full sync.
                TriggerServerEvent('polcam:trackingRequestState', vehicleNetId)
                -- The activation will happen in the receiveCameraState handler
            else
                ActivatePolCam(true, nil)
            end
            return
        end


    local msg = "Camera already in use."
    if ownerServerId and tonumber(ownerServerId) then
        msg = msg .. " (User ID: " .. tostring(ownerServerId) .. ")"
    end
    PolCamNotify('error', msg)
end)

-- ============================================================================
-- SHARED CAMERA STATE HANDLING
-- ============================================================================
local _pendingSharedState = nil  -- Temporarily stores received state until camera activates
local _lastStateSyncTime = 0
local STATE_SYNC_INTERVAL = (Config.Intervals and Config.Intervals.StateSync) or 200  -- ms between state syncs to server

RegisterNetEvent('polcam:receiveCameraState')
AddEventHandler('polcam:receiveCameraState', function(vehicleNetId, state)
    -- Store the state and activate with it
    _pendingSharedState = state

    if PolCam and PolCam.DebugState then
        local now = GetGameTimer()
        PolCam.DebugState.lastCameraStateReceive = now
        PolCam.DebugState.lastSharedStateVehicle = vehicleNetId
        PolCam.DebugState.lastSharedStatePayload = state
        PolCam.DebugState.lastCameraStateReceiveCount = (PolCam.DebugState.lastCameraStateReceiveCount or 0) + 1
    end

    if Config and Config.Debug and Config.Debug.LogEvents then
        print(('[PolCam] receiveCameraState vehicle=%s hasState=%s'):format(tostring(vehicleNetId), tostring(state ~= nil)))
    end

    -- Ensure we also pull the latest tracking state for this heli.
    if vehicleNetId then
        TriggerServerEvent('polcam:trackingRequestState', vehicleNetId)
    end

    ActivatePolCam(true, state)
end)

-- Apply shared camera state from another operator
function ApplySharedCameraState(state)
    if not state then return end
    
    -- Check if shared camera is enabled
    if not Config.SharedCamera or not Config.SharedCamera.Enabled then return end
    
    -- Apply camera orientation
    if state.heading then
        PolCam.Heading = state.heading
    end
    if state.pitch then
        PolCam.Pitch = state.pitch
    end
    if state.zoom then
        PolCam.Zoom = state.zoom
        PolCam.TargetZoom = state.targetZoom or state.zoom
        PolCam.FOV = CalculateFOV(PolCam.Zoom)
    end
    
    -- Apply vision mode (if enabled in config)
    if state.visionMode and SetVisionMode then
        if Config.SharedCamera.RestoreVisionMode ~= false then
            PolCam.VisionMode = state.visionMode
            SetVisionMode(state.visionMode)
        end
    end
    
    -- Apply ground lock point (if enabled in config)
    if state.groundLockPoint then
        if Config.SharedCamera.RestoreGroundLock ~= false then
            PolCam.GroundLockPoint = vector3(
                state.groundLockPoint.x,
                state.groundLockPoint.y,
                state.groundLockPoint.z
            )
            -- Update NUI to show ground lock is active
            SendNUIMessage({ action = "groundLockOn" })
        end
    end
    
    -- Try to restore locked target if it's still valid (if enabled in config)
    if state.lockedTargetNetId and state.lockedTargetType and not (PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget)) then
        if Config.SharedCamera.RestoreTrackedTarget ~= false then
            local entity = NetworkGetEntityFromNetworkId(state.lockedTargetNetId)
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                PolCam.LockedTarget = entity
                PolCam.LockedTargetType = state.lockedTargetType
                PolCam.TargetInfo = GetTargetInfo and GetTargetInfo(entity, state.lockedTargetType) or nil
                
                -- Notify targeting system
                if PlayPolCamSound then
                    PlayPolCamSound("TargetLocked")
                end
                
                SendNUIMessage({
                    action = "targetLocked",
                    info = PolCam.TargetInfo
                })
                
                -- NOTE: We no longer need to re-sync tracking to the server here.
                -- With per-helicopter tracking, the server already has the tracking state
                -- in HeliTracking[vehicleNetId], and the polcam:heliTrackingState event
                -- will sync all occupants automatically.
                
                if Config.Debug and Config.Debug.Enabled then
                    print("[PolCam] Restored locked target from shared state: " .. tostring(state.lockedTargetType))
                end
            end
        end
    end
    
    if Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Applied shared camera state - Heading: " .. tostring(state.heading) .. ", Pitch: " .. tostring(state.pitch))
    end
end

-- Build current camera state for syncing
function BuildCameraState()
    local state = {
        heading = PolCam.Heading,
        pitch = PolCam.Pitch,
        zoom = PolCam.Zoom,
        targetZoom = PolCam.TargetZoom,
        visionMode = PolCam.VisionMode
    }
    
    -- Include ground lock point if active
    if PolCam.GroundLockPoint then
        state.groundLockPoint = {
            x = PolCam.GroundLockPoint.x,
            y = PolCam.GroundLockPoint.y,
            z = PolCam.GroundLockPoint.z
        }
    end
    
    -- Include locked target if tracking something
    if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        local netId = SafeGetNetworkId(PolCam.LockedTarget)
        if netId then
            state.lockedTargetNetId = netId
            state.lockedTargetType = PolCam.LockedTargetType
        end
    end
    
    return state
end

-- Continuous camera state sync loop
function CameraStateSyncLoop()
    -- Check if shared camera is enabled
    if not Config.SharedCamera or not Config.SharedCamera.Enabled then return end
    
    local syncInterval = Config.SharedCamera.SyncIntervalMs or STATE_SYNC_INTERVAL
    
    while PolCam.Active do
        local now = GetGameTimer()
        if (now - _lastStateSyncTime) >= syncInterval then
            _lastStateSyncTime = now
            
            local vehicleNetId = GetCurrentVehicleNetId()
            if vehicleNetId then
                local state = BuildCameraState()
                TriggerServerEvent('polcam:cameraStateSync', vehicleNetId, state)

                if PolCam and PolCam.DebugState then
                    PolCam.DebugState.lastCameraStateSync = now
                    PolCam.DebugState.lastCameraStateVehicle = vehicleNetId
                    PolCam.DebugState.lastCameraStatePayload = state
                    PolCam.DebugState.lastCameraStateSyncCount = (PolCam.DebugState.lastCameraStateSyncCount or 0) + 1
                end

                if Config and Config.Debug and Config.Debug.LogEvents and PolCam and PolCam.DebugState then
                    local lastLog = PolCam.DebugState.lastCameraStateLog or 0
                    if (now - lastLog) > 1000 then
                        PolCam.DebugState.lastCameraStateLog = now
                        print(('[PolCam] cameraStateSync vehicle=%s heading=%.1f pitch=%.1f zoom=%.1f'):format(
                            tostring(vehicleNetId),
                            tonumber(state.heading) or 0.0,
                            tonumber(state.pitch) or 0.0,
                            tonumber(state.zoom) or 0.0
                        ))
                    end
                end
            end
        end
        
        Wait(50)
    end
end

function TogglePolCam()
    if PolCam.Active then
        DeactivatePolCam()
    else
        if IsInAllowedHelicopter() then
            -- Disallow opening the camera while on/near the ground.
            -- This prevents a GTA/FiveM camera bug where the view can clip underground.
            local heli = PolCam.CurrentVehicle
            if heli and DoesEntityExist(heli) then
                local minHeight = (Config.HeliControl and Config.HeliControl.MinAirborneHeight) or 2.0
                local heightAboveGround = GetEntityHeightAboveGround(heli)
                if heightAboveGround ~= nil and heightAboveGround <= minHeight then
                    PolCamNotify('error', 'Camera unavailable while on the ground')
                    return
                end
            end
            
            ActivatePolCam(false)
        end
    end
end

function ActivatePolCam(hasClaim, sharedState)
    -- If already active, don't reinitialize.
    if PolCam.Active and PolCam.Camera then return end

    -- If we don't have the claim yet, request it and wait.
    if not hasClaim then
        if _pendingCameraClaim then return end
        local vehicleNetId = GetCurrentVehicleNetId()
        if vehicleNetId then
            RequestCameraClaim(vehicleNetId)
        end
        return
    end

    PolCam.Active = true
    
    hideEsHud()
    if isPilot() then
        setEsHudForceAircraftHud(true)
    end

    -- Prevent "re-enter camera" from treating held lock key as a toggle.
    -- The lock key uses +/- commands; if the key is still held when we reactivate,
    -- we want to require a fresh re-press before StartLocking() can fire.
    PolCam.LockKeyHeld = false
    
    -- Notify targeting system that camera was activated (for grace period on lock toggle)
    if OnCameraActivated_Tracking then
        OnCameraActivated_Tracking()
    end
    
    -- Apply shared state if provided (continuing from another operator)
    if sharedState then
        ApplySharedCameraState(sharedState)
    end
    
    -- Create camera
    CreatePolCamCamera()
    
    -- If shared state was applied, we need to update the camera with those values
    if sharedState then
        -- Update camera rotation and zoom after creation
        if PolCam.Camera and DoesCamExist(PolCam.Camera) then
            SetCamRot(PolCam.Camera, -PolCam.Pitch, 0.0, PolCam.Heading, 2)
            SetCamFov(PolCam.Camera, PolCam.FOV)
        end
    end
    
    -- Clear label cache to ensure fresh lookup for this vehicle
    if ClearCameraLabelCache then
        ClearCameraLabelCache()
    end
    
    -- Play activation sound
    if PlayPolCamSound then
        PlayPolCamSound("CameraOn")
    end
    
    -- Start CCTV ambient loop
    if StartPolCamLoopSound then
        StartPolCamLoopSound("CCTVLoop")
    end
    
    -- Show NUI
    SendNUIMessage({
        action = "show",
        visionMode = PolCam.VisionMode,
        highContrast = {
            enabled = Config.UI.HighContrast.Enabled or false,
            theme = Config.UI.HighContrast.Theme or "green"
        }
    })
    SetNuiFocus(false, false)
    
    -- Start camera loop
    CreateThread(CameraLoop)
    
    -- Start UI update loop
    CreateThread(UIUpdateLoop)
    
    -- Start camera state sync loop for shared camera feature
    CreateThread(CameraStateSyncLoop)
    
    if Config.Debug.Enabled then
        if sharedState then
            print("[PolCam] Camera activated (continuing from shared state)")
        else
            print("[PolCam] Camera activated")
        end
    end
end

function DeactivatePolCam()
    if not PolCam.Active then return end
    
    -- Sync final state before releasing so next operator can continue
    local vehicleNetId = GetCurrentVehicleNetId()
    if vehicleNetId then
        local state = BuildCameraState()
        TriggerServerEvent('polcam:cameraStateSync', vehicleNetId, state)
    end
    
    PolCam.Active = false
    ReleaseCameraClaim()
    ResetCameraClaim()
    
    showEsHud()
    setEsHudForceAircraftHud(false)
    
    SendNUIMessage({ action = "hideAircraftHUD" })
    
    -- Destroy camera
    DestroyPolCamCamera()
    
    -- Reset vision
    if ResetVision then
        ResetVision()
    end
    
    -- Enable persistent tracking if we have a locked target
    -- (Don't clear the lock - let it persist)
    if OnCameraDeactivated_Tracking then
        OnCameraDeactivated_Tracking()
    end
    
    -- Notify spotlight system that camera is deactivated (for persistent mode)
    -- Spotlight will stay on if ground locked or tracking target, otherwise deactivate
    if OnCameraDeactivated then
        OnCameraDeactivated()
    elseif DeactivateSpotlight then
        DeactivateSpotlight()
    end
    
    -- Preserve hover state when leaving camera.
    -- Hover is a flight mode (pilot-only) and can be used without the camera UI.
    -- We only force-disable orbit here because it depends on camera context.
    if DeactivateOrbit then
        DeactivateOrbit()
    end

    
    -- Play deactivation sound
    if PlayPolCamSound then
        PlayPolCamSound("CameraOff")
    end
    
    -- Stop CCTV ambient loop
    if StopPolCamLoopSound then
        StopPolCamLoopSound("CCTVLoop")
    end
    
     -- Restore minimap when leaving camera mode
     DisplayRadar(true)

     -- Hide NUI
     SendNUIMessage({
         action = "hide"
     })
    
    if Config.Debug.Enabled then
        print("[PolCam] Camera deactivated")
    end
end

-- ============================================================================
-- UI TOGGLE
-- ============================================================================
function ToggleUI()
    PolCam.UIVisible = not PolCam.UIVisible
    SendNUIMessage({
        action = "toggleUI",
        visible = PolCam.UIVisible
    })
end

-- ============================================================================
-- MAIN LOOPS
-- ============================================================================
function CameraLoop()
    while PolCam.Active do
        -- Chord controls
        local ctrlHeld = IsControlPressed(0, 36)
        if ctrlHeld and IsControlJustPressed(0, 74) then
            if ToggleSpotlight then
                ToggleSpotlight()
            end
        end
        if ctrlHeld and IsControlJustPressed(0, 22) then
            if ToggleGroundLock then
                ToggleGroundLock()
            end
        end
        -- Check if still in valid helicopter
        if not IsInAllowedHelicopter() then
            DeactivatePolCam()
            break
        end
        
        -- Disable controls while camera active
        DisableControlActions()
        
        -- Handle mouse input for camera rotation
        HandleCameraInput()
        
        -- Handle zoom input
        HandleZoomInput()
        
        -- Update camera position and rotation
        UpdateCameraPosition()
        
        -- Update targeting
        if Config.Tracking and Config.Tracking.Enabled and UpdateTargeting then
            UpdateTargeting()
        end
        
        -- Update and render street overlay
        if UpdateStreetOverlay then
            UpdateStreetOverlay()
        end
        if RenderStreetOverlay then
            RenderStreetOverlay()
        end
        
        -- Render camera view
        RenderCameraView()
        
        -- Render debug visuals (drawn on top of everything)
        if RenderTargetingDebug then
            RenderTargetingDebug()
        end
        
        Wait(0)
    end
end

-- ============================================================================
-- TRACKING / UI HELPERS
-- ============================================================================
local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function SafeNormalize2D(x, y)
    local len = sqrt(x * x + y * y)
    if len < 1.0e-6 then return 0.0, 0.0 end
    return x / len, y / len
end

local function SignedAngle2D(fromX, fromY, toX, toY)
    local dot = fromX * toX + fromY * toY
    local det = fromX * toY - fromY * toX
    return atan(det, dot)
end

local function GetOffscreenTrackingCue(useCamera)
    if not PolCam.TargetInfo or not PolCam.TargetInfo.coords then return nil end

    local targetCoords = PolCam.TargetInfo.coords
    local sourcePos = PolCam.CameraCoords
    local forwardX, forwardY = 0.0, 1.0
    local fovDeg = PolCam.FOV or (Config.Camera and Config.Camera.DefaultFOV) or 50.0

    if useCamera and PolCam.Camera and GetCamMatrix then
        local _, _, _, forwardVector = GetCamMatrix(PolCam.Camera)
        forwardX, forwardY = SafeNormalize2D(forwardVector.x, forwardVector.y)
    else
        local vehicle = PolCam.CurrentVehicle
        if vehicle and DoesEntityExist(vehicle) then
            local headingRad = (GetEntityHeading(vehicle) or 0.0) * 0.017453292519943295
            forwardX, forwardY = SafeNormalize2D(-math.sin(headingRad), math.cos(headingRad))
            sourcePos = GetEntityCoords(vehicle)
        end
    end

    local toX, toY = SafeNormalize2D(targetCoords.x - sourcePos.x, targetCoords.y - sourcePos.y)
    local signedAngleRad = SignedAngle2D(forwardX, forwardY, toX, toY)
    local signedAngleDeg = deg(signedAngleRad)

    local halfFov = max(5.0, fovDeg * 0.5)
    local offscreen = abs(signedAngleDeg) > halfFov
    if not offscreen then return nil end

    local side = signedAngleDeg < 0.0 and "left" or "right"
    local distance = PolCam.TargetInfo.distance or 0

    return {
        active = true,
        side = side,
        angle = Clamp(abs(signedAngleDeg), halfFov, 180.0),
        distance = distance,
        label = "TRACK"
    }
end

-- ============================================================================
-- UI UPDATE OPTIMIZATION CONSTANTS
-- ============================================================================
local UI_SPEED_MULTIPLIER = 1.94384  -- m/s to knots
local UI_FEET_MULTIPLIER = 3.28084   -- meters to feet

-- Tiered update intervals (ms)
local UI_FAST_INTERVAL = (Config.Intervals and Config.Intervals.UI and Config.Intervals.UI.Fast) or 50
local UI_MEDIUM_INTERVAL = (Config.Intervals and Config.Intervals.UI and Config.Intervals.UI.Medium) or 200
local UI_SLOW_INTERVAL = (Config.Intervals and Config.Intervals.UI and Config.Intervals.UI.Slow) or 1000

-- Cached slow-update values
local CachedUIData = {
    postalCode = nil,
    streetName = "UNKNOWN",
    lat = 0,
    lng = 0,
    altitude = 0,
    groundElevation = 0,
    verticalSpeedFPM = 0,
    lastSlowUpdate = 0,
    lastMediumUpdate = 0,
}

-- ============================================================================
-- POSTAL INTEGRATION (Built-in coordinate-based lookup)
-- ============================================================================
local LoadedPostals = nil
local PostalsLoaded = false

-- Load postals from JSON file (call once)
local function LoadPostalData()
    if PostalsLoaded then return end
    PostalsLoaded = true
    
    if not Config.Postal or not Config.Postal.Enabled then return end
    
    -- Try to load from the configured postal resource
    local postalFile = Config.Postal.PostalFile or "ocrp-postals.json"
    local resource = Config.Postal.ExportResource or "nearest-postal"
    
    -- Try loading the JSON file from the postal resource
    local jsonData = LoadResourceFile(resource, postalFile)
    
    if not jsonData then
        -- Try common alternatives
        local alternatives = {"new-postals.json", "old-postals.json", "postals.json"}
        for _, alt in ipairs(alternatives) do
            jsonData = LoadResourceFile(resource, alt)
            if jsonData then
                if Config.Debug and Config.Debug.Enabled then
                    print("[PolCam] Loaded postal data from: " .. resource .. "/" .. alt)
                end
                break
            end
        end
    else
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Loaded postal data from: " .. resource .. "/" .. postalFile)
        end
    end
    
    if jsonData then
        local success, decoded = pcall(json.decode, jsonData)
        if success and decoded then
            LoadedPostals = decoded
            if Config.Debug and Config.Debug.Enabled then
                print("[PolCam] Loaded " .. #LoadedPostals .. " postals")
            end
        else
            if Config.Debug and Config.Debug.Enabled then
                print("[PolCam] Failed to decode postal JSON")
            end
        end
    else
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Could not find postal JSON file")
        end
    end
end

-- Calculate nearest postal for given coordinates
function GetPostalForCoords(coords)
    if not Config.Postal or not Config.Postal.Enabled or not coords then
        return nil
    end
    
    -- Ensure postals are loaded
    if not PostalsLoaded then
        LoadPostalData()
    end
    
    if not LoadedPostals or #LoadedPostals == 0 then
        return nil
    end
    
    -- Find nearest postal by distance
    local nearestCode = nil
    local minDistSq = math.huge
    local cx, cy = coords.x, coords.y
    
    for _, postal in ipairs(LoadedPostals) do
        local px, py = postal.x, postal.y
        if px and py then
            local dx = cx - px
            local dy = cy - py
            local distSq = dx * dx + dy * dy
            
            if distSq < minDistSq then
                minDistSq = distSq
                nearestCode = postal.code
            end
        end
    end
    
    return nearestCode and tostring(nearestCode) or nil
end

-- ============================================================================
-- CAMERA LABELS (Agency/Department Name per Helicopter/Livery)
-- ============================================================================
local CachedCameraLabel = nil
local CachedLabelVehicle = nil

-- Force refresh the camera label cache (call when activating camera)
function ClearCameraLabelCache()
    CachedCameraLabel = nil
    CachedLabelVehicle = nil
end

function GetCameraLabel(vehicle)
    if not Config.CameraLabels or not Config.CameraLabels.Enabled then
        return "LOS SANTOS POLICE DEPARTMENT"
    end
    
    -- Return cached label if same vehicle
    if vehicle == CachedLabelVehicle and CachedCameraLabel then
        return CachedCameraLabel
    end
    
    CachedLabelVehicle = vehicle
    CachedCameraLabel = Config.CameraLabels.DefaultLabel or "LOS SANTOS POLICE DEPARTMENT"
    
    if not vehicle or not DoesEntityExist(vehicle) then
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] GetCameraLabel: No valid vehicle, using default")
        end
        return CachedCameraLabel
    end
    
    local model = GetEntityModel(vehicle)
    
    -- Find matching model name from AllowedHelicopters
    local modelName = nil
    for _, name in ipairs(Config.AllowedHelicopters or {}) do
        local hash = GetHashKey(name)
        if hash == model then
            modelName = name
            if Config.Debug and Config.Debug.Enabled then
                print("[PolCam] GetCameraLabel: Matched model '" .. name .. "'")
            end
            break
        end
    end
    
    if not modelName then
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] GetCameraLabel: No model match found, hash=" .. tostring(model))
        end
        return CachedCameraLabel
    end
    
    -- Check for livery-specific label first
    if Config.CameraLabels.LiveryLabels and Config.CameraLabels.LiveryLabels[modelName] then
        local livery = GetVehicleLivery(vehicle)
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] GetCameraLabel: Vehicle livery=" .. tostring(livery))
        end
        if livery >= 0 and Config.CameraLabels.LiveryLabels[modelName][livery] then
            CachedCameraLabel = Config.CameraLabels.LiveryLabels[modelName][livery]
            if Config.Debug and Config.Debug.Enabled then
                print("[PolCam] GetCameraLabel: Using livery label: " .. CachedCameraLabel)
            end
            return CachedCameraLabel
        end
    end
    
    -- Fall back to model-specific label
    if Config.CameraLabels.ModelLabels and Config.CameraLabels.ModelLabels[modelName] then
        CachedCameraLabel = Config.CameraLabels.ModelLabels[modelName]
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] GetCameraLabel: Using model label: " .. CachedCameraLabel)
        end
        return CachedCameraLabel
    end
    
    if Config.Debug and Config.Debug.Enabled then
        print("[PolCam] GetCameraLabel: No specific label found, using default: " .. CachedCameraLabel)
    end
    return CachedCameraLabel
end

function UIUpdateLoop()
    -- Cache config values once at loop start
    local pitchMin = Config.Camera.MinVerticalAngle
    local pitchMax = Config.Camera.MaxVerticalAngle
    
    while PolCam.Active do
        local vehicle = PolCam.CurrentVehicle
        if vehicle and DoesEntityExist(vehicle) then
            local currentTime = GetGameTimer()
            local groundCoords = PolCam.GroundCoords
            local heliCoords = GetEntityCoords(vehicle)
            
            -- ================================================================
            -- SLOW UPDATES (every ~UI_SLOW_INTERVAL ms): Postal, Street, Lat/Lng
            -- These are expensive operations that don't need real-time updates
            -- ================================================================
            if currentTime - CachedUIData.lastSlowUpdate >= UI_SLOW_INTERVAL then
                CachedUIData.lastSlowUpdate = currentTime
                
                -- Get street name (expensive native calls)
                local streetHash, crossingHash = GetStreetNameAtCoord(groundCoords.x, groundCoords.y, groundCoords.z)
                local streetName = GetStreetNameFromHashKey(streetHash)
                local crossingName = GetStreetNameFromHashKey(crossingHash)
                
                if crossingName and crossingName ~= "" then
                    CachedUIData.streetName = streetName .. " / " .. crossingName
                else
                    CachedUIData.streetName = streetName or "UNKNOWN"
                end
                
                -- Get postal (expensive - iterates through all postals)
                CachedUIData.postalCode = GetPostalForCoords(groundCoords)
                
                -- Update lat/lng as whole numbers (no decimal precision needed)
                CachedUIData.lat = floor(groundCoords.x)
                CachedUIData.lng = floor(groundCoords.y)
            end
            
            -- ================================================================
            -- MEDIUM UPDATES (every ~UI_MEDIUM_INTERVAL ms): Altitude, Vertical Speed, Ground Elev
            -- These change slowly and don't need frame-perfect accuracy
            -- ================================================================
            if currentTime - CachedUIData.lastMediumUpdate >= UI_MEDIUM_INTERVAL then
                CachedUIData.lastMediumUpdate = currentTime
                
                local altitude = heliCoords.z
                
                -- Calculate Vertical Speed (FPM) - avoid division by zero
                local timeDiff = currentTime - PolCam.LastHeliTime
                if PolCam.LastHeliTime > 0 and timeDiff > 0 then
                    local zDiff = (altitude - PolCam.LastHeliZ) * UI_FEET_MULTIPLIER
                    CachedUIData.verticalSpeedFPM = floor((zDiff / (timeDiff * 0.001)) * 60)
                end
                PolCam.LastHeliZ = altitude
                PolCam.LastHeliTime = currentTime
                
                -- Altitude as whole number in feet
                CachedUIData.altitude = floor(altitude * UI_FEET_MULTIPLIER)
                
                -- Get ground elevation at camera center
                local found, groundZ = GetGroundZFor_3dCoord(groundCoords.x, groundCoords.y, groundCoords.z + 50.0, false)
                groundZ = found and groundZ or 0.0
                CachedUIData.groundElevation = floor(groundZ * UI_FEET_MULTIPLIER)
            end
            
            -- ================================================================
            -- FAST UPDATES (every ~50ms): Heading, Pitch, Speed, Compass
            -- These need real-time updates for smooth gimbal display
            -- ================================================================
            local heliSpeed = floor(GetEntitySpeed(vehicle) * UI_SPEED_MULTIPLIER)
            local heliHeading = floor(GetEntityHeading(vehicle))
            
            -- Get camera label (cached internally, cheap after first call)
            local cameraLabel = GetCameraLabel(vehicle)
            
            -- Check for hover/orbit status (simple boolean checks)
            local hoverActive = IsHoverActive and IsHoverActive() or false
            local orbitActive = IsOrbitActive and IsOrbitActive() or false
            local groundLockActive = IsGroundLockActive and IsGroundLockActive() or false
            
            -- Send UI update with all data
            SendNUIMessage({
                action = "update",
                data = {
                    -- Fast data (real-time)
                    heading = floor(PolCam.Heading),
                    pitch = floor(PolCam.Pitch),
                    pitchMin = pitchMin,
                    pitchMax = pitchMax,
                    heliSpeed = heliSpeed,
                    heliHeading = heliHeading,
                    zoom = format("%.1fx", PolCam.Zoom),
                    
                    -- Medium data (cached)
                    altitude = CachedUIData.altitude,
                    verticalSpeed = CachedUIData.verticalSpeedFPM,
                    groundElevation = CachedUIData.groundElevation,
                    
                    -- Slow data (cached)
                    street = CachedUIData.streetName,
                    postal = CachedUIData.postalCode,
                    lat = CachedUIData.lat,
                    lng = CachedUIData.lng,
                    
                    -- Static/cheap data
                    cameraLabel = cameraLabel,
                    visionMode = PolCam.VisionMode,
                    targetInfo = PolCam.TargetInfo,
                    hasTarget = PolCam.LockedTarget ~= nil,

                    hoverActive = hoverActive,
                    orbitActive = orbitActive,
                    groundLockActive = groundLockActive,
                    lrfStatus = "READY",
                    systemStatus = "NORM 32°C"
                }
            })
        
        end -- if vehicle exists
        
        Wait(UI_FAST_INTERVAL)
    end
end


-- ============================================================================
-- PILOT HUD (TRACKING)
-- ============================================================================
-- Cached values for Pilot HUD slow updates
local CachedPilotHUD = {
    street = "UNKNOWN",
    postal = nil,
    lastUpdate = 0,
}

function UpdatePilotHUD()
    if not Config.UI or not Config.UI.PilotHUD or not Config.UI.PilotHUD.Enabled then 
        return 
    end

    local hoverActive = IsHoverActive and IsHoverActive() or false
    local target = PolCam.LockedTarget

    -- Important: a locked target can be temporarily unstreamed when far away.
    -- In that case, keep the Pilot HUD visible using the last known TargetInfo
    -- instead of hiding the HUD.
    if target and DoesEntityExist(target) then
        -- Always update info to get fresh coords/heading/plate
        -- (UpdateLockedTargetInfo is throttled to 100ms in targeting.lua)
        if UpdateLockedTargetInfo then
            UpdateLockedTargetInfo()
        end
    end

    local targetInfo = PolCam.TargetInfo

    -- No lock and not hovering: nothing to show.
    if not targetInfo and not hoverActive then
        SendNUIMessage({ action = "hidePilotHUD" })
        return
    end

    local currentTime = GetGameTimer()
    local coords = targetInfo and targetInfo.coords or nil

    -- Slow updates (every 1000ms): Street and Postal
    if currentTime - CachedPilotHUD.lastUpdate >= 1000 then
        CachedPilotHUD.lastUpdate = currentTime
        
        -- Get street name
        if coords then
            local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
            local streetName = GetStreetNameFromHashKey(streetHash)
            local crossingName = GetStreetNameFromHashKey(crossingHash)
            if crossingName and crossingName ~= "" then
                CachedPilotHUD.street = streetName .. " / " .. crossingName
            else
                CachedPilotHUD.street = streetName or "UNKNOWN"
            end
            
            -- Target Postal
            CachedPilotHUD.postal = GetPostalForCoords(coords)
        end
    end

    -- Determine heading text (Northbound, etc.)
    local heading = (targetInfo and targetInfo.heading) or 0
    local headingNames = {"NORTH", "NORTH-EAST", "EAST", "SOUTH-EAST", "SOUTH", "SOUTH-WEST", "WEST", "NORTH-WEST"}
    local index = floor((heading + 22.5) / 45) % 8
    local headingText = format("%sBOUND (%d°)", headingNames[index + 1], heading)

    -- Target ID (Plate or Name) and Details
    local targetId = "SYSTEM"
    local targetDetails = nil

    if targetInfo and targetInfo.type == "vehicle" then
        targetId = "VEHICLE: " .. (targetInfo.plate or "-------")
        targetDetails = format("%s %s", targetInfo.make or "", targetInfo.model or "Unknown Vehicle")
    elseif targetInfo and targetInfo.type then
        targetId = "PED: " .. (targetInfo.name or "Civilian")
        targetDetails = "PEDESTRIAN"
        if targetInfo.inVehicle then
            targetDetails = targetInfo.vehicleModel or "In Vehicle"
        end
    elseif hoverActive then
        targetDetails = "HOVER MODE"
    end
    
    SendNUIMessage({
        action = "updatePilotHUD",
        config = Config.UI.PilotHUD,
        data = {
            targetId = targetId,
            targetDetails = targetDetails,
            postal = CachedPilotHUD.postal,
            street = CachedPilotHUD.street,
            headingText = headingText,
            distance = (targetInfo and targetInfo.distance) or 0,
            spotlightActive = IsSpotlightActive and IsSpotlightActive() or false,

            -- Used by NUI to show hover indicator while camera is off.
            hoverActive = hoverActive,

            -- Ensure NUI can apply correct theme even if camera UI never opened.
            highContrast = {
                enabled = Config.UI.HighContrast.Enabled or false,
                theme = Config.UI.HighContrast.Theme or "green"
            }
        }
    })
end

CreateThread(function()
    while true do
        local sleep = 1000
        -- Only run if we are in a valid helicopter
        local inHeli = IsInAllowedHelicopter()
        
        if inHeli then
            sleep = 500 -- Base check interval
            
            local trackingHUDEnabled = Config.UI and Config.UI.PilotHUD and Config.UI.PilotHUD.Enabled

            -- If we have a lock, we should try to show the pilot HUD even if the entity
            -- is temporarily unstreamed (DoesEntityExist can flip false at range).
            local hasLock = PolCam.LockedTarget ~= nil

            -- If we are hovering (even with no target lock), keep Pilot HUD visible so
            -- the hover indicator can display while the camera is off.
            local hoverActive = IsHoverActive and IsHoverActive() or false

            -- If camera is NOT active, but we are tracking or hovering, show the pilot HUD
            if trackingHUDEnabled and not PolCam.Active and (hasLock or hoverActive) then
                UpdatePilotHUD()
                sleep = 200 -- Update faster while showing HUD
            else
                -- If camera IS active, or not tracking/hovering, hide the pilot HUD
                -- (Main HUD already shows this info)
                SendNUIMessage({ action = "hidePilotHUD" })
            end
        else
            -- Not in heli, ensure HUD is hidden
            SendNUIMessage({ action = "hidePilotHUD" })
            sleep = 2000
        end
        
        Wait(sleep)
    end
end)

-- ============================================================================
-- CONTROL DISABLING
-- ============================================================================
-- Pre-define control IDs to disable for faster iteration
local DISABLED_CONTROLS = {24, 25, 37, 47, 58, 263, 264, 75, 27, 81, 82, 99, 100, 157, 158, 159, 160, 161, 162, 163, 164, 165}
local DISABLED_CONTROLS_COUNT = #DISABLED_CONTROLS

function DisableControlActions()
    for i = 1, DISABLED_CONTROLS_COUNT do
        DisableControlAction(0, DISABLED_CONTROLS[i], true)
    end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================
exports('IsPolCamActive', function()
    return PolCam.Active
end)

exports('GetCurrentTarget', function()
    return PolCam.LockedTarget, PolCam.TargetInfo
end)

exports('GetCameraHeading', function()
    return PolCam.Heading
end)

-- ============================================================================
-- FORCE RELEASE ALL (Called when another player takes over camera/spotlight)
-- ============================================================================
-- This event is sent by the server when ownership of the camera or spotlight
-- transfers to another player. It clears camera/spotlight local state.
-- NOTE: Tracking is NOT cleared here - tracking is now per-helicopter and
-- persists through camera handoffs. It will be synced via polcam:heliTrackingState.
RegisterNetEvent('polcam:forceReleaseAll')
AddEventHandler('polcam:forceReleaseAll', function()
    print("[PolCam DEBUG] Received polcam:forceReleaseAll")
    
    -- NOTE: Do NOT clear tracking here - tracking is per-heli and persists
    -- Only clear camera/spotlight/ground lock state
    PolCam.GroundLockPoint = nil
    
    -- Force-deactivate spotlight locally (without syncing to server)
    if ForceDeactivateSpotlightLocal then
        ForceDeactivateSpotlightLocal()
    elseif SpotlightData then
        -- Direct spotlight state reset as fallback
        SpotlightData.Active = false
        SpotlightData.PersistentActive = false
        SpotlightData.LockedGroundPoint = nil
        SpotlightData.TrackingTarget = false
        SendNUIMessage({ action = "spotlightOff" })
    end
    
    -- Additional NUI cleanup for ground lock
    SendNUIMessage({ action = "groundLockOff" })
    
    if Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Force released camera/spotlight state (ownership transferred)")
    end
end)

-- ============================================================================
-- ECOSYSTEM INTEGRATION (PolFeeds)
-- ============================================================================
CreateThread(function()
    while true do
        Wait(1000) -- Heartbeat every second
        
        if PolCam.Active and PolCam.CurrentVehicle then
            local heli = PolCam.CurrentVehicle
            local plate = GetVehicleNumberPlateText(heli)
            local model = GetEntityModel(heli)
            local label = GetCameraLabel(heli)
            
            TriggerServerEvent('polfeeds:updateFeed', {
                type = 'heli',
                id = GetPlayerServerId(PlayerId()),
                label = label,
                unit = plate,
                coords = GetEntityCoords(heli),
                rotation = GetCamRot(PolCam.Camera, 2),
                fov = PolCam.FOV,
                visionMode = PolCam.VisionMode,
                active = true
            })
        end
    end
end)

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
CreateThread(function()
    -- Register keybinds
    RegisterKeybinds()
    
    -- Initialize sounds
    if InitializeSounds then
        InitializeSounds()
    end
    
    if Config.Debug.Enabled then
        print("[PolCam] Initialized successfully")
    end
end)

-- ============================================================================
-- CLEANUP ON RESOURCE STOP
-- ============================================================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    if PolCam.Active then
        DeactivatePolCam()
    end
end)
