--[[
    PolCam - Sound System Script
    Handles audio using GTA V native sounds
]]

-- ============================================================================
-- NATIVE CACHING (Performance Optimization)
-- ============================================================================
local RequestAmbientAudioBank = RequestAmbientAudioBank
local PlaySoundFrontend = PlaySoundFrontend
local GetSoundId = GetSoundId
local StopSound = StopSound
local ReleaseSoundId = ReleaseSoundId
local GetCurrentResourceName = GetCurrentResourceName
local CreateThread = CreateThread
local Wait = Wait
local type = type
local pairs = pairs
local tostring = tostring

-- ============================================================================
-- SOUND INITIALIZATION
-- ============================================================================
local SoundsLoaded = false
local LoopingSounds = {}

function InitializeSounds()
    if not Config.Sounds.Enabled then return end
    
    -- Request audio banks
    -- Always preload common sets used by UI sounds
    RequestAmbientAudioBank("HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    RequestAmbientAudioBank("HUD_AWARDS", false)
    
    -- Preload all soundsets referenced in Config.Sounds (if any)
    if type(Config.Sounds) == "table" then
        local requested = {}
        for k, v in pairs(Config.Sounds) do
            if type(v) == "table" then
                local bank = v.audioBank
                if type(bank) == "string" and bank ~= "" and not requested[bank] then
                    requested[bank] = true
                    RequestAmbientAudioBank(bank, false)
                end
            end
        end
    end
    
    -- Backwards-compat: banks used by the legacy hardcoded sound library below
    RequestAmbientAudioBank("DLC_HEI_HACKER_SOUNDS", false)
    RequestAmbientAudioBank("DLC_HEIST_HACKING_SNAKE_SOUNDS", false)
    RequestAmbientAudioBank("DLC_HEIST_BIOLAB_PREP_SOUNDS", false)
    RequestAmbientAudioBank("DLC_ARENA_TRACK_SOUNDSET", false)
    
    CreateThread(function()
        Wait(1000)
        SoundsLoaded = true
        if Config.Debug.Enabled then
            print("[PolCam] Sound banks loaded")
        end
    end)
end

-- ============================================================================
-- PLAY SOUND
-- ============================================================================
function PlayPolCamSound(soundName)
    if not Config.Sounds.Enabled then return end
    
    -- Prefer Config.Sounds entries (audioName/audioBank)
    local cfg = Config.Sounds and Config.Sounds[soundName]
    if cfg == false then
        return
    end
    if type(cfg) == "table" then
        local audioName = cfg.audioName
        local audioBank = cfg.audioBank
        if type(audioName) == "string" and audioName ~= "" and type(audioBank) == "string" and audioBank ~= "" then
            PlaySoundFrontend(-1, audioName, audioBank, true)
            return
        end
    end
    
    -- Sound library
    local sounds = {
        -- Camera sounds
        CameraOn = {name = "Hacker_Keypad_Submit_Success", bank = "DLC_HEI_HACKER_SOUNDS"},
        CameraOff = {name = "Hacker_Keypad_Error", bank = "DLC_HEI_HACKER_SOUNDS"},
        CameraTransitionIn = {name = "CONFIRM_BEEP", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        CameraTransitionOut = {name = "BACK", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        
        -- Zoom sounds
        ZoomIn = {name = "HACKING_CLICK", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS"},
        ZoomOut = {name = "HACKING_CLICK", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS"},
        
        -- Targeting sounds
        TargetLocked = {name = "SCANNED_ID_OK", bank = "DLC_HEI_HACKER_SOUNDS"},
        TargetLost = {name = "HACKING_CLICK_BAD", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS"},
        
        -- Vision sounds
        VisionSwitch = {name = "PICK_UP_SOUND", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        
        -- Marker sounds
        MarkerPlaced = {name = "WAYPOINT_SET", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        
        -- Spotlight sounds
        SpotlightOn = {name = "SELECT", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        SpotlightOff = {name = "BACK", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        
        -- Hover/Orbit sounds
        HoverOn = {name = "FLIGHT_SCHOOL_LESSON_PASS", bank = "HUD_AWARDS"},
        HoverOff = {name = "BACK", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        OrbitOn = {name = "SELECT", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        OrbitOff = {name = "BACK", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        
        -- Ground lock
        GroundLockOn = {name = "HACKING_SUCCESS", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS"},
        GroundLockOff = {name = "HACKING_FAILURE", bank = "DLC_HEIST_HACKING_SNAKE_SOUNDS"},
        
        -- UI sounds
        Click = {name = "SELECT", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        Confirm = {name = "SCANNED_ID_OK", bank = "DLC_HEI_HACKER_SOUNDS"},
        Alert = {name = "ERROR", bank = "HUD_FRONTEND_DEFAULT_SOUNDSET"},
        SystemAlert = {name = "Power_Down", bank = "DLC_HEIST_BIOLAB_PREP_SOUNDS"}
    }
    
    local sound = sounds[soundName]
    if not sound then
        if Config.Debug.Enabled then
            print("[PolCam] Sound not found: " .. tostring(soundName))
        end
        return
    end
    
    PlaySoundFrontend(-1, sound.name, sound.bank, true)
end

-- ============================================================================
-- LOOPING FRONTEND SOUNDS
-- ============================================================================
function StartPolCamLoopSound(loopName)
    if not Config.Sounds.Enabled then return end

    local cfg = Config.Sounds and Config.Sounds[loopName]
    if cfg == false then
        return
    end
    if type(cfg) ~= "table" then
        return
    end

    local audioName = cfg.audioName
    local audioBank = cfg.audioBank
    if type(audioName) ~= "string" or audioName == "" or type(audioBank) ~= "string" or audioBank == "" then
        return
    end

    if LoopingSounds[loopName] then
        return
    end

    local soundId = GetSoundId()
    LoopingSounds[loopName] = soundId

    PlaySoundFrontend(soundId, audioName, audioBank, true)
end

function StopPolCamLoopSound(loopName)
    local soundId = LoopingSounds[loopName]
    if not soundId then return end

    StopSound(soundId)
    ReleaseSoundId(soundId)
    LoopingSounds[loopName] = nil
end

-- ============================================================================
-- CLEANUP
-- ============================================================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for loopName, _ in pairs(LoopingSounds) do
        StopPolCamLoopSound(loopName)
    end
end)
