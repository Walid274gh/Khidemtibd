// lib/models/notification_model.dart
//
// STEP 1 MIGRATION: Firestore Timestamp → ISO-8601 DateTime string

import 'package:equatable/equatable.dart';

class NotificationModel extends Equatable {
  final String id;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final bool isRead;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map, String id) {
    return NotificationModel(
      id: id,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? '',
      data: Map<String, dynamic>.from(map['data'] as Map? ?? {}),
      createdAt: _parseDate(map['createdAt']),
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id']) as String? ?? '';
    return NotificationModel.fromMap(json, id);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'data': data,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
    };
  }

  NotificationModel copyWith({
    String? id, String? title, String? body, String? type,
    Map<String, dynamic>? data, DateTime? createdAt, bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id, title: title ?? this.title, body: body ?? this.body,
      type: type ?? this.type, data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt, isRead: isRead ?? this.isRead,
    );
  }

  @override
  List<Object?> get props => [id, title, body, type, data, createdAt, isRead];
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
