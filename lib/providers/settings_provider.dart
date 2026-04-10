// lib/providers/settings_provider.dart
//
// MOVED FROM: lib/screens/settings/settings_provider.dart
//
// STATE FIX (P2): collapsed isSigningOut: bool + isDeletingAccount: bool into
// SettingsStatus enum variants (signingOut, deletingAccount). Consumers that
// already used state.isSigningOut / state.isDeletingAccount continue to work
// via backward-compat getters on SettingsState.
//
// FIX (Settings Audit P1): SettingsNotifier was calling
// FirebaseAnalytics.instance.logEvent() directly from the state layer.
// Fix: replaced with ref.read(analyticsServiceProvider) calls.
//
// FIX [AUTO] deleteAccount — FCM tokens cleared before Auth deletion.
// FIX [AUTO] deleteAccount — prefs.clear() moved after confirmed deletion so
//   re-authentication (requires-recent-login) leaves prefs intact and the
//   account remains accessible.
// FIX [AUTO] deleteAccount — prefs.clear() replaced with targeted key removal
//   so unrelated local preferences (theme, locale, etc.) survive.
//
// FIX [L1] signOut — prefs.remove(PrefKeys.accountRole) moved AFTER
//   authService.signOut() succeeds. Previously it was called BEFORE signOut,
//   meaning that if signOut threw an exception the role pref was already wiped
//   — leaving the user in a broken state where the app thought they were a
//   client even though they were still authenticated as a worker.
//
// FIX (MIGRATION — collection unifiée) :
//   _loadProfileData() faisait jusqu'à 3 appels HTTP :
//     1. getWorker(uid) si rôle en cache
//     2. getWorker(uid) si rôle non-caché
//     3. getUser(uid)   si getWorker == null
//   Remplacé par 1 seul appel getUser(uid) — le champ `role` du document
//   unifié discrimine worker vs client. Les champs worker (profession,
//   averageRating, ratingCount…) sont portés par le même document UserModel.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_providers.dart';
import 'core_providers.dart';
import 'user_role_provider.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

// ============================================================================
// SETTINGS STATE
// ============================================================================

// FIX (P2): extended with signingOut + deletingAccount to replace the separate
// boolean fields. SettingsStatus.loading is now reserved for profile load only.
enum SettingsStatus { idle, loading, signingOut, deletingAccount, error }

class SettingsState {
  final SettingsStatus status;
  final String? userName;
  final String? professionLabel;
  final String? profileImageUrl;
  final UserRole activeRole;
  final bool isWorkerAccount;

  final double? workerAverageRating;
  final int?    workerRatingCount;

  final String? errorMessage;

  const SettingsState({
    this.status              = SettingsStatus.loading,
    this.userName,
    this.professionLabel,
    this.profileImageUrl,
    this.activeRole          = UserRole.client,
    this.isWorkerAccount     = false,
    this.workerAverageRating,
    this.workerRatingCount,
    this.errorMessage,
  });

  // ── Backward-compat getters — settings_screen / settings_content unchanged ─

  /// True while a sign-out operation is in progress.
  bool get isSigningOut => status == SettingsStatus.signingOut;

  /// True while an account-deletion operation is in progress.
  bool get isDeletingAccount => status == SettingsStatus.deletingAccount;

  // ─────────────────────────────────────────────────────────────────────────

  SettingsState copyWith({
    SettingsStatus? status,
    String?  userName,
    String?  professionLabel,
    String?  profileImageUrl,
    UserRole? activeRole,
    bool?    isWorkerAccount,
    double?  workerAverageRating,
    int?     workerRatingCount,
    String?  errorMessage,
  }) {
    return SettingsState(
      status:              status              ?? this.status,
      userName:            userName            ?? this.userName,
      professionLabel:     professionLabel     ?? this.professionLabel,
      profileImageUrl:     profileImageUrl     ?? this.profileImageUrl,
      activeRole:          activeRole          ?? this.activeRole,
      isWorkerAccount:     isWorkerAccount     ?? this.isWorkerAccount,
      workerAverageRating: workerAverageRating ?? this.workerAverageRating,
      workerRatingCount:   workerRatingCount   ?? this.workerRatingCount,
      errorMessage:        errorMessage,
    );
  }
}

