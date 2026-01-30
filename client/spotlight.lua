--[[
    PolCam - Spotlight System Script
    Handles spotlight rendering, radius control, server sync, and visibility to all players
]]

-- ============================================================================
-- NATIVE CACHING (Performance Optimization)
-- ============================================================================
local DoesEntityExist = DoesEntityExist
local GetEntityCoords = GetEntityCoords
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local GetGameTimer = GetGameTimer
local TriggerServerEvent = TriggerServerEvent
local SendNUIMessage = SendNUIMessage
local CreateThread = CreateThread
local Wait = Wait
local DrawSpotLight = DrawSpotLight
local IsDisabledControlPressed = IsDisabledControlPressed
local IsControlPressed = IsControlPressed
local GetPlayerServerId = GetPlayerServerId
local PlayerId = PlayerId
local GetFrameTime = GetFrameTime

-- Math caching
local math_sqrt = math.sqrt
local math_min = math.min
local math_max = math.max
local math_exp = math.exp
local pairs = pairs

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

-- ============================================================================
-- SPOTLIGHT STATE
-- ============================================================================
local SpotlightData = {
    Active = false,
    PersistentActive = false,   -- Spotlight stays on even when camera is off
    LockedGroundPoint = nil,    -- Ground point to keep spotlight on
    TrackingTarget = false,     -- Whether to follow PolCam.LockedTarget dynamically
    Radius = 5.0,               -- Current radius (cone angle)
    MinRadius = 2.0,
    MaxRadius = 20.0,
    Brightness = 5.0,
    Range = 300.0,
    Hardness = 0.0,             -- Light intensity falloff (0 = soft center, higher = harder center)
    Falloff = 15.0,             -- Edge softness (higher = softer edges, 0 = hard cutoff)
    Color = {255, 255, 255},
    SyncWithCamera = true,
    MaxPersistentDistance = 500.0  -- Max distance before spotlight auto-disables
}

-- Apply config overrides
if Config and Config.Spotlight then
    SpotlightData.SyncWithCamera = Config.Spotlight.SyncWithCamera ~= false
    SpotlightData.Brightness = Config.Spotlight.Brightness or SpotlightData.Brightness
    SpotlightData.Range = Config.Spotlight.Range or SpotlightData.Range
    SpotlightData.Radius = Config.Spotlight.Radius or SpotlightData.Radius
    SpotlightData.Hardness = Config.Spotlight.Hardness or SpotlightData.Hardness
    SpotlightData.Falloff = Config.Spotlight.Falloff or SpotlightData.Falloff
    SpotlightData.Color = Config.Spotlight.Color or SpotlightData.Color
end

local _lastSpotlightPosSentAt = 0
local _lastSentGround = nil
local _lastSentHeli = nil
local _smoothedDir = nil

local function GetNetSyncConfig()
    local net = Config and Config.Spotlight and Config.Spotlight.NetSync
    local posInterval = 150
    local minMove = 0.25
    local smoothingSpeed = 10.0

    if net then
        posInterval = net.PositionIntervalMs or posInterval
        minMove = net.MinMoveDistance or minMove
        smoothingSpeed = net.SmoothingSpeed or smoothingSpeed
    end

    return posInterval, minMove, smoothingSpeed
end

local function CoordsDistance(a, b)

    if not a or not b then return math.huge end
    local ax, ay, az = a.x, a.y, a.z
    local bx, by, bz = b.x, b.y, b.z
    if ax == nil or bx == nil then return math.huge end
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    return math_sqrt(dx * dx + dy * dy + dz * dz)
end

local function MaybeSyncSpotlightPosition(targetCoords, heliCoords)
    if not targetCoords or not heliCoords then return end

    local posInterval, minMove = GetNetSyncConfig()
    local now = GetGameTimer()
    if (now - _lastSpotlightPosSentAt) < posInterval then
        return
    end

    local movedGround = CoordsDistance(targetCoords, _lastSentGround) >= minMove
    local movedHeli = CoordsDistance(heliCoords, _lastSentHeli) >= minMove

    if not _lastSentGround or not _lastSentHeli then
        movedGround = true
        movedHeli = true
    end

    if not (movedGround or movedHeli) then
        return
    end

    _lastSpotlightPosSentAt = now
    _lastSentGround = vector3(targetCoords.x, targetCoords.y, targetCoords.z)
    _lastSentHeli = vector3(heliCoords.x, heliCoords.y, heliCoords.z)
    TriggerServerEvent('polcam:spotlightPosition', targetCoords, heliCoords)
end

