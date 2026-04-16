// lib/models/auth_state.dart
//
// State model for the phone authentication flow.
// Handles three stages: phone entry → OTP entry → verification.
//
// Design notes:
// - verificationId lives in state (not a local variable) so it survives
//   hot reload and widget rebuilds without loss.
// - resendCooldown is tracked here so the timer is decoupled from the UI.
// - errorKey holds a localization key, never raw text.

import 'package:equatable/equatable.dart';

// ── Status ────────────────────────────────────────────────────────────────────

enum AuthStatus {
  /// Initial state — no action taken yet.
  idle,

  /// Sending verification SMS to Firebase.
  sendingOtp,

  /// OTP sent — waiting for user to enter the 6-digit code.
  otpSent,

  /// Verifying the credential with Firebase.
  verifying,

  /// Sign-in complete — proceed to navigation.
  success,

  /// Recoverable error — errorKey contains the l10n key.
  error,

  /// Firebase SMS quota exhausted — show specific message.
  quotaExceeded,

  /// Too many requests — show cooldown.
  tooManyRequests,
}

// ── State ─────────────────────────────────────────────────────────────────────

class AuthState extends Equatable {
  /// Current status of the authentication flow.
  final AuthStatus status;

  /// Phone number in E.164 format (+213XXXXXXXXX).
  final String phone;

  /// Firebase verificationId — must persist in state, not a local variable.
  final String? verificationId;

  /// ForceResendingToken from the previous codeSent callback.
  /// Required for resend requests to avoid re-billing the same session.
  final int? resendToken;

  /// True when the backend has confirmed no profile exists for this UID.
  final bool isNewUser;

  /// True when verificationCompleted fired (instant verification on Android).
  final bool isInstantVerified;

  /// Localization key for the current error, resolved via context.tr().
  final String? errorKey;

  /// Seconds remaining before the user can request a new OTP.
  final int resendCooldown;

  const AuthState({
    this.status            = AuthStatus.idle,
    this.phone             = '',
    this.verificationId,
    this.resendToken,
    this.isNewUser         = false,
    this.isInstantVerified = false,
    this.errorKey,
    this.resendCooldown    = 0,
  });

  // ── Computed ────────────────────────────────────────────────────────────────

  bool get isLoading  => status == AuthStatus.sendingOtp || status == AuthStatus.verifying;
  bool get hasError   => status == AuthStatus.error;
  bool get isOtpReady => status == AuthStatus.otpSent && verificationId != null;
  bool get canResend  => resendCooldown == 0 && isOtpReady;

  // ── copyWith ────────────────────────────────────────────────────────────────

  AuthState copyWith({
    AuthStatus? status,
    String?     phone,
    String?     verificationId,
    int?        resendToken,
    bool?       isNewUser,
    bool?       isInstantVerified,
    String?     errorKey,
    int?        resendCooldown,
    bool        clearError    = false,
    bool        clearVerif    = false,
  }) {
    return AuthState(
      status:            status            ?? this.status,
      phone:             phone             ?? this.phone,
      verificationId:    clearVerif ? null : (verificationId ?? this.verificationId),
      resendToken:       resendToken       ?? this.resendToken,
      isNewUser:         isNewUser         ?? this.isNewUser,
      isInstantVerified: isInstantVerified ?? this.isInstantVerified,
      errorKey:          clearError ? null : (errorKey ?? this.errorKey),
      resendCooldown:    resendCooldown    ?? this.resendCooldown,
    );
  }

  @override
  List<Object?> get props => [
    status, phone, verificationId, resendToken,
    isNewUser, isInstantVerified, errorKey, resendCooldown,
  ];

  @override
  String toString() =>
      'AuthState(status: $status, phone: ${_maskPhone(phone)}, '
      'isNewUser: $isNewUser, cooldown: ${resendCooldown}s)';

  static String _maskPhone(String phone) {
    if (phone.length < 4) return '***';
    return '${phone.substring(0, phone.length - 4)}****';
  }
}