// ============================================================================
// SETTINGS NOTIFIER
// ============================================================================

class SettingsNotifier extends StateNotifier<SettingsState> {
  final Ref _ref;

  SettingsNotifier(this._ref) : super(const SettingsState()) {
    _loadProfileData();
  }

  /// FIX (MIGRATION — collection unifiée) :
  ///
  /// AVANT — jusqu'à 3 appels HTTP :
  ///   • Branche "rôle caché worker" : getWorker(uid)
  ///   • Branche "slow path"         : getWorker(uid)  puis  getUser(uid)
  ///
  /// APRÈS — 1 seul appel HTTP :
  ///   • getUser(uid) retourne le document unifié avec le champ `role`.
  ///   • userDoc.isWorker == true  → branche worker (profession, rating…)
  ///   • userDoc.isWorker == false → branche client
  ///   • null                      → fallback Firebase displayName
  ///
  /// Les champs worker (profession, averageRating, ratingCount, profileImageUrl)
  /// sont maintenant portés par UserModel — aucun second appel nécessaire.
  Future<void> _loadProfileData() async {
    try {
      final authService      = _ref.read(authServiceProvider);
      final firestoreService = _ref.read(firestoreServiceProvider);
      final uid              = authService.user?.uid;

      if (uid == null) {
        state = state.copyWith(
          status:       SettingsStatus.error,
          errorMessage: 'errors.no_user',
        );
        return;
      }

      // Une seule requête — le document unifié porte le rôle et tous les champs.
      final userDoc = await firestoreService.getUser(uid);

      if (!mounted) return;

      if (userDoc == null) {
        // Profil pas encore créé (edge case : première connexion, latence réseau).
        // Fallback sur les données Firebase Auth.
        final firebaseUser = authService.user;
        state = state.copyWith(
          status:          SettingsStatus.idle,
          userName:        firebaseUser?.displayName ?? '',
          activeRole:      UserRole.client,
          isWorkerAccount: false,
        );
        AppLogger.warning('Settings: userDoc null for uid=$uid — fallback to Firebase');
        return;
      }

      if (userDoc.isWorker) {
        // Mettre à jour le cache SharedPreferences pour cohérence.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(PrefKeys.accountRole, UserType.worker);

        if (!mounted) return;
        state = state.copyWith(
          status:              SettingsStatus.idle,
          userName:            userDoc.name,
          professionLabel:     userDoc.profession,       // String? — correct
          profileImageUrl:     userDoc.profileImageUrl,
          activeRole:          UserRole.worker,
          isWorkerAccount:     true,
          workerAverageRating: userDoc.averageRating,
          workerRatingCount:   userDoc.ratingCount,
        );
        AppLogger.info('Settings loaded: worker uid=$uid');
      } else {
        if (!mounted) return;
        state = state.copyWith(
          status:          SettingsStatus.idle,
          userName:        userDoc.name,
          profileImageUrl: userDoc.profileImageUrl,
          activeRole:      UserRole.client,
          isWorkerAccount: false,
        );
        AppLogger.info('Settings loaded: client uid=$uid');
      }
    } catch (e, st) {
      AppLogger.error('SettingsNotifier._loadProfileData', e, st);
      if (mounted) {
        state = state.copyWith(
          status:       SettingsStatus.error,
          errorMessage: 'errors.load_failed',
        );
      }
    }
  }

