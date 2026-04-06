// lib/utils/snack_utils.dart

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'constants.dart';

/// Themed snackbar utility shared across all auth screens.
///
/// Extracted to eliminate the identical _showSnack() implementation that was
/// duplicated verbatim in LoginScreen, RegisterScreen,
/// EmailVerificationScreen, and ForgotPasswordScreen.
///
/// Usage:
///   showAuthSnackBar(context, context.tr('login.reset_email_sent'));
///   showAuthSnackBar(context, context.tr(errorKey), isError: true);
void showAuthSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  if (!context.mounted) return;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError
          ? (isDark ? AppTheme.darkError : AppTheme.lightError)
          : (isDark ? AppTheme.darkAccent : AppTheme.lightAccent),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
    ),
  );
}
