// lib/services/repositories/firestore_repository_base.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// EXCEPTION
// ============================================================================

class FirestoreServiceException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  FirestoreServiceException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() =>
      'FirestoreServiceException: $message'
      '${code != null ? ' (Code: $code)' : ''}';
}

// ============================================================================
// BASE REPOSITORY
// ============================================================================

abstract class FirestoreRepositoryBase {
  static const Duration operationTimeout = Duration(seconds: 10);
  static const int maxRetries = 3;
  static const Duration baseRetryDelay = Duration(seconds: 2);

  // Firebase error codes that are deterministic and must NOT be retried.
  // Retrying them wastes 4–6 seconds before surfacing the error.
  //   permission-denied  : Firestore security rules blocked the request.
  //   unauthenticated    : No valid Firebase Auth session.
  //   not-found          : Document/collection does not exist.
  //   already-exists     : Document already present.
  //   resource-exhausted : Quota exceeded — retrying immediately makes it worse.
  static const Set<String> _nonRetriableFirebaseCodes = {
    'permission-denied',
    'unauthenticated',
    'not-found',
    'already-exists',
    'resource-exhausted',
  };

  final FirebaseFirestore firestore;
  bool _isDisposed = false;

  FirestoreRepositoryBase(this.firestore);

  // FIX (Engineer): The original abstract getter was declared as `_logTag`
  // (library-private). In Dart, members prefixed with `_` are private to the
  // file they are declared in — they cannot be overridden across file
  // boundaries. Every subclass that wrote `@override String get _logTag` was
  // silently creating a new, unrelated field in its own library. The base
  // class logInfo/logWarning/logError methods resolved `_logTag` to their own
  // file's private field (empty string), so every repository printed `INFO:`
  // with no tag instead of `[UserRepo] INFO:`, `[WorkerRepo] INFO:`, etc.
  //
  // Fix: renamed to `logTag` (public). All repository subclasses must update
  // their override accordingly:
  //
  //   BEFORE:  @override String get _logTag => '[UserRepo]';
  //   AFTER:   @override String get logTag  => '[UserRepo]';
  //
  // Files to update:
  //   - user_firestore_repository.dart
  //   - worker_firestore_repository.dart
  //   - geo_cell_firestore_repository.dart
  //   - service_request_firestore_repository.dart  (already patched in dossier 1)
  String get logTag;

  bool get isDisposed => _isDisposed;

  void markDisposed() {
    _isDisposed = true;
  }

  // --------------------------------------------------------------------------
  // Guard
  // --------------------------------------------------------------------------

  void ensureNotDisposed() {
    if (_isDisposed) {
      throw FirestoreServiceException(
        'Repository has been disposed',
        code: 'SERVICE_DISPOSED',
      );
    }
  }

  // --------------------------------------------------------------------------
  // Retry
  // --------------------------------------------------------------------------

  Future<T> retryOperation<T>(Future<T> Function() operation) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        return await operation();
      } on FirebaseException catch (e) {
        // Non-retriable Firebase errors are rethrown immediately.
        if (_nonRetriableFirebaseCodes.contains(e.code)) {
          logWarning(
            'Non-retriable Firebase error (${e.code}) — not retrying.',
          );
          rethrow;
        }
        attempts++;
        if (attempts >= maxRetries) rethrow;
        final delay = baseRetryDelay * attempts;
        logWarning('Retry $attempts/$maxRetries after ${delay.inSeconds}s '
            '(Firebase error: ${e.code})');
        await Future.delayed(delay);
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) rethrow;
        final delay = baseRetryDelay * attempts;
        logWarning('Retry $attempts/$maxRetries after ${delay.inSeconds}s');
        await Future.delayed(delay);
      }
    }
    throw FirestoreServiceException(
      'Max retries exceeded',
      code: 'MAX_RETRIES_EXCEEDED',
    );
  }

  // --------------------------------------------------------------------------
  // Validation helpers
  // --------------------------------------------------------------------------

  void validateUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw FirestoreServiceException(
        'User ID cannot be empty',
        code: 'INVALID_USER_ID',
      );
    }
  }

  void validateWorkerId(String workerId) {
    if (workerId.trim().isEmpty) {
      throw FirestoreServiceException(
        'Worker ID cannot be empty',
        code: 'INVALID_WORKER_ID',
      );
    }
  }

  void validateCoordinates(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) {
      throw FirestoreServiceException(
        'Invalid latitude: $latitude',
        code: 'INVALID_LATITUDE',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw FirestoreServiceException(
        'Invalid longitude: $longitude',
        code: 'INVALID_LONGITUDE',
      );
    }
  }

  // --------------------------------------------------------------------------
  // Logging — use logTag (public) so subclass overrides work across files
  // --------------------------------------------------------------------------

  void logInfo(String message) {
    if (kDebugMode) debugPrint('$logTag INFO: $message');
  }

  void logWarning(String message) {
    if (kDebugMode) debugPrint('$logTag WARNING: $message');
  }

  void logError(String method, dynamic error) {
    if (kDebugMode) debugPrint('$logTag ERROR in $method: $error');
  }
}
