import {
  Controller,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { FirebaseAuthGuard }             from '../../common/guards/firebase-auth.guard';
import { CurrentUser }                   from '../../common/decorators/current-user.decorator';
import { AuthUser }                      from '../../common/guards/firebase-auth.guard';
import { AuthService, UserCheckResult }  from './auth.service';

@Controller('auth')
@UseGuards(FirebaseAuthGuard)
export class AuthController {
  private readonly logger = new Logger(AuthController.name);

  constructor(private readonly authService: AuthService) {}

  /**
   * GET /auth/check?uid=:uid
   *
   * Appelé immédiatement après Firebase signInWithCredential pour déterminer
   * si l'utilisateur authentifié possède déjà un profil backend.
   *
   * Réponse :
   *   • { isNewUser: true,  role: null }     → rediriger vers /role-selection
   *   • { isNewUser: false, role: 'client' } → rediriger vers /home
   *   • { isNewUser: false, role: 'worker' } → rediriger vers /home (app worker)
   *
   * Sécurité :
   *   Le paramètre uid DOIT correspondre à user.uid du JWT.
   *   Un utilisateur ne peut pas interroger le statut d'un autre compte.
   *
   * Rate limiting :
   *   10 req/min par UID — empêche l'énumération et protège le compte Firebase billing.
   */
  @Get('check')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async check(
    @Query('uid') uid: string,
    @CurrentUser() user: AuthUser,
  ): Promise<UserCheckResult> {
    if (!uid?.trim()) {
      throw new ForbiddenException('uid query parameter is required');
    }
    if (uid !== user.uid) {
      this.logger.warn(
        `Auth check UID mismatch — JWT uid=${user.uid} vs query uid=${uid}`,
      );
      throw new ForbiddenException('UID mismatch — you may only check your own account');
    }

    return this.authService.checkUser(uid);
  }
}
