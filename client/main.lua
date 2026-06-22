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
local IsControlJustPressed = IsControlJustPressed
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked

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

local function DebugLog(message)
    if Config and Config.Debug and Config.Debug.Enabled then
        print(message)
    end
end

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

Config = Config or {}
Config.Camera = Config.Camera or {}
Config.Vision = Config.Vision or {}
Config.Keybinds = Config.Keybinds or {}
Config.Lib = Config.Lib or {}
Config.EsHud = Config.EsHud or {}

_G.PolCamNotify = PolCamNotify

PolCam = {

    Active = false,
    Camera = nil,
    Scaleform = nil,

    Heading = 0.0,
    Pitch = -15.0,
    Zoom = Config.Camera.DefaultZoom or 5.0,
    TargetZoom = Config.Camera.DefaultZoom or 5.0,
    FOV = Config.Camera.DefaultFOV or 50.0,

    VisionMode = Config.Vision.DefaultMode or "normal",

    LockedTarget = nil,
    LockedTargetType = nil,
    TargetInfo = nil,
    LockKeyHeld = false,

    GroundLockPoint = nil,

    UIVisible = true,

    CameraCoords = vector3(0, 0, 0),
    GroundCoords = vector3(0, 0, 0),

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

local PolCamSettingsKeys = {
    HighContrastEnabled = 'polcam_highContrastEnabled',
    HighContrastTheme = 'polcam_highContrastTheme',
    TargetLabelFollowTheme = 'polcam_targetLabelFollowTheme',
    TargetLabelColor = 'polcam_targetLabelColor',
}

local PolCamThemeOptions = {
    { value = 'green', label = 'Green' },
    { value = 'orange', label = 'Orange' },
    { value = 'red', label = 'Red' },
    { value = 'purple', label = 'Purple' },
    { value = 'blue', label = 'Blue' },
    { value = 'pink', label = 'Pink' },
    { value = 'black', label = 'Black' },
    { value = '#ffffff', label = 'White' },
    { value = '#38bdf8', label = 'Cyan' },
    { value = '#f59e0b', label = 'Amber' },
}

local PolCamThemeAllowList = {
    green = true,
    orange = true,
    red = true,
    purple = true,
    blue = true,
    pink = true,
    black = true,
}

local PolCamLabelColorOptions = {
    { value = '#00ff00', label = 'Green' },
    { value = '#ffffff', label = 'White' },
    { value = '#38bdf8', label = 'Cyan' },
    { value = '#5eb2ff', label = 'Blue' },
    { value = '#f59e0b', label = 'Amber' },
    { value = '#ef4444', label = 'Red' },
    { value = '#bf00ff', label = 'Purple' },
    { value = '#ff00ff', label = 'Pink' },
}

local function IsHexColor(value)
    return type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') ~= nil
end

local function HexToRgba(value, alpha)
    if not IsHexColor(value) then return nil end
    local r = tonumber(value:sub(2, 3), 16)
    local g = tonumber(value:sub(4, 5), 16)
    local b = tonumber(value:sub(6, 7), 16)
    if not r or not g or not b then return nil end
    return { r, g, b, alpha or 230 }
end

local function RgbaToHex(value)
    if type(value) ~= 'table' then return '#00ff00' end
    local r = max(0, min(255, floor(tonumber(value[1]) or 0)))
    local g = max(0, min(255, floor(tonumber(value[2]) or 255)))
    local b = max(0, min(255, floor(tonumber(value[3]) or 0)))
    return format('#%02x%02x%02x', r, g, b)
end

local function BuildPolCamTrackColorsPayload()
    local targetCfg = (Config.UI and Config.UI.TargetLabel) or {}
    if targetCfg.FollowHighContrast ~= false then
        return { FollowTheme = true }
    end

    local color = targetCfg.Color or { 0, 255, 0, 230 }
    local r = max(0, min(255, floor(tonumber(color[1]) or 0)))
    local g = max(0, min(255, floor(tonumber(color[2]) or 255)))
    local b = max(0, min(255, floor(tonumber(color[3]) or 0)))

    return {
        FollowTheme = false,
        Color = format('rgb(%d, %d, %d)', r, g, b),
        DimColor = format('rgba(%d, %d, %d, 0.85)', r, g, b),
    }
end

local function BuildPolCamHighContrastPayload()
    local highContrastCfg = (Config.UI and Config.UI.HighContrast) or {}
    return {
        enabled = highContrastCfg.Enabled == true,
        theme = highContrastCfg.Theme or 'green'
    }
end

local function CanUseEsLibSettings()
    return GetResourceState('es_lib') == 'started'
        and type(exports) == 'table'
        and exports.es_lib
        and exports.es_lib.registerSettingsScript
        and exports.es_lib.getSetting
end

local POLCAM_SETTING_WATCH = {
    [PolCamSettingsKeys.HighContrastEnabled] = true,
    [PolCamSettingsKeys.HighContrastTheme] = true,
    [PolCamSettingsKeys.TargetLabelFollowTheme] = true,
    [PolCamSettingsKeys.TargetLabelColor] = true,
}

local function getSettingsDefinition()
    local targetCfg = (Config.UI and Config.UI.TargetLabel) or {}
    local highContrastCfg = (Config.UI and Config.UI.HighContrast) or {}

    return {
        label = 'PolCam',
        settings = {
            {
                key = PolCamSettingsKeys.HighContrastEnabled,
                type = 'toggle',
                label = 'High Contrast',
                description = 'Enable high contrast color mode for PolCam HUD',
                default = highContrastCfg.Enabled == true,
            },
            {
                key = PolCamSettingsKeys.HighContrastTheme,
                type = 'select',
                label = 'HUD Color Theme',
                description = 'Personal PolCam HUD color theme',
                default = highContrastCfg.Theme or 'green',
                options = PolCamThemeOptions,
            },
            {
                key = PolCamSettingsKeys.TargetLabelFollowTheme,
                type = 'toggle',
                label = 'Track Label Follows Theme',
                description = 'Use HUD theme color for world track labels',
                default = targetCfg.FollowHighContrast ~= false,
            },
            {
                key = PolCamSettingsKeys.TargetLabelColor,
                type = 'select',
                label = 'Track Label Color',
                description = 'Track label color when follow-theme is disabled',
                default = RgbaToHex(targetCfg.Color),
                options = PolCamLabelColorOptions,
            },
        },
        sections = {
            {
                label = 'Visuals',
                keys = {
                    PolCamSettingsKeys.HighContrastEnabled,
                    PolCamSettingsKeys.HighContrastTheme,
                    PolCamSettingsKeys.TargetLabelFollowTheme,
                    PolCamSettingsKeys.TargetLabelColor,
                }
            },
        },
    }
end

local function ApplyPolCamClientSettingsFromEsLib()
    if not CanUseEsLibSettings() then return end

    local highContrastCfg = (Config.UI and Config.UI.HighContrast) or {}
    local targetCfg = (Config.UI and Config.UI.TargetLabel) or {}

    local highContrastEnabled = exports.es_lib:getSetting(PolCamSettingsKeys.HighContrastEnabled)
    if type(highContrastEnabled) ~= 'boolean' then
        highContrastEnabled = highContrastCfg.Enabled == true
    end

    local highContrastTheme = exports.es_lib:getSetting(PolCamSettingsKeys.HighContrastTheme)
    if type(highContrastTheme) ~= 'string' then
        highContrastTheme = highContrastCfg.Theme or 'green'
    end
    local normalizedTheme = string.lower(highContrastTheme)
    if not PolCamThemeAllowList[normalizedTheme] and not IsHexColor(highContrastTheme) then
        highContrastTheme = highContrastCfg.Theme or 'green'
    end

    local followTheme = exports.es_lib:getSetting(PolCamSettingsKeys.TargetLabelFollowTheme)
    if type(followTheme) ~= 'boolean' then
        followTheme = targetCfg.FollowHighContrast ~= false
    end

    local targetLabelColor = exports.es_lib:getSetting(PolCamSettingsKeys.TargetLabelColor)
    if type(targetLabelColor) ~= 'string' or not IsHexColor(targetLabelColor) then
        targetLabelColor = RgbaToHex(targetCfg.Color)
    end

    Config.UI = Config.UI or {}
    Config.UI.HighContrast = Config.UI.HighContrast or {}
    Config.UI.TargetLabel = Config.UI.TargetLabel or {}

    Config.UI.HighContrast.Enabled = highContrastEnabled == true
    Config.UI.HighContrast.Theme = highContrastTheme
    Config.UI.TargetLabel.FollowHighContrast = followTheme == true

    local rgba = HexToRgba(targetLabelColor, 230)
    if rgba then
        Config.UI.TargetLabel.Color = rgba
    end
end

local function PushPolCamClientSettingsToNui()
    SendNUIMessage({
        action = 'applyClientSettings',
        data = {
            highContrast = BuildPolCamHighContrastPayload(),
            trackColors = BuildPolCamTrackColorsPayload()
        }
    })
end

local function RegisterPolCamSettingsIntegration()
    if not CanUseEsLibSettings() then return end

    exports.es_lib:registerSettingsScript('polcam', getSettingsDefinition())
    ApplyPolCamClientSettingsFromEsLib()
    PushPolCamClientSettingsToNui()
end

AddEventHandler('es_lib:settingChanged', function(key)
    if not POLCAM_SETTING_WATCH[key] then
        return
    end

    ApplyPolCamClientSettingsFromEsLib()
    PushPolCamClientSettingsToNui()
end)

local function RegisterKeybinds()

    RegisterKeyMapping('polcam_toggle', 'PolCam: Toggle Camera', 'keyboard', Config.Keybinds.ToggleCamera)
    RegisterCommand('polcam_toggle', function()
        TogglePolCam()
    end, false)

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

    RegisterKeyMapping('polcam_vision', 'PolCam: Cycle Vision Mode', 'keyboard', Config.Keybinds.CycleVision)
    RegisterCommand('polcam_vision', function()
        if PolCam.Active then
            CycleVisionMode()
        end
    end, false)

    RegisterKeyMapping('polcam_marker', 'PolCam: Place Marker', 'keyboard', Config.Keybinds.PlaceMarker)
    RegisterCommand('polcam_marker', function()
        if PolCam.Active then
            PlaceMarker()
        end
    end, false)

    RegisterKeyMapping('polcam_delete_marker', 'PolCam: Delete Last Marker', 'keyboard', Config.Keybinds.DeleteMarker or "DELETE")
    RegisterCommand('polcam_delete_marker', function()
        if PolCam.Active then
            DeleteLastMarker()
        end
    end, false)

    RegisterKeyMapping('polcam_ui', 'PolCam: Toggle UI', 'keyboard', Config.Keybinds.ToggleUI)
    RegisterCommand('polcam_ui', function()
        if PolCam.Active then
            ToggleUI()
        end
    end, false)

    if Config.Spotlight and Config.Spotlight.Enabled then
        RegisterKeyMapping('polcam_spotlight', 'PolCam: Toggle Spotlight', 'keyboard', Config.Keybinds.Spotlight)
        RegisterCommand('polcam_spotlight', function()
            if PolCam.Active and ToggleSpotlight then
                ToggleSpotlight()
            end
        end, false)

        if Config.Keybinds.CycleSpotlightColor then
            RegisterKeyMapping('polcam_spotlight_color', 'PolCam: Cycle Spotlight Color', 'keyboard', Config.Keybinds.CycleSpotlightColor)
            RegisterCommand('polcam_spotlight_color', function()
                if PolCam.Active and CycleSpotlightColor then
                    CycleSpotlightColor()
                end
            end, false)
        end
    end

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
                    PolCamNotify('error', 'Usage: /hover [altitude_ft]')
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

    if Config.HeliControl and Config.HeliControl.OrbitEnabled then
        RegisterKeyMapping('polcam_orbit', 'PolCam: Toggle Orbit Mode', 'keyboard', Config.Keybinds.ToggleOrbit)
        RegisterCommand('polcam_orbit', function()
            if ToggleOrbitMode and (PolCam.Active or (IsHeliTrackingActive and IsHeliTrackingActive())) then
                ToggleOrbitMode()
            end
        end, false)
    end

    RegisterKeyMapping('polcam_streets', 'PolCam: Toggle Street Names', 'keyboard', Config.Keybinds.ToggleStreets or "N")
    RegisterCommand('polcam_streets', function()
        if PolCam.Active and ToggleStreetOverlay then
            ToggleStreetOverlay()
        end
    end, false)

    RegisterCommand('hudedit', function()
        if IsInAllowedHelicopter() then
            ToggleHUDEdit()
        end
    end, false)

    RegisterKeyMapping('polcam_groundlock', 'PolCam: Lock Camera to Ground', 'keyboard', Config.Keybinds.GroundLock or "T")
    RegisterCommand('polcam_groundlock', function()
        if PolCam.Active and ToggleGroundLock then
            ToggleGroundLock()
        end
    end, false)

    if Config and Config.Debug and Config.Debug.ToolsEnabled then
        local esStarted = GetResourceState('es_lib') == 'started'
        if not esStarted then

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

    if GetVehicleClass(vehicle) ~= 15 then return false end

    local model = GetEntityModel(vehicle)
    if not AllowedHeliHashes[model] then return false end

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

            local vehicleNetId = GetCurrentVehicleNetId()
            if vehicleNetId then
                TriggerServerEvent('polcam:requestCameraState', vehicleNetId)

                TriggerServerEvent('polcam:trackingRequestState', vehicleNetId)
                TriggerServerEvent('polcam:requestSyncedMarkers', vehicleNetId)

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

local _pendingSharedState = nil
local _lastStateSyncTime = 0
local STATE_SYNC_INTERVAL = (Config.Intervals and Config.Intervals.StateSync) or 200

RegisterNetEvent('polcam:receiveCameraState')
AddEventHandler('polcam:receiveCameraState', function(vehicleNetId, state)

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

    if vehicleNetId then
        TriggerServerEvent('polcam:trackingRequestState', vehicleNetId)
        TriggerServerEvent('polcam:requestSyncedMarkers', vehicleNetId)
    end

    ActivatePolCam(true, state)
end)

function ApplySharedCameraState(state)
    if not state then return end

    if not Config.SharedCamera or not Config.SharedCamera.Enabled then return end

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

    if state.visionMode and SetVisionMode then
        if Config.SharedCamera.RestoreVisionMode ~= false then
            PolCam.VisionMode = state.visionMode
            SetVisionMode(state.visionMode)
        end
    end

    if state.groundLockPoint then
        if Config.SharedCamera.RestoreGroundLock ~= false then
            PolCam.GroundLockPoint = vector3(
                state.groundLockPoint.x,
                state.groundLockPoint.y,
                state.groundLockPoint.z
            )

            SendNUIMessage({ action = "groundLockOn" })
        end
    end

    if state.lockedTargetNetId and state.lockedTargetType and not (PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget)) then
        if Config.SharedCamera.RestoreTrackedTarget ~= false then
            local entity = NetworkGetEntityFromNetworkId(state.lockedTargetNetId)
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                PolCam.LockedTarget = entity
                PolCam.LockedTargetType = state.lockedTargetType
                PolCam.TargetInfo = GetTargetInfo and GetTargetInfo(entity, state.lockedTargetType) or nil

                if PlayPolCamSound then
                    PlayPolCamSound("TargetLocked")
                end

                SendNUIMessage({
                    action = "targetLocked",
                    info = PolCam.TargetInfo
                })

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

