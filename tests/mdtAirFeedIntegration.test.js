const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (relPath) => fs.readFileSync(path.join(root, relPath), 'utf8');

test('MDT integration loads before the PolCam feed registry', () => {
  const manifest = read('fxmanifest.lua');
  assert.match(
    manifest,
    /server\/mdt_integration\.lua'[\s\S]*?server\/main\.lua'/,
  );
  assert.match(manifest, /IsMdtAirFeedAuthorized/);
  assert.match(manifest, /GetMdtDutyState/);
});

test('MDT bridge uses the authoritative server duty export with bounded caching', () => {
  const source = read('server/mdt_integration.lua');
  assert.match(source, /exports\[resource\]:getOfficerDutyState\(source\)/);
  assert.match(source, /config\.DutyCacheMs/);
  assert.match(source, /result\.operator\.onDuty ~= true/);
  assert.match(source, /result\.pilot\.onDuty ~= true/);
  assert.match(source, /config\.FailClosedWhenUnavailable ~= true/);
  assert.match(source, /_G\.CortexPolCamMdtIntegration/);
});

test('all exported air-feed surfaces apply the MDT authorization hook', () => {
  const source = read('server/main.lua');
  assert.match(source, /local function IsAirFeedExportAuthorized\(feed\)/);
  assert.match(source, /GetActiveAirFeeds[\s\S]*?IsAirFeedExportAuthorized\(feed\)/);
  assert.match(source, /GetAirFeedById[\s\S]*?not IsAirFeedExportAuthorized\(feed\)/);
  assert.match(source, /GetTrackedDatalinkTargets[\s\S]*?IsAirFeedExportAuthorized\(feed\)/);
});

test('MDT linking defaults to on-duty operator and pilot', () => {
  const source = read('config.lua');
  assert.match(source, /Config\.MDTIntegration\s*=\s*\{/);
  assert.match(source, /RequireOperatorOnDuty\s*=\s*true/);
  assert.match(source, /RequirePilotOnDuty\s*=\s*true/);
  assert.match(source, /FailClosedWhenUnavailable\s*=\s*false/);
  assert.match(source, /DutyCacheMs\s*=\s*250/);
});
