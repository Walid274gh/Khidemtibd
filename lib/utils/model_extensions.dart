// lib/utils/model_extensions.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/geographic_cell.dart';
import '../models/route_info.dart';
import '../models/service_request_enhanced_model.dart';
import '../models/worker_model.dart';
import '../models/message_enums.dart';

// ============================================================================
// GEOGRAPHIC CELL EXTENSIONS
// ============================================================================

extension GeographicCellLogic on GeographicCell {
  /// Checks whether a point falls within this cell.
  bool containsPoint(double lat, double lng) {
    return _calculateDistance(centerLat, centerLng, lat, lng) <= radius;
  }

  /// Haversine distance in km between two geographic points.
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}

// ============================================================================
// ROUTE INFO EXTENSIONS
// ============================================================================

extension RouteInfoLogic on RouteInfo {
  /// Formatted distance: "500 m" or "1.2 km".
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.toInt()} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Formatted duration: "15 min" or "1h 30min".
  String get formattedDuration {
    final minutes = (duration / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}min';
    }
  }
}

// ============================================================================
// SERVICE REQUEST ENHANCED EXTENSIONS
// ============================================================================

extension ServiceRequestEnhancedLogic on ServiceRequestEnhancedModel {
  /// HH:MM formatted scheduled time.
  String get formattedScheduledTime {
    return '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}';
  }

  /// DD/MM short date.
  String get formattedScheduledDateShort {
    return '${scheduledDate.day.toString().padLeft(2, '0')}/${scheduledDate.month.toString().padLeft(2, '0')}';
  }

  /// DD/MM/YYYY full date.
  String get formattedScheduledDate {
    return '${scheduledDate.day.toString().padLeft(2, '0')}/${scheduledDate.month.toString().padLeft(2, '0')}/${scheduledDate.year}';
  }

  bool get isUrgent => priority == ServicePriority.urgent;
  bool get hasMedia  => mediaUrls.isNotEmpty;

  bool get isCompleted => status == ServiceStatus.completed;
  bool get isPending   => status == ServiceStatus.pending;
  bool get isAccepted  => status == ServiceStatus.accepted;
}

// ============================================================================
// WORKER MODEL EXTENSIONS
// ============================================================================

extension WorkerLogic on WorkerModel {
  /// Haversine distance in km from this worker to a user location.
  double distanceTo(double userLat, double userLng) {
    if (latitude == null || longitude == null) return double.infinity;

    const double earthRadius = 6371;
    double dLat = _degreesToRadians(userLat - latitude!);
    double dLng = _degreesToRadians(userLng - longitude!);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(latitude!)) *
            cos(_degreesToRadians(userLat)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180);
}
