// lib/models/service_request_model.dart
//
// @Deprecated — use ServiceRequestEnhancedModel for all new code.
//
// STEP 6 MIGRATION:
//   • Removed: import 'package:cloud_firestore/cloud_firestore.dart'
//   • Replaced: Timestamp → ISO-8601 DateTime string (same pattern as
//               ServiceRequestEnhancedModel which was already migrated).
//   • fromMap() now parses createdAt/acceptedAt/completedAt from ISO-8601
//     strings, DateTime, or legacy Timestamp-shaped Maps.
//   • toMap() now serializes with toIso8601String() instead of
//     Timestamp.fromDate().

import 'package:equatable/equatable.dart';

@Deprecated(
  'Use ServiceRequestEnhancedModel. '
  'ServiceRequestModel predates the Hybrid Bid Model and will be deleted '
  'after full consumer migration.',
)
class ServiceRequestModel extends Equatable {
  final String id;
  final String userId;
  final String workerId;
  final String serviceType;
  final String status; // pending, accepted, declined, completed
  final double userLatitude;
  final double userLongitude;
  final String userAddress;
  final String? description;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  const ServiceRequestModel({
    required this.id,
    required this.userId,
    required this.workerId,
    required this.serviceType,
    required this.status,
    required this.userLatitude,
    required this.userLongitude,
    required this.userAddress,
    this.description,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
  });

  factory ServiceRequestModel.fromMap(Map<String, dynamic> map, String id) {
    return ServiceRequestModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      workerId: map['workerId'] as String? ?? '',
      serviceType: map['serviceType'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      userLatitude: (map['userLatitude'] as num?)?.toDouble() ?? 0.0,
      userLongitude: (map['userLongitude'] as num?)?.toDouble() ?? 0.0,
      userAddress: map['userAddress'] as String? ?? '',
      description: map['description'] as String?,
      createdAt: _parseDate(map['createdAt']),
      acceptedAt: _parseDateOrNull(map['acceptedAt']),
      completedAt: _parseDateOrNull(map['completedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'workerId': workerId,
      'serviceType': serviceType,
      'status': status,
      'userLatitude': userLatitude,
      'userLongitude': userLongitude,
      'userAddress': userAddress,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  ServiceRequestModel copyWith({
    String? id,
    String? userId,
    String? workerId,
    String? serviceType,
    String? status,
    double? userLatitude,
    double? userLongitude,
    String? userAddress,
    String? description,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? completedAt,
  }) {
    return ServiceRequestModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      workerId: workerId ?? this.workerId,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      userLatitude: userLatitude ?? this.userLatitude,
      userLongitude: userLongitude ?? this.userLongitude,
      userAddress: userAddress ?? this.userAddress,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        workerId,
        serviceType,
        status,
        userLatitude,
        userLongitude,
        userAddress,
        description,
        createdAt,
        acceptedAt,
        completedAt,
      ];
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  // Legacy Firestore Timestamp shape {_seconds, _nanoseconds}
  if (value is Map) {
    final seconds = value['_seconds'] as int? ?? value['seconds'] as int?;
    if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return DateTime.now();
}

DateTime? _parseDateOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['_seconds'] as int? ?? value['seconds'] as int?;
    if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return null;
}
