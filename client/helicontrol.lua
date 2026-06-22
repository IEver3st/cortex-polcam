local DoesEntityExist = DoesEntityExist
local GetEntityCoords = GetEntityCoords
local GetEntityVelocity = GetEntityVelocity
local SetEntityVelocity = SetEntityVelocity
local GetEntityHeading = GetEntityHeading
local GetPedInVehicleSeat = GetPedInVehicleSeat
local PlayerPedId = PlayerPedId
local TaskVehicleMissionCoorsTarget = TaskVehicleMissionCoorsTarget
local TaskVehicleHeliProtect = TaskVehicleHeliProtect
local SetHeliBladesFullSpeed = SetHeliBladesFullSpeed
local ClearPedTasks = ClearPedTasks
local SendNUIMessage = SendNUIMessage
local GetGameTimer = GetGameTimer
local CreateThread = CreateThread
local Wait = Wait
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetVehicleClass = GetVehicleClass
local IsControlPressed = IsControlPressed
local GetVehicleEngineHealth = GetVehicleEngineHealth
local GetVehicleBodyHealth = GetVehicleBodyHealth
local IsVehicleEngineOn = IsVehicleEngineOn
local GetHeadingFromVector_2d = GetHeadingFromVector_2d
local SetEntityHeading = SetEntityHeading

local math_sqrt = math.sqrt
local math_floor = math.floor

local ALTITUDE_FT = 3.28084

local function FormatAltitude(altitude)
    return math_floor(altitude * ALTITUDE_FT) .. " FT"
end

local function CheckAvionicsHealth(heli)
    if not heli or not DoesEntityExist(heli) then
        return false
    end

    local engineHealth = GetVehicleEngineHealth(heli)
    local bodyHealth = GetVehicleBodyHealth(heli)
    local engineOn = IsVehicleEngineOn(heli)

    local minEngineHealth = (Config.HeliControl and Config.HeliControl.MinEngineHealth) or 100.0
    local minBodyHealth = (Config.HeliControl and Config.HeliControl.MinBodyHealth) or 100.0

    if not engineOn then
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Avionics check failed: Engine is off")
        end
        return false
    end

    if engineHealth < minEngineHealth then
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Avionics check failed: Engine health " .. engineHealth .. " < " .. minEngineHealth)
        end
        return false
    end

    if bodyHealth < minBodyHealth then
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Avionics check failed: Body health " .. bodyHealth .. " < " .. minBodyHealth)
        end
        return false
    end

    return true
end

local function ShowAvionicsDamagedNotification()
    if Config.HeliControl and Config.HeliControl.AvionicsDamagedMessage ~= false then
        if _G.PolCamNotify then
            _G.PolCamNotify('error', 'AVIONICS DAMAGED - STABILIZATION FAIL')
        else
            SendNUIMessage({
                action = "notification",
                message = "AVIONICS DAMAGED",
                type = "error"
            })
        end
    end
end

local HeliControl = {
    HoverMode = false,
    OrbitMode = false,
    OrbitCenter = nil,
    OrbitRadius = 100.0,
    OrbitAltitude = 0,
    OrbitSpeed = 15.0,
    OrbitAngle = nil,
    OrbitDirection = 1,
    OrbitAngularSpeed = 0,
    OrbitLastTick = 0,
    HoverCoords = nil,
    HoverHeading = 0,
    HoverTargetZ = 0,
    HoverAltitudeDisplay = 0,
    LastAltUpdate = 0
}

local function ApplyAltitudeHold(heli, targetZ, stiffness, velX, velY)
    local coords = GetEntityCoords(heli)
    local zError = targetZ - coords.z
    local zCorrection = zError * stiffness
    SetEntityVelocity(heli, velX, velY, zCorrection)
    if SetHeliBladesFullSpeed then
        SetHeliBladesFullSpeed(heli)
    end
    return coords
end

local function UpdateAltitudeDisplay(currentTime, targetZ)
    local interval = 200
    if currentTime - (HeliControl.LastAltUpdate or 0) >= interval then
        HeliControl.HoverAltitudeDisplay = FormatAltitude(targetZ)
        SendNUIMessage({
            action = "hoverAltitude",
            altitude = HeliControl.HoverAltitudeDisplay
        })
        HeliControl.LastAltUpdate = currentTime
    end
end

local function LerpVector3(a, b, t)
    return vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t
    )
end

