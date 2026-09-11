import type { Request, Response } from 'express';
import { pingMysql } from '../services/mysql.service.js';
import { pingMongo } from '../services/mongo.service.js';

/**
 * GET /health — état des dépendances.
 *
 * Le code HTTP est ASYMÉTRIQUE, et c'est volontaire :
 *
 *   MySQL absent  → 503. Sans lui il n'y a ni comptes ni trajets :
 *                   l'application n'a plus rien à servir.
 *   Mongo absent  → 200. Il ne manque que les préférences de voyage ;
 *                   tout le reste fonctionne, on signale par un drapeau.
 *
 * Un orchestrateur (Docker, Kubernetes, load balancer) lit ce code pour
 * décider s'il envoie du trafic. Renvoyer 200 sans MySQL enverrait des
 * utilisateurs sur une instance incapable de répondre.
 */
export async function showHealth(_req: Request, res: Response): Promise<void> {
  const [mysql, mongo] = await Promise.all([pingMysql(), pingMongo()]);

  // Seul MySQL est critique. Mongo dégrade, il ne casse pas.
  const status = mysql ? 'ok' : 'unavailable';

  res.status(mysql ? 200 : 503).json({
    status,
    services: { mysql, mongo },
    // `degraded` reste à false quand MySQL est mort : à ce stade
    // l'application n'est pas dégradée, elle est hors service.
    degraded: mysql && !mongo,
  });
}
