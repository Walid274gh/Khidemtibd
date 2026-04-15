// ══════════════════════════════════════════════════════════════════════════════
// AuthService
//
// DESIGN NOTE — Pourquoi ne pas utiliser UsersService ici ?
//
//   UsersModule imports AuthModule (pour FirebaseAuthGuard).
//   Si AuthModule importait UsersModule, on créerait une dépendance circulaire.
//
//   Solution : AuthService injecte UserModel directement via DatabaseModule
//   (@Global()), qui exporte MongooseModule.forFeature([User]). AuthModule
//   n'a donc pas besoin d'importer UsersModule.
//
//   Cette classe reste volontairement fine (single-responsibility) :
//   seule la vérification d'existence d'un profil lui appartient.
// ══════════════════════════════════════════════════════════════════════════════

import { Injectable, Logger } from '@nestjs/common';
import { InjectModel }        from '@nestjs/mongoose';
import { Model }              from 'mongoose';
import { User, UserDocument } from '../../schemas/user.schema';

export interface UserCheckResult {
  /** true si aucun profil MongoDB n'existe encore pour cet uid Firebase. */
  isNewUser: boolean;

  /**
   * Rôle actuel du profil : 'client' | 'worker'.
   * null si isNewUser === true.
   */
  role: string | null;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    @InjectModel(User.name)
    private readonly userModel: Model<UserDocument>,
  ) {}

  /**
   * Vérifie si un profil existe dans MongoDB pour l'uid Firebase donné.
   *
   * Appelé par AuthController immédiatement après signInWithCredential pour
   * décider si le client doit afficher le flow d'onboarding (nouveau) ou
   * naviguer directement vers l'accueil (utilisateur existant).
   */
  async checkUser(uid: string): Promise<UserCheckResult> {
    const doc = await this.userModel
      .findById(uid)
      .select('role')
      .lean()
      .exec();

    const result: UserCheckResult = {
      isNewUser: doc === null,
      role:      doc ? ((doc as unknown as { role: string }).role ?? null) : null,
    };

    if (result.isNewUser) {
      this.logger.log(`Auth check: new user uid=${uid} — onboarding required`);
    }

    return result;
  }
}
