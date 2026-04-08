// lib/services/realtime_location_service.dart
//
// STEP 6 MIGRATION:
//   • Removed: import 'package:cloud_firestore/cloud_firestore.dart'
//   • Removed: import 'firestore_service.dart' → import 'api_service.dart'
//   • Changed: final FirestoreService firestoreService → final ApiService firestoreService
//              (field name kept for constructor compat — type widens to ApiService)
//   • Removed: firestoreService.firestore.collection().doc().update({'lastSeenAt': Timestamp.now()})
//              The Cloud Function watchdog heartbeat was Firestore-specific.
//              NestJS tracks worker activity via updateWorkerLocation() → lastUpdated field.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'auth_service.dart';
import 'api_service.dart';

class RealTimeLocationException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  RealTimeLocationException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() =>
      'RealTimeLocationException: $message${code != null ? ' (Code: $code)' : ''}';
}

class RealTimeLocationService {
  static const Duration updateInterval = Duration(seconds: 30);
  static const Duration positionTimeout = Duration(seconds: 10);
  static const Duration minUpdateInterval = Duration(seconds: 5);
  static const double minDistanceMeters = 50.0;
  static const double significantDistanceMeters = 10.0;
  static const LocationAccuracy trackingAccuracy = LocationAccuracy.high;

  final AuthService authService;
  // STEP 6: type changed from FirestoreService → ApiService
  // Field name kept as 'firestoreService' to avoid changing constructor callsites
  // that pass it positionally.
  final ApiService firestoreService;

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<ServiceStatus>? _serviceStatusStream;
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  Timer? _periodicUpdateTimer;
  bool _isTracking = false;
  bool _isDisposed = false;
  bool? _isWorker;

  RealTimeLocationService(
    this.authService,
    this.firestoreService,
  );

  bool get isTracking => _isTracking && !_isDisposed;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastUpdateTime => _lastUpdateTime;

  Future<void> startTracking({required bool isWorker}) async {
    _ensureNotDisposed();

    if (_isTracking) {
      _logWarning('Location tracking already started');
      return;
    }

    try {
      await _checkAndRequestPermissions();
      await _checkLocationServiceEnabled();

      await stopTracking();

      _isWorker = isWorker;
      _isTracking = true;

      await _startPositionStream();
      _startPeriodicUpdates();
      _startServiceStatusMonitoring();

      _logInfo('Location tracking started (${isWorker ? 'Worker' : 'User'} mode)');
    } catch (e) {
      _isTracking = false;
      _isWorker = null;
      _logError('startTracking', e);
      if (e is RealTimeLocationException) rethrow;
      throw RealTimeLocationException(
        'Failed to start location tracking',
        code: 'START_TRACKING_FAILED',
        originalError: e,
      );
    }
  }

  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    await _positionStream?.cancel();
    _positionStream = null;

    await _serviceStatusStream?.cancel();
    _serviceStatusStream = null;

    _periodicUpdateTimer?.cancel();
    _periodicUpdateTimer = null;

    _isTracking = false;
    _isWorker = null;

