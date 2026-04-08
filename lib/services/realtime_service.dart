// lib/services/realtime_service.dart
//
// STEP 5 MIGRATION: WebSocket client replacing all Firestore real-time streams.
//
// Uses package:socket_io_client to connect to the NestJS gateways from Step 4.
//
// Authentication:
//   auth: { 'token': <Firebase ID token> }   — sent on connection
//   Token is refreshed on every reconnect attempt.
//
// Room subscription pattern (mirrors Step 4 gateway room names):
//   worker:{workerId}
//   wilaya:{wilayaCode}
//   wilaya:{wilayaCode}:service:{serviceType}
//   user:{userId}
//   request:{requestId}
//   request:{requestId}:bids
//   worker:{workerId}:bids
//
// Streams use StreamController.broadcast() so multiple listeners are safe.
// dispose() closes the socket and all StreamControllers.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/service_request_enhanced_model.dart';
import '../models/worker_bid_model.dart';
import '../models/worker_model.dart';
import '../models/message_enums.dart';

class RealtimeService {
  final String _baseUrl;

  // Three namespace sockets (Step 4 gateways)
  io.Socket? _workersSocket;
  io.Socket? _requestsSocket;
  io.Socket? _bidsSocket;

  bool _isDisposed = false;

  // ── Stream controllers ─────────────────────────────────────────────────────

  // Workers namespace
  final Map<String, StreamController<WorkerModel?>>         _workerControllers    = {};
  final Map<String, StreamController<List<WorkerModel>>>    _wilayaControllers    = {};
  final StreamController<List<WorkerModel>>                 _allOnlineController  =
      StreamController<List<WorkerModel>>.broadcast();
  final Map<String, List<WorkerModel>> _wilayaWorkerCache = {};

  // Requests namespace
  final Map<String, StreamController<ServiceRequestEnhancedModel?>>    _requestControllers = {};
  final Map<String, StreamController<List<ServiceRequestEnhancedModel>>> _userReqControllers  = {};
  final Map<String, StreamController<List<ServiceRequestEnhancedModel>>> _workerReqControllers= {};
  final Map<String, StreamController<List<ServiceRequestEnhancedModel>>> _availableReqCtrl    = {};
  final Map<String, StreamController<List<ServiceRequestEnhancedModel>>> _activeJobsCtrl      = {};
  final Map<String, StreamController<List<ServiceRequestEnhancedModel>>> _assignedJobsCtrl    = {};
  // In-memory last-known lists for each stream key
  final Map<String, List<ServiceRequestEnhancedModel>> _reqCache = {};

  // Bids namespace
  final Map<String, StreamController<List<WorkerBidModel>>> _bidsControllers      = {};
  final Map<String, StreamController<List<WorkerBidModel>>> _workerBidsControllers = {};
  final Map<String, List<WorkerBidModel>> _bidsCache = {};

  RealtimeService({required String baseUrl})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl {
    _connect();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Connection management
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _connect() async {
    if (_isDisposed) return;
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final opts = io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token ?? ''})
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionDelay(2000)
        .setReconnectionDelayMax(10000)
        .build();

    _workersSocket  = io.io('$_baseUrl/workers',  opts)..connect();
    _requestsSocket = io.io('$_baseUrl/requests', opts)..connect();
    _bidsSocket     = io.io('$_baseUrl/bids',     opts)..connect();

