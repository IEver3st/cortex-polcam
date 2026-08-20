local dutyCache = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$') or ''
end

local function clampInteger(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) == math.huge then
        return fallback
    end
    number = math.floor(number)
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function getConfig()
    return type(Config) == 'table' and type(Config.MDTIntegration) == 'table'
        and Config.MDTIntegration or {}
end

local function getMdtResource(config)
    local resource = trim(config.Resource)
    return resource ~= '' and resource or 'cortex_mdtsv'
end

local function cacheKey(resource, source)
    return ('%s:%d'):format(resource, source)
end

local function clearDutyCache(source)
    if source == nil then
        dutyCache = {}
        return
    end

    source = tonumber(source)
    if not source then return end

    local suffix = ':' .. tostring(source)
    for key in pairs(dutyCache) do
        if key:sub(-#suffix) == suffix then
            dutyCache[key] = nil
        end
    end
end

local function sanitizeDutyState(source, state)
    if type(state) ~= 'table' then
        return {
            ok = false,
            source = source,
            onDuty = false,
            status = 'off_duty',
            code = 'invalid_duty_response',
        }
    end

    local status = trim(state.status):lower()
    local onDuty = state.ok == true and state.onDuty == true
    if onDuty and (status == '' or status == 'off_duty') then
        status = 'available'
    elseif not onDuty then
        status = 'off_duty'
    end

    return {
        ok = state.ok == true,
        source = source,
        onDuty = onDuty,
        status = status,
        callsign = trim(state.callsign):sub(1, 32),
        department = trim(state.department):sub(1, 64),
        frameworkMode = trim(state.frameworkMode):sub(1, 24),
        code = trim(state.code):sub(1, 48),
    }
end

local function getDutyState(source, config)
    source = tonumber(source)
    if not source or source <= 0 or source ~= math.floor(source) then
        return {
            ok = false,
            onDuty = false,
            status = 'off_duty',
            code = 'invalid_source',
        }
    end

    config = config or getConfig()
    local resource = getMdtResource(config)
    if GetResourceState(resource) ~= 'started' then
        return {
            ok = false,
            source = source,
            onDuty = false,
            status = 'off_duty',
            code = 'mdt_unavailable',
        }
    end

    local now = GetGameTimer()
    local cacheMs = clampInteger(config.DutyCacheMs, 50, 2000, 250)
    local key = cacheKey(resource, source)
    local cached = dutyCache[key]
    if cached and now >= cached.at and now - cached.at < cacheMs then
        return cached.state
    end

    local ok, result = pcall(function()
        return exports[resource]:getOfficerDutyState(source)
    end)

    local state
    if ok then
        state = sanitizeDutyState(source, result)
    else
        state = {
            ok = false,
            source = source,
            onDuty = false,
            status = 'off_duty',
            code = 'duty_export_failed',
        }
    end

    dutyCache[key] = {
        at = now,
        state = state,
    }

    return state
end

local function authorizeFeed(feed)
    local config = getConfig()
    if config.Enabled == false then
        return true, {
            authorized = true,
            code = 'integration_disabled',
        }
    end

    if type(feed) ~= 'table' then
        return false, {
            authorized = false,
            code = 'invalid_feed',
        }
    end

    local resource = getMdtResource(config)
    if GetResourceState(resource) ~= 'started' then
        local authorized = config.FailClosedWhenUnavailable ~= true
        return authorized, {
            authorized = authorized,
            code = 'mdt_unavailable',
        }
    end

    local operatorSource = tonumber(feed.operatorSource)
    local pilotSource = tonumber(feed.pilotSource)
    local result = {
        authorized = false,
        operatorSource = operatorSource,
        pilotSource = pilotSource,
    }

    if config.RequireOperatorOnDuty ~= false then
        if not operatorSource or operatorSource <= 0 then
            result.code = 'operator_unavailable'
            return false, result
        end

        result.operator = getDutyState(operatorSource, config)
        if result.operator.ok ~= true or result.operator.onDuty ~= true then
            result.code = 'operator_off_duty'
            return false, result
        end

        if result.operator.callsign ~= '' then
            feed.callsign = result.operator.callsign
        end
    end

    if config.RequirePilotOnDuty ~= false
        and pilotSource and pilotSource > 0
        and pilotSource ~= operatorSource then
        result.pilot = getDutyState(pilotSource, config)
        if result.pilot.ok ~= true or result.pilot.onDuty ~= true then
            result.code = 'pilot_off_duty'
            return false, result
        end
    end

    result.authorized = true
    result.code = 'authorized'
    return true, result
end

_G.CortexPolCamMdtIntegration = {
    isFeedAuthorized = function(feed)
        local authorized = authorizeFeed(feed)
        return authorized == true
    end,
    getFeedEligibility = function(feed)
        local _, result = authorizeFeed(feed)
        return result
    end,
    getDutyState = function(source)
        return getDutyState(source, getConfig())
    end,
}

exports('IsMdtAirFeedAuthorized', function(feed)
    local authorized = authorizeFeed(feed)
    return authorized == true
end)

exports('GetMdtDutyState', function(source)
    return getDutyState(source, getConfig())
end)

AddEventHandler('playerDropped', function()
    clearDutyCache(source)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == getMdtResource(getConfig()) then
        clearDutyCache()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == getMdtResource(getConfig()) then
        clearDutyCache()
    end

    if resourceName == GetCurrentResourceName() then
        _G.CortexPolCamMdtIntegration = nil
        clearDutyCache()
    end
end)
