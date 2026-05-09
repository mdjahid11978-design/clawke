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
});
