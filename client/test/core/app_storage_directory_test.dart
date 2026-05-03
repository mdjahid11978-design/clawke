import 'dart:io';

import 'package:client/core/app_storage_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldAvoidDocumentsDirectoryForAppData', () {
    test('avoids the user Documents directory on macOS', () {
      final avoid = shouldAvoidDocumentsDirectoryForAppData(
        Directory('/Users/samy/Documents'),
        isMacOS: true,
        environment: const {'HOME': '/Users/samy'},
      );

      expect(avoid, isTrue);
    });

    test('keeps sandbox Documents directories on macOS', () {
      final avoid = shouldAvoidDocumentsDirectoryForAppData(
        Directory(
          '/Users/samy/Library/Containers/ai.clawke.app/Data/Documents',
        ),
        isMacOS: true,
        environment: const {'HOME': '/Users/samy'},
      );

      expect(avoid, isFalse);
    });

    test('keeps Documents directories on non-macOS platforms', () {
      final avoid = shouldAvoidDocumentsDirectoryForAppData(
        Directory('/Users/samy/Documents'),
        isMacOS: false,
        environment: const {'HOME': '/Users/samy'},
      );

      expect(avoid, isFalse);
    });
  });
}
