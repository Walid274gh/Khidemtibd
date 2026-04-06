// lib/utils/profession_resolver.dart

class ProfessionResolver {
  ProfessionResolver._();

  // ── Comprehensive keyword → profession map ─────────────────────────────────
  // All keys are pre-normalised (lowercase, diacritics removed — see _normalize).
  // ORDER MATTERS within a profession: most specific entries first.
  static const Map<String, String> _keywords = {
    // ═══════════════════════════════════════════════════════════════════════
    // PLUMBER
    // ═══════════════════════════════════════════════════════════════════════
    // English
    'plumber':           'plumber',
    'plumbing':          'plumber',
    'pipe':              'plumber',
    // French
    'plombier':          'plumber',
    'plomberie':         'plumber',
    'fuite':             'plumber',
    "fuite d'eau":       'plumber',
    'eau':               'plumber',
    'robinet':           'plumber',
    // Algerian phonetics / Arabized misspellings — the main ask
    'blombi':            'plumber',
    'blombie':           'plumber',
    'blombe':            'plumber',
    'bloumbi':           'plumber',
    'bloumbie':          'plumber',
    'plambier':          'plumber',
    'plombi':            'plumber',
    'plambir':           'plumber',
    'plamsier':          'plumber',
    'bloumseur':         'plumber',
    'blombier':          'plumber',
    'blomsier':          'plumber',
    'blomber':           'plumber',
    'plan b':            'plumber', // STT misrecognition common pattern
    'plam':              'plumber',
    // Arabic / Darija
    'سباك':              'plumber',
    'سبّاك':             'plumber',
    'صباك':              'plumber',
    'صبّاك':             'plumber',
    'سباكة':             'plumber',
    'ماء ساقط':          'plumber',
    'ماء':               'plumber',
    'فيضان':             'plumber',
    'تسرب':              'plumber',
    'تسريب':             'plumber',
    'صنبور':             'plumber',
    'صنفارية':           'plumber',
    'فيته':              'plumber', // Darija "fuite"
    'بلومبي':            'plumber',
    'بلومب':             'plumber',

    // ═══════════════════════════════════════════════════════════════════════
    // ELECTRICIAN
    // ═══════════════════════════════════════════════════════════════════════
    'electrician':       'electrician',
    'electrical':        'electrician',
    'electricien':       'electrician',
    'electricite':       'electrician',
    'elec':              'electrician',
    'electric':          'electrician',
    'courant':           'electrician',
    'panne electrique':  'electrician',
    'panne':             'electrician',
    'tension':           'electrician',
    'fusible':           'electrician',
    'disjoncteur':       'electrician',
    // Algerian phonetics
    'iliktrisyan':       'electrician',
    'ilaktrisyan':       'electrician',
    'iliktrisyane':      'electrician',
    'ilaktrisi':         'electrician',
    'الكتريسيان':        'electrician',
    // Arabic / Darija
    'كهربائي':           'electrician',
    'كهرباء':            'electrician',
    'ضوء':               'electrician',
    'ضو':                'electrician', // Darija
    'نور':               'electrician',
    'انقطاع':            'electrician',
    'تيار':              'electrician',

    // ═══════════════════════════════════════════════════════════════════════
    // CLEANER
    // ═══════════════════════════════════════════════════════════════════════
    'cleaner':           'cleaner',
    'cleaning':          'cleaner',
    'nettoyage':         'cleaner',
    'nettoyeur':         'cleaner',
    'menage':            'cleaner',
    'femme de menage':   'cleaner',
    // Algerian phonetics
    'nitayaj':           'cleaner',
    'nettayaj':          'cleaner',
    // Arabic / Darija
    'تنظيف':             'cleaner',
    'نظافة':             'cleaner',
    'نضافة':             'cleaner', // Darija spelling

    // ═══════════════════════════════════════════════════════════════════════
    // PAINTER
    // ═══════════════════════════════════════════════════════════════════════
    'painter':           'painter',
    'painting':          'painter',
    'peintre':           'painter',
    'peinture':          'painter',
    // Algerian phonetics
    'banteri':           'painter',
    'pantri':            'painter',
    'bantiri':           'painter',
    'باينتري':           'painter',
    // Arabic / Darija
    'دهّان':             'painter',
    'دهان':              'painter',
    'صبّاغ':             'painter',
    'صباغ':              'painter',
    'صباغة':             'painter',
    'دهانة':             'painter',

    // ═══════════════════════════════════════════════════════════════════════
    // CARPENTER
    // ═══════════════════════════════════════════════════════════════════════
    'carpenter':         'carpenter',
    'carpentry':         'carpenter',
    'menuisier':         'carpenter',
    'menuiserie':        'carpenter',
    'bois':              'carpenter',
    // Algerian phonetics
    'miniziri':          'carpenter',
    'minouizri':         'carpenter',
    'menuizri':          'carpenter',
    // Arabic / Darija
    'نجّار':             'carpenter',
    'نجار':              'carpenter',
    'نجارة':             'carpenter',
    'منويزري':           'carpenter', // Darija for menuisier

    // ═══════════════════════════════════════════════════════════════════════
    // GARDENER
    // ═══════════════════════════════════════════════════════════════════════
    'gardener':          'gardener',
    'gardening':         'gardener',
    'jardinier':         'gardener',
    'jardinage':         'gardener',
    // Arabic / Darija
    'بستاني':            'gardener',
    'بستنة':             'gardener',
    'حديقة':             'gardener',
    'عشب':               'gardener',

    // ═══════════════════════════════════════════════════════════════════════
    // AC REPAIR
    // ═══════════════════════════════════════════════════════════════════════
    'ac_repair':         'ac_repair',
    'ac repair':         'ac_repair',
    'climatiseur':       'ac_repair',
    'climatisation':     'ac_repair',
    'clim':              'ac_repair',
    'air conditioning':  'ac_repair',
    'air conditioner':   'ac_repair',
    'ac':                'ac_repair',
    // Algerian phonetics
    'klimatizor':        'ac_repair',
    'klimatizour':       'ac_repair',
    'klimatizeur':       'ac_repair',
    'klimatizer':        'ac_repair',
    'klimatizur':        'ac_repair',
    // Arabic / Darija
    'كليماتيزور':        'ac_repair',
    'كليمة':             'ac_repair', // colloquial shortening
    'تكييف':             'ac_repair',
    'مكيف':              'ac_repair',
    'تبريد':             'ac_repair',

    // ═══════════════════════════════════════════════════════════════════════
    // APPLIANCE REPAIR
    // ═══════════════════════════════════════════════════════════════════════
    'appliance_repair':  'appliance_repair',
    'appliance repair':  'appliance_repair',
    'appliance':         'appliance_repair',
    'electromenager':    'appliance_repair',
    'electromenagiste':  'appliance_repair',
    'frigo':             'appliance_repair',
    'refrigerateur':     'appliance_repair',
    'lave linge':        'appliance_repair',
    'machine a laver':   'appliance_repair',
    // Algerian phonetics
    'filiktromenajer':   'appliance_repair',
    'iliktromenajer':    'appliance_repair',
    // Arabic / Darija
    'فريج':              'appliance_repair',
    'فريجو':             'appliance_repair', // Darija for frigo
    'ثلاجة':             'appliance_repair',
    'غسالة':             'appliance_repair',
    'أجهزة':             'appliance_repair',

    // ═══════════════════════════════════════════════════════════════════════
    // MASON
    // ═══════════════════════════════════════════════════════════════════════
    'mason':             'mason',
    'masonry':           'mason',
    'macon':             'mason',
    'maconnerie':        'mason',
    'ciment':            'mason',
    'carrelage':         'mason',
    'beton':             'mason',
    'construction':      'mason',
    // Algerian phonetics
    'karilaj':           'mason',
    'karilo':            'mason',
    'كاريلاج':           'mason', // Darija for carrelage
    // Arabic / Darija
    'بنّاء':             'mason',
    'بناء':              'mason',
    'جدار':              'mason',
    'سيمان':             'mason', // Darija for ciment
    'بلاط':              'mason',

    // ═══════════════════════════════════════════════════════════════════════
    // MECHANIC
    // ═══════════════════════════════════════════════════════════════════════
    'mechanic':          'mechanic',
    'mecanicien':        'mechanic',
    'mecanique':         'mechanic',
    'voiture':           'mechanic',
    'auto':              'mechanic',
    'moteur':            'mechanic',
    // Arabic / Darija
    'ميكانيكي':          'mechanic',
    'سيارة':             'mechanic',
    'موتور':             'mechanic',

    // ═══════════════════════════════════════════════════════════════════════
    // MOVER
    // ═══════════════════════════════════════════════════════════════════════
    'mover':             'mover',
    'demenageur':        'mover',
    'demenagement':      'mover',
    'mobilier':          'mover',
    'transport':         'mover',
    // Arabic / Darija
    'ناقل':              'mover',
    'نقل':               'mover',
    'أثاث':              'mover',
    'اثاث':              'mover',
  };

