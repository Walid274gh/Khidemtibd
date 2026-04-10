// lib/models/user_model.dart
//
// ARCHITECTURE — COLLECTION UNIFIÉE
// ────────────────────────────────────────────────────────────────────────────
// Le backend a fusionné les collections `users` et `workers` en une seule
// collection `users`, discriminée par le champ `role`.  Ce modèle reflète
// cette réalité : un seul objet Dart représente un client ET un travailleur.
//
// CHAMPS WORKER
// Les champs spécifiques aux travailleurs (profession, isOnline, averageRating…)
// sont présents dans tous les documents mais avec des valeurs neutres pour les
// clients (null / false / 0). Cela garantit qu'un document client ne satisfera
// jamais une requête worker-ciblée côté serveur.
//
// MIGRATION
// WorkerModel est maintenant un alias de type dans worker_model.dart.
// Tous les call sites existants compilent sans aucune modification.

import 'package:equatable/equatable.dart';

// Sentinel pour distinguer "champ absent" de "champ explicitement null"
// dans copyWith. Technique éprouvée — ne pas remplacer par null.
const _kUndef = Object();

// ─────────────────────────────────────────────────────────────────────────────
// UserModel
// ─────────────────────────────────────────────────────────────────────────────

class UserModel extends Equatable {
  // ── Identité ─────────────────────────────────────────────────────────────
  final String id;
  final String name;
  final String email;
  final String phoneNumber;

  /// Discriminateur de collection : 'client' | 'worker'
  final String role;

  // ── Localisation (commune) ────────────────────────────────────────────────
  final double? latitude;
  final double? longitude;
  final DateTime lastUpdated;
  final String? cellId;
  final int? wilayaCode;
  final String? geoHash;
  final DateTime? lastCellUpdate;

  // ── Médias / push (communs) ───────────────────────────────────────────────
  final String? profileImageUrl;
  final String? fcmToken;

  // ── Spécifiques au travailleur ────────────────────────────────────────────
  // Valeurs neutres pour les clients : null / false / 0 / 0.7
  // → un document client ne satisfera jamais isOnline=true ou profession≠null.

  /// Clé de métier (null pour les clients).
  final String? profession;

  /// Statut en ligne — pertinent uniquement pour les travailleurs.
  final bool isOnline;

  /// Note bayésienne (0–5). Initialisée à 0.0 pour les clients.
  final double averageRating;

  /// Nombre de notes reçues.
  final int ratingCount;

  /// Somme cumulée des étoiles — permet le recalcul bayésien sans historique.
  final int ratingSum;

  /// Nombre de missions accomplies.
  final int jobsCompleted;

  /// Taux de réponse aux offres (0–1). Valeur a priori : 0.7.
  final double responseRate;

