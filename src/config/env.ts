/**
 * Lecture centralisée des variables d'environnement.
 *
 * Règle : aucun secret en dur dans le code. Tout passe par process.env,
 * alimenté par le fichier .env (jamais commité) ou par docker compose.
 */

/** Lit une variable obligatoire. Lève une erreur si elle manque. */
function required(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === '') {
    throw new Error(`Variable d'environnement manquante : ${name}`);
  }
  return value;
}

/** Lit une variable optionnelle, avec une valeur par défaut. */
function optional(name: string, fallback: string): string {
  const value = process.env[name];
  return value === undefined || value === '' ? fallback : value;
}

/** Lit une variable numérique optionnelle. */
function optionalInt(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed)) {
    throw new Error(`Variable d'environnement invalide : ${name} doit être un entier`);
  }
  return parsed;
}

export const env = {
  nodeEnv: optional('NODE_ENV', 'development'),
  port: optionalInt('PORT', 3000),

  mysql: {
    host: optional('MYSQL_HOST', 'localhost'),
    port: optionalInt('MYSQL_PORT', 3306),
    user: optional('MYSQL_USER', 'ecoride'),
    password: optional('MYSQL_PASSWORD', ''),
    database: optional('MYSQL_DATABASE', 'ecoride'),
    connectionLimit: optionalInt('MYSQL_POOL_LIMIT', 10),
  },

  mongo: {
    uri: optional('MONGO_URI', 'mongodb://localhost:27017'),
    database: optional('MONGO_DATABASE', 'ecoride'),
    timeoutMs: optionalInt('MONGO_TIMEOUT_MS', 3000),
  },
} as const;

export const isProduction = env.nodeEnv === 'production';

// `required` n'est pas encore utilisé : le squelette n'a aucun secret obligatoire.
// Il le deviendra dès la première variable critique (JWT_SECRET, par exemple).
export { required };
