// lib/providers/core_providers.dart
//
// STEP 6 MIGRATION: Firebase Firestore + Cloudinary + Gemini → ApiService + LocalMediaService + LocalAiService
//
// WHAT CHANGED:
//   • firestoreServiceProvider  → apiServiceProvider (Provider<ApiService>)
//     - firestoreServiceProvider is kept as a TYPE-ALIAS pointing to apiServiceProvider
//       so every existing controller (available_requests_controller, worker_home_controller,
//       service_request_form_controller …) continues to compile without modification.
//   • cloudinaryServiceProvider → localMediaServiceProvider (Provider<LocalMediaService>)
//   • aiIntentExtractorProvider → localAiServiceProvider (Provider<LocalAiService>)
//   • Added: realtimeServiceProvider (Provider<RealtimeService>)
//   • Removed: cloud_firestore import, CloudinaryConfig, FirestoreService, CloudinaryService,
//              AiIntentExtractorService
//   • All Level-2 providers (workerBidService, serviceRequestService, smartSearch,
//     notificationPush, realTimeLocation, geographicGrid) now inject apiServiceProvider.
//   • API base URL: reads --dart-define=API_BASE_URL at build time; defaults to
//     10.0.2.2:3000 (Android emulator) for debug builds.
//     Production: flutter build apk --dart-define=API_BASE_URL=https://your-server.com

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../services/local_ai_service.dart';
import '../services/local_media_service.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../services/notification_push_service.dart';
import '../services/native_channel_service.dart';
import '../services/permission_service.dart';
import '../services/location_service.dart';
import '../services/wilaya_manager.dart';
import '../services/geographic_grid_service.dart';
import '../services/realtime_location_service.dart';
import '../services/media_service.dart';
import '../services/service_request_service.dart';
import '../services/worker_bid_service.dart';
import '../services/smart_search_service.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/routing_service.dart';
import '../services/geocoding_service.dart';
import '../services/speech_to_text_service.dart';
import '../models/user_model.dart';
import '../models/worker_model.dart';
import '../models/service_request_enhanced_model.dart';
import '../models/worker_bid_model.dart';
export 'auth_providers.dart';

// ── API Base URL ──────────────────────────────────────────────────────────────
// Pass at build time: flutter run --dart-define=API_BASE_URL=http://192.168.1.x:3000
// Android emulator default (10.0.2.2 → host machine localhost:3000)
const String _kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

// ============================================================================
// LOCAL AI SERVICE
// ============================================================================

final localAiServiceProvider = Provider<LocalAiService>((ref) {
  _logInfo('Initializing LocalAiService → $_kApiBaseUrl');
  final service = LocalAiService(baseUrl: _kApiBaseUrl);
  ref.onDispose(() {
    _logInfo('Disposing LocalAiService');
    service.dispose();
  });
  return service;
});

// ============================================================================
// LEVEL 0 — INDEPENDENT SERVICES
// ============================================================================

// ── Realtime WebSocket service ────────────────────────────────────────────────
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  _logInfo('Initializing RealtimeService → $_kApiBaseUrl');
  final service = RealtimeService(baseUrl: _kApiBaseUrl);
  ref.onDispose(() {
    _logInfo('Disposing RealtimeService');
    service.dispose();
  });
  return service;
});

// ── REST API service (replaces FirestoreService) ─────────────────────────────
final apiServiceProvider = Provider<ApiService>((ref) {
  _logInfo('Initializing ApiService → $_kApiBaseUrl');
  final realtime = ref.watch(realtimeServiceProvider);
  final service = ApiService(baseUrl: _kApiBaseUrl, realtime: realtime);
  service.startCacheCleanup();
  ref.onDispose(() {
    _logInfo('Disposing ApiService');
    service.dispose();
  });
  return service;
});

// ── BACKWARD-COMPAT ALIAS ────────────────────────────────────────────────────
// All controllers that call ref.read(firestoreServiceProvider) continue to work.
// ApiService exposes identical method signatures to FirestoreService.
// New code should prefer apiServiceProvider directly.
final firestoreServiceProvider = apiServiceProvider;

// ── Local media service (replaces CloudinaryService) ─────────────────────────
final localMediaServiceProvider = Provider<LocalMediaService>((ref) {
  _logInfo('Initializing LocalMediaService → $_kApiBaseUrl');
  final service = LocalMediaService(baseUrl: _kApiBaseUrl);
  ref.onDispose(() {
    _logInfo('Disposing LocalMediaService');
    service.dispose();
  });
  return service;
});