local function SmoothHeading(currentHeading, targetHeading, smoothing, dt)
    local delta = ((targetHeading - currentHeading + 540) % 360) - 180
    local t = dt * smoothing
    if t > 1 then t = 1 end
    return (currentHeading + (delta * t)) % 360
end

function SetHoverAltitude(altitudeFT)
    local ped = PlayerPedId()
    local heli = PolCam.CurrentVehicle

    if HeliControl.OrbitMode then
        return
    end

    if not (heli and DoesEntityExist(heli)) then
        heli = GetVehiclePedIsIn(ped, false)
        if heli == 0 or GetVehicleClass(heli) ~= 15 then
            return
        end
        PolCam.CurrentVehicle = heli
    end

    if GetPedInVehicleSeat(heli, -1) ~= ped then
        return
    end

    local targetZ = altitudeFT / ALTITUDE_FT
    local coords = GetEntityCoords(heli)

    HeliControl.HoverTargetZ = targetZ
    HeliControl.HoverAltitudeDisplay = FormatAltitude(targetZ)

    if not HeliControl.HoverMode then
        ActivateHover()
        HeliControl.HoverCoords = vector3(coords.x, coords.y, targetZ)
    else
        HeliControl.HoverCoords.z = targetZ
    end

    SendNUIMessage({
        action = "hoverStatus",
        active = true,
        altitude = HeliControl.HoverAltitudeDisplay
    })

    if Config.Debug.Enabled then
        print("[PolCam] Hover altitude set to: " .. HeliControl.HoverAltitudeDisplay)
    end
end

function ToggleHoverMode()
    local ped = PlayerPedId()
    local heli = PolCam.CurrentVehicle

    if not (heli and DoesEntityExist(heli)) then
        heli = GetVehiclePedIsIn(ped, false)
        if heli == 0 or GetVehicleClass(heli) ~= 15 then
            return
        end
        PolCam.CurrentVehicle = heli
    end

    if GetPedInVehicleSeat(heli, -1) ~= ped then
        return
    end

    if HeliControl.HoverMode then
        DeactivateHover()
    else
        ActivateHover()
    end
end

function ActivateHover()
    if HeliControl.HoverMode then return end

    local heli = PolCam.CurrentVehicle
    local ped = PlayerPedId()

    if not CheckAvionicsHealth(heli) then
        ShowAvionicsDamagedNotification()
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Cannot activate hover: Avionics damaged")
        end
        return
    end

    HeliControl.HoverCoords = GetEntityCoords(heli)
    HeliControl.HoverHeading = GetEntityHeading(heli)

    HeliControl.HoverMode = true
    HeliControl.OrbitMode = false

    HeliControl.HoverTargetZ = HeliControl.HoverCoords.z
    HeliControl.HoverAltitudeDisplay = FormatAltitude(HeliControl.HoverTargetZ)

    if PlayPolCamSound then
        PlayPolCamSound("HoverOn")
    end

    SendNUIMessage({
        action = "hoverOn"
    })

    SendNUIMessage({
        action = "hoverStatus",
        active = true,
        altitude = HeliControl.HoverAltitudeDisplay
    })

    if Config.Debug.Enabled then
        print("[PolCam] Hover mode activated at " .. tostring(HeliControl.HoverCoords))
    end
end

function DeactivateHover()
    if not HeliControl.HoverMode then return end

    local ped = PlayerPedId()

    HeliControl.HoverMode = false
    HeliControl.OrbitMode = false

    ClearPedTasks(ped)

    if PlayPolCamSound then
        PlayPolCamSound("HoverOff")
    end

    SendNUIMessage({
        action = "hoverOff"
    })

    SendNUIMessage({
        action = "hoverStatus",
        active = false,
        altitude = nil
    })

    HeliControl.HoverAltitudeDisplay = nil

    if Config.Debug.Enabled then
        print("[PolCam] Hover mode deactivated")
    end
end

function ToggleOrbitMode()
    if not PolCam.Active and not (IsHeliTrackingActive and IsHeliTrackingActive()) then return end
    if not PolCam.CurrentVehicle or not DoesEntityExist(PolCam.CurrentVehicle) then
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 or GetVehicleClass(vehicle) ~= 15 then
            return
        end
        PolCam.CurrentVehicle = vehicle
    end

    local ped = PlayerPedId()
    local driver = GetPedInVehicleSeat(PolCam.CurrentVehicle, -1)

    if driver ~= ped then
        return
    end

    if HeliControl.OrbitMode then
        DeactivateOrbit()
    else
        ActivateOrbit()
    end
