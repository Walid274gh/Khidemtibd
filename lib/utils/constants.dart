// lib/utils/constants.dart
//
// CHANGES (Cleanliness §7 — Dead Code):
//   • 7 dead AppRoutes constants removed:
//       messages, workerMessages, chat, mediaViewer, becomeWorker,
//       serviceRequestDetails, workerHome
//     (none of these are registered in app_router.dart)
//   • AppIcons.info2 removed — duplicate of AppIcons.info, both mapped to
//     Icons.info_outline_rounded. Dead code.
//
// CHANGES (UI Manual Pass):
//   • toggleTrackW / toggleTrackH / toggleThumbSize added — back the
//     HomeWorkerSection _ToggleSwitch raw literals (40×20 track, 16dp thumb).
//   • statusDotSize added — backs the 8dp status indicator dot in
//     _AvailabilityToggle.
//   • locationDotSize added — backs the PulsingLocationDot core diameter,
//     promoted from off-grid 14dp to the nearest on-grid value 16dp.
//
// CHANGES (UI-APPLY pass — manual items):
//   • splashLogoSize (248.0) added.
//   • splashStatusAreaHeight (64.0) added.
//   • iconSizeHero (80.0) added.
//   • splashErrorCircleSize (200.0) added.
//
// CHANGES (ui-apply W9 / W10):
//   • cardRadius = 20.0 REMOVED — duplicate of radiusCard (20.0).
//   • sectionMT: 22.0 → 24.0 (snapped to 8dp grid).
//   • navPillPaddingV: 7.0 → 8.0 (snapped to 4dp grid).
//   • chipPaddingV: 5.0 → 4.0 (snapped to 4dp grid).
//   • locationDotMarker: 38.0 → 40.0 (snapped to 8dp grid).
//
// CHANGES (ui-apply AUTO W3 / MANUAL):
//   • splashRetryButtonMinWidth (120.0) added.
//   • AppAssets.splashStatic added.
//
// CHANGES (settings ui-apply):
//   [C12] iconSizeLg2 = 64.0 — mid-scale icon between iconSizeXl (48) and
//         iconSizeHero (80); used for in-content error state icons.
//   [W5]  emojiIconSize = 22.0 — flag/icon size in SheetOption rows.
//   [W6]  tileHeight = 64.0 — canonical height for SettingsTile,
//         SignOutTile, and _DeleteAccountTile rows.
//   [W8]  settingsRetryButtonWidth = 180.0 — replaces the arithmetic
//         splashRetryButtonMinWidth * 1.5 in SettingsErrorView.
//   [W2/W3] Opacity tokens for state-conditional destructive tiles.
//         These are runtime .withValues() calls — they cannot be const-baked
//         because the base color is caller-resolved (signOutRed, error scheme).
//         Named constants replace magic literals and document each level's intent.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class AppConstants {
  AppConstants._();

  static const String appName    = 'Khidmeti';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'خدمات منزلية احترافية';
  static const String baseUrl    = 'https://api.khidmeti.com';

  static const int defaultPageSize = 20;
  static const int maxPageSize     = 100;

  static const double fabClearance = 80.0;
  static const double maxBidPrice  = 500000.0;

  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration longTimeout    = Duration(minutes: 2);
  static const Duration cacheExpiry    = Duration(hours: 1);

  static const int biddingDeadlineMinutes  = 120;
  static const int maxPendingBidsPerWorker = 5;

  // Spacing
  static const double spacingXxs  = 2.0;
  static const double spacingXs   = 4.0;
  static const double spacingSm   = 8.0;
  static const double spacingMd   = 16.0;
  static const double spacingLg   = 24.0;
  static const double spacingXl   = 32.0;
  static const double spacingMdLg = 20.0;

  // [UI-FIX] 12dp gap token — used in HomeServiceGrid chip separators.
  // Sits between spacingSm (8) and spacingMd (16); deliberate design gap.
  static const double spacingChipGap = 12.0;

  // Padding
  static const double paddingXs = 4.0;
  static const double paddingSm = 8.0;
  static const double paddingMd = 16.0;
  static const double paddingLg = 24.0;
  static const double paddingXl = 32.0;

  // Radius
  static const double radiusXs     = 4.0;
  static const double radiusSm     = 8.0;
  static const double radiusMd     = 12.0;
  static const double radiusLg     = 16.0;
  static const double radiusXl     = 20.0;
  static const double radiusXxl    = 24.0;
  static const double radiusCircle = 28.0;
  static const double radiusCard   = 20.0;
  static const double radiusTile   = 18.0;

  // Buttons
  static const double buttonHeight   = 54.0;
  static const double buttonHeightMd = 48.0;
  static const double buttonHeightSm = 44.0;

  // Cards
  static const double cardPadding     = 18.0;
  static const double cardBorderWidth = 0.5;
  static const double accentBarWidth  = 3.0;

  // [MANUAL FIX]: gap between a circular icon and its label in grid chips.
  static const double cardIconLabelGap = 8.0;

  // Inputs
  static const double inputRadius   = 14.0;
  static const double inputPaddingH = 18.0;
  static const double inputPaddingV = 15.0;

  // Navigation bar
  static const double navBarRadius    = 24.0;
  static const double navBarHeight    = 68.0;
  static const double navBarMarginH   = 16.0;
  static const double navBarMarginB   = 10.0;
  static const double navPillPaddingH = 14.0;
  static const double navPillPaddingV = 8.0;
  static const double navDotSize      = 4.0;

  // Hero
  static const double heroPaddingTop    = 38.0;
  static const double heroPaddingH      = 24.0;
  static const double heroPaddingBottom = 30.0;

  // Sections
  static const double sectionLabelMB = 12.0;
  static const double sectionMT      = 24.0;
  static const double sectionCardGap = 10.0;

  // Badges / chips / tile gaps
  static const double spacingTileInner = 14.0;
  static const double badgePaddingH    = 10.0;
  static const double badgePaddingV    = 3.0;
  static const double chipRadius       = 8.0;
  static const double chipPaddingH     = 10.0;
  static const double chipPaddingV     = 4.0;

  // Wordmark
  static const double wordmarkDotSize  = 8.0;
  static const double wordmarkDotBlur  = 10.0;
  static const double wordmarkFontSize = 13.0;

  // Font sizes
  static const double heroFontSize    = 32.0;
  static const double fontSizeTileLg  = 15.0;
  static const double fontSizeXxs     = 11.0;
  static const double fontSizeXs      = 10.0;
  static const double fontSizeSm      = 12.0;
  static const double fontSizeCaption = 13.0;
  static const double fontSizeMd      = 14.0;
  static const double fontSizeLg      = 16.0;
  static const double fontSizeXl      = 18.0;
  static const double fontSizeXxl     = 20.0;
  static const double fontSizeDisplay = 24.0;

  // Icons
  static const double iconSizeXs = 16.0;
  static const double iconSizeSm = 20.0;
  static const double iconSizeMd = 24.0;
  static const double iconSizeLg = 32.0;
  static const double iconSizeXl = 48.0;

  /// Mid-scale icon token between iconSizeXl (48) and iconSizeHero (80).
  /// [C12]: used for in-content error state icons (e.g. SettingsErrorView).
  /// 64dp is appropriate for content-area illustrations — larger than a
  /// standard action icon but smaller than full-screen hero art.
  static const double iconSizeLg2 = 64.0;

  /// Hero-scale icon used in full-screen state illustrations (e.g. SplashErrorIcon).
  /// Intentionally outside the standard icon scale — it is a decorative display
  /// element, not a UI control icon.
  static const double iconSizeHero = 80.0;

  // Container sizes
  static const double iconContainerSm  = 28.0;
  static const double iconContainerMd  = 32.0;
  static const double iconContainerLg  = 36.0;
  static const double iconContainerXl  = 40.0;
  static const double buttonIconSize   = 20.0;

  /// Emoji / flag icon size used in SheetOption rows.
  /// [W5]: promotes the raw 22dp literal from sheet_option.dart to a
  /// named token. Applied to Text(flag, fontSize) and Icon(icon, size).
  static const double emojiIconSize = 22.0;

  static const double filterChipHeight   = 36.0;
  static const double filterChipPaddingV = 8.0;
  static const double locationDotMarker  = 40.0;
  static const int    maxEmailLength     = 254;

  // Sheet handle
  static const double sheetHandleWidth  = 40.0;
  static const double sheetHandleHeight = 4.0;

  // Search / input
  static const double searchBarHeight      = 44.0;
  static const double categoryTileIconSize = 48.0;

  // ── Settings tile height ─────────────────────────────────────────────────
  /// Canonical row height for SettingsTile, SignOutTile, _DeleteAccountTile.
  /// [W6]: promotes the magic literal 64 (repeated 3×) to a named token.
  /// Note: 64dp sits between the M3 one-line (56dp) and two-line (72dp)
  /// standard heights — this is an explicit product design decision.
  static const double tileHeight = 64.0;

  // ── Settings error view ──────────────────────────────────────────────────
  /// Width of the retry button in SettingsErrorView.
  /// [W8]: replaces the arithmetic `splashRetryButtonMinWidth * 1.5`
  /// (120.0 × 1.5 = 180.0) with a named token — arithmetic in layout
  /// code is a code smell.
  static const double settingsRetryButtonWidth = 180.0;

  // ── Toggle switch ─────────────────────────────────────────────────────────
  static const double toggleTrackW    = 40.0;
  static const double toggleTrackH    = 20.0;
  static const double toggleThumbSize = 16.0;
  static const double statusDotSize   =  8.0;

  // ── Map / location ────────────────────────────────────────────────────────
  static const double locationDotSize = 16.0;

  // ── Splash screen ─────────────────────────────────────────────────────────
  static const double splashLogoSize            = 248.0;
  static const double splashStatusAreaHeight    = 64.0;
  static const double splashErrorCircleSize     = 200.0;
  static const double splashRetryButtonMinWidth = 120.0;

  // ── Opacity tokens — state-conditional destructive tiles ─────────────────
  // Applied at runtime via .withValues(alpha: x) to caller-resolved colors
  // (AppTheme.signOutRed, colorScheme.error, iconColor). Cannot be baked as
  // const Colors because the base color is dynamic. Named constants replace
  // magic literals and make each opacity level's intent explicit.
  //
  // Usage map:
  //   opacityDisabledColor    → disabled text/icon dimming (sign-out, delete)
  //   opacityChevron          → chevron / muted icon alpha (both tiles)
  //   opacityTileFillDisabled → sign-out tile bg, disabled state
  //   opacityTileFillDarkEn   → sign-out tile bg, dark theme, enabled
  //   opacityTileFillLightEn  → sign-out tile bg, light theme, enabled
  //                             ↳ also: delete tile bg, dark theme, enabled
  //   opacityDeleteFillLightEn→ delete tile bg, light theme, enabled
  //   opacityDeleteFillDis    → delete tile bg, disabled state
  //   opacityIconBg           → delete tile icon container background
  //   opacityIconBgAlt        → sign-out tile icon container background
  //                             ↳ also: delete tile border, enabled state
  //   opacityBorderEnabled    → sign-out tile border, enabled state
  //   opacityBorderDisabled   → sign-out tile border, disabled state
  //                             ↳ also: delete tile border alternative
  //   opacityDeleteBorderDis  → delete tile border, disabled state

  /// Disabled text/icon alpha — applied to signOutRed / error color
  /// to produce the muted disabled variant. Used in both destructive tiles.
  static const double opacityDisabledColor    = 0.40;

  /// Chevron and secondary icon mute alpha. Applied to the trailing icon
  /// in SignOutTile and _DeleteAccountTile.
  static const double opacityChevron          = 0.50;

  /// Sign-out tile background, disabled state.
  static const double opacityTileFillDisabled = 0.04;

  /// Sign-out tile background, enabled, dark theme.
  static const double opacityTileFillDarkEn   = 0.12;

  /// Sign-out tile background, enabled, light theme.
  /// Also: delete tile background, enabled, dark theme (same design value).
  static const double opacityTileFillLightEn  = 0.08;

  /// Delete tile background, enabled, light theme (tighter fill than sign-out).
  static const double opacityDeleteFillLightEn = 0.05;

  /// Delete tile background, disabled state (tighter than sign-out).
  static const double opacityDeleteFillDis     = 0.03;

  /// Icon container background — delete tile (slightly darker than sign-out).
  static const double opacityIconBg            = 0.12;

  /// Icon container background — sign-out tile.
  /// Also: delete tile border colour, enabled state (same design value).
  static const double opacityIconBgAlt         = 0.15;

  /// Tile border colour, enabled — sign-out tile.
  static const double opacityBorderEnabled     = 0.20;

  /// Tile border colour, disabled — sign-out tile.
  static const double opacityBorderDisabled    = 0.08;

  /// Delete tile border colour, disabled state (tighter than sign-out).
  static const double opacityDeleteBorderDis   = 0.06;

  // Location & map
  static const double defaultSearchRadiusKm = 50.0;
  static const double minSearchRadiusKm     = 5.0;
  static const double maxSearchRadiusKm     = 100.0;
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double defaultZoom = 12.0;
  static const double minZoom     = 8.0;
  static const double maxZoom     = 18.0;

  static const Map<String, LatLng> cityCenters = {
    'alger':       LatLng(36.7372, 3.0865),
    'oran':        LatLng(35.7089, -0.6416),
    'constantine': LatLng(36.3650, 6.6147),
    'annaba':      LatLng(36.9000, 7.7667),
    'blida':       LatLng(36.4203, 2.8277),
    'batna':       LatLng(35.5559, 6.1741),
    'djelfa':      LatLng(34.6792, 3.2550),
    'setif':       LatLng(36.1905, 5.4033),
  };

  // File upload
  static const int maxImageSizeMB = 10;
  static const int maxVideoSizeMB = 100;
  static const int maxAudioSizeMB = 50;

  // Validation
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 128;
  static const int minUsernameLength = 2;
  static const int maxUsernameLength = 50;

  static final RegExp emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
}

