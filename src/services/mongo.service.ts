import { MongoClient } from 'mongodb';
import type { Db } from 'mongodb';
import { env } from '../config/env.js';

/**
 * Service MongoDB avec dégradation gracieuse.
 *
 * « Dégradation gracieuse » = quand Mongo est indisponible, l'application
 * continue de fonctionner en mode réduit au lieu de renvoyer une erreur 500.
 * Sur EcoRide, Mongo stocke des données secondaires (préférences, avis) :
 * les perdre temporairement doit dégrader l'expérience, pas casser le site.
 *
 * Deux garde-fous :
 *   1. Connexion paresseuse — rien ne se connecte au démarrage du serveur.
 *   2. Timeout court (3 s par défaut) — un Mongo injoignable ne fait pas
 *      attendre l'utilisateur 30 secondes.
 */

let client: MongoClient | null = null;
/** Promesse de connexion en cours, pour ne pas lancer 10 connexions en parallèle. */
let connecting: Promise<Db | null> | null = null;

/** Instant (ms) après lequel on réessaiera une connexion échouée. */
let retryAfter = 0;
/** Délai d'attente avant nouvelle tentative après un échec. */
const RETRY_COOLDOWN_MS = 10_000;

async function connect(): Promise<Db | null> {
  const candidate = new MongoClient(env.mongo.uri, {
    // Temps max pour trouver un serveur Mongo joignable.
    serverSelectionTimeoutMS: env.mongo.timeoutMs,
    connectTimeoutMS: env.mongo.timeoutMs,
    socketTimeoutMS: env.mongo.timeoutMs,
  });

  try {
    await candidate.connect();
    client = candidate;
    retryAfter = 0;
    return candidate.db(env.mongo.database);
  } catch (error) {
    // On ferme proprement le client raté pour ne pas fuiter de sockets.
    await candidate.close().catch(() => undefined);
    client = null;
    retryAfter = Date.now() + RETRY_COOLDOWN_MS;
    console.warn(
      '[mongo] connexion indisponible, mode dégradé actif :',
      error instanceof Error ? error.message : String(error),
    );
    return null;
  }
}

/**
 * Retourne la base Mongo, ou `null` si elle est injoignable.
 *
 * L'appelant DOIT gérer le cas `null`. C'est volontaire : le type force
 * à écrire le chemin dégradé au lieu de l'oublier.
 */
export async function getDb(): Promise<Db | null> {
  if (client !== null) {
    return client.db(env.mongo.database);
  }

  // Échec récent : on ne martèle pas un serveur qu'on sait éteint.
  if (Date.now() < retryAfter) {
    return null;
  }

  connecting ??= connect().finally(() => {
    connecting = null;
  });

  return connecting;
}

/** Vérifie que Mongo répond. Ne lève jamais d'erreur. */
export async function pingMongo(): Promise<boolean> {
  const db = await getDb();
  if (db === null) return false;

  try {
    await db.command({ ping: 1 });
    return true;
  } catch {
    // La connexion a été perdue après coup : on repart de zéro au prochain appel.
    client = null;
    retryAfter = Date.now() + RETRY_COOLDOWN_MS;
    return false;
  }
}

/** Ferme la connexion. Appelé à l'arrêt du serveur. */
export async function closeMongo(): Promise<void> {
  if (client !== null) {
    await client.close();
    client = null;
  }
}
