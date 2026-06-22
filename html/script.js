




const State = {
    visible: false,
    visionMode: 'normal',
    heading: 0,
    zoom: 1.0,
    hasTarget: false,
    uiVisible: true,
    spotlightActive: false,
    hoverActive: false,
    orbitActive: false,
    groundLockActive: false,
    currentAzimuth: 0,
    targetAzimuth: 0,
    currentPitch: 0,
    targetPitch: 0,
    pitchMin: -90,
    pitchMax: 30,
    lastFrameTime: performance.now(),
    highContrastEnabled: false,
    highContrastTheme: 'green',
    
    timeFormat: 'LOCAL',
    dateFormat: 'MM/DD/YY',
    showSeconds: true,
    use24Hour: true,
    
    speedUnit: 'KTS',
    altitudeUnit: 'FT',
    distanceUnit: 'M'
};

function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
}

function wrap360(deg) {
    return ((deg % 360) + 360) % 360;
}

function lerp(a, b, t) {
    return a + (b - a) * t;
}

function lerpAngleDegrees(current, target, t) {
    let diff = wrap360(target) - wrap360(current);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return current + diff * t;
}

function getDtSeconds() {
    const now = performance.now();
    const dt = Math.min(0.1, Math.max(0.0, (now - State.lastFrameTime) / 1000));
    State.lastFrameTime = now;
    return dt;
}




const Elements = {};




document.addEventListener('DOMContentLoaded', () => {
    
    Elements.container = document.getElementById('polcam-container');
    Elements.heading = document.getElementById('heading');
    Elements.currentTime = document.getElementById('current-time');
    Elements.currentDate = document.getElementById('current-date');
    Elements.altitude = document.getElementById('altitude');
    Elements.streetName = document.getElementById('street-name');
    Elements.zoomLevel = document.getElementById('zoom-level');
    Elements.heliSpeed = document.getElementById('heli-speed');
    Elements.heliHeading = document.getElementById('heli-heading');
    Elements.visionMode = document.getElementById('vision-mode');
    Elements.lockStatus = document.getElementById('lock-status');
    Elements.targetPanel = document.getElementById('target-panel');
    Elements.targetSpeed = document.getElementById('target-speed');
    Elements.targetHeading = document.getElementById('target-heading');
    Elements.targetDistance = document.getElementById('target-distance');
    Elements.targetPlate = document.getElementById('target-plate');
    Elements.targetMake = document.getElementById('target-make');
    Elements.targetModel = document.getElementById('target-model');
    Elements.targetElevation = document.getElementById('target-elevation');
    Elements.lockProgressBar = document.getElementById('lock-progress-bar');
    Elements.lockProgressFill = document.getElementById('lock-progress-fill');
    Elements.lockIndicator = document.getElementById('lock-indicator');
    Elements.lockX = document.getElementById('lock-x');
    Elements.poiContainer = document.getElementById('poi-container');
    Elements.compassTape = document.getElementById('compass-tape');
    Elements.gimbalPitch = document.getElementById('gimbal-pitch');
    Elements.gimbalHeading = document.getElementById('gimbal-heading');
    Elements.spotlightIndicator = document.getElementById('spotlight-indicator');
    Elements.hoverIndicator = document.getElementById('hover-indicator');
    Elements.orbitIndicator = document.getElementById('orbit-indicator');
    Elements.groundlockIndicator = document.getElementById('groundlock-indicator');
    Elements.trackingStatus = document.getElementById('tracking-status');
    Elements.verticalSpeed = document.getElementById('vertical-speed');
    Elements.groundElevation = document.getElementById('ground-elevation');
    Elements.lrfStatus = document.getElementById('lrf-status');
    Elements.camLat = document.getElementById('cam-lat');
    Elements.camLng = document.getElementById('cam-lng');
    Elements.systemStatus = document.getElementById('system-status');



    
    Elements.postal = document.getElementById('postal');
    Elements.cameraLabel = document.getElementById('camera-label');
    Elements.rappelIndicator = document.getElementById('rappel-indicator');
    Elements.hoverAltitudePanel = document.getElementById('hover-altitude-panel');

    
    Elements.pilotHoverIndicator = document.getElementById('pilot-hover-indicator');
    Elements.pilotHoverAltitude = document.getElementById('pilot-hover-altitude');

    
    Elements.pilotHud = document.getElementById('pilot-hud');
    Elements.pilotTargetId = document.getElementById('pilot-target-id');
    Elements.pilotTargetDetails = document.getElementById('pilot-target-details');
    Elements.pilotTargetPostal = document.getElementById('pilot-target-postal');
    Elements.pilotTargetStreet = document.getElementById('pilot-target-street');
    Elements.pilotTargetHeading = document.getElementById('pilot-target-heading');
    Elements.pilotTargetDistance = document.getElementById('pilot-target-distance');
    Elements.pilotSpotlightIndicator = document.getElementById('pilot-spotlight-indicator');

    
    Elements.azimuthMarker = document.getElementById('azimuth-marker');
    Elements.azimuthValue = document.getElementById('azimuth-value');
    Elements.elevationArc = document.getElementById('elevation-arc');
    Elements.elevationTrack = document.getElementById('elevation-track');
    Elements.elevationMarker = document.getElementById('elevation-marker');
    Elements.elevationValue = document.getElementById('elevation-value');

    
    updateTime();
    setInterval(updateTime, 1000);
});