class AppAssets {
  AppAssets._();

  static const String _images     = 'assets/images';
  static const String _animations = 'assets/animations';

  static const String logo                = '$_images/logo.png';
  static const String logoWhite           = '$_images/logo_white.png';
  static const String logoIcon            = '$_images/logo_icon.png';
  static const String onboarding1         = '$_images/onboarding_1.png';
  static const String onboarding2         = '$_images/onboarding_2.png';
  static const String onboarding3         = '$_images/onboarding_3.png';
  static const String emptyRequests       = '$_images/empty_requests.png';
  static const String emptyMessages       = '$_images/empty_messages.png';
  static const String emptyWorkers        = '$_images/empty_workers.png';
  static const String noResults           = '$_images/no_results.png';
  static const String workerIllustration  = '$_images/worker.png';
  static const String userIllustration    = '$_images/user.png';
  static const String serviceIllustration = '$_images/service.png';
  static const String avatarPlaceholder   = '$_images/avatar_placeholder.png';
  static const String imagePlaceholder    = '$_images/image_placeholder.png';
  static const String loadingAnimation    = '$_animations/loading.json';
  static const String successAnimation    = '$_animations/success.json';
  static const String errorAnimation      = '$_animations/error.json';
  static const String locationAnimation   = '$_animations/location.json';
  static const String homeBoilerCare      = '$_animations/home_boiler_care.json';
  static const String splashStatic        = 'assets/splash_static.png';
}

