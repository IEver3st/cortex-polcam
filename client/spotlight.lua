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

local math_sqrt = math.sqrt
local math_min = math.min
local math_max = math.max
local math_exp = math.exp
local pairs = pairs

local SpotlightData = {
    Active = false,
    PersistentActive = false,
    LockedGroundPoint = nil,
    TrackingTarget = false,
    Radius = 5.0,
    MinRadius = 2.0,
    MaxRadius = 20.0,
    Brightness = 5.0,
    Range = 300.0,
    Hardness = 0.0,
    Falloff = 15.0,
    Color = {255, 255, 255},
    SyncWithCamera = true,
    MaxPersistentDistance = 500.0,
    ThemeIndex = 1
}

if Config and Config.Spotlight then
    SpotlightData.SyncWithCamera = Config.Spotlight.SyncWithCamera ~= false
    SpotlightData.Brightness = Config.Spotlight.Brightness or SpotlightData.Brightness
    SpotlightData.Range = Config.Spotlight.Range or SpotlightData.Range
    SpotlightData.Radius = Config.Spotlight.Radius or SpotlightData.Radius
    SpotlightData.Hardness = Config.Spotlight.Hardness or SpotlightData.Hardness
    SpotlightData.Falloff = Config.Spotlight.Falloff or SpotlightData.Falloff
    SpotlightData.Color = Config.Spotlight.Color or SpotlightData.Color

    if Config.Spotlight.Themes then

        for i, theme in ipairs(Config.Spotlight.Themes) do
            if theme.color[1] == SpotlightData.Color[1] and
               theme.color[2] == SpotlightData.Color[2] and
               theme.color[3] == SpotlightData.Color[3] then
                SpotlightData.ThemeIndex = i
                break
            end
        end
    end
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

local OtherSpotlights = {}

local RemoteSpotlightInterp = {}

function ToggleSpotlight()
    if SpotlightData.Active then
        DeactivateSpotlight()
    else
        ActivateSpotlight()
    end
end

function ActivateSpotlight()
    if SpotlightData.Active then return end
    if not PolCam.Active then return end

    SpotlightData.Active = true
    SpotlightData.PersistentActive = true

    if PlayPolCamSound then
        PlayPolCamSound("SpotlightOn")
    end

    SendNUIMessage({
        action = "spotlightOn"
    })

    local heli = PolCam.CurrentVehicle
    local initialGroundCoords = PolCam.GroundCoords
    local initialHeliCoords = heli and DoesEntityExist(heli) and GetEntityCoords(heli) or nil

    TriggerServerEvent('polcam:spotlightSync', true, SpotlightData.Radius, initialGroundCoords, initialHeliCoords, SpotlightData.Color)

    _lastSpotlightPosSentAt = 0
    _lastSentGround = nil
    _lastSentHeli = nil

    if not SpotlightData.RenderLoopActive then
        SpotlightData.RenderLoopActive = true
        CreateThread(RenderSpotlightLoop)
    end

    if Config.Debug.Enabled then
        print("[PolCam] Spotlight activated")
    end
end

function DeactivateSpotlight()
    if not SpotlightData.Active and not SpotlightData.PersistentActive then return end

    SpotlightData.Active = false
    SpotlightData.PersistentActive = false
    SpotlightData.LockedGroundPoint = nil
    SpotlightData.TrackingTarget = false
    _smoothedDir = nil

    if PlayPolCamSound then
        PlayPolCamSound("SpotlightOff")
    end

    SendNUIMessage({
        action = "spotlightOff"
    })

    TriggerServerEvent('polcam:spotlightSync', false, SpotlightData.Radius)

    if Config.Debug.Enabled then
        print("[PolCam] Spotlight deactivated")
    end
end

function ForceDeactivateSpotlightLocal()
    SpotlightData.Active = false
    SpotlightData.PersistentActive = false
    SpotlightData.LockedGroundPoint = nil
    SpotlightData.TrackingTarget = false
    _smoothedDir = nil

    SendNUIMessage({
        action = "spotlightOff"
    })

    if Config.Debug.Enabled then
        print("[PolCam] Spotlight force-deactivated (ownership transferred)")
    end
end

RegisterNetEvent('polcam:spotlightForceOff')
AddEventHandler('polcam:spotlightForceOff', function()
    ForceDeactivateSpotlightLocal()
end)

function OnCameraDeactivated()
    if SpotlightData.Active then

        if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then

            SpotlightData.LockedGroundPoint = nil
            SpotlightData.TrackingTarget = true

            SpotlightData.Active = false

        elseif PolCam.GroundLockPoint then
            SpotlightData.LockedGroundPoint = PolCam.GroundLockPoint
            SpotlightData.TrackingTarget = false

            SpotlightData.Active = false

        else

            DeactivateSpotlight()
        end
    end
