local DoesEntityExist = DoesEntityExist
local GetEntityCoords = GetEntityCoords
local GetEntityVelocity = GetEntityVelocity
local SetEntityVelocity = SetEntityVelocity
local DoesEntityExist = DoesEntityExist
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
    HoverCoords = nil,
    HoverHeading = 0,
    HoverTargetZ = 0,
    HoverAltitudeDisplay = 0
}

function SetHoverAltitude(altitudeFT)
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
    if not PolCam.Active then return end
    if not PolCam.CurrentVehicle or not DoesEntityExist(PolCam.CurrentVehicle) then return end
    
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
    
    HeliControl.OrbitMode = true
    HeliControl.HoverMode = true
    
    TaskVehicleHeliProtect(
        ped,
        heli,
        HeliControl.OrbitCenter.x,
        HeliControl.OrbitCenter.y,
        HeliControl.OrbitCenter.z,
        HeliControl.OrbitRadius,
        HeliControl.OrbitAltitude - HeliControl.OrbitCenter.z,
        HeliControl.OrbitSpeed,
        0
    )
    
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
    
    if HeliControl.HoverMode then
        local heli = PolCam.CurrentVehicle
        if heli and DoesEntityExist(heli) then
            HeliControl.HoverCoords = GetEntityCoords(heli)
        end
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
    local lastAltUpdate = 0
    local ALT_UPDATE_INTERVAL = 200
    
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
                    wait = 0
                    
                    local coords = GetEntityCoords(heli)
                    local velocity = GetEntityVelocity(heli)
                    
                    local targetZ = HeliControl.HoverTargetZ or coords.z
                    local zError = targetZ - coords.z
                    local zCorrection = zError * (Config.HeliControl and Config.HeliControl.HoverZStiffness or 2.0)
                    
                    local brake = (Config.HeliControl and Config.HeliControl.HoverBrakeFactor) or 0.98
                    local newVelX = velocity.x
                    local newVelY = velocity.y
                    
                    local inputting = IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35)
                    if not inputting then
                        newVelX = newVelX * brake
                        newVelY = newVelY * brake
                    end
                    
                    SetEntityVelocity(heli, newVelX, newVelY, zCorrection)
                    
                    if SetHeliBladesFullSpeed then
                        SetHeliBladesFullSpeed(heli)
                    end

                    if currentTime - lastAltUpdate >= ALT_UPDATE_INTERVAL then
                        HeliControl.HoverAltitudeDisplay = FormatAltitude(targetZ)
                        SendNUIMessage({
                            action = "hoverAltitude",
                            altitude = HeliControl.HoverAltitudeDisplay
                        })
                        lastAltUpdate = currentTime
                    end
                end
            end
        end
        
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        
        if HeliControl.OrbitMode and PolCam.Active then
            local heli = PolCam.CurrentVehicle
            
            if not CheckAvionicsHealth(heli) then
                ShowAvionicsDamagedNotification()
                DeactivateOrbit()
                DeactivateHover()
                if Config.Debug and Config.Debug.Enabled then
                    print("[PolCam] Orbit disabled: Avionics damaged during flight")
                end
            elseif PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
                local targetCoords = GetEntityCoords(PolCam.LockedTarget)
                local dx = targetCoords.x - HeliControl.OrbitCenter.x
                local dy = targetCoords.y - HeliControl.OrbitCenter.y
                local movement = math.sqrt(dx * dx + dy * dy)
                
                if movement > 20.0 then
                    HeliControl.OrbitCenter = targetCoords
                    
                    local ped = PlayerPedId()
                    local heli = PolCam.CurrentVehicle
                    
                    if heli and DoesEntityExist(heli) then
                        TaskVehicleHeliProtect(
                            ped,
                            heli,
                            HeliControl.OrbitCenter.x,
                            HeliControl.OrbitCenter.y,
                            HeliControl.OrbitCenter.z,
                            HeliControl.OrbitRadius,
                            HeliControl.OrbitAltitude - HeliControl.OrbitCenter.z,
                            HeliControl.OrbitSpeed,
                            0
                        )
                    end
                end
            end
        end
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