class AppIcons {
  AppIcons._();

  // Navigation
  static const IconData home             = Icons.home_rounded;
  static const IconData homeOutlined     = Icons.home_outlined;
  static const IconData search           = Icons.search_rounded;
  static const IconData searchOutlined   = Icons.search_outlined;
  static const IconData requests         = Icons.request_page_rounded;
  static const IconData requestsOutlined = Icons.request_page_outlined;
  static const IconData messages         = Icons.message_rounded;
  static const IconData messagesOutlined = Icons.message_outlined;
  static const IconData profile          = Icons.person_rounded;
  static const IconData profileOutlined  = Icons.person_outline_rounded;

  // Worker navigation
  static const IconData dashboard         = Icons.dashboard_rounded;
  static const IconData dashboardOutlined = Icons.dashboard_outlined;
  static const IconData jobs              = Icons.work_rounded;
  static const IconData jobsOutlined      = Icons.work_outline_rounded;

  // Auth
  static const IconData email         = Icons.email_outlined;
  static const IconData password      = Icons.lock_outline_rounded;
  static const IconData visibility    = Icons.visibility_outlined;
  static const IconData visibilityOff = Icons.visibility_off_outlined;
  static const IconData person        = Icons.person_outline_rounded;
  static const IconData phone         = Icons.phone_outlined;