function BuildCameraState()
    local state = {
        heading = PolCam.Heading,
        pitch = PolCam.Pitch,
        zoom = PolCam.Zoom,
        targetZoom = PolCam.TargetZoom,
        visionMode = PolCam.VisionMode
    }

    if PolCam.GroundLockPoint then
        state.groundLockPoint = {
            x = PolCam.GroundLockPoint.x,
            y = PolCam.GroundLockPoint.y,
            z = PolCam.GroundLockPoint.z
        }
    end

    if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        local netId = SafeGetNetworkId(PolCam.LockedTarget)
        if netId then
            state.lockedTargetNetId = netId
            state.lockedTargetType = PolCam.LockedTargetType
        end
    end

    return state
end

function CameraStateSyncLoop()

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

    if PolCam.Active and PolCam.Camera then return end

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

    PolCam.LockKeyHeld = false

    if OnCameraActivated_Tracking then
        OnCameraActivated_Tracking()
    end

    if sharedState then
        ApplySharedCameraState(sharedState)
    end

    CreatePolCamCamera()

    if sharedState then

        if PolCam.Camera and DoesCamExist(PolCam.Camera) then
            SetCamRot(PolCam.Camera, -PolCam.Pitch, 0.0, PolCam.Heading, 2)
            SetCamFov(PolCam.Camera, PolCam.FOV)
        end
    end

    if ClearCameraLabelCache then
        ClearCameraLabelCache()
    end

    if PlayPolCamSound then
        PlayPolCamSound("CameraOn")
    end

    if StartPolCamLoopSound then
        StartPolCamLoopSound("CCTVLoop")
    end

    SendNUIMessage({
        action = "show",
        visionMode = PolCam.VisionMode,
        highContrast = BuildPolCamHighContrastPayload(),
        trackColors = BuildPolCamTrackColorsPayload()
    })
    SetNuiFocus(false, false)

    CreateThread(CameraLoop)

    CreateThread(UIUpdateLoop)

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

    DestroyPolCamCamera()

    if ResetVision then
        ResetVision()
    end

    if OnCameraDeactivated_Tracking then
        OnCameraDeactivated_Tracking()
    end

    if OnCameraDeactivated then
        OnCameraDeactivated()
    elseif DeactivateSpotlight then
        DeactivateSpotlight()
    end

    if DeactivateOrbit then
        DeactivateOrbit()
    end

    if PlayPolCamSound then
        PlayPolCamSound("CameraOff")
    end

    if StopPolCamLoopSound then
        StopPolCamLoopSound("CCTVLoop")
    end

     DisplayRadar(true)

     SendNUIMessage({
         action = "hide"
     })

    if Config.Debug.Enabled then
        print("[PolCam] Camera deactivated")
    end
