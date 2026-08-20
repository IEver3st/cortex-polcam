Config = {}
Config.AllowedHelicopters = { "polmav", "maverick" }
Config.AllowedSeats = { -1, 0, 1, 2 }
Config.InstantLock = false
Config.Lib = { Notify = 'auto' }

-- Optional Cortex MDT link. Local PolCam operation remains available when the
-- MDT is absent; only exported remote feeds are duty-gated while it is online.
Config.MDTIntegration = {
    Enabled = true,
    Resource = 'cortex_mdtsv',
    RequireOperatorOnDuty = true,
    RequirePilotOnDuty = true,
    FailClosedWhenUnavailable = false,
    DutyCacheMs = 250,
}

Config.Keybinds = {
    ToggleCamera  = "E",
    ToggleUI      = "H",
    ToggleStreets = "N",
    ToggleHover   = "X",
    ToggleOrbit   = "O",
    Spotlight     = "L",
    CycleSpotlightColor = "K",
    CycleVision   = "V",
    LockTarget    = "SPACE",
    GroundLock    = "T",
    PlaceMarker   = "B", -- changed from "G" to avoid conflict with Config.Rappel.Keybind
    DeleteMarker  = "DELETE",
    ToggleDebug   = "F10",
}

-- CAMERA SETTINGS
Config.Camera = {
    MinZoom = 1.0, MaxZoom = 30.0, DefaultZoom = 5.0, ZoomSpeed = 2.0, SmoothZoomSpeed = 8.0,
    DefaultFOV = 50.0, MinFOV = 2.0, MaxFOV = 70.0,
    RotationSpeed = 3.0, MaxVerticalAngle = 89.0, MinVerticalAngle = -30.0,
    ZoomSensitivityMinMultiplier = 0.20,
    CameraOffset = vector3(0.0, 2.5, -1.5),
    RenderDistance = 1000.0,
}

-- TRACKING SETTINGS
Config.Tracking = {
    Enabled = true, LockDurationMs = 1200,
    TrackVehicles = true, TrackPeds = true,
    TrackingSpeed = 12.0,
    DetectionBaseRadius = 3.0, DetectionScaling = 0.025, DetectionMaxRadius = 35.0,
    TargetingMaxDistanceVehicles = 1000.0, TargetingMaxDistancePeds = 1000.0,
    UsePoolFallbackTargeting = true, PlateVisibilityAngle = 45.0,
    OcclusionEnabled = true,
    OcclusionGracePeriodMs = 3000,
    OcclusionCheckIntervalMs = 150, 
    OcclusionNearTargetTolerance = 2.0,
}


-- UI SETTINGS
Config.UI = {
    PilotHUD = { Enabled = true, Position = "top-right", ShowStreet = true, ShowHeading = true },
    TargetLabel = {
        Enabled = true, ShowWhenCameraActive = true, ShowWhenCameraOff = true,
        ShowWhilePersistent = true, MaxDistance = 1500.0,
        HeightOffsetPed = 1.0, HeightOffsetVehicle = 1.6,
        LabelSmoothingSpeed = 12.0,
        Color = {0, 255, 0, 230},
        FollowHighContrast = true,
    },
    HighContrast = { Enabled = true, Theme = "green" },
    LRFStatus = "READY",
    SystemStatus = "NORM",
}

-- VISION SETTINGS
Config.Vision = { DefaultMode = "normal", NightVision = { Enabled = true, Intensity = 0.7 }, Thermal = { Enabled = true } }

-- CAMERA LABELS
Config.CameraLabels = {
    Enabled = true,
    DefaultLabel = "LOS SANTOS POLICE DEPARTMENT",
    ModelLabels = {
        ["polmav"] = "LOS SANTOS POLICE DEPARTMENT",
        ["gsd11bell"] = "BLAINE COUNTY SHERIFF'S OFFICE",
        ["maverick"] = "SAN ANDREAS STATE POLICE",
    },
    LiveryLabels = {
        ["polmav"] = { [0] = "LSPD", [1] = "LSPD AIR-2", [2] = "VINEWOOD AIR UNIT" },
        ["gsd11bell"] = { [0] = "SAN ANDREAS STATE TROOPER", [1] = "LSPD AIR-2", [2] = "VINEWOOD AIR UNIT" },
    },
}

-- FEATURES
Config.Spotlight = {
    Enabled = true, SyncWithCamera = true, Brightness = 10.0, Range = 400.0, Radius = 10.0,
    Color = {170, 185, 255},
    NetSync = { PositionIntervalMs = 150, BroadcastIntervalMs = 150, MinMoveDistance = 0.25, SmoothingSpeed = 12.0 }
}

Config.POI = { Enabled = true, MaxPOIs = 10, ExpiryTime = 300, SyncToOthers = true }

Config.Rappel = {
    Enabled = true, Keybind = "G", MinAltitude = 15, MaxAltitude = 150,
    AllowedSeats = {1, 2}, SyncEnabled = true,
    AllowedHashes = {}, DisableHashes = {}
}

