import 'dart:io';

import 'package:client/core/file_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS debug logger writes to configured or sandbox logs', (
    tester,
  ) async {
    await FileLogger.instance.init();
    final path = await FileLogger.instance.logPath;

    expect(path, isNotNull);
    const runtimeDir = String.fromEnvironment('CLAWKE_RUNTIME_DIR');
    if (runtimeDir.isNotEmpty) {
      expect(path, contains('$runtimeDir/logs/client-'));
    } else {
      expect(path, contains('/logs/client-'));
    }

    const marker = '[TEST] file logger macOS e2e marker';
    FileLogger.instance.log(marker);
    await tester.pump(const Duration(milliseconds: 100));

    final logFile = File(path!);
    expect(logFile.existsSync(), isTrue);
    expect(logFile.readAsStringSync(), contains(marker));
  });
}
