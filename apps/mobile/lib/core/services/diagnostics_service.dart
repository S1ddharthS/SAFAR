import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SafarDiagnosticLevel { info, warning, error }

enum DiagnosticCategory {
  framework,
  network,
  auth,
  realtime,
  sync,
  storage,
  location,
}

const Set<String> _sensitiveKeys = {
  'password',
  'token',
  'ticket',
  'secret',
  'authorization',
  'cookie',
  'key',
  'csrf',
  'text_content',
  'text',
  'lat',
  'lon',
  'coordinates',
  'private_memory',
};

Map<String, dynamic> sanitizeDetails(Map<String, dynamic> raw) {
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    final keyLower = entry.key.toLowerCase();
    if (_sensitiveKeys.any((s) => keyLower.contains(s))) {
      result[entry.key] = '<redacted>';
    } else if (entry.value is Map<String, dynamic>) {
      result[entry.key] = sanitizeDetails(entry.value as Map<String, dynamic>);
    } else if (entry.value is List) {
      result[entry.key] = (entry.value as List).map((item) {
        if (item is Map<String, dynamic>) return sanitizeDetails(item);
        return item;
      }).toList();
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

class DiagnosticEntry {
  const DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.details,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final SafarDiagnosticLevel level;
  final DiagnosticCategory category;
  final String message;
  final Map<String, dynamic>? details;
  final Object? error;
  final StackTrace? stackTrace;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'category': category.name,
        'message': message,
        if (details != null && details!.isNotEmpty) 'details': details,
        if (error != null && error.toString().isNotEmpty) 'error': error.toString(),
      };
}

class DiagnosticsService {
  DiagnosticsService({this.maxEntries = 100});

  static final DiagnosticsService instance = DiagnosticsService();

  final int maxEntries;
  final Queue<DiagnosticEntry> _buffer = Queue<DiagnosticEntry>();

  void record({
    required DiagnosticCategory category,
    required String message,
    SafarDiagnosticLevel level = SafarDiagnosticLevel.info,
    Map<String, dynamic>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = DiagnosticEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      details: details != null ? sanitizeDetails(details) : null,
      error: error,
      stackTrace: stackTrace,
    );

    if (_buffer.length >= maxEntries) {
      _buffer.removeFirst();
    }
    _buffer.add(entry);

    if (kDebugMode && level == SafarDiagnosticLevel.error) {
      debugPrint('[SAFAR-ERROR][${category.name}] $message: $error');
    }
  }

  void recordError(
    DiagnosticCategory category,
    String message,
    Object? error, [
    StackTrace? stackTrace,
  ]) {
    record(
      category: category,
      message: message,
      level: SafarDiagnosticLevel.error,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void recordNetwork(
    String path,
    String method,
    int? statusCode,
    int durationMs, {
    String? error,
  }) {
    final isFailure = statusCode == null || statusCode >= 400;
    record(
      category: DiagnosticCategory.network,
      level: isFailure ? SafarDiagnosticLevel.warning : SafarDiagnosticLevel.info,
      message: '$method $path -> ${statusCode ?? 'ERROR'} (${durationMs}ms)',
      details: {
        'path': path,
        'method': method,
        'statusCode': statusCode,
        'durationMs': durationMs,
        if (error != null && error.isNotEmpty) 'error': error,
      },
      error: error,
    );
  }

  void recordRealtime(
    String event,
    String status, {
    String? tripId,
    Map<String, dynamic>? details,
  }) {
    final combinedDetails = <String, dynamic>{
      'status': status,
      if (tripId != null && tripId.isNotEmpty) 'tripId': tripId,
      if (details != null && details.isNotEmpty) ...details,
    };
    record(
      category: DiagnosticCategory.realtime,
      message: 'WebSocket: $event ($status)',
      details: combinedDetails,
    );
  }

  void recordSync(
    String status,
    int count, {
    String? tripId,
    String? error,
  }) {
    record(
      category: DiagnosticCategory.sync,
      level: error != null ? SafarDiagnosticLevel.warning : SafarDiagnosticLevel.info,
      message: 'Offline Sync: $status (items: $count)',
      details: {
        'status': status,
        'count': count,
        if (tripId != null && tripId.isNotEmpty) 'tripId': tripId,
        if (error != null && error.isNotEmpty) 'error': error,
      },
      error: error,
    );
  }

  List<DiagnosticEntry> getEntries({
    int limit = 50,
    DiagnosticCategory? category,
    SafarDiagnosticLevel? minLevel,
  }) {
    var items = _buffer.toList();
    if (category != null) {
      items = items.where((e) => e.category == category).toList();
    }
    if (minLevel != null) {
      items = items.where((e) => e.level.index >= minLevel.index).toList();
    }
    if (items.length > limit) {
      items = items.sublist(items.length - limit);
    }
    return items;
  }

  void clear() {
    _buffer.clear();
  }

  static void setupGlobalErrorHandling() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      instance.recordError(
        DiagnosticCategory.framework,
        details.exceptionAsString(),
        details.exception,
        details.stack,
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      instance.recordError(
        DiagnosticCategory.framework,
        'Unhandled async error: $error',
        error,
        stack,
      );
      return true; // handled
    };
  }
}

final diagnosticsProvider = Provider<DiagnosticsService>((ref) {
  return DiagnosticsService.instance;
});