  // Services
  static const IconData plumbing        = Icons.plumbing_rounded;
  static const IconData electrical      = Icons.electrical_services_rounded;
  static const IconData cleaning        = Icons.cleaning_services_rounded;
  static const IconData painting        = Icons.format_paint_rounded;
  static const IconData carpentry       = Icons.carpenter_rounded;
  static const IconData gardening       = Icons.grass_rounded;
  static const IconData airConditioning = Icons.air_rounded;
  static const IconData appliances      = Icons.kitchen_rounded;

  // Actions
  static const IconData add      = Icons.add_rounded;
  static const IconData edit     = Icons.edit_rounded;
  static const IconData delete   = Icons.delete_outline_rounded;
  static const IconData save     = Icons.save_rounded;
  static const IconData cancel   = Icons.cancel_outlined;
  static const IconData check    = Icons.check_circle_rounded;
  static const IconData close    = Icons.close_rounded;
  static const IconData back     = Icons.arrow_back_rounded;
  static const IconData forward  = Icons.arrow_forward_rounded;
  static const IconData upload   = Icons.upload_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData share    = Icons.share_rounded;
  static const IconData filter   = Icons.filter_list_rounded;
  static const IconData sort     = Icons.sort_rounded;
  static const IconData stop     = Icons.stop_rounded;
  static const IconData build    = Icons.build_rounded;
  static const IconData gridView = Icons.grid_view_rounded;