final nativeChannelServiceProvider = Provider<NativeChannelService>((ref) {
  _logInfo('Initializing NativeChannelService');
  final service = NativeChannelService();
  ref.onDispose(() { _logInfo('Disposing NativeChannelService'); service.dispose(); });
  return service;
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  _logInfo('Initializing PermissionService');
  final service = PermissionService();
  ref.onDispose(() { _logInfo('Disposing PermissionService'); service.dispose(); });
  return service;
});

final locationServiceProvider = Provider<LocationService>((ref) {
  _logInfo('Initializing LocationService');
  final service = LocationService();
  ref.onDispose(() async { _logInfo('Disposing LocationService'); await service.dispose(); });
  return service;
});

final languageServiceProvider = Provider<LanguageService>((ref) {
  _logInfo('Initializing LanguageService');
  final service = LanguageService();
  ref.onDispose(() { _logInfo('Disposing LanguageService'); service.dispose(); });
  return service;
});

final wilayaManagerProvider = Provider<WilayaManager>((ref) {
  _logInfo('Initializing WilayaManager');
  final service = WilayaManager();
  ref.onDispose(() { _logInfo('Disposing WilayaManager'); service.dispose(); });
  return service;
});

final routingServiceProvider = Provider<RoutingService>((ref) {
  _logInfo('Initializing RoutingService');
  final service = RoutingService();
  ref.onDispose(() { _logInfo('Disposing RoutingService'); service.dispose(); });
  return service;
});

final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  _logInfo('Initializing GeocodingService');
  final service = GeocodingService();
  ref.onDispose(() { _logInfo('Disposing GeocodingService'); service.dispose(); });
  return service;
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  _logInfo('Initializing NotificationService');
  final service = NotificationService();
  ref.onDispose(() { _logInfo('Disposing NotificationService'); service.dispose(); });
  return service;
});

final audioServiceProvider = Provider<AudioService>((ref) {
  _logInfo('Initializing AudioService');
  final service = AudioService();
  ref.onDispose(() async { _logInfo('Disposing AudioService'); await service.dispose(); });
  return service;
});

final speechToTextServiceProvider = Provider<SpeechToTextService>((ref) {
  _logInfo('Initializing SpeechToTextService');
  final service = SpeechToTextService();
  ref.onDispose(() { _logInfo('Disposing SpeechToTextService'); service.dispose(); });
  return service;
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  _logInfo('Initializing AnalyticsService');
  return AnalyticsService();
});

// ============================================================================
// LEVEL 1
// ============================================================================

final mediaServiceProvider = Provider<MediaService>((ref) {
  _logInfo('Initializing MediaService');
  final localMedia = ref.watch(localMediaServiceProvider);
  final service = MediaService(localMedia);
  ref.onDispose(() async { _logInfo('Disposing MediaService'); await service.dispose(); });
  return service;
});

final geographicGridServiceProvider = Provider<GeographicGridService>((ref) {
  _logInfo('Initializing GeographicGridService');
  final service = GeographicGridService(
    ref.watch(apiServiceProvider),
    ref.watch(wilayaManagerProvider),
  );
  ref.onDispose(() { _logInfo('Disposing GeographicGridService'); service.dispose(); });
  return service;
});

final authServiceProvider = Provider<AuthService>((ref) {
  _logInfo('Initializing AuthService');
  final service = AuthService(ref.watch(apiServiceProvider));
  ref.onDispose(() { _logInfo('Disposing AuthService'); service.dispose(); });
  return service;
});

// ============================================================================
// LEVEL 2
// ============================================================================

final notificationPushServiceProvider = Provider<NotificationPushService>((ref) {
  _logInfo('Initializing NotificationPushService');
  final service = NotificationPushService(
    ref.watch(authServiceProvider),
    ref.watch(apiServiceProvider),
  );
  ref.onDispose(() async { _logInfo('Disposing NotificationPushService'); await service.dispose(); });
  return service;
});

final realTimeLocationServiceProvider = Provider<RealTimeLocationService>((ref) {
  _logInfo('Initializing RealTimeLocationService');
  final service = RealTimeLocationService(
    ref.watch(authServiceProvider),
    ref.watch(apiServiceProvider),
  );
  ref.onDispose(() async { _logInfo('Disposing RealTimeLocationService'); await service.dispose(); });
  return service;
});

final serviceRequestServiceProvider = Provider<ServiceRequestService>((ref) {
  _logInfo('Initializing ServiceRequestService');
  final service = ServiceRequestService(
    ref.watch(apiServiceProvider),
    ref.watch(mediaServiceProvider),
    ref.watch(geographicGridServiceProvider),
  );
  ref.onDispose(() { _logInfo('Disposing ServiceRequestService'); service.dispose(); });
  return service;
});

