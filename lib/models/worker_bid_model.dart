// lib/models/worker_bid_model.dart
//
// STEP 1 MIGRATION: Firestore Timestamp → ISO-8601 DateTime string

import 'package:equatable/equatable.dart';
import 'message_enums.dart';

const _kUndefined = Object();

class WorkerBidModel extends Equatable {
  final String id;
  final String serviceRequestId;
  final String workerId;
  final String workerName;
  final double workerAverageRating;
  final int workerJobsCompleted;
  final String? workerProfileImageUrl;
  final double proposedPrice;
  final int estimatedMinutes;
  final DateTime availableFrom;
  final String? message;
  final BidStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;

  const WorkerBidModel({
    required this.id,
    required this.serviceRequestId,
    required this.workerId,
    required this.workerName,
    required this.workerAverageRating,
    required this.workerJobsCompleted,
    this.workerProfileImageUrl,
    required this.proposedPrice,
    required this.estimatedMinutes,
    required this.availableFrom,
    this.message,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    this.acceptedAt,
  });

  factory WorkerBidModel.fromMap(Map<String, dynamic> map, String id) {
    return WorkerBidModel(
      id: id,
      serviceRequestId: map['serviceRequestId'] as String? ?? '',
      workerId: map['workerId'] as String? ?? '',
      workerName: map['workerName'] as String? ?? '',
      workerAverageRating: (map['workerAverageRating'] as num?)?.toDouble() ?? 0.0,
      workerJobsCompleted: map['workerJobsCompleted'] as int? ?? 0,
      workerProfileImageUrl: map['workerProfileImageUrl'] as String?,
      proposedPrice: (map['proposedPrice'] as num?)?.toDouble() ?? 0.0,
      estimatedMinutes: map['estimatedMinutes'] as int? ?? 60,
      availableFrom: _parseDate(map['availableFrom']),
      message: map['message'] as String?,
      status: BidStatus.values.firstWhere(
        (e) => e.name == map['status'] || e.toString() == map['status'],
        orElse: () => BidStatus.pending,
      ),
      createdAt: _parseDate(map['createdAt']),
      expiresAt: _parseDateOrNull(map['expiresAt']),
      acceptedAt: _parseDateOrNull(map['acceptedAt']),
    );
  }

  factory WorkerBidModel.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id']) as String? ?? '';
    return WorkerBidModel.fromMap(json, id);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'serviceRequestId': serviceRequestId,
      'workerId': workerId,
      'workerName': workerName,
      'workerAverageRating': workerAverageRating,
      'workerJobsCompleted': workerJobsCompleted,
      'workerProfileImageUrl': workerProfileImageUrl,
      'proposedPrice': proposedPrice,
      'estimatedMinutes': estimatedMinutes,
      'availableFrom': availableFrom.toIso8601String(),
      'message': message,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
    };
  }

  WorkerBidModel copyWith({
    String? id,
    String? serviceRequestId,
    String? workerId,
    String? workerName,
    double? workerAverageRating,
    int? workerJobsCompleted,
    Object? workerProfileImageUrl = _kUndefined,
    double? proposedPrice,
    int? estimatedMinutes,
    DateTime? availableFrom,
    Object? message = _kUndefined,
    BidStatus? status,
    DateTime? createdAt,
    Object? expiresAt = _kUndefined,
    Object? acceptedAt = _kUndefined,
  }) {
    return WorkerBidModel(
      id: id ?? this.id,
      serviceRequestId: serviceRequestId ?? this.serviceRequestId,
      workerId: workerId ?? this.workerId,
      workerName: workerName ?? this.workerName,
      workerAverageRating: workerAverageRating ?? this.workerAverageRating,
      workerJobsCompleted: workerJobsCompleted ?? this.workerJobsCompleted,
      workerProfileImageUrl: identical(workerProfileImageUrl, _kUndefined)
          ? this.workerProfileImageUrl
          : workerProfileImageUrl as String?,
      proposedPrice: proposedPrice ?? this.proposedPrice,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      availableFrom: availableFrom ?? this.availableFrom,
      message: identical(message, _kUndefined) ? this.message : message as String?,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: identical(expiresAt, _kUndefined) ? this.expiresAt : expiresAt as DateTime?,
      acceptedAt: identical(acceptedAt, _kUndefined) ? this.acceptedAt : acceptedAt as DateTime?,
    );
  }

  String get estimatedDurationLabel {
    if (estimatedMinutes < 60) return '${estimatedMinutes}min';
    final hours = estimatedMinutes ~/ 60;
    final mins  = estimatedMinutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h${mins}min';
  }

  String get workerInitials {
    final parts = workerName.trim().split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts[0];
    if (first.isEmpty) return '?';
    if (parts.length == 1) return first[0].toUpperCase();
    final second = parts[1];
    if (second.isEmpty) return first[0].toUpperCase();
    return '${first[0]}${second[0]}'.toUpperCase();
  }

  @override
  List<Object?> get props => [
        id, serviceRequestId, workerId, workerName, workerAverageRating,
        workerJobsCompleted, workerProfileImageUrl, proposedPrice,
        estimatedMinutes, availableFrom, message, status,
        createdAt, expiresAt, acceptedAt,
      ];
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  if (value is Map) {
    final seconds = value['_seconds'] as int?;
    if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return DateTime.now();
}

DateTime? _parseDateOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['_seconds'] as int?;
    if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return null;
}
