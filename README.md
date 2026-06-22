# Cortex PolCam

A FLIR-style police helicopter camera system for FiveM with target tracking, spotlight, hover/orbit autopilot, rappelling, and multi-crew synchronization.

## Dependencies

| Resource | Required | Notes |
|----------|----------|-------|
| **es_lib** | **Yes** | Required for notifications, radial progress, and debug tools. Must be started before polcam. |
| **es_hud** | Optional | Auto-detected. Hides the player HUD while the camera is active and optionally forces the aircraft HUD for the pilot. |
| **nearest-postal** | Optional | Provides postal code data for the camera overlay. |

## es_hud Compatibility

PolCam integrates with es_hud to manage HUD visibility while the camera is active. When the camera activates, it calls `exports.es_hud:hideHud('polcam')` to hide the player HUD, and `exports.es_hud:showHud('polcam')` when deactivated. es_hud recognizes `'polcam'` as a visibility reason and handles it accordingly.

The pilot can optionally have the aircraft HUD forced on via `exports.es_hud:setForceAircraftHud()`.

Configure this behavior in `config.lua`:

```lua
Config.EsHud = {
    Enabled = true,                  -- Enable es_hud integration
    AutoDetect = true,               -- Auto-detect if es_hud is running
    ShowAircraftHudForPilot = false,  -- Force aircraft HUD for the pilot while camera is active
    FallbackAircraftHud = false,      -- Use polcam's built-in aircraft HUD if es_hud is unavailable
}
```

## es_lib Integration

es_lib is used for notifications, the target lock radial progress, and debug tooling.

```lua
Config.Lib = {
    Notify = 'auto'  -- 'auto' uses es_lib for notifications
}
```

When `Config.Debug.ToolsEnabled` is `true`, es_lib provides the debug panel and debug menu (bound to F10). If es_lib is not running, all debug features are automatically disabled.

## Exports

### Client Exports

| Export | Returns | Description |
|--------|---------|-------------|
| `IsPolCamActive()` | `boolean` | Whether the camera is currently active |
| `GetCurrentTarget()` | `entity, table` | The locked target entity and target info table |
| `GetCameraHeading()` | `number` | Current camera heading in degrees |
| `IsRappelAvailable()` | `boolean` | Whether rappel conditions are met (altitude, seat, helicopter) |
| `IsRappeling()` | `boolean` | Whether a rappel is currently in progress |
| `StartRappel()` | — | Triggers a rappel from the helicopter |
| `ConvertSpeed(speed)` | `number` | Converts a speed value to display units |
| `ConvertAltitude(altitude)` | `number` | Converts an altitude value to display units |
| `ConvertDistance(distance)` | `number` | Converts a distance value to display units |
| `OpenPolCamDebugMenu()` | — | Opens the debug menu (requires `Config.Debug.ToolsEnabled = true`) |

### Server Exports

| Export | Returns | Description |
|--------|---------|-------------|
| `GetActiveAirFeeds()` | `table` | Returns a list of all active air feed entries (camera operators currently online) |
| `GetAirFeedById(feedId)` | `table` | Returns a single air feed by its feed ID (e.g. `"air:123"`) |
| `GetTrackedDatalinkTargets()` | `table` | Returns all currently tracked vehicle targets across all active air feeds |

## Configuration

All settings are in `config.lua`.

### Core

```lua
Config.AllowedHelicopters = { "polmav", "maverick" }
Config.AllowedSeats = { -1, 0, 1, 2 }    -- Seats that can activate the camera (-1 = driver)
Config.InstantLock = false                 -- false = uses es_lib radial progress for lock acquisition
```

### Keybinds

```lua
Config.Keybinds = {
    ToggleCamera  = "E",       -- Activate/deactivate camera
    ToggleUI      = "H",       -- Toggle camera UI overlay
    ToggleStreets = "N",       -- Toggle street name overlay
    ToggleHover   = "X",       -- Toggle hover autopilot
    ToggleOrbit   = "O",       -- Toggle orbit autopilot
    Spotlight     = "L",       -- Toggle spotlight
    CycleSpotlightColor = "K", -- Cycle spotlight color
    CycleVision   = "V",       -- Cycle vision mode (normal/NV/thermal)
    LockTarget    = "SPACE",   -- Lock/unlock target
    GroundLock    = "T",       -- Lock camera to ground position
    PlaceMarker   = "G",       -- Place a POI marker
    DeleteMarker  = "DELETE",  -- Delete nearest marker
    ToggleDebug   = "F10",     -- Toggle debug menu (requires ToolsEnabled)
}
```