Config.HeliControl = {
    HoverEnabled = true, OrbitEnabled = true, MinOrbitRadius = 30.0,
    HoverMaxDrift = 0.45, HoverZStiffness = 2.0, HoverBrakeFactor = 1.0,
    MinAirborneHeight = 2.0,
    OrbitRadialStiffness = 1.2,
    OrbitRadialDamping = 0.6,
    OrbitVelocitySmoothing = 2.2,
    OrbitMinTangentScale = 0.55,
    OrbitRadialMaxCorrection = 12.0,
    OrbitMaxAccel = 8.0,
    OrbitCenterLerp = 2.0,
    OrbitHeadingSmoothing = 2.2,
    OrbitSwayAmplitude = 1.6,
    OrbitSwayFrequency = 0.55,
    OrbitSwayTangentBias = 1.25,
    OrbitSwayRadialBias = 0.9,
    OrbitSwayGustAmplitude = 0.85,
    OrbitSwayGustFrequency = 0.22,
    MinEngineHealth = 100.0, MinBodyHealth = 100.0, AvionicsDamagedMessage = true,
}

Config.SharedCamera = {
    Enabled = true, SyncIntervalMs = 200, StateTimeoutMs = 300000,
    RestoreTrackedTarget = true, RestoreGroundLock = true, RestoreVisionMode = true,
}

-- LOCALIZATION & DATA
Config.Postal = { Enabled = true, ExportResource = "nearest-postal", PostalFile = "ocrp-postals.json" }

-- SOUNDS
Config.Sounds = {
    Enabled = true,
    CameraOn = { audioBank = "DLC_HEI_HACKER_SOUNDS", audioName = "Hacker_Keypad_Submit_Success" },
    CameraOff = { audioBank = "DLC_HEI_HACKER_SOUNDS", audioName = "Hacker_Keypad_Error" },
    CameraTransitionIn = { audioBank = "PLAYER_SWITCH_CUSTOM_SOUNDSET", audioName = "Short_Transition_In" },
    CameraTransitionOut = { audioBank = "PLAYER_SWITCH_CUSTOM_SOUNDSET", audioName = "1st_Person_Transition" },
    ZoomIn = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_CLICK" },
    ZoomOut = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_CLICK" },
    VisionSwitch = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "PICK_UP_SOUND" },
    TargetLocked = { audioBank = "DLC_GR_MOC_Computer_Sounds", audioName = "Select_Mission_Launch" },
    TargetLost = { audioBank = "GTAO_FM_Events_Soundset", audioName = "OOB_Cancel" },
    MarkerPlaced = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "WAYPOINT_SET" },
    SpotlightOn = { audioBank = "DLC_XM_FACILITY_AMBIENT_SOUNDS", audioName = "Activate_Privacy_Glass" },
    SpotlightOff = { audioBank = "DLC_XM_FACILITY_AMBIENT_SOUNDS", audioName = "Deactivate_Privacy_Glass" },
    HoverOn = { audioBank = "DLC_GR_Steal_Railguns_Sounds", audioName = "Hack_Success" }, 
    HoverOff = { audioBank = "DLC_Biker_Computer_Sounds", audioName = "Exit" },
    OrbitOn = { audioBank = "DLC_sum20_Business_Battle_AC_Sounds", audioName = "Hack_Success" },
    OrbitOff = { audioBank = "DLC_sum20_Business_Battle_AC_Sounds", audioName = "Hack_Failure" },
    GroundLockOn = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_SUCCESS" },
    GroundLockOff = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_FAILURE" },
    Click = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "SELECT" },
    Confirm = { audioBank = "DLC_HEI_HACKER_SOUNDS", audioName = "SCANNED_ID_OK" },
    Alert = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "ERROR" },
    SystemAlert = { audioBank = "DLC_HEIST_BIOLAB_PREP_SOUNDS", audioName = "Power_Down" },
    CCTVLoop = { audioBank = "DLC_Arena_CCTV_SOUNDSET", audioName = "Background" },
}

Config.EsHud = {
    Enabled = true,
    AutoDetect = true,
    ShowAircraftHudForPilot = false,
    FallbackAircraftHud = false,
}

Config.Debug = {
    Enabled = false,
    ToolsEnabled = false,
    ShowRaycast = true, ShowDetectionRadius = false, ShowHitPoint = false,
    ShowTargetBox = false, ShowDebugPanel = false,
    ShowDistanceInfo = false, ShowRadiusInfo = false, ShowEntityInfo = false,
    ShowScanDetails = false, ShowSharedState = false,
    LogEvents = false, LogScans = false,
    RaycastColor = {0, 255, 255, 200}, DetectionColor = {255, 255, 0, 100}, HitPointColor = {0, 255, 0, 255},
    TargetBoxColor = {255, 128, 0, 200}
}

Config.Intervals = {
    StateSync = 200,
    ClaimTimeout = 5000,
    UI = {
        Fast = 50,
        Medium = 200,
        Slow = 1000
    },
    Heartbeat = {
        BaseCheck = 1000,
        PilotHUDUpdate = 1000,
        FastUpdate = 200
    },
    GroundZCheckOffset = 50.0
}
