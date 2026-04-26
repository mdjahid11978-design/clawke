import 'dart:io';

import 'package:client/core/file_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  test('debug log directory resolves to repo runtime logs', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-file-logger-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final repoDir = Directory('${tempDir.path}/clawke')..createSync();
    final clientDir = Directory('${repoDir.path}/client')..createSync();
    File('${clientDir.path}/pubspec.yaml').writeAsStringSync('name: client\n');
    final bundleDir = Directory(
      '${clientDir.path}/build/macos/Build/Products/Debug/Clawke.app/Contents/MacOS',
    )..createSync(recursive: true);

    final logDir = resolveDebugLogDirectory(
      startDirectory: bundleDir,
      debugMode: true,
    );

    expect(logDir?.path, '${repoDir.path}/.runtime/logs');
  });

  test('non debug builds keep sandbox logging', () {
    final logDir = resolveDebugLogDirectory(
      startDirectory: Directory.systemTemp,
      debugMode: false,
    );

    expect(logDir, isNull);
  });

  test('concurrent init prints log path once', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-file-logger-init-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() {
      PathProviderPlatform.instance = originalPlatform;
    });

    final originalDebugPrint = debugPrint;
    var pathPrintCount = 0;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message?.contains('[FileLogger] 📂 Log path:') ?? false) {
        pathPrintCount += 1;
      }
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
    });

    final logger = FileLogger.createForTesting();
    await Future.wait([logger.init(), logger.init()]);

    expect(pathPrintCount, 1);
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return documentsPath;
  }
}
