// ══════════════════════════════════════════════════════════════════════════════
// AuthModule
//
// RESPONSABILITÉS :
//   1. Fournit FirebaseAuthGuard (réexporté pour tous les modules qui l'importent)
//   2. Expose GET /auth/check — vérification post-signIn (nouveau utilisateur ?)
//
// PATTERN — éviter la dépendance circulaire :
//   UsersModule → importe AuthModule (pour FirebaseAuthGuard)
//   AuthModule  → N'importe PAS UsersModule
//   AuthService → injecte UserModel directement (DatabaseModule est @Global())
//
// Ce module est le point d'entrée unique de toute la logique d'authentification
// côté backend. Garder sa surface minimal et sa responsabilité bien délimitée.
// ══════════════════════════════════════════════════════════════════════════════

import { Module } from '@nestjs/common';
import { FirebaseAuthGuard } from '../../common/guards/firebase-auth.guard';
import { AuthController }    from './auth.controller';
import { AuthService }       from './auth.service';

@Module({
  controllers: [AuthController],
  providers:   [FirebaseAuthGuard, AuthService],
  exports:     [FirebaseAuthGuard],
})
export class AuthModule {}