### Camera

```lua
Config.Camera = {
    MinZoom = 1.0,              -- Minimum zoom level
    MaxZoom = 30.0,             -- Maximum zoom level
    DefaultZoom = 5.0,          -- Starting zoom level
    ZoomSpeed = 2.0,            -- Zoom input speed
    SmoothZoomSpeed = 8.0,      -- Zoom interpolation speed
    DefaultFOV = 50.0,          -- Default field of view
    MinFOV = 2.0,               -- Minimum FOV (max zoom)
    MaxFOV = 70.0,              -- Maximum FOV (min zoom)
    RotationSpeed = 3.0,        -- Camera rotation speed
    MaxVerticalAngle = 89.0,    -- Max upward angle
    MinVerticalAngle = -30.0,   -- Max downward angle
    ZoomSensitivityMinMultiplier = 0.20,
    CameraOffset = vector3(0.0, 2.5, -1.5),
    RenderDistance = 1000.0,    -- Max render distance
}
```

### Tracking

```lua
Config.Tracking = {
    Enabled = true,
    LockDurationMs = 1200,                -- Lock acquisition time (when InstantLock = false)
    TrackVehicles = true,                  -- Allow locking vehicles
    TrackPeds = true,                      -- Allow locking pedestrians
    TrackingSpeed = 12.0,                  -- Camera follow speed when locked
    DetectionBaseRadius = 3.0,             -- Base detection radius
    DetectionScaling = 0.025,              -- Detection radius scaling with distance
    DetectionMaxRadius = 35.0,             -- Max detection radius
    TargetingMaxDistanceVehicles = 1000.0, -- Max lock range for vehicles
    TargetingMaxDistancePeds = 1000.0,     -- Max lock range for peds
    UsePoolFallbackTargeting = true,       -- Fallback to entity pool scanning
    PlateVisibilityAngle = 45.0,           -- Angle threshold for plate readability
    OcclusionEnabled = true,               -- Drop lock when target goes behind objects
    OcclusionGracePeriodMs = 3000,         -- Grace period before dropping occluded target
    OcclusionCheckIntervalMs = 150,        -- How often to check occlusion
    OcclusionNearTargetTolerance = 2.0,    -- Tolerance for near-target occlusion checks
}
```

### UI

```lua
Config.UI = {
    PilotHUD = {
        Enabled = true,
        Position = "top-right",  -- Pilot HUD position
        ShowStreet = true,       -- Show street name
        ShowHeading = true,      -- Show heading
    },
    TargetLabel = {
        Enabled = true,
        ShowWhenCameraActive = true,   -- Show target label while camera is on
        ShowWhenCameraOff = true,      -- Show target label after camera is off (persistent tracking)
        ShowWhilePersistent = true,    -- Show during persistent tracking
        MaxDistance = 1500.0,          -- Max render distance for labels
        HeightOffsetPed = 1.0,         -- Label height offset for peds
        HeightOffsetVehicle = 1.6,     -- Label height offset for vehicles
        LabelSmoothingSpeed = 12.0,
        Color = {0, 255, 0, 230},      -- RGBA (overridden if FollowHighContrast is true)
        FollowHighContrast = true,     -- Match label color to high contrast theme
    },
    HighContrast = {
        Enabled = true,
        Theme = "green",  -- Options: green, black, orange, red, purple, blue, pink, or hex (e.g. "#FF00FF")
    },
    LRFStatus = "READY",       -- Laser range finder status text shown on HUD
    SystemStatus = "NORM",     -- System status text shown on HUD
}
```

### Vision Modes

```lua
Config.Vision = {
    DefaultMode = "normal",                       -- Starting vision mode
    NightVision = { Enabled = true, Intensity = 0.7 },
    Thermal = { Enabled = true },
}
```

### Camera Labels

Per-model and per-livery agency labels displayed on the camera overlay.

