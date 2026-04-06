// lib/utils/geo_cell_utils.dart
//
// Pure geographic utilities — no Flutter / Firebase imports.
//
// Algorithms:
//   • GeoHashHelper.encode  — standard base32 geohash (replaces fake coordinate-string hash)
//   • GeoCellUtils.ringCellIds — expand search ring by radius rather than fixed 8-neighbour step

/// Base32 character set used by the standard geohash algorithm.
const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Geohash encoding helper.
///
/// Produces standard, interoperable geohash strings compatible with
/// Firestore geohash range queries and the `geoflutterfire2` / `firebase_geopoint`
/// libraries.
///
/// The fake implementation it replaces stored raw coordinates as a string:
///   `'${(lat*1000).round()}_${(lng*1000).round()}'`
/// That string is NOT a geohash — it cannot be range-queried on Firestore
/// and its sort order does not correspond to geographic proximity.
class GeoHashHelper {
  GeoHashHelper._();

  /// Encode [lat] / [lng] to a geohash string at [precision] characters.
  ///
  /// [precision] controls spatial resolution:
  ///   1 char  ≈ 5000 × 5000 km
  ///   4 chars ≈ 39 × 20 km
  ///   6 chars ≈ 1.2 × 0.6 km   ← default: matches ~5 km cell radius
  ///   8 chars ≈ 19 × 19 m
  ///
  /// Throws [ArgumentError] for invalid coordinates.
  static String encode(double lat, double lng, {int precision = 6}) {
    if (lat < -90  || lat > 90)  throw ArgumentError('Invalid latitude: $lat');
    if (lng < -180 || lng > 180) throw ArgumentError('Invalid longitude: $lng');
    if (precision < 1 || precision > 12) {
      throw ArgumentError('Precision must be 1–12, got $precision');
    }

    final buffer = StringBuffer();
    bool isEven = true;       // even bits → longitude, odd bits → latitude
    int  bit     = 0;
    int  ch      = 0;

    double latMin = -90.0,  latMax = 90.0;
    double lngMin = -180.0, lngMax = 180.0;

    while (buffer.length < precision) {
      double mid;
      if (isEven) {
        mid = (lngMin + lngMax) / 2.0;
        if (lng >= mid) { ch |= _bits[bit]; lngMin = mid; }
        else              {                   lngMax = mid; }
      } else {
        mid = (latMin + latMax) / 2.0;
        if (lat >= mid) { ch |= _bits[bit]; latMin = mid; }
        else              {                   latMax = mid; }
      }
      isEven = !isEven;

      if (bit < 4) {
        bit++;
      } else {
        buffer.writeCharCode(_base32.codeUnitAt(ch));
        bit = 0;
        ch  = 0;
      }
    }

    return buffer.toString();
  }

  /// Decode a geohash string back to a [_GeoHashBounds].
  /// Useful for computing neighbour hashes and bounding-box queries.
  static _GeoHashBounds decode(String hash) {
    if (hash.isEmpty) throw ArgumentError('Hash cannot be empty');

    bool isEven = true;
    double latMin = -90.0,  latMax = 90.0;
    double lngMin = -180.0, lngMax = 180.0;

    for (final c in hash.runes) {
      final charStr = String.fromCharCode(c);
      final cd = _base32.indexOf(charStr);
      if (cd == -1) throw ArgumentError('Invalid geohash character: $charStr');

      for (int mask in _bits) {
        final bitSet = (cd & mask) != 0;
        if (isEven) {
          final mid = (lngMin + lngMax) / 2.0;
          if (bitSet) lngMin = mid; else lngMax = mid;
        } else {
          final mid = (latMin + latMax) / 2.0;
          if (bitSet) latMin = mid; else latMax = mid;
        }
        isEven = !isEven;
      }
    }

    return _GeoHashBounds(
      latMin: latMin, latMax: latMax,
      lngMin: lngMin, lngMax: lngMax,
    );
  }

  /// Returns the 8 neighbouring geohashes at the same precision level.
  static List<String> neighbours(String hash) {
    final b       = decode(hash);
    final latMid  = (b.latMin + b.latMax) / 2.0;
    final lngMid  = (b.lngMin + b.lngMax) / 2.0;
    final latStep = b.latMax - b.latMin;
    final lngStep = b.lngMax - b.lngMin;
    final p       = hash.length;

    return [
      for (final dLat in [-1, 0, 1])
        for (final dLng in [-1, 0, 1])
          if (dLat != 0 || dLng != 0)
            encode(
              latMid + dLat * latStep,
              lngMid + dLng * lngStep,
              precision: p,
            ),
    ];
  }

  static const List<int> _bits = [16, 8, 4, 2, 1];
}

class _GeoHashBounds {
  final double latMin, latMax, lngMin, lngMax;
  const _GeoHashBounds({
    required this.latMin,
    required this.latMax,
    required this.lngMin,
    required this.lngMax,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GeoCellUtils — cell-ring expansion helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Helpers for generating geographic cell IDs based on the app's
/// `{wilayaCode}_{lat2dp}_{lng2dp}` cell-ID convention.
///
/// Replaces the fixed 8-neighbour offset (0.05°) with a configurable
/// radius-ring that matches the actual cell step size (0.01° per cell).
class GeoCellUtils {
  GeoCellUtils._();

  /// Cell step in decimal degrees — matches [GeographicGridService.cellPrecisionDegrees].
  static const double cellStepDeg = 0.01;

  /// Returns all cell IDs within [radiusSteps] rings around [centerLat]/[centerLng]
  /// in wilaya [wilayaCode], excluding the centre cell itself.
  ///
  /// [radiusSteps] = 1 → the 8 immediately-adjacent cells (0.01° offset each)
  /// [radiusSteps] = 5 → ~5 km radius at equator (~0.05° per step)
  ///
  /// This replaces the hard-coded 0.05° offset that skipped the 4 cells
  /// immediately adjacent to the centre (gap ≈ 5× the cell size).
  static List<String> ringCellIds({
    required double centerLat,
    required double centerLng,
    required int    wilayaCode,
    int radiusSteps = 1,
  }) {
    final ids = <String>[];
    for (int dLatSteps = -radiusSteps; dLatSteps <= radiusSteps; dLatSteps++) {
      for (int dLngSteps = -radiusSteps; dLngSteps <= radiusSteps; dLngSteps++) {
        if (dLatSteps == 0 && dLngSteps == 0) continue; // skip centre

        final adjLat = centerLat + dLatSteps * cellStepDeg;
        final adjLng = centerLng + dLngSteps * cellStepDeg;

        if (adjLat < -90 || adjLat > 90)   continue;
        if (adjLng < -180 || adjLng > 180) continue;

        ids.add(_cellId(adjLat, adjLng, wilayaCode));
      }
    }
    return ids;
  }

  static String _cellId(double lat, double lng, int wilayaCode) {
    final rLat = _round2dp(lat);
    final rLng = _round2dp(lng);
    return '${wilayaCode}_${rLat.toStringAsFixed(2)}_${rLng.toStringAsFixed(2)}';
  }

  static double _round2dp(double v) => (v * 100).round() / 100.0;
}
