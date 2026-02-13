local DoesCamExist = DoesCamExist
local DestroyCam = DestroyCam
local CreateCam = CreateCam
local GetEntityCoords = GetEntityCoords
local SetCamCoord = SetCamCoord
local GetEntityHeading = GetEntityHeading
local SetCamRot = SetCamRot
local SetCamFov = SetCamFov
local RenderScriptCams = RenderScriptCams
local SetCamActive = SetCamActive
local ClearFocus = ClearFocus
local ClearHdArea = ClearHdArea
local GetDisabledControlNormal = GetDisabledControlNormal
local IsDisabledControlPressed = IsDisabledControlPressed
local IsControlPressed = IsControlPressed
local GetFrameTime = GetFrameTime
local DoesEntityExist = DoesEntityExist
local GetEntityRotation = GetEntityRotation
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local StartShapeTestRay = StartShapeTestRay
local GetShapeTestResult = GetShapeTestResult
local HideHudAndRadarThisFrame = HideHudAndRadarThisFrame
local DisplayRadar = DisplayRadar
local GetCamMatrix = GetCamMatrix
local SetFocusPosAndVel = SetFocusPosAndVel
local SetHdArea = SetHdArea
local SendNUIMessage = SendNUIMessage

local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_rad = math.rad
local math_deg = math.deg
local math_sin = math.sin
local math_cos = math.cos
local math_sqrt = math.sqrt
local math_atan2 = math.atan2

function CreatePolCamCamera()
    if PolCam.Camera and DoesCamExist(PolCam.Camera) then
        DestroyCam(PolCam.Camera, false)
    end
    
    PolCam.Camera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    
    local heliCoords = GetEntityCoords(PolCam.CurrentVehicle)
    local offset = Config.Camera.CameraOffset
    SetCamCoord(PolCam.Camera, heliCoords.x + offset.x, heliCoords.y + offset.y, heliCoords.z + offset.z)
    
    local isDefaultState = (PolCam.Heading == 0.0 and PolCam.Pitch == -15.0)
    
    if isDefaultState then
        PolCam.Heading = GetEntityHeading(PolCam.CurrentVehicle)
        PolCam.Pitch = -15.0
    end
    
    SetCamRot(PolCam.Camera, -PolCam.Pitch, 0.0, PolCam.Heading, 2)
    
    if PolCam.FOV == nil or PolCam.FOV == (Config.Camera.DefaultFOV or 50.0) then
        PolCam.FOV = CalculateFOV(PolCam.Zoom)
    end
    SetCamFov(PolCam.Camera, PolCam.FOV)
    
    if PlayPolCamSound then
        PlayPolCamSound("CameraTransitionIn")
    end
    
    RenderScriptCams(true, true, 1000, true, false)
    SetCamActive(PolCam.Camera, true)
end

function DestroyPolCamCamera()
    if PolCam.Camera and DoesCamExist(PolCam.Camera) then
        if PlayPolCamSound then
            PlayPolCamSound("CameraTransitionOut")
        end
        
        RenderScriptCams(false, true, 1000, true, false)
        SetCamActive(PolCam.Camera, false)
        DestroyCam(PolCam.Camera, false)
        PolCam.Camera = nil
    end

    if ClearFocus then
        ClearFocus()
    end
    if ClearHdArea then
        ClearHdArea()
    end
end

local cachedZoomRange = nil
local cachedFovRange = nil

local function EnsureFovCacheValid()
    if not cachedZoomRange then
        cachedZoomRange = Config.Camera.MaxZoom - Config.Camera.MinZoom
        cachedFovRange = Config.Camera.MaxFOV - Config.Camera.MinFOV
    end
end

function CalculateFOV(zoomLevel)
    EnsureFovCacheValid()
    local normalizedZoom = (zoomLevel - Config.Camera.MinZoom) / cachedZoomRange
    return Config.Camera.MaxFOV - (normalizedZoom * cachedFovRange)
