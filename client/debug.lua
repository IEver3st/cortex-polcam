local tostring = tostring

local function hasEsLibMenu()
    return type(exports) == 'table'
        and exports['cortex-lib']
        and type(exports['cortex-lib'].registerMenu) == 'function'
        and type(exports['cortex-lib'].showMenu) == 'function'
end

local function hasEsLibDebugPanel()
    return type(exports) == 'table'
        and exports['cortex-lib']
        and type(exports['cortex-lib'].showDebugPanel) == 'function'
        and type(exports['cortex-lib'].updateDebugPanel) == 'function'
        and type(exports['cortex-lib'].hideDebugPanel) == 'function'
end

local function setDebugFlag(key, value)
    Config.Debug = Config.Debug or {}
    Config.Debug[key] = value
end

local function toggleDebugFlag(key)
    Config.Debug = Config.Debug or {}
    Config.Debug[key] = not not (not Config.Debug[key])
end

local function isDebugEnabled()
    return Config and Config.Debug and Config.Debug.Enabled
end

local function setDebugEnabled(value)
    Config.Debug = Config.Debug or {}
    Config.Debug.Enabled = value
end

local function safeSendPanelUpdate(data)
    if not hasEsLibDebugPanel() then return false end

    if data then
        exports['cortex-lib']:updateDebugPanel(data)
    else
        exports['cortex-lib']:updateDebugPanel({})
    end

    return true
end

local function safeShowPanel(data)
    if not hasEsLibDebugPanel() then return false end
    exports['cortex-lib']:showDebugPanel(data)
    return true
end

local function safeHidePanel()
    if not hasEsLibDebugPanel() then return false end
    exports['cortex-lib']:hideDebugPanel()
    return true
end

local MENU_ID = 'polcam:debug'

function OpenPolCamDebugMenu()
    if not (Config and Config.Debug and Config.Debug.ToolsEnabled) then
        return
    end

    if GetResourceState('cortex-lib') ~= 'started' then
        Config.Debug.Enabled = false
        Config.Debug.ShowDebugPanel = false
        Config.Debug.LogEvents = false
        Config.Debug.LogScans = false
        return
    end

    if not hasEsLibMenu() then
        if PolCamNotify then
            PolCamNotify('error', 'cortex-lib menu not available')
        else
            print('[PolCam] cortex-lib menu not available')
        end
        return
    end

    exports['cortex-lib']:registerMenu({
        id = MENU_ID,
        title = 'POLCAM DEBUG',
        subtitle = 'Toggle debug flags + panel',
        position = 'top-left',
        options = {
            { label = 'Enable Debug', checked = isDebugEnabled(), close = false, args = { t = 'toggle', k = 'Enabled' } },
            { label = 'Show Debug Panel', checked = Config.Debug and Config.Debug.ShowDebugPanel or false, close = false, args = { t = 'toggle', k = 'ShowDebugPanel' } },
            { label = 'Show Raycast', checked = Config.Debug and Config.Debug.ShowRaycast or false, close = false, args = { t = 'toggle', k = 'ShowRaycast' } },
            { label = 'Show Detection Radius', checked = Config.Debug and Config.Debug.ShowDetectionRadius or false, close = false, args = { t = 'toggle', k = 'ShowDetectionRadius' } },
            { label = 'Show Hit Point', checked = Config.Debug and Config.Debug.ShowHitPoint or false, close = false, args = { t = 'toggle', k = 'ShowHitPoint' } },
            { label = 'Show Target Box', checked = Config.Debug and Config.Debug.ShowTargetBox or false, close = false, args = { t = 'toggle', k = 'ShowTargetBox' } },
            { label = 'Show Distance Info', checked = Config.Debug and Config.Debug.ShowDistanceInfo or false, close = false, args = { t = 'toggle', k = 'ShowDistanceInfo' } },
            { label = 'Show Radius Info', checked = Config.Debug and Config.Debug.ShowRadiusInfo or false, close = false, args = { t = 'toggle', k = 'ShowRadiusInfo' } },
            { label = 'Show Entity Info', checked = Config.Debug and Config.Debug.ShowEntityInfo or false, close = false, args = { t = 'toggle', k = 'ShowEntityInfo' } },
            { label = 'Show Scan Details', checked = Config.Debug and Config.Debug.ShowScanDetails or false, close = false, args = { t = 'toggle', k = 'ShowScanDetails' } },
            { label = 'Show Shared State', checked = Config.Debug and Config.Debug.ShowSharedState or false, close = false, args = { t = 'toggle', k = 'ShowSharedState' } },
            { label = 'Log Events', checked = Config.Debug and Config.Debug.LogEvents or false, close = false, args = { t = 'toggle', k = 'LogEvents' } },
            { label = 'Log Scans', checked = Config.Debug and Config.Debug.LogScans or false, close = false, args = { t = 'toggle', k = 'LogScans' } },
            { label = 'Open Panel Now', description = 'Forces debug panel to show (if available).', close = false, args = { t = 'action', k = 'openPanel' } },
            { label = 'Hide Panel', description = 'Hides debug panel.', close = false, args = { t = 'action', k = 'hidePanel' } },
        }
    }, function(selected, scrollIndex, args)
        local key = args and args.k
        local actionType = args and args.t

        if actionType == 'toggle' then
            if key == 'Enabled' then
                setDebugEnabled(not isDebugEnabled())
            else
                toggleDebugFlag(key)
            end

            OpenPolCamDebugMenu()
            return
        end

        if actionType == 'action' then
            if key == 'openPanel' then
                safeShowPanel({
                    title = 'POLCAM DEBUG',
                    subtitle = 'Waiting for data...',
                    position = 'top-right',
                    accentColor = '#7cc7ff',
                    lines = {
                        'Panel opened manually',
                        { label = 'Debug Enabled', value = tostring(isDebugEnabled()) },
                    }
                })
                return
            end

            if key == 'hidePanel' then
                safeHidePanel()
                return
            end
        end

        print(('[PolCam Debug] menu submit selected=%s scroll=%s'):format(tostring(selected), tostring(scrollIndex)))
    end)

    exports['cortex-lib']:showMenu(MENU_ID)
end

exports('OpenPolCamDebugMenu', OpenPolCamDebugMenu)
