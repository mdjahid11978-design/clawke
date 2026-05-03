import 'dart:io';

import 'package:client/core/shared_preferences_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug runtime directory produces isolated preferences prefix', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-prefs-runtime-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final repoDir = Directory('${tempDir.path}/clawke')..createSync();
    final clientDir = Directory('${repoDir.path}/client')..createSync();
    File('${clientDir.path}/pubspec.yaml').writeAsStringSync('name: client\n');

    final prefix = resolveDebugSharedPreferencesPrefix(
      startDirectory: clientDir,
      debugMode: true,
      environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
    );

    expect(prefix, startsWith('flutter.clawke.runtime.'));
    expect(prefix, endsWith('.'));
  });

  test('preferences prefix is disabled without runtime directory', () {
    final prefix = resolveDebugSharedPreferencesPrefix(
      startDirectory: Directory.systemTemp,
      debugMode: true,
      environment: const {},
    );

    expect(prefix, isNull);
  });

  test('non debug builds keep default shared preferences prefix', () {
    final prefix = resolveDebugSharedPreferencesPrefix(
      startDirectory: Directory.systemTemp,
      debugMode: false,
      environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
    );

    expect(prefix, isNull);
  });

  test('configure applies isolated prefix exactly once', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-prefs-config-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final repoDir = Directory('${tempDir.path}/clawke')..createSync();
    final clientDir = Directory('${repoDir.path}/client')..createSync();
    File('${clientDir.path}/pubspec.yaml').writeAsStringSync('name: client\n');

    final prefixes = <String>[];
    configureSharedPreferencesRuntimeIsolation(
      startDirectory: clientDir,
      debugMode: true,
      environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
      setPrefix: prefixes.add,
      log: (_) {},
    );

    expect(prefixes, hasLength(1));
    expect(prefixes.single, startsWith('flutter.clawke.runtime.'));
  });
}