final workerBidServiceProvider = Provider<WorkerBidService>((ref) {
  _logInfo('Initializing WorkerBidService');
  final service = WorkerBidService(ref.watch(apiServiceProvider));
  ref.onDispose(() { _logInfo('Disposing WorkerBidService'); service.dispose(); });
  return service;
});

final smartSearchServiceProvider = Provider<SmartSearchService>((ref) {
  _logInfo('Initializing SmartSearchService');
  final service = SmartSearchService(
    ref.watch(apiServiceProvider),
    ref.watch(geographicGridServiceProvider),
    ref.watch(wilayaManagerProvider),
  );
  ref.onDispose(() { _logInfo('Disposing SmartSearchService'); service.dispose(); });
  return service;
});

// ============================================================================
// LANGUAGE — LOCALE STATE ADAPTER
// ============================================================================

class _LocaleStateNotifier extends StateNotifier<Locale> {
  final LanguageService _service;

  _LocaleStateNotifier(this._service) : super(_service.currentLocale) {
    _service.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    final newLocale = _service.currentLocale;
    if (newLocale != state) state = newLocale;
  }

  @override
  void dispose() {
    _service.removeListener(_onLocaleChanged);
    super.dispose();
  }
}

final localeStateNotifierProvider =
    StateNotifierProvider<_LocaleStateNotifier, Locale>((ref) {
  return _LocaleStateNotifier(ref.watch(languageServiceProvider));
});

// ============================================================================
// LANGUAGE & LOCALE — DERIVED PROVIDERS
// ============================================================================

final currentLocaleProvider = Provider<Locale>((ref) =>
    ref.watch(localeStateNotifierProvider));

final currentLanguageCodeProvider = Provider<String>((ref) =>
    ref.watch(localeStateNotifierProvider).languageCode);

final isRTLProvider = Provider<bool>((ref) {
  final langCode = ref.watch(localeStateNotifierProvider).languageCode;
  return langCode == 'ar';
});

final currentLanguageNameProvider = Provider<String>((ref) {
  final locale = ref.watch(localeStateNotifierProvider);
  return ref.read(languageServiceProvider).getLanguageName(locale.languageCode);
});

// ============================================================================
// PERMISSIONS
// ============================================================================

final hasLocationPermissionProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(permissionServiceProvider).hasLocationPermission();
  } catch (e) { _logError('hasLocationPermissionProvider', e); return false; }
});

final hasAllCriticalPermissionsProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(permissionServiceProvider).areAllCriticalPermissionsGranted();
  } catch (e) { _logError('hasAllCriticalPermissionsProvider', e); return false; }
});

// ============================================================================
// PROFILE PROVIDERS
// ============================================================================

final userProfileProvider = FutureProvider.family
    .autoDispose<UserModel?, String>((ref, String userId) async {
  final api = ref.watch(apiServiceProvider);
  if (userId.trim().isEmpty) throw ArgumentError('User ID cannot be empty');
  try {
    return await api.getUser(userId);
  } catch (e) { _logError('userProfileProvider($userId)', e); rethrow; }
});

final workerProfileProvider = FutureProvider.family
    .autoDispose<WorkerModel?, String>((ref, String workerId) async {
  final api = ref.watch(apiServiceProvider);
  if (workerId.trim().isEmpty) throw ArgumentError('Worker ID cannot be empty');
  try {
    return await api.getWorker(workerId);
  } catch (e) { _logError('workerProfileProvider($workerId)', e); rethrow; }
});

final serviceRequestProvider = FutureProvider.family
    .autoDispose<ServiceRequestEnhancedModel?, String>((ref, String requestId) async {
  final api = ref.watch(apiServiceProvider);
  if (requestId.trim().isEmpty) throw ArgumentError('Request ID cannot be empty');
  try {
    return await api.getServiceRequest(requestId);
  } catch (e) { _logError('serviceRequestProvider($requestId)', e); rethrow; }
});

// ============================================================================
// STREAM PROVIDERS
// ============================================================================

final userServiceRequestsStreamProvider = StreamProvider.family
    .autoDispose<List<ServiceRequestEnhancedModel>, String>((ref, String userId) {
  final api = ref.watch(apiServiceProvider);
  if (userId.trim().isEmpty)
    return Stream.error(ArgumentError('User ID cannot be empty'));
  try {
    return api.streamUserServiceRequests(userId);
  } catch (e) { _logError('userServiceRequestsStreamProvider', e); return Stream.error(e); }
});

