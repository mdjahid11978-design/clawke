const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..', '..');

function sha256File(filePath) {
  return crypto
    .createHash('sha256')
    .update(fs.readFileSync(filePath))
    .digest('hex');
}

test('Windows and Linux desktop bundles use the Clawke app icon', () => {
  const macIconPath = path.join(
    repoRoot,
    'client',
    'macos',
    'Runner',
    'Assets.xcassets',
    'AppIcon.appiconset',
    '1024.png',
  );
  const windowsIconPath = path.join(
    repoRoot,
    'client',
    'windows',
    'runner',
    'resources',
    'app_icon.ico',
  );
  const linuxIconPath = path.join(
    repoRoot,
    'client',
    'linux',
    'runner',
    'resources',
    'app_icon.png',
  );
  const linuxCMake = fs.readFileSync(
    path.join(repoRoot, 'client', 'linux', 'CMakeLists.txt'),
    'utf8',
  );
  const linuxRunner = fs.readFileSync(
    path.join(repoRoot, 'client', 'linux', 'runner', 'my_application.cc'),
    'utf8',
  );

  assert.notEqual(
    sha256File(windowsIconPath),
    'c098d3fc85cacff98b8e69811b48e9f0d852fcee278132d794411d978869cbf8',
  );
  assert.equal(sha256File(linuxIconPath), sha256File(macIconPath));
  assert.match(linuxCMake, /runner\/resources\/app_icon\.png/);
  assert.match(linuxRunner, /gtk_window_set_icon_from_file/);
  assert.match(linuxRunner, /"data", "app_icon\.png"/);
});
