-- =====================================================================
-- EcoRide V2 — Schéma relationnel (MySQL 8.4 / InnoDB / utf8mb4)
-- ---------------------------------------------------------------------
-- Fichier REJOUABLE : les DROP en tête permettent de le relancer
-- autant de fois que nécessaire sans erreur.
--
-- Contenu : DDL uniquement. Aucune logique métier (pas de trigger,
-- pas de procédure stockée, pas de vue).
-- =====================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ---------------------------------------------------------------------
-- Nettoyage — ordre inverse des dépendances.
-- FOREIGN_KEY_CHECKS est désactivé le temps des DROP : cela évite
-- d'avoir à respecter un ordre parfait si le schéma évolue plus tard.
-- ---------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS mouvements_credits;
DROP TABLE IF EXISTS litiges;
DROP TABLE IF EXISTS avis;
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS trajets;
DROP TABLE IF EXISTS vehicules;
DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- users — comptes de la plateforme.
-- Un même compte peut être passager ET chauffeur : d'où deux booléens
-- distincts plutôt qu'un unique champ "rôle".
-- =====================================================================
CREATE TABLE users (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  pseudo         VARCHAR(50)  NOT NULL,
  email          VARCHAR(180) NOT NULL,
  -- Hash bcrypt : toujours 60 caractères, jamais le mot de passe en clair.
  mot_de_passe   CHAR(60)     NOT NULL,
  type_compte    ENUM('utilisateur','employe','admin') NOT NULL DEFAULT 'utilisateur',
  est_passager   BOOLEAN      NOT NULL DEFAULT TRUE,
  est_chauffeur  BOOLEAN      NOT NULL DEFAULT FALSE,
  -- 20 crédits offerts à l'inscription (règle EcoRide).
  credits        INT          NOT NULL DEFAULT 20,
  suspendu       BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Anonymisation RGPD : on ne supprime jamais la ligne (elle porte
  -- l'historique des trajets et la comptabilité), on l'horodate ici.
  -- NULL = compte actif. Colonne seulement : aucune logique associée.
  deleted_at     DATETIME     NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_pseudo (pseudo),
  UNIQUE KEY uq_users_email  (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- vehicules — voitures déclarées par les chauffeurs.
-- =====================================================================
CREATE TABLE vehicules (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         INT UNSIGNED NOT NULL,
  immatriculation VARCHAR(15)  NOT NULL,
  date_immat      DATE         NOT NULL,
  marque          VARCHAR(50)  NOT NULL,
  modele          VARCHAR(50)  NOT NULL,
  couleur         VARCHAR(30)  NOT NULL,
  energie         ENUM('electrique','hybride','thermique') NOT NULL,
  -- Places passagers proposables, chauffeur non compris.
  places          INT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_vehicules_immatriculation (immatriculation),
  -- Redondant avec la clé primaire seule, mais indispensable : c'est la
  -- cible de la clé étrangère composite de `trajets`, qui garantit qu'un
  -- chauffeur ne publie qu'avec SES propres véhicules.
  UNIQUE KEY uq_vehicules_id_user (id, user_id),
  KEY idx_vehicules_user (user_id),
  -- ON DELETE CASCADE : un véhicule n'a aucun sens sans son propriétaire.
  -- Supprimer le compte supprime ses véhicules.
  CONSTRAINT fk_vehicules_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- trajets — covoiturages publiés par un chauffeur.
-- =====================================================================
CREATE TABLE trajets (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  chauffeur_id    INT UNSIGNED NOT NULL,
  vehicule_id     INT UNSIGNED NOT NULL,
  ville_depart    VARCHAR(100) NOT NULL,
  ville_arrivee   VARCHAR(100) NOT NULL,
  depart_at       DATETIME     NOT NULL,
  arrivee_at      DATETIME     NOT NULL,
  -- Prix en crédits EcoRide (pas en euros).
  prix            INT UNSIGNED NOT NULL,
  places_restantes INT UNSIGNED NOT NULL,
  statut          ENUM('publie','demarre','termine','annule') NOT NULL DEFAULT 'publie',
  PRIMARY KEY (id),
  -- ON DELETE CASCADE : supprimer un chauffeur retire ses annonces.
  CONSTRAINT fk_trajets_chauffeur
    FOREIGN KEY (chauffeur_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  -- RÈGLE MÉTIER : un trajet n'utilise que le véhicule de SON chauffeur.
  -- La clé étrangère porte sur le COUPLE (véhicule, chauffeur) : le SGBD
  -- rejette donc un trajet publié avec la voiture de quelqu'un d'autre.
  -- ON DELETE RESTRICT : un véhicule engagé dans un trajet ne peut pas
  -- être supprimé — on préserve l'historique des covoiturages.
  CONSTRAINT fk_trajets_vehicule_proprietaire
    FOREIGN KEY (vehicule_id, chauffeur_id) REFERENCES vehicules (id, user_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  KEY idx_trajets_chauffeur (chauffeur_id),
  KEY idx_trajets_vehicule  (vehicule_id),
  -- Index principal de la recherche voyageur :
  -- "départ → arrivée à telle date".
  KEY idx_trajets_recherche (ville_depart, ville_arrivee, depart_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- reservations — participation d'un passager à un trajet.
-- =====================================================================
CREATE TABLE reservations (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  trajet_id   INT UNSIGNED NOT NULL,
  passager_id INT UNSIGNED NOT NULL,
  -- Cycle de vie complet d'une réservation (décision crédits 2026-09-11).
  -- Une annulation tardive ne rend pas la place : d'où un statut distinct.
  statut      ENUM('en_attente','confirmee','refusee','annulee','annulee_tardive',
                   'terminee','a_regulariser','en_litige','cloturee','remboursee')
              NOT NULL DEFAULT 'en_attente',
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Horodatage de l'annulation : c'est lui qui, comparé à depart_at,
  -- sépare une annulation normale d'une annulation tardive.
  annulee_at  DATETIME NULL DEFAULT NULL,
  -- Déclaration d'arrivée par le passager : point de départ du délai
  -- de 48 h au terme duquel la réservation peut être clôturée.
  arrivee_declaree_at DATETIME NULL DEFAULT NULL,
  -- Clôture effective : c'est elle qui déclenche la commission.
  cloturee_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  -- Un passager ne réserve qu'une seule fois le même trajet.
  UNIQUE KEY uq_reservations_trajet_passager (trajet_id, passager_id),
  KEY idx_reservations_passager (passager_id),
  -- ON DELETE CASCADE : la réservation n'existe que par son trajet.
  CONSTRAINT fk_reservations_trajet
    FOREIGN KEY (trajet_id) REFERENCES trajets (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  -- ON DELETE CASCADE : idem côté passager.
  CONSTRAINT fk_reservations_passager
    FOREIGN KEY (passager_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- avis — note laissée par le passager, soumise à modération employé.
-- =====================================================================
CREATE TABLE avis (
  id                 INT UNSIGNED NOT NULL AUTO_INCREMENT,
  -- UNIQUE : un seul avis par réservation.
  reservation_id     INT UNSIGNED NOT NULL,
  note               INT UNSIGNED NOT NULL,
  commentaire        TEXT NULL,
  statut_moderation  ENUM('en_attente','valide','refuse') NOT NULL DEFAULT 'en_attente',
  PRIMARY KEY (id),
  UNIQUE KEY uq_avis_reservation (reservation_id),
  -- Note sur 5. CHECK réellement appliqué depuis MySQL 8.0.16.
  CONSTRAINT ck_avis_note CHECK (note BETWEEN 1 AND 5),
  -- ON DELETE CASCADE : l'avis disparaît avec la réservation notée.
  CONSTRAINT fk_avis_reservation
    FOREIGN KEY (reservation_id) REFERENCES reservations (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- litiges — signalement traité par un employé.
-- =====================================================================
CREATE TABLE litiges (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  reservation_id INT UNSIGNED NOT NULL,
  description    TEXT NOT NULL,
  -- Les dossiers « à régulariser » rejoignent la même file que les
  -- incidents signalés : une seule table, deux origines possibles.
  origine        ENUM('signalement_passager','regularisation') NOT NULL,
  statut         ENUM('ouvert','resolu') NOT NULL DEFAULT 'ouvert',
  -- NULL tant qu'aucun employé n'a pris le dossier en charge.
  employe_id     INT UNSIGNED NULL,
  PRIMARY KEY (id),
  KEY idx_litiges_reservation (reservation_id),
  KEY idx_litiges_employe (employe_id),
  -- ON DELETE CASCADE : plus de réservation, plus de litige associé.
  CONSTRAINT fk_litiges_reservation
    FOREIGN KEY (reservation_id) REFERENCES reservations (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  -- ON DELETE SET NULL : le départ d'un employé ne doit pas effacer
  -- le litige ; le dossier redevient simplement non assigné.
  CONSTRAINT fk_litiges_employe
    FOREIGN KEY (employe_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- mouvements_credits — journal des crédits (grand livre).
-- montant est SIGNÉ : négatif = sortie, positif = entrée.
-- La somme des montants d'un utilisateur reconstitue son solde.
-- =====================================================================
CREATE TABLE mouvements_credits (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  -- NULL = mouvement de la PLATEFORME et non d'un utilisateur : c'est le
  -- cas des commissions, qui n'alimentent aucun compte (pas même l'admin).
  user_id        INT UNSIGNED NULL,
  -- NULL pour les mouvements hors réservation (ex. dotation d'inscription).
  reservation_id INT UNSIGNED NULL,
  montant        INT NOT NULL,
  type           ENUM('dotation','debit_reservation','commission',
                      'transfert_chauffeur','remboursement') NOT NULL,
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_mouvements_user (user_id),
  KEY idx_mouvements_reservation (reservation_id),
  -- ON DELETE CASCADE : le journal suit le compte auquel il appartient.
  -- Les lignes de commission (user_id NULL) ne sont, elles, jamais emportées.
  CONSTRAINT fk_mouvements_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  -- ON DELETE SET NULL : on conserve la trace comptable même si la
  -- réservation d'origine est supprimée.
  CONSTRAINT fk_mouvements_reservation
    FOREIGN KEY (reservation_id) REFERENCES reservations (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