final workerServiceRequestsStreamProvider = StreamProvider.family
    .autoDispose<List<ServiceRequestEnhancedModel>, String>((ref, String workerId) {
  final api = ref.watch(apiServiceProvider);
  if (workerId.trim().isEmpty)
    return Stream.error(ArgumentError('Worker ID cannot be empty'));
  try {
    return api.streamWorkerServiceRequests(workerId);
  } catch (e) { _logError('workerServiceRequestsStreamProvider', e); return Stream.error(e); }
});

final serviceRequestStreamProvider = StreamProvider.family
    .autoDispose<ServiceRequestEnhancedModel?, String>((ref, String requestId) {
  final api = ref.watch(apiServiceProvider);
  if (requestId.trim().isEmpty)
    return Stream.error(ArgumentError('Request ID cannot be empty'));
  try {
    return api.streamServiceRequest(requestId);
  } catch (e) { _logError('serviceRequestStreamProvider', e); return Stream.error(e); }
});

final bidsStreamProvider = StreamProvider.family
    .autoDispose<List<WorkerBidModel>, String>((ref, String requestId) {
  final bidService = ref.watch(workerBidServiceProvider);
  if (requestId.trim().isEmpty)
    return Stream.error(ArgumentError('Request ID cannot be empty'));
  try {
    return bidService.streamBidsForRequest(requestId);
  } catch (e) { _logError('bidsStreamProvider', e); return Stream.error(e); }
});

final availableRequestsStreamProvider = StreamProvider.family.autoDispose<
    List<ServiceRequestEnhancedModel>,
    ({int wilayaCode, String serviceType})>((ref, params) {
  final bidService = ref.watch(workerBidServiceProvider);
  try {
    return bidService.streamAvailableRequests(
        wilayaCode: params.wilayaCode, serviceType: params.serviceType);
  } catch (e) { _logError('availableRequestsStreamProvider', e); return Stream.error(e); }
});

final workerActiveJobsStreamProvider = StreamProvider.family
    .autoDispose<List<ServiceRequestEnhancedModel>, String>((ref, String workerId) {
  final bidService = ref.watch(workerBidServiceProvider);
  if (workerId.trim().isEmpty)
    return Stream.error(ArgumentError('Worker ID cannot be empty'));
  try {
    return bidService.streamWorkerActiveJobs(workerId);
  } catch (e) { _logError('workerActiveJobsStreamProvider', e); return Stream.error(e); }
});

final workerBidsStreamProvider = StreamProvider.family
    .autoDispose<List<WorkerBidModel>, String>((ref, String workerId) {
  final bidService = ref.watch(workerBidServiceProvider);
  if (workerId.trim().isEmpty)
    return Stream.error(ArgumentError('Worker ID cannot be empty'));
  try {
    return bidService.streamWorkerBids(workerId);
  } catch (e) { _logError('workerBidsStreamProvider', e); return Stream.error(e); }
});

// ============================================================================
// UTILITY
// ============================================================================

final servicesInitializedProvider = Provider<bool>((ref) {
  try {
    ref.watch(apiServiceProvider);
    ref.watch(authServiceProvider);
    ref.watch(languageServiceProvider);
    _logInfo('All services initialized successfully');
    return true;
  } catch (e) {
    _logError('servicesInitializedProvider', e);
    rethrow;
  }
});

// ============================================================================
// PROVIDER OBSERVER
// ============================================================================

class CoreProviderObserver extends ProviderObserver {
  const CoreProviderObserver();

  @override
  void didAddProvider(ProviderBase p, Object? v, ProviderContainer c) {
    if (kDebugMode) debugPrint('[Provider] Added: ${p.name ?? p.runtimeType}');
  }
  @override
  void didDisposeProvider(ProviderBase p, ProviderContainer c) {
    if (kDebugMode) debugPrint('[Provider] Disposed: ${p.name ?? p.runtimeType}');
  }
  @override
  void providerDidFail(ProviderBase p, Object e, StackTrace s, ProviderContainer c) {
    if (kDebugMode) {
      debugPrint('[Provider] FAILED: ${p.name ?? p.runtimeType}');
      debugPrint('[Provider] Error: $e');
    }
  }
}

// ============================================================================
// LOGGING
// ============================================================================

void _logInfo(String message) {
  if (kDebugMode) debugPrint('[CoreProviders] INFO: $message');
}
void _logError(String provider, dynamic error) {
  if (kDebugMode) debugPrint('[CoreProviders] ERROR in $provider: $error');
}
