import type { Request, Response } from 'express';
import { pingMysql } from '../services/mysql.service.js';
import { pingMongo } from '../services/mongo.service.js';

/**
 * GET /health — état des dépendances.
 *
 * Renvoie toujours 200 : le serveur répond, c'est l'information utile.
 * Le détail par datastore permet de voir si on tourne en mode dégradé.
 */
export async function showHealth(_req: Request, res: Response): Promise<void> {
  const [mysql, mongo] = await Promise.all([pingMysql(), pingMongo()]);

  res.json({
    status: 'ok',
    services: { mysql, mongo },
  });
}
