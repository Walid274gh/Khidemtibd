// lib/services/repositories/worker_firestore_repository.dart
//
// TASK 2 FIX — Extracted online-worker stream queries from HomeController.
//
// NEW METHODS:
//   • streamOnlineWorkersByWilayas(wilayaCodes): streams online workers whose
//     wilayaCode is in the provided list. Previously called directly via
//     FirebaseFirestore.instance in HomeController._subscribeToNearbyWorkers().
//   • streamOnlineWorkersUnscoped({limit}): fallback stream for all online
//     workers up to [limit]. Previously called via FirebaseFirestore.instance
//     in HomeController._subscribeFallback().
//
// The HomeController is now DI-clean: it uses these methods via
// firestoreServiceProvider and no longer holds a direct Firestore dependency.
//
// ALGO FIX (A9): updateWorkerStatus() previously never wrote lastActiveAt.
// This meant workerScore()'s recency component (10% weight) always received
// daysSinceActive=0 (the default fallback), making all workers appear equally
// fresh regardless of when they last went offline. The recency signal was
// effectively dead.
//
// Fix: when isOnline transitions to false, write lastActiveAt: Timestamp.now()
// so that the daysSinceActive field (computed from lastActiveAt in
// WorkerModel.fromMap or model_extensions) accurately reflects time offline.
// When isOnline=true we do NOT overwrite lastActiveAt — going back online
// doesn't reset "last seen offline" (that would be semantically wrong).
//
// [AUTO FIX] streamOnlineWorkersByWilayas: added .limit(150) to cap Firestore
// reads. Without a limit, a wilaya with hundreds of online workers would
// return all documents on every snapshot, exhausting read quota unnecessarily.
// 150 covers the busiest known wilaya with headroom; tune upward if needed.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/worker_model.dart';
import 'firestore_cache.dart';
import 'firestore_repository_base.dart';

class WorkerFirestoreRepository extends FirestoreRepositoryBase {
  static const String workersCollection = 'workers';

  final FirestoreCache<WorkerModel> _cache;

  WorkerFirestoreRepository(super.firestore)
      : _cache = FirestoreCache<WorkerModel>(
          ttl: const Duration(minutes: 15),
          maxSize: 100,
          tag: '[WorkerRepo]',
        );

  @override
  String get logTag => '[WorkerRepo]';

  // --------------------------------------------------------------------------
  // READ
  // --------------------------------------------------------------------------

