// lib/utils/logger.dart

import 'package:flutter/foundation.dart';

/// Centralized logging utility - replaces print statements
/// 
/// Usage:
/// - AppLogger.info('User logged in')
/// - AppLogger.error('Failed to load data', error, stackTrace)
class AppLogger {
  AppLogger._();

  static const String _prefix = '🔷 Khidmeti';
  static bool _enableLogs = true;

  /// Enable or disable logging
  static void setEnabled(bool enabled) {
    _enableLogs = enabled;
  }

  /// Check if logging is enabled
  static bool get isEnabled => _enableLogs;

  /// Log info message
  static void info(String message, [String? tag]) {
    if (!_enableLogs || !kDebugMode) return;
    final tagStr = tag != null ? '[$tag]' : '';
    debugPrint('$_prefix ℹ️  $tagStr $message');
  }

  /// Log warning message
  static void warning(String message, [String? tag]) {
    if (!_enableLogs || !kDebugMode) return;
    final tagStr = tag != null ? '[$tag]' : '';
    debugPrint('$_prefix ⚠️  $tagStr $message');
  }

  /// Log error message
  static void error(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
    String? tag,
  ]) {
    if (!_enableLogs || !kDebugMode) return;
    final tagStr = tag != null ? '[$tag]' : '';
    debugPrint('$_prefix ❌ $tagStr $message');
    if (error != null) {
      debugPrint('   Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('   StackTrace: $stackTrace');
    }
  }

  /// Log success message
  static void success(String message, [String? tag]) {
    if (!_enableLogs || !kDebugMode) return;
    final tagStr = tag != null ? '[$tag]' : '';
    debugPrint('$_prefix ✅ $tagStr $message');
  }

  /// Log debug message (verbose)
  static void debug(String message, [String? tag]) {
    if (!_enableLogs || !kDebugMode) return;
    final tagStr = tag != null ? '[$tag]' : '';
    debugPrint('$_prefix 🔍 $tagStr $message');
  }

  /// Log network request
  static void network(String method, String url, [int? statusCode]) {
    if (!_enableLogs || !kDebugMode) return;
    final status = statusCode != null ? ' ($statusCode)' : '';
    debugPrint('$_prefix 🌐 $method $url$status');
  }

  /// Log navigation
  static void navigation(String from, String to) {
    if (!_enableLogs || !kDebugMode) return;
    debugPrint('$_prefix 🧭 Navigation: $from → $to');
  }

  /// Log lifecycle event
  static void lifecycle(String event) {
    if (!_enableLogs || !kDebugMode) return;
    debugPrint('$_prefix 📱 Lifecycle: $event');
  }
}
