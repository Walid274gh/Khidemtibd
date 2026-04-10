// lib/models/worker_model.dart
//
// MIGRATION — COLLECTION UNIFIÉE
// ────────────────────────────────────────────────────────────────────────────
// WorkerModel est désormais un alias de type (typedef) pour UserModel.
//
// POURQUOI UN TYPEDEF ET NON UNE SUPPRESSION ?
//   • 100+ call sites utilisent WorkerModel (controllers, providers, services,
//     widgets). Les renommer tous en une seule PR est une opération risquée.
//   • `typedef WorkerModel = UserModel` offre une compatibilité totale :
//
//       WorkerModel.fromJson(json)  → UserModel.fromJson(json)    ✅
//       WorkerModel.fromMap(m, id)  → UserModel.fromMap(m, id)    ✅
//       worker.profession           → UserModel.profession         ✅
//       worker.isOnline             → UserModel.isOnline           ✅
//       worker.averageRating        → UserModel.averageRating      ✅
//       worker.copyWith(...)        → UserModel.copyWith(...)      ✅
//       worker is WorkerModel       → identique à is UserModel     ✅
//       WorkerModel?                → type annotation valide       ✅
//
// MIGRATION FUTURE
//   Lancer `dart fix --apply` ou un script sed pour remplacer `WorkerModel`
//   par `UserModel` dans tout le codebase, puis supprimer ce fichier.
//   L'opération est sûre, mécanique, et sans risque de régression.
//
// NOTE SUR daysSinceActive
//   Était un champ stocké dans l'ancienne classe WorkerModel (calculé dans
//   fromMap). C'est maintenant un getter calculé sur UserModel, ce qui est
//   plus correct : la valeur dépend de `DateTime.now()` et ne devrait pas
//   être figée dans un objet immuable.

import 'user_model.dart';

/// WorkerModel est un alias complet de UserModel.
///
/// Les documents workers ont `role == 'worker'` et un champ `profession`
/// non-null. Toutes leurs statistiques (averageRating, jobsCompleted, etc.)
/// sont portées par le même document UserModel.
typedef WorkerModel = UserModel;
