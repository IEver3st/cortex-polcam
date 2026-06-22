local SetNightvision = SetNightvision
local SetSeethrough = SetSeethrough
local ClearTimecycleModifier = ClearTimecycleModifier
local SetTimecycleModifier = SetTimecycleModifier
local SetTimecycleModifierStrength = SetTimecycleModifierStrength
local SendNUIMessage = SendNUIMessage
local ipairs = ipairs

local VisionModes = {"normal", "nightvision", "thermal"}
local VisionModeCount = #VisionModes
local CurrentModeIndex = 1

local VisionModeIndexLookup = {}
for i, mode in ipairs(VisionModes) do
    VisionModeIndexLookup[mode] = i
end

local function SyncCurrentVisionIndex()
    if PolCam and PolCam.VisionMode then
        local idx = VisionModeIndexLookup[PolCam.VisionMode]
        if idx then
            CurrentModeIndex = idx
            return
        end
    end

    CurrentModeIndex = 1
    if PolCam then
        PolCam.VisionMode = VisionModes[1]
    end
end

function CycleVisionMode()
    SyncCurrentVisionIndex()

    CurrentModeIndex = CurrentModeIndex + 1
    if CurrentModeIndex > VisionModeCount then
        CurrentModeIndex = 1
    end

    PolCam.VisionMode = VisionModes[CurrentModeIndex]

    if PlayPolCamSound then
        PlayPolCamSound("VisionSwitch")
    end

    SendNUIMessage({
        action = "visionMode",
        mode = PolCam.VisionMode
    })

    local debug = Config and Config.Debug
    if debug and debug.Enabled then
        print("[PolCam] Vision mode: " .. PolCam.VisionMode)
    end
end

local lastAppliedMode = nil

function ApplyVisionMode()
    local mode = PolCam.VisionMode

    if mode == lastAppliedMode then return end

    if mode == "nightvision" then
        ApplyNightVision()
    elseif mode == "thermal" then
        ApplyThermalVision()
    else

        SetNightvision(false)
        SetSeethrough(false)
        ClearTimecycleModifier()
    end

    lastAppliedMode = mode
end

function ApplyNightVision()
    if not (Config and Config.Vision and Config.Vision.NightVision and Config.Vision.NightVision.Enabled) then return end

    SetNightvision(true)
    SetSeethrough(false)

    SetTimecycleModifier("heliGunCam")
    SetTimecycleModifierStrength(Config.Vision.NightVision.Intensity or 0.7)
end

function ApplyThermalVision()
    if not (Config and Config.Vision and Config.Vision.Thermal and Config.Vision.Thermal.Enabled) then return end

    SetNightvision(false)
    SetSeethrough(true)

    ClearTimecycleModifier()
end

function ResetVision()
    SetNightvision(false)
    SetSeethrough(false)
    ClearTimecycleModifier()

    CurrentModeIndex = 1
    PolCam.VisionMode = "normal"
    lastAppliedMode = nil
end

function GetCurrentVisionMode()
    return PolCam.VisionMode
end
