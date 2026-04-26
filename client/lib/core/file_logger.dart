// 文件日志工具 — 将关键 WS 消息路由信息写入文件，用于排查跨会话路由 Bug
//
// 所有平台统一使用 getApplicationSupportDirectory：
//   macOS:   ~/Library/Containers/ai.clawke.app/Data/Library/Application Support/ai.clawke.app/logs/
//   Windows: C:\Users\<user>\AppData\Roaming\ai.clawke.app\logs\
//   Linux:   ~/.local/share/ai.clawke.app/logs/
//   iOS/Android: <app sandbox>/logs/
//
// 文件名：client-YYYY-MM-DD.log
// 仅记录关键路由事件，不会过度写入
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileLogger {
  FileLogger._();
  static final FileLogger instance = FileLogger._();

  @visibleForTesting
  factory FileLogger.createForTesting() => FileLogger._();

  File? _logFile;
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> init() async {
    if (_initialized) return;
    final running = _initializing;
    if (running != null) return running;

    final initFuture = _initOnce();
    _initializing = initFuture;
    await initFuture;
  }

  Future<void> _initOnce() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sandboxLogDir = Directory('${appDir.path}/logs');
      final logDir = resolveDebugLogDirectory() ?? sandboxLogDir;
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      _logFile = File('${logDir.path}/client-$date.log');
      _initialized = true;
      debugPrint('[FileLogger] 📂 Log path: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[FileLogger] ❌ Init failed: $e');
    } finally {
      _initializing = null;
    }
  }

  /// 写入一行日志（异步，不阻塞 UI）
  void log(String message) {
    init().then((_) {
      final ts = DateTime.now().toIso8601String();
      _logFile?.writeAsStringSync(
        '[$ts] $message\n',
        mode: FileMode.append,
        flush: false,
      );
    });
  }

  /// 获取日志文件路径（供调试用）
  Future<String?> get logPath async {
    await init();
    return _logFile?.path;
  }
}

@visibleForTesting
Directory? resolveDebugLogDirectory({
  Directory? startDirectory,
  bool debugMode = kDebugMode,
}) {
  if (!debugMode) return null;

  for (final start in _debugSearchStarts(startDirectory)) {
    final clientDir = _findClientDirectory(start);
    if (clientDir == null) continue;
    return Directory('${clientDir.parent.path}/.runtime/logs');
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
