// lib/utils/ranking_utils.dart
//
// Pure algorithm utilities for worker ranking.
// No Flutter / Firebase imports — fully unit-testable.
//
// Algorithms:
//   • bayesianRating  — prevents cold-start and low-volume rating inflation
//   • workerScore     — composite ranking (rating + distance + recency)
//
// ALGO FIX (A5):
//   workerScore() previously accepted bayesianRatingValue but had no
//   reviewCount parameter. Callers passed worker.averageRating (raw average)
//   without any cold-start guard, meaning a newly-registered worker with zero
//   reviews and averageRating=0.0 received the minimum possible score instead
//   of the platform globalAverage — suppressing new workers unfairly.
//
//   Fix: add `int reviewCount = 0` parameter.
//   When reviewCount == 0, substitute globalAverage for the rating component
//   (same cold-start logic as bayesianRating()). When reviewCount > 0, use
//   bayesianRatingValue as provided (caller is responsible for Bayesian
//   computation; passing averageRating is also acceptable when reviewCount
//   is known — workerScore normalises the value by 5.0 either way).

import 'dart:math' show exp;

/// Ranking utilities — pure Dart, no external dependencies.
class RankingUtils {
  RankingUtils._();

  // ── Bayesian rating ────────────────────────────────────────────────────────

  /// Bayesian average rating.
  ///
  /// Prevents a worker with 1× 5★ from outranking one with 500× 4.8★.
  ///
  /// Formula: (m × C + Σratings) / (m + n)
  ///
  /// Parameters
  /// ----------
  /// [sumRatings]    — sum of all individual star ratings given to this worker.
  /// [reviewCount]   — total number of ratings received.
  /// [globalAverage] — C: global average across all workers.
  ///                   Start at 3.5; recalculate periodically from real data
  ///                   once you have 100+ reviews in the system.
  /// [minReviews]    — m: minimum reviews threshold (confidence weight).
  ///                   Start at 10; tune based on your platform's worker density.
  ///
  /// Returns [globalAverage] for workers with zero reviews (cold-start fallback).
  static double bayesianRating({
    required double sumRatings,
    required int    reviewCount,
    double globalAverage = 3.5, // C — recalibrate after 100+ real ratings
    int    minReviews    = 10,  // m — tune based on worker density
  }) {
    if (reviewCount <= 0) return globalAverage; // cold-start fallback
    return (minReviews * globalAverage + sumRatings) / (minReviews + reviewCount);
  }

  // ── Composite worker score ─────────────────────────────────────────────────

  /// Composite ranking score — higher is better, range ≈ [0, 1].
  ///
  /// Combines four signals with tunable weights.
  ///
  /// Weights (must sum to 1.0):
  ///   wRating   = 0.40  — Bayesian rating (0–5 normalized to 0–1)
  ///   wDistance = 0.35  — proximity (exponential decay over [decayKm] km)
  ///   wResponse = 0.15  — response rate (0–1 fraction)
  ///   wRecency  = 0.10  — last-active recency (exponential decay over 30 days)
  ///
  /// ALGO FIX (A5): added [reviewCount] parameter.
  ///
  /// When [reviewCount] == 0, the rating component uses [globalAverage] / 5.0
  /// as a neutral fallback — identical cold-start logic to bayesianRating().
  /// This prevents new workers (averageRating = 0.0) from being pushed to the
  /// bottom of results simply for having no history yet.
  ///
  /// When [reviewCount] > 0, [bayesianRatingValue] is used as-is.
  /// Callers should pass a pre-computed Bayesian average or the raw
  /// averageRating — workerScore() normalises it to [0, 1] via /5.0 either way.
  ///
  /// Tune weights after collecting sufficient user feedback data.
  static double workerScore({
    required double bayesianRatingValue, // 0–5
    required double distanceKm,          // 0–∞
    int    reviewCount     = 0,          // FIX (A5): 0 → cold-start fallback
    double responseRate    = 1.0,        // 0–1  (default: assume responsive)
    int    daysSinceActive = 0,          // 0–∞  (default: active today)
    double decayKm         = 5.0,        // distance half-life in km
    double decayDays       = 30.0,       // recency half-life in days
    double globalAverage   = 3.5,        // C — matches bayesianRating() default
  }) {
    const double wRating   = 0.40;
    const double wDistance = 0.35;
    const double wResponse = 0.15;
    const double wRecency  = 0.10;

    // FIX (A5): cold-start guard — use globalAverage when no reviews yet so
    // that new workers receive a neutral score rather than the minimum (0.0).
    final double effectiveRating =
        reviewCount == 0 ? globalAverage : bayesianRatingValue;

    final double ratingScore   = (effectiveRating / 5.0).clamp(0.0, 1.0);
    // Exponential decay: score = e^(-distance / decayKm)
    final double distanceScore = exp(-distanceKm / decayKm);
    final double responseScore = responseRate.clamp(0.0, 1.0);
    // Exponential decay: score = e^(-days / decayDays)
    final double recencyScore  = exp(-daysSinceActive / decayDays);

    return wRating   * ratingScore
         + wDistance * distanceScore
         + wResponse * responseScore
         + wRecency  * recencyScore;
  }

  // ── Normalization helpers ──────────────────────────────────────────────────

  /// Min-max normalize [value] within [[min], [max]].
  /// Returns 0.5 when range collapses (all values equal) to avoid degeneration.
  static double minMaxNormalize(double value, double min, double max) {
    final double range = max - min;
    if (range < 1e-9) return 0.5; // degenerate guard — not 0.0 or 1.0
    return ((value - min) / range).clamp(0.0, 1.0);
  }
}
