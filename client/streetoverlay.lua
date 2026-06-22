local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord
local GetClosestVehicleNodeWithHeading = GetClosestVehicleNodeWithHeading
local GetStreetNameAtCoord = GetStreetNameAtCoord
local GetStreetNameFromHashKey = GetStreetNameFromHashKey
local GetGameTimer = GetGameTimer
local GetEntityCoords = GetEntityCoords
local CreateThread = CreateThread
local Wait = Wait
local SetTextScale = SetTextScale
local SetTextFont = SetTextFont
local SetTextColour = SetTextColour
local SetTextOutline = SetTextOutline
local SetTextCentre = SetTextCentre
local BeginTextCommandDisplayText = BeginTextCommandDisplayText
local AddTextComponentSubstringPlayerName = AddTextComponentSubstringPlayerName
local EndTextCommandDisplayText = EndTextCommandDisplayText
local StartShapeTestRay = StartShapeTestRay
local GetShapeTestResult = GetShapeTestResult

local math_ceil = math.ceil

local StreetOverlayEnabled = true
local Labels = {}
local LabelsCount = 0
local LastUpdateTime = 0
local LastUpdateX = 0
local LastUpdateY = 0

local UPDATE_INTERVAL = 2000
local UPDATE_DISTANCE_SQ = 120.0 * 120.0
local SAMPLE_RADIUS = 150.0
local SAMPLE_SPACING = 85.0
local LABEL_SPACING_SQ = 140.0 * 140.0
local MAX_LABELS = 8
local MAX_DRAW_DISTANCE_SQ = 500.0 * 500.0
local MAX_DRAW_PER_FRAME = 4

local TEXT_SCALE = 0.22
local TEXT_R, TEXT_G, TEXT_B, TEXT_A = 200, 230, 255, 180

function ToggleStreetOverlay()
    StreetOverlayEnabled = not StreetOverlayEnabled
    if not StreetOverlayEnabled then
        Labels = {}
        LabelsCount = 0
    end
end

function IsStreetOverlayEnabled()
    return StreetOverlayEnabled
end

local function UpdateLabels(cx, cy, cz)
    local newLabels = {}
    local count = 0
    local placed = {}

    local steps = math_ceil(SAMPLE_RADIUS * 2 / SAMPLE_SPACING)
    local startX = cx - SAMPLE_RADIUS
    local startY = cy - SAMPLE_RADIUS

    for gx = 0, steps do
        if count >= MAX_LABELS then break end
        local x = startX + gx * SAMPLE_SPACING

        for gy = 0, steps do
            if count >= MAX_LABELS then break end
            local y = startY + gy * SAMPLE_SPACING

            local ok, pos = GetClosestVehicleNodeWithHeading(x, y, cz, 1, 3.0, 0)
            if ok then
                local streetHash = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
                if streetHash and streetHash ~= 0 then

                    local tooClose = false
                    local existingPositions = placed[streetHash]
                    if existingPositions then
                        for i = 1, #existingPositions do
                            local other = existingPositions[i]
                            local dx = pos.x - other.x
                            local dy = pos.y - other.y
                            if dx*dx + dy*dy < LABEL_SPACING_SQ then
                                tooClose = true
                                break
                            end
                        end
                    end

                    if not tooClose then

                        local visible = true
                        if PolCam.CameraCoords then

                            local ray = StartShapeTestRay(
                                PolCam.CameraCoords.x, PolCam.CameraCoords.y, PolCam.CameraCoords.z,
                                pos.x, pos.y, pos.z + 1.5,
                                1, PolCam.CurrentVehicle, 0
                            )
                            local _, hit, _, _, _ = GetShapeTestResult(ray)

                            if hit == 1 or hit == true then
                                visible = false
                            end
                        end

                        if visible then
                            local name = GetStreetNameFromHashKey(streetHash)
                            if name and name ~= "" then
                                if not existingPositions then
                                    placed[streetHash] = {}
                                    existingPositions = placed[streetHash]
                                end
                                existingPositions[#existingPositions + 1] = pos

                                count = count + 1
                                newLabels[count] = {
                                    x = pos.x,
                                    y = pos.y,
                                    z = pos.z + 0.5,
                                    name = name
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    Labels = newLabels
    LabelsCount = count
    LastUpdateTime = GetGameTimer()
    LastUpdateX = cx
    LastUpdateY = cy
end

local function GetOverlayCameraPosition()
    if not PolCam or not PolCam.Active or not StreetOverlayEnabled then
        return nil
    end

    return PolCam.GroundCoords
end

function UpdateStreetOverlay()
    local camPos = GetOverlayCameraPosition()
    if not camPos then
        return
    end

    local now = GetGameTimer()
    if LastUpdateTime == 0 then
        UpdateLabels(camPos.x, camPos.y, camPos.z)
        return
    end

    if (now - LastUpdateTime) <= UPDATE_INTERVAL then
        return
    end

    local dx = camPos.x - LastUpdateX
    local dy = camPos.y - LastUpdateY

    if (dx * dx + dy * dy > UPDATE_DISTANCE_SQ) or (now - LastUpdateTime > UPDATE_INTERVAL * 4) then
        UpdateLabels(camPos.x, camPos.y, camPos.z)
    end
end

function RenderStreetOverlay()
    local camPos = GetOverlayCameraPosition()
    if not camPos then
        return
    end

    local drawn = 0
    for i = 1, LabelsCount do
        if drawn >= MAX_DRAW_PER_FRAME then break end
        local lbl = Labels[i]

        local distDx = lbl.x - camPos.x
        local distDy = lbl.y - camPos.y
        if (distDx * distDx + distDy * distDy) < MAX_DRAW_DISTANCE_SQ then
            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(lbl.x, lbl.y, lbl.z)
            if onScreen then
                SetTextScale(TEXT_SCALE, TEXT_SCALE)
                SetTextFont(0)
                SetTextColour(TEXT_R, TEXT_G, TEXT_B, TEXT_A)
                SetTextOutline()
                SetTextCentre(true)
                BeginTextCommandDisplayText("STRING")
                AddTextComponentSubstringPlayerName(lbl.name)
                EndTextCommandDisplayText(sx, sy)
                drawn = drawn + 1
            end
        end
    end
end