end

function ToggleUI()
    PolCam.UIVisible = not PolCam.UIVisible
    SendNUIMessage({
        action = "toggleUI",
        visible = PolCam.UIVisible
    })
end

function CameraLoop()
    while PolCam.Active do

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
        if not IsInAllowedHelicopter() then
            if ClearLock then
                ClearLock()
            end
            DeactivatePolCam()
            break
        end

        DisableControlActions()

        HandleCameraInput()

        HandleZoomInput()

        UpdateCameraPosition()

        if Config.Tracking and Config.Tracking.Enabled and UpdateTargeting then
            UpdateTargeting()
        end

        if UpdateStreetOverlay then
            UpdateStreetOverlay()
        end
        if RenderStreetOverlay then
            RenderStreetOverlay()
        end

        RenderCameraView()

        if RenderTargetingDebug then
            RenderTargetingDebug()
        end

        Wait(0)
    end
end

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

local UI_SPEED_MULTIPLIER = 1.94384
local UI_FEET_MULTIPLIER = 3.28084

local UI_FAST_INTERVAL = (Config.Intervals and Config.Intervals.UI and Config.Intervals.UI.Fast) or 50
local UI_MEDIUM_INTERVAL = (Config.Intervals and Config.Intervals.UI and Config.Intervals.UI.Medium) or 200
local UI_SLOW_INTERVAL = (Config.Intervals and Config.Intervals.UI and Config.Intervals.UI.Slow) or 1000

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

