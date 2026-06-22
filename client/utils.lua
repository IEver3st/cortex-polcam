--[[
    PolCam - Shared Client Utilities
    Common helpers used across multiple client modules.
    Loaded first in fxmanifest so all other scripts can reference these globals.
]]

local DoesEntityExist = DoesEntityExist
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity

--- Safe wrapper to get network ID from entity.
--- Returns nil if entity doesn't exist or isn't networked (prevents warning spam).
--- @param entity number
--- @return number|nil
function SafeGetNetworkId(entity)
    if not entity or entity == 0 then
        return nil
    end
    if not DoesEntityExist(entity) then
        return nil
    end
    if not NetworkGetEntityIsNetworked(entity) then
        return nil
    end
    return NetworkGetNetworkIdFromEntity(entity)
end
