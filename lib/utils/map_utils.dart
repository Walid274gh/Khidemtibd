// lib/utils/map_utils.dart

import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/map_bounds.dart';

/// Typed exception thrown by [MapUtils.createCustomMarker] when the canvas
/// pipeline fails (e.g. OOM or invalid recorder state).
class MapUtilsException implements Exception {
  final String message;
  final dynamic originalError;

  const MapUtilsException(this.message, {this.originalError});

  @override
  String toString() =>
      'MapUtilsException: $message'
      '${originalError != null ? ' (caused by: $originalError)' : ''}';
}

class MapUtils {
  // Calculer le centre et le zoom pour afficher tous les points
  static MapBounds calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return MapBounds(
        center: LatLng(36.7372, 3.0865), // Alger par défaut
        zoom: 10.0,
      );
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Calculer le zoom approprié basé sur la distance
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = math.max(latDiff, lngDiff);

    double zoom;
    if (maxDiff > 1.0) {
      zoom = 8.0;
    } else if (maxDiff > 0.5) {
      zoom = 10.0;
    } else if (maxDiff > 0.1) {
      zoom = 12.0;
    } else if (maxDiff > 0.01) {
      zoom = 14.0;
    } else {
      zoom = 16.0;
    }

    return MapBounds(
      center: LatLng(centerLat, centerLng),
      zoom: zoom,
    );
  }

  // Créer des markers personnalisés
  //
  // B1 FIX: wrapped the entire method body in try/catch.
  // picture.toImage() can throw if the PictureRecorder is in an invalid
  // state or the system is out of memory. Previously the exception would
  // silently propagate as an unhandled error; now it is caught and rethrown
  // as a typed [MapUtilsException] so callers can handle it gracefully.
  static Future<ui.Image> createCustomMarker({
    required String text,
    required Color backgroundColor,
    required Color textColor,
    double size = 80.0,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Dessiner le cercle
      final paint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);

      // Ajouter une bordure
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

      // Dessiner le texte
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: textColor,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          size / 2 - textPainter.width / 2,
          size / 2 - textPainter.height / 2,
        ),
      );

      final picture = recorder.endRecording();
      return await picture.toImage(size.toInt(), size.toInt());
    } catch (e) {
      throw MapUtilsException(
        'Failed to create custom marker for text "$text"',
        originalError: e,
      );
    }
  }
}