  /// Signs the user out with a clean teardown sequence.
  ///
  /// FIX (P2): status: SettingsStatus.signingOut replaces isSigningOut: true.
  /// FIX: isSigningOut guard prevents double-tap race condition.
  /// FIX: FCM token cleared from Firestore before sign-out.
  /// FIX (Settings Audit P1): replaced FirebaseAnalytics.instance.logEvent()
  ///   with ref.read(analyticsServiceProvider).logUserSignedOut().
  /// FIX [L1]: prefs.remove(PrefKeys.accountRole) moved AFTER
  ///   authService.signOut() succeeds.
  Future<void> signOut() async {
    if (!mounted) return;
    if (state.isSigningOut) return;

    state = state.copyWith(status: SettingsStatus.signingOut);

    final cachedRoleNotifier = _ref.read(cachedUserRoleProvider.notifier);
    final authService        = _ref.read(authServiceProvider);
    final firestoreService   = _ref.read(firestoreServiceProvider);
    final uid                = authService.user?.uid;

    _ref.read(analyticsServiceProvider).logUserSignedOut(
      accountType: state.isWorkerAccount ? 'worker' : 'client',
    );

    try {
      cachedRoleNotifier.state = UserRole.unknown;

      if (uid != null) {
        try {
          await firestoreService.updateUserFcmToken(uid, '');
          if (state.isWorkerAccount) {
            await firestoreService.updateWorkerFcmToken(uid, '');
          }
          AppLogger.info('FCM token cleared for uid: $uid');
        } catch (fcmError) {
          AppLogger.warning('FCM cleanup failed: $fcmError');
        }
      }

      await authService.signOut();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(PrefKeys.accountRole);
      } catch (prefsError) {
        AppLogger.warning('signOut: prefs.remove failed — $prefsError');
      }

    } catch (e) {
      AppLogger.error('SettingsNotifier.signOut', e);

      if (mounted) {
        cachedRoleNotifier.state = state.isWorkerAccount
            ? UserRole.worker
            : UserRole.client;
        state = state.copyWith(
          status:       SettingsStatus.error,
          errorMessage: 'errors.signout_failed',
        );
      }
    }
  }

  /// Permanently deletes the Firebase Auth account and wipes local state.
  Future<String?> deleteAccount() async {
    if (!mounted) return null;
    if (state.isDeletingAccount) return null;

    state = state.copyWith(status: SettingsStatus.deletingAccount);

    final cachedRoleNotifier = _ref.read(cachedUserRoleProvider.notifier);
    final authService        = _ref.read(authServiceProvider);
    final firestoreService   = _ref.read(firestoreServiceProvider);
    final uid                = authService.user?.uid;

    _ref.read(analyticsServiceProvider).logUserDeletedAccount(
      accountType: state.isWorkerAccount ? 'worker' : 'client',
    );

    try {
      cachedRoleNotifier.state = UserRole.unknown;

      if (uid != null) {
        try {
          await firestoreService.updateUserFcmToken(uid, '');
          if (state.isWorkerAccount) {
            await firestoreService.updateWorkerFcmToken(uid, '');
          }
          AppLogger.info(
              'SettingsNotifier.deleteAccount: FCM tokens cleared uid=$uid');
        } catch (fcmError) {
          AppLogger.warning(
              'SettingsNotifier.deleteAccount: FCM cleanup failed — $fcmError');
        }
      }

      final errorKey = await authService.deleteAccount();
      if (errorKey != null) {
        if (mounted) {
          cachedRoleNotifier.state = state.isWorkerAccount
              ? UserRole.worker
              : UserRole.client;
          state = state.copyWith(
            status:       SettingsStatus.error,
            errorMessage: errorKey,
          );
        }
        return errorKey;
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(PrefKeys.accountRole);
        AppLogger.info('SettingsNotifier.deleteAccount: local auth prefs cleared');
      } catch (prefsError) {
        AppLogger.warning(
            'SettingsNotifier.deleteAccount: prefs cleanup failed — $prefsError');
      }

      return null;

    } catch (e) {
      AppLogger.error('SettingsNotifier.deleteAccount', e);

      if (mounted) {
        cachedRoleNotifier.state = state.isWorkerAccount
            ? UserRole.worker
            : UserRole.client;
        state = state.copyWith(
          status:       SettingsStatus.error,
          errorMessage: 'errors.delete_account_failed',
        );
      }
      return 'errors.delete_account_failed';
    }
  }

  Future<void> retry() async {
    if (mounted) state = const SettingsState();
    await _loadProfileData();
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final settingsProvider =
    StateNotifierProvider.autoDispose<SettingsNotifier, SettingsState>(
        (ref) => SettingsNotifier(ref));
