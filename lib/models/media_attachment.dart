// lib/models/media_attachment.dart
//
// STEP 1 MIGRATION: Firestore Timestamp → ISO-8601 DateTime string

import 'package:equatable/equatable.dart';
import 'message_enums.dart';

class MediaAttachment extends Equatable {
  final String id;
  final String url;
  final String localPath;
  final MediaType type;
  final DateTime uploadedAt;
  final int? fileSize;

  const MediaAttachment({
    required this.id,
    required this.url,
    required this.localPath,
    required this.type,
    required this.uploadedAt,
    this.fileSize,
  });

  factory MediaAttachment.fromMap(Map<String, dynamic> map) {
    return MediaAttachment(
      id: map['id'] as String? ?? '',
      url: map['url'] as String? ?? '',
      localPath: map['localPath'] as String? ?? '',
      type: MediaType.values.firstWhere(
        (e) => e.name == map['type'] || e.toString() == map['type'],
        orElse: () => MediaType.image,
      ),
      uploadedAt: _parseDate(map['uploadedAt']),
      fileSize: map['fileSize'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'localPath': localPath,
      'type': type.name,
      'uploadedAt': uploadedAt.toIso8601String(),
      'fileSize': fileSize,
    };
  }

  MediaAttachment copyWith({
    String? id, String? url, String? localPath,
    MediaType? type, DateTime? uploadedAt, int? fileSize,
  }) {
    return MediaAttachment(
      id: id ?? this.id, url: url ?? this.url, localPath: localPath ?? this.localPath,
      type: type ?? this.type, uploadedAt: uploadedAt ?? this.uploadedAt,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  @override
  List<Object?> get props => [id, url, localPath, type, uploadedAt, fileSize];
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