window.addEventListener('message', (event) => {
    const data = event.data;

    switch (data.action) {
        case 'show':
            showHUD(data);
            break;
        case 'hide':
            hideHUD();
            break;
        case 'update':
            updateHUD(data.data);
            break;
        case 'visionMode':
            setVisionMode(data.mode);
            break;
        case 'targetLocked':
            showTargetLocked(data.info);
            break;
        case 'lockCleared':
            clearTargetLock();
            break;
        case 'toggleUI':
            toggleUIVisibility(data.visible);
            break;
        case 'spotlightOn':
            setSpotlightStatus(true);
            break;
        case 'spotlightOff':
            setSpotlightStatus(false);
            break;
        case 'hoverOn':
            setHoverStatus(true);
            break;
        case 'hoverOff':
            setHoverStatus(false);
            break;
        case 'hoverStatus':
            setHoverStatus(data.active, data.altitude);
            break;
        case 'hoverAltitude':
            if (Elements.hoverAltitudePanel) {
                Elements.hoverAltitudePanel.textContent = data.altitude;
            }
            break;
        case 'updatePilotHUD':
            updatePilotHUD(data.data, data.config);
            break;
        case 'hidePilotHUD':
            hidePilotHUD();
            break;
        case 'applyClientSettings':
            applyClientSettings(data.data);
            break;
    }
});




function showHUD(data) {
    State.visible = true;
    Elements.container.classList.remove('hidden');
    Elements.container.classList.remove('hud-fade-out');
    Elements.container.classList.add('hud-fade-in');

    if (data.visionMode) {
        setVisionMode(data.visionMode);
    }

    
    if (data.highContrast) {
        setHighContrast(data.highContrast.enabled, data.highContrast.theme);
    }

    if (data.trackColors) {
        applyTrackColors(data.trackColors);
    }
}

function hideHUD() {
    State.visible = false;
    Elements.container.classList.remove('hud-fade-in');
    Elements.container.classList.add('hud-fade-out');

    
    setTimeout(() => {
        if (!State.visible) {
            Elements.container.classList.add('hidden');
            Elements.container.classList.remove('hud-fade-out');
        }
    }, 500);

    document.body.classList.remove('nightvision');
}






