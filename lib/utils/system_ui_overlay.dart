// lib/utils/system_ui_overlay.dart
//
// EXTRACTED FROM: about_screen.dart, help_screen.dart, settings_screen.dart,
//                 splash_screen.dart, worker_jobs_screen.dart, submit_bid_screen.dart,
//                 job_detail_screen.dart, and every other screen.
// REASON: Identical 14-line AnnotatedRegion<SystemUiOverlayStyle> block was
//         copy-pasted across every screen. Single canonical function with no
//         duplication.
//
// USAGE:
//   AnnotatedRegion<SystemUiOverlayStyle>(
//     value: systemOverlayStyle(isDark),
//     child: Scaffold(...),
//   )

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Returns the standard full-edge-to-edge [SystemUiOverlayStyle] used across
/// all Khidmeti screens.
///
/// Produces transparent status + navigation bars with icon brightness
/// automatically derived from [isDark].
SystemUiOverlayStyle systemOverlayStyle(bool isDark) {
  return SystemUiOverlayStyle(
    statusBarColor:                      Colors.transparent,
    statusBarIconBrightness:             isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness:                 isDark ? Brightness.dark  : Brightness.light,
    systemNavigationBarColor:            Colors.transparent,
    systemNavigationBarDividerColor:     Colors.transparent,
    systemNavigationBarIconBrightness:   isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}
