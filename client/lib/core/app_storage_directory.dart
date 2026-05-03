import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> getWritableAppDataDirectory() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  if (shouldAvoidDocumentsDirectoryForAppData(documentsDir)) {
    return getApplicationSupportDirectory();
  }
  return documentsDir;
}

@visibleForTesting
bool shouldAvoidDocumentsDirectoryForAppData(
  Directory documentsDir, {
  bool? isMacOS,
  Map<String, String>? environment,
}) {
  if (!(isMacOS ?? Platform.isMacOS)) return false;

  final home = (environment ?? Platform.environment)['HOME'];
  if (home == null || home.trim().isEmpty) return false;

  final documentPath = p.normalize(documentsDir.absolute.path);
  final homeDocuments = p.normalize(p.join(home, 'Documents'));
  return documentPath == homeDocuments ||
      p.isWithin(homeDocuments, documentPath);
}