-- Storage for other players' spotlights
-- Keyed by vehicleNetId (camera instance) so only one spotlight exists per heli.
local OtherSpotlights = {} -- vehicleNetId -> spotlightData

-- Interpolation state for smooth remote spotlight rendering
local RemoteSpotlightInterp = {} -- vehicleNetId -> {targetGround, currentGround, targetDir, currentDir, lastUpdateTime}

-- ============================================================================
-- TOGGLE SPOTLIGHT
-- ============================================================================
function ToggleSpotlight()
    if SpotlightData.Active then
        DeactivateSpotlight()
    else
        ActivateSpotlight()
    end
end

-- ============================================================================
-- ACTIVATE SPOTLIGHT
-- ============================================================================
function ActivateSpotlight()
    if SpotlightData.Active then return end
    if not PolCam.Active then return end
    
    SpotlightData.Active = true
    SpotlightData.PersistentActive = true  -- Enable persistence
    
    -- Play sound
    if PlayPolCamSound then
        PlayPolCamSound("SpotlightOn")
    end
    
    -- Update NUI
    SendNUIMessage({
        action = "spotlightOn"
    })
    
    -- Get initial position data to include with activation
    local heli = PolCam.CurrentVehicle
    local initialGroundCoords = PolCam.GroundCoords
    local initialHeliCoords = heli and DoesEntityExist(heli) and GetEntityCoords(heli) or nil
    
    -- Sync to server with initial position data
    TriggerServerEvent('polcam:spotlightSync', true, SpotlightData.Radius, initialGroundCoords, initialHeliCoords)
    
    -- Reset position sync timer to ensure immediate updates flow through
    _lastSpotlightPosSentAt = 0
    _lastSentGround = nil
    _lastSentHeli = nil
    
    -- Start render loop (only if not already running)
    if not SpotlightData.RenderLoopActive then
        SpotlightData.RenderLoopActive = true
        CreateThread(RenderSpotlightLoop)
    end
    
    if Config.Debug.Enabled then
        print("[PolCam] Spotlight activated")
    end
end

-- ============================================================================
-- DEACTIVATE SPOTLIGHT
-- ============================================================================
function DeactivateSpotlight()
    if not SpotlightData.Active and not SpotlightData.PersistentActive then return end
    
    SpotlightData.Active = false
    SpotlightData.PersistentActive = false
    SpotlightData.LockedGroundPoint = nil
    SpotlightData.TrackingTarget = false
    _smoothedDir = nil
    
    -- Play sound
    if PlayPolCamSound then
        PlayPolCamSound("SpotlightOff")
    end

    
    -- Update NUI
    SendNUIMessage({
        action = "spotlightOff"
    })
    
    -- Sync to server
    TriggerServerEvent('polcam:spotlightSync', false, SpotlightData.Radius)
    
    if Config.Debug.Enabled then
        print("[PolCam] Spotlight deactivated")
    end
end

-- ============================================================================
-- FORCE DEACTIVATE SPOTLIGHT (Called when another player takes ownership)
-- This version does NOT sync to server since the server already knows
-- ============================================================================
function ForceDeactivateSpotlightLocal()
    SpotlightData.Active = false
    SpotlightData.PersistentActive = false
    SpotlightData.LockedGroundPoint = nil
    SpotlightData.TrackingTarget = false
    _smoothedDir = nil
    
    -- Update NUI
    SendNUIMessage({
        action = "spotlightOff"
    })
    
    if Config.Debug.Enabled then
        print("[PolCam] Spotlight force-deactivated (ownership transferred)")
    end
end

-- Handler for when another player takes over the spotlight
RegisterNetEvent('polcam:spotlightForceOff')
AddEventHandler('polcam:spotlightForceOff', function()
    ForceDeactivateSpotlightLocal()
end)

-- ============================================================================
-- CALLED WHEN CAMERA IS DEACTIVATED - KEEP SPOTLIGHT IF TRACKING OR GROUND LOCKED
-- ============================================================================
function OnCameraDeactivated()
    if SpotlightData.Active then
        -- Check if we have a locked target - spotlight will follow the target
        if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
            -- Don't set a static ground point - we'll track the target dynamically
            SpotlightData.LockedGroundPoint = nil
            SpotlightData.TrackingTarget = true
            -- Keep spotlight persistent but mark camera as inactive
            SpotlightData.Active = false
            -- PersistentActive stays true so the loop keeps rendering
        -- Otherwise lock to ground point if we have one
        elseif PolCam.GroundLockPoint then
            SpotlightData.LockedGroundPoint = PolCam.GroundLockPoint
            SpotlightData.TrackingTarget = false
            -- Keep spotlight persistent but mark camera as inactive
            SpotlightData.Active = false
            -- PersistentActive stays true so the loop keeps rendering
        else
            -- No valid target or ground lock - turn off spotlight completely
            DeactivateSpotlight()
        end
    end