end

function HandleCameraInput()
    if PolCam.LockedTarget then return end
    
    local mouseX = GetDisabledControlNormal(0, 1)
    local mouseY = GetDisabledControlNormal(0, 2)
    
    if mouseX == 0 and mouseY == 0 then return end
    
    local rotSpeed = Config.Camera.RotationSpeed
    if Config.Camera and Config.Camera.MaxFOV and PolCam.FOV then
        local minMult = (Config.Camera.ZoomSensitivityMinMultiplier ~= nil) and Config.Camera.ZoomSensitivityMinMultiplier or 0.20
        if minMult < 0.01 then minMult = 0.01 end
        if minMult > 1.0 then minMult = 1.0 end
        local ratio = PolCam.FOV / Config.Camera.MaxFOV
        if ratio < minMult then ratio = minMult end
        if ratio > 1.0 then ratio = 1.0 end
        rotSpeed = rotSpeed * ratio
    end
    
    local newHeading = PolCam.Heading - (mouseX * rotSpeed)
    if newHeading < 0 then newHeading = newHeading + 360
    elseif newHeading > 360 then newHeading = newHeading - 360 end
    PolCam.Heading = newHeading
    
    local newPitch = PolCam.Pitch + (mouseY * rotSpeed)
    PolCam.Pitch = math_max(Config.Camera.MinVerticalAngle, math_min(Config.Camera.MaxVerticalAngle, newPitch))
end

function HandleZoomInput()
    if IsControlPressed(0, 36) then return end
    
    local zoomChanged = false
    local maxZoom = Config.Camera.MaxZoom
    local minZoom = Config.Camera.MinZoom
    local zoomSpeed = Config.Camera.ZoomSpeed
    
    if IsDisabledControlPressed(0, 241) then
        PolCam.TargetZoom = math_min(maxZoom, PolCam.TargetZoom + zoomSpeed)
        zoomChanged = true
    end
    
    if IsDisabledControlPressed(0, 242) then
        PolCam.TargetZoom = math_max(minZoom, PolCam.TargetZoom - zoomSpeed)
        zoomChanged = true
    end
    
    local zoomDiff = PolCam.Zoom - PolCam.TargetZoom
    if math_abs(zoomDiff) > 0.01 then
        local delta = GetFrameTime() * Config.Camera.SmoothZoomSpeed
        if zoomDiff < 0 then
            PolCam.Zoom = math_min(PolCam.TargetZoom, PolCam.Zoom + delta)
        else
            PolCam.Zoom = math_max(PolCam.TargetZoom, PolCam.Zoom - delta)
        end
        
        PolCam.FOV = CalculateFOV(PolCam.Zoom)
        SetCamFov(PolCam.Camera, PolCam.FOV)
        
        if zoomChanged and PlayPolCamSound then
            PlayPolCamSound(zoomDiff > 0 and "ZoomOut" or "ZoomIn")
        end
    end
end

function UpdateCameraPosition()
    if not PolCam.Camera or not DoesCamExist(PolCam.Camera) then return end
    if not PolCam.CurrentVehicle or not DoesEntityExist(PolCam.CurrentVehicle) then return end
    
    local heliCoords = GetEntityCoords(PolCam.CurrentVehicle)
    local heliRot = GetEntityRotation(PolCam.CurrentVehicle, 2)
    
    local offset = Config.Camera.CameraOffset
    local camCoords = GetOffsetFromEntityInWorldCoords(PolCam.CurrentVehicle, offset.x, offset.y, offset.z)
    
    SetCamCoord(PolCam.Camera, camCoords.x, camCoords.y, camCoords.z)
    PolCam.CameraCoords = camCoords
    
    if PolCam.GroundLockPoint then
        TrackGroundLockPoint()
    elseif PolCam.LockedTarget and DoesEntityExist(PolCam.LockedTarget) then
        TrackLockedTarget()
    else
        SetCamRot(PolCam.Camera, -PolCam.Pitch, 0.0, PolCam.Heading, 2)
    end
    
    UpdateGroundCoords()

    UpdateStreamingFocus()
