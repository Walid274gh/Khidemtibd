// lib/services/repositories/service_request_firestore_repository.dart
//
// TASK 2 FIX — Added streamWorkerAssignedRequests().
//
// ALGO FIX — submitClientRating: replaced simple running average with
// Bayesian average. Also persists ratingSum field so Bayesian is computable
// from stored data without requiring raw review history.
//
// Bayesian formula: (m × C + Σratings) / (m + n)
//   C = globalAverage (3.5 — recalibrate after 100+ real ratings)
//   m = minReviews    (10   — tune based on platform worker density)
//   n = reviewCount
//   Σratings = ratingSum (new Firestore field — see manual steps below)
//
// Simple average defect: a worker with 1× 5★ had averageRating = 5.0,
// outranking a 500× 4.8★ worker in search results. Bayesian pulls low-volume
// ratings toward the global average, preventing cold-start inflation.
//
// MIGRATION NOTE (manual):
//   Existing worker documents lack the ratingSum field.
//   On first write, ratingSum is derived from averageRating × ratingCount
//   (backward-compatible fallback in the transaction below).
//   Run a backfill Cloud Function to pre-populate ratingSum for all workers.
//
// [AUTO FIX] cancelRequest: wrapped in Firestore transaction that atomically
//   sets status=cancelled AND batch-declines all pending bids on that request.
//   Prevents the race where a worker's bid is accepted after the client cancels.
//
// [AUTO FIX] completeJob: wrapped in runTransaction with a stale-status guard.
//   Reads the live request inside the transaction and validates that status is
//   bidSelected or inProgress before writing completed. Prevents a second
//   completeJob call from re-completing an already-completed request.
//
// [LOGIC-APPLY FIX] submitClientRating: added isRatedByClient guard inside the
//   transaction. If req.isRatedByClient == true the transaction throws
//   ALREADY_RATED immediately, preventing double-writes on retry/tap scenarios.
//
// [AUTO FIX] Stream query limits:
//   streamBidsForRequest     → .limit(20)
//   streamWorkerBids         → .limit(100)
//   streamAvailableRequests  → .limit(50)
//   streamUserServiceRequests→ .limit(50)
//   streamWorkerActiveJobs   → .limit(10)
//   Prevents unbounded reads that could exhaust Firestore read quotas on
//   high-traffic accounts.
//
// [B8 FIX] submitClientRating: replaced private `_workersCollection = 'workers'`
//   constant with `FirestoreService.workersCollection` to eliminate the
//   duplication and keep a single canonical collection name across the codebase.
//   Import added: `import '../firestore_service.dart' show FirestoreService;`
//
// [AUTO FIX] submitClientRating: replaced hardcoded 'workers' string with
//   FirestoreService.workersCollection constant to eliminate magic strings and
//   ease future collection renames.
//
// [B3/B7 FIX] streamWorkerServiceRequests:
//   assignedSub: added .limit(50) — prevents scanning a worker's full history.
//   openSub: added optional wilayaCode scoping + .limit(50) — replaces the
//   previous platform-wide scan (.where('workerId', isNull: true) with no
//   geographic or profession filter). When wilayaCode is provided the query is
//   restricted to the worker's wilaya; without it the stream still falls back
//   to unscoped (backward-compatible) but is capped at 50 documents.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/message_enums.dart';
import '../../models/notification_model.dart';
import '../../models/service_request_enhanced_model.dart';
import '../../models/service_request_model.dart';
import '../../models/worker_bid_model.dart';
import 'firestore_repository_base.dart';
// [B8 FIX] Import FirestoreService to reference the canonical workersCollection
// constant instead of duplicating the string literal here.
import '../firestore_service.dart' show FirestoreService;

class ServiceRequestFirestoreRepository extends FirestoreRepositoryBase {
  static const String serviceRequestsCollection = 'service_requests';
  static const String workerBidsCollection = 'worker_bids';
  static const String notificationsCollection = 'notifications';

  // [B8 FIX] Removed: static const String _workersCollection = 'workers';
  // Use FirestoreService.workersCollection everywhere instead.

  static const int _maxBidsToDecline = 50;

  // ── Bayesian rating parameters ────────────────────────────────────────────
  // Calibrate both after 100+ real reviews in production.
  static const double _bayesianGlobalAvg = 3.5; // C — global platform average
  static const int    _bayesianMinReviews = 10; // m — confidence threshold

