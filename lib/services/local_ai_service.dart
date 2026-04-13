// lib/services/local_ai_service.dart
//
// BUG 4 FIX B — AI image search échoue au premier appel
//
// PROBLÈME :
//   1. TIMEOUT cold-start : Gemini met 15–25s sur la première requête
//      (chargement modèle). Le timeout client était fixé à 15s pour TOUTES les
//      requêtes → TimeoutException → "Erreur de recherche". Le retry suivant
//      fonctionnait car le modèle était déjà chaud.
//   2. Le timeout image partageait la même constante que le timeout texte
//      (_callTimeout = 15s), trop court pour un cold-start Gemini.
//
// SOLUTION :
//   • _callTimeoutText  = 15s  (inchangé — texte est rapide)
//   • _callTimeoutImage = 30s  (augmenté — cold-start Gemini ~20s)
//   • _extractWithImage() : retry x2 sur TimeoutException avec 2s de délai
//     (si Gemini cold-start dépasse même 30s au premier appel, le second
//     appel trouvera le modèle chaud et répondra en < 5s)

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/search_intent.dart';

// ── Re-export error types so callers keep identical imports ──────────────────

enum AiExtractorErrorCode {
  quotaExceeded,
  modelOverloaded,
  timeout,
  network,
  parse,
  invalidInput,
  alreadyProcessing,
}

class AiIntentExtractorException implements Exception {
  final String              message;
  final AiExtractorErrorCode code;

  const AiIntentExtractorException(
    this.message, {
    this.code = AiExtractorErrorCode.network,
  });

  @override
  String toString() => 'AiIntentExtractorException[$code]: $message';
}

// ─────────────────────────────────────────────────────────────────────────────

class LocalAiService {
  final String      _baseUrl;
  final http.Client _http;

  // BUG 4 FIX B : deux timeouts distincts
  // • texte/audio : 15s  — réponse rapide sur modèle chaud
  // • image       : 30s  — cold-start Gemini peut atteindre ~25s
  static const Duration _callTimeoutText  = Duration(seconds: 15);
  static const Duration _callTimeoutImage = Duration(seconds: 30);

  static const int _cacheCapacity   = 20;
  static const int _maxCallsPerHour = 20;

  bool _isBusyText  = false; // garde pour extract() text + image
  bool _isBusyAudio = false; // garde pour extractFromAudio()

  bool get isBusy => _isBusyText || _isBusyAudio;

  final _cache = LinkedHashMap<String, SearchIntent>(
    equals:   (a, b) => a == b,
    hashCode: (k) => k.hashCode,
  );

  final List<DateTime> _callTimestamps = [];