local LoadedPostals = nil
local PostalsLoaded = false

local function LoadPostalData()
    if PostalsLoaded then return end
    PostalsLoaded = true

    if not Config.Postal or not Config.Postal.Enabled then return end

    local postalFile = Config.Postal.PostalFile or "ocrp-postals.json"
    local resource = Config.Postal.ExportResource or "nearest-postal"

    local jsonData = LoadResourceFile(resource, postalFile)

    if not jsonData then

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

function GetPostalForCoords(coords)
    if not Config.Postal or not Config.Postal.Enabled or not coords then
        return nil
    end

    if not PostalsLoaded then
        LoadPostalData()
    end

    if not LoadedPostals or #LoadedPostals == 0 then
        return nil
    end

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

local CachedCameraLabel = nil
local CachedLabelVehicle = nil

function ClearCameraLabelCache()
    CachedCameraLabel = nil
    CachedLabelVehicle = nil
end

function GetCameraLabel(vehicle)
    if not Config.CameraLabels or not Config.CameraLabels.Enabled then
        return "LOS SANTOS POLICE DEPARTMENT"
    end

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

    local pitchMin = Config.Camera.MinVerticalAngle
    local pitchMax = Config.Camera.MaxVerticalAngle

    while PolCam.Active do
        local vehicle = PolCam.CurrentVehicle
        if vehicle and DoesEntityExist(vehicle) then
            local currentTime = GetGameTimer()
            local groundCoords = PolCam.GroundCoords
            local heliCoords = GetEntityCoords(vehicle)

            if currentTime - CachedUIData.lastSlowUpdate >= UI_SLOW_INTERVAL then
                CachedUIData.lastSlowUpdate = currentTime

                local streetHash, crossingHash = GetStreetNameAtCoord(groundCoords.x, groundCoords.y, groundCoords.z)
                local streetName = GetStreetNameFromHashKey(streetHash)
                local crossingName = GetStreetNameFromHashKey(crossingHash)

                if crossingName and crossingName ~= "" then
                    CachedUIData.streetName = streetName .. " / " .. crossingName
                else
                    CachedUIData.streetName = streetName or "UNKNOWN"
                end

                CachedUIData.postalCode = GetPostalForCoords(groundCoords)

                CachedUIData.lat = floor(groundCoords.x)
                CachedUIData.lng = floor(groundCoords.y)
            end

            if currentTime - CachedUIData.lastMediumUpdate >= UI_MEDIUM_INTERVAL then
                CachedUIData.lastMediumUpdate = currentTime

                local altitude = heliCoords.z

                local timeDiff = currentTime - PolCam.LastHeliTime
                if PolCam.LastHeliTime > 0 and timeDiff > 0 then
                    local zDiff = (altitude - PolCam.LastHeliZ) * UI_FEET_MULTIPLIER
                    CachedUIData.verticalSpeedFPM = floor((zDiff / (timeDiff * 0.001)) * 60)
                end
                PolCam.LastHeliZ = altitude
                PolCam.LastHeliTime = currentTime

                CachedUIData.altitude = floor(altitude * UI_FEET_MULTIPLIER)

                local found, groundZ = GetGroundZFor_3dCoord(groundCoords.x, groundCoords.y, groundCoords.z + 50.0, false)
                groundZ = found and groundZ or 0.0
                CachedUIData.groundElevation = floor(groundZ * UI_FEET_MULTIPLIER)
            end

            local heliSpeed = floor(GetEntitySpeed(vehicle) * UI_SPEED_MULTIPLIER)
            local heliHeading = floor(GetEntityHeading(vehicle))

            local cameraLabel = GetCameraLabel(vehicle)

            local hoverActive = IsHoverActive and IsHoverActive() or false
            local orbitActive = IsOrbitActive and IsOrbitActive() or false
            local groundLockActive = IsGroundLockActive and IsGroundLockActive() or false

            SendNUIMessage({
                action = "update",
                data = {

                    heading = floor(PolCam.Heading),
                    pitch = floor(PolCam.Pitch),
                    pitchMin = pitchMin,
                    pitchMax = pitchMax,
                    heliSpeed = heliSpeed,
                    heliHeading = heliHeading,
                    zoom = format("%.1fx", PolCam.Zoom),

                    altitude = CachedUIData.altitude,
                    verticalSpeed = CachedUIData.verticalSpeedFPM,
                    groundElevation = CachedUIData.groundElevation,

                    street = CachedUIData.streetName,
                    postal = CachedUIData.postalCode,
                    lat = CachedUIData.lat,
                    lng = CachedUIData.lng,

                    cameraLabel = cameraLabel,
                    visionMode = PolCam.VisionMode,
                    targetInfo = PolCam.TargetInfo,
                    hasTarget = PolCam.LockedTarget ~= nil,

                    hoverActive = hoverActive,
                    orbitActive = orbitActive,
                    groundLockActive = groundLockActive,
                    lrfStatus = (Config.UI and Config.UI.LRFStatus) or "READY",
                    systemStatus = (Config.UI and Config.UI.SystemStatus) or "NORM"
                }
            })

        end

        Wait(UI_FAST_INTERVAL)
    end