function updateHUD(data) {
    if (!State.visible) return;

    if (data.highContrast && data.highContrast.enabled !== undefined) {
        setHighContrast(data.highContrast.enabled, data.highContrast.theme);
    }

    if (data.trackColors) {
        applyTrackColors(data.trackColors);
    }

    const dt = getDtSeconds();
    
    const pitchSmoothingHz = 18;
    const azimuthSmoothingHz = 45;
    const pitchAlpha = 1 - Math.exp(-pitchSmoothingHz * dt);
    const azimuthAlpha = 1 - Math.exp(-azimuthSmoothingHz * dt);

    
    if (data.heading !== undefined) {
        State.heading = data.heading;
        if (Elements.heading) Elements.heading.textContent = data.heading;
        updateCompassTape(data.heading);
        if (Elements.gimbalHeading) Elements.gimbalHeading.textContent = data.heading + '°';
    }

    
    if (data.heliHeading !== undefined) {
        if (Elements.heliHeading) Elements.heliHeading.textContent = data.heliHeading + '°';
    }

    
    if (data.heliSpeed !== undefined) {
        const speedUnit = data.heliSpeedUnit || State.speedUnit || 'KTS';
        if (Elements.heliSpeed) Elements.heliSpeed.textContent = data.heliSpeed + ' ' + speedUnit;
    }

    
    if (data.zoom !== undefined) {
        if (Elements.zoomLevel) Elements.zoomLevel.textContent = data.zoom;
    }

    
    if (data.altitude !== undefined) {
        const altUnit = data.altitudeUnit || State.altitudeUnit || 'FT';
        if (Elements.altitude) Elements.altitude.textContent = data.altitude + ' ' + altUnit;
    }

    
    if (data.street) {
        if (Elements.streetName) Elements.streetName.textContent = data.street || 'UNKNOWN';
    }

    
    if (data.pitch !== undefined) {
        State.targetPitch = data.pitch;
    }

    if (data.pitchMin !== undefined) State.pitchMin = data.pitchMin;
    if (data.pitchMax !== undefined) State.pitchMax = data.pitchMax;

    
    State.currentPitch = lerp(State.currentPitch, State.targetPitch, pitchAlpha);
    if (Elements.elevationValue) Elements.elevationValue.textContent = Math.floor(State.currentPitch) + '°';
    updateElevationHalo(State.currentPitch);

    
    
    if (data.heading !== undefined && data.heliHeading !== undefined) {
        State.targetAzimuth = wrap360(data.heading - data.heliHeading);
    }

    
    State.currentAzimuth = lerpAngleDegrees(State.currentAzimuth, State.targetAzimuth, azimuthAlpha);
    if (Elements.azimuthValue) {
        const azimuthDisplay = wrap360(State.currentAzimuth);
        Elements.azimuthValue.textContent = String(Math.floor(azimuthDisplay)).padStart(3, '0') + '°';
    }
    if (Elements.azimuthMarker) {
        
        Elements.azimuthMarker.style.transform = `rotate(${-State.currentAzimuth}deg)`;
        Elements.azimuthMarker.style.transformOrigin = '50% 50%';
    }

    
    if (data.verticalSpeed !== undefined && Elements.verticalSpeed) {
        const vsUnit = data.verticalSpeedUnit || 'FPM';
        Elements.verticalSpeed.textContent = data.verticalSpeed + ' ' + vsUnit;
    }
    if (data.groundElevation !== undefined && Elements.groundElevation) {
        const geUnit = data.groundElevationUnit || State.altitudeUnit || 'FT';
        Elements.groundElevation.textContent = data.groundElevation + ' ' + geUnit;
    }
    if (data.lrfStatus !== undefined && Elements.lrfStatus) {
        Elements.lrfStatus.textContent = data.lrfStatus;
    }
    if (data.lat !== undefined && Elements.camLat) {
        Elements.camLat.textContent = data.lat;
    }
    if (data.lng !== undefined && Elements.camLng) {
        Elements.camLng.textContent = data.lng;
    }
    if (data.systemStatus !== undefined && Elements.systemStatus) {
        Elements.systemStatus.textContent = data.systemStatus;
    }

    
    if (Elements.postal) {
        if (data.postal) {
            Elements.postal.textContent = data.postal;
            Elements.postal.classList.remove('hidden');
        } else {
            Elements.postal.classList.add('hidden');
        }
    }

    
    if (Elements.cameraLabel && data.cameraLabel) {
        Elements.cameraLabel.textContent = data.cameraLabel;
    }

    
    if (data.timeFormat) State.timeFormat = data.timeFormat;
    if (data.dateFormat) State.dateFormat = data.dateFormat;
    if (data.showSeconds !== undefined) State.showSeconds = data.showSeconds;
    if (data.use24Hour !== undefined) State.use24Hour = data.use24Hour;

    
    if (data.hoverActive !== undefined) setHoverStatus(data.hoverActive);
    if (data.orbitActive !== undefined) setOrbitStatus(data.orbitActive);
    if (data.groundLockActive !== undefined) setGroundLockStatus(data.groundLockActive);

    
    if (data.hasTarget && data.targetInfo) {
        State.hasTarget = true;
        updateTargetInfo(data.targetInfo);
        if (Elements.targetPanel) Elements.targetPanel.classList.remove('hidden');
    } else if (!data.hasTarget) {
        State.hasTarget = false;
        if (Elements.targetPanel) Elements.targetPanel.classList.add('hidden');
    }


    updateTrackingStatus();
}




