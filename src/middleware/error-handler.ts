import type { NextFunction, Request, Response } from 'express';
import { isProduction } from '../config/env.js';

/** Route inconnue → 404. Placé après toutes les routes. */
export function notFound(_req: Request, res: Response): void {
  res.status(404).json({ error: 'Not Found' });
}

/**
 * Gestionnaire d'erreurs global.
 *
 * Express reconnaît un gestionnaire d'erreurs à ses QUATRE paramètres.
 * Retirer `_next` casserait silencieusement le mécanisme : Express
 * traiterait la fonction comme un middleware ordinaire.
 */
export function errorHandler(
  error: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction,
): void {
  console.error('[error]', error);

  // En production, on ne divulgue jamais la trace interne au client.
  res.status(500).json({
    error: 'Internal Server Error',
    ...(isProduction ? {} : { detail: error instanceof Error ? error.message : String(error) }),
  });
}
