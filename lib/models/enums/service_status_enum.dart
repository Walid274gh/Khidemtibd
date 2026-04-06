// lib/models/enums/service_status_enum.dart

import 'package:flutter/material.dart';

// ============================================================================
// SERVICE STATUS — HYBRID BID MODEL
// ============================================================================

enum ServiceStatus {
  // ── Hybrid Bid Model ────────────────────────────────────────────────────

  /// Client posted request — visible to workers for bidding
  open,

  /// At least one bid received — client reviewing offers
  awaitingSelection,

  /// Client chose a worker — other bids auto-declined
  bidSelected,

  /// Worker started the job on-site
  inProgress,

  /// Worker marked complete — client may rate
  completed,

  /// Client or admin cancelled before start
  cancelled,

  /// Deadline passed with zero bids, or admin action
  expired,

  // ── Legacy push-model values — kept for backward compatibility ─────────
  // Do NOT use in new code.

  /// @deprecated — use ServiceStatus.open
  pending,

  /// @deprecated — use ServiceStatus.bidSelected
  accepted,

  /// @deprecated — use ServiceStatus.cancelled
  declined,
}

// ============================================================================
// BID STATUS
// ============================================================================

enum BidStatus {
  /// Worker submitted, client has not responded yet
  pending,

  /// Client selected this bid
  accepted,

  /// Client chose another worker
  declined,

  /// Worker withdrew before client decision
  withdrawn,

  /// Bidding deadline passed without selection
  expired,
}

// ============================================================================
// SERVICE PRIORITY
// ============================================================================

enum ServicePriority { low, normal, high, urgent }

// ============================================================================
// EXTENSIONS
// ============================================================================

extension ServiceStatusExtension on ServiceStatus {
  // FIX (README1 L10n P1): hardcoded French strings → localization keys.
  // UI layer: Text(context.tr(status.l10nKey))
  // Keys live under the existing 'requests' map in all 3 locales.

  /// Localization key — pass to context.tr() in the UI layer.
  String get l10nKey {
    switch (this) {
      case ServiceStatus.open:              return 'requests.open';
      case ServiceStatus.awaitingSelection: return 'requests.awaiting_selection';
      case ServiceStatus.bidSelected:       return 'requests.selected';
      case ServiceStatus.inProgress:        return 'requests.in_progress';
      case ServiceStatus.completed:         return 'requests.completed';
      case ServiceStatus.cancelled:         return 'requests.cancelled';
      case ServiceStatus.expired:           return 'requests.expired';
      case ServiceStatus.pending:           return 'requests.pending';
      case ServiceStatus.accepted:          return 'requests.accepted';
      case ServiceStatus.declined:          return 'requests.declined';
    }
  }

  /// @deprecated Use context.tr(status.l10nKey) for proper localization.
  @Deprecated('Use l10nKey with context.tr() for proper localization.')
  String get displayName {
    switch (this) {
      case ServiceStatus.open:              return 'Ouverte';
      case ServiceStatus.awaitingSelection: return 'Offres reçues';
      case ServiceStatus.bidSelected:       return 'Prestataire sélectionné';
      case ServiceStatus.inProgress:        return 'En cours';
      case ServiceStatus.completed:         return 'Terminée';
      case ServiceStatus.cancelled:         return 'Annulée';
      case ServiceStatus.expired:           return 'Expirée';
      case ServiceStatus.pending:           return 'En attente';
      case ServiceStatus.accepted:          return 'Acceptée';
      case ServiceStatus.declined:          return 'Refusée';
    }
  }