function updateCompassTape(heading) {
    if (!Elements.compassTape) return;
    const offset = -(heading * 3) + 200;
    Elements.compassTape.style.transform = `translateX(${offset}px)`;
}




function updateTime() {
    let now = new Date();
    let suffix = '';

    
    if (State.timeFormat === 'ZULU') {
        
        now = new Date(now.getTime() + now.getTimezoneOffset() * 60000);
        suffix = 'Z';
    }

    let hours = now.getHours();
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');

    
    let ampm = '';
    if (!State.use24Hour) {
        ampm = hours >= 12 ? ' PM' : ' AM';
        hours = hours % 12;
        if (hours === 0) hours = 12;
    }
    hours = String(hours).padStart(2, '0');

    if (Elements.currentTime) {
        let timeStr = `${hours}:${minutes}`;
        if (State.showSeconds) {
            timeStr += `:${seconds}`;
        }
        timeStr += suffix + ampm;
        Elements.currentTime.textContent = timeStr;
    }

    if (Elements.currentDate) {
        const day = String(now.getDate()).padStart(2, '0');
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const yearShort = String(now.getFullYear()).slice(-2);
        const yearFull = String(now.getFullYear());

        let dateStr;
        switch (State.dateFormat) {
            case 'DD/MM/YY':
                dateStr = `${day}/${month}/${yearShort}`;
                break;
            case 'YY/MM/DD':
                dateStr = `${yearShort}/${month}/${day}`;
                break;
            case 'YYYY-MM-DD':
                dateStr = `${yearFull}-${month}-${day}`;
                break;
            case 'MM/DD/YY':
            default:
                dateStr = `${month}/${day}/${yearShort}`;
                break;
        }
        Elements.currentDate.textContent = dateStr;
    }
}




function hexToRgb(hex) {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16)
    } : null;
}

function setHighContrast(enabled, theme) {
    State.highContrastEnabled = !!enabled;
    State.highContrastTheme = theme || 'green';

    
    const classes = Array.from(document.body.classList).filter(c => c.startsWith('highcontrast-'));
    if (classes.length > 0) {
        document.body.classList.remove(...classes);
    }

    
    document.body.style.removeProperty('--hud-color');
    document.body.style.removeProperty('--hud-glow');
    document.body.style.removeProperty('--hud-dim');
    document.body.style.removeProperty('--hud-bg');

    if (State.highContrastEnabled) {
        if (State.highContrastTheme.startsWith('#')) {
            const rgb = hexToRgb(State.highContrastTheme);
            if (rgb) {
                document.body.style.setProperty('--hud-color', State.highContrastTheme);
                document.body.style.setProperty('--hud-glow', `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.6)`);
                document.body.style.setProperty('--hud-dim', `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.8)`);
                document.body.style.setProperty('--hud-bg', `rgba(0, 0, 0, 0.7)`);
            }
        } else {
            document.body.classList.add(`highcontrast-${State.highContrastTheme}`);
        }
    }
}




function setVisionMode(mode) {
    State.visionMode = mode;
    document.body.classList.remove('nightvision');

    if (mode === 'nightvision') {
        document.body.classList.add('nightvision');
        if (Elements.visionMode) Elements.visionMode.textContent = 'WHNV';
    } else if (mode === 'thermal') {
        if (Elements.visionMode) Elements.visionMode.textContent = 'THRM';
    } else {
        if (Elements.visionMode) Elements.visionMode.textContent = 'DAY';
    }
}




function showTargetLocked(info) {
    State.hasTarget = true;
    if (Elements.lockStatus) Elements.lockStatus.textContent = 'TRACK';
    if (Elements.lockX) Elements.lockX.classList.remove('hidden');
    if (Elements.targetPanel) Elements.targetPanel.classList.remove('hidden');
    updateTargetInfo(info);
}

function clearTargetLock() {
    State.hasTarget = false;
    if (Elements.lockStatus) Elements.lockStatus.textContent = 'NONE';
    if (Elements.lockX) Elements.lockX.classList.add('hidden');
    if (Elements.targetPanel) Elements.targetPanel.classList.add('hidden');
}