    _attachWorkerListeners();
    _attachRequestListeners();
    _attachBidListeners();
  }

  void _attachWorkerListeners() {
    _workersSocket
      ?..on('worker:location', (data) {
        if (data is! Map) return;
        final workerId = data['workerId'] as String?;
        if (workerId == null) return;
        final ctrl = _workerControllers[workerId];
        if (ctrl != null && !ctrl.isClosed) {
          // Emit null so HomeController re-fetches or we emit a delta
          ctrl.add(null);
        }
        // Update wilaya caches
        _wilayaControllers.forEach((key, ctrl) {
          if (!ctrl.isClosed) ctrl.add(_wilayaWorkerCache[key] ?? []);
        });
      })
      ..on('worker:status', (data) {
        if (data is! Map) return;
        final workerId = data['workerId'] as String?;
        if (workerId == null) return;
        final ctrl = _workerControllers[workerId];
        if (ctrl != null && !ctrl.isClosed) ctrl.add(null);
      })
      ..on('reconnect', (_) async {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
        _workersSocket?.auth = {'token': token ?? ''};
      });
  }

  void _attachRequestListeners() {
    _requestsSocket
      ?..on('request:updated', (data) {
        if (data is! Map) return;
        final requestId = data['requestId'] as String?;
        if (requestId == null) return;
        final ctrl = _requestControllers[requestId];
        if (ctrl != null && !ctrl.isClosed) ctrl.add(null); // trigger re-fetch
      })
      ..on('request:bid_received', (data) {
        if (data is! Map) return;
        final requestId = data['requestId'] as String?;
        if (requestId == null) return;
        final ctrl = _requestControllers[requestId];
        if (ctrl != null && !ctrl.isClosed) ctrl.add(null);
      })
      ..on('request:created', (data) {
        if (data is! Map) return;
        try {
          final req = ServiceRequestEnhancedModel.fromJson(
              (data['request'] as Map).cast<String, dynamic>());
          _availableReqCtrl.forEach((key, ctrl) {
            final existing = List<ServiceRequestEnhancedModel>.from(_reqCache[key] ?? []);
            if (!existing.any((r) => r.id == req.id)) existing.insert(0, req);
            _reqCache[key] = existing;
            if (!ctrl.isClosed) ctrl.add(existing);
          });
        } catch (_) {}
      })
      ..on('request:completed', (data) => _handleRequestStatusChange(data))
      ..on('request:cancelled',  (data) => _handleRequestStatusChange(data))
      ..on('request:started',    (data) => _handleRequestStatusChange(data))
      ..on('reconnect', (_) async {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
        _requestsSocket?.auth = {'token': token ?? ''};
        // Re-subscribe to all active rooms
        _requestControllers.keys.forEach((id) {
          _requestsSocket?.emit('subscribe:request', {'requestId': id});
        });
      });
  }

  void _handleRequestStatusChange(dynamic data) {
    if (data is! Map) return;
    final requestId = data['requestId'] as String?;
    if (requestId == null) return;
    final ctrl = _requestControllers[requestId];
    if (ctrl != null && !ctrl.isClosed) ctrl.add(null);
    // Invalidate list caches that may contain this request
    _workerReqControllers.forEach((_, c) { if (!c.isClosed) c.add([]); });
    _userReqControllers.forEach((_,  c) { if (!c.isClosed) c.add([]); });
  }

  void _attachBidListeners() {
    _bidsSocket
      ?..on('bid:submitted', (data) {
        if (data is! Map) return;
        final requestId = data['requestId'] as String?;
        if (requestId == null) return;
        final ctrl = _bidsControllers[requestId];
        if (ctrl != null && !ctrl.isClosed) {
          // Emit current cache (ApiService will re-fetch the full list)
          ctrl.add(_bidsCache[requestId] ?? []);
        }
      })
      ..on('bid:accepted', (data) {
        if (data is! Map) return;
        _bidsControllers.forEach((_, c) { if (!c.isClosed) c.add([]); });
        _workerBidsControllers.forEach((_, c) { if (!c.isClosed) c.add([]); });
      })
      ..on('bid:withdrawn', (data) {
        if (data is! Map) return;
        _bidsControllers.forEach((_, c) { if (!c.isClosed) c.add([]); });
        _workerBidsControllers.forEach((_, c) { if (!c.isClosed) c.add([]); });
      })
      ..on('bid:declined', (data) {
        if (data is! Map) return;
        final workerId = (data['workerId'] as String?) ?? '';
        final ctrl = _workerBidsControllers[workerId];
        if (ctrl != null && !ctrl.isClosed) ctrl.add([]);
      })
      ..on('reconnect', (_) async {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
        _bidsSocket?.auth = {'token': token ?? ''};
      });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Worker streams
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<WorkerModel?> streamWorker(String workerId) {
    if (!_workerControllers.containsKey(workerId)) {
      _workerControllers[workerId] =
          StreamController<WorkerModel?>.broadcast();
      _workersSocket?.emit('subscribe:worker', {'workerId': workerId});
    }
    return _workerControllers[workerId]!.stream;
  }

  Stream<List<WorkerModel>> streamOnlineWorkersByWilayas(List<int> wilayaCodes) {
    final key = wilayaCodes.join(',');
    if (!_wilayaControllers.containsKey(key)) {
      _wilayaControllers[key] =
          StreamController<List<WorkerModel>>.broadcast();
      for (final code in wilayaCodes) {
        _workersSocket?.emit('subscribe:wilaya', {'wilayaCode': code});
      }
    }
    return _wilayaControllers[key]!.stream;
  }

  Stream<List<WorkerModel>> streamOnlineWorkersUnscoped({int limit = 100}) =>
      _allOnlineController.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // Request streams
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<ServiceRequestEnhancedModel?> streamServiceRequest(String requestId) {
    if (!_requestControllers.containsKey(requestId)) {
      _requestControllers[requestId] =
          StreamController<ServiceRequestEnhancedModel?>.broadcast();
      _requestsSocket?.emit('subscribe:request', {'requestId': requestId});
    }
    return _requestControllers[requestId]!.stream;
  }

  Stream<List<ServiceRequestEnhancedModel>> streamUserServiceRequests(String userId) {
    if (!_userReqControllers.containsKey(userId)) {
      _userReqControllers[userId] =
          StreamController<List<ServiceRequestEnhancedModel>>.broadcast();
    }
    return _userReqControllers[userId]!.stream;
  }

  Stream<List<ServiceRequestEnhancedModel>> streamWorkerServiceRequests(
      String workerId, {int? wilayaCode}) {
    final key = '$workerId:${wilayaCode ?? "all"}';
    if (!_workerReqControllers.containsKey(key)) {
      _workerReqControllers[key] =
          StreamController<List<ServiceRequestEnhancedModel>>.broadcast();
    }
    return _workerReqControllers[key]!.stream;
  }

  Stream<List<ServiceRequestEnhancedModel>> streamAvailableRequests({
    required int wilayaCode, required String serviceType,
  }) {
    final key = '$wilayaCode:$serviceType';
    if (!_availableReqCtrl.containsKey(key)) {
      _availableReqCtrl[key] =
          StreamController<List<ServiceRequestEnhancedModel>>.broadcast();
      _requestsSocket?.emit('subscribe:available_requests', {
        'wilayaCode':  wilayaCode,
        'serviceType': serviceType,
      });
    }
    return _availableReqCtrl[key]!.stream;
  }

  Stream<List<ServiceRequestEnhancedModel>> streamWorkerActiveJobs(String workerId) {
    if (!_activeJobsCtrl.containsKey(workerId)) {
      _activeJobsCtrl[workerId] =
          StreamController<List<ServiceRequestEnhancedModel>>.broadcast();
    }
    return _activeJobsCtrl[workerId]!.stream;
  }

  Stream<List<ServiceRequestEnhancedModel>> streamWorkerAssignedRequests(
      String workerId, {int limit = 30}) {
    if (!_assignedJobsCtrl.containsKey(workerId)) {
      _assignedJobsCtrl[workerId] =
          StreamController<List<ServiceRequestEnhancedModel>>.broadcast();
    }
    return _assignedJobsCtrl[workerId]!.stream;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Bid streams
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<WorkerBidModel>> streamBidsForRequest(String requestId) {
    if (!_bidsControllers.containsKey(requestId)) {
      _bidsControllers[requestId] =
          StreamController<List<WorkerBidModel>>.broadcast();
      _bidsSocket?.emit('subscribe:bids', {'requestId': requestId});
    }
    return _bidsControllers[requestId]!.stream;
  }

  Stream<List<WorkerBidModel>> streamWorkerBids(String workerId) {
    if (!_workerBidsControllers.containsKey(workerId)) {
      _workerBidsControllers[workerId] =
          StreamController<List<WorkerBidModel>>.broadcast();
      _bidsSocket?.emit('subscribe:worker_bids');
    }
    return _workerBidsControllers[workerId]!.stream;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Worker location emit (used by RealTimeLocationService)
  // ═══════════════════════════════════════════════════════════════════════════

  void emitWorkerLocation(double lat, double lng) {
    _workersSocket?.emit('worker:update_location', {'lat': lat, 'lng': lng});
  }

  void emitWorkerStatus(bool isOnline) {
    _workersSocket?.emit('worker:set_status', {'isOnline': isOnline});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Dispose
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _workersSocket?.disconnect();
    _requestsSocket?.disconnect();
    _bidsSocket?.disconnect();

    void closeAll(Map<String, StreamController> map) {
      map.values.forEach((c) { if (!c.isClosed) c.close(); });
      map.clear();
    }

    closeAll(_workerControllers);
    closeAll(_wilayaControllers);
    closeAll(_requestControllers);
    closeAll(_userReqControllers);
    closeAll(_workerReqControllers);
    closeAll(_availableReqCtrl);
    closeAll(_activeJobsCtrl);
    closeAll(_assignedJobsCtrl);
    closeAll(_bidsControllers);
    closeAll(_workerBidsControllers);

    if (!_allOnlineController.isClosed) _allOnlineController.close();

    if (kDebugMode) debugPrint('[RealtimeService] disposed');
  }
}
