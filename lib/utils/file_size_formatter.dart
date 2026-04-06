// lib/utils/file_size_formatter.dart
//
// EXTRACTED FROM: audio_service.dart and media_service.dart
// REASON: Both services defined an identical _formatBytes(int) private method.
//         Pure utility function — no Flutter imports needed.

/// Formats a byte count into a human-readable string.
///
/// Examples:
///   512      → '512 B'
///   1500     → '1.5 KB'
///   2097152  → '2.0 MB'
class FileSizeFormatter {
  FileSizeFormatter._();

  static String format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
