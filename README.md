# EcoRide V2 — squelette

Plateforme de covoiturage. Réécriture Node 22 + TypeScript de la V1 (PHP/Slim).

Le schéma relationnel est en place (voir [Base de données](#base-de-données)) ;
les routes métier et les vues au-delà du layout restent à construire.

## Stack

| Couche | Techno |
|---|---|
| Runtime | Node 22, TypeScript strict (ESM) |
| Serveur | Express 5 |
| Vues | Nunjucks |
| Front | TypeScript compilé par esbuild |
| SQL | MySQL 8 (`mysql2`, pool) |
| Documents | MongoDB 7 (connexion paresseuse, dégradation gracieuse) |
| Tests | Vitest + supertest |

## Prérequis

- Node 22 ou plus
- Docker et Docker Compose

## Démarrage avec Docker (recommandé)

```bash
cp .env.example .env    # puis remplir les mots de passe
docker compose up --build
```

L'application écoute sur http://localhost:3000

| Route | Réponse |
|---|---|
| `GET /` | page HTML « EcoRide V2 OK » |
| `GET /health` | JSON avec l'état de MySQL et Mongo |

Arrêt :

```bash
docker compose down          # garde les données
docker compose down -v       # supprime aussi les volumes
```

## Démarrage sans Docker

Les bases doivent tourner séparément. Dans `.env`, remplacer les hôtes
`mysql` et `mongo` par `localhost`.

```bash
npm install
npm run build:front
npm run dev
```

## Commandes

| Commande | Effet |
|---|---|
| `npm run dev` | serveur en rechargement automatique (tsx) |
| `npm run build` | compile serveur + front |
| `npm run build:front` | compile `src/front/*.ts` vers `public/js/` |
| `npm run typecheck` | vérifie les types sans produire de fichiers |
| `npm start` | lance la version compilée (`dist/`) |
| `npm test` | lance les tests Vitest |

## Structure

```
src/
├── config/env.ts        # lecture des variables d'environnement
├── controllers/         # un fichier par groupe de routes
├── middleware/          # erreurs, et plus tard auth / CSRF
├── models/              # (vide) accès aux données
├── routes/index.ts      # table des routes
├── services/            # mysql.service.ts, mongo.service.ts
├── views/               # templates Nunjucks
├── front/               # TypeScript navigateur → public/js/
├── app.ts               # construction de l'app Express
└── server.ts            # écoute du port, arrêt propre
```

## Architecture

```mermaid
flowchart TD
    A[Requête HTTP] --> B[app.ts]
    B --> C[helmet, urlencoded, static]
    C --> D[routes/index.ts]
    D --> E[controllers]
    E --> F[Nunjucks: layout.njk]
    F --> G[HTML]

    E -.-> H[mysql.service<br/>pool paresseux]
    E -.-> I[mongo.service<br/>timeout 3 s]
    H -.-> J[(MySQL 8)]
    I -.-> K[(Mongo 7)]
    I -.échec.-> L[mode dégradé:<br/>getDb retourne null]
```

## Base de données

| Fichier | Rôle |
|---|---|
| [`db/schema.sql`](db/schema.sql) | DDL MySQL 8.4, rejouable (`DROP IF EXISTS` en tête). **Source de vérité.** |
| [`db/seed.sql`](db/seed.sql) | jeu de données de démonstration, `INSERT` uniquement |
| [`db/mcd.mmd`](db/mcd.mmd) | **MCD** — diagramme entité-association (Mermaid `erDiagram`) |

Le MCD reflète exactement `schema.sql` : 7 tables, clés primaires, clés
étrangères et types. `schema.sql` fait foi — toute évolution du DDL doit être
reportée dans `db/mcd.mmd`.

```bash
# Création du schéma puis chargement des données de démonstration
docker compose exec -T mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ecoride < db/schema.sql
docker compose exec -T mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ecoride < db/seed.sql
```

Deux règles sont portées par le SGBD et non par le code applicatif :

- **un trajet n'utilise que le véhicule de son chauffeur** — clé étrangère
  composite `trajets (vehicule_id, chauffeur_id) → vehicules (id, user_id)` ;
  toute tentative contraire est rejetée en `ERROR 1452` ;
- **un compte n'est jamais supprimé** — `users.deleted_at` horodate
  l'anonymisation, afin de préserver l'historique et la comptabilité.

## Trois principes à connaître avant d'ajouter du code

**1. Aucune base ne bloque le démarrage.**
Le pool MySQL et le client Mongo se créent au premier usage réel, pas au boot.
Une base éteinte n'empêche pas le serveur de répondre.

**2. Les deux bases n'ont pas le même poids. C'est une décision d'architecture.**

| Base | Contient | Si elle tombe | `/health` |
|---|---|---|---|
| MySQL | comptes, trajets, réservations, crédits | plus rien à servir | **503** |
| MongoDB | préférences de voyage | le reste fonctionne | **200** + drapeau |

Sans MySQL il n'y a ni comptes ni trajets : l'application est morte, elle doit
le dire. Sans Mongo il manque seulement les préférences : on sert la page et on
signale la dégradation. Un load balancer lit ce code pour décider s'il envoie du
trafic — un 200 sans MySQL enverrait des utilisateurs dans le vide.

**3. `getDb()` retourne `Db | null`.**
Le type force à écrire le cas d'échec. Sur les données secondaires, un `null`
doit dégrader l'affichage, jamais renvoyer une erreur 500 :

```ts
const db = await getDb();
if (db === null) {
  // Mongo indisponible : on affiche le trajet sans les préférences
  // du chauffeur, plutôt que rien du tout.
  return { ...trajet, preferences: null };
}
```

Côté MySQL, l'inverse : une erreur remonte et devient un 500. Ne jamais
l'avaler silencieusement — une réservation perdue sans bruit est pire
qu'une erreur visible.

## Secrets

`.env` est ignoré par git (`**/.env` dans `.gitignore`). Seul `.env.example`
est commité, avec des valeurs factices. Aucun mot de passe ne doit apparaître
dans un fichier suivi.
