# Agent Instructions for PolCam (FiveM Resource)

This document contains instructions for AI agents working on the PolCam repository.

## 1. Project Overview
- **Type**: FiveM Resource (Lua 5.4)
- **Purpose**: Police Helicopter Camera System ("Eye in the Sky")
- **Structure**:
  - `client/`: Client-side Lua scripts
  - `server/`: Server-side Lua scripts
  - `html/`: NUI (UI) assets (HTML/CSS/JS)
  - `config.lua`: Shared configuration
  - `fxmanifest.lua`: Resource manifest

## 2. Build & Test
- **Build**: No build step required for Lua files. UI is vanilla HTML/JS/CSS.
- **Reload**: To apply changes in-game, use the server console command: `refresh` then `ensure polcam` (or `restart polcam`).
- **Linting**:
  - Use `luacheck` for Lua files (if available).
  - Recommended globals: `Config`, `PolCam`, `source`, `exports`, and FiveM natives (e.g., `CreateThread`, `TriggerEvent`).
- **Testing**:
  - **Manual**: Most testing must be done in a FiveM server environment.
  - **Logic**: You can write small standalone Lua scripts to test non-native logic (math, table manipulation) locally using a standard Lua 5.4 interpreter.

## 3. Code Style & Conventions
### Lua (Client & Server)
- **Version**: Lua 5.4 (`lua54 'yes'` in `fxmanifest.lua`).
- **Naming**:
  - **Global/Public Functions**: `PascalCase` (e.g., `ActivatePolCam`, `ToggleUI`).
  - **Local Variables/Functions**: `camelCase` (e.g., `vehicleNetId`, `local function getSpeed()`).
  - **Constants**: `UPPER_CASE` (e.g., `UI_FAST_INTERVAL`).
  - **Events**: `camelCase` with namespace (e.g., `polcam:cameraClaimResult`).
- **Optimization (Critical)**:
  - **Native Caching**: Always cache frequently used natives locally at the top of the file (e.g., `local PlayerPedId = PlayerPedId`).
  - **Loops**: Use `Wait(0)` for render loops, `Wait(ms)` for logic loops. Use tiered updates (Fast/Medium/Slow) for UI data to save performance.
  - **Math**: Use local aliases for math functions (e.g., `local floor = math.floor`).
- **Structure**:
  - Group related functions.
  - Use `CreateThread` for async loops.
  - Separate state (`PolCam` table) from logic.
- **Error Handling**:
  - Check `DoesEntityExist(entity)` before accessing entities.
  - Use `pcall` for risky operations like JSON decoding.

### NUI (HTML/JS)
- **Structure**: standard vanilla JS/CSS.
- **Communication**:
  - Client -> UI: `SendNUIMessage({ action = "...", data = ... })`
  - UI -> Client: `fetch('https://polcam/callbackName', ...)`
- **Visibility**: Handle `display: none` in CSS based on message actions.

### Configuration (`config.lua`)
- Use the `Config` global table.
- Group settings logically (e.g., `Config.Camera`, `Config.Tracking`).
- Provide sensible defaults.

## 4. Dependencies
- **ox_lib** / **es_lib**: For notifications (handle checks for availability).
- **nearest-postal**: For postal code lookups.
- **FiveM Natives**: Assume standard CFX Lua runtime environment.

## 5. Development Workflow
1. **Analyze**: Check `fxmanifest.lua` to see script loading order.
2. **Edit**: Modify files in `client/` or `server/`.
3. **Verify**:
   - For logic changes, trace the execution path.
   - For UI changes, check `html/index.html` and `html/script.js`.
4. **Communicate**: If adding new events, document them in comments.

## 6. Common Patterns
- **Entity Locking**: Use `NetworkGetNetworkIdFromEntity` / `NetworkGetEntityFromNetworkId` for network syncing.
- **State Sync**: Server maintains `SharedCameraState` and broadcasts to clients.
- **Debug**: Wrap debug prints in `if Config.Debug.Enabled then ... end`.

## 7. Cursor/Copilot Rules
- **No unnecessary comments**: Code should be self-documenting where possible.
- **Preserve existing style**: Match indentation (4 spaces) and bracketing style.
- **Safety**: Never assume a client-sent event is secure; validate on server.
