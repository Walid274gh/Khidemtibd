// lib/utils/error_handler.dart

import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'logger.dart';

/// Error handler with logging and themed UI.
///
/// All snackbar backgrounds are theme-aware — no hardcoded palette tokens.
class ErrorHandler {
  ErrorHandler._();

  static void showErrorSnackBar(
    BuildContext context,
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    AppLogger.error(message, error, stackTrace);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color:      Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? AppTheme.darkError : AppTheme.lightError,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin:   const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    AppLogger.success(message);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color:      Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin:   const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void showWarningSnackBar(BuildContext context, String message) {
    AppLogger.warning(message);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color:      Colors.white,
                ),
              ),
            ),
          ],
        ),
        // FIX (Designer): was using accent (Indigo) — identical to Info
        // snackbar, destroying semantic differentiation. Warning now uses the
        // correct Amber token so users can distinguish caution from information.
        backgroundColor: isDark ? AppTheme.darkWarning : AppTheme.lightWarning,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin:   const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void showInfoSnackBar(BuildContext context, String message) {
    AppLogger.info(message);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color:      Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? AppTheme.darkAccent : AppTheme.lightAccent,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin:   const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
