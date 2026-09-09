import type { Request, Response } from 'express';

/** GET / — page d'accueil. Confirme que le squelette tourne. */
export function showHome(_req: Request, res: Response): void {
  res.render('home.njk', { message: 'EcoRide V2 OK' });
}
