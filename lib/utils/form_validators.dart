// lib/utils/form_validators.dart
//
// CANONICAL FORM VALIDATION — Khidmeti
//
// Two tiers of methods:
//   • Context-free  — pure Dart, usable from any layer (controllers, services).
//   • Context-aware — require BuildContext for localized error strings (UI only).
//
// Import this file everywhere. validation_form.dart re-exports it for backward compat.

import 'package:flutter/material.dart';

import 'constants.dart';
import 'localization.dart';

class FormValidators {
  FormValidators._();

  // ── Private constants ──────────────────────────────────────────────────────
  static final RegExp _emailRegex = AppConstants.emailRegex;

  static const int _minPasswordLength = AppConstants.minPasswordLength;
  static const int _maxPasswordLength = AppConstants.maxPasswordLength;
  static const int _minUsernameLength = AppConstants.minUsernameLength;
  static const int _maxUsernameLength = AppConstants.maxUsernameLength;
  static const int _maxEmailLength    = AppConstants.maxEmailLength;

  /// Compiled once — +213[5-7]XXXXXXXX (12 digits after +).
  static final RegExp _e164Algeria = RegExp(r'^\+213[5-7]\d{8}$');

  // ═══════════════════════════════════════════════════════════════════════════
  // PHONE — Context-free (AuthController calls these without BuildContext)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converts any Algerian phone notation to E.164 (+213XXXXXXXXX).
  ///
  /// Accepted input formats:
  ///   • +213[5-7]XXXXXXXX  — already E.164, returned as-is
  ///   •  213[5-7]XXXXXXXX  — + prepended
  ///   •   0[5-7]XXXXXXXX   — local format (10 digits)
  ///   •    [5-7]XXXXXXXX   — 9 digits, missing leading zero
  ///
  /// Strips spaces, hyphens, dots, and parentheses before parsing.
  /// Falls back to a best-effort "+cleaned" for unrecognised input.
  static String toE164Algeria(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

    // Already valid E.164
    if (_e164Algeria.hasMatch(cleaned)) return cleaned;

    // Country code without +  → +213XXXXXXXXX (12 chars)
    if (cleaned.startsWith('213') && cleaned.length == 12) {
      return '+$cleaned';
    }

    // Local format: 0[5-7]XXXXXXXX (10 digits)
    if (cleaned.startsWith('0') &&
        cleaned.length == 10 &&
        RegExp(r'^0[5-7]').hasMatch(cleaned)) {
      return '+213${cleaned.substring(1)}';
    }

    // Without leading zero: [5-7]XXXXXXXX (9 digits)
    if (cleaned.length == 9 && RegExp(r'^[5-7]').hasMatch(cleaned)) {
      return '+213$cleaned';
    }

    // Best effort — preserve + if already there
    return cleaned.startsWith('+') ? cleaned : '+$cleaned';
  }

  /// Returns `true` if [phone] is a valid Algerian E.164 number.
  ///
  /// Valid range: +213[5-7]XXXXXXXX (Djezzy 06, Mobilis 07, Ooredoo 05).
  static bool isValidE164(String phone) => _e164Algeria.hasMatch(phone);

  // ═══════════════════════════════════════════════════════════════════════════
  // EMAIL — Context-aware
  // ═══════════════════════════════════════════════════════════════════════════

  static String? validateEmail(String? value, BuildContext context) {
    if (value == null || value.trim().isEmpty) {
      return context.tr('errors.required_field');
    }
    final trimmed = value.trim();
    if (trimmed.length > _maxEmailLength) {
      return context.tr('errors.email_too_long');
    }
    if (!_emailRegex.hasMatch(trimmed)) {
      return context.tr('errors.email_invalid');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PASSWORD — Context-aware
  // ═══════════════════════════════════════════════════════════════════════════

  static String? validatePassword(String? value, BuildContext context) {
    if (value == null || value.isEmpty) {
      return context.tr('errors.required_field');
    }
    if (value.length < _minPasswordLength) {
      return context.tr('errors.password_short');
    }
    // Enforce upper bound — prevents DoS on hash function.
    if (value.length > _maxPasswordLength) {
      return context.tr('errors.password_too_long');
    }
    return null;
  }

  static String? validateConfirmPassword(
    String?      value,
    String       originalPassword,
    BuildContext context,
  ) {
    if (value == null || value.isEmpty) {
      return context.tr('errors.required_field');
    }
    if (value != originalPassword) {
      return context.tr('errors.passwords_mismatch');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // USERNAME / DISPLAY NAME — Context-aware
  // ═══════════════════════════════════════════════════════════════════════════

  static String? validateUsername(String? value, BuildContext context) {
    if (value == null || value.trim().isEmpty) {
      return context.tr('errors.required_field');
    }
    final trimmed = value.trim();
    if (trimmed.length < _minUsernameLength) {
      return context.tr('errors.username_too_short');
    }
    if (trimmed.length > _maxUsernameLength) {
      return context.tr('errors.username_too_long');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHONE — Context-aware (UI form validation)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validates a raw phone input and shows a localised error if invalid.
  ///
  /// Internally converts to E.164 before checking — so local format "0661234567"
  /// is accepted just like "+213661234567".
  static String? validatePhone(String? value, BuildContext context) {
    if (value == null || value.trim().isEmpty) {
      return context.tr('errors.required_field');
    }
    final e164 = toE164Algeria(value.trim());
    if (!isValidE164(e164)) {
      return context.tr('errors.phone_invalid_format');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SANITIZERS — Context-free
  // ═══════════════════════════════════════════════════════════════════════════

  static String sanitizeEmail(String email)      => email.trim().toLowerCase();
  static String sanitizeUsername(String username) => username.trim();

  /// Lightweight check for real-time UX hints. NOT a substitute for
  /// [validateEmail] in final form submission.
  static bool hasEmailStructure(String email) =>
      email.contains('@') && email.contains('.');
}
