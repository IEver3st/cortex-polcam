local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetPedInVehicleSeat = GetPedInVehicleSeat
local GetEntityCoords = GetEntityCoords
local GetEntityHeightAboveGround = GetEntityHeightAboveGround
local GetEntityModel = GetEntityModel
local DoesEntityExist = DoesEntityExist
local TaskRappelFromHeli = TaskRappelFromHeli
local GetVehicleClass = GetVehicleClass
local GetHashKey = GetHashKey
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked

local GetGroundZFor_3dCoord = GetGroundZFor_3dCoord
local GetPlayerServerId = GetPlayerServerId
local GetPlayerFromServerId = GetPlayerFromServerId
local GetPlayerPed = GetPlayerPed
local Wait = Wait
local CreateThread = CreateThread
local GetGameTimer = GetGameTimer
local IsControlJustPressed = IsControlJustPressed

local RappelState = {
    IsRappeling = false,
    CanRappel = false,
    CurrentVehicle = nil,
    LastCheck = 0,
    CheckInterval = 500,
    ConfirmPending = false,
    ConfirmExpiresAt = 0,
}

local function GetRappelConfig()
    return Config.Rappel or {
        Enabled = false,
        MinAltitude = 15,
        MaxAltitude = 150,
        AllowedSeats = {1, 2},
        SyncEnabled = true,
        AllowedHashes = {},
        DisableHashes = {}
    }
end

local function IsRappelEnabled()
    local cfg = GetRappelConfig()
    return cfg.Enabled == true
end

local function HashMatches(list, model)
    if type(list) ~= "table" then return false end

    for key, value in pairs(list) do

        local entry = key
        local enabled = value

        if type(key) == "number" then
            entry = value
            enabled = true
        end

        if enabled ~= false then
            local hash
            if type(entry) == "string" then
                hash = GetHashKey(entry)
            elseif type(entry) == "number" then
                hash = entry
            end

            if hash and hash == model then
                return true
            end
        end
    end

    return false
end

local function IsVehicleHashAllowed(vehicle)
    local cfg = GetRappelConfig()
    local model = GetEntityModel(vehicle)

    if cfg.AllowedHashes and next(cfg.AllowedHashes) ~= nil then
        return HashMatches(cfg.AllowedHashes, model)
    end

    if cfg.DisableHashes and next(cfg.DisableHashes) ~= nil then
        if HashMatches(cfg.DisableHashes, model) then
            return false
        end
    end

    if Config.AllowedHelicopters then
        for _, name in ipairs(Config.AllowedHelicopters) do
            if GetHashKey(name) == model then
                return true
            end
        end

        return false
    end

    return true
end

local function IsInAllowedRappelSeat()
    local cfg = GetRappelConfig()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then return false, nil end

    if GetVehicleClass(vehicle) ~= 15 then return false, nil end

    if not IsVehicleHashAllowed(vehicle) then
        return false, vehicle
    end

    for _, seat in ipairs(cfg.AllowedSeats or {1, 2}) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return true, vehicle
        end
    end

    return false, vehicle
end

local function GetHeliAltitude(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return 0
    end

    local height = GetEntityHeightAboveGround(vehicle)

    local cfg = GetRappelConfig()
    return height * 3.28084
end

local function CanRappelFromAltitude(vehicle)
    local cfg = GetRappelConfig()
    local altitudeFeet = GetHeliAltitude(vehicle)

    local minAlt = cfg.MinAltitude or 15
    local maxAlt = cfg.MaxAltitude or 150

    return altitudeFeet >= minAlt and altitudeFeet <= maxAlt, altitudeFeet
end

local function StartRappel()
    if RappelState.IsRappeling then return end

    local inSeat, vehicle = IsInAllowedRappelSeat()
    if not inSeat then

        if Config.Debug and Config.Debug.Enabled then
            print("[PolCam] Cannot rappel: not in allowed seat")
        end
        return
    end

    local canRappel, altitude = CanRappelFromAltitude(vehicle)
    if not canRappel then
        local cfg = GetRappelConfig()
        if Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Cannot rappel: altitude %.0f ft (need %d-%d ft)",
                altitude, cfg.MinAltitude or 15, cfg.MaxAltitude or 150))
        end
        return
    end

    RappelState.IsRappeling = true
    RappelState.CurrentVehicle = vehicle
    RappelState.ConfirmPending = false
    RappelState.ConfirmExpiresAt = 0

    local ped = PlayerPedId()

    local cfg = GetRappelConfig()
    if cfg.SyncEnabled then
        local vehicleNetId = SafeGetNetworkId(vehicle)
        if vehicleNetId then
            TriggerServerEvent('polcam:rappelStart', {
                vehicle = vehicleNetId,
                altitude = altitude,
                model = GetEntityModel(vehicle)
            })
        end
    end

    TaskRappelFromHeli(ped, 1)

    if Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Rappeling from %.0f ft", altitude))
    end

    CreateThread(function()
        Wait(1000)

        while RappelState.IsRappeling do
            local currentPed = PlayerPedId()
            local currentVehicle = GetVehiclePedIsIn(currentPed, false)

            if currentVehicle == 0 then

                local pedCoords = GetEntityCoords(currentPed)
                local _, groundZ = GetGroundZFor_3dCoord(pedCoords.x, pedCoords.y, pedCoords.z, false)

                if pedCoords.z - groundZ < 1.5 then

                    RappelState.IsRappeling = false
                    RappelState.CurrentVehicle = nil

                    if cfg.SyncEnabled then
                        TriggerServerEvent('polcam:rappelEnd', {})
                    end

                    if Config.Debug and Config.Debug.Enabled then
                        print("[PolCam] Rappel complete")
                    end
                    break
                end
            end

            Wait(100)
        end
    end)