end

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

    if target and DoesEntityExist(target) then

        if UpdateLockedTargetInfo then
            UpdateLockedTargetInfo()
        end
    end

    local targetInfo = PolCam.TargetInfo

    if not targetInfo and not hoverActive then
        SendNUIMessage({ action = "hidePilotHUD" })
        return
    end

    local currentTime = GetGameTimer()
    local coords = targetInfo and targetInfo.coords or nil

    if currentTime - CachedPilotHUD.lastUpdate >= 1000 then
        CachedPilotHUD.lastUpdate = currentTime

        if coords then
            local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
            local streetName = GetStreetNameFromHashKey(streetHash)
            local crossingName = GetStreetNameFromHashKey(crossingHash)
            if crossingName and crossingName ~= "" then
                CachedPilotHUD.street = streetName .. " / " .. crossingName
            else
                CachedPilotHUD.street = streetName or "UNKNOWN"
            end

            CachedPilotHUD.postal = GetPostalForCoords(coords)
        end
    end

    local heading = (targetInfo and targetInfo.heading) or 0
    local headingNames = {"NORTH", "NORTH-EAST", "EAST", "SOUTH-EAST", "SOUTH", "SOUTH-WEST", "WEST", "NORTH-WEST"}
    local index = floor((heading + 22.5) / 45) % 8
    local headingText = format("%sBOUND (%d°)", headingNames[index + 1], heading)

    local targetId = "SYSTEM"
    local targetDetails = nil
    local hoverAltitude = nil

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
        if HeliControl and HeliControl.HoverAltitudeDisplay then
            hoverAltitude = HeliControl.HoverAltitudeDisplay
        else
            local heli = PolCam.CurrentVehicle
            if heli and DoesEntityExist(heli) then
                local coords = GetEntityCoords(heli)
                hoverAltitude = floor(coords.z * 3.28084) .. " FT"
            end
        end
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

            hoverActive = hoverActive,
            hoverAltitude = hoverAltitude,

            highContrast = BuildPolCamHighContrastPayload(),
            trackColors = BuildPolCamTrackColorsPayload()
        }
    })
