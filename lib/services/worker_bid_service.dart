// lib/services/worker_bid_service.dart
//
// STEP 6 MIGRATION:
//   • Removed: import 'package:cloud_firestore/cloud_firestore.dart'
//   • Changed: FirestoreService → ApiService (field name kept: _api)
//   • submitBid():   Replaced Firestore runTransaction with _api.createBid().
//                   Atomicity + duplicate-check + own-request guard are now
//                   enforced server-side by NestJS BidsService.submit().
//   • withdrawBid(): Removed Firestore ownership read; server handles auth.
//                   Just calls _api.withdrawBid() — NestJS returns 403 if
//                   the caller is not the bid owner.
//   • Removed: _pendingBidMarkersCollection, _deleteMarker() — server-side concern.
//   • All stream methods, sortBids, acceptBid, startJob, completeJob,
//     submitClientRating: unchanged (already delegated via API / RealtimeService).
//   • firebase_auth kept: client-side pre-flight UID check in submitBid + withdrawBid.

import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/service_request_enhanced_model.dart';
import '../models/worker_bid_model.dart';
import '../models/worker_model.dart';
import '../models/message_enums.dart';
import '../utils/constants.dart';
import 'api_service.dart';

class WorkerBidService {
  final ApiService _api;
  bool _isDisposed = false;

  static const int _maxMessageLength = 500;

  // Composite sort weights for bid ranking.
  static const double _bidSortWeightPrice  = 0.40;
  static const double _bidSortWeightRating = 0.60;

  WorkerBidService(this._api);

  bool get isDisposed => _isDisposed;

  // =========================================================================
  // BROWSING — available requests for a worker
  // =========================================================================

  Stream<List<ServiceRequestEnhancedModel>> streamAvailableRequests({
    required int wilayaCode,
    required String serviceType,
  }) {
    _ensureNotDisposed();
    return _api.streamAvailableRequests(
      wilayaCode: wilayaCode,
      serviceType: serviceType,
    );
  }

  Stream<List<ServiceRequestEnhancedModel>> streamWorkerActiveJobs(
      String workerId) {
    _ensureNotDisposed();
    return _api.streamWorkerActiveJobs(workerId);
  }

  Stream<List<WorkerBidModel>> streamWorkerBids(String workerId) {
    _ensureNotDisposed();
    return _api.streamWorkerBids(workerId);
  }

  // =========================================================================
  // BID SUBMISSION
  // =========================================================================

  /// Submits a bid via REST POST /bids.
  ///
  /// STEP 6: The Firestore runTransaction (duplicate-bid marker, request status
  /// check, own-request guard) is removed from the Flutter client.  All of
  /// that logic lives in NestJS BidsService.submit(), which throws typed HTTP
  /// errors (409 duplicate, 403 own-request, 400 closed) that map to
  /// WorkerBidServiceException below.
  ///
  /// Client-side pre-flight checks retained:
  ///   • UID must match worker.id        (AUTH_MISMATCH)
  ///   • proposedPrice > 0               (INVALID_PRICE)
  ///   • estimatedMinutes > 0            (INVALID_DURATION)
  ///   • message length ≤ 500 chars      (sanitized silently)
  Future<WorkerBidModel> submitBid({
    required String requestId,
    required WorkerModel worker,
    required double proposedPrice,
    required int estimatedMinutes,
    required DateTime availableFrom,
    String? message,
  }) async {
    _ensureNotDisposed();

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != worker.id) {
      throw WorkerBidServiceException(
        'Cannot submit bid: authenticated user does not match worker identity',
        code: 'AUTH_MISMATCH',
      );
    }

    if (proposedPrice <= 0) {
      throw WorkerBidServiceException(
        'Proposed price must be greater than 0',
        code: 'INVALID_PRICE',
      );
    }
    if (estimatedMinutes <= 0) {
      throw WorkerBidServiceException(
        'Estimated duration must be greater than 0',
        code: 'INVALID_DURATION',
      );
    }

    String? sanitizedMessage;
    if (message != null && message.trim().isNotEmpty) {
      final trimmed = message.trim();
      sanitizedMessage = trimmed.substring(0, min(trimmed.length, _maxMessageLength));
    }

    final bidId = const Uuid().v4();
    final deadline = DateTime.now().add(
      const Duration(minutes: AppConstants.biddingDeadlineMinutes),
    );