```lua
Config.CameraLabels = {
    Enabled = true,
    DefaultLabel = "LOS SANTOS POLICE DEPARTMENT",
    ModelLabels = {
        ["polmav"]    = "LOS SANTOS POLICE DEPARTMENT",
        ["gsd11bell"] = "BLAINE COUNTY SHERIFF'S OFFICE",
        ["maverick"]  = "SAN ANDREAS STATE POLICE",
    },
    LiveryLabels = {
        ["polmav"] = {
            [0] = "LSPD",
            [1] = "LSPD AIR-2",
            [2] = "VINEWOOD AIR UNIT",
        },
        ["gsd11bell"] = {
            [0] = "SAN ANDREAS STATE TROOPER",
            [1] = "LSPD AIR-2",
            [2] = "VINEWOOD AIR UNIT",
        },
    },
}
```

### Spotlight

```lua
Config.Spotlight = {
    Enabled = true,
    SyncWithCamera = true,    -- Spotlight follows camera direction
    Brightness = 10.0,
    Range = 400.0,
    Radius = 10.0,
    Color = {170, 185, 255},  -- RGB
    NetSync = {
        PositionIntervalMs = 150,
        BroadcastIntervalMs = 150,
        MinMoveDistance = 0.25,
        SmoothingSpeed = 12.0,
    },
}
```

### Points of Interest

```lua
Config.POI = {
    Enabled = true,
    MaxPOIs = 10,           -- Max active POI markers
    ExpiryTime = 300,       -- POI lifetime in seconds
    SyncToOthers = true,    -- Sync POIs to other players
}
```

### Rappel

```lua
Config.Rappel = {
    Enabled = true,
    Keybind = "G",
    MinAltitude = 15,        -- Minimum altitude in feet
    MaxAltitude = 150,       -- Maximum altitude in feet
    AllowedSeats = {1, 2},   -- Seats that can rappel
    SyncEnabled = true,      -- Sync rappel to other players
    AllowedHashes = {},      -- Whitelist specific vehicle hashes (empty = all allowed helicopters)
    DisableHashes = {},      -- Blacklist specific vehicle hashes
}
```

### Helicopter Control

```lua
Config.HeliControl = {
    HoverEnabled = true,              -- Enable hover autopilot
    OrbitEnabled = true,              -- Enable orbit autopilot
    MinOrbitRadius = 30.0,            -- Minimum orbit radius
    HoverMaxDrift = 0.45,
    HoverZStiffness = 2.0,
    HoverBrakeFactor = 1.0,
    MinAirborneHeight = 2.0,
    OrbitRadialStiffness = 1.2,
    OrbitRadialDamping = 0.6,
    OrbitVelocitySmoothing = 2.2,
    OrbitMinTangentScale = 0.55,
    OrbitRadialMaxCorrection = 12.0,
    OrbitMaxAccel = 8.0,
    OrbitCenterLerp = 2.0,
    OrbitHeadingSmoothing = 2.2,
    OrbitSwayAmplitude = 1.6,         -- Turbulence/sway amplitude
    OrbitSwayFrequency = 0.55,
    OrbitSwayTangentBias = 1.25,
    OrbitSwayRadialBias = 0.9,
    OrbitSwayGustAmplitude = 0.85,
    OrbitSwayGustFrequency = 0.22,
    MinEngineHealth = 100.0,          -- Minimum engine health for autopilot
    MinBodyHealth = 100.0,            -- Minimum body health for autopilot
    AvionicsDamagedMessage = true,    -- Notify when avionics are damaged
}
```

### Shared Camera

Multi-crew camera state synchronization.

```lua
Config.SharedCamera = {
    Enabled = true,
    SyncIntervalMs = 200,              -- State sync interval
    StateTimeoutMs = 300000,           -- State timeout (5 minutes)
    RestoreTrackedTarget = true,       -- Restore locked target on camera takeover
    RestoreGroundLock = true,          -- Restore ground lock on takeover
    RestoreVisionMode = true,          -- Restore vision mode on takeover
}
```

### Postal Data

```lua
Config.Postal = {
    Enabled = true,
    ExportResource = "nearest-postal",        -- Resource containing postal data
    PostalFile = "ocrp-postals.json",         -- Postal JSON file name
}
```

### Sounds

All sounds use GTA native audio banks. Set `Config.Sounds.Enabled = false` to disable all sounds.