end

CreateThread(function()
    while true do
        local sleep = 1000

        local inHeli = IsInAllowedHelicopter()

        if inHeli then
            sleep = 500

            local trackingHUDEnabled = Config.UI and Config.UI.PilotHUD and Config.UI.PilotHUD.Enabled

            local hasLock = PolCam.LockedTarget ~= nil

            local hoverActive = IsHoverActive and IsHoverActive() or false

            if trackingHUDEnabled and not PolCam.Active and (hasLock or hoverActive) then
                UpdatePilotHUD()
                sleep = 200
            else

                SendNUIMessage({ action = "hidePilotHUD" })
            end
        else

            SendNUIMessage({ action = "hidePilotHUD" })
            sleep = 2000
        end

        Wait(sleep)
    end
end)

local DISABLED_CONTROLS = {24, 25, 37, 47, 58, 263, 264, 75, 27, 81, 82, 99, 100, 157, 158, 159, 160, 161, 162, 163, 164, 165}
local DISABLED_CONTROLS_COUNT = #DISABLED_CONTROLS

function DisableControlActions()
    for i = 1, DISABLED_CONTROLS_COUNT do
        DisableControlAction(0, DISABLED_CONTROLS[i], true)
    end
end

function ConvertSpeed(speedMps, unit)
    if type(speedMps) ~= 'number' then return 0.0 end

    local targetUnit = type(unit) == 'string' and string.lower(unit) or 'mph'

    if targetUnit == 'kmh' or targetUnit == 'kph' then
        return speedMps * 3.6
    end

    if targetUnit == 'knots' or targetUnit == 'kts' then
        return speedMps * 1.943844
    end

    return speedMps * 2.236936