end

function HandleSpotlightRadiusInput()
    if not SpotlightData.Active then return end
    if not PolCam.Active then return end

    if not IsControlPressed(0, 36) then return end

    local radiusChanged = false
    local maxRadius = SpotlightData.MaxRadius
    local minRadius = SpotlightData.MinRadius
    local currentRadius = SpotlightData.Radius

    if IsDisabledControlPressed(0, 241) then
        SpotlightData.Radius = math_min(maxRadius, currentRadius + 0.5)
        radiusChanged = true

    elseif IsDisabledControlPressed(0, 242) then
        SpotlightData.Radius = math_max(minRadius, currentRadius - 0.5)
        radiusChanged = true
    end

    if radiusChanged then
        TriggerServerEvent('polcam:spotlightRadius', SpotlightData.Radius)
    end
end

function RenderSpotlightLoop()

    local range = SpotlightData.Range
    local brightness = SpotlightData.Brightness
    local hardness = SpotlightData.Hardness
    local falloff = SpotlightData.Falloff
    local maxPersistentDist = SpotlightData.MaxPersistentDistance

    while SpotlightData.Active or SpotlightData.PersistentActive do
        local colorR = SpotlightData.Color[1]
        local colorG = SpotlightData.Color[2]
        local colorB = SpotlightData.Color[3]

        local heli = PolCam.CurrentVehicle

        if SpotlightData.PersistentActive and not SpotlightData.Active then

            if SpotlightData.TrackingTarget then
                if not PolCam.LockedTarget or not DoesEntityExist(PolCam.LockedTarget) then

                    DeactivateSpotlight()
                    break
                end

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

        if heli and DoesEntityExist(heli) then
            local heliCoords = GetEntityCoords(heli)
            local spotlightOriginX = heliCoords.x
            local spotlightOriginY = heliCoords.y
            local spotlightOriginZ = heliCoords.z - 2.0

            local dirX, dirY, dirZ = 0.0, 0.0, -1.0
            local targetCoords

            if SpotlightData.Active and PolCam.Active then

                targetCoords = PolCam.GroundCoords
            elseif SpotlightData.TrackingTarget and PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then

                targetCoords = GetEntityCoords(PolCam.LockedTarget)
            elseif SpotlightData.LockedGroundPoint then

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

                MaybeSyncSpotlightPosition(targetCoords, heliCoords)
            end

            local _, _, smoothingSpeed = GetNetSyncConfig()
            local dt = GetFrameTime()
            local speed = smoothingSpeed or 10.0
            local alpha = 1.0 - math_exp(-speed * dt)
            if not _smoothedDir then
                _smoothedDir = {x = dirX, y = dirY, z = dirZ}
            else
                _smoothedDir.x = _smoothedDir.x + (dirX - _smoothedDir.x) * alpha
                _smoothedDir.y = _smoothedDir.y + (dirY - _smoothedDir.y) * alpha
                _smoothedDir.z = _smoothedDir.z + (dirZ - _smoothedDir.z) * alpha
            end

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

        if PolCam.Active then
            HandleSpotlightRadiusInput()
        end

        Wait(0)
    end

    SpotlightData.RenderLoopActive = false
end

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