  // Status
  static const IconData pending    = Icons.pending_outlined;
  static const IconData accepted   = Icons.check_circle_outline_rounded;
  static const IconData declined   = Icons.cancel_outlined;
  static const IconData completed  = Icons.done_all_rounded;
  static const IconData inProgress = Icons.hourglass_empty_rounded;

  // Bid model
  static const IconData bid            = Icons.local_offer_rounded;
  static const IconData bidOutlined    = Icons.local_offer_outlined;
  static const IconData tracking       = Icons.track_changes_rounded;
  static const IconData ratingFilled   = Icons.star_rounded;
  static const IconData ratingOutlined = Icons.star_outline_rounded;
  static const IconData timer          = Icons.timer_outlined;
  static const IconData timerActive    = Icons.timer_rounded;
  static const IconData wallet         = Icons.account_balance_wallet_outlined;

  // Settings
  static const IconData settings            = Icons.settings_rounded;
  static const IconData language            = Icons.language_rounded;
  static const IconData theme               = Icons.brightness_6_rounded;
  static const IconData notifications       = Icons.notifications_outlined;
  static const IconData notificationsActive = Icons.notifications_active_rounded;
  static const IconData help                = Icons.help_outline_rounded;
  static const IconData info                = Icons.info_outline_rounded;
  static const IconData logout              = Icons.logout_rounded;
  static const IconData deleteAccount       = Icons.no_accounts_outlined;