end

function ConvertAltitude(altitudeMeters, unit)
    if type(altitudeMeters) ~= 'number' then return 0.0 end

    local targetUnit = type(unit) == 'string' and string.lower(unit) or 'ft'
    if targetUnit == 'm' or targetUnit == 'meters' then
        return altitudeMeters
    end

    return altitudeMeters * 3.28084
end

function ConvertDistance(distanceMeters, unit)
    if type(distanceMeters) ~= 'number' then return 0.0 end

    local targetUnit = type(unit) == 'string' and string.lower(unit) or 'm'

    if targetUnit == 'ft' or targetUnit == 'feet' then
        return distanceMeters * 3.28084
    end

    if targetUnit == 'km' or targetUnit == 'kilometers' then
        return distanceMeters / 1000.0
    end

    if targetUnit == 'mi' or targetUnit == 'miles' then
        return distanceMeters / 1609.344
    end

    return distanceMeters
end

exports('ConvertSpeed', ConvertSpeed)
exports('ConvertAltitude', ConvertAltitude)
exports('ConvertDistance', ConvertDistance)

exports('IsPolCamActive', function()
    return PolCam.Active
end)

exports('GetCurrentTarget', function()
    return PolCam.LockedTarget, PolCam.TargetInfo
end)

exports('GetCameraHeading', function()
    return PolCam.Heading
end)

RegisterNetEvent('polcam:forceReleaseAll')
AddEventHandler('polcam:forceReleaseAll', function()
    DebugLog("[PolCam DEBUG] Received polcam:forceReleaseAll")

    PolCam.GroundLockPoint = nil

    if ForceDeactivateSpotlightLocal then
        ForceDeactivateSpotlightLocal()
    elseif SpotlightData then

        SpotlightData.Active = false
        SpotlightData.PersistentActive = false
        SpotlightData.LockedGroundPoint = nil
        SpotlightData.TrackingTarget = false
        SendNUIMessage({ action = "spotlightOff" })
    end

    SendNUIMessage({ action = "groundLockOff" })

    if Config.Debug and Config.Debug.Enabled then
        print("[PolCam] Force released camera/spotlight state (ownership transferred)")
    end
end)

local AIR_FEED_HEARTBEAT_INTERVAL_MS = 200
local AIR_FEED_HEARTBEAT_FORCE_MS = 500
local lastAirFeedHeartbeatAt = 0
local lastAirFeedHeartbeatState = nil

local function CoordsDiffer(a, b, epsilon)
    if type(a) ~= 'vector3' and type(a) ~= 'table' then return true end
    if type(b) ~= 'vector3' and type(b) ~= 'table' then return true end

    local ax = tonumber(a.x or a[1])
    local ay = tonumber(a.y or a[2])
    local az = tonumber(a.z or a[3])
    local bx = tonumber(b.x or b[1])
    local by = tonumber(b.y or b[2])
    local bz = tonumber(b.z or b[3])
    if not ax or not ay or not az or not bx or not by or not bz then
        return true
    end

    local delta = tonumber(epsilon) or 0.05
    return abs(ax - bx) > delta or abs(ay - by) > delta or abs(az - bz) > delta
