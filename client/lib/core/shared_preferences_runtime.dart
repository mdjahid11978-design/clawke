import 'dart:convert';
import 'dart:io';

import 'package:client/core/debug_runtime_directory.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SharedPreferencesPrefixSetter = void Function(String prefix);
typedef RuntimeIsolationLogger = void Function(String message);

String? resolveDebugSharedPreferencesPrefix({
  Directory? startDirectory,
  bool debugMode = kDebugMode,
  Map<String, String>? environment,
}) {
  final runtimeDir = resolveDebugRuntimeDirectory(
    startDirectory: startDirectory,
    debugMode: debugMode,
    environment: environment,
  );
  if (runtimeDir == null) return null;

  final digest = sha1.convert(utf8.encode(runtimeDir.path)).toString();
  return 'flutter.clawke.runtime.${digest.substring(0, 12)}.';
}

void configureSharedPreferencesRuntimeIsolation({
  Directory? startDirectory,
  bool debugMode = kDebugMode,
  Map<String, String>? environment,
  SharedPreferencesPrefixSetter? setPrefix,
  RuntimeIsolationLogger? log,
}) {
  final prefix = resolveDebugSharedPreferencesPrefix(
    startDirectory: startDirectory,
    debugMode: debugMode,
    environment: environment,
  );
  if (prefix == null) return;

  (setPrefix ?? SharedPreferences.setPrefix)(prefix);
  (log ?? debugPrint)('[SharedPreferences] 🔒 runtime prefix: $prefix');
}