  // Map
  static const IconData location         = Icons.location_on_rounded;
  static const IconData locationOutlined = Icons.location_on_outlined;
  static const IconData myLocation       = Icons.my_location_rounded;
  static const IconData directions       = Icons.directions_rounded;
  static const IconData map              = Icons.map_outlined;
  static const IconData openWith         = Icons.open_with_rounded;
  static const IconData locationSearch   = Icons.location_searching_rounded;
  static const IconData locationOff      = Icons.location_off_rounded;

  // Feedback
  static const IconData error   = Icons.error_outline_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData success = Icons.check_circle_outline_rounded;

  // Chat / media
  static const IconData send     = Icons.send_rounded;
  static const IconData attach   = Icons.attach_file_rounded;
  static const IconData image    = Icons.image_outlined;
  static const IconData camera   = Icons.camera_alt_outlined;
  static const IconData mic      = Icons.mic_rounded;
  static const IconData micOff   = Icons.mic_off_rounded;
  static const IconData gallery  = Icons.photo_library_rounded;
  static const IconData videocam = Icons.videocam_rounded;
  static const IconData play     = Icons.play_arrow_rounded;
  static const IconData pause    = Icons.pause_rounded;

  // Rating
  static const IconData star         = Icons.star_rounded;
  static const IconData starOutlined = Icons.star_outline_rounded;
  static const IconData starHalf     = Icons.star_half_rounded;

  // AI
  static const IconData ai         = Icons.auto_awesome_rounded;
  static const IconData aiOutlined = Icons.auto_awesome_outlined;

  // Form / step
  static const IconData editNote      = Icons.edit_note_rounded;
  static const IconData twilight      = Icons.wb_twilight_rounded;
  static const IconData calendarToday = Icons.calendar_today_rounded;
}

class AppRoutes {
  AppRoutes._();

  static const String splash            = '/';
  static const String login             = '/login';
  static const String register          = '/register';
  static const String forgotPassword    = '/forgot-password';
  static const String emailVerification = '/verify-email';
  static const String home              = '/home';
  static const String search            = '/search';
  static const String requests          = '/requests';
  static const String profile           = '/profile';
  static const String workerJobs        = '/worker-jobs';
  static const String workerSettings    = '/worker-settings';
  static const String serviceRequest    = '/service-request';
  static const String workerProfile     = '/worker/:id';
  static const String settings          = '/settings';
  static const String editProfile       = '/edit-profile';
  static const String notifications     = '/notifications';
  static const String help              = '/help';
  static const String about             = '/about';
  static const String bidsListScreen    = '/service-request/:id/bids';
  static const String requestTracking   = '/service-request/:id/tracking';
  static const String clientRating      = '/service-request/:id/rating';
  static const String submitBid         = '/worker/jobs/:id/bid';
  static const String workerJobDetail   = '/worker/jobs/:id';

  // KEPT — used only in app_router.dart redirect logic (not a registered route):
  static const String workerHome = '/worker-home';
}

class PrefKeys {
  PrefKeys._();

  static const String isFirstLaunch = 'is_first_launch';
  static const String languageCode  = 'language_code';
  static const String themeMode     = 'theme_mode';
  static const String userId        = 'user_id';
  static const String userType      = 'user_type';
  static const String viewMode      = 'view_mode';
  static const String accountRole   = 'account_role';
  static const String fcmToken      = 'fcm_token';
  static const String lastLocation  = 'last_location';
}

class UserType {
  UserType._();
  static const String user   = 'user';
  static const String worker = 'worker';
}

class ServiceType {
  ServiceType._();
  static const String plumbing        = 'plumber';
  static const String electrical      = 'electrician';
  static const String cleaning        = 'cleaner';
  static const String painting        = 'painter';
  static const String carpentry       = 'carpenter';
  static const String gardening       = 'gardener';
  static const String airConditioning = 'ac_repair';
  static const String appliances      = 'appliance_repair';
  static const String masonry         = 'mason';

  static List<String> get all => [
    plumbing, electrical, cleaning, painting,
    carpentry, gardening, airConditioning, appliances,
  ];
}
