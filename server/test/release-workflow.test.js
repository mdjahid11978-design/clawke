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
  const internalDesktopWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'internal-desktop-build.yml'),
    'utf8',
  );
  const androidReleaseSmokeWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'android-release-smoke.yml'),
    'utf8',
  );
  const androidBuildGradle = fs.readFileSync(
    path.join(repoRoot, 'client', 'android', 'app', 'build.gradle.kts'),
    'utf8',
  );
  const linuxCMake = fs.readFileSync(
    path.join(repoRoot, 'client', 'linux', 'CMakeLists.txt'),
    'utf8',
  );
  const windowsCMake = fs.readFileSync(
    path.join(repoRoot, 'client', 'windows', 'CMakeLists.txt'),
    'utf8',
  );
  const windowsRunnerRc = fs.readFileSync(
    path.join(repoRoot, 'client', 'windows', 'runner', 'Runner.rc'),
    'utf8',
  );
  const macosReleaseEntitlements = fs.readFileSync(
    path.join(repoRoot, 'client', 'macos', 'Runner', 'Release.entitlements'),
    'utf8',
  );
  const macosDebugProfileEntitlements = fs.readFileSync(
    path.join(
      repoRoot,
      'client',
      'macos',
      'Runner',
      'DebugProfile.entitlements',
    ),
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

  it('keeps Android signing report out of public GitHub Release assets', () => {
    assert.match(workflow, /name: android-signing-report/);
    assert.doesNotMatch(workflow, /release\/Clawke-\$\{TAG\}-android-signing\.txt/);
  });

  it('keeps Android release builds free of dev-only integration_test registration', () => {
    assert.match(androidBuildGradle, /stripReleaseIntegrationTestPlugin/);
    assert.match(androidBuildGradle, /GeneratedPluginRegistrant\.java/);
    assert.match(androidBuildGradle, /integration_test/);
    assert.match(androidBuildGradle, /compileReleaseJavaWithJavac/);
  });

  it('uses GitHub JavaScript actions with native Node 24 support', () => {
    for (const candidate of [
      workflow,
      internalDesktopWorkflow,
      androidReleaseSmokeWorkflow,
    ]) {
      assert.match(candidate, /actions\/checkout@v6/);
      assert.match(candidate, /actions\/upload-artifact@v7/);
      assert.doesNotMatch(candidate, /actions\/checkout@v4/);
      assert.doesNotMatch(candidate, /actions\/upload-artifact@v4/);
      assert.doesNotMatch(candidate, /FORCE_JAVASCRIPT_ACTIONS_TO_NODE24/);
      assert.doesNotMatch(candidate, /ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION/);
    }
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
    assert.match(macosBuild, /Verify macOS production APNs entitlement/);
    assert.doesNotMatch(macosBuild, /codesign --force --deep --options runtime/);
    assert.match(macosBuild, /find "\$APP_PATH\/Contents\/Frameworks" -maxdepth 1 -name "\*\.framework" -type d -print0/);
    assert.match(macosBuild, /codesign --force --options runtime --timestamp/);
    assert.match(macosBuild, /codesign --verify --deep --strict --verbose=2 "\$APP_PATH"/);
    assert.match(macosBuild, /Missing macOS provisioning profile entitlement/);
    assert.match(macosBuild, /flutter build macos --release/);
    assert.doesNotMatch(macosBuild, /GOOGLE_DESKTOP_CLIENT_ID/);
    assert.match(macosBuild, /com\.google\.GIDSignIn/);
    assert.match(macosVerify, /lipo -archs "\$DMG_EXE_PATH"/);
    assert.match(macosVerify, /grep -qw x86_64/);
    assert.match(macosVerify, /grep -qw arm64/);
    assert.match(macosVerify, /Published macOS binary is not universal/);
    assert.match(macosVerify, /com\.google\.GIDSignIn/);
    assert.doesNotMatch(macosReleaseEntitlements, /com\.apple\.developer\.applesignin/);
    assert.match(
      macosReleaseEntitlements,
      /\$\(AppIdentifierPrefix\)ai\.clawke\.app[\s\S]*\$\(AppIdentifierPrefix\)com\.google\.GIDSignIn/,
    );
    assert.match(
      macosDebugProfileEntitlements,
      /\$\(AppIdentifierPrefix\)ai\.clawke\.app[\s\S]*\$\(AppIdentifierPrefix\)com\.google\.GIDSignIn/,
    );
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
    assert.match(workflow, /clawke\.exe/);
    assert.doesNotMatch(workflow, /client\.exe/);
  });

  it('enables Windows desktop Google OAuth only when the release secret is configured', () => {
    const buildStep = workflow.indexOf('Build Windows');
    const bundleStep = workflow.indexOf('Bundle Visual C++ runtime');
    assert.ok(buildStep > -1, 'Windows workflow must build the Flutter Windows app');
    assert.ok(bundleStep > -1, 'Windows workflow must bundle Visual C++ runtime DLLs');
    assert.ok(buildStep < bundleStep, 'Windows app must be built before bundling runtime DLLs');
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_ID: \$\{\{ secrets\.GOOGLE_DESKTOP_CLIENT_ID \}\}/);
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_SECRET: \$\{\{ secrets\.GOOGLE_DESKTOP_CLIENT_SECRET \}\}/);
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_ID secret is not configured; Windows Google login will remain disabled/);
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_SECRET secret is not configured; Google token exchange may fail/);
    assert.match(workflow, /--dart-define=GOOGLE_DESKTOP_CLIENT_ID=/);
    assert.match(workflow, /--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=/);
    assert.match(workflow, /flutter build windows --release/);
    assert.doesNotMatch(workflow, /GOOGLE_DESKTOP_CLIENT_ID secret is required for Windows Google login/);
  });

  it('builds Linux release artifacts for x64 and ARM64', () => {
    assert.match(workflow, /build-linux-\$\{\{ matrix\.arch \}\}/);
    assert.match(workflow, /ubuntu-24\.04-arm/);
    assert.match(workflow, /Clawke-linux-x64\.tar\.gz/);
    assert.match(workflow, /Clawke-linux-arm64\.tar\.gz/);
    assert.match(workflow, /linux-x64-tar/);
    assert.match(workflow, /linux-arm64-tar/);
    assert.match(workflow, /client\/build\/linux\/x64\/release\/bundle/);
    assert.match(workflow, /client\/build\/linux\/arm64\/release\/bundle/);
    assert.match(workflow, /container_platform: linux\/amd64/);
    assert.match(workflow, /container_platform: linux\/arm64/);
    assert.match(workflow, /Build Linux in Ubuntu 20\.04 container/);
    assert.match(workflow, /ubuntu:20\.04 bash -euxo pipefail -c/);
    assert.match(workflow, /apt-get install -y ca-certificates curl git unzip xz-utils zip clang lld cmake ninja-build pkg-config libgtk-3-dev liblzma-dev binutils file/);
    assert.match(workflow, /git clone --branch "\$FLUTTER_VERSION" --depth 1 https:\/\/github\.com\/flutter\/flutter\.git \/opt\/flutter/);
    assert.match(workflow, /flutter config --enable-linux-desktop/);
    assert.match(workflow, /Building Linux with desktop Google OAuth enabled/);
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_ID secret is required for Linux Google login release builds/);
    assert.match(workflow, /GOOGLE_DESKTOP_CLIENT_SECRET secret is required for Linux Google login release builds/);
    assert.match(workflow, /--dart-define=GOOGLE_DESKTOP_CLIENT_ID=\$\{GOOGLE_DESKTOP_CLIENT_ID\}/);
    assert.match(workflow, /--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=\$\{GOOGLE_DESKTOP_CLIENT_SECRET\}/);
    assert.match(workflow, /readelf --version-info/);
    assert.match(workflow, /requires glibc newer than 2\.31/);
    assert.match(workflow, /Verify Linux binary architecture/);
    assert.match(workflow, /EXE_PATH="\$\{\{ matrix\.bundle_path \}\}\/clawke"/);
    assert.match(workflow, /EXE_PATH="\$VERIFY_DIR\/extract\/clawke"/);
    assert.doesNotMatch(workflow, /\/client"/);
    assert.match(workflow, /ARM aarch64\|aarch64\|ARM64/);
    assert.match(workflow, /Clawke-\$\{TAG\}-linux-arm64\.tar\.gz/);
    assert.match(workflow, /verify-linux-release/);
    assert.match(workflow, /Download and verify published Linux tarball/);
    assert.match(workflow, /gh release download "\$TAG"/);
    assert.match(workflow, /--pattern "Clawke-\$\{TAG\}-linux-\$\{\{ matrix\.arch \}\}\.tar\.gz"/);
    assert.match(workflow, /published-linux-\$\{\{ matrix\.arch \}\}-file\.txt/);
    assert.match(workflow, /Linux ARM64/);
  });

  it('uses Clawke as the desktop executable name', () => {
    assert.match(linuxCMake, /set\(BINARY_NAME "clawke"\)/);
    assert.match(windowsCMake, /project\(clawke LANGUAGES CXX\)/);
    assert.match(windowsCMake, /set\(BINARY_NAME "clawke"\)/);
    assert.match(windowsRunnerRc, /VALUE "OriginalFilename", "clawke\.exe"/);
    assert.match(windowsRunnerRc, /VALUE "ProductName", "Clawke"/);
    assert.doesNotMatch(linuxCMake, /set\(BINARY_NAME "client"\)/);
    assert.doesNotMatch(windowsCMake, /set\(BINARY_NAME "client"\)/);
    assert.doesNotMatch(windowsRunnerRc, /client\.exe/);
  });

  it('keeps internal desktop builds private and covers macOS, Windows, and Linux', () => {
    assert.match(internalDesktopWorkflow, /workflow_dispatch/);
    assert.match(internalDesktopWorkflow, /contents: read/);
    assert.doesNotMatch(internalDesktopWorkflow, /softprops\/action-gh-release/);
    assert.match(internalDesktopWorkflow, /build-macos-universal/);
    assert.match(internalDesktopWorkflow, /Clawke-internal-macOS\.dmg/);
    assert.match(internalDesktopWorkflow, /com\.apple\.developer\.applesignin/);
    assert.match(internalDesktopWorkflow, /build-windows-x64/);
    assert.match(internalDesktopWorkflow, /Clawke-internal-windows-x64\.zip/);
    assert.match(internalDesktopWorkflow, /build-linux-\$\{\{ matrix\.arch \}\}/);
    assert.match(internalDesktopWorkflow, /Clawke-internal-linux-x64\.tar\.gz/);
    assert.match(internalDesktopWorkflow, /Clawke-internal-linux-arm64\.tar\.gz/);
    assert.match(internalDesktopWorkflow, /Build Linux in Ubuntu 20\.04 container/);
    assert.match(internalDesktopWorkflow, /ubuntu:20\.04 bash -euxo pipefail -c/);
    assert.match(internalDesktopWorkflow, /requires glibc newer than 2\.31/);
    assert.match(internalDesktopWorkflow, /release_tag:/);
    assert.match(internalDesktopWorkflow, /refresh-linux-release-assets/);
    assert.match(internalDesktopWorkflow, /actions\/download-artifact@v7/);
    assert.match(internalDesktopWorkflow, /gh release upload "\$RELEASE_TAG"/);
    assert.match(internalDesktopWorkflow, /--clobber/);
    assert.match(internalDesktopWorkflow, /GOOGLE_DESKTOP_CLIENT_SECRET/);
  });
});