```lua
Config.Sounds = {
    Enabled = true,
    CameraOn           = { audioBank = "DLC_HEI_HACKER_SOUNDS", audioName = "Hacker_Keypad_Submit_Success" },
    CameraOff          = { audioBank = "DLC_HEI_HACKER_SOUNDS", audioName = "Hacker_Keypad_Error" },
    CameraTransitionIn = { audioBank = "PLAYER_SWITCH_CUSTOM_SOUNDSET", audioName = "Short_Transition_In" },
    CameraTransitionOut= { audioBank = "PLAYER_SWITCH_CUSTOM_SOUNDSET", audioName = "1st_Person_Transition" },
    ZoomIn             = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_CLICK" },
    ZoomOut            = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_CLICK" },
    VisionSwitch       = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "PICK_UP_SOUND" },
    TargetLocked       = { audioBank = "DLC_GR_MOC_Computer_Sounds", audioName = "Select_Mission_Launch" },
    TargetLost         = { audioBank = "GTAO_FM_Events_Soundset", audioName = "OOB_Cancel" },
    MarkerPlaced       = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "WAYPOINT_SET" },
    SpotlightOn        = { audioBank = "DLC_XM_FACILITY_AMBIENT_SOUNDS", audioName = "Activate_Privacy_Glass" },
    SpotlightOff       = { audioBank = "DLC_XM_FACILITY_AMBIENT_SOUNDS", audioName = "Deactivate_Privacy_Glass" },
    HoverOn            = { audioBank = "DLC_GR_Steal_Railguns_Sounds", audioName = "Hack_Success" },
    HoverOff           = { audioBank = "DLC_Biker_Computer_Sounds", audioName = "Exit" },
    OrbitOn            = { audioBank = "DLC_sum20_Business_Battle_AC_Sounds", audioName = "Hack_Success" },
    OrbitOff           = { audioBank = "DLC_sum20_Business_Battle_AC_Sounds", audioName = "Hack_Failure" },
    GroundLockOn       = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_SUCCESS" },
    GroundLockOff      = { audioBank = "DLC_HEIST_HACKING_SNAKE_SOUNDS", audioName = "HACKING_FAILURE" },
    Click              = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "SELECT" },
    Confirm            = { audioBank = "DLC_HEI_HACKER_SOUNDS", audioName = "SCANNED_ID_OK" },
    Alert              = { audioBank = "HUD_FRONTEND_DEFAULT_SOUNDSET", audioName = "ERROR" },
    SystemAlert        = { audioBank = "DLC_HEIST_BIOLAB_PREP_SOUNDS", audioName = "Power_Down" },
    CCTVLoop           = { audioBank = "DLC_Arena_CCTV_SOUNDSET", audioName = "Background" },
}
```

### Debug

```lua
Config.Debug = {
    Enabled = false,              -- Enable debug visualizations
    ToolsEnabled = false,         -- Enable debug menu and keybind (requires es_lib)
    ShowRaycast = true,           -- Draw raycast line
    ShowDetectionRadius = false,  -- Draw detection sphere
    ShowHitPoint = false,         -- Draw hit point marker
    ShowTargetBox = false,        -- Draw target bounding box
    ShowDebugPanel = false,       -- Show es_lib debug panel
    ShowDistanceInfo = false,
    ShowRadiusInfo = false,
    ShowEntityInfo = false,
    ShowScanDetails = false,
    ShowSharedState = false,
    LogEvents = false,            -- Log events to console
    LogScans = false,             -- Log scan results to console
    RaycastColor = {0, 255, 255, 200},       -- RGBA color for raycast debug lines
    DetectionColor = {255, 255, 0, 100},     -- RGBA color for detection radius debug
    HitPointColor = {0, 255, 0, 255},        -- RGBA color for hit point debug marker
    TargetBoxColor = {255, 128, 0, 200},     -- RGBA color for target bounding box debug
}
```

### Update Intervals

```lua
Config.Intervals = {
    StateSync = 200,          -- Camera state sync interval (ms)
    ClaimTimeout = 5000,      -- Camera claim timeout (ms)
    UI = {
        Fast = 50,            -- Fast UI update rate (ms)
        Medium = 200,         -- Medium UI update rate (ms)
        Slow = 1000,          -- Slow UI update rate (ms)
    },
    Heartbeat = {
        BaseCheck = 1000,
        PilotHUDUpdate = 1000,
        FastUpdate = 200,
    },
    GroundZCheckOffset = 50.0,
}
```