function updateTargetInfo(info) {
    if (!info) return;
    if (Elements.targetSpeed) Elements.targetSpeed.textContent = (info.speed || 0) + ' MPH';
    if (Elements.targetHeading) Elements.targetHeading.textContent = (info.heading || 0) + '°';
    if (Elements.targetDistance) Elements.targetDistance.textContent = Math.floor(info.distance || 0) + ' M';
    if (Elements.targetElevation && info.coords) Elements.targetElevation.textContent = Math.floor(info.coords.z * 3.28084) + ' FT';
    if (Elements.targetPlate) Elements.targetPlate.textContent = info.plate || '-------';
    if (Elements.targetMake) Elements.targetMake.textContent = info.make || 'UNKNOWN';
    if (Elements.targetModel) Elements.targetModel.textContent = info.model || 'UNKNOWN';
}




function setSpotlightStatus(active) {
    State.spotlightActive = active;
    if (Elements.spotlightIndicator) {
        Elements.spotlightIndicator.classList.toggle('hidden', !active);
    }
}

function ensureHighContrastApplied() {
    if (!State.highContrastEnabled) return;

    const hasHighContrastClass = Array.from(document.body.classList).some(c => c.startsWith('highcontrast-'));
    const hasInlineStyles = document.body.style.getPropertyValue('--hud-color') !== '';

    if (!hasHighContrastClass && !hasInlineStyles) {
        setHighContrast(true, State.highContrastTheme);
    }
}

function setHoverStatus(active, altitude) {
    State.hoverActive = active;

    
    
    ensureHighContrastApplied();

    if (Elements.hoverIndicator) {
        Elements.hoverIndicator.classList.toggle('hidden', !active);
        Elements.hoverIndicator.classList.toggle('blink', active);
    }
    if (Elements.hoverAltitudePanel && altitude !== undefined) {
        Elements.hoverAltitudePanel.textContent = altitude;
    }

    
    if (Elements.pilotHoverIndicator) {
        const showPilotHover = active && !State.visible;
        Elements.pilotHoverIndicator.classList.toggle('hidden', !showPilotHover);
        Elements.pilotHoverIndicator.classList.toggle('blink', showPilotHover);
    }
    if (Elements.pilotHoverAltitude && altitude !== undefined) {
        
        const compactAlt = String(altitude).replace(/\s+FT\b/i, 'FT');
        Elements.pilotHoverAltitude.textContent = compactAlt;
    }
}


function setOrbitStatus(active) {
    State.orbitActive = active;
    if (Elements.orbitIndicator) {
        Elements.orbitIndicator.classList.toggle('hidden', !active);
    }
}

function setGroundLockStatus(active) {
    State.groundLockActive = active;
    if (Elements.groundlockIndicator) {
        Elements.groundlockIndicator.classList.toggle('hidden', !active);
    }
}

function setRappelStatus(available) {
    State.rappelAvailable = available;
    if (Elements.rappelIndicator) {
        Elements.rappelIndicator.classList.toggle('hidden', !available);
    }
}

function updateTrackingStatus() {
    if (!Elements.trackingStatus) return;

    if (State.groundLockActive) {
        Elements.trackingStatus.textContent = 'GND LOCK';
    } else if (State.orbitActive) {
        Elements.trackingStatus.textContent = 'TRK ORBIT';
    } else if (State.hasTarget) {
        Elements.trackingStatus.textContent = 'TRK COR';
    } else if (State.hoverActive) {
        Elements.trackingStatus.textContent = 'HOVER';
    } else {
        Elements.trackingStatus.textContent = 'SLAVE READY';
    }
}




function updateElevationHalo(pitch) {
    const arcEl = Elements.elevationArc || Elements.elevationTrack;
    if (!arcEl || !Elements.elevationMarker) return;

    const radius = 45;
    const centerX = 50;
    const centerY = 50;

    
    
    
    
    const minPitch = typeof State.pitchMin === 'number' ? State.pitchMin : -90;
    const maxPitch = typeof State.pitchMax === 'number' ? State.pitchMax : 30;
    const clampedPitch = clamp(pitch, minPitch, maxPitch);

    
    
    
    const t = (clampedPitch - minPitch) / Math.max(0.0001, (maxPitch - minPitch));
    const endAngle = 225 - (t * 120);
    const startAngle = 105;

    
    const startRad = startAngle * Math.PI / 180;
    const endRad = endAngle * Math.PI / 180;

    const startX = centerX + radius * Math.cos(startRad);
    const startY = centerY + radius * Math.sin(startRad);
    const endX = centerX + radius * Math.cos(endRad);
    const endY = centerY + radius * Math.sin(endRad);

    
    const sweepFlag = 1;

    
    const d = `M ${startX.toFixed(2)} ${startY.toFixed(2)} A ${radius} ${radius} 0 0 ${sweepFlag} ${endX.toFixed(2)} ${endY.toFixed(2)}`;
    arcEl.setAttribute("d", d);

    
    Elements.elevationMarker.setAttribute("cx", endX.toFixed(2));
    Elements.elevationMarker.setAttribute("cy", endY.toFixed(2));
}

