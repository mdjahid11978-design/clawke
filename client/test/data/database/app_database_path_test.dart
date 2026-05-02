import 'dart:io';

import 'package:client/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'configured debug database file resolves under runtime directory',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'clawke-db-path-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final repoDir = Directory('${tempDir.path}/clawke')..createSync();
      final clientDir = Directory('${repoDir.path}/client')..createSync();
      File(
        '${clientDir.path}/pubspec.yaml',
      ).writeAsStringSync('name: client\n');

      final file = await resolveDatabaseFile(
        'test_uid',
        startDirectory: clientDir,
        environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
      );

      expect(file.path, '${repoDir.path}/.runtime/db/clawke_test_uid.db');
    },
  );
}