end

local function RotationDiffer(a, b, epsilon)
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return true
    end

    local delta = tonumber(epsilon) or 0.05
    return abs((tonumber(a.x) or 0.0) - (tonumber(b.x) or 0.0)) > delta
        or abs((tonumber(a.y) or 0.0) - (tonumber(b.y) or 0.0)) > delta
        or abs((tonumber(a.z) or 0.0) - (tonumber(b.z) or 0.0)) > delta
end

local function BuildAirFeedHeartbeatPayload()
    local heli = PolCam.CurrentVehicle
    if not PolCam.Active or not heli or not DoesEntityExist(heli) then
        return nil
    end

    if not IsInAllowedHelicopter() then
        return nil
    end

    if not PolCam.Camera or not DoesCamExist(PolCam.Camera) then
        return nil
    end

    local heliNetId = SafeGetNetworkId(heli)
    if not heliNetId then
        return nil
    end

    local cameraCoords = PolCam.CameraCoords
    if (type(cameraCoords) ~= 'vector3' and type(cameraCoords) ~= 'table') or not tonumber(cameraCoords.x or cameraCoords[1]) then
        cameraCoords = GetEntityCoords(heli)
    end

    local targetNetId = nil
    local targetType = nil
    if PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        targetNetId = SafeGetNetworkId(PolCam.LockedTarget)
        targetType = PolCam.LockedTargetType
    end

    return {
        heliNetId = heliNetId,
        camCoords = {
            x = tonumber(cameraCoords.x or cameraCoords[1]) or 0.0,
            y = tonumber(cameraCoords.y or cameraCoords[2]) or 0.0,
            z = tonumber(cameraCoords.z or cameraCoords[3]) or 0.0,
        },
        camRot = GetCamRot(PolCam.Camera, 2),
        fov = PolCam.FOV,
        visionMode = PolCam.VisionMode,
        operatorSource = GetPlayerServerId(PlayerId()),
        targetNetId = targetNetId,
        targetType = targetType,
        label = GetCameraLabel(heli),
    }
end

local function ShouldSendAirFeedHeartbeat(payload, now)
    if type(payload) ~= 'table' then
        return false
    end

    if (now - lastAirFeedHeartbeatAt) >= AIR_FEED_HEARTBEAT_FORCE_MS then
        return true
    end

    local previous = lastAirFeedHeartbeatState
    if type(previous) ~= 'table' then
        return true
    end

    if tonumber(previous.heliNetId) ~= tonumber(payload.heliNetId) then
        return true
    end

    if CoordsDiffer(previous.camCoords, payload.camCoords, 0.03) then
        return true
    end

    if RotationDiffer(previous.camRot, payload.camRot, 0.05) then
        return true
    end

    if abs((tonumber(previous.fov) or 0.0) - (tonumber(payload.fov) or 0.0)) > 0.05 then
        return true
    end

    if tostring(previous.visionMode or '') ~= tostring(payload.visionMode or '') then
        return true
    end

    if tonumber(previous.targetNetId) ~= tonumber(payload.targetNetId) then
        return true
    end

    if tostring(previous.targetType or '') ~= tostring(payload.targetType or '') then
        return true
    end

    return false
end

local function SendAirFeedHeartbeat()
    local now = GetGameTimer()
    if (now - lastAirFeedHeartbeatAt) < AIR_FEED_HEARTBEAT_INTERVAL_MS then
        return
    end

    local payload = BuildAirFeedHeartbeatPayload()
    if not payload then
        return
    end

    if not ShouldSendAirFeedHeartbeat(payload, now) then
        return
    end

    lastAirFeedHeartbeatAt = now
    lastAirFeedHeartbeatState = payload
    TriggerServerEvent('polcam:feedHeartbeat', payload)
end

CreateThread(function()
    while true do
        if PolCam.Active then
            SendAirFeedHeartbeat()
            Wait(AIR_FEED_HEARTBEAT_INTERVAL_MS)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    RegisterPolCamSettingsIntegration()

    RegisterKeybinds()

    if InitializeSounds then
        InitializeSounds()
    end

    if Config.Debug.Enabled then
        print("[PolCam] Initialized successfully")
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= 'es_lib' then return end
    RegisterPolCamSettingsIntegration()
    ApplyPolCamClientSettingsFromEsLib()
    PushPolCamClientSettingsToNui()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if PolCam.Active then
        DeactivatePolCam()
    end
end)