end

-- ============================================================================
-- ADJUST SPOTLIGHT RADIUS (CTRL + Scroll)
-- ============================================================================
function HandleSpotlightRadiusInput()
    if not SpotlightData.Active then return end
    if not PolCam.Active then return end
    
    -- Check if CTRL is held
    if not IsControlPressed(0, 36) then return end
    
    local radiusChanged = false
    local maxRadius = SpotlightData.MaxRadius
    local minRadius = SpotlightData.MinRadius
    local currentRadius = SpotlightData.Radius
    
    -- Scroll up = increase radius
    if IsDisabledControlPressed(0, 241) then
        SpotlightData.Radius = math_min(maxRadius, currentRadius + 0.5)
        radiusChanged = true
    -- Scroll down = decrease radius
    elseif IsDisabledControlPressed(0, 242) then
        SpotlightData.Radius = math_max(minRadius, currentRadius - 0.5)
        radiusChanged = true
    end
    
    if radiusChanged then
        TriggerServerEvent('polcam:spotlightRadius', SpotlightData.Radius)
    end
end

-- ============================================================================
-- RENDER SPOTLIGHT LOOP (Handles both active camera and persistent mode)
-- ============================================================================
function RenderSpotlightLoop()
    -- Cache spotlight config values once
    local colorR = SpotlightData.Color[1]
    local colorG = SpotlightData.Color[2]
    local colorB = SpotlightData.Color[3]
    local range = SpotlightData.Range
    local brightness = SpotlightData.Brightness
    local hardness = SpotlightData.Hardness
    local falloff = SpotlightData.Falloff
    local maxPersistentDist = SpotlightData.MaxPersistentDistance
    
    while SpotlightData.Active or SpotlightData.PersistentActive do
        local heli = PolCam.CurrentVehicle
        
        -- Check if we need to stop due to distance or lost target
        if SpotlightData.PersistentActive and not SpotlightData.Active then
            -- If tracking a target, check if target is still valid
            if SpotlightData.TrackingTarget then
                if not PolCam.LockedTarget or not DoesEntityExist(PolCam.LockedTarget) then
                    -- Target lost, deactivate spotlight
                    DeactivateSpotlight()
                    break
                end
                -- Check distance to target
                if heli and DoesEntityExist(heli) then
                    local heliCoords = GetEntityCoords(heli)
                    local targetCoords = GetEntityCoords(PolCam.LockedTarget)
                    local dx = heliCoords.x - targetCoords.x
                    local dy = heliCoords.y - targetCoords.y
                    local dz = heliCoords.z - targetCoords.z
                    local distSq = dx*dx + dy*dy + dz*dz
                    
                    if distSq > (maxPersistentDist * maxPersistentDist) then
                        DeactivateSpotlight()
                        break
                    end
                else
                    DeactivateSpotlight()
                    break
                end
            -- If locked to ground point, check distance to ground point
            elseif SpotlightData.LockedGroundPoint then
                if heli and DoesEntityExist(heli) then
                    local heliCoords = GetEntityCoords(heli)
                    local lockedPt = SpotlightData.LockedGroundPoint
                    local dx = heliCoords.x - lockedPt.x
                    local dy = heliCoords.y - lockedPt.y
                    local dz = heliCoords.z - lockedPt.z
                    local distSq = dx*dx + dy*dy + dz*dz
                    
                    if distSq > (maxPersistentDist * maxPersistentDist) then
                        DeactivateSpotlight()
                        break
                    end
                else
                    DeactivateSpotlight()
                    break
                end
            end
        end
        
        -- Render our own spotlight
        if heli and DoesEntityExist(heli) then
            local heliCoords = GetEntityCoords(heli)
            local spotlightOriginX = heliCoords.x
            local spotlightOriginY = heliCoords.y
            local spotlightOriginZ = heliCoords.z - 2.0
            
            -- Calculate direction based on mode
            local dirX, dirY, dirZ = 0.0, 0.0, -1.0
            local targetCoords
            
            if SpotlightData.Active and PolCam.Active then
                -- Camera is active, follow camera ground coords
                targetCoords = PolCam.GroundCoords
            elseif SpotlightData.TrackingTarget and PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
                -- Tracking a locked target - get its position dynamically
                targetCoords = GetEntityCoords(PolCam.LockedTarget)
            elseif SpotlightData.LockedGroundPoint then
                -- Locked to a static ground point
                targetCoords = SpotlightData.LockedGroundPoint
            end
            
            if targetCoords then
                local dx = targetCoords.x - spotlightOriginX
                local dy = targetCoords.y - spotlightOriginY
                local dz = targetCoords.z - spotlightOriginZ
                local dist = math_sqrt(dx*dx + dy*dy + dz*dz)
                if dist > 0 then
                    local invDist = 1.0 / dist
                    dirX = dx * invDist
                    dirY = dy * invDist
                    dirZ = dz * invDist
                end

                -- Sync position to server for other players (throttled)
                MaybeSyncSpotlightPosition(targetCoords, heliCoords)
            end
            
            -- Smooth direction to avoid jitter (time-based exponential smoothing)
            local _, _, smoothingSpeed = GetNetSyncConfig()
            local dt = GetFrameTime()
            local speed = smoothingSpeed or 10.0
            local alpha = 1.0 - math_exp(-speed * dt)
            if not _smoothedDir then
                _smoothedDir = vector3(dirX, dirY, dirZ)
            else
                _smoothedDir = vector3(
                    _smoothedDir.x + (dirX - _smoothedDir.x) * alpha,
                    _smoothedDir.y + (dirY - _smoothedDir.y) * alpha,
                    _smoothedDir.z + (dirZ - _smoothedDir.z) * alpha
                )
            end

            -- Draw spotlight
            DrawSpotLight(
                spotlightOriginX, spotlightOriginY, spotlightOriginZ,
                _smoothedDir.x, _smoothedDir.y, _smoothedDir.z,
                colorR, colorG, colorB,
                range,
                brightness,
                hardness,
                SpotlightData.Radius,
                falloff
            )
        end
        
        -- Handle radius input if camera is active
        if PolCam.Active then
            HandleSpotlightRadiusInput()
        end
        
        Wait(0)
    end
    
    SpotlightData.RenderLoopActive = false