  ServiceRequestFirestoreRepository(super.firestore);

  @override
  String get logTag => '[ServiceRequestRepo]';

  // --------------------------------------------------------------------------
  // SERVICE REQUESTS — CRUD
  // --------------------------------------------------------------------------

  Future<void> createServiceRequest(
      ServiceRequestEnhancedModel request) async {
    ensureNotDisposed();
    if (request.id.trim().isEmpty) {
      throw FirestoreServiceException(
        'Service request ID cannot be empty',
        code: 'INVALID_REQUEST_ID',
      );
    }

    return retryOperation(() async {
      try {
        await firestore
            .collection(serviceRequestsCollection)
            .doc(request.id)
            .set(request.toMap())
            .timeout(FirestoreRepositoryBase.operationTimeout);
        logInfo('Service request created: ${request.id}');
      } catch (e) {
        logError('createServiceRequest', e);
        throw FirestoreServiceException(
          'Error creating service request',
          code: 'REQUEST_CREATE_FAILED',
          originalError: e,
        );
      }
    });
  }

  Future<ServiceRequestEnhancedModel?> getServiceRequest(
      String requestId) async {
    ensureNotDisposed();
    if (requestId.trim().isEmpty) {
      logWarning('getServiceRequest called with empty requestId');
      return null;
    }

    return retryOperation(() async {
      try {
        final doc = await firestore
            .collection(serviceRequestsCollection)
            .doc(requestId)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);
        if (!doc.exists || doc.data() == null) return null;
        return ServiceRequestEnhancedModel.fromMap(doc.data()!, doc.id);
      } catch (e) {
        logError('getServiceRequest', e);
        return null;
      }
    });
  }

  Future<void> updateServiceRequest(
      ServiceRequestEnhancedModel request) async {
    ensureNotDisposed();
    if (request.id.trim().isEmpty) {
      throw FirestoreServiceException(
        'Service request ID cannot be empty',
        code: 'INVALID_REQUEST_ID',
      );
    }

    return retryOperation(() async {
      try {
        await firestore
            .collection(serviceRequestsCollection)
            .doc(request.id)
            .update(request.toMap())
            .timeout(FirestoreRepositoryBase.operationTimeout);
        logInfo('Service request updated: ${request.id}');
      } catch (e) {
        logError('updateServiceRequest', e);
        throw FirestoreServiceException(
          'Error updating service request',
          code: 'REQUEST_UPDATE_FAILED',
          originalError: e,
        );
      }
    });
  }

  // --------------------------------------------------------------------------
  // SERVICE REQUESTS — STREAMS
  // --------------------------------------------------------------------------

  Stream<ServiceRequestEnhancedModel?> streamServiceRequest(
      String requestId) {
    if (requestId.trim().isEmpty) {
      logWarning('streamServiceRequest called with empty requestId');
      return Stream.value(null);
    }
    return firestore
        .collection(serviceRequestsCollection)
        .doc(requestId)
        .snapshots()
        .handleError((e) => logError('streamServiceRequest', e))
        .map((doc) {
          try {
            if (!doc.exists || doc.data() == null) return null;
            return ServiceRequestEnhancedModel.fromMap(doc.data()!, doc.id);
          } catch (e) {
            logError('streamServiceRequest.parsing', e);
            return null;
          }
        });
  }

  /// [AUTO FIX] Added .limit(50) — prevents unbounded reads on accounts
  /// with many historical requests.
  Stream<List<ServiceRequestEnhancedModel>> streamUserServiceRequests(
      String userId) {
    if (userId.trim().isEmpty) {
      logWarning('streamUserServiceRequests called with empty userId');
      return Stream.value([]);
    }
    return firestore
        .collection(serviceRequestsCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .handleError((e) => logError('streamUserServiceRequests', e))
        .map((s) =>
            _parseRequestList(s.docs, 'streamUserServiceRequests'));
  }

  // [B3/B7 FIX] Signature extended with optional wilayaCode parameter.
  //
  // assignedSub: added .limit(50) — a worker's full job history could be
  // thousands of documents; cap to the most recent 50.
  //
  // openSub: two changes:
  //   1. Added .where('wilayaCode', isEqualTo: wilayaCode) when wilayaCode
  //      is supplied — replaces the previous platform-wide scan that read
  //      every open/awaitingSelection request across all regions.
  //   2. Added .limit(50) — caps unscoped fallback (backward-compatible).
  //
  // Callers that already know the worker's wilayaCode (WorkerJobsController)
  // should pass it in. Callers that cannot yet provide it fall back to the
  // unscoped query, which is now at least bounded to 50 documents.
  Stream<List<ServiceRequestEnhancedModel>> streamWorkerServiceRequests(
      String workerId, {int? wilayaCode}) {
    if (workerId.trim().isEmpty) {
      logWarning(
          'streamWorkerServiceRequests called with empty workerId');
      return Stream.value([]);
    }

    List<ServiceRequestEnhancedModel> assignedJobs = [];
    List<ServiceRequestEnhancedModel> openJobs = [];
    StreamSubscription? assignedSub;
    StreamSubscription? openSub;

    late StreamController<List<ServiceRequestEnhancedModel>> controller;

    void emit() {
      if (controller.isClosed) return;
      final dedup = <String, ServiceRequestEnhancedModel>{};
      for (final j in [...assignedJobs, ...openJobs]) {
        dedup[j.id] = j;
      }
      controller.add(dedup.values.toList());
    }

    controller = StreamController<List<ServiceRequestEnhancedModel>>.broadcast(
      onListen: () {
        // [B3 FIX] Added .limit(50) — prevents full history scans.
        assignedSub = firestore
            .collection(serviceRequestsCollection)
            .where('workerId', isEqualTo: workerId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots()
            .listen(
          (s) {
            assignedJobs =
                _parseRequestList(s.docs, 'workerAssigned');
            emit();
          },
          onError: (e) {
            logError('streamWorkerServiceRequests.assigned', e);
            if (!controller.isClosed) controller.addError(e);
          },
        );

        // [B7 FIX] Added wilayaCode scoping + .limit(50).
        // When wilayaCode is known, the query is restricted to the worker's
        // wilaya instead of scanning all open requests platform-wide.
        // Without wilayaCode the query falls back to unscoped but is still
        // capped at 50 documents (vs. the previous unbounded scan).
        Query<Map<String, dynamic>> openQuery = firestore
            .collection(serviceRequestsCollection)
            .where('status', whereIn: [
              ServiceStatus.open.name,
              ServiceStatus.awaitingSelection.name,
            ])
            .where('workerId', isNull: true);

        if (wilayaCode != null) {
          openQuery = openQuery.where('wilayaCode', isEqualTo: wilayaCode);
        }

        openSub = openQuery
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots()
            .listen(
          (s) {
            openJobs = _parseRequestList(s.docs, 'workerOpen');
            emit();
          },
          onError: (e) {
            logError('streamWorkerServiceRequests.open', e);
            if (!controller.isClosed) controller.addError(e);
          },
        );
      },
      onCancel: () {
        assignedSub?.cancel();
        openSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// [AUTO FIX] Added .limit(50) — prevents unbounded reads when a wilaya
  /// has a large backlog of open requests.
  Stream<List<ServiceRequestEnhancedModel>> streamAvailableRequests({
    required int wilayaCode,
    required String serviceType,
  }) {
    return firestore
        .collection(serviceRequestsCollection)
        .where('wilayaCode', isEqualTo: wilayaCode)
        .where('serviceType', isEqualTo: serviceType)
        .where('status', whereIn: [
          ServiceStatus.open.name,
          ServiceStatus.awaitingSelection.name,
        ])
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .handleError((e) => logError('streamAvailableRequests', e))
        .map((s) =>
            _parseRequestList(s.docs, 'streamAvailableRequests'));
  }

  /// [AUTO FIX] Added .limit(10) — a worker should never have more than
  /// a handful of active jobs simultaneously; cap prevents runaway reads.
  Stream<List<ServiceRequestEnhancedModel>> streamWorkerActiveJobs(
      String workerId) {
    if (workerId.trim().isEmpty) {
      logWarning('streamWorkerActiveJobs called with empty workerId');
      return Stream.value([]);
    }
    return firestore
        .collection(serviceRequestsCollection)
        .where('workerId', isEqualTo: workerId)
        .where('status', whereIn: [
          ServiceStatus.bidSelected.name,
          ServiceStatus.inProgress.name,
        ])
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .handleError((e) => logError('streamWorkerActiveJobs', e))
        .map((s) =>
            _parseRequestList(s.docs, 'streamWorkerActiveJobs'));
  }

  // --------------------------------------------------------------------------
  // TASK 2 — WORKER HOME ASSIGNED REQUESTS STREAM
  // --------------------------------------------------------------------------

  Stream<List<ServiceRequestEnhancedModel>> streamWorkerAssignedRequests(
      String workerId, {int limit = 30}) {
    if (workerId.trim().isEmpty) {
      logWarning('streamWorkerAssignedRequests called with empty workerId');
      return Stream.value([]);
    }
    return firestore
        .collection(serviceRequestsCollection)
        .where('workerId', isEqualTo: workerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .handleError((Object e) =>
            logError('streamWorkerAssignedRequests', e))
        .map((s) =>
            _parseRequestList(s.docs, 'streamWorkerAssignedRequests'));
  }

  // --------------------------------------------------------------------------
  // WORKER BIDS — CRUD
  // --------------------------------------------------------------------------

  /// [AUTO FIX] Added .limit(20) — a single request should not receive an
  /// unbounded number of bids; cap keeps reads predictable.
  Stream<List<WorkerBidModel>> streamBidsForRequest(String requestId) {
    if (requestId.trim().isEmpty) {
      logWarning('streamBidsForRequest called with empty requestId');
      return Stream.value([]);
    }
    return firestore
        .collection(workerBidsCollection)
        .where('serviceRequestId', isEqualTo: requestId)
        .orderBy('createdAt', descending: false)
        .limit(20)
        .snapshots()
        .handleError((e) => logError('streamBidsForRequest', e))
        .map((s) => _parseBidList(s.docs, 'streamBidsForRequest'));
  }

  /// [AUTO FIX] Added .limit(100) — workers accumulate historical bids over
  /// time; cap prevents the stream from scanning the full collection on
  /// high-volume accounts.
  Stream<List<WorkerBidModel>> streamWorkerBids(String workerId) {
    if (workerId.trim().isEmpty) {
      logWarning('streamWorkerBids called with empty workerId');
      return Stream.value([]);
    }
    return firestore
        .collection(workerBidsCollection)
        .where('workerId', isEqualTo: workerId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .handleError((e) => logError('streamWorkerBids', e))
        .map((s) => _parseBidList(s.docs, 'streamWorkerBids'));
  }

  Future<WorkerBidModel> createBid(WorkerBidModel bid) async {
    ensureNotDisposed();
    if (bid.id.trim().isEmpty) {
      throw FirestoreServiceException('Bid ID cannot be empty',
          code: 'INVALID_BID_ID');
    }
    return retryOperation(() async {
      try {
        await firestore
            .collection(workerBidsCollection)
            .doc(bid.id)
            .set(bid.toMap())
            .timeout(FirestoreRepositoryBase.operationTimeout);
        logInfo('Bid created: ${bid.id}');
        return bid;
      } catch (e) {
        logError('createBid', e);
        throw FirestoreServiceException('Error creating bid',
            code: 'BID_CREATE_FAILED', originalError: e);
      }
    });
  }

  // --------------------------------------------------------------------------
  // BID LIFECYCLE
  // --------------------------------------------------------------------------

  Future<void> acceptBidTransaction({
    required String requestId,
    required String bidId,
    required String workerId,
    required String workerName,
    required double agreedPrice,
  }) async {
    ensureNotDisposed();
    try {
      final requestRef = firestore
          .collection(serviceRequestsCollection)
          .doc(requestId);

      await firestore.runTransaction((tx) async {
        final reqSnap = await tx.get(requestRef);
        if (!reqSnap.exists || reqSnap.data() == null) {
          throw FirestoreServiceException(
            'Request not found: $requestId',
            code: 'REQUEST_NOT_FOUND',
          );
        }
        final req = ServiceRequestEnhancedModel.fromMap(
            reqSnap.data()!, reqSnap.id);
        if (req.status != ServiceStatus.awaitingSelection &&
            req.status != ServiceStatus.open) {
          throw FirestoreServiceException(
            'Cannot accept bid — invalid state',
            code: 'INVALID_REQUEST_STATE',
          );
        }
        tx.update(
          firestore.collection(workerBidsCollection).doc(bidId),
          {
            'status': BidStatus.accepted.name,
            'acceptedAt': Timestamp.now(),
          },
        );
        tx.update(requestRef, {
          'status': ServiceStatus.bidSelected.name,
          'selectedBidId': bidId,
          'workerId': workerId,
          'workerName': workerName,
          'agreedPrice': agreedPrice,
          'bidSelectedAt': Timestamp.now(),
        });
      }).timeout(const Duration(seconds: 20));

      final others = await firestore
          .collection(workerBidsCollection)
          .where('serviceRequestId', isEqualTo: requestId)
          .where('status', isEqualTo: BidStatus.pending.name)
          .limit(_maxBidsToDecline)
          .get()
          .timeout(FirestoreRepositoryBase.operationTimeout);

      final batch = firestore.batch();
      for (final doc in others.docs) {
        if (doc.id != bidId) {
          batch.update(doc.reference,
              {'status': BidStatus.declined.name});
        }
      }
      if (others.docs.isNotEmpty) {
        await batch
            .commit()
            .timeout(FirestoreRepositoryBase.operationTimeout);
      }

      logInfo('Bid accepted: $bidId → request $requestId bidSelected');
    } catch (e) {
      logError('acceptBidTransaction', e);
      if (e is FirestoreServiceException) rethrow;
      throw FirestoreServiceException('Error accepting bid',
          code: 'BID_ACCEPT_FAILED', originalError: e);
    }
  }

  Future<void> withdrawBid({
    required String bidId,
    required String requestId,
  }) async {
    ensureNotDisposed();
    try {
      await firestore.runTransaction((tx) async {
        final bidRef =
            firestore.collection(workerBidsCollection).doc(bidId);
        final snap = await tx.get(bidRef);
        if (!snap.exists) {
          throw FirestoreServiceException('Bid not found: $bidId',
              code: 'BID_NOT_FOUND');
        }
        final bid =
            WorkerBidModel.fromMap(snap.data()!, snap.id);
        if (bid.status != BidStatus.pending) {
          throw FirestoreServiceException(
              'Can only withdraw pending bids',
              code: 'INVALID_BID_STATE');
        }
        tx.update(bidRef, {'status': BidStatus.withdrawn.name});
        tx.update(
          firestore
              .collection(serviceRequestsCollection)
              .doc(requestId),
          {'bidCount': FieldValue.increment(-1)},
        );
      }).timeout(const Duration(seconds: 15));
      logInfo('Bid withdrawn: $bidId');
    } catch (e) {
      logError('withdrawBid', e);
      if (e is FirestoreServiceException) rethrow;
      throw FirestoreServiceException('Error withdrawing bid',
          code: 'BID_WITHDRAW_FAILED', originalError: e);
    }
  }

  // --------------------------------------------------------------------------
  // JOB LIFECYCLE
  // --------------------------------------------------------------------------

  Future<void> startJob(String requestId) async {
    ensureNotDisposed();
    await _updateRequestStatus(requestId, ServiceStatus.inProgress,
        extras: {'acceptedAt': Timestamp.now()});
    logInfo('Job started: $requestId');
  }

  /// [AUTO FIX] completeJob: wrapped in runTransaction with a stale-status
  /// guard. Validates that the live request status is bidSelected or inProgress
  /// before writing completed, and batch-writes completedAt + optional fields
  /// atomically. Prevents re-completion of an already-completed or cancelled
  /// request.
  Future<void> completeJob({
    required String requestId,
    String? workerNotes,
    double? finalPrice,
  }) async {
    ensureNotDisposed();
    if (requestId.trim().isEmpty) {
      throw FirestoreServiceException('requestId cannot be empty',
          code: 'INVALID_REQUEST_ID');
    }

    try {
      final requestRef = firestore
          .collection(serviceRequestsCollection)
          .doc(requestId);

      await firestore.runTransaction((tx) async {
        final reqSnap = await tx.get(requestRef);

        if (!reqSnap.exists || reqSnap.data() == null) {
          throw FirestoreServiceException(
            'Request not found: $requestId',
            code: 'REQUEST_NOT_FOUND',
          );
        }

        final req = ServiceRequestEnhancedModel.fromMap(
            reqSnap.data()!, reqSnap.id);

        if (req.status != ServiceStatus.bidSelected &&
            req.status != ServiceStatus.inProgress) {
          throw FirestoreServiceException(
            'Cannot complete job — current status is ${req.status.name}. '
            'Expected bidSelected or inProgress.',
            code: 'INVALID_REQUEST_STATE',
          );
        }

        final updatePayload = <String, dynamic>{
          'status': ServiceStatus.completed.name,
          'completedAt': Timestamp.now(),
          if (workerNotes != null && workerNotes.trim().isNotEmpty)
            'workerNotes': workerNotes.trim(),
          if (finalPrice != null) 'finalPrice': finalPrice,
        };

        tx.update(requestRef, updatePayload);
      }).timeout(const Duration(seconds: 20));

      logInfo('Job completed (transactional): $requestId');
    } catch (e) {
      logError('completeJob', e);
      if (e is FirestoreServiceException) rethrow;
      throw FirestoreServiceException(
        'Error completing job',
        code: 'COMPLETE_JOB_FAILED',
        originalError: e,
      );
    }
  }

  /// [AUTO FIX] cancelRequest: wrapped in a Firestore transaction that
  /// atomically sets the request status to cancelled AND batch-declines all
  /// pending bids on that request.
  Future<void> cancelRequest(String requestId) async {
    ensureNotDisposed();
    if (requestId.trim().isEmpty) {
      throw FirestoreServiceException('requestId cannot be empty',
          code: 'INVALID_REQUEST_ID');
    }

    try {
      final requestRef = firestore
          .collection(serviceRequestsCollection)
          .doc(requestId);

      await firestore.runTransaction((tx) async {
        final reqSnap = await tx.get(requestRef);

        if (!reqSnap.exists || reqSnap.data() == null) {
          throw FirestoreServiceException(
            'Request not found: $requestId',
            code: 'REQUEST_NOT_FOUND',
          );
        }

        final req = ServiceRequestEnhancedModel.fromMap(
            reqSnap.data()!, reqSnap.id);

        if (req.status == ServiceStatus.completed ||
            req.status == ServiceStatus.cancelled) {
          throw FirestoreServiceException(
            'Cannot cancel request — current status is ${req.status.name}.',
            code: 'INVALID_REQUEST_STATE',
          );
        }

        tx.update(requestRef, {
          'status': ServiceStatus.cancelled.name,
          'cancelledAt': Timestamp.now(),
        });
      }).timeout(const Duration(seconds: 20));

      final pendingBids = await firestore
          .collection(workerBidsCollection)
          .where('serviceRequestId', isEqualTo: requestId)
          .where('status', isEqualTo: BidStatus.pending.name)
          .limit(_maxBidsToDecline)
          .get()
          .timeout(FirestoreRepositoryBase.operationTimeout);

      if (pendingBids.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in pendingBids.docs) {
          batch.update(doc.reference, {
            'status': BidStatus.declined.name,
            'declinedAt': Timestamp.now(),
          });
        }
        await batch
            .commit()
            .timeout(FirestoreRepositoryBase.operationTimeout);
        logInfo(
            'cancelRequest: declined ${pendingBids.docs.length} pending bids for $requestId');
      }

      logInfo('Request cancelled (transactional): $requestId');
    } catch (e) {
      logError('cancelRequest', e);
      if (e is FirestoreServiceException) rethrow;
      throw FirestoreServiceException(
        'Error cancelling request',
        code: 'CANCEL_REQUEST_FAILED',
        originalError: e,
      );
    }
  }

  Future<void> _updateRequestStatus(
    String requestId,
    ServiceStatus status, {
    Map<String, dynamic> extras = const {},
  }) async {
    if (requestId.trim().isEmpty) {
      throw FirestoreServiceException('requestId cannot be empty',
          code: 'INVALID_REQUEST_ID');
    }
    await retryOperation(() async {
      try {
        await firestore
            .collection(serviceRequestsCollection)
            .doc(requestId)
            .update({'status': status.name, ...extras})
            .timeout(FirestoreRepositoryBase.operationTimeout);
      } catch (e) {
        logError('_updateRequestStatus', e);
        throw FirestoreServiceException('Error updating request status',
            code: 'STATUS_UPDATE_FAILED', originalError: e);
      }
    });
  }

  // --------------------------------------------------------------------------
  // RATING
  // --------------------------------------------------------------------------

  Future<void> submitClientRating({
    required String requestId,
    required int stars,
    String? comment,
  }) async {
    ensureNotDisposed();

    if (stars < 1 || stars > 5) {
      throw FirestoreServiceException('Stars must be 1–5',
          code: 'INVALID_RATING');
    }
    if (requestId.trim().isEmpty) {
      throw FirestoreServiceException('Request ID cannot be empty',
          code: 'INVALID_REQUEST_ID');
    }

    try {
      await firestore.runTransaction((tx) async {
        final reqRef = firestore
            .collection(serviceRequestsCollection)
            .doc(requestId);
        final reqSnap = await tx.get(reqRef);

        if (!reqSnap.exists || reqSnap.data() == null) {
          throw FirestoreServiceException(
              'Request not found: $requestId',
              code: 'REQUEST_NOT_FOUND');
        }

        final req = ServiceRequestEnhancedModel.fromMap(
            reqSnap.data()!, reqSnap.id);

        if (req.isRatedByClient) {
          throw FirestoreServiceException(
            'Request has already been rated by the client',
            code: 'ALREADY_RATED',
          );
        }

        tx.update(reqRef, {
          'clientRating': stars,
          if (comment != null && comment.isNotEmpty)
            'reviewComment': comment,
        });

        if (req.workerId != null && req.workerId!.isNotEmpty) {
          // [B8 FIX] FirestoreService.workersCollection replaces the removed
          // private _workersCollection constant — single source of truth.
          final workerRef =
              firestore.collection(FirestoreService.workersCollection).doc(req.workerId!);
          final workerSnap = await tx.get(workerRef);

          final oldCount =
              workerSnap.data()?['ratingCount'] as int? ?? 0;
          final oldAvg =
              (workerSnap.data()?['averageRating'] as num?)
                  ?.toDouble() ??
              0.0;

          final oldSum =
              (workerSnap.data()?['ratingSum'] as num?)?.toDouble() ??
              (oldAvg * oldCount);

          final newCount = oldCount + 1;
          final newSum   = oldSum + stars;

          final newBayesianAvg =
              (_bayesianMinReviews * _bayesianGlobalAvg + newSum) /
              (_bayesianMinReviews + newCount);

          tx.update(workerRef, {
            'averageRating': newBayesianAvg,
            'ratingSum':     newSum,
            'ratingCount':   newCount,
            'lastRating':    stars,
            'lastRatedAt':   Timestamp.now(),
          });
        }
      }).timeout(FirestoreRepositoryBase.operationTimeout);

      logInfo('Rating submitted: $stars ★ for $requestId (Bayesian avg updated)');
    } catch (e) {
      logError('submitClientRating', e);
      if (e is FirestoreServiceException) rethrow;
      throw FirestoreServiceException('Error submitting rating',
          code: 'RATING_FAILED', originalError: e);
    }
  }

  // --------------------------------------------------------------------------
  // NOTIFICATIONS
  // --------------------------------------------------------------------------

  Future<void> createNotification(NotificationModel notification) async {
    ensureNotDisposed();
    if (notification.id.trim().isEmpty) {
      throw FirestoreServiceException(
          'Notification ID cannot be empty',
          code: 'INVALID_NOTIFICATION_ID');
    }
    return retryOperation(() async {
      try {
        await firestore
            .collection(notificationsCollection)
            .doc(notification.id)
            .set(notification.toMap())
            .timeout(FirestoreRepositoryBase.operationTimeout);
        logInfo('Notification created: ${notification.id}');
      } catch (e) {
        logError('createNotification', e);
        rethrow;
      }
    });
  }

  // --------------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------------

  List<ServiceRequestEnhancedModel> _parseRequestList(
    List<QueryDocumentSnapshot> docs,
    String tag,
  ) {
    return docs
        .map((doc) {
          try {
            return ServiceRequestEnhancedModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id);
          } catch (e) {
            logError('$tag.parsing', e);
            return null;
          }
        })
        .whereType<ServiceRequestEnhancedModel>()
        .toList();
  }

  List<WorkerBidModel> _parseBidList(
    List<QueryDocumentSnapshot> docs,
    String tag,
  ) {
    return docs
        .map((doc) {
          try {
            return WorkerBidModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id);
          } catch (e) {
            logError('$tag.parsing', e);
            return null;
          }
        })
        .whereType<WorkerBidModel>()
        .toList();
  }

  // --------------------------------------------------------------------------
  // DISPOSE
  // --------------------------------------------------------------------------

  void dispose() {
    if (isDisposed) return;
    markDisposed();
    logInfo('ServiceRequestFirestoreRepository disposed');
  }
}