function CycleSpotlightColor()
    if not SpotlightData.Active then return end
    if not Config.Spotlight.Themes then return end

    local themeCount = #Config.Spotlight.Themes
    if themeCount <= 1 then return end

    SpotlightData.ThemeIndex = SpotlightData.ThemeIndex + 1
    if SpotlightData.ThemeIndex > themeCount then
        SpotlightData.ThemeIndex = 1
    end

    local theme = Config.Spotlight.Themes[SpotlightData.ThemeIndex]
    SpotlightData.Color = theme.color

    if PolCamNotify then
        PolCamNotify('inform', 'Spotlight Theme: ' .. theme.name)
    end

    TriggerServerEvent('polcam:spotlightColor', SpotlightData.Color)
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

        local myVehicleNetId = nil
        local isLocalCameraOperator = PolCam.Active and (SpotlightData.Active or SpotlightData.PersistentActive)
        if isLocalCameraOperator and PolCam.CurrentVehicle and DoesEntityExist(PolCam.CurrentVehicle) then
            myVehicleNetId = NetworkGetNetworkIdFromEntity(PolCam.CurrentVehicle)
        end

        for vehicleNetId, data in pairs(OtherSpotlights) do

            if vehicleNetId ~= myVehicleNetId and data and data.active and data.groundCoords then
                hasAnySpotlight = true

                local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)

                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then

                    local r, g, b = colorR, colorG, colorB
                    if data.color then
                        r, g, b = data.color[1], data.color[2], data.color[3]
                    end

                    local realHeliCoords = GetEntityCoords(vehicle)
                    local spotlightOrigin = vector3(realHeliCoords.x, realHeliCoords.y, realHeliCoords.z - 2.0)

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

                    local newTarget = vector3(data.groundCoords.x, data.groundCoords.y, data.groundCoords.z)
                    local targetDist = CoordsDistance(newTarget, interp.targetGround)
                    if targetDist > 0.1 then
                        interp.targetGround = newTarget
                        interp.lastUpdateTime = GetGameTimer()
                    end

                    local _, _, smoothingSpeed = GetNetSyncConfig()
                    local interpSpeed = (smoothingSpeed or 10.0) * 0.8
                    local alpha = 1.0 - math_exp(-interpSpeed * dt)

                    local cg = interp.currentGround
                    local tg = interp.targetGround
                    local cgx = cg.x + (tg.x - cg.x) * alpha
                    local cgy = cg.y + (tg.y - cg.y) * alpha
                    local cgz = cg.z + (tg.z - cg.z) * alpha
                    interp.currentGround = vector3(cgx, cgy, cgz)

                    local dx = cgx - spotlightOrigin.x
                    local dy = cgy - spotlightOrigin.y
                    local dz = cgz - spotlightOrigin.z
                    local len = math_sqrt(dx * dx + dy * dy + dz * dz)
                    if len < 0.0001 then len = 1 end
                    local invLen = 1.0 / len
                    local tdx, tdy, tdz = dx * invLen, dy * invLen, dz * invLen

                    if not interp.currentDir then
                        interp.currentDir = vector3(tdx, tdy, tdz)
                    else
                        local cd = interp.currentDir
                        local sx = cd.x + (tdx - cd.x) * alpha
                        local sy = cd.y + (tdy - cd.y) * alpha
                        local sz = cd.z + (tdz - cd.z) * alpha
                        local slen = math_sqrt(sx * sx + sy * sy + sz * sz)
                        if slen < 0.0001 then slen = 1 end
                        local sinv = 1.0 / slen
                        interp.currentDir = vector3(sx * sinv, sy * sinv, sz * sinv)
                    end

                    local radius = data.radius or 5.0

                    DrawSpotLight(
                        spotlightOrigin.x, spotlightOrigin.y, spotlightOrigin.z,
                        interp.currentDir.x, interp.currentDir.y, interp.currentDir.z,
                        r, g, b,
                        range,
                        brightness,
                        hardness,
                        radius,
                        falloff
                    )
                end
            end
        end

        for vehicleNetId, _ in pairs(RemoteSpotlightInterp) do
            if not OtherSpotlights[vehicleNetId] then
                RemoteSpotlightInterp[vehicleNetId] = nil
            end
        end

        if hasAnySpotlight then
            Wait(0)
        else
            Wait(100)
        end
    end
end)

RegisterNetEvent('polcam:spotlightUpdate')
AddEventHandler('polcam:spotlightUpdate', function(vehicleNetId, data)

    local isLocalCameraOperator = PolCam.Active and (SpotlightData.Active or SpotlightData.PersistentActive)
    if isLocalCameraOperator and PolCam.CurrentVehicle and DoesEntityExist(PolCam.CurrentVehicle) then
        local myVehicleNetId = NetworkGetNetworkIdFromEntity(PolCam.CurrentVehicle)
        if vehicleNetId == myVehicleNetId then

            return
        end
    end

    if data == nil then
        OtherSpotlights[vehicleNetId] = nil
    else
        OtherSpotlights[vehicleNetId] = data
    end
end)

RegisterNetEvent('polcam:spotlightEnsureOn')
AddEventHandler('polcam:spotlightEnsureOn', function(radius, color)
    if not PolCam or not PolCam.Active then return end
    if not SpotlightData then return end

    SpotlightData.Radius = radius or SpotlightData.Radius
    if color then
        SpotlightData.Color = color
    end

    if SpotlightData.Active or SpotlightData.PersistentActive then return end

    if ActivateSpotlight then
        ActivateSpotlight()
    end
end)

function IsSpotlightActive()
    return SpotlightData.Active or SpotlightData.PersistentActive
end

function GetSpotlightRadius()
    return SpotlightData.Radius
end

function IsSpotlightTrackingTarget()
    return SpotlightData.TrackingTarget
end
