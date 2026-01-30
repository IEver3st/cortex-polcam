--[[
    PolCam - Street Labels
    Optimized road name labels with toggle support.
]]

-- Cache natives for performance
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord
local GetClosestVehicleNodeWithHeading = GetClosestVehicleNodeWithHeading
local GetStreetNameAtCoord = GetStreetNameAtCoord
local GetStreetNameFromHashKey = GetStreetNameFromHashKey
local GetGameTimer = GetGameTimer
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

-- Cache math
local math_ceil = math.ceil

-- State
local StreetOverlayEnabled = true
local Labels = {}
local LabelsCount = 0
local LastUpdateTime = 0
local LastUpdateX = 0
local LastUpdateY = 0

-- Config (can be overridden from Config.StreetOverlay)
local UPDATE_INTERVAL = 1500         -- Increase time between updates
local UPDATE_DISTANCE_SQ = 100.0 * 100.0 -- Increase distance threshold to 100m
local SAMPLE_RADIUS = 150.0          -- Slightly smaller radius
local SAMPLE_SPACING = 75.0          -- Slightly larger spacing (fewer samples)
local LABEL_SPACING_SQ = 120.0 * 120.0 -- Increase spacing between identical street labels
local MAX_LABELS = 12                -- Reduce max labels from 20 to 12
local MAX_DRAW_DISTANCE_SQ = 600.0 * 600.0 -- Max distance from camera to draw a label

-- Text settings
local TEXT_SCALE = 0.22
local TEXT_R, TEXT_G, TEXT_B, TEXT_A = 200, 230, 255, 180

-- Toggle function (called from main.lua)
function ToggleStreetOverlay()
    StreetOverlayEnabled = not StreetOverlayEnabled
    if not StreetOverlayEnabled then
        Labels = {}
        LabelsCount = 0
    end
end

-- Check if enabled (for external use)
function IsStreetOverlayEnabled()
    return StreetOverlayEnabled
end

-- Optimized label update - runs less frequently
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
                    -- Check spacing from same street
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
                        -- Check Line of Sight (Optimization: Don't show labels through buildings)
                        local visible = true
                        if PolCam.CameraCoords then
                            -- Raycast from camera to 1.5m above the road node (Flag 1: Map/World only)
                            local ray = StartShapeTestRay(
                                PolCam.CameraCoords.x, PolCam.CameraCoords.y, PolCam.CameraCoords.z,
                                pos.x, pos.y, pos.z + 1.5,
                                1, PolCam.CurrentVehicle, 0
                            )
                            local _, hit, _, _, _ = GetShapeTestResult(ray)
                            -- If hit is 1 or true, we hit something (blocked)
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

-- Render thread
CreateThread(function()
    while true do
        Wait(0)
        
        -- Skip if polcam not active or overlay disabled
        if not PolCam or not PolCam.Active or not StreetOverlayEnabled then
            Wait(200)
            goto continue
        end
        
        local camPos = PolCam.GroundCoords
        if not camPos then
            Wait(100)
            goto continue
        end
        
        -- Check if update needed (Require BOTH distance AND time cooldown)
        local now = GetGameTimer()
        if (now - LastUpdateTime) > UPDATE_INTERVAL then
            local dx = camPos.x - LastUpdateX
            local dy = camPos.y - LastUpdateY
            
            -- Update if distance threshold met OR if it's been a long time (force refresh)
            if (dx*dx + dy*dy > UPDATE_DISTANCE_SQ) or (now - LastUpdateTime > UPDATE_INTERVAL * 4) then
                UpdateLabels(camPos.x, camPos.y, camPos.z)
            end
        end
        
        -- Draw labels (optimized - distance culling)
        local heliCoords = GetEntityCoords(PolCam.CurrentVehicle)
        for i = 1, LabelsCount do
            local lbl = Labels[i]
            
            -- Only attempt to draw if reasonably close to the camera's focus/heli
            local distDx = lbl.x - camPos.x
            local distDy = lbl.y - camPos.y
            if (distDx*distDx + distDy*distDy) < MAX_DRAW_DISTANCE_SQ then
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
                end
            end
        end
        
        ::continue::
    end
end)
