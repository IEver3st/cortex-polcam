--[[
    PolCam - Vision Modes Script
    Handles night vision effects
]]

-- ============================================================================
-- NATIVE CACHING (Performance Optimization)
-- ============================================================================
local SetNightvision = SetNightvision
local SetSeethrough = SetSeethrough
local ClearTimecycleModifier = ClearTimecycleModifier
local SetTimecycleModifier = SetTimecycleModifier
local SetTimecycleModifierStrength = SetTimecycleModifierStrength
local SendNUIMessage = SendNUIMessage
local ipairs = ipairs

-- ============================================================================
-- VISION MODE CYCLING
-- ============================================================================
local VisionModes = {"normal", "nightvision", "thermal"}
local VisionModeCount = #VisionModes
local CurrentModeIndex = 1

-- Create a lookup table for O(1) mode index lookup
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
    
    -- Play sound
    if PlayPolCamSound then
        PlayPolCamSound("VisionSwitch")
    end
    
    -- Update NUI
    SendNUIMessage({
        action = "visionMode",
        mode = PolCam.VisionMode
    })
    
    local debug = Config and Config.Debug
    if debug and debug.Enabled then
        print("[PolCam] Vision mode: " .. PolCam.VisionMode)
    end
end

-- ============================================================================
-- VISION MODE APPLICATION
-- ============================================================================
-- Cache last applied mode to avoid redundant native calls
local lastAppliedMode = nil

function ApplyVisionMode()
    local mode = PolCam.VisionMode
    
    -- Skip if mode hasn't changed (avoids redundant native calls every frame)
    if mode == lastAppliedMode then return end
    
    if mode == "nightvision" then
        ApplyNightVision()
    elseif mode == "thermal" then
        ApplyThermalVision()
    else
        -- Normal mode - ensure effects are disabled
        SetNightvision(false)
        SetSeethrough(false)
        ClearTimecycleModifier()
    end
    
    lastAppliedMode = mode
end

-- ============================================================================
-- NIGHT VISION (White Phosphor Style)
-- ============================================================================
function ApplyNightVision()
    if not (Config and Config.Vision and Config.Vision.NightVision and Config.Vision.NightVision.Enabled) then return end
    
    -- Enable night vision effect
    SetNightvision(true)
    SetSeethrough(false)
    
    -- Apply white phosphor style timecycle (desaturated with slight brightness boost)
    -- Using a combination that creates white/grey tones instead of green
    SetTimecycleModifier("heliGunCam")
    SetTimecycleModifierStrength(Config.Vision.NightVision.Intensity or 0.7)
end

-- ============================================================================
-- THERMAL VISION (White Hot Black/White)
-- ============================================================================
function ApplyThermalVision()
    if not (Config and Config.Vision and Config.Vision.Thermal and Config.Vision.Thermal.Enabled) then return end

    SetNightvision(false)
    SetSeethrough(true)

    -- Vanilla thermal: no extra palette tweaks or timecycle modifiers
    ClearTimecycleModifier()
end

-- ============================================================================
-- RESET VISION
-- ============================================================================
function ResetVision()
    SetNightvision(false)
    SetSeethrough(false)
    ClearTimecycleModifier()
    
    -- Reset to normal
    CurrentModeIndex = 1
    PolCam.VisionMode = "normal"
    lastAppliedMode = nil  -- Clear cache so next apply takes effect
end

-- ============================================================================
-- VISION MODE GETTER
-- ============================================================================
function GetCurrentVisionMode()
    return PolCam.VisionMode
end