end


-- ============================================================================
-- RENDER OTHER PLAYERS' SPOTLIGHTS (with smooth interpolation)
-- ============================================================================
local function LerpVec3(a, b, t)
    return vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t
    )
end

local function NormalizeVec3(v)
    local len = math_sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len < 0.0001 then return vector3(0, 0, -1) end
    return vector3(v.x / len, v.y / len, v.z / len)
end

CreateThread(function()
    local colorR = SpotlightData.Color[1]
    local colorG = SpotlightData.Color[2]
    local colorB = SpotlightData.Color[3]
    local range = SpotlightData.Range
    local brightness = SpotlightData.Brightness
    local hardness = SpotlightData.Hardness
    local falloff = SpotlightData.Falloff
    
    while true do
        local dt = GetFrameTime()
        local hasAnySpotlight = false
        
        -- Get our own helicopter's network ID to skip rendering our own spotlight twice
        -- IMPORTANT: Only skip if we are the ACTIVE camera operator rendering locally.
        -- Passengers in the same helicopter who are NOT operating the camera should still
        -- see the spotlight via the sync mechanism.
        local myVehicleNetId = nil
        local isLocalCameraOperator = PolCam.Active and (SpotlightData.Active or SpotlightData.PersistentActive)
        if isLocalCameraOperator and PolCam.CurrentVehicle and DoesEntityExist(PolCam.CurrentVehicle) then
            myVehicleNetId = NetworkGetNetworkIdFromEntity(PolCam.CurrentVehicle)
        end
        
        for vehicleNetId, data in pairs(OtherSpotlights) do
            -- Skip our own helicopter ONLY if we are the active camera operator rendering locally
            if vehicleNetId ~= myVehicleNetId and data and data.active and data.groundCoords then
                hasAnySpotlight = true
                
                -- Get the actual vehicle entity for real-time position
                local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
                
                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    -- Use REAL helicopter position (not synced) for smooth origin
                    local realHeliCoords = GetEntityCoords(vehicle)
                    local spotlightOrigin = vector3(realHeliCoords.x, realHeliCoords.y, realHeliCoords.z - 2.0)
                    
                    -- Get or create interpolation state
                    local interp = RemoteSpotlightInterp[vehicleNetId]
                    if not interp then
                        local targetGround = vector3(data.groundCoords.x, data.groundCoords.y, data.groundCoords.z)
                        interp = {
                            targetGround = targetGround,
                            currentGround = targetGround,
                            currentDir = nil,
                            lastUpdateTime = GetGameTimer()
                        }
                        RemoteSpotlightInterp[vehicleNetId] = interp
                    end
                    
                    -- Update target when new data arrives (detected by checking if groundCoords changed)
                    local newTarget = vector3(data.groundCoords.x, data.groundCoords.y, data.groundCoords.z)
                    local targetDist = CoordsDistance(newTarget, interp.targetGround)
                    if targetDist > 0.1 then
                        interp.targetGround = newTarget
                        interp.lastUpdateTime = GetGameTimer()
                    end
                    
                    -- Smoothly interpolate ground position toward target
                    -- Use exponential smoothing for natural movement
                    local _, _, smoothingSpeed = GetNetSyncConfig()
                    local interpSpeed = (smoothingSpeed or 10.0) * 0.8  -- Slightly slower for remote to hide latency
                    local alpha = 1.0 - math_exp(-interpSpeed * dt)
                    
                    interp.currentGround = LerpVec3(interp.currentGround, interp.targetGround, alpha)
                    
                    -- Calculate direction from real helicopter position to interpolated ground
                    local dx = interp.currentGround.x - spotlightOrigin.x
                    local dy = interp.currentGround.y - spotlightOrigin.y
                    local dz = interp.currentGround.z - spotlightOrigin.z
                    local targetDir = NormalizeVec3(vector3(dx, dy, dz))
                    
                    -- Smooth the direction as well for extra smoothness
                    if not interp.currentDir then
                        interp.currentDir = targetDir
                    else
                        interp.currentDir = LerpVec3(interp.currentDir, targetDir, alpha)
                        interp.currentDir = NormalizeVec3(interp.currentDir)
                    end
                    
                    local radius = data.radius or 5.0
                    
                    -- Draw other player's spotlight with interpolated values
                    DrawSpotLight(
                        spotlightOrigin.x, spotlightOrigin.y, spotlightOrigin.z,
                        interp.currentDir.x, interp.currentDir.y, interp.currentDir.z,
                        colorR, colorG, colorB,
                        range,
                        brightness,
                        hardness,
                        radius,
                        falloff
                    )
                end
            end
        end
        
        -- Clean up interpolation state for removed spotlights
        for vehicleNetId, _ in pairs(RemoteSpotlightInterp) do
            if not OtherSpotlights[vehicleNetId] then
                RemoteSpotlightInterp[vehicleNetId] = nil
            end
        end
        
        -- If no spotlights to render, sleep longer to save CPU
        if hasAnySpotlight then
            Wait(0)
        else
            Wait(100)
        end
    end
end)