  // ── Latin canonical targets for fuzzy matching only ──────────────────────
  // Kept minimal — fuzzy is a last-resort fallback for clear misspellings.
  static const Map<String, String> _fuzzyTargets = {
    'plombier':       'plumber',
    'plumber':        'plumber',
    'blombi':         'plumber',
    'electricien':    'electrician',
    'electrician':    'electrician',
    'nettoyeur':      'cleaner',
    'cleaner':        'cleaner',
    'peintre':        'painter',
    'painter':        'painter',
    'menuisier':      'carpenter',
    'carpenter':      'carpenter',
    'jardinier':      'gardener',
    'gardener':       'gardener',
    'climatiseur':    'ac_repair',
    'klimatizor':     'ac_repair',
    'electromenager': 'appliance_repair',
    'macon':          'mason',
    'mason':          'mason',
    'mecanicien':     'mechanic',
    'mechanic':       'mechanic',
    'demenageur':     'mover',
    'mover':          'mover',
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Resolves a free-text query to a canonical profession key, or null.
  ///
  /// Accepts Arabic, French, English, Algerian Darija, and phonetic variants
  /// (e.g. "blombi", "بلومبي", "klim", "plambier" → correct profession).
  ///
  /// Returns null when the query is too ambiguous or unrecognised.
  static String? resolve(String query) {
    if (query.trim().isEmpty) return null;

    final normalised = _normalise(query);
    if (normalised.isEmpty) return null;

    // ── Stage 1: exact full-query match ──────────────────────────────────────
    final exactHit = _keywords[normalised];
    if (exactHit != null) return exactHit;

    // ── Stage 2: per-token scan ───────────────────────────────────────────────
    final tokens = normalised.split(RegExp(r'\s+'));
    for (final token in tokens) {
      if (token.length < 2) continue;
      final hit = _keywords[token];
      if (hit != null) return hit;
    }

    // ── Stage 3: prefix match ─────────────────────────────────────────────────
    // "plomb" matches "plombier", "clim" matches "climatiseur", etc.
    for (final entry in _keywords.entries) {
      if (entry.key.length < 3) continue;
      if (normalised.startsWith(entry.key) || entry.key.startsWith(normalised)) {
        return entry.value;
      }
      // Also try per-token prefix
      for (final token in tokens) {
        if (token.length < 3) continue;
        if (token.startsWith(entry.key) || entry.key.startsWith(token)) {
          return entry.value;
        }
      }
    }

    // ── Stage 4: Levenshtein fuzzy (Latin tokens only) ────────────────────────
    // Arabic is handled entirely by the exact map above;
    // fuzzy is only for Latin misspellings like "blombi" vs "plombier".
    final latinTokens = tokens
        .where((t) => t.length >= 4 && _isLatin(t))
        .toList();

    if (latinTokens.isNotEmpty) {
      String? bestProfession;
      int bestDistance = 3; // allow up to 3 edits (insertions/deletions/substitutions)

      for (final token in latinTokens) {
        for (final entry in _fuzzyTargets.entries) {
          final d = _levenshtein(token, entry.key);
          if (d < bestDistance) {
            bestDistance = d;
            bestProfession = entry.value;
          }
        }
      }

      if (bestProfession != null) return bestProfession;
    }

    return null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Lowercase + strip common French/Spanish diacritics + collapse whitespace.
  /// Arabic characters are preserved as-is (they appear in the keyword map).
  static String _normalise(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll('ç', 'c')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// True when the string contains NO Arabic/Farsi Unicode block characters.
  /// Used to gate the fuzzy matcher (Levenshtein is meaningless for Arabic).
  static bool _isLatin(String s) {
    return !RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]').hasMatch(s);
  }

  /// Classic two-row Levenshtein distance, bails early if [maxDist] exceeded.
  static int _levenshtein(String a, String b, {int maxDist = 3}) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length.clamp(0, maxDist);
    if (b.isEmpty) return a.length.clamp(0, maxDist);
    if ((a.length - b.length).abs() > maxDist) return maxDist + 1;

    List<int> prev = List<int>.generate(b.length + 1, (i) => i);
    List<int> curr = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      int rowMin = curr[0];
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
        if (curr[j] < rowMin) rowMin = curr[j];
      }
      // Early exit: entire row exceeds cap
      if (rowMin > maxDist) return maxDist + 1;
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[b.length];
  }
}
