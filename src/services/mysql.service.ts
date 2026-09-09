import mysql from 'mysql2/promise';
import type { Pool } from 'mysql2/promise';
import { env } from '../config/env.js';

/**
 * Pool de connexions MySQL.
 *
 * « Pool » = réserve de connexions ouvertes et réutilisées. Ouvrir une connexion
 * coûte cher ; on en garde quelques-unes prêtes plutôt que d'en ouvrir une par requête.
 *
 * Création paresseuse (lazy) : le pool n'est créé qu'au premier appel réel.
 * Conséquence : si MySQL est éteint, l'application démarre quand même. Elle
 * n'échoue que sur les routes qui ont vraiment besoin de SQL.
 */
let pool: Pool | null = null;

/** Retourne le pool, en le créant au premier appel. */
export function getPool(): Pool {
  if (pool === null) {
    pool = mysql.createPool({
      host: env.mysql.host,
      port: env.mysql.port,
      user: env.mysql.user,
      password: env.mysql.password,
      database: env.mysql.database,
      waitForConnections: true,
      connectionLimit: env.mysql.connectionLimit,
      queueLimit: 0,
      // Empêche mysql2 de convertir DATE/DATETIME en objets Date JS.
      // On garde les chaînes brutes : moins de surprises de fuseau horaire.
      dateStrings: true,
    });
  }
  return pool;
}

/**
 * Vérifie que MySQL répond. Ne lève jamais d'erreur.
 * Utilisé par la route de santé (health check).
 */
export async function pingMysql(): Promise<boolean> {
  try {
    const connection = await getPool().getConnection();
    try {
      await connection.ping();
      return true;
    } finally {
      connection.release();
    }
  } catch {
    return false;
  }
}

/** Ferme le pool. Appelé à l'arrêt du serveur. */
export async function closePool(): Promise<void> {
  if (pool !== null) {
    await pool.end();
    pool = null;
  }
}
