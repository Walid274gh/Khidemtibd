// lib/models/user_model.dart
//
// STEP 1 MIGRATION: Firestore Timestamp → ISO-8601 DateTime string
// fromMap() now parses JSON from the NestJS REST API (no cloud_firestore dep).

import 'package:equatable/equatable.dart';

const _kUndefined = Object();

class UserModel extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final double? latitude;
  final double? longitude;
  final DateTime lastUpdated;
  final String? profileImageUrl;

  final String? cellId;
  final int? wilayaCode;
  final String? geoHash;
  final String? fcmToken;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.latitude,
    this.longitude,
    required this.lastUpdated,
    this.profileImageUrl,
    this.cellId,
    this.wilayaCode,
    this.geoHash,
    this.fcmToken,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      lastUpdated: _parseDate(map['lastUpdated']),
      profileImageUrl: map['profileImageUrl'] as String?,
      cellId: map['cellId'] as String?,
      wilayaCode: map['wilayaCode'] as int?,
      geoHash: map['geoHash'] as String?,
      fcmToken: map['fcmToken'] as String?,
    );
  }

  // Also accepts NestJS response where id is under '_id'
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id']) as String? ?? '';
    return UserModel.fromMap(json, id);
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'latitude': latitude,
      'longitude': longitude,
      'lastUpdated': lastUpdated.toIso8601String(),
      'profileImageUrl': profileImageUrl,
      'cellId': cellId,
      'wilayaCode': wilayaCode,
      'geoHash': geoHash,
      'fcmToken': fcmToken,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    Object? latitude         = _kUndefined,
    Object? longitude        = _kUndefined,
    DateTime? lastUpdated,
    Object? profileImageUrl  = _kUndefined,
    Object? cellId           = _kUndefined,
    Object? wilayaCode       = _kUndefined,
    Object? geoHash          = _kUndefined,
    Object? fcmToken         = _kUndefined,
  }) {
    return UserModel(
      id:          id          ?? this.id,
      name:        name        ?? this.name,
      email:       email       ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      latitude: identical(latitude, _kUndefined) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _kUndefined) ? this.longitude : longitude as double?,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      profileImageUrl: identical(profileImageUrl, _kUndefined)
          ? this.profileImageUrl
          : profileImageUrl as String?,
      cellId: identical(cellId, _kUndefined) ? this.cellId : cellId as String?,
      wilayaCode: identical(wilayaCode, _kUndefined) ? this.wilayaCode : wilayaCode as int?,
      geoHash: identical(geoHash, _kUndefined) ? this.geoHash : geoHash as String?,
      fcmToken: identical(fcmToken, _kUndefined) ? this.fcmToken : fcmToken as String?,
    );
  }

  @override
  List<Object?> get props => [
        id, name, email, phoneNumber, latitude, longitude,
        lastUpdated, profileImageUrl, cellId, wilayaCode, geoHash, fcmToken,
      ];
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  // Legacy Firestore Timestamp shape {_seconds, _nanoseconds} — safe fallback
  if (value is Map) {
    final seconds = value['_seconds'] as int?;
    if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return DateTime.now();
}
