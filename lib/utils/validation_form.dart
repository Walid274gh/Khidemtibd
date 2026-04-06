// lib/utils/validation_form.dart

import 'package:flutter/material.dart';
import 'constants.dart';
import 'localization.dart';

/// Form validation utilities with multi-language support.
///
/// Uses AppLocalizations (context.tr()) for all error messages.
class FormValidators {
  FormValidators._();

  static final RegExp _emailRegex = AppConstants.emailRegex;

  static const int _minPasswordLength = AppConstants.minPasswordLength;
  static const int _maxPasswordLength = AppConstants.maxPasswordLength;
  static const int _minUsernameLength = AppConstants.minUsernameLength;
  static const int _maxUsernameLength = AppConstants.maxUsernameLength;

  // RFC 5321 maximum email address length.
  static const int _maxEmailLength = 254;

  // ─── Email ────────────────────────────────────────────────────────────────

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

  // ─── Password ─────────────────────────────────────────────────────────────

  static String? validatePassword(String? value, BuildContext context) {
    if (value == null || value.isEmpty) {
      return context.tr('errors.required_field');
    }
    if (value.length < _minPasswordLength) {
      return context.tr('errors.password_short');
    }
    // FIX (Auth P0): enforce upper bound to prevent DoS on hash function.
    if (value.length > _maxPasswordLength) {
      return context.tr('errors.password_too_long');
    }
    return null;
  }

  static String? validateConfirmPassword(
    String? value,
    String  originalPassword,
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

  // ─── Username ─────────────────────────────────────────────────────────────

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

  // ─── Phone ────────────────────────────────────────────────────────────────

  static String? validatePhone(String? value, BuildContext context) {
    if (value == null || value.trim().isEmpty) {
      return context.tr('errors.required_field');
    }
    if (value.trim().length < 9) {
      return context.tr('errors.phone_too_short');
    }
    return null;
  }

  // ─── Sanitizers ───────────────────────────────────────────────────────────

  static String sanitizeEmail(String email) => email.trim().toLowerCase();

  static String sanitizeUsername(String username) => username.trim();

  /// Quick structural check — use for real-time UX hints only, not for
  /// final validation (use validateEmail for the authoritative check).
  static bool hasEmailStructure(String email) =>
      email.contains('@') && email.contains('.');
}
