import { createApp } from './app.js';
import { env } from './config/env.js';
import { closePool } from './services/mysql.service.js';
import { closeMongo } from './services/mongo.service.js';

const app = createApp();

const server = app.listen(env.port, () => {
  console.log(`[ecoride] http://localhost:${env.port} (${env.nodeEnv})`);
});

/**
 * Arrêt propre : on ferme le serveur HTTP puis les connexions DB.
 * Sans ça, docker compose down attend 10 s avant de tuer le conteneur.
 */
async function shutdown(signal: string): Promise<void> {
  console.log(`[ecoride] ${signal} reçu, arrêt en cours…`);
  server.close();
  await Promise.allSettled([closePool(), closeMongo()]);
  process.exit(0);
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
