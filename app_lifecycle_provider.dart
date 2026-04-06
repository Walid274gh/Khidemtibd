// lib/providers/app_lifecycle_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// APP LIFECYCLE STATE
// ============================================================================

enum AppLifecycleStateEnum {
  resumed,
  paused,
  inactive,
  detached,
  hidden,
}

// ============================================================================
// APP LIFECYCLE NOTIFIER
// ============================================================================

class AppLifecycleNotifier extends StateNotifier<AppLifecycleStateEnum> {
  static const Duration navigationTimeout           = Duration(minutes: 5);
  static const Duration locationServiceStartTimeout = Duration(seconds: 30);
  static const Duration permissionCheckTimeout      = Duration(seconds: 10);

  DateTime?          _lastStateChange;
  AppLifecycleState? _previousState;

  AppLifecycleNotifier() : super(AppLifecycleStateEnum.resumed) {
    _lastStateChange = DateTime.now();
    _logInfo('AppLifecycleNotifier initialized');
  }

  AppLifecycleStateEnum? get previousState => _mapToEnum(_previousState);
  DateTime?  get lastStateChange  => _lastStateChange;

  Duration? get timeSinceLastChange {
    if (_lastStateChange == null) return null;
    return DateTime.now().difference(_lastStateChange!);
  }

  void updateState(AppLifecycleState newState) {
    if (!mounted) {
      _logWarning('Attempted to update state after disposal');
      return;
    }
    final previousEnum = state;
    final newEnum      = _mapToEnum(newState);

    if (previousEnum == newEnum) {
      _logInfo('App lifecycle state unchanged: $newState');
      return;
    }
    _previousState   = _getCurrentRawState();
    _lastStateChange = DateTime.now();
    state            = newEnum;
    _logStateChange(newState);
  }

  AppLifecycleState? _getCurrentRawState() {
    switch (state) {
      case AppLifecycleStateEnum.resumed:  return AppLifecycleState.resumed;
      case AppLifecycleStateEnum.paused:   return AppLifecycleState.paused;
      case AppLifecycleStateEnum.inactive: return AppLifecycleState.inactive;
      case AppLifecycleStateEnum.detached: return AppLifecycleState.detached;
      case AppLifecycleStateEnum.hidden:   return AppLifecycleState.hidden;
    }
  }

  AppLifecycleStateEnum _mapToEnum(AppLifecycleState? rawState) {
    if (rawState == null) return AppLifecycleStateEnum.resumed;
    switch (rawState) {
      case AppLifecycleState.resumed:  return AppLifecycleStateEnum.resumed;
      case AppLifecycleState.paused:   return AppLifecycleStateEnum.paused;
      case AppLifecycleState.inactive: return AppLifecycleStateEnum.inactive;
      case AppLifecycleState.detached: return AppLifecycleStateEnum.detached;
      case AppLifecycleState.hidden:   return AppLifecycleStateEnum.hidden;
    }
  }

  // FIX (README2): removed `break` statements — dead code in Dart switch.
  void _logStateChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:  _logInfo('App resumed (foreground)');
      case AppLifecycleState.paused:   _logInfo('App paused (background)');
      case AppLifecycleState.inactive: _logInfo('App inactive');
      case AppLifecycleState.detached: _logWarning('App detached (closing)');
      case AppLifecycleState.hidden:   _logInfo('App hidden');
    }
  }

  void _logInfo(String message) {
    if (kDebugMode) debugPrint('[AppLifecycle] INFO: $message');
  }

  void _logWarning(String message) {
    if (kDebugMode) debugPrint('[AppLifecycle] WARNING: $message');
  }

  @override
  void dispose() {
    _logInfo('AppLifecycleNotifier disposed');
    super.dispose();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final appLifecycleProvider =
    StateNotifierProvider<AppLifecycleNotifier, AppLifecycleStateEnum>(
        (ref) => AppLifecycleNotifier());

final isAppInForegroundProvider = Provider<bool>((ref) {
  return ref.watch(appLifecycleProvider) == AppLifecycleStateEnum.resumed;
});

final isAppInBackgroundProvider = Provider<bool>((ref) {
  return ref.watch(appLifecycleProvider) == AppLifecycleStateEnum.paused;
});

final timeSinceLastStateChangeProvider = Provider<Duration?>((ref) {
  return ref.watch(appLifecycleProvider.notifier).timeSinceLastChange;
});