end

local lastFocusUpdate = 0
local FOCUS_UPDATE_INTERVAL = 100 -- ms between SetFocusPosAndVel calls
local lastHdAreaUpdate = 0
local HD_AREA_UPDATE_INTERVAL = 500 -- ms between SetHdArea calls (expensive)
local lastHdAreaPos = nil
local HD_AREA_MIN_MOVE_SQ = 25.0 * 25.0 -- only update HdArea if focus moved 25m+

function UpdateStreamingFocus()
    if not PolCam.Active then return end
    if not Config or not Config.Camera or not Config.Camera.StreamingFocusEnabled then return end

    local focusPos = PolCam.GroundCoords

    if not focusPos and PolCam.Camera and DoesCamExist(PolCam.Camera) and PolCam.CameraCoords then
        local _, forwardVector = GetCamMatrix(PolCam.Camera)
        if forwardVector then
            local distance = Config.Camera.StreamingFocusDistance or 350.0
            focusPos = PolCam.CameraCoords + (forwardVector * distance)
        end
    end

    if not focusPos then return end

    local now = GetGameTimer()

    -- Throttle SetFocusPosAndVel to every 100ms (still smooth, saves GPU streaming pressure)
    if SetFocusPosAndVel and (now - lastFocusUpdate) >= FOCUS_UPDATE_INTERVAL then
        lastFocusUpdate = now
        SetFocusPosAndVel(focusPos.x, focusPos.y, focusPos.z, 0.0, 0.0, 0.0)
    end

    -- Throttle SetHdArea more aggressively and only when focus moved significantly
    if Config.Camera.HdAreaEnabled and SetHdArea and (now - lastHdAreaUpdate) >= HD_AREA_UPDATE_INTERVAL then
        local shouldUpdate = not lastHdAreaPos
        if not shouldUpdate then
            local dx = focusPos.x - lastHdAreaPos.x
            local dy = focusPos.y - lastHdAreaPos.y
            shouldUpdate = (dx * dx + dy * dy) >= HD_AREA_MIN_MOVE_SQ
        end
        if shouldUpdate then
            lastHdAreaUpdate = now
            lastHdAreaPos = vector3(focusPos.x, focusPos.y, focusPos.z)
            SetHdArea(focusPos.x, focusPos.y, focusPos.z, Config.Camera.HdAreaRadius or 200.0)
        end
    end
end

function ToggleGroundLock()
    if PolCam.GroundLockPoint then
        ClearGroundLock()
    else
        SetGroundLock()
    end
end

function SetGroundLock()
    PolCam.GroundLockPoint = PolCam.GroundCoords
    
    if PlayPolCamSound then
        PlayPolCamSound("GroundLockOn")
    end
    
    SendNUIMessage({
        action = "groundLockOn"
    })
    
    if Config.Debug.Enabled then
        print("[PolCam] Ground lock set at " .. tostring(PolCam.GroundLockPoint))
    end
end

function ClearGroundLock()
    PolCam.GroundLockPoint = nil
    
    if PlayPolCamSound then
        PlayPolCamSound("GroundLockOff")
    end
    
    SendNUIMessage({
        action = "groundLockOff"
    })
    
    if Config.Debug.Enabled then
        print("[PolCam] Ground lock cleared")
    end
end

