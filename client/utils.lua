local DoesEntityExist = DoesEntityExist
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity

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
