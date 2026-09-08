<div align="center">

# Cortex PolCam

### A synchronised FLIR-style police helicopter camera system for FiveM

Target tracking, thermal and night vision, ground lock, spotlight control, hover and orbit assistance, points of interest, rappelling and multi-crew camera hand-off.

[![Release](https://img.shields.io/github/v/release/IEver3st/cortex-polcam?display_name=tag&sort=semver)](../../releases/latest)
[![FiveM](https://img.shields.io/badge/platform-FiveM-F40552?logo=fivem)](https://fivem.net/)
[![Lua](https://img.shields.io/badge/Lua-5.4-2C2D72?logo=lua)](https://www.lua.org/)
[![Licence](https://img.shields.io/github/license/IEver3st/cortex-polcam)](./LICENSE)

[Download](../../releases/latest) · [Configuration](#configuration) · [Exports](#exports)

</div>

<!--
Add a cockpit or camera-overlay screenshot here.
Recommended path: docs/media/polcam-camera.png
-->

## Overview

Cortex PolCam is a configurable airborne camera resource for FiveM law-enforcement and public-safety roleplay servers.

It provides a FLIR-inspired NUI, smooth zoom and camera motion, vehicle and pedestrian tracking, plate visibility logic, synchronised spotlights, points of interest, ground locking and shared camera state between helicopter crew members.

The system is framework-light. Core camera behaviour is implemented in Lua with a small HTML, CSS and JavaScript NUI.

## Features

### Camera system

- Smooth camera rotation and zoom
- Configurable field-of-view limits
- Ground-position locking
- Street and postal overlays
- Heading, altitude, speed and range information
- Per-model and per-livery agency labels
- High-contrast interface themes
- Optional pilot HUD
- Configurable native audio feedback

### Vision modes

- Standard camera view
- Night vision
- Thermal imaging
- Configurable default mode and feature availability

### Target tracking

- Lock vehicles and pedestrians
- Distance-scaled target acquisition
- Configurable vehicle and pedestrian ranges
- Smooth camera following
- Plate visibility angle checks
- Occlusion detection
- Grace period before dropping an obstructed target
- Persistent target labels
- Entity-pool fallback scanning

### Spotlight

- Camera-following searchlight
- Network-synchronised direction and position
- Configurable brightness, range, radius and colour
- Adjustable update and smoothing intervals

### Helicopter assistance

- Hover assistance
- Orbit assistance around a selected position or target
- Damage checks before autopilot operation
- Configurable orbit radius and correction behaviour
- Natural sway and gust parameters

### Multi-crew operation

- Shared camera state between helicopter occupants
- Camera hand-off between operators
- Restoration of tracked targets after takeover
- Restoration of ground lock and vision mode
- Server-side active air-feed registry
- Datalink access to tracked vehicles

### Points of interest

- Place temporary world markers from the camera
- Synchronise markers with other players
- Configure maximum active markers and expiry time
- Remove nearby markers through a keybind

### Rappelling

- Rappel from configured helicopter seats
- Enforce minimum and maximum altitude
- Whitelist or blacklist specific helicopter models
- Synchronise rappel state to nearby players

## Dependencies

| Resource | Required | Purpose |
|---|---:|---|
| `cortex-lib` | Yes | Notifications, target-lock progress and debug tools |
| `cortex-hud` | No | Hides the player HUD and can force the aircraft HUD |
| `nearest-postal` | No | Supplies postal data for the camera overlay |

`cortex-lib` must start before `cortex_polcam`.

## Installation

1. Download the [latest release](../../releases/latest) or clone the repository.
2. Place the resource in the server's resources directory.
3. Ensure the folder is named `cortex_polcam`.
4. Install and configure `cortex-lib`.
5. Review `config.lua`.
6. Add the resources to `server.cfg` in dependency order.

```cfg
ensure cortex-lib
ensure cortex-hud
ensure nearest-postal
ensure cortex_polcam
```

Only `cortex-lib` is required. Remove optional resources from the configuration when they are not installed.

Restart the server and test the camera in a configured helicopter model.

## Default controls

| Action | Default key |
|---|---|
| Toggle camera | `E` |
| Toggle camera UI | `H` |
| Toggle street overlay | `N` |
| Toggle hover assistance | `X` |
| Toggle orbit assistance | `O` |
| Toggle spotlight | `L` |
| Cycle spotlight colour | `K` |
| Cycle vision mode | `V` |
| Lock or unlock target | `SPACE` |
| Lock camera to ground | `T` |
| Place point of interest | `B` |
| Delete nearest marker | `DELETE` |
| Open debug tools | `F10` |

All keybinds are configurable in `config.lua`.

## Configuration

All settings are held in `config.lua`.

### Core access

```lua
Config.AllowedHelicopters = {
    "polmav",
    "maverick"
}

Config.AllowedSeats = { -1, 0, 1, 2 }
Config.InstantLock = false
```

### Camera

```lua
Config.Camera = {
    MinZoom = 1.0,
    MaxZoom = 30.0,
    DefaultZoom = 5.0,
    DefaultFOV = 50.0,
    MinFOV = 2.0,
    MaxFOV = 70.0,
    RotationSpeed = 3.0,
    RenderDistance = 1000.0
}
```

### Tracking

```lua
Config.Tracking = {
    Enabled = true,
    LockDurationMs = 1200,
    TrackVehicles = true,
    TrackPeds = true,
    TrackingSpeed = 12.0,
    TargetingMaxDistanceVehicles = 1000.0,
    TargetingMaxDistancePeds = 1000.0,
    OcclusionEnabled = true,
    OcclusionGracePeriodMs = 3000
}
```

### Vision

```lua
Config.Vision = {
    DefaultMode = "normal",
    NightVision = {
        Enabled = true,
        Intensity = 0.7
    },
    Thermal = {
        Enabled = true
    }
}
```

### Spotlight

```lua
Config.Spotlight = {
    Enabled = true,
    SyncWithCamera = true,
    Brightness = 10.0,
    Range = 400.0,
    Radius = 10.0,
    Color = { 170, 185, 255 }
}
```

### Points of interest

```lua
Config.POI = {
    Enabled = true,
    MaxPOIs = 10,
    ExpiryTime = 300,
    SyncToOthers = true
}
```

### Rappelling

```lua
Config.Rappel = {
    Enabled = true,
    Keybind = "G",
    MinAltitude = 15,
    MaxAltitude = 150,
    AllowedSeats = { 1, 2 },
    SyncEnabled = true,
    AllowedHashes = {},
    DisableHashes = {}
}
```

### Shared camera

```lua
Config.SharedCamera = {
    Enabled = true,
    SyncIntervalMs = 200,
    StateTimeoutMs = 300000,
    RestoreTrackedTarget = true,
    RestoreGroundLock = true,
    RestoreVisionMode = true
}
```

## HUD integration

When `cortex-hud` is enabled, PolCam hides the normal player HUD while the camera is active:

```lua
exports['cortex-hud']:hideHud('polcam')
exports['cortex-hud']:showHud('polcam')
```

The pilot can optionally retain a forced aircraft HUD through:

```lua
exports['cortex-hud']:setForceAircraftHud()
```

Example configuration:

```lua
Config.EsHud = {
    Enabled = true,
    AutoDetect = true,
    ShowAircraftHudForPilot = false,
    FallbackAircraftHud = false
}
```

## Camera labels

Agency labels can be selected by vehicle model and livery index.

```lua
Config.CameraLabels = {
    Enabled = true,
    DefaultLabel = "LOS SANTOS POLICE DEPARTMENT",

    ModelLabels = {
        ["polmav"] = "LOS SANTOS POLICE DEPARTMENT",
        ["maverick"] = "SAN ANDREAS STATE POLICE"
    },

    LiveryLabels = {
        ["polmav"] = {
            [0] = "LSPD",
            [1] = "LSPD AIR-2",
            [2] = "VINEWOOD AIR UNIT"
        }
    }
}
```

## Exports

### Client exports

| Export | Returns | Purpose |
|---|---|---|
| `IsPolCamActive()` | `boolean` | Whether the camera is active |
| `GetCurrentTarget()` | `entity, table` | Current target entity and metadata |
| `GetCameraHeading()` | `number` | Current camera heading |
| `IsRappelAvailable()` | `boolean` | Whether rappel conditions are satisfied |
| `IsRappeling()` | `boolean` | Whether the player is rappelling |
| `StartRappel()` | - | Starts a rappel |
| `ConvertSpeed(speed)` | `number` | Converts speed to configured units |
| `ConvertAltitude(altitude)` | `number` | Converts altitude to configured units |
| `ConvertDistance(distance)` | `number` | Converts distance to configured units |
| `OpenPolCamDebugMenu()` | - | Opens debug tools when enabled |

Example:

```lua
local active = exports['cortex_polcam']:IsPolCamActive()
local target, targetInfo = exports['cortex_polcam']:GetCurrentTarget()

if active and target then
    print(("Tracking entity %s"):format(target))
end
```

### Server exports

| Export | Returns | Purpose |
|---|---|---|
| `GetActiveAirFeeds()` | `table` | Lists active airborne camera feeds |
| `GetAirFeedById(feedId)` | `table` | Returns one feed by identifier |
| `GetTrackedDatalinkTargets()` | `table` | Returns vehicles tracked by active feeds |

Example:

```lua
local feeds = exports['cortex_polcam']:GetActiveAirFeeds()

for _, feed in ipairs(feeds) do
    print(json.encode(feed))
end
```

## Debugging

Debug tools are disabled by default.

```lua
Config.Debug = {
    Enabled = false,
    ToolsEnabled = false,
    ShowRaycast = true,
    ShowDetectionRadius = false,
    ShowHitPoint = false,
    ShowTargetBox = false,
    ShowDebugPanel = false,
    LogEvents = false,
    LogScans = false
}
```

When enabled, the resource can display raycasts, hit points, target bounds, detection radii and synchronisation state. The F10 debug menu requires `cortex-lib`.

Do not leave verbose debug logging enabled on a production server unless it is required for diagnosis.

## Architecture

```text
cortex_polcam/
├── client/
│   ├── camera.lua           # Camera lifecycle and movement
│   ├── vision.lua           # Night and thermal modes
│   ├── targeting.lua        # Entity acquisition and tracking
│   ├── spotlight.lua        # Searchlight control and sync
│   ├── helicontrol.lua      # Hover and orbit assistance
│   ├── poi.lua              # Shared world markers
│   ├── rappel.lua           # Rappel checks and execution
│   ├── streetoverlay.lua    # Location display
│   ├── sounds.lua           # Native audio cues
│   ├── debug.lua            # Diagnostic tools
│   └── main.lua             # Resource orchestration
├── server/
│   └── main.lua             # Air feeds, datalink and network state
├── html/
│   ├── index.html           # NUI structure
│   ├── style.css            # Camera interface
│   └── script.js            # NUI behaviour
├── config.lua
└── fxmanifest.lua
```

## Performance considerations

The default configuration separates update work into fast, medium and slow intervals. Before lowering intervals:

- Profile the resource with realistic player counts
- Check spotlight and camera synchronisation traffic
- Test several simultaneous air units
- Confirm target scanning does not create avoidable entity-pool work
- Keep debug rendering disabled in production

More frequent synchronisation is not automatically smoother if network latency or client frame time is already the limiting factor.

## Compatibility

PolCam uses FiveM's Cerulean resource format and Lua 5.4.

The core resource is not tied directly to QBCore, Qbox or ESX. Server integrations can consume the provided client and server exports.

## Project status

PolCam has been released publicly as a complete open-source resource. Maintenance and future feature development are best-effort rather than guaranteed.

Forks and pull requests are welcome, particularly where changes remain configurable and do not impose a specific server framework.

## Contributing

When reporting an issue, include:

- FiveM server artefact version
- OneSync configuration
- Helicopter model and seat
- Relevant `config.lua` values
- Whether `cortex-lib`, `cortex-hud` and `nearest-postal` are running
- Client and server console output
- Reproduction steps

Keep framework-specific behaviour behind configuration or an integration layer.

## Licence

Cortex PolCam is released under the [MIT Licence](./LICENSE).

## Credits

Designed and developed in collaboration with GSD Modifications.

## Disclaimer

Cortex PolCam is an independent FiveM community resource. It is not affiliated with or endorsed by Rockstar Games, Take-Two Interactive or Cfx.re.

---

<div align="center">

A capable air unit is useful. A configurable one is less troublesome.

</div>