  LocalAiService({required String baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http    = httpClient ?? http.Client();

  // ── Cache helpers ──────────────────────────────────────────────────────────

  SearchIntent? _getCached(String key) {
    final entry = _cache[key];
    if (entry != null) {
      _cache.remove(key);
      _cache[key] = entry;
    }
    return entry;
  }

  void _putCache(String key, SearchIntent value) {
    if (_cache.length >= _cacheCapacity) _cache.remove(_cache.keys.first);
    _cache[key] = value;
  }

  // ── Rate limiter ───────────────────────────────────────────────────────────

  bool _isRateLimited() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    _callTimestamps.removeWhere((t) => t.isBefore(cutoff));
    return _callTimestamps.length >= _maxCallsPerHour;
  }

  void _recordCall() => _callTimestamps.add(DateTime.now());

  // ── Auth header ────────────────────────────────────────────────────────────

  Future<String?> _getToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SearchIntent> extract(
    String text, {
    Uint8List? imageBytes,
    String?    mime,
  }) async {
    final hasText  = text.trim().isNotEmpty;
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;

    if (!hasText && !hasImage) {
      throw const AiIntentExtractorException(
        'No input provided',
        code: AiExtractorErrorCode.invalidInput,
      );
    }

    if (_isBusyText) {
      throw const AiIntentExtractorException(
        'Already processing a request',
        code: AiExtractorErrorCode.alreadyProcessing,
      );
    }

    if (_isRateLimited()) {
      throw const AiIntentExtractorException(
        'Rate limit exceeded — max 20 requests per hour',
        code: AiExtractorErrorCode.quotaExceeded,
      );
    }

    if (hasText && !hasImage) {
      final cacheKey     = text.trim().toLowerCase();
      final cachedResult = _getCached(cacheKey);
      if (cachedResult != null) return cachedResult;
    }

    _isBusyText = true;
    try {
      SearchIntent result;
      if (hasImage) {
        // BUG 4 FIX B : déléguer à _extractWithImage() qui gère
        // le timeout long (30s) et le retry x2.
        result = await _extractWithImage(text, imageBytes!, mime);
      } else {
        result = await _extractText(text);
      }
      if (hasText && !hasImage) _putCache(text.trim().toLowerCase(), result);
      _recordCall();
      return result;
    } finally {
      _isBusyText = false;
    }
  }

  Future<SearchIntent> extractFromAudio(
    Uint8List audioBytes, {
    String mime       = 'audio/m4a',
    int    maxRetries = 2,
  }) async {
    if (audioBytes.isEmpty) {
      throw const AiIntentExtractorException(
        'Audio bytes are empty',
        code: AiExtractorErrorCode.invalidInput,
      );
    }

    if (_isBusyAudio) {
      throw const AiIntentExtractorException(
        'Already processing an audio request',
        code: AiExtractorErrorCode.alreadyProcessing,
      );
    }

    if (_isRateLimited()) {
      throw const AiIntentExtractorException(
        'Rate limit exceeded',
        code: AiExtractorErrorCode.quotaExceeded,
      );
    }

    _isBusyAudio = true;
    Exception? lastError;

    try {
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final token   = await _getToken();
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('$_baseUrl/ai/extract-intent/audio'),
          );
          if (token != null) request.headers['Authorization'] = 'Bearer $token';

          request.files.add(http.MultipartFile.fromBytes(
            'file',
            audioBytes,
            filename:    'audio.m4a',
            contentType: MediaType.parse(mime),
          ));

          // Audio utilise le timeout texte (15s) — il n'a pas de cold-start image
          final streamed = await request.send().timeout(_callTimeoutText);
          final response = await http.Response.fromStream(streamed);

          if (response.statusCode >= 500 && attempt < maxRetries) {
            if (kDebugMode) {
              debugPrint('[LocalAiService] Audio attempt $attempt failed '
                  '(${response.statusCode}), retrying...');
            }
            await Future.delayed(Duration(seconds: attempt));
            continue;
          }

          _recordCall();
          return _parseResponse(response);

        } on AiIntentExtractorException {
          rethrow;
        } on TimeoutException {
          lastError = const AiIntentExtractorException(
            'Audio request timed out',
            code: AiExtractorErrorCode.timeout,
          );
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          lastError = _classifyError(e);
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }

      throw lastError ??
          const AiIntentExtractorException(
            'Audio extraction failed after retries',
            code: AiExtractorErrorCode.network,
          );
    } finally {
      _isBusyAudio = false;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<SearchIntent> _extractText(String text) async {
    final token    = await _getToken();
    final response = await _http.post(
      Uri.parse('$_baseUrl/ai/extract-intent'),
      headers: {
        'Content-Type':  'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'text': text.trim()}),
    ).timeout(_callTimeoutText);
    return _parseResponse(response);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 4 FIX B — _extractWithImage()
  //
  // Timeout augmenté à 30s (_callTimeoutImage) pour absorber le cold-start
  // Gemini (~15–25s sur la première requête).
  //
  // Retry x2 sur TimeoutException :
  //   • Attempt 1 : peut timeout si Gemini était en cold-start
  //   • Attempt 2 : modèle maintenant chaud → réponse en < 5s
  //   • Les erreurs quota/overload (AiIntentExtractorException) ne sont PAS
  //     retentées — elles indiquent un problème permanent.
  // ─────────────────────────────────────────────────────────────────────────
  Future<SearchIntent> _extractWithImage(
    String text,
    Uint8List imageBytes,
    String? mime,
  ) async {
    final detectedMime = _detectImageMime(imageBytes) ?? mime ?? 'image/jpeg';
    final extension    = detectedMime == 'image/png'
        ? 'png'
        : detectedMime == 'image/webp'
            ? 'webp'
            : 'jpg';

    Exception? lastError;

    // BUG 4 FIX B : retry x2 sur timeout (cold-start Gemini)
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final token   = await _getToken();
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_baseUrl/ai/extract-intent/image'),
        );
        if (token != null) request.headers['Authorization'] = 'Bearer $token';

        // MediaType explicite — évite application/octet-stream
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename:    'image.$extension',
          contentType: MediaType.parse(detectedMime),
        ));

        if (text.trim().isNotEmpty) {
          request.fields['text'] = text.trim();
        }

        // BUG 4 FIX B : timeout image = 30s (au lieu de 15s partagé)
        final streamed = await request.send().timeout(_callTimeoutImage);
        final response = await http.Response.fromStream(streamed);
        return _parseResponse(response);

      } on AiIntentExtractorException {
        // quota / overload → ne pas retenter
        rethrow;
      } on TimeoutException {
        lastError = AiIntentExtractorException(
          'Image analysis timed out (attempt $attempt/2)',
          code: AiExtractorErrorCode.timeout,
        );
        if (attempt < 2) {
          if (kDebugMode) {
            debugPrint('[LocalAiService] Image timeout (attempt $attempt/2), retrying...');
          }
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        lastError = _classifyError(e);
        break; // erreur non-timeout → pas de retry
      }
    }