  // FIX (README2 QA P1 — two sources of truth): this getter is @Deprecated to
  // force all UI code toward the single authoritative source:
  //   AppTheme.getStatusColor(status, isDark)  ← SINGLE SOURCE OF TRUTH
  //
  // NOTE: cannot import AppTheme here (circular dependency — AppTheme imports
  // this file). Raw Color values are kept ONLY for the migration window.
  @Deprecated(
    'Use AppTheme.getStatusColor(status, isDark) instead. '
    'This getter returns light-mode-only raw colors with no dark mode support '
    'and is inconsistent with the Midnight Indigo design system.',
  )
  Color get color {
    switch (this) {
      case ServiceStatus.open:
      case ServiceStatus.pending:
        return const Color(0xFFFBBF24); // Amber 400
      case ServiceStatus.awaitingSelection:
        return const Color(0xFFF59E0B); // Amber 500
      case ServiceStatus.bidSelected:
      case ServiceStatus.accepted:
        return const Color(0xFF60A5FA); // Blue 400
      case ServiceStatus.inProgress:
        return const Color(0xFFA78BFA); // Violet 400
      case ServiceStatus.completed:
        return const Color(0xFF34D399); // Emerald 400
      case ServiceStatus.cancelled:
      case ServiceStatus.declined:
        return const Color(0xFFF87171); // Red 400
      case ServiceStatus.expired:
        return const Color(0xFF94A3B8); // Slate 400
    }
  }

  bool get isActive =>
      this == ServiceStatus.open ||
      this == ServiceStatus.pending ||
      this == ServiceStatus.awaitingSelection ||
      this == ServiceStatus.bidSelected ||
      this == ServiceStatus.accepted ||
      this == ServiceStatus.inProgress;

  bool get isTerminal =>
      this == ServiceStatus.completed ||
      this == ServiceStatus.cancelled ||
      this == ServiceStatus.declined ||
      this == ServiceStatus.expired;

  bool get canCancel =>
      this == ServiceStatus.open ||
      this == ServiceStatus.pending ||
      this == ServiceStatus.awaitingSelection;
}

extension BidStatusExtension on BidStatus {
  // FIX (README1 L10n P1): hardcoded French strings → localization keys.

  /// Localization key — pass to context.tr() in the UI layer.
  String get l10nKey {
    switch (this) {
      case BidStatus.pending:   return 'bid_status.pending';
      case BidStatus.accepted:  return 'bid_status.accepted';
      case BidStatus.declined:  return 'bid_status.declined';
      case BidStatus.withdrawn: return 'bid_status.withdrawn';
      case BidStatus.expired:   return 'bid_status.expired';
    }
  }

  /// @deprecated Use context.tr(status.l10nKey) for proper localization.
  @Deprecated('Use l10nKey with context.tr() for proper localization.')
  String get displayName {
    switch (this) {
      case BidStatus.pending:   return 'En attente';
      case BidStatus.accepted:  return 'Acceptée';
      case BidStatus.declined:  return 'Refusée';
      case BidStatus.withdrawn: return 'Retirée';
      case BidStatus.expired:   return 'Expirée';
    }
  }
}

extension ServicePriorityExtension on ServicePriority {
  // FIX (README1 L10n P1): hardcoded French strings → localization keys.

  /// Localization key — pass to context.tr() in the UI layer.
  String get l10nKey {
    switch (this) {
      case ServicePriority.low:    return 'priority.low';
      case ServicePriority.normal: return 'priority.normal';
      case ServicePriority.high:   return 'priority.high';
      case ServicePriority.urgent: return 'priority.urgent';
    }
  }

  /// @deprecated Use context.tr(priority.l10nKey) for proper localization.
  @Deprecated('Use l10nKey with context.tr() for proper localization.')
  String get displayName {
    switch (this) {
      case ServicePriority.low:    return 'Basse';
      case ServicePriority.normal: return 'Normale';
      case ServicePriority.high:   return 'Élevée';
      case ServicePriority.urgent: return 'Urgente';
    }
  }

  // Raw fallback color — prefer AppTheme tokens in UI.
  Color get color {
    switch (this) {
      case ServicePriority.low:    return const Color(0xFF059669); // Emerald 600
      case ServicePriority.normal: return const Color(0xFF2563EB); // Blue 600
      case ServicePriority.high:   return const Color(0xFFD97706); // Amber 600
      case ServicePriority.urgent: return const Color(0xFFDC2626); // Red 600
    }
  }
}
