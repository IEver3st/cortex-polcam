--[[
    PolCam - Rappeling System Script
    Handles helicopter rappeling with server synchronization
    Requires OneSync for proper sync across players
]]

-- ============================================================================
-- NATIVE CACHING
-- ============================================================================
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
local GetGroundZFor_3dCoord = GetGroundZFor_3dCoord
local PolCamNotify = PolCamNotify
local GetPlayerServerId = GetPlayerServerId
local GetPlayerFromServerId = GetPlayerFromServerId
local GetPlayerPed = GetPlayerPed
local Wait = Wait
local CreateThread = CreateThread
local GetGameTimer = GetGameTimer
local IsControlJustPressed = IsControlJustPressed


-- ============================================================================

-- RAPPEL STATE
-- ============================================================================
local RappelState = {
    IsRappeling = false,
    CanRappel = false,
    CurrentVehicle = nil,
    LastCheck = 0,
    CheckInterval = 500, -- ms between altitude checks,
    ConfirmPending = false,
    ConfirmExpiresAt = 0,
}


-- ============================================================================
-- CONFIGURATION HELPERS
-- ============================================================================
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

-- ============================================================================
-- SEAT VALIDATION
-- ============================================================================

local function HashMatches(list, model)
    if type(list) ~= "table" then return false end

    for key, value in pairs(list) do
        -- Support both array style (numeric keys) and map style (hash -> bool)
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

    -- If an allowlist is defined, only those hashes may rappel
    if cfg.AllowedHashes and next(cfg.AllowedHashes) ~= nil then
        return HashMatches(cfg.AllowedHashes, model)
    end

    -- If a denylist is defined, block those hashes
    if cfg.DisableHashes and next(cfg.DisableHashes) ~= nil then
        if HashMatches(cfg.DisableHashes, model) then
            return false
        end
    end

    -- Fallback to global allowed helicopter list (if provided)
    if Config.AllowedHelicopters then
        for _, name in ipairs(Config.AllowedHelicopters) do
            if GetHashKey(name) == model then
                return true
            end
        end
        -- Not in allowed list
        return false
    end

    -- Default allow if nothing is defined
    return true
end

local function IsInAllowedRappelSeat()
    local cfg = GetRappelConfig()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle == 0 then return false, nil end
    
    -- Check if it's a helicopter (class 15)
    if GetVehicleClass(vehicle) ~= 15 then return false, nil end

    if not IsVehicleHashAllowed(vehicle) then
        return false, vehicle
    end
    
    -- Check each allowed seat
    for _, seat in ipairs(cfg.AllowedSeats or {1, 2}) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return true, vehicle
        end
    end
    
    return false, vehicle
end


-- ============================================================================
-- ALTITUDE CHECK
-- ============================================================================
local function GetHeliAltitude(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return 0
    end
    
    -- Get height above ground (more accurate for rappeling)
    local height = GetEntityHeightAboveGround(vehicle)
    
    -- Convert to feet if config uses feet
    local cfg = GetRappelConfig()
    return height * 3.28084 -- Always calculate in feet for comparison
end

local function CanRappelFromAltitude(vehicle)
    local cfg = GetRappelConfig()
    local altitudeFeet = GetHeliAltitude(vehicle)
    
    local minAlt = cfg.MinAltitude or 15
    local maxAlt = cfg.MaxAltitude or 150
    
    return altitudeFeet >= minAlt and altitudeFeet <= maxAlt, altitudeFeet
end

-- ============================================================================
-- RAPPEL EXECUTION
-- ============================================================================
local function StartRappel()
    if RappelState.IsRappeling then return end
    
    local inSeat, vehicle = IsInAllowedRappelSeat()
    if not inSeat then
        -- Notify player they're not in the right seat
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
    
    -- Notify server for sync
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

    
    -- Execute the rappel using native
    TaskRappelFromHeli(ped, 1)
    
    if Config.Debug and Config.Debug.Enabled then
        print(string.format("[PolCam] Rappeling from %.0f ft", altitude))
    end
    
    -- Monitor rappel state
    CreateThread(function()
        Wait(1000) -- Wait for rappel to start
        
        while RappelState.IsRappeling do
            local currentPed = PlayerPedId()
            local currentVehicle = GetVehiclePedIsIn(currentPed, false)
            
            -- If ped is no longer in vehicle, rappel is complete
            if currentVehicle == 0 then
                -- Check if ped is on the ground
                local pedCoords = GetEntityCoords(currentPed)
                local _, groundZ = GetGroundZFor_3dCoord(pedCoords.x, pedCoords.y, pedCoords.z, false)
                
                if pedCoords.z - groundZ < 1.5 then
                    -- Rappel complete
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


-- ============================================================================
-- KEYBIND REGISTRATION
-- ============================================================================
local function RegisterRappelKeybind()
    if not IsRappelEnabled() then return end
    
    local cfg = GetRappelConfig()
    local keybind = cfg.Keybind or "F"
    
    RegisterKeyMapping('polcam_rappel', 'PolCam: Rappel from Helicopter', 'keyboard', keybind)
    RegisterCommand('polcam_rappel', function()
        if not IsRappelEnabled() then return end

        local now = GetGameTimer()
        local confirmWindowMs = 2500

        if not RappelState.ConfirmPending or now > RappelState.ConfirmExpiresAt then
            RappelState.ConfirmPending = true
            RappelState.ConfirmExpiresAt = now + confirmWindowMs

            if Config.Debug and Config.Debug.Enabled then
                print("[PolCam] Rappel confirm: press again to rappel")
            end

            if PolCamNotify then
                PolCamNotify('inform', 'Press rappel key again to confirm')
            end
            return
        end

        RappelState.ConfirmPending = false
        RappelState.ConfirmExpiresAt = 0
        StartRappel()
    end, false)
end


-- ============================================================================
-- ALTITUDE MONITORING (Shows indicator when rappel is available)
-- ============================================================================
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
                        
                        -- Notify UI of rappel availability
                        SendNUIMessage({
                            action = "rappelStatus",
                            available = canRappel
                        })
                    end
                else
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

-- ============================================================================
-- SERVER SYNC HANDLERS
-- ============================================================================
-- Receive other players' rappel events for visual effects
RegisterNetEvent('polcam:syncRappel')
AddEventHandler('polcam:syncRappel', function(data)
    if type(data) ~= 'table' then return end

    local sourcePlayer = tonumber(data.source)
    if not sourcePlayer then return end

    local playerIdx = GetPlayerFromServerId(sourcePlayer)
    if not playerIdx or playerIdx == -1 then return end
    
    -- Get the ped of the source player
    local targetPed = GetPlayerPed(playerIdx)
    
    if targetPed and DoesEntityExist(targetPed) then
        -- The native TaskRappelFromHeli already syncs visually
        -- This event is for additional effects/notifications if needed
        if Config.Debug and Config.Debug.Enabled then
            print(string.format("[PolCam] Player %d rappeling", sourcePlayer))
        end
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================
exports('IsRappelAvailable', function()
    return RappelState.CanRappel
end)

exports('IsRappeling', function()
    return RappelState.IsRappeling
end)

exports('StartRappel', function()
    StartRappel()
end)

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
CreateThread(function()
    RegisterRappelKeybind()
    MonitorRappelAvailability()
    
    if Config.Debug and Config.Debug.Enabled and IsRappelEnabled() then
        print("[PolCam] Rappeling system initialized")
    end
end)
