// lib/services/local_ai_service.dart
//
// STEP 5 MIGRATION: Replaces AiIntentExtractorService.
//
// IDENTICAL external API to AiIntentExtractorService — method signatures,
// exception types, and error codes are preserved so HomeSearchController
// and all other callers need ZERO changes.
//
// Instead of calling Google Gemini directly from the Flutter client,
// all AI inference is routed through the NestJS backend which applies
// the Strategy Pattern (Gemini/Ollama/vLLM) based on AI_PROVIDER env var.
//
// Endpoints:
//   extract(text)            → POST /ai/extract-intent            { text }
//   extract(text+image)      → POST /ai/extract-intent/image      multipart
//   extractFromAudio(bytes)  → POST /ai/extract-intent/audio      multipart
//
// KEPT from original:
//   • LRU cache 20 entries (client-side dedup — server has its own)
//   • Rate limit 20/hour client-side guard
//   • AiIntentExtractorException + AiExtractorErrorCode values
//   • _isBusy guard (no concurrent calls)
//
// REMOVED:
//   • package:google_generative_ai
//   • GenerativeModel, Content, Part, _systemPrompt, _modelName

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  final String     _baseUrl;
  final http.Client _http;

  static const Duration _callTimeout    = Duration(seconds: 15);
  static const int      _cacheCapacity  = 20;
  static const int      _maxCallsPerHour = 20;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  // LRU cache (text-only queries)
  final _cache = LinkedHashMap<String, SearchIntent>(
    equals:   (a, b) => a == b,
    hashCode: (k) => k.hashCode,
  );

  // Rate limiter
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
  // Public API — identical signatures to AiIntentExtractorService
  // ═══════════════════════════════════════════════════════════════════════════

  /// Extracts a [SearchIntent] from [text] and/or [imageBytes].
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

    if (_isBusy) {
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

    _isBusy = true;
    try {
      SearchIntent result;
      if (hasImage) {
        result = await _extractWithImage(text, imageBytes!, mime);
      } else {
        result = await _extractText(text);
      }
      if (hasText && !hasImage) _putCache(text.trim().toLowerCase(), result);
      _recordCall();
      return result;
    } finally {
      _isBusy = false;
    }
  }

  /// Extracts a [SearchIntent] from raw audio bytes.
  Future<SearchIntent> extractFromAudio(
    Uint8List audioBytes, {
    String mime = 'audio/m4a',
  }) async {
    if (audioBytes.isEmpty) {
      throw const AiIntentExtractorException(
        'Audio bytes are empty',
        code: AiExtractorErrorCode.invalidInput,
      );
    }

    if (_isBusy) {
      throw const AiIntentExtractorException(
        'Already processing a request',
        code: AiExtractorErrorCode.alreadyProcessing,
      );
    }

    if (_isRateLimited()) {
      throw const AiIntentExtractorException(
        'Rate limit exceeded',
        code: AiExtractorErrorCode.quotaExceeded,
      );
    }

    _isBusy = true;
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
      ));

      final streamed  = await request.send().timeout(_callTimeout);
      final response  = await http.Response.fromStream(streamed);
      _recordCall();
      return _parseResponse(response);
    } on AiIntentExtractorException {
      rethrow;
    } catch (e) {
      throw _classifyError(e);
    } finally {
      _isBusy = false;
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
    ).timeout(_callTimeout);
    return _parseResponse(response);
  }

  Future<SearchIntent> _extractWithImage(
      String text, Uint8List imageBytes, String? mime) async {
    final token   = await _getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/ai/extract-intent/image'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      imageBytes,
      filename: 'image.jpg',
    ));
    if (text.trim().isNotEmpty) request.fields['text'] = text.trim();

    final streamed = await request.send().timeout(_callTimeout);
    final response = await http.Response.fromStream(streamed);
    return _parseResponse(response);
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
      // NestJS ResponseInterceptor wraps: { success, data, timestamp }
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