function polarToCartesian(centerX, centerY, radius, angleInDegrees) {
    const angleInRadians = (angleInDegrees * Math.PI) / 180.0;
    return {
        x: centerX + (radius * Math.cos(angleInRadians)),
        y: centerY + (radius * Math.sin(angleInRadians))
    };
}




function toggleUIVisibility(visible) {
    State.uiVisible = visible;
    Elements.container.style.opacity = visible ? '1' : '0.2';
}




function updatePilotHUD(data, config) {
    if (!Elements.pilotHud) return;

    
    if (data.highContrast && data.highContrast.enabled !== undefined) {
        setHighContrast(data.highContrast.enabled, data.highContrast.theme);
    }

    if (data.trackColors) {
        applyTrackColors(data.trackColors);
    }

    
    if (config) {
        if (config.Position === 'top-left') {
            Elements.pilotHud.classList.add('top-left');
        } else {
            Elements.pilotHud.classList.remove('top-left');
        }
    }

    
    Elements.pilotHud.classList.remove('hidden');

    
    if (data.targetId && Elements.pilotTargetId) {
        Elements.pilotTargetId.textContent = data.targetId;
    }

    if (data.targetDetails && Elements.pilotTargetDetails) {
        Elements.pilotTargetDetails.textContent = data.targetDetails;
        Elements.pilotTargetDetails.classList.remove('hidden');
    } else if (Elements.pilotTargetDetails) {
        Elements.pilotTargetDetails.classList.add('hidden');
    }

    if (data.postal && Elements.pilotTargetPostal) {
        Elements.pilotTargetPostal.textContent = data.postal;
        Elements.pilotTargetPostal.classList.remove('hidden');
    } else if (Elements.pilotTargetPostal) {
        Elements.pilotTargetPostal.classList.add('hidden');
    }

    if (data.street && Elements.pilotTargetStreet) {
        Elements.pilotTargetStreet.textContent = data.street;
    }

    if (data.headingText && Elements.pilotTargetHeading) {
        Elements.pilotTargetHeading.textContent = data.headingText;
    }
    
    if (data.distance !== undefined && Elements.pilotTargetDistance) {
        Elements.pilotTargetDistance.textContent = Math.floor(data.distance) + ' M';
    }

    
    
    if (data.hoverActive !== undefined) {
        setHoverStatus(!!data.hoverActive, data.hoverAltitude);
    }

    if (Elements.pilotSpotlightIndicator) {
        Elements.pilotSpotlightIndicator.classList.toggle('hidden', !data.spotlightActive);
    }

}

function applyTrackColors(trackColors) {
    if (trackColors.FollowTheme) {
        const styles = getComputedStyle(document.body);
        const hudColor = styles.getPropertyValue('--hud-color').trim();
        const hudDim = styles.getPropertyValue('--hud-dim').trim();

        if (hudColor) {
            document.body.style.setProperty('--track-text-color', hudColor);
        } else {
            document.body.style.removeProperty('--track-text-color');
        }

        if (hudDim) {
            document.body.style.setProperty('--track-dim-color', hudDim);
        } else {
            document.body.style.removeProperty('--track-dim-color');
        }
        return;
    }

    if (trackColors.Color) {
        document.body.style.setProperty('--track-text-color', trackColors.Color);
    } else {
        document.body.style.removeProperty('--track-text-color');
    }

    if (trackColors.DimColor) {
        document.body.style.setProperty('--track-dim-color', trackColors.DimColor);
    } else {
        document.body.style.removeProperty('--track-dim-color');
    }
}

function hidePilotHUD() {
    if (Elements.pilotHud) {
        Elements.pilotHud.classList.add('hidden');
    }
}

function applyClientSettings(data) {
    if (!data) return;

    if (data.highContrast && data.highContrast.enabled !== undefined) {
        setHighContrast(data.highContrast.enabled, data.highContrast.theme);
    }

    if (data.trackColors) {
        applyTrackColors(data.trackColors);
    }
}
