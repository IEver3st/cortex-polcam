fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'polcam'
description 'Police Helicopter Camera System - Eye in the Sky'
author 'PolCam Script'
version '1.0.0'

-- Shared configuration
shared_scripts {
    'config.lua'
}

-- Client scripts (IMPORTANT: main.lua must be last as it calls functions from other scripts)
client_scripts {
    'client/sounds.lua',
    'client/camera.lua',
    'client/vision.lua',
    'client/targeting.lua',
    'client/debug.lua',
    'client/poi.lua',
    'client/spotlight.lua',
    'client/helicontrol.lua',
    'client/streetoverlay.lua',
    'client/rappel.lua',
    'client/main.lua'
}

-- Server scripts
server_scripts {
    'server/main.lua'
}

-- NUI configuration
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

-- Exports
exports {
    'IsPolCamActive',
    'GetCurrentTarget',
    'GetCameraHeading',
    'IsRappelAvailable',
    'IsRappeling',
    'StartRappel',
    'ConvertSpeed',
    'ConvertAltitude',
    'ConvertDistance'
}

server_exports {
    'GetActiveAirFeeds',
    'GetAirFeedById',
    'GetTrackedDatalinkTargets'
}