    _logInfo('Location tracking stopped');
  }

  Future<Position?> getCurrentPosition() async {
    _ensureNotDisposed();

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: trackingAccuracy,
        timeLimit: positionTimeout,
      );

      _validatePosition(position);
      return position;
    } on TimeoutException {
      _logError('getCurrentPosition', 'Position timeout');
      throw RealTimeLocationException(
        'Location request timed out',
        code: 'POSITION_TIMEOUT',
      );
    } catch (e) {
      _logError('getCurrentPosition', e);
      if (e is RealTimeLocationException) rethrow;
      throw RealTimeLocationException(
        'Failed to get current position',
        code: 'GET_POSITION_FAILED',
        originalError: e,
      );
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw RealTimeLocationException(
        'Location permission denied',
        code: 'PERMISSION_DENIED',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw RealTimeLocationException(
        'Location permission permanently denied. Please enable in settings.',
        code: 'PERMISSION_DENIED_FOREVER',
      );
    }

    _logInfo('Location permission granted: $permission');
  }

  Future<void> _checkLocationServiceEnabled() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw RealTimeLocationException(
        'Location services are disabled. Please enable location services.',
        code: 'LOCATION_SERVICE_DISABLED',
      );
    }

    _logInfo('Location service is enabled');
  }

  Future<void> _startPositionStream() async {
    final locationSettings = LocationSettings(
      accuracy: trackingAccuracy,
      distanceFilter: minDistanceMeters.toInt(),
      timeLimit: positionTimeout,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: _onPositionError,
      cancelOnError: false,
    );
  }

  void _startPeriodicUpdates() {
    _periodicUpdateTimer?.cancel();
    _periodicUpdateTimer = Timer.periodic(updateInterval, (_) async {
      if (!_isTracking || _isWorker == null) return;

      try {
        final position = await getCurrentPosition();
        if (position != null) {
          await _processPositionUpdate(position);
        }
      } catch (e) {
        _logError('_periodicUpdate', e);
      }
    });
  }

  void _startServiceStatusMonitoring() {
    _serviceStatusStream = Geolocator.getServiceStatusStream().listen(
      (ServiceStatus status) {
        _logInfo('Location service status changed: $status');
        if (status == ServiceStatus.disabled) {
          _logWarning('Location service was disabled');
          stopTracking();
        }
      },
      onError: (error) {
        _logError('serviceStatusStream', error);
      },
    );
  }

  void _onPositionUpdate(Position position) {
    if (!_isTracking || _isWorker == null) return;

    try {
      _validatePosition(position);
      _processPositionUpdate(position);
    } catch (e) {
      _logError('_onPositionUpdate', e);
    }
  }

  void _onPositionError(dynamic error) {
    _logError('positionStream', error);

    if (error is LocationServiceDisabledException) {
      _logWarning('Location service disabled, stopping tracking');
      stopTracking();
    }
  }

  /// Persists updated position to the NestJS REST API.
  ///
  /// STEP 6: Removed the Firestore lastSeenAt heartbeat write that used
  /// Timestamp.now() from cloud_firestore. The NestJS updateWorkerLocation()
  /// endpoint already stamps `lastUpdated` on every call, providing the same
  /// signal for the server-side watchdog without Firestore.
  Future<void> _processPositionUpdate(Position position) async {
    if (!_shouldUpdateLocation(position)) {
      return;
    }

    final userId = _getCurrentUserIdOrNull();
    if (userId == null) {
      _logWarning('Cannot update location: user not authenticated');
      return;
    }

    try {
      if (_isWorker == true) {
        await firestoreService.updateWorkerLocation(
          userId,
          position.latitude,
          position.longitude,
        );
      } else {
        await firestoreService.updateUserLocation(
          userId,
          position.latitude,
          position.longitude,
        );
      }

      _lastPosition = position;
      _lastUpdateTime = DateTime.now();

      _logInfo(
        'Location updated: (${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}) '
        'accuracy: ${position.accuracy.toStringAsFixed(1)}m',
      );
    } catch (e) {
      _logError('_processPositionUpdate', e);
    }
  }

  bool _shouldUpdateLocation(Position position) {
    if (_lastPosition == null || _lastUpdateTime == null) {
      return true;
    }

    final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
    if (timeSinceLastUpdate < minUpdateInterval) {
      _logInfo('Skipping update: too soon (${timeSinceLastUpdate.inSeconds}s)');
      return false;
    }

    final distanceFromLast = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    if (distanceFromLast < significantDistanceMeters) {
      _logInfo('Skipping update: insignificant distance (${distanceFromLast.toStringAsFixed(1)}m)');
      return false;
    }

    return true;
  }

  void _validatePosition(Position position) {
    if (position.latitude < -90 || position.latitude > 90) {
      throw RealTimeLocationException(
        'Invalid latitude: ${position.latitude}',
        code: 'INVALID_LATITUDE',
      );
    }

    if (position.longitude < -180 || position.longitude > 180) {
      throw RealTimeLocationException(
        'Invalid longitude: ${position.longitude}',
        code: 'INVALID_LONGITUDE',
      );
    }

    if (position.accuracy < 0) {
      throw RealTimeLocationException(
        'Invalid accuracy: ${position.accuracy}',
        code: 'INVALID_ACCURACY',
      );
    }

    if (position.accuracy > 100) {
      _logWarning('Low accuracy position: ${position.accuracy.toStringAsFixed(1)}m');
    }
  }

  String? _getCurrentUserIdOrNull() {
    try {
      return authService.user?.uid;
    } catch (e) {
      _logError('_getCurrentUserIdOrNull', e);
      return null;
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw RealTimeLocationException(
        'RealTimeLocationService has been disposed',
        code: 'SERVICE_DISPOSED',
      );
    }
  }

  void _logInfo(String message) {
    if (kDebugMode) debugPrint('[RealTimeLocationService] INFO: $message');
  }

  void _logWarning(String message) {
    if (kDebugMode) debugPrint('[RealTimeLocationService] WARNING: $message');
  }

  void _logError(String method, dynamic error) {
    if (kDebugMode) {
      debugPrint('[RealTimeLocationService] ERROR in $method: $error');
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    await stopTracking();
    _lastPosition = null;
    _lastUpdateTime = null;
    _logInfo('RealTimeLocationService disposed');
  }
}