end

function ActivateOrbit()
    if HeliControl.OrbitMode then return end

    local heli = PolCam.CurrentVehicle
    local ped = PlayerPedId()
    local heliCoords = GetEntityCoords(heli)

    if not CheckAvionicsHealth(heli) then
        ShowAvionicsDamagedNotification()
        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Cannot activate orbit: Avionics damaged")
        end
        return
    end

    if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        HeliControl.OrbitCenter = GetEntityCoords(PolCam.LockedTarget)
    else
        HeliControl.OrbitCenter = PolCam.GroundCoords
    end

    local dx = heliCoords.x - HeliControl.OrbitCenter.x
    local dy = heliCoords.y - HeliControl.OrbitCenter.y
    HeliControl.OrbitRadius = math.sqrt(dx * dx + dy * dy)

    if HeliControl.OrbitRadius < Config.HeliControl.MinOrbitRadius then
        HeliControl.OrbitRadius = Config.HeliControl.MinOrbitRadius
    end

    HeliControl.OrbitAltitude = heliCoords.z
    HeliControl.HoverTargetZ = HeliControl.OrbitAltitude
    HeliControl.OrbitAngle = math.atan(dy, dx)
    HeliControl.OrbitAngularSpeed = (HeliControl.OrbitSpeed or 15.0) / HeliControl.OrbitRadius
    HeliControl.OrbitLastTick = GetGameTimer()
    HeliControl.OrbitDirection = 1

    HeliControl.OrbitMode = true
    HeliControl.HoverMode = true

    if PlayPolCamSound then
        PlayPolCamSound("OrbitOn")
    end

    SendNUIMessage({
        action = "orbitOn"
    })

    if Config.Debug.Enabled then
        print("[PolCam] Orbit mode activated - radius: " .. HeliControl.OrbitRadius)
    end
end

function DeactivateOrbit()
    if not HeliControl.OrbitMode then return end

    local ped = PlayerPedId()

    HeliControl.OrbitMode = false
    HeliControl.OrbitAngle = nil
    HeliControl.OrbitAngularSpeed = 0
    HeliControl.OrbitLastTick = 0

    if HeliControl.HoverMode then
        DeactivateHover()
    else
        ClearPedTasks(ped)
    end

    if PlayPolCamSound then
        PlayPolCamSound("OrbitOff")
    end

    SendNUIMessage({
        action = "orbitOff"
    })

    if Config.Debug.Enabled then
        print("[PolCam] Orbit mode deactivated")
    end
end

