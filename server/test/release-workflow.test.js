const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..', '..');

describe('release workflow guardrails', () => {
  const workflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'release.yml'),
    'utf8',
  );
  const androidBuildGradle = fs.readFileSync(
    path.join(repoRoot, 'client', 'android', 'app', 'build.gradle.kts'),
    'utf8',
  );
  const macosReleaseEntitlements = fs.readFileSync(
    path.join(repoRoot, 'client', 'macos', 'Runner', 'Release.entitlements'),
    'utf8',
  );

  it('requires Android release signing and rejects debug-signed APKs', () => {
    assert.match(workflow, /ANDROID_KEYSTORE_BASE64/);
    assert.match(workflow, /ANDROID_RELEASE_CERT_SHA256/);
    assert.match(workflow, /ANDROID_RELEASE_CERT_SHA1/);
    assert.match(workflow, /client\/android\/key\.properties/);
    assert.match(workflow, /keytool -list -v/);
    assert.match(workflow, /Verify Android Firebase OAuth config/);
    assert.match(workflow, /google-services\.json does not include the release certificate SHA-1/);
    assert.match(workflow, /verify --print-certs/);
    assert.match(workflow, /\/certificate SHA-256 digest\/ \{print \$NF; exit\}/);
    assert.match(workflow, /CN=Android Debug/);
    assert.match(workflow, /Android release APK certificate SHA-256 does not match/);
    assert.match(workflow, /verify-android-release/);
    assert.match(workflow, /gh release download "\$TAG"/);
    assert.match(workflow, /android-signing-report/);
  });

  it('keeps Android release builds free of dev-only integration_test registration', () => {
    assert.match(androidBuildGradle, /stripReleaseIntegrationTestPlugin/);
    assert.match(androidBuildGradle, /GeneratedPluginRegistrant\.java/);
    assert.match(androidBuildGradle, /integration_test/);
    assert.match(androidBuildGradle, /compileReleaseJavaWithJavac/);
  });

  it('builds and verifies macOS releases on macOS 26 with explicit nested signing', () => {
    const macosBuildStart = workflow.indexOf('build-macos:');
    const macosVerifyStart = workflow.indexOf('verify-macos-release:');
    const windowsBuildStart = workflow.indexOf('build-windows:');
    assert.ok(macosBuildStart > -1, 'workflow must include build-macos');
    assert.ok(macosVerifyStart > -1, 'workflow must include verify-macos-release');
    assert.ok(windowsBuildStart > -1, 'workflow must include build-windows');

    const macosBuild = workflow.slice(macosBuildStart, macosVerifyStart);
    const macosVerify = workflow.slice(macosVerifyStart, windowsBuildStart);

    assert.match(macosBuild, /runs-on: macos-26/);
    assert.match(macosVerify, /runs-on: macos-26/);
    assert.match(macosReleaseEntitlements, /com\.apple\.developer\.applesignin/);
    assert.match(macosBuild, /Verify macOS production entitlements/);
    assert.match(macosBuild, /APPLE_SIGNIN=\$\(\/usr\/libexec\/PlistBuddy -c 'Print :com\.apple\.developer\.applesignin:0'/);
    assert.match(macosBuild, /PROFILE_APPLE_SIGNIN=\$\(\/usr\/libexec\/PlistBuddy -c 'Print :Entitlements:com\.apple\.developer\.applesignin:0'/);
    assert.match(macosBuild, /test "\$PROFILE_APPLE_SIGNIN" = "Default"/);
    assert.doesNotMatch(macosBuild, /codesign --force --deep --options runtime/);
    assert.match(macosBuild, /find "\$APP_PATH\/Contents\/Frameworks" -maxdepth 1 -name "\*\.framework" -type d -print0/);
    assert.match(macosBuild, /codesign --force --options runtime --timestamp/);
    assert.match(macosBuild, /codesign --verify --deep --strict --verbose=2 "\$APP_PATH"/);
    assert.match(macosVerify, /com\.apple\.developer\.applesignin/);
  });

  it('bundles the Visual C++ runtime into Windows release zips', () => {
    const bundleStep = workflow.indexOf('Bundle Visual C++ runtime');
    const zipStep = workflow.indexOf('Create ZIP');
    assert.ok(bundleStep > -1, 'Windows workflow must bundle Visual C++ runtime DLLs');
    assert.ok(zipStep > -1, 'Windows workflow must create a release ZIP');
    assert.ok(bundleStep < zipStep, 'Visual C++ runtime DLLs must be copied before zipping');
    assert.match(workflow, /Microsoft\.VC143\.CRT/);
    assert.match(workflow, /msvcp140\.dll/);
    assert.match(workflow, /vcruntime140\.dll/);
    assert.match(workflow, /vcruntime140_1\.dll/);
    assert.match(workflow, /Failed to bundle Visual C\+\+ runtime DLL/);
  });

  it('enables Windows desktop Google OAuth only when the release secret is configured', () => {
    const buildStep = workflow.indexOf('Build Windows');
    const bundleStep = workflow.indexOf('Bundle Visual C++ runtime');
    assert.ok(buildStep > -1, 'Windows workflow must build the Flutter Windows app');
    assert.ok(bundleStep > -1, 'Windows workflow must bundle Visual C++ runtime DLLs');
    assert.ok(buildStep < bundleStep, 'Windows app must be built before bundling runtime DLLs');
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_ID: \$\{\{ secrets\.GOOGLE_DESKTOP_CLIENT_ID \}\}/);
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_ID secret is not configured; Windows Google login will remain disabled/);
    assert.match(workflow, /--dart-define=GOOGLE_DESKTOP_CLIENT_ID=/);
    assert.match(workflow, /flutter build windows --release/);
    assert.doesNotMatch(workflow, /GOOGLE_DESKTOP_CLIENT_ID secret is required for Windows Google login/);
  });
});