  /// Horodatage de la dernière déconnexion — utilisé pour le tri par récence.
  final DateTime? lastActiveAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.role = 'client',
    this.latitude,
    this.longitude,
    required this.lastUpdated,
    this.cellId,
    this.wilayaCode,
    this.geoHash,
    this.lastCellUpdate,
    this.profileImageUrl,
    this.fcmToken,
    // Valeurs neutres par défaut — sûres pour les clients
    this.profession,
    this.isOnline = false,
    this.averageRating = 0.0,
    this.ratingCount = 0,
    this.ratingSum = 0,
    this.jobsCompleted = 0,
    this.responseRate = 0.7,
    this.lastActiveAt,
  });

  // ── Getters calculés ──────────────────────────────────────────────────────

  /// Vrai si ce document représente un travailleur.
  bool get isWorker => role == 'worker';

  /// Vrai si ce document représente un client.
  bool get isClient => role == 'client';

  /// Jours depuis la dernière activité. 0 si le worker est en ligne ou inconnu.
  int get daysSinceActive {
    if (lastActiveAt == null) return 0;
    return DateTime.now().difference(lastActiveAt!).inDays.clamp(0, 9999);
  }

  // ── Désérialisation ───────────────────────────────────────────────────────

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id:          id,
      name:        map['name']        as String? ?? '',
      email:       map['email']       as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      role:        map['role']        as String? ?? 'client',
      latitude:    (map['latitude']   as num?)?.toDouble(),
      longitude:   (map['longitude']  as num?)?.toDouble(),
      lastUpdated:    _parseDate(map['lastUpdated']),
      cellId:         map['cellId']          as String?,
      wilayaCode:     map['wilayaCode']      as int?,
      geoHash:        map['geoHash']         as String?,
      lastCellUpdate: _parseDateOrNull(map['lastCellUpdate']),
      profileImageUrl: map['profileImageUrl'] as String?,
      fcmToken:        map['fcmToken']        as String?,
      // Champs worker — valeurs neutres si absents (documents clients)
      profession:    map['profession']    as String?,
      isOnline:      map['isOnline']      as bool?   ?? false,
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount:   map['ratingCount']   as int?    ?? 0,
      ratingSum:     map['ratingSum']     as int?    ?? 0,
      jobsCompleted: map['jobsCompleted'] as int?    ?? 0,
      responseRate:  (map['responseRate'] as num?)?.toDouble() ?? 0.7,
      lastActiveAt:  _parseDateOrNull(map['lastActiveAt']),
    );
  }

  /// Accepte les réponses NestJS où l'id est sous `_id` ou `id`.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id']) as String? ?? '';
    return UserModel.fromMap(json, id);
  }

  Map<String, dynamic> toMap() => {
    'name':            name,
    'email':           email,
    'phoneNumber':     phoneNumber,
    'role':            role,
    'latitude':        latitude,
    'longitude':       longitude,
    'lastUpdated':     lastUpdated.toIso8601String(),
    'cellId':          cellId,
    'wilayaCode':      wilayaCode,
    'geoHash':         geoHash,
    'lastCellUpdate':  lastCellUpdate?.toIso8601String(),
    'profileImageUrl': profileImageUrl,
    'fcmToken':        fcmToken,
    'profession':      profession,
    'isOnline':        isOnline,
    'averageRating':   averageRating,
    'ratingCount':     ratingCount,
    'ratingSum':       ratingSum,
    'jobsCompleted':   jobsCompleted,
    'responseRate':    responseRate,
    'lastActiveAt':    lastActiveAt?.toIso8601String(),
  };

  // ── copyWith ──────────────────────────────────────────────────────────────
  // Sentinel _kUndef permet de distinguer "ne pas changer" de "mettre à null".
  // Pattern standard pour les champs nullable — ne pas simplifier.

  UserModel copyWith({
    String?   id,
    String?   name,
    String?   email,
    String?   phoneNumber,
    String?   role,
    Object?   latitude        = _kUndef,
    Object?   longitude       = _kUndef,
    DateTime? lastUpdated,
    Object?   cellId          = _kUndef,
    Object?   wilayaCode      = _kUndef,
    Object?   geoHash         = _kUndef,
    Object?   lastCellUpdate  = _kUndef,
    Object?   profileImageUrl = _kUndef,
    Object?   fcmToken        = _kUndef,
    Object?   profession      = _kUndef,
    bool?     isOnline,
    double?   averageRating,
    int?      ratingCount,
    int?      ratingSum,
    int?      jobsCompleted,
    double?   responseRate,
    Object?   lastActiveAt    = _kUndef,
  }) {
    return UserModel(
      id:          id          ?? this.id,
      name:        name        ?? this.name,
      email:       email       ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role:        role        ?? this.role,
      latitude: identical(latitude, _kUndef)
          ? this.latitude        : latitude        as double?,
      longitude: identical(longitude, _kUndef)
          ? this.longitude       : longitude       as double?,
      lastUpdated:    lastUpdated    ?? this.lastUpdated,
      cellId: identical(cellId, _kUndef)
          ? this.cellId          : cellId          as String?,
      wilayaCode: identical(wilayaCode, _kUndef)
          ? this.wilayaCode      : wilayaCode      as int?,
      geoHash: identical(geoHash, _kUndef)
          ? this.geoHash         : geoHash         as String?,
      lastCellUpdate: identical(lastCellUpdate, _kUndef)
          ? this.lastCellUpdate  : lastCellUpdate  as DateTime?,
      profileImageUrl: identical(profileImageUrl, _kUndef)
          ? this.profileImageUrl : profileImageUrl as String?,
      fcmToken: identical(fcmToken, _kUndef)
          ? this.fcmToken        : fcmToken        as String?,
      profession: identical(profession, _kUndef)
          ? this.profession      : profession      as String?,
      isOnline:      isOnline      ?? this.isOnline,
      averageRating: averageRating ?? this.averageRating,
      ratingCount:   ratingCount   ?? this.ratingCount,
      ratingSum:     ratingSum     ?? this.ratingSum,
      jobsCompleted: jobsCompleted ?? this.jobsCompleted,
      responseRate:  responseRate  ?? this.responseRate,
      lastActiveAt: identical(lastActiveAt, _kUndef)
          ? this.lastActiveAt    : lastActiveAt    as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
    id, name, email, phoneNumber, role,
    latitude, longitude, lastUpdated,
    cellId, wilayaCode, geoHash, lastCellUpdate,
    profileImageUrl, fcmToken,
    profession, isOnline, averageRating, ratingCount,
    ratingSum, jobsCompleted, responseRate, lastActiveAt,
  ];

  @override
  String toString() =>
      'UserModel(id: $id, role: $role, name: $name'
      '${isWorker ? ", profession: $profession, isOnline: $isOnline" : ""})';
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de parsing de date
// Acceptent : DateTime, String ISO-8601, Map Firestore {_seconds, _nanoseconds}
// ─────────────────────────────────────────────────────────────────────────────

DateTime _parseDate(dynamic value) {
  if (value == null)         return DateTime.now();
  if (value is DateTime)     return value;
  if (value is String)       return DateTime.tryParse(value) ?? DateTime.now();
  if (value is Map) {
    final s = value['_seconds'] as int?;
    if (s != null) return DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }
  return DateTime.now();
}

DateTime? _parseDateOrNull(dynamic value) {
  if (value == null)         return null;
  if (value is DateTime)     return value;
  if (value is String)       return DateTime.tryParse(value);
  if (value is Map) {
    final s = value['_seconds'] as int?;
    if (s != null) return DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }
  return null;
}