    throw lastError ??
        const AiIntentExtractorException(
          'Image extraction failed',
          code: AiExtractorErrorCode.network,
        );
  }

  /// Détection MIME depuis magic bytes — évite application/octet-stream.
  String? _detectImageMime(Uint8List bytes) {
    if (bytes.length < 4) return null;
    // JPEG : FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // PNG : 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    // WebP : RIFF....WEBP (12 octets minimum)
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 &&
        bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  SearchIntent _parseResponse(http.Response response) {
    if (response.statusCode == 429) {
      throw const AiIntentExtractorException(
        'Quota exceeded — retry in a few minutes',
        code: AiExtractorErrorCode.quotaExceeded,
      );
    }
    if (response.statusCode == 503) {
      throw const AiIntentExtractorException(
        'Model temporarily overloaded — retry',
        code: AiExtractorErrorCode.modelOverloaded,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiIntentExtractorException(
        'Server error (${response.statusCode})',
        code: AiExtractorErrorCode.network,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      final Map<String, dynamic> json;
      if (decoded is Map && decoded['success'] == true && decoded.containsKey('data')) {
        json = (decoded['data'] as Map).cast<String, dynamic>();
      } else if (decoded is Map) {
        json = decoded.cast<String, dynamic>();
      } else {
        return const SearchIntent();
      }
      return SearchIntent.fromJson(json);
    } catch (e) {
      throw AiIntentExtractorException(
        'Parse error: $e',
        code: AiExtractorErrorCode.parse,
      );
    }
  }

  AiIntentExtractorException _classifyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('429') || msg.contains('quota') || msg.contains('rate limit')) {
      return const AiIntentExtractorException(
          'Quota exceeded', code: AiExtractorErrorCode.quotaExceeded);
    }
    if (msg.contains('503') || msg.contains('overload') || msg.contains('unavailable')) {
      return const AiIntentExtractorException(
          'Model overloaded', code: AiExtractorErrorCode.modelOverloaded);
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return const AiIntentExtractorException(
          'Request timed out', code: AiExtractorErrorCode.timeout);
    }
    return AiIntentExtractorException(
        'Network error: $e', code: AiExtractorErrorCode.network);
  }

  void dispose() {
    _cache.clear();
    _callTimestamps.clear();
    _http.close();
  }
}