function TrackGroundLockPoint()
    if not PolCam.GroundLockPoint then return end
    
    local camCoords = PolCam.CameraCoords
    local targetCoords = PolCam.GroundLockPoint
    
    local dx = targetCoords.x - camCoords.x
    local dy = targetCoords.y - camCoords.y
    local dz = targetCoords.z - camCoords.z
    
    local targetHeading = GetHeadingFromVector_2d(dx, dy)
    
    local horizontalDist = math.sqrt(dx * dx + dy * dy)
    local targetPitch = -math.deg(math.atan2(dz, horizontalDist))
    
    local delta = GetFrameTime() * (Config.Tracking.TrackingSpeed or 12.0)
    
    PolCam.Heading = LerpAngle(PolCam.Heading, targetHeading, delta)
    PolCam.Pitch = Lerp(PolCam.Pitch, targetPitch, delta)
    
    SetCamRot(PolCam.Camera, -PolCam.Pitch, 0.0, PolCam.Heading, 2)
end

function IsGroundLockActive()
    return PolCam.GroundLockPoint ~= nil
end

function TrackLockedTarget()
    local targetCoords = GetEntityCoords(PolCam.LockedTarget)
    local camCoords = PolCam.CameraCoords
    
    local dx = targetCoords.x - camCoords.x
    local dy = targetCoords.y - camCoords.y
    local dz = targetCoords.z - camCoords.z
    
    local targetHeading = GetHeadingFromVector_2d(dx, dy)
    
    local horizontalDist = math.sqrt(dx * dx + dy * dy)
    local targetPitch = -math.deg(math.atan2(dz, horizontalDist))
    
    local delta = GetFrameTime() * (Config.Tracking.TrackingSpeed or 12.0)
    
    PolCam.Heading = LerpAngle(PolCam.Heading, targetHeading, delta)
    PolCam.Pitch = Lerp(PolCam.Pitch, targetPitch, delta)
    
    SetCamRot(PolCam.Camera, -PolCam.Pitch, 0.0, PolCam.Heading, 2)
end

local lastGroundCheck = 0
local GROUND_CHECK_INTERVAL = 66

function UpdateGroundCoords()
    local now = GetGameTimer()
    if now - lastGroundCheck < GROUND_CHECK_INTERVAL then return end
    lastGroundCheck = now

    local camCoords = PolCam.CameraCoords
    
    local heading = math_rad(PolCam.Heading)
    local pitch = math_rad(-PolCam.Pitch)
    
    local cosPitch = math_cos(pitch)
    local dirX = -math_sin(heading) * cosPitch
    local dirY = math_cos(heading) * cosPitch
    local dirZ = math_sin(pitch)
    
    local renderDist = Config.Camera.RenderDistance
    local endCoords = vector3(
        camCoords.x + dirX * renderDist,
        camCoords.y + dirY * renderDist,
        camCoords.z + dirZ * renderDist
    )
    
    local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, endCoords.x, endCoords.y, endCoords.z, -1, PolCam.CurrentVehicle, 0)
    local _, hit, hitCoords, _, _ = GetShapeTestResult(rayHandle)
    
    PolCam.GroundCoords = hit and hitCoords or endCoords
end

function RenderCameraView()
    if PolCam and PolCam.Active then
        HideHudAndRadarThisFrame()
        DisplayRadar(false)
    end

    ApplyVisionMode()
end

function Lerp(a, b, t)
    return a + (b - a) * t
end

function LerpAngle(a, b, t)
    local diff = b - a
    while diff > 180 do diff = diff - 360 end
    while diff < -180 do diff = diff + 360 end
    return a + diff * t
end

function ResetCameraZoomToDefault()
    local defaultZoom = Config.Camera.DefaultZoom or 5.0
    PolCam.Zoom = defaultZoom
    PolCam.TargetZoom = defaultZoom
    PolCam.FOV = CalculateFOV(defaultZoom)
    if PolCam.Camera and DoesCamExist(PolCam.Camera) then
        SetCamFov(PolCam.Camera, PolCam.FOV)
    end
end

function GetHeadingFromVector_2d(dx, dy)
    local heading = -math_deg(math_atan2(dx, dy))
    return heading < 0 and heading + 360 or heading
end
