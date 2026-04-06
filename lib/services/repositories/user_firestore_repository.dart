// lib/services/repositories/user_firestore_repository.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user_model.dart';
import 'firestore_cache.dart';
import 'firestore_repository_base.dart';

class UserFirestoreRepository extends FirestoreRepositoryBase {
  static const String usersCollection = 'users';

  final FirestoreCache<UserModel> _cache;

  UserFirestoreRepository(super.firestore)
      : _cache = FirestoreCache<UserModel>(
          ttl: const Duration(minutes: 15),
          maxSize: 100,
          tag: '[UserRepo]',
        );

  // FIX: renamed from `_logTag` (library-private — cannot be overridden across
  // files in Dart) to `logTag` (public). See firestore_repository_base.dart.
  @override
  String get logTag => '[UserRepo]';

  // --------------------------------------------------------------------------
  // READ
  // --------------------------------------------------------------------------

  Future<UserModel?> getUser(String userId) async {
    ensureNotDisposed();
    if (userId.trim().isEmpty) {
      logWarning('getUser called with empty userId');
      return null;
    }

    final cached = _cache.get(userId);
    if (cached != null) return cached;

    return retryOperation(() async {
      try {
        final doc = await firestore
            .collection(usersCollection)
            .doc(userId)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);

        if (!doc.exists || doc.data() == null) {
          logWarning('User not found: $userId');
          return null;
        }

        final user = UserModel.fromMap(doc.data()!, doc.id);
        _cache.set(userId, user);
        return user;
      } on TimeoutException {
        logError('getUser', 'Timeout fetching user: $userId');
        return null;
      } catch (e) {
        logError('getUser', e);
        return null;
      }
    });
  }

  // --------------------------------------------------------------------------
  // WRITE
  // --------------------------------------------------------------------------

  Future<void> setUser(UserModel user) async {
    ensureNotDisposed();
    validateUserId(user.id);

    return retryOperation(() async {
      try {
        await firestore
            .collection(usersCollection)
            .doc(user.id)
            .set(user.toMap(), SetOptions(merge: true))
            .timeout(FirestoreRepositoryBase.operationTimeout);

        _cache.set(user.id, user);
        logInfo('User saved: ${user.id}');
      } catch (e) {
        logError('setUser', e);
        throw FirestoreServiceException(
          'Error saving user',
          code: 'USER_SAVE_FAILED',
          originalError: e,
        );
      }
    });
  }

  Future<void> createOrUpdateUser(UserModel user) => setUser(user);

  Future<void> updateUserLocation(
    String userId,
    double latitude,
    double longitude,
  ) async {
    ensureNotDisposed();
    validateUserId(userId);
    validateCoordinates(latitude, longitude);

    return retryOperation(() async {
      try {
        await firestore.collection(usersCollection).doc(userId).update({
          'latitude': latitude,
          'longitude': longitude,
          'lastUpdated': Timestamp.now(),
        }).timeout(FirestoreRepositoryBase.operationTimeout);

        _cache.update(
            userId,
            (u) => u.copyWith(
                  latitude: latitude,
                  longitude: longitude,
                  lastUpdated: DateTime.now(),
                ));
        logInfo('User location updated: $userId');
      } catch (e) {
        logError('updateUserLocation', e);
        rethrow;
      }
    });
  }

  Future<void> updateFcmToken(String userId, String token) async {
    ensureNotDisposed();
    validateUserId(userId);

    if (token.trim().isEmpty) {
      throw FirestoreServiceException(
        'FCM token cannot be empty',
        code: 'INVALID_FCM_TOKEN',
      );
    }

    return retryOperation(() async {
      try {
        await firestore.collection(usersCollection).doc(userId).update({
          'fcmToken': token,
          'lastFcmTokenUpdate': Timestamp.now(),
        }).timeout(FirestoreRepositoryBase.operationTimeout);

        logInfo('FCM token updated for user: $userId');
      } catch (e) {
        logError('updateFcmToken', e);
        rethrow;
      }
    });
  }

  // --------------------------------------------------------------------------
  // CACHE MANAGEMENT
  // --------------------------------------------------------------------------

  void cacheUser(String userId, UserModel user) => _cache.set(userId, user);

  void cleanExpiredCache() => _cache.cleanExpired();

  void clearCache() => _cache.clear();

  // --------------------------------------------------------------------------
  // DISPOSE
  // --------------------------------------------------------------------------

  void dispose() {
    if (isDisposed) return;
    markDisposed();
    _cache.clear();
    logInfo('UserFirestoreRepository disposed');
  }
}