-- ============================================================================
-- RECEIVE SPOTLIGHT UPDATES FROM SERVER
-- ============================================================================
RegisterNetEvent('polcam:spotlightUpdate')
AddEventHandler('polcam:spotlightUpdate', function(vehicleNetId, data)
    -- Only skip storing if we are the ACTIVE camera operator who is rendering locally.
    -- Passengers in the same helicopter who are NOT operating the camera should still
    -- receive and store the spotlight data so they can see it rendered.
    local isLocalCameraOperator = PolCam.Active and (SpotlightData.Active or SpotlightData.PersistentActive)
    if isLocalCameraOperator and PolCam.CurrentVehicle and DoesEntityExist(PolCam.CurrentVehicle) then
        local myVehicleNetId = NetworkGetNetworkIdFromEntity(PolCam.CurrentVehicle)
        if vehicleNetId == myVehicleNetId then
            -- Skip - this is our own spotlight, we handle it locally
            return
        end
    end
    
    -- Store remote spotlight data keyed by heli instance.
    if data == nil then
        OtherSpotlights[vehicleNetId] = nil
    else
        OtherSpotlights[vehicleNetId] = data
    end
end)

-- Force-enable spotlight locally when server hands off the camera.
RegisterNetEvent('polcam:spotlightEnsureOn')
AddEventHandler('polcam:spotlightEnsureOn', function(radius)
    if not PolCam or not PolCam.Active then return end
    if not SpotlightData then return end

    SpotlightData.Radius = radius or SpotlightData.Radius

    -- If already on or persistent, nothing to do.
    if SpotlightData.Active or SpotlightData.PersistentActive then return end

    if ActivateSpotlight then
        ActivateSpotlight()
    end
end)


-- ============================================================================
-- GETTERS
-- ============================================================================
function IsSpotlightActive()
    return SpotlightData.Active or SpotlightData.PersistentActive
end

function GetSpotlightRadius()
    return SpotlightData.Radius
end

function IsSpotlightTrackingTarget()
    return SpotlightData.TrackingTarget
end
