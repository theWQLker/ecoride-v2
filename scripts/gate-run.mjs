#!/usr/bin/env node
// Oracles de vérification pour GATES.md (CP5).
// Chaque sous-commande imprime un jeton de succès unique et sort 0,
// ou imprime le détail de l'écart et sort 1.
//
// Cible : le conteneur MySQL 8.4 du projet, sur une base SCRATCH dédiée.
// La base applicative `ecoride` n'est jamais touchée.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const CONTAINER = 'ecoride-v2-mysql-1';
const SCRATCH = 'ecoride_gatecheck';

function rootPw() {
  const env = readFileSync(new URL('../.env', import.meta.url), 'utf8');
  const m = env.match(/^MYSQL_ROOT_PASSWORD=(.*)$/m);
  if (!m) throw new Error('MYSQL_ROOT_PASSWORD absent de .env');
  return m[1].trim();
}

// Exécute du SQL dans le conteneur. `stdinFile` permet de jouer un fichier .sql.
function mysql(sql, { db = SCRATCH, stdinFile = null, tolerate = false } = {}) {
  const args = ['exec', '-i', CONTAINER, 'mysql', `-uroot`, `-p${rootPw()}`,
                '--default-character-set=utf8mb4', '-N', '-B'];
  if (db) args.push(db);
  try {
    return execFileSync('docker', args, {
      input: stdinFile ? readFileSync(stdinFile) : sql,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (e) {
    if (tolerate) return (e.stdout || '') + (e.stderr || '');
    const out = (e.stdout || '') + (e.stderr || '');
    throw new Error(out.trim() || e.message);
  }
}

function q(sql) { return mysql(sql).trim(); }

// Reconstruit la base scratch depuis les deux fichiers livrés.
function rebuild() {
  mysql(`DROP DATABASE IF EXISTS ${SCRATCH}; CREATE DATABASE ${SCRATCH}
         CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`, { db: null });
  mysql(null, { stdinFile: 'db/schema.sql' });
  mysql(null, { stdinFile: 'db/seed.sql' });
}

function ok(token) { console.log(token); process.exit(0); }
function fail(msg) { console.error(msg); process.exit(1); }

const checks = {
  // G1 — deux passes consécutives schema+seed sur base déjà peuplée.
  pass2() {
    rebuild();              // passe 1
    mysql(null, { stdinFile: 'db/schema.sql' });
    mysql(null, { stdinFile: 'db/seed.sql' });   // passe 2
    const n = q('SELECT COUNT(*) FROM users');
    if (n !== '9') return fail(`passe 2 : ${n} users au lieu de 9`);
    ok('G1_PASS2_OK');
  },

  // G2 — solde de chaque user = somme de ses mouvements (lignes user_id NULL exclues).
  solde() {
    rebuild();
    const bad = q(`SELECT GROUP_CONCAT(CONCAT(id,':',credits,'<>',s))
      FROM (SELECT u.id, u.credits,
                   COALESCE((SELECT SUM(m.montant) FROM mouvements_credits m
                             WHERE m.user_id = u.id),0) AS s
            FROM users u) t WHERE credits <> s`);
    if (bad && bad !== 'NULL') return fail(`écarts de solde : ${bad}`);
    ok('G2_SOLDE_OK');
  },

  // G3 — commissions : toutes à user_id NULL, et total = 2 x nombre de trajets.
  commission() {
    rebuild();
    const nonNull = q(`SELECT COUNT(*) FROM mouvements_credits
                       WHERE type='commission' AND user_id IS NOT NULL`);
    if (nonNull !== '0') return fail(`${nonNull} ligne(s) commission avec user_id non NULL`);
    const total = q(`SELECT COALESCE(SUM(montant),0) FROM mouvements_credits WHERE type='commission'`);
    const trajets = q(`SELECT COUNT(*) FROM trajets`);
    const attendu = 2 * Number(trajets);
    if (Number(total) !== attendu) {
      return fail(`commissions = ${total}, attendu 2 x ${trajets} trajets = ${attendu}`);
    }
    ok('G3_COMMISSION_OK');
  },

  // G4 — US7 : toute dotation vaut exactement 20 crédits.
  dotation() {
    rebuild();
    const bad = q(`SELECT GROUP_CONCAT(CONCAT('user ',user_id,'=',montant))
                   FROM mouvements_credits WHERE type='dotation' AND montant <> 20`);
    if (bad && bad !== 'NULL') return fail(`dotation(s) hors 20 crédits : ${bad}`);
    const n = q(`SELECT COUNT(*) FROM mouvements_credits WHERE type='dotation'`);
    if (n === '0') return fail('aucune dotation trouvée');
    ok('G4_DOTATION_OK');
  },

  // G5 — colonne users.deleted_at : DATETIME, NULL autorisé, défaut NULL.
  deletedat() {
    rebuild();
    const r = q(`SELECT CONCAT(DATA_TYPE,'|',IS_NULLABLE,'|',IFNULL(COLUMN_DEFAULT,'NULL'))
                 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA='${SCRATCH}' AND TABLE_NAME='users'
                   AND COLUMN_NAME='deleted_at'`);
    if (r !== 'datetime|YES|NULL') return fail(`deleted_at = "${r}", attendu "datetime|YES|NULL"`);
    ok('G5_DELETEDAT_OK');
  },

  // G6 — contrôle négatif : un trajet avec la voiture d'un autre chauffeur DOIT être rejeté.
  // On vérifie d'abord qu'un trajet légitime passe (contrôle positif), pour ne pas
  // confondre "rejet correct" et "insert cassé pour une autre raison".
  fkcomposite() {
    rebuild();
    // Contrôle positif : véhicule 1 appartient au chauffeur 4 -> doit passer.
    const bon = mysql(`INSERT INTO trajets
      (chauffeur_id, vehicule_id, ville_depart, ville_arrivee, depart_at, arrivee_at, prix, places_restantes, statut)
      VALUES (4, 1, 'A', 'B', '2026-04-01 08:00:00', '2026-04-01 09:00:00', 5, 3, 'publie');
      SELECT 'INSERT_LEGITIME_OK';`, { tolerate: true });
    if (!bon.includes('INSERT_LEGITIME_OK')) {
      return fail(`contrôle positif échoué, la FK rejette un trajet pourtant valide :\n${bon}`);
    }
    // Contrôle négatif : véhicule 1 (Sophie, 4) attribué au chauffeur 6 -> doit être rejeté.
    const mauvais = mysql(`INSERT INTO trajets
      (chauffeur_id, vehicule_id, ville_depart, ville_arrivee, depart_at, arrivee_at, prix, places_restantes, statut)
      VALUES (6, 1, 'X', 'Y', '2026-04-02 08:00:00', '2026-04-02 09:00:00', 5, 3, 'publie');`,
      { tolerate: true });
    const m = mauvais.match(/ERROR (\d+)/);
    if (!m) return fail(`le trajet avec la voiture d'un autre a été ACCEPTÉ :\n${mauvais}`);
    console.log(`code d'erreur observé : ERROR ${m[1]}`);
    ok('G6_FK_REJECTED_OK');
  },

  // G7 — tout trajet roule avec un véhicule de son propre chauffeur.
  proprio() {
    rebuild();
    const bad = q(`SELECT GROUP_CONCAT(CONCAT('trajet ',t.id))
                   FROM trajets t JOIN vehicules v ON v.id = t.vehicule_id
                   WHERE v.user_id <> t.chauffeur_id`);
    if (bad && bad !== 'NULL') return fail(`véhicule d'un autre chauffeur : ${bad}`);
    const n = q('SELECT COUNT(*) FROM trajets');
    if (n !== '8') return fail(`${n} trajets au lieu de 8`);
    ok('G7_PROPRIO_OK');
  },

  // G8 — les 5 statuts de réservation restent représentés.
  statuts() {
    rebuild();
    // GROUP_CONCAT(... ORDER BY) sur un ENUM trie par position ordinale,
    // pas alphabétiquement : on compare donc des ensembles, pas des chaînes.
    const got = q(`SELECT DISTINCT statut FROM reservations`)
      .split('\n').map(s => s.trim()).filter(Boolean).sort();
    const want = ['acceptee', 'annulee', 'en_attente', 'refusee', 'terminee'];
    const manquants = want.filter(s => !got.includes(s));
    if (manquants.length) {
      return fail(`statut(s) absent(s) : ${manquants.join(', ')} — présents : ${got.join(', ')}`);
    }
    ok('G8_STATUTS_OK');
  },

  // G9 — aucun solde négatif.
  negatif() {
    rebuild();
    const bad = q(`SELECT GROUP_CONCAT(CONCAT(pseudo,'=',credits))
                   FROM users WHERE credits < 0`);
    if (bad && bad !== 'NULL') return fail(`solde(s) négatif(s) : ${bad}`);
    ok('G9_NEGATIF_OK');
  },

  // G10 — places_restantes = capacité - réservations occupantes.
  places() {
    rebuild();
    const bad = q(`SELECT GROUP_CONCAT(CONCAT('trajet ',id,' declare ',places_restantes,' calcule ',calc))
      FROM (SELECT t.id, t.places_restantes,
                   v.places - (SELECT COUNT(*) FROM reservations r
                               WHERE r.trajet_id=t.id AND r.statut IN ('acceptee','terminee')) AS calc
            FROM trajets t JOIN vehicules v ON v.id=t.vehicule_id) x
      WHERE places_restantes <> calc`);
    if (bad && bad !== 'NULL') return fail(`places_restantes incohérent : ${bad}`);
    ok('G10_PLACES_OK');
  },

  // G11 — volumétrie conforme au cahier des charges CP5.
  comptes() {
    rebuild();
    const attendu = {
      admin: ["SELECT COUNT(*) FROM users WHERE type_compte='admin'", '1'],
      employes: ["SELECT COUNT(*) FROM users WHERE type_compte='employe'", '2'],
      utilisateurs: ["SELECT COUNT(*) FROM users WHERE type_compte='utilisateur'", '6'],
      chauffeurs: ['SELECT COUNT(*) FROM users WHERE est_chauffeur=TRUE', '3'],
      vehicules: ['SELECT COUNT(*) FROM vehicules', '4'],
      electrique: ["SELECT COUNT(*) FROM vehicules WHERE energie='electrique'", '1'],
      trajets: ['SELECT COUNT(*) FROM trajets', '8'],
      dates: ['SELECT COUNT(DISTINCT DATE(depart_at)) FROM trajets', '3'],
      complets: ['SELECT COUNT(*) FROM trajets WHERE places_restantes=0', '2'],
      avis: ['SELECT COUNT(*) FROM avis', '3'],
      avis_attente: ["SELECT COUNT(*) FROM avis WHERE statut_moderation='en_attente'", '1'],
      litiges: ["SELECT COUNT(*) FROM litiges WHERE statut='ouvert'", '1'],
    };
    const ecarts = [];
    for (const [nom, [sql, want]] of Object.entries(attendu)) {
      const got = q(sql);
      if (got !== want) ecarts.push(`${nom}=${got} (attendu ${want})`);
    }
    if (ecarts.length) return fail(`volumétrie : ${ecarts.join(', ')}`);
    ok('G11_COMPTES_OK');
  },

  // G12 — les deux fichiers sont bien commités et l'arbre est propre pour db/.
  commit() {
    const tracked = execFileSync('git', ['ls-files', 'db/schema.sql', 'db/seed.sql'],
      { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
    if (tracked.length !== 2) return fail(`fichiers suivis par git : ${tracked.join(', ') || 'aucun'}`);
    const dirty = execFileSync('git', ['status', '--porcelain', 'db/'],
      { encoding: 'utf8' }).trim();
    if (dirty) return fail(`db/ non commité :\n${dirty}`);
    ok('G12_COMMIT_OK');
  },
};

const name = process.argv[2];
if (!checks[name]) {
  console.error(`sous-commande inconnue : ${name}\nconnues : ${Object.keys(checks).join(', ')}`);
  process.exit(2);
}
try {
  checks[name]();
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
