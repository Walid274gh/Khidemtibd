// lib/models/enums/message_type_enum.dart

import 'package:flutter/material.dart';

// ============================================================================
// MESSAGE TYPE
// ============================================================================

enum MessageType { text, image, video, voice, location, service, system }

enum MessageStatus { sending, sent, delivered, read, failed }

extension MessageTypeExtension on MessageType {
  // FIX (L10n P1): hardcoded French strings replaced with localization keys.
  // UI layer must call context.tr(messageType.l10nKey) instead of
  // messageType.displayName.
  //
  // Keys to add in localization.dart under 'message_type':
  //   text / image / video / voice / location / service / system
  //
  // Example:
  //   fr: { 'message_type': { 'text': 'Texte', 'image': 'Image', ... } }
  //   en: { 'message_type': { 'text': 'Text',  'image': 'Image', ... } }
  //   ar: { 'message_type': { 'text': 'نص',     'image': 'صورة',  ... } }

  /// Localization key — pass to context.tr() in the UI layer.
  String get l10nKey {
    switch (this) {
      case MessageType.text:     return 'message_type.text';
      case MessageType.image:    return 'message_type.image';
      case MessageType.video:    return 'message_type.video';
      case MessageType.voice:    return 'message_type.voice';
      case MessageType.location: return 'message_type.location';
      case MessageType.service:  return 'message_type.service';
      case MessageType.system:   return 'message_type.system';
    }
  }

  /// @deprecated Use context.tr(messageType.l10nKey) in UI code.
  /// Retained for callers that cannot access BuildContext.
  /// Will return French text — not suitable for multilingual display.
  @Deprecated('Use l10nKey with context.tr() for proper localization.')
  String get displayName {
    switch (this) {
      case MessageType.text:     return 'Texte';
      case MessageType.image:    return 'Image';
      case MessageType.video:    return 'Video';
      case MessageType.voice:    return 'Vocal';
      case MessageType.location: return 'Position';
      case MessageType.service:  return 'Service';
      case MessageType.system:   return 'Système';
    }
  }

  IconData get icon {
    switch (this) {
      case MessageType.text:     return Icons.text_fields;
      case MessageType.image:    return Icons.image;
      case MessageType.video:    return Icons.videocam;
      case MessageType.voice:    return Icons.mic;
      case MessageType.location: return Icons.location_on;
      case MessageType.service:  return Icons.build;
      case MessageType.system:   return Icons.info;
    }
  }
}

// ============================================================================
// MEDIA TYPE
// ============================================================================

enum MediaType { image, video, text }

// ============================================================================
// REQUEST SORT
// ============================================================================

enum RequestSortType { nearest, recent, urgent }
