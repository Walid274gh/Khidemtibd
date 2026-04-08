// lib/services/local_media_service.dart
//
// STEP 5 MIGRATION: Replaces CloudinaryService.
//
// IDENTICAL external API to CloudinaryService — same method signatures,
// same exception type (CloudinaryServiceException) — so MediaService
// needs ZERO code changes (only its constructor injection changes in Step 6).
//
// All uploads are routed to the NestJS MinIO endpoints:
//   POST /media/upload/image  → returns { url, key }
//   POST /media/upload/video  → returns { url, key }
//   POST /media/upload/audio  → returns { url, key }
//
// Returns the MinIO URL string (same type Cloudinary returned).

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Re-export exception type so MediaService import is unchanged
export 'local_media_service.dart' show CloudinaryServiceException;

class CloudinaryServiceException implements Exception {
  final String  message;
  final String? code;
  final dynamic originalError;

  const CloudinaryServiceException(this.message, {this.code, this.originalError});

  @override
  String toString() =>
      'CloudinaryServiceException: $message${code != null ? ' ($code)' : ''}';
}

class LocalMediaService {
  final String      _baseUrl;
  final http.Client _http;

  static const Duration _uploadTimeout = Duration(minutes: 5);

  LocalMediaService({required String baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http    = httpClient ?? http.Client();

  Future<String?> _getToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  // ── Core upload ────────────────────────────────────────────────────────────

  Future<String> _upload(File file, String endpoint) async {
    if (!await file.exists()) {
      throw CloudinaryServiceException(
          'File does not exist: ${file.path}', code: 'FILE_NOT_FOUND');
    }
    final fileSize = await file.length();
    if (fileSize == 0) {
      throw CloudinaryServiceException('File is empty', code: 'EMPTY_FILE');
    }

    final token   = await _getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$endpoint'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    try {
      final streamed  = await request.send().timeout(_uploadTimeout);
      final response  = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudinaryServiceException(
          'Upload failed (${response.statusCode})',
          code: 'UPLOAD_FAILED',
        );
      }

      final decoded = jsonDecode(response.body);
      final Map<String, dynamic> data;
      if (decoded is Map && decoded['success'] == true && decoded.containsKey('data')) {
        data = (decoded['data'] as Map).cast<String, dynamic>();
      } else if (decoded is Map) {
        data = decoded.cast<String, dynamic>();
      } else {
        throw const CloudinaryServiceException('Unexpected response format', code: 'PARSE_ERROR');
      }

      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const CloudinaryServiceException('No URL in response', code: 'PARSE_ERROR');
      }

      if (kDebugMode) debugPrint('[LocalMediaService] Upload success: $url');
      return url;
    } on CloudinaryServiceException {
      rethrow;
    } catch (e) {
      throw CloudinaryServiceException(
        'Upload error',
        code: 'UPLOAD_ERROR',
        originalError: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API — identical signatures to CloudinaryService
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> uploadImage(File file, {String? folder}) async =>
      _upload(file, '/media/upload/image');

  Future<String> uploadVideo(File file, {String? folder, int? maxDurationSeconds}) async =>
      _upload(file, '/media/upload/video');

  Future<String> uploadAudio(File file, {String? folder}) async =>
      _upload(file, '/media/upload/audio');

  // Stubs that match CloudinaryService interface (used by MediaService)

  String getOptimizedImageUrl(String publicId, {
    int? width, int? height, String crop = 'fill',
    int quality = 80, String format = 'auto',
  }) => publicId; // MinIO URLs are already direct — no transformation needed

  String getVideoUrl(String publicId, {int? width, int? height, String format = 'mp4'}) =>
      publicId;

  Future<bool> deleteFile(String publicId) async => false; // server-side only

  void dispose() => _http.close();
}
