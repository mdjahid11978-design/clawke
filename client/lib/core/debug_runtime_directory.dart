import 'dart:io';

import 'package:flutter/foundation.dart';

Directory? resolveDebugRuntimeDirectory({
  Directory? startDirectory,
  bool debugMode = kDebugMode,
}) {
  if (!debugMode) return null;

  for (final start in _debugSearchStarts(startDirectory)) {
    final clientDir = _findClientDirectory(start);
    if (clientDir == null) continue;
    return Directory('${clientDir.parent.path}/.runtime');
  }

  return null;
}

List<Directory> _debugSearchStarts(Directory? startDirectory) {
  if (startDirectory != null) return [startDirectory];
  return [Directory.current, File(Platform.resolvedExecutable).parent];
}

Directory? _findClientDirectory(Directory start) {
  var current = start.absolute;
  for (var depth = 0; depth < 24; depth += 1) {
    final directClient = Directory('${current.path}/client');
    if (_isFlutterClientDirectory(directClient)) return directClient;
    if (_isFlutterClientDirectory(current)) return current;

    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}

bool _isFlutterClientDirectory(Directory dir) {
  final name = dir.path.split(Platform.pathSeparator).last;
  return name == 'client' && File('${dir.path}/pubspec.yaml').existsSync();
}