end

local function RegisterRappelKeybind()
    if not IsRappelEnabled() then return end

    local cfg = GetRappelConfig()
    local keybind = cfg.Keybind or "F"

    RegisterKeyMapping('polcam_rappel', 'PolCam: Rappel from Helicopter', 'keyboard', keybind)
    RegisterCommand('polcam_rappel', function()
        if not IsRappelEnabled() then return end

        local inSeat, vehicle = IsInAllowedRappelSeat()
        if not inSeat or not vehicle then
            RappelState.ConfirmPending = false
            RappelState.ConfirmExpiresAt = 0
            return
        end

        local canRappel = CanRappelFromAltitude(vehicle)
        if not canRappel then
            RappelState.ConfirmPending = false
            RappelState.ConfirmExpiresAt = 0
            return
        end

        local now = GetGameTimer()
        local confirmWindowMs = 2500

        if not RappelState.ConfirmPending or now > RappelState.ConfirmExpiresAt then
            RappelState.ConfirmPending = true
            RappelState.ConfirmExpiresAt = now + confirmWindowMs

            if Config.Debug and Config.Debug.Enabled then
                print("[PolCam] Rappel confirm: press again to rappel")
            end

            if _G.PolCamNotify then
                _G.PolCamNotify('inform', 'Press rappel key again to confirm')
            end
            return
        end

        RappelState.ConfirmPending = false
        RappelState.ConfirmExpiresAt = 0
        StartRappel()
    end, false)
end

local function MonitorRappelAvailability()
    CreateThread(function()
        while true do
            local sleep = 1000

            if IsRappelEnabled() then
                local inSeat, vehicle = IsInAllowedRappelSeat()

                if inSeat and vehicle then
                    sleep = 500
                    local canRappel = CanRappelFromAltitude(vehicle)

                    if canRappel ~= RappelState.CanRappel then
                        RappelState.CanRappel = canRappel

                        SendNUIMessage({
                            action = "rappelStatus",
                            available = canRappel
                        })
                    end
                else
                    if RappelState.ConfirmPending then
                        RappelState.ConfirmPending = false
                        RappelState.ConfirmExpiresAt = 0
                    end
                    if RappelState.CanRappel then
                        RappelState.CanRappel = false
                        SendNUIMessage({
                            action = "rappelStatus",
                            available = false
                        })
                    end
                end
            end

            Wait(sleep)
        end
    end)
end

RegisterNetEvent('polcam:syncRappel')
AddEventHandler('polcam:syncRappel', function(data)
    if type(data) ~= 'table' then return end

    local sourcePlayer = tonumber(data.source)
    if not sourcePlayer then return end

    local playerIdx = GetPlayerFromServerId(sourcePlayer)
    if not playerIdx or playerIdx == -1 then return end

    local targetPed = GetPlayerPed(playerIdx)

    if targetPed and DoesEntityExist(targetPed) then

        if Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Player %d rappeling", sourcePlayer))
        end
    end
end)

exports('IsRappelAvailable', function()
    return RappelState.CanRappel
end)

exports('IsRappeling', function()
    return RappelState.IsRappeling
end)

exports('StartRappel', function()
    StartRappel()
end)

CreateThread(function()
    RegisterRappelKeybind()
    MonitorRappelAvailability()

    if Config.Debug and Config.Debug.Enabled and IsRappelEnabled() then
        print("[PolCam] Rappeling system initialized")
    end
end)
