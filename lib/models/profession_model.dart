// lib/models/profession_model.dart
//
// Dynamic profession model that mirrors the backend /professions endpoint.
//
// Design notes:
// - Labels are stored per-locale so the picker can display the right language.
// - iconName is a Material Icons string resolved at render time, never at model time.
//   This lets the backend add new icons without a client update.
// - key must match VALID_PROFESSIONS in the NestJS IntentExtractorService.

import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfessionModel
// ─────────────────────────────────────────────────────────────────────────────

class ProfessionModel extends Equatable {
  /// Stable snake_case key — 'plumber', 'electrician', etc.
  /// Sent to the API and matched by the AI intent extractor.
  final String key;

  /// Material Icons name — mapped at render time in ProfessionPickerV2.
  final String iconName;

  /// Grouping key for the category-aware picker: 'water', 'energy', etc.
  final String categoryKey;

  /// Display label in the requested locale.
  final String label;

  /// Category label in the requested locale.
  final String categoryLabel;

  /// Display order in the picker (ascending).
  final int sortOrder;

  /// False → profession hidden in picker but still valid in existing requests.
  final bool isActive;

  const ProfessionModel({
    required this.key,
    required this.iconName,
    required this.categoryKey,
    required this.label,
    required this.categoryLabel,
    required this.sortOrder,
    this.isActive = true,
  });

  // ── Deserialization ────────────────────────────────────────────────────────

  factory ProfessionModel.fromJson(Map<String, dynamic> json, {String lang = 'fr'}) {
    // The API can return localized labels directly (if ?lang= was passed)
    // or as nested maps { fr: ..., ar: ..., en: ... }
    final rawLabels    = json['labels'];
    final rawCatLabels = json['categoryLabels'];

    final String label;
    final String categoryLabel;

    if (rawLabels is String) {
      label = rawLabels;
    } else if (rawLabels is Map) {
      label = (rawLabels[lang] as String?) ??
              (rawLabels['fr']  as String?) ??
              (json['key'] as String? ?? '');
    } else {
      label = json['label'] as String? ?? json['key'] as String? ?? '';
    }

    if (rawCatLabels is String) {
      categoryLabel = rawCatLabels;
    } else if (rawCatLabels is Map) {
      categoryLabel = (rawCatLabels[lang] as String?) ??
                      (rawCatLabels['fr']  as String?) ??
                      '';
    } else {
      categoryLabel = json['categoryLabel'] as String? ?? '';
    }

    return ProfessionModel(
      key:           json['key']         as String? ?? '',
      iconName:      json['iconName']    as String? ?? 'work_outline',
      categoryKey:   json['categoryKey'] as String? ?? 'service',
      label:         label,
      categoryLabel: categoryLabel,
      sortOrder:     json['sortOrder']   as int?    ?? 99,
      isActive:      json['isActive']    as bool?   ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'key':           key,
    'iconName':      iconName,
    'categoryKey':   categoryKey,
    'label':         label,
    'categoryLabel': categoryLabel,
    'sortOrder':     sortOrder,
    'isActive':      isActive,
  };

  ProfessionModel copyWith({
    String? key, String? iconName, String? categoryKey,
    String? label, String? categoryLabel, int? sortOrder, bool? isActive,
  }) {
    return ProfessionModel(
      key:           key           ?? this.key,
      iconName:      iconName      ?? this.iconName,
      categoryKey:   categoryKey   ?? this.categoryKey,
      label:         label         ?? this.label,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      sortOrder:     sortOrder     ?? this.sortOrder,
      isActive:      isActive      ?? this.isActive,
    );
  }

  @override
  List<Object?> get props => [key, iconName, categoryKey, label, categoryLabel, sortOrder, isActive];

  @override
  String toString() => 'ProfessionModel(key: $key, label: $label, category: $categoryKey)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline fallback list — always available, no network required.
// These 12 professions are the baseline. Additional ones come from the API.
// Keys MUST match VALID_PROFESSIONS in apps/api/src/modules/ai/services/intent-extractor.service.ts
// ─────────────────────────────────────────────────────────────────────────────

const List<ProfessionModel> kDefaultProfessions = [
  // Water & Plumbing
  ProfessionModel(key: 'plumber',          iconName: 'water_drop_outlined',          categoryKey: 'water',     label: 'Plombier',                    categoryLabel: 'Eau & Plomberie',       sortOrder: 10),
  // Energy & Cooling
  ProfessionModel(key: 'electrician',      iconName: 'bolt_outlined',                categoryKey: 'energy',    label: 'Électricien',                 categoryLabel: 'Énergie & Froid',       sortOrder: 20),
  ProfessionModel(key: 'ac_repair',        iconName: 'air_outlined',                 categoryKey: 'energy',    label: 'Climatisation',               categoryLabel: 'Énergie & Froid',       sortOrder: 21),
  // Building & Renovation
  ProfessionModel(key: 'mason',            iconName: 'foundation_outlined',          categoryKey: 'building',  label: 'Maçon',                       categoryLabel: 'Bâtiment & Rénovation', sortOrder: 30),
  ProfessionModel(key: 'painter',          iconName: 'format_paint_outlined',        categoryKey: 'building',  label: 'Peintre',                     categoryLabel: 'Bâtiment & Rénovation', sortOrder: 31),
  ProfessionModel(key: 'carpenter',        iconName: 'carpenter_outlined',           categoryKey: 'building',  label: 'Menuisier',                   categoryLabel: 'Bâtiment & Rénovation', sortOrder: 32),
  // Home Services
  ProfessionModel(key: 'cleaner',          iconName: 'cleaning_services_outlined',   categoryKey: 'service',   label: 'Agent de nettoyage',          categoryLabel: 'Services à domicile',   sortOrder: 40),
  ProfessionModel(key: 'appliance_repair', iconName: 'home_repair_service_outlined', categoryKey: 'service',   label: 'Réparation électroménager',   categoryLabel: 'Services à domicile',   sortOrder: 41),
  ProfessionModel(key: 'gardener',         iconName: 'yard_outlined',                categoryKey: 'service',   label: 'Jardinier',                   categoryLabel: 'Services à domicile',   sortOrder: 42),
  ProfessionModel(key: 'mover',            iconName: 'local_shipping_outlined',      categoryKey: 'service',   label: 'Déménageur',                  categoryLabel: 'Services à domicile',   sortOrder: 43),
  // Transport & Mobility
  ProfessionModel(key: 'mechanic',         iconName: 'car_repair_outlined',          categoryKey: 'transport', label: 'Mécanicien',                  categoryLabel: 'Transport & Mobilité',  sortOrder: 50),
];

/// All valid profession keys — mirrors VALID_PROFESSIONS on the backend.
const Set<String> kValidProfessionKeys = {
  'plumber', 'electrician', 'ac_repair', 'mason', 'painter', 'carpenter',
  'cleaner', 'appliance_repair', 'gardener', 'mover', 'mechanic',
};
