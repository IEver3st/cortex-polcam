from __future__ import annotations

import hashlib
from pathlib import Path


def git_blob_sha(text: str) -> str:
    payload = text.encode('utf-8')
    header = f'blob {len(payload)}\0'.encode('utf-8')
    return hashlib.sha1(header + payload).hexdigest()


def replace_once(source: str, before: str, after: str, label: str) -> str:
    count = source.count(before)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    return source.replace(before, after, 1)


server_path = Path('server/main.lua')
server = server_path.read_text(encoding='utf-8')
expected_server_blob = '2f797621ab07a2f6d2edc813e65e2f056354f51e'
actual_server_blob = git_blob_sha(server)
if actual_server_blob != expected_server_blob:
    raise RuntimeError(
        f'server/main.lua changed before patching: expected {expected_server_blob}, found {actual_server_blob}'
    )

server = replace_once(
    server,
    """local function RemoveAirFeed(vehicleNetId)
    ActiveAirFeeds[vehicleNetId] = nil
end

local function GetActiveAirFeeds()
""",
    """local function RemoveAirFeed(vehicleNetId)
    ActiveAirFeeds[vehicleNetId] = nil
end

local function IsAirFeedExportAuthorized(feed)
    local integration = rawget(_G, 'CortexPolCamMdtIntegration')
    if type(integration) ~= 'table' or type(integration.isFeedAuthorized) ~= 'function' then
        return true
    end

    local ok, authorized = pcall(integration.isFeedAuthorized, feed)
    return ok and authorized == true
end

local function GetActiveAirFeeds()
""",
    'air feed authorization hook',
)

server = replace_once(
    server,
    """        if type(feed) == 'table' and feed.cameraActive == true then
            feeds[#feeds + 1] = BuildAirFeedPublic(feed)
        end
""",
    """        if type(feed) == 'table'
            and feed.cameraActive == true
            and IsAirFeedExportAuthorized(feed) then
            feeds[#feeds + 1] = BuildAirFeedPublic(feed)
        end
""",
    'active air feed export guard',
)

server = replace_once(
    server,
    """local function GetAirFeedById(feedId)
    local vehicleNetId = ParseFeedId(feedId)
    if not vehicleNetId then
        return nil
    end

    return BuildAirFeedPublic(ActiveAirFeeds[vehicleNetId])
end
""",
    """local function GetAirFeedById(feedId)
    local vehicleNetId = ParseFeedId(feedId)
    if not vehicleNetId then
        return nil
    end

    local feed = ActiveAirFeeds[vehicleNetId]
    if not IsAirFeedExportAuthorized(feed) then
        return nil
    end

    return BuildAirFeedPublic(feed)
end
""",
    'single air feed export guard',
)

server = replace_once(
    server,
    """    for _, feed in pairs(ActiveAirFeeds) do
        local publicFeed = BuildAirFeedPublic(feed)
        local tracking = publicFeed and publicFeed.tracking
""",
    """    for _, feed in pairs(ActiveAirFeeds) do
        local publicFeed = IsAirFeedExportAuthorized(feed) and BuildAirFeedPublic(feed) or nil
        local tracking = publicFeed and publicFeed.tracking
""",
    'datalink export guard',
)

server_path.write_text(server, encoding='utf-8')

config_path = Path('config.lua')
config = config_path.read_text(encoding='utf-8')
expected_config_blob = '7fd17aa6685b659b75f6d22dc21b4c46a334f2a9'
actual_config_blob = git_blob_sha(config)
if actual_config_blob != expected_config_blob:
    raise RuntimeError(
        f'config.lua changed before patching: expected {expected_config_blob}, found {actual_config_blob}'
    )

config = replace_once(
    config,
    """Config.InstantLock = false
Config.Lib = { Notify = 'auto' }

Config.Keybinds = {
""",
    """Config.InstantLock = false
Config.Lib = { Notify = 'auto' }

-- Optional Cortex MDT link. Local PolCam operation remains available when the
-- MDT is absent; only exported remote feeds are duty-gated while it is online.
Config.MDTIntegration = {
    Enabled = true,
    Resource = 'cortex_mdtsv',
    RequireOperatorOnDuty = true,
    RequirePilotOnDuty = true,
    FailClosedWhenUnavailable = false,
    DutyCacheMs = 250,
}

Config.Keybinds = {
""",
    'MDT integration defaults',
)

config_path.write_text(config, encoding='utf-8')

print(f'patched {server_path} -> {git_blob_sha(server)}')
print(f'patched {config_path} -> {git_blob_sha(config)}')
