// lib/utils/whatsapp_launcher.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

export '../widgets/whatsapp_button.dart'
    show WhatsAppIcon, whatsAppOutlinedStyle, whatsAppFilledStyle;

// ============================================================================
// CONSTANTS
// ============================================================================

const String kWhatsAppIconAsset = 'assets/images/whatsapp.png';
const Color  kWhatsAppGreen     = Color(0xFF25D366);

// ============================================================================
// PHONE FORMATTER
// ============================================================================

/// Normalises any Algerian phone format to the international wa.me format.
///
///   "0612345678"    → "213612345678"
///   "+213612345678" → "213612345678"
///   "213612345678"  → "213612345678"  (already correct)
///   "612345678"     → "213612345678"  (9-digit, no prefix)
String formatAlgerianPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('213')) return digits;
  if (digits.startsWith('0'))   return '213${digits.substring(1)}';
  return '213$digits';
}

// ============================================================================
// LAUNCHER
// ============================================================================

/// Opens WhatsApp directly (no canLaunchUrl check — avoids the
/// QUERY_ALL_PACKAGES Android restriction that makes canLaunchUrl return
/// false even when WhatsApp is installed).
///
/// Falls back to the web browser if WhatsApp is not installed.
/// Returns `true` on success.
Future<bool> launchWhatsApp({
  required String phone,
  required String message,
}) async {
  if (phone.trim().isEmpty) return false;

  final number  = formatAlgerianPhone(phone);
  final encoded = Uri.encodeComponent(message);

  final uri = Uri.parse('https://wa.me/$number?text=$encoded');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }
}