CreateThread(function()
    while true do
        local wait = 500
        local currentTime = GetGameTimer()

        if HeliControl.HoverMode and not HeliControl.OrbitMode then
            local ped = PlayerPedId()
            local heli = PolCam.CurrentVehicle

            if heli and DoesEntityExist(heli) and GetPedInVehicleSeat(heli, -1) == ped and GetVehicleClass(heli) == 15 then
                if not CheckAvionicsHealth(heli) then
                    ShowAvionicsDamagedNotification()
                    DeactivateHover()
                    if Config.Debug and Config.Debug.Enabled then
                        print("[PolCam] Hover disabled: Avionics damaged during flight")
                    end
                else
                    wait = 5

                    local coords = GetEntityCoords(heli)
                    local velocity = GetEntityVelocity(heli)

                    local targetZ = HeliControl.HoverTargetZ or coords.z
                    local brake = (Config.HeliControl and Config.HeliControl.HoverBrakeFactor) or 0.98
                    local newVelX = velocity.x
                    local newVelY = velocity.y

                    local inputting = IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35)
                    if not inputting then
                        newVelX = newVelX * brake
                        newVelY = newVelY * brake
                    end

                    local zStiffness = (Config.HeliControl and Config.HeliControl.HoverZStiffness) or 2.0
                    ApplyAltitudeHold(heli, targetZ, zStiffness, newVelX, newVelY)
                    UpdateAltitudeDisplay(currentTime, targetZ)
                end
            end
        end

        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        local wait = 250
        if HeliControl.OrbitMode and PolCam.Active then
            wait = 20
            local heli = PolCam.CurrentVehicle
            if not CheckAvionicsHealth(heli) then
                ShowAvionicsDamagedNotification()
                DeactivateOrbit()
                DeactivateHover()
                if Config.Debug and Config.Debug.Enabled then
                    print("[PolCam] Orbit disabled: Avionics damaged during flight")
                end
            elseif heli and DoesEntityExist(heli) then
                local currentTime = GetGameTimer()
                local lastTick = HeliControl.OrbitLastTick or currentTime
                local dt = (currentTime - lastTick) / 1000
                if dt <= 0 then dt = 0.02 end
                HeliControl.OrbitLastTick = currentTime

                if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
                    local targetCoords = GetEntityCoords(PolCam.LockedTarget)
                    if HeliControl.OrbitCenter then
                        local lerpSpeed = (Config.HeliControl and Config.HeliControl.OrbitCenterLerp) or 2.0
                        local t = dt * lerpSpeed
                        if t > 1 then t = 1 end
                        HeliControl.OrbitCenter = LerpVector3(HeliControl.OrbitCenter, targetCoords, t)
                    else
                        HeliControl.OrbitCenter = targetCoords
                    end
                end

                local center = HeliControl.OrbitCenter
                if center then
                    local coords = GetEntityCoords(heli)
                    local dx = coords.x - center.x
                    local dy = coords.y - center.y
                    local currentRadius = math.sqrt(dx * dx + dy * dy)
                    if currentRadius < 1.0 then currentRadius = 1.0 end
                    if HeliControl.OrbitRadius < Config.HeliControl.MinOrbitRadius then
                        HeliControl.OrbitRadius = Config.HeliControl.MinOrbitRadius
                    end

                    if not HeliControl.OrbitAngle then
                        HeliControl.OrbitAngle = math.atan(dy, dx)
                    end

                    local vel = GetEntityVelocity(heli)
                    if HeliControl.OrbitDirection == 1 and math.abs(vel.x) + math.abs(vel.y) > 0.2 then
                        local cross = dx * vel.y - dy * vel.x
                        if cross < -0.1 then
                            HeliControl.OrbitDirection = -1
                        end
                    end

                    local orbitSpeed = HeliControl.OrbitSpeed or 15.0
                    local angularSpeed = orbitSpeed / HeliControl.OrbitRadius
                    HeliControl.OrbitAngularSpeed = angularSpeed
                    HeliControl.OrbitAngle = HeliControl.OrbitAngle + (angularSpeed * HeliControl.OrbitDirection * dt)

                    local sinA = math.sin(HeliControl.OrbitAngle)
                    local cosA = math.cos(HeliControl.OrbitAngle)
                    local tangentX = -sinA * HeliControl.OrbitDirection
                    local tangentY = cosA * HeliControl.OrbitDirection

                    local radialX = dx / currentRadius
                    local radialY = dy / currentRadius
                    local radialError = currentRadius - HeliControl.OrbitRadius
                    local radialStiffness = (Config.HeliControl and Config.HeliControl.OrbitRadialStiffness) or 1.2
                    local radialDamping = (Config.HeliControl and Config.HeliControl.OrbitRadialDamping) or 0.6
                    local radialVel = (vel.x * radialX) + (vel.y * radialY)
                    local radialCorrection = (-radialError * radialStiffness) - (radialVel * radialDamping)

                    local errorRatio = math.abs(radialError) / HeliControl.OrbitRadius
                    local minTangentScale = (Config.HeliControl and Config.HeliControl.OrbitMinTangentScale) or 0.55
                    local tangentScale = 1.0 - math.min(errorRatio, 0.7)
                    if tangentScale < minTangentScale then tangentScale = minTangentScale end

                    local maxRadialCorrection = (Config.HeliControl and Config.HeliControl.OrbitRadialMaxCorrection) or (orbitSpeed * 0.8)
                    if radialCorrection > maxRadialCorrection then radialCorrection = maxRadialCorrection end
                    if radialCorrection < -maxRadialCorrection then radialCorrection = -maxRadialCorrection end

                    local desiredVelX = (tangentX * orbitSpeed * tangentScale) + (radialX * radialCorrection)
                    local desiredVelY = (tangentY * orbitSpeed * tangentScale) + (radialY * radialCorrection)

                    local swayAmp = (Config.HeliControl and Config.HeliControl.OrbitSwayAmplitude) or 1.1
                    local swayFreq = (Config.HeliControl and Config.HeliControl.OrbitSwayFrequency) or 0.45
                    local swayTangent = (Config.HeliControl and Config.HeliControl.OrbitSwayTangentBias) or 1.0
                    local swayRadial = (Config.HeliControl and Config.HeliControl.OrbitSwayRadialBias) or 0.7
                    local gustAmp = (Config.HeliControl and Config.HeliControl.OrbitSwayGustAmplitude) or 0.5
                    local gustFreq = (Config.HeliControl and Config.HeliControl.OrbitSwayGustFrequency) or 0.18
                    if swayAmp > 0 then
                        local time = currentTime * 0.001
                        local base = math.sin((time * swayFreq) + (HeliControl.OrbitAngle * 0.7))
                            + 0.6 * math.sin((time * swayFreq * 1.7) + 2.1)
                            + 0.4 * math.cos((time * swayFreq * 0.73) - 1.4)
                        local gust = math.sin((time * gustFreq) + 1.3) * math.sin((time * gustFreq * 0.37) + 0.7)
                        local sway = (base * 0.65 + (gust * gustAmp)) * swayAmp
                        desiredVelX = desiredVelX + (tangentX * sway * swayTangent) + (radialX * sway * swayRadial)
                        desiredVelY = desiredVelY + (tangentY * sway * swayTangent) + (radialY * sway * swayRadial)
                    end

                    local smoothing = (Config.HeliControl and Config.HeliControl.OrbitVelocitySmoothing) or 2.2
                    local lerp = dt * smoothing
                    if lerp > 1 then lerp = 1 end
                    local targetVelX = vel.x + (desiredVelX - vel.x) * lerp
                    local targetVelY = vel.y + (desiredVelY - vel.y) * lerp

                    local maxAccel = (Config.HeliControl and Config.HeliControl.OrbitMaxAccel) or 8.0
                    local dvX = targetVelX - vel.x
                    local dvY = targetVelY - vel.y
                    local dvMag = math.sqrt((dvX * dvX) + (dvY * dvY))
                    local maxDelta = maxAccel * dt
                    if dvMag > maxDelta and dvMag > 0 then
                        local scale = maxDelta / dvMag
                        dvX = dvX * scale
                        dvY = dvY * scale
                    end
                    local newVelX = vel.x + dvX
                    local newVelY = vel.y + dvY

                    local maxSpeed = orbitSpeed * 1.25
                    local horizSpeed = math.sqrt((newVelX * newVelX) + (newVelY * newVelY))
                    if horizSpeed > maxSpeed then
                        local scale = maxSpeed / horizSpeed
                        newVelX = newVelX * scale
                        newVelY = newVelY * scale
                    end

                    if horizSpeed > 0.05 then
                        local targetHeading = GetHeadingFromVector_2d(newVelX, newVelY)
                        local currentHeading = GetEntityHeading(heli)
                        local headingSmoothing = (Config.HeliControl and Config.HeliControl.OrbitHeadingSmoothing) or 2.2
                        local newHeading = SmoothHeading(currentHeading, targetHeading, headingSmoothing, dt)
                        SetEntityHeading(heli, newHeading)
                    end

                    local zStiffness = (Config.HeliControl and Config.HeliControl.HoverZStiffness) or 2.0
                    ApplyAltitudeHold(heli, HeliControl.HoverTargetZ, zStiffness, newVelX, newVelY)
                    UpdateAltitudeDisplay(currentTime, HeliControl.HoverTargetZ)
                end
            end
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        local wait = 750

        if HeliControl.HoverMode or HeliControl.OrbitMode then
            wait = 200

            local ped = PlayerPedId()
            local heli = PolCam and PolCam.CurrentVehicle or nil

            if not (heli and DoesEntityExist(heli)) then
                ClearPedTasks(ped)
                HeliControl.HoverMode = false
                HeliControl.OrbitMode = false

                SendNUIMessage({
                    action = "hoverStatus",
                    active = false,
                    altitude = nil
                })
            else
                local notPilot = GetPedInVehicleSeat(heli, -1) ~= ped
                local notHeli = GetVehicleClass(heli) ~= 15

                if notPilot or notHeli then
                    if DeactivateOrbit then DeactivateOrbit() end
                    if DeactivateHover then DeactivateHover() end
                end
            end
        end

        Wait(wait)
    end
end)

function CleanupHeliControl()
    if HeliControl.HoverMode or HeliControl.OrbitMode then
        local ped = PlayerPedId()
        ClearPedTasks(ped)
    end

    HeliControl.HoverMode = false
    HeliControl.OrbitMode = false
end

function IsHoverActive()
    return HeliControl.HoverMode
end

function IsOrbitActive()
    return HeliControl.OrbitMode
end
