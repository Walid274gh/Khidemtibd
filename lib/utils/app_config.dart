// lib/utils/app_config.dart
//
// SECURITY FIX: Added cloudinary_cloud_name and cloudinary_upload_preset
// to Remote Config defaults and fetch cycle. These were previously compiled
// as static const String directly into the binary (CloudinaryConfig).
//
// Both keys are now fetched at runtime alongside gemini_api_key. The binary
// contains only empty-string defaults — never the real values.

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // Remote Config parameter names — must match exactly what is set in Firebase.
  static const String _kGemini         = 'gemini_api_key';
  static const String _kMaptiler       = 'maptiler_api_key';
  // SECURITY FIX: Cloudinary credentials now live in Remote Config, not binary.
  static const String _kCloudinaryName  = 'cloudinary_cloud_name';
  static const String _kCloudinaryPreset = 'cloudinary_upload_preset';

  // Cache duration — keys are fetched fresh at most once per hour.
  static const Duration _fetchInterval = Duration(hours: 1);

  static FirebaseRemoteConfig get _rc => FirebaseRemoteConfig.instance;

  /// Call once in main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout:         const Duration(seconds: 10),
        minimumFetchInterval: _fetchInterval,
      ));

      // Set empty defaults so the app never crashes if Remote Config
      // is unreachable on first launch.
      await _rc.setDefaults(const {
        _kGemini:          '',
        _kMaptiler:        '',
        // SECURITY FIX: register Cloudinary keys with empty defaults.
        _kCloudinaryName:   '',
        _kCloudinaryPreset: '',
      });

      await _rc.fetchAndActivate();
      _logInfo('AppConfig: Remote Config initialised');
    } catch (e) {
      // Non-fatal — cached or default values will be used.
      _logWarning('AppConfig: Remote Config init failed — $e');
    }
  }

  /// Gemini API key — read from Remote Config at runtime.
  static String get geminiApiKey {
    final key = _rc.getString(_kGemini);
    if (key.isEmpty) _logWarning('AppConfig: gemini_api_key is empty');
    return key;
  }

  /// MapTiler API key — read from Remote Config at runtime.
  static String get maptilerApiKey {
    final key = _rc.getString(_kMaptiler);
    if (key.isEmpty) _logWarning('AppConfig: maptiler_api_key is empty');
    return key;
  }

  // NOTE: Cloudinary values are intentionally NOT exposed here.
  // They are accessed exclusively through CloudinaryConfig (lib/config/
  // cloudinary_config.dart) which reads directly from FirebaseRemoteConfig.
  // This keeps the access pattern consistent and avoids a second getter path.

  static void _logInfo(String msg) {
    if (kDebugMode) debugPrint('[AppConfig] $msg');
  }

  static void _logWarning(String msg) {
    if (kDebugMode) debugPrint('[AppConfig] WARNING: $msg');
  }
}