  Future<WorkerModel?> getWorker(String workerId) async {
    ensureNotDisposed();
    if (workerId.trim().isEmpty) {
      logWarning('getWorker called with empty workerId');
      return null;
    }

    final cached = _cache.get(workerId);
    if (cached != null) return cached;

    return retryOperation(() async {
      try {
        final doc = await firestore
            .collection(workersCollection)
            .doc(workerId)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);

        if (!doc.exists || doc.data() == null) {
          logWarning('Worker not found: $workerId');
          return null;
        }

        final worker = WorkerModel.fromMap(doc.data()!, doc.id);
        _cache.set(workerId, worker);
        return worker;
      } on TimeoutException {
        logError('getWorker', 'Timeout fetching worker: $workerId');
        return null;
      } catch (e) {
        logError('getWorker', e);
        return null;
      }
    });
  }

  Stream<WorkerModel?> streamWorker(String workerId) {
    if (workerId.trim().isEmpty) {
      logWarning('streamWorker called with empty workerId');
      return Stream.value(null);
    }

    return firestore
        .collection(workersCollection)
        .doc(workerId)
        .snapshots()
        .handleError((Object error, StackTrace stack) {
          logError('streamWorker', error);
          throw error;
        })
        .map((doc) {
          try {
            if (!doc.exists || doc.data() == null) return null;
            final worker = WorkerModel.fromMap(doc.data()!, doc.id);
            _cache.set(workerId, worker);
            return worker;
          } catch (e) {
            logError('streamWorker.parsing', e);
            return null;
          }
        });
  }

  // --------------------------------------------------------------------------
  // TASK 2 — NEARBY WORKER STREAMS (extracted from HomeController)
  // --------------------------------------------------------------------------

  /// Streams online workers whose wilayaCode is in [wilayaCodes].
  ///
  /// Previously this query was constructed directly in
  /// HomeController._subscribeToNearbyWorkers() via FirebaseFirestore.instance,
  /// bypassing DI and making the controller untestable. Now injected through
  /// firestoreServiceProvider.
  ///
  /// The controller still handles distance filtering and sorting on the
  /// returned list — those are business concerns, not data concerns.
  ///
  /// [AUTO FIX] Added .limit(150) — caps Firestore reads per snapshot.
  /// Without a limit a busy wilaya (e.g. Algiers) could return thousands of
  /// worker documents on every real-time update, exhausting read quota.
  /// 150 covers the busiest known wilaya with headroom; increase if needed.
  Stream<List<WorkerModel>> streamOnlineWorkersByWilayas(List<int> wilayaCodes) {
    if (wilayaCodes.isEmpty) {
      logWarning('streamOnlineWorkersByWilayas called with empty wilayaCodes');
      return Stream.value([]);
    }
    return firestore
        .collection(workersCollection)
        .where('isOnline', isEqualTo: true)
        .where('wilayaCode', whereIn: wilayaCodes)
        .limit(150)
        .snapshots()
        .handleError((Object e) => logError('streamOnlineWorkersByWilayas', e))
        .map((s) => s.docs.map((doc) {
              try {
                return WorkerModel.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id);
              } catch (e) {
                logError('streamOnlineWorkersByWilayas.parsing', e);
                return null;
              }
            }).whereType<WorkerModel>().toList());
  }

  /// Fallback stream: all online workers up to [limit], with no wilaya filter.
  ///
  /// Previously constructed directly in HomeController._subscribeFallback().
  /// Used when the wilaya lookup fails or the composite index is not yet built.
  Stream<List<WorkerModel>> streamOnlineWorkersUnscoped({int limit = 100}) {
    return firestore
        .collection(workersCollection)
        .where('isOnline', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .handleError((Object e) => logError('streamOnlineWorkersUnscoped', e))
        .map((s) => s.docs.map((doc) {
              try {
                return WorkerModel.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id);
              } catch (e) {
                logError('streamOnlineWorkersUnscoped.parsing', e);
                return null;
              }
            }).whereType<WorkerModel>().toList());
  }

  // --------------------------------------------------------------------------
  // QUERY HELPERS
  // --------------------------------------------------------------------------

  Future<List<WorkerModel>> getWorkersInCell({
    required String cellId,
    String? serviceType,
    bool onlineOnly = false,
  }) async {
    ensureNotDisposed();
    if (cellId.trim().isEmpty) {
      logWarning('getWorkersInCell called with empty cellId');
      return [];
    }

    return retryOperation(() async {
      try {
        Query query = firestore
            .collection(workersCollection)
            .where('cellId', isEqualTo: cellId);
        if (serviceType != null && serviceType.trim().isNotEmpty) {
          query = query.where('profession', isEqualTo: serviceType);
        }
        if (onlineOnly) query = query.where('isOnline', isEqualTo: true);

        final snapshot = await query
            .limit(50)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);
        return snapshot.docs
            .map((doc) {
              try {
                return WorkerModel.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id);
              } catch (e) {
                logError('getWorkersInCell.parsing', e);
                return null;
              }
            })
            .whereType<WorkerModel>()
            .toList();
      } catch (e) {
        logError('getWorkersInCell', e);
        return [];
      }
    });
  }

  Future<List<WorkerModel>> getWorkersInWilaya({
    required int wilayaCode,
    String? serviceType,
    bool onlineOnly = false,
  }) async {
    ensureNotDisposed();

    return retryOperation(() async {
      try {
        Query query = firestore
            .collection(workersCollection)
            .where('wilayaCode', isEqualTo: wilayaCode);
        if (serviceType != null && serviceType.trim().isNotEmpty) {
          query = query.where('profession', isEqualTo: serviceType);
        }
        if (onlineOnly) query = query.where('isOnline', isEqualTo: true);

        final snapshot = await query
            .limit(50)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);
        return snapshot.docs
            .map((doc) {
              try {
                return WorkerModel.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id);
              } catch (e) {
                logError('getWorkersInWilaya.parsing', e);
                return null;
              }
            })
            .whereType<WorkerModel>()
            .toList();
      } catch (e) {
        logError('getWorkersInWilaya', e);
        return [];
      }
    });
  }

  // --------------------------------------------------------------------------
  // WRITE
  // --------------------------------------------------------------------------

  Future<void> setWorker(WorkerModel worker) async {
    ensureNotDisposed();
    validateWorkerId(worker.id);

    return retryOperation(() async {
      try {
        await firestore
            .collection(workersCollection)
            .doc(worker.id)
            .set(worker.toMap(), SetOptions(merge: true))
            .timeout(FirestoreRepositoryBase.operationTimeout);

        _cache.set(worker.id, worker);
        logInfo('Worker saved: ${worker.id}');
      } catch (e) {
        logError('setWorker', e);
        throw FirestoreServiceException(
          'Error saving worker',
          code: 'WORKER_SAVE_FAILED',
          originalError: e,
        );
      }
    });
  }

  Future<void> createOrUpdateWorker(WorkerModel worker) => setWorker(worker);

  Future<void> updateWorkerLocation(
    String workerId,
    double latitude,
    double longitude, {
    String? cellId,
    int? wilayaCode,
    String? geoHash,
  }) async {
    ensureNotDisposed();
    validateWorkerId(workerId);
    validateCoordinates(latitude, longitude);

    return retryOperation(() async {
      try {
        final updateData = <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'lastUpdated': Timestamp.now(),
          'lastLocationUpdate': Timestamp.now(),
        };
        if (cellId != null) updateData['cellId'] = cellId;
        if (wilayaCode != null) updateData['wilayaCode'] = wilayaCode;
        if (geoHash != null) updateData['geoHash'] = geoHash;

        await firestore
            .collection(workersCollection)
            .doc(workerId)
            .update(updateData)
            .timeout(FirestoreRepositoryBase.operationTimeout);

        _cache.update(
            workerId,
            (w) => w.copyWith(
                  latitude: latitude,
                  longitude: longitude,
                  cellId: cellId,
                  wilayaCode: wilayaCode,
                  geoHash: geoHash,
                  lastUpdated: DateTime.now(),
                  lastCellUpdate: DateTime.now(),
                ));
        logInfo('Worker location updated: $workerId');
      } catch (e) {
        logError('updateWorkerLocation', e);
        rethrow;
      }
    });
  }

  /// ALGO FIX (A9): write [lastActiveAt] when [isOnline] transitions to false.
  ///
  /// Previously this method never wrote lastActiveAt, so
  /// WorkerModel.daysSinceActive always fell back to 0 — making the recency
  /// component of RankingUtils.workerScore() a no-op (all workers scored
  /// equally on recency regardless of how long ago they went offline).
  ///
  /// Fix: when isOnline=false, include lastActiveAt: Timestamp.now() in the
  /// update payload. When isOnline=true we intentionally do NOT write
  /// lastActiveAt — coming back online should not reset "last seen offline".
  ///
  /// ⚠️  MANUAL: run a backfill Cloud Function to populate lastActiveAt on
  /// existing worker documents so the recency signal works for workers who
  /// went offline before this fix was deployed.
  Future<void> updateWorkerStatus(String workerId, bool isOnline) async {
    ensureNotDisposed();
    validateWorkerId(workerId);

    return retryOperation(() async {
      try {
        final updateData = <String, dynamic>{
          'isOnline': isOnline,
          'lastUpdated': Timestamp.now(),
        };

        // FIX (A9): stamp lastActiveAt when the worker goes offline so that
        // daysSinceActive can be computed accurately for ranking purposes.
        if (!isOnline) {
          updateData['lastActiveAt'] = Timestamp.now();
        }

        await firestore
            .collection(workersCollection)
            .doc(workerId)
            .update(updateData)
            .timeout(FirestoreRepositoryBase.operationTimeout);

        _cache.update(
            workerId,
            (w) => w.copyWith(
                  isOnline: isOnline,
                  lastUpdated: DateTime.now(),
                  daysSinceActive: isOnline ? w.daysSinceActive : 0,
                ));
        logInfo('Worker status updated: $workerId → $isOnline');
      } catch (e) {
        logError('updateWorkerStatus', e);
        rethrow;
      }
    });
  }

  Future<void> updateWorkerOnlineStatus(String workerId, bool isOnline) =>
      updateWorkerStatus(workerId, isOnline);

  Future<void> updateFcmToken(String workerId, String token) async {
    ensureNotDisposed();
    validateWorkerId(workerId);

    if (token.trim().isEmpty) {
      throw FirestoreServiceException(
        'FCM token cannot be empty',
        code: 'INVALID_FCM_TOKEN',
      );
    }

    return retryOperation(() async {
      try {
        await firestore
            .collection(workersCollection)
            .doc(workerId)
            .update({
          'fcmToken': token,
          'lastFcmTokenUpdate': Timestamp.now(),
        }).timeout(FirestoreRepositoryBase.operationTimeout);

        logInfo('FCM token updated for worker: $workerId');
      } catch (e) {
        logError('updateFcmToken', e);
        rethrow;
      }
    });
  }

  // --------------------------------------------------------------------------
  // CACHE MANAGEMENT
  // --------------------------------------------------------------------------

  void cacheWorker(String workerId, WorkerModel worker) =>
      _cache.set(workerId, worker);

  void cleanExpiredCache() => _cache.cleanExpired();

  void clearCache() => _cache.clear();

  // --------------------------------------------------------------------------
  // DISPOSE
  // --------------------------------------------------------------------------

  void dispose() {
    if (isDisposed) return;
    markDisposed();
    _cache.clear();
    logInfo('WorkerFirestoreRepository disposed');
  }
}
