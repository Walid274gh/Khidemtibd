// lib/models/worker_model.dart
//
// STEP 1 MIGRATION: Firestore Timestamp → ISO-8601 DateTime string

import 'package:equatable/equatable.dart';

const _kUndefined = Object();

class WorkerModel extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String profession;
  final bool isOnline;
  final double? latitude;
  final double? longitude;
  final DateTime lastUpdated;

  final String? cellId;
  final int? wilayaCode;
  final String? geoHash;
  final DateTime? lastCellUpdate;

  final String? profileImageUrl;
  final double averageRating;
  final int ratingCount;
  final int jobsCompleted;
  final double responseRate;
  final int daysSinceActive;

  const WorkerModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.profession,
    required this.isOnline,
    this.latitude,
    this.longitude,
    required this.lastUpdated,
    this.cellId,
    this.wilayaCode,
    this.geoHash,
    this.lastCellUpdate,
    this.profileImageUrl,
    this.averageRating = 0.0,
    this.ratingCount = 0,
    this.jobsCompleted = 0,
    this.responseRate = 0.7,
    this.daysSinceActive = 0,
  });

  factory WorkerModel.fromMap(Map<String, dynamic> map, String id) {
    final lastActiveAt = _parseDateOrNull(map['lastActiveAt']);
    final daysSince = lastActiveAt != null
        ? DateTime.now().difference(lastActiveAt).inDays.clamp(0, 9999)
        : 0;

    return WorkerModel(
      id: id,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      profession: map['profession'] as String? ?? '',
      isOnline: map['isOnline'] as bool? ?? false,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      lastUpdated: _parseDate(map['lastUpdated']),
      cellId: map['cellId'] as String?,
      wilayaCode: map['wilayaCode'] as int?,
      geoHash: map['geoHash'] as String?,
      lastCellUpdate: _parseDateOrNull(map['lastCellUpdate']),
      profileImageUrl: map['profileImageUrl'] as String?,
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: map['ratingCount'] as int? ?? 0,
      jobsCompleted: map['jobsCompleted'] as int? ?? map['ratingCount'] as int? ?? 0,
      responseRate: (map['responseRate'] as num?)?.toDouble() ?? 0.7,
      daysSinceActive: daysSince,
    );
  }

  factory WorkerModel.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id']) as String? ?? '';
    return WorkerModel.fromMap(json, id);
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'profession': profession,
      'isOnline': isOnline,
      'latitude': latitude,
      'longitude': longitude,
      'lastUpdated': lastUpdated.toIso8601String(),
      'cellId': cellId,
      'wilayaCode': wilayaCode,
      'geoHash': geoHash,
      'lastCellUpdate': lastCellUpdate?.toIso8601String(),
      'profileImageUrl': profileImageUrl,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
      'jobsCompleted': jobsCompleted,
    };
  }

  WorkerModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    String? profession,
    bool? isOnline,
    Object? latitude = _kUndefined,
    Object? longitude = _kUndefined,
    DateTime? lastUpdated,
    Object? cellId = _kUndefined,
    Object? wilayaCode = _kUndefined,
    Object? geoHash = _kUndefined,
    Object? lastCellUpdate = _kUndefined,
    Object? profileImageUrl = _kUndefined,
    double? averageRating,
    int? ratingCount,
    int? jobsCompleted,
    double? responseRate,
    int? daysSinceActive,
  }) {
    return WorkerModel(
      id:          id          ?? this.id,
      name:        name        ?? this.name,
      email:       email       ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profession:  profession  ?? this.profession,
      isOnline:    isOnline    ?? this.isOnline,
      latitude: identical(latitude, _kUndefined) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _kUndefined) ? this.longitude : longitude as double?,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      cellId: identical(cellId, _kUndefined) ? this.cellId : cellId as String?,
      wilayaCode: identical(wilayaCode, _kUndefined) ? this.wilayaCode : wilayaCode as int?,
      geoHash: identical(geoHash, _kUndefined) ? this.geoHash : geoHash as String?,
      lastCellUpdate: identical(lastCellUpdate, _kUndefined)
          ? this.lastCellUpdate
          : lastCellUpdate as DateTime?,
      profileImageUrl: identical(profileImageUrl, _kUndefined)
          ? this.profileImageUrl
          : profileImageUrl as String?,
      averageRating:  averageRating  ?? this.averageRating,
      ratingCount:    ratingCount    ?? this.ratingCount,
      jobsCompleted:  jobsCompleted  ?? this.jobsCompleted,
      responseRate:   responseRate   ?? this.responseRate,
      daysSinceActive: daysSinceActive ?? this.daysSinceActive,
    );
  }

  @override
  List<Object?> get props => [
        id, name, email, phoneNumber, profession, isOnline,
        latitude, longitude, lastUpdated, cellId, wilayaCode, geoHash,
        lastCellUpdate, profileImageUrl, averageRating, ratingCount,
        jobsCompleted, responseRate, daysSinceActive,
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
