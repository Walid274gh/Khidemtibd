// lib/models/service_request_enhanced_model.dart
//
// STEP 1 MIGRATION: Firestore Timestamp → ISO-8601 DateTime string

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'message_enums.dart';

class ServiceRequestEnhancedModel extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;

  final String serviceType;
  final String title;
  final String description;
  final DateTime scheduledDate;
  final TimeOfDay scheduledTime;
  final ServicePriority priority;

  final ServiceStatus status;

  final double userLatitude;
  final double userLongitude;
  final String userAddress;

  final String? cellId;
  final int? wilayaCode;
  final String? geoHash;
  final DateTime? lastCellUpdate;

  final int bidCount;
  final DateTime? biddingDeadlineAt;
  final String? selectedBidId;
  final double? budgetMin;
  final double? budgetMax;

  final String? workerId;
  final String? workerName;
  final double? agreedPrice;

  final List<String> mediaUrls;

  final DateTime createdAt;
  final DateTime? bidSelectedAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  final String? workerNotes;
  final double? finalPrice;
  final double? estimatedPrice;
  final int? estimatedDuration;

  final int? clientRating;
  final String? reviewComment;

  int? get rating => clientRating;

  const ServiceRequestEnhancedModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.serviceType,
    required this.title,
    required this.description,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.priority,
    required this.status,
    required this.userLatitude,
    required this.userLongitude,
    required this.userAddress,
    required this.mediaUrls,
    this.bidCount = 0,
    this.biddingDeadlineAt,
    this.selectedBidId,
    this.budgetMin,
    this.budgetMax,
    this.workerId,
    this.workerName,
    this.agreedPrice,
    required this.createdAt,
    this.bidSelectedAt,
    this.acceptedAt,
    this.completedAt,
    this.workerNotes,
    this.finalPrice,
    this.estimatedPrice,
    this.estimatedDuration,
    this.clientRating,
    this.reviewComment,
    this.cellId,
    this.wilayaCode,
    this.geoHash,
    this.lastCellUpdate,
  });

  static ServiceStatus _parseStatus(dynamic raw) {
    final s = raw?.toString() ?? '';
    switch (s) {
      case 'open':              case 'ServiceStatus.open':              return ServiceStatus.open;
      case 'awaitingSelection': case 'ServiceStatus.awaitingSelection': return ServiceStatus.awaitingSelection;
      case 'bidSelected':       case 'ServiceStatus.bidSelected':       return ServiceStatus.bidSelected;
      case 'inProgress':        case 'ServiceStatus.inProgress':        return ServiceStatus.inProgress;
      case 'completed':         case 'ServiceStatus.completed':         return ServiceStatus.completed;
      case 'cancelled':         case 'ServiceStatus.cancelled':         return ServiceStatus.cancelled;
      case 'expired':           case 'ServiceStatus.expired':           return ServiceStatus.expired;
      case 'pending':           case 'ServiceStatus.pending':           return ServiceStatus.pending;
      case 'accepted':          case 'ServiceStatus.accepted':          return ServiceStatus.accepted;
      case 'declined':          case 'ServiceStatus.declined':          return ServiceStatus.declined;
      default:                                                           return ServiceStatus.open;
    }
  }

  factory ServiceRequestEnhancedModel.fromMap(Map<String, dynamic> map, String id) {
    return ServiceRequestEnhancedModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String? ?? '',
      userPhone: map['userPhone'] as String? ?? '',
      serviceType: map['serviceType'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      scheduledDate: _parseDate(map['scheduledDate']),
      scheduledTime: TimeOfDay(
        hour:   map['scheduledHour']   as int? ?? 9,
        minute: map['scheduledMinute'] as int? ?? 0,
      ),
      priority: ServicePriority.values.firstWhere(
        (e) => e.name == map['priority'] || e.toString() == map['priority'],
        orElse: () => ServicePriority.normal,
      ),
      status: _parseStatus(map['status']),
      userLatitude:  (map['userLatitude']  as num?)?.toDouble() ?? 0.0,
      userLongitude: (map['userLongitude'] as num?)?.toDouble() ?? 0.0,
      userAddress: map['userAddress'] as String? ?? '',
      mediaUrls: List<String>.from(map['mediaUrls'] as List? ?? []),
      bidCount: map['bidCount'] as int? ?? 0,
      biddingDeadlineAt: _parseDateOrNull(map['biddingDeadlineAt']),
      selectedBidId: map['selectedBidId'] as String?,
      budgetMin: (map['budgetMin'] as num?)?.toDouble(),
      budgetMax: (map['budgetMax'] as num?)?.toDouble(),
      workerId:   map['workerId']   as String?,
      workerName: map['workerName'] as String?,
      agreedPrice: (map['agreedPrice'] as num?)?.toDouble(),
      createdAt:    _parseDate(map['createdAt']),
      bidSelectedAt: _parseDateOrNull(map['bidSelectedAt']),
      acceptedAt:    _parseDateOrNull(map['acceptedAt']),
      completedAt:   _parseDateOrNull(map['completedAt']),
      workerNotes: map['workerNotes'] as String?,
      finalPrice:     (map['finalPrice']     as num?)?.toDouble(),
      estimatedPrice: (map['estimatedPrice'] as num?)?.toDouble(),
      estimatedDuration: map['estimatedDuration'] as int?,
      clientRating:  map['clientRating']  as int? ?? map['rating'] as int?,
      reviewComment: map['reviewComment'] as String?,
      cellId:     map['cellId']     as String?,
      wilayaCode: map['wilayaCode'] as int?,
      geoHash:    map['geoHash']    as String?,
      lastCellUpdate: _parseDateOrNull(map['lastCellUpdate']),
    );
  }

  factory ServiceRequestEnhancedModel.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id']) as String? ?? '';
    return ServiceRequestEnhancedModel.fromMap(json, id);
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'serviceType': serviceType,
      'title': title,
      'description': description,
      'scheduledDate':   scheduledDate.toIso8601String(),
      'scheduledHour':   scheduledTime.hour,
      'scheduledMinute': scheduledTime.minute,
      'priority': priority.name,
      'status':   status.name,
      'userLatitude':  userLatitude,
      'userLongitude': userLongitude,
      'userAddress': userAddress,
      'mediaUrls': mediaUrls,
      'bidCount': bidCount,
      'biddingDeadlineAt': biddingDeadlineAt?.toIso8601String(),
      'selectedBidId': selectedBidId,
      'budgetMin': budgetMin,
      'budgetMax': budgetMax,
      'workerId':   workerId,
      'workerName': workerName,
      'agreedPrice': agreedPrice,
      'createdAt':    createdAt.toIso8601String(),
      'bidSelectedAt': bidSelectedAt?.toIso8601String(),
      'acceptedAt':    acceptedAt?.toIso8601String(),
      'completedAt':   completedAt?.toIso8601String(),
      'workerNotes': workerNotes,
      'finalPrice':     finalPrice,
      'estimatedPrice': estimatedPrice,
      'estimatedDuration': estimatedDuration,
      'clientRating': clientRating,
      'reviewComment': reviewComment,
      'cellId':     cellId,
      'wilayaCode': wilayaCode,
      'geoHash':    geoHash,
      'lastCellUpdate': lastCellUpdate?.toIso8601String(),
    };
  }

  bool get hasWorker     => workerId != null && workerId!.isNotEmpty;
  bool get hasBids       => bidCount > 0;
  bool get isRatedByClient => clientRating != null;

  bool get isBiddingOpen {
    if (biddingDeadlineAt == null) return true;
    return DateTime.now().isBefore(biddingDeadlineAt!);
  }

  Duration? get timeUntilDeadline {
    if (biddingDeadlineAt == null) return null;
    final remaining = biddingDeadlineAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String? get displayAmount {
    if (agreedPrice != null)  return agreedPrice!.toStringAsFixed(0);
    if (finalPrice  != null)  return finalPrice!.toStringAsFixed(0);
    if (budgetMin != null && budgetMax != null) {
      return '${budgetMin!.toStringAsFixed(0)}–${budgetMax!.toStringAsFixed(0)}';
    }
    if (estimatedPrice != null) return '~${estimatedPrice!.toStringAsFixed(0)}';
    return null;
  }

  @Deprecated('Use displayAmount and append context.tr("common.currency") in the UI layer')
  String? get displayPrice => displayAmount == null ? null : '$displayAmount DZD';

  ServiceRequestEnhancedModel copyWith({
    String? id, String? userId, String? userName, String? userPhone,
    String? serviceType, String? title, String? description,
    DateTime? scheduledDate, TimeOfDay? scheduledTime,
    ServicePriority? priority, ServiceStatus? status,
    double? userLatitude, double? userLongitude, String? userAddress,
    List<String>? mediaUrls, int? bidCount, DateTime? biddingDeadlineAt,
    String? selectedBidId, double? budgetMin, double? budgetMax,
    String? workerId, String? workerName, double? agreedPrice,
    DateTime? createdAt, DateTime? bidSelectedAt, DateTime? acceptedAt,
    DateTime? completedAt, String? workerNotes, double? finalPrice,
    double? estimatedPrice, int? estimatedDuration, int? clientRating,
    String? reviewComment, String? cellId, int? wilayaCode,
    String? geoHash, DateTime? lastCellUpdate,
  }) {
    return ServiceRequestEnhancedModel(
      id: id ?? this.id, userId: userId ?? this.userId,
      userName: userName ?? this.userName, userPhone: userPhone ?? this.userPhone,
      serviceType: serviceType ?? this.serviceType, title: title ?? this.title,
      description: description ?? this.description,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      priority: priority ?? this.priority, status: status ?? this.status,
      userLatitude: userLatitude ?? this.userLatitude,
      userLongitude: userLongitude ?? this.userLongitude,
      userAddress: userAddress ?? this.userAddress,
      mediaUrls: mediaUrls ?? this.mediaUrls, bidCount: bidCount ?? this.bidCount,
      biddingDeadlineAt: biddingDeadlineAt ?? this.biddingDeadlineAt,
      selectedBidId: selectedBidId ?? this.selectedBidId,
      budgetMin: budgetMin ?? this.budgetMin, budgetMax: budgetMax ?? this.budgetMax,
      workerId: workerId ?? this.workerId, workerName: workerName ?? this.workerName,
      agreedPrice: agreedPrice ?? this.agreedPrice,
      createdAt: createdAt ?? this.createdAt,
      bidSelectedAt: bidSelectedAt ?? this.bidSelectedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      completedAt: completedAt ?? this.completedAt,
      workerNotes: workerNotes ?? this.workerNotes,
      finalPrice: finalPrice ?? this.finalPrice,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      clientRating: clientRating ?? this.clientRating,
      reviewComment: reviewComment ?? this.reviewComment,
      cellId: cellId ?? this.cellId, wilayaCode: wilayaCode ?? this.wilayaCode,
      geoHash: geoHash ?? this.geoHash, lastCellUpdate: lastCellUpdate ?? this.lastCellUpdate,
    );
  }

  @override
  List<Object?> get props => [
        id, userId, userName, userPhone, serviceType, title, description,
        scheduledDate, scheduledTime, priority, status, userLatitude,
        userLongitude, userAddress, mediaUrls, bidCount, biddingDeadlineAt,
        selectedBidId, budgetMin, budgetMax, workerId, workerName, agreedPrice,
        createdAt, bidSelectedAt, acceptedAt, completedAt, workerNotes,
        finalPrice, estimatedPrice, estimatedDuration, clientRating,
        reviewComment, cellId, wilayaCode, geoHash, lastCellUpdate,
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
