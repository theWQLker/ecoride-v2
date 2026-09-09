import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import type { Express } from 'express';
import helmet from 'helmet';
import nunjucks from 'nunjucks';
import { router } from './routes/index.js';
import { errorHandler, notFound } from './middleware/error-handler.js';
import { isProduction } from './config/env.js';

const here = path.dirname(fileURLToPath(import.meta.url));
/** Racine du projet : un cran au-dessus de src/ (ou de dist/ une fois compilé). */
const projectRoot = path.resolve(here, '..');

/**
 * Construit l'application Express sans l'écouter.
 * Séparer app et serveur permet aux tests de l'importer sans ouvrir de port.
 */
export function createApp(): Express {
  const app = express();

  // helmet pose des en-têtes HTTP de sécurité (anti-clickjacking, anti-sniffing…).
  app.use(helmet());

  // Les templates restent en .njk dans src/ : ils ne sont pas compilés par tsc.
  nunjucks.configure(path.join(projectRoot, 'src', 'views'), {
    autoescape: true, // échappe le HTML des variables : première défense anti-XSS
    express: app,
    noCache: !isProduction, // rechargement à chaud en développement
  });
  app.set('view engine', 'njk');

  // Lecture des formulaires HTML et du JSON.
  app.use(express.urlencoded({ extended: false }));
  app.use(express.json());

  // Fichiers statiques : CSS, images, et le JS front compilé par esbuild.
  app.use(express.static(path.join(projectRoot, 'public')));

  app.use(router);

  // Toujours en dernier, et dans cet ordre.
  app.use(notFound);
  app.use(errorHandler);

  return app;
}
