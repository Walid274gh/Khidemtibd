// lib/utils/app_config.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// API URL RESOLUTION — 3 layers, highest priority wins
// ═══════════════════════════════════════════════════════════════════════════
//
//  LAYER 1 — Firebase Remote Config  (dynamic, no rebuild)
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │ Key: "api_base_url"                                                 │
//  │ How: Firebase Console → Remote Config → api_base_url → Publish     │
//  │ Use: Paste your daily Cloudflare Quick Tunnel URL here              │
//  │      e.g.  https://random-words.trycloudflare.com                  │
//  │      or    https://api.khidmeti.dz  (production)                   │
//  │ When it applies: any time the app can reach Firebase on cold-start  │
//  └─────────────────────────────────────────────────────────────────────┘
//
//  LAYER 2 — Compile-time --dart-define  (static, set once per session)
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │ Key: API_BASE_URL                                                   │
//  │ How: flutter run  --dart-define=API_BASE_URL=http://192.168.1.X:80 │
//  │      flutter build --dart-define=API_BASE_URL=https://api.khidmeti.dz│
//  │ Use: Local network testing — same WiFi, no internet needed         │
//  │ When it applies: Firebase is unreachable (offline, first install)  │
//  └─────────────────────────────────────────────────────────────────────┘
//
//  LAYER 3 — Hardcoded safety net  (last resort, never crashes)
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │ Value: http://localhost:80                                           │
//  │ Use:   Emulator running the Docker stack on the same machine        │
//  │ When it applies: Both Layer 1 and Layer 2 are absent / failed      │
//  └─────────────────────────────────────────────────────────────────────┘
//
//  QUICK TUNNEL WORKFLOW (Codespaces / Daily Dev):
//  1. Terminal A: make start            (starts Docker backend)
//  2. Terminal B: make tunnel-quick     (starts Cloudflare Quick Tunnel)
//  3. Copy the https://random-xyz.trycloudflare.com URL from Terminal B
//  4. Firebase Console → Remote Config → api_base_url → paste URL → Publish
//  5. Kill & relaunch Flutter app → it picks up the new URL automatically
//
//  LOCAL NETWORK WORKFLOW (Same WiFi):
//  1. make start
//  2. flutter run --dart-define=API_BASE_URL=http://$(hostname -I | awk '{print $1}'):80
//     (Linux) or  flutter run --dart-define=API_BASE_URL=http://YOUR_LOCAL_IP:80
//
// ═══════════════════════════════════════════════════════════════════════════

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ── Layer 3: Hardcoded safety net ─────────────────────────────────────────
  // Never changes. Keeps the app from crashing with a null URL.
  static const String _hardcodedFallback = 'http://localhost:80';

  // ── Layer 2: Compile-time variable ───────────────────────────────────────
  // Set via: flutter run --dart-define=API_BASE_URL=http://192.168.1.42:80
  // If not provided, defaults to the hardcoded safety net above.
  static const String _compileFallback = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _hardcodedFallback,
  );

  // ── Resolved URL (written once in initialize(), read-only after) ──────────
  static String _apiBaseUrl = _compileFallback;

  // ── Resolution source — for debugging only ────────────────────────────────
  static String _resolvedVia = 'pre-init (compile-time fallback)';

  // ── Public getters ─────────────────────────────────────────────────────────
  static String get apiBaseUrl     => _apiBaseUrl;
  static String get resolvedVia    => _resolvedVia;  // visible in debug logs

  static String get maptilerApiKey =>
      _getString('maptiler_api_key', 'btE7rXDcH3x6nBHcYTUY');

  // ═══════════════════════════════════════════════════════════════════════════
  // initialize() — called ONCE from main.dart before runApp()
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> initialize() async {
    try {
      final rc = FirebaseRemoteConfig.instance;

      // Embed Layer 2 as the in-app default so Remote Config can always
      // fall back to it even without a network response.
      await rc.setDefaults({
        'api_base_url':     _compileFallback,
        'maptiler_api_key': 'btE7rXDcH3x6nBHcYTUY',
      });

      await rc.setConfigSettings(RemoteConfigSettings(
        // Short timeout — we never want the splash screen to hang.
        // If Firebase doesn't respond in 5 s, we use Layer 2 or Layer 3.
        fetchTimeout:         const Duration(seconds: 5),
        // Debug: re-fetch on every cold start so you can paste a new tunnel
        // URL and see it immediately. Release: honour 1-hour cache.
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ));

      await rc.fetchAndActivate();

      // ── Try Layer 1: Firebase Remote Config ──────────────────────────────
      final remoteUrl = rc.getString('api_base_url').trim();
      if (_isValidUrl(remoteUrl) && remoteUrl != _compileFallback) {
        _apiBaseUrl   = remoteUrl;
        _resolvedVia  = 'Layer 1 — Firebase Remote Config';
        _log('✅ [$_resolvedVia] → $_apiBaseUrl');
        return;
      }

      // ── Try Layer 2: compile-time --dart-define ───────────────────────────
      if (_isValidUrl(_compileFallback) && _compileFallback != _hardcodedFallback) {
        _apiBaseUrl   = _compileFallback;
        _resolvedVia  = 'Layer 2 — --dart-define API_BASE_URL';
        _log('✅ [$_resolvedVia] → $_apiBaseUrl');
        return;
      }

      // ── Layer 3: hardcoded safety net ─────────────────────────────────────
      _apiBaseUrl   = _hardcodedFallback;
      _resolvedVia  = 'Layer 3 — hardcoded safety net';
      _log('⚠️  [$_resolvedVia] → $_apiBaseUrl');

    } catch (e) {
      // Firebase is unreachable (no internet, first install, emulator, etc.)
      // Degrade gracefully: try Layer 2, then Layer 3.
      if (_isValidUrl(_compileFallback)) {
        _apiBaseUrl   = _compileFallback;
        _resolvedVia  = 'Layer 2 — --dart-define API_BASE_URL (Firebase failed)';
      } else {
        _apiBaseUrl   = _hardcodedFallback;
        _resolvedVia  = 'Layer 3 — hardcoded safety net (Firebase + compile failed)';
      }
      _log('⚠️  [$_resolvedVia] → $_apiBaseUrl');
      _log('   Firebase error: $e');
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Accepts http:// and https:// URLs with a non-empty host.
  static bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
             uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _getString(String key, String fallback) {
    try {
      final val = FirebaseRemoteConfig.instance.getString(key).trim();
      return val.isNotEmpty ? val : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[AppConfig] $message');
  }
}