    final bid = WorkerBidModel(
      id: bidId,
      serviceRequestId: requestId,
      workerId: worker.id,
      workerName: worker.name,
      workerAverageRating: worker.averageRating,
      workerJobsCompleted: worker.jobsCompleted,
      workerProfileImageUrl: worker.profileImageUrl,
      proposedPrice: proposedPrice,
      estimatedMinutes: estimatedMinutes,
      availableFrom: availableFrom,
      message: sanitizedMessage,
      status: BidStatus.pending,
      createdAt: DateTime.now(),
      expiresAt: deadline,
    );

    try {
      // STEP 6: POST /bids — server handles atomicity, duplicate check, own-request guard.
      final created = await _api.createBid(bid);
      _logInfo('Bid submitted: ${created.id} by ${worker.id} on $requestId');
      return created;
    } on ApiServiceException catch (e) {
      _logError('submitBid', e);
      // Map HTTP status codes to domain exception codes
      final code = _mapApiCode(e.code);
      throw WorkerBidServiceException(e.message, code: code, originalError: e);
    } catch (e) {
      _logError('submitBid', e);
      throw WorkerBidServiceException(
        'Failed to submit bid',
        code: 'SUBMIT_BID_FAILED',
        originalError: e,
      );
    }
  }

  // =========================================================================
  // BID ACCEPTANCE (client action)
  // =========================================================================

  Future<void> acceptBid({
    required String requestId,
    required WorkerBidModel bid,
  }) async {
    _ensureNotDisposed();

    try {
      await _api.acceptBidTransaction(
        requestId: requestId,
        bidId: bid.id,
        workerId: bid.workerId,
        workerName: bid.workerName,
        agreedPrice: bid.proposedPrice,
      );
      _logInfo('Bid accepted: ${bid.id} — worker ${bid.workerId} on $requestId');
    } on ApiServiceException catch (e) {
      _logError('acceptBid', e);
      throw WorkerBidServiceException(e.message,
          code: _mapApiCode(e.code), originalError: e);
    } catch (e) {
      _logError('acceptBid', e);
      throw WorkerBidServiceException(
        'Failed to accept bid',
        code: 'ACCEPT_BID_FAILED',
        originalError: e,
      );
    }
  }

  // =========================================================================
  // BID WITHDRAWAL (worker action)
  // =========================================================================

  /// Withdraws a bid via POST /bids/:id/withdraw.
  ///
  /// STEP 6: Removed the Firestore ownership read that fetched bid.workerId
  /// before withdrawing. Ownership is now enforced server-side: NestJS
  /// BidsService.withdraw() verifies the Firebase UID matches the bid owner
  /// and returns 403 (PERMISSION_DENIED) if not.
  ///
  /// Client-side pre-flight: currentUid must not be null (UNAUTHENTICATED).
  Future<void> withdrawBid({
    required String bidId,
    required String requestId,
  }) async {
    _ensureNotDisposed();

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      throw WorkerBidServiceException(
        'Not authenticated',
        code: 'UNAUTHENTICATED',
      );
    }

    try {
      await _api.withdrawBid(bidId: bidId, requestId: requestId);
      _logInfo('Bid withdrawn: $bidId by $currentUid');
    } on ApiServiceException catch (e) {
      _logError('withdrawBid', e);
      throw WorkerBidServiceException(e.message,
          code: _mapApiCode(e.code), originalError: e);
    } catch (e) {
      _logError('withdrawBid', e);
      throw WorkerBidServiceException(
        'Failed to withdraw bid',
        code: 'WITHDRAW_BID_FAILED',
        originalError: e,
      );
    }
  }

  // =========================================================================
  // JOB LIFECYCLE
  // =========================================================================

  Future<void> startJob(String requestId) async {
    _ensureNotDisposed();
    try {
      await _api.startJob(requestId);
      _logInfo('Job started: $requestId');
    } on ApiServiceException catch (e) {
      _logError('startJob', e);
      throw WorkerBidServiceException(e.message,
          code: _mapApiCode(e.code), originalError: e);
    } catch (e) {
      _logError('startJob', e);
      throw WorkerBidServiceException(
        'Failed to start job',
        code: 'START_JOB_FAILED',
        originalError: e,
      );
    }
  }

  Future<void> completeJob({
    required String requestId,
    String? workerNotes,
    double? finalPrice,
  }) async {
    _ensureNotDisposed();
    try {
      await _api.completeJob(
        requestId: requestId,
        workerNotes: workerNotes,
        finalPrice: finalPrice,
      );
      _logInfo('Job completed: $requestId');
    } on ApiServiceException catch (e) {
      _logError('completeJob', e);
      throw WorkerBidServiceException(e.message,
          code: _mapApiCode(e.code), originalError: e);
    } catch (e) {
      _logError('completeJob', e);
      throw WorkerBidServiceException(
        'Failed to complete job',
        code: 'COMPLETE_JOB_FAILED',
        originalError: e,
      );
    }
  }

  // =========================================================================
  // BIDS STREAM — client side (composite price+rating sort)
  // =========================================================================

  Stream<List<WorkerBidModel>> streamBidsForRequest(String requestId) {
    _ensureNotDisposed();
    return _api.streamBidsForRequest(requestId).map(
      (bids) {
        if (bids.isEmpty) return bids;

        final sorted = List<WorkerBidModel>.from(bids);
        final maxPrice = sorted.map((b) => b.proposedPrice).reduce(max);
        final minPrice = sorted.map((b) => b.proposedPrice).reduce(min);
        final priceRange = maxPrice - minPrice;

        sorted.sort((a, b) {
          final aPriceSaving = priceRange > 0
              ? (maxPrice - a.proposedPrice) / priceRange
              : 0.0;
          final bPriceSaving = priceRange > 0
              ? (maxPrice - b.proposedPrice) / priceRange
              : 0.0;

          final aRatingScore = (a.workerAverageRating / 5.0).clamp(0.0, 1.0);
          final bRatingScore = (b.workerAverageRating / 5.0).clamp(0.0, 1.0);

          final scoreA = _bidSortWeightPrice  * aPriceSaving
                       + _bidSortWeightRating * aRatingScore;
          final scoreB = _bidSortWeightPrice  * bPriceSaving
                       + _bidSortWeightRating * bRatingScore;

          return scoreB.compareTo(scoreA);
        });

        return sorted;
      },
    );
  }

  // =========================================================================
  // RATING
  // =========================================================================

  Future<void> submitClientRating({
    required String requestId,
    required int stars,
    String? comment,
  }) async {
    _ensureNotDisposed();
    try {
      await _api.submitClientRating(
        requestId: requestId,
        stars: stars,
        comment: comment,
      );
    } on ApiServiceException catch (e) {
      _logError('submitClientRating', e);
      throw WorkerBidServiceException(e.message,
          code: _mapApiCode(e.code), originalError: e);
    } catch (e) {
      _logError('submitClientRating', e);
      throw WorkerBidServiceException(
        'Failed to submit rating',
        code: 'SUBMIT_RATING_FAILED',
        originalError: e,
      );
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  /// Maps ApiServiceException HTTP error codes to WorkerBidService domain codes.
  String _mapApiCode(String? apiCode) {
    switch (apiCode) {
      case 'ALREADY_EXISTS':      return 'DUPLICATE_BID';
      case 'PERMISSION_DENIED':   return 'AUTH_MISMATCH';
      case 'UNAUTHENTICATED':     return 'UNAUTHENTICATED';
      case 'NOT_FOUND':           return 'REQUEST_NOT_FOUND';
      case 'RESOURCE_EXHAUSTED':  return 'RATE_LIMIT';
      default:                    return apiCode ?? 'UNKNOWN';
    }
  }

  void dispose() {
    _isDisposed = true;
    _logInfo('WorkerBidService disposed');
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw WorkerBidServiceException(
        'WorkerBidService has been disposed',
        code: 'SERVICE_DISPOSED',
      );
    }
  }

  void _logInfo(String message) {
    if (kDebugMode) debugPrint('[WorkerBidService] INFO: $message');
  }

  void _logError(String method, dynamic error) {
    if (kDebugMode) debugPrint('[WorkerBidService] ERROR in $method: $error');
  }
}

class WorkerBidServiceException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  WorkerBidServiceException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() =>
      'WorkerBidServiceException: $message${code != null ? ' (Code: $code)' : ''}';
}
