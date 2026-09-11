-- =====================================================================
-- EcoRide V2 — Jeu de données de démonstration
-- ---------------------------------------------------------------------
-- À exécuter APRÈS db/schema.sql.
-- INSERT uniquement, aucune logique métier.
--
-- MOTS DE PASSE (hashés bcrypt, coût 10) — valeurs en clair :
--   admin@ecoride.test .................... Admin1234!
--   tous les employés (@ecoride.test) ..... Employe1234!
--   tous les utilisateurs (@ecoride.test) . User1234!
-- Ce sont des comptes de test fictifs, destinés à la soutenance.
--
-- Convention de crédits retenue pour ce jeu de données :
--   - US7 : 20 crédits de dotation à l'inscription, pour TOUS les
--     utilisateurs, sans exception ;
--   - une réservation débite le passager du prix du trajet ;
--   - la plateforme prélève 2 crédits de commission par trajet. Ces
--     lignes portent user_id = NULL : la commission n'alimente aucun
--     compte, pas même celui de l'administrateur ;
--   - le reste (prix - 2) est transféré au chauffeur à la fin du trajet ;
--   - une annulation rembourse intégralement le passager.
--
-- Le nombre de réservations des passagers 7 et 8 est calibré pour que
-- leur solde reste positif avec 20 crédits de dotation seulement.
-- =====================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Vide les tables si le seed est rejoué sur un schéma déjà peuplé.
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE mouvements_credits;
TRUNCATE TABLE litiges;
TRUNCATE TABLE avis;
TRUNCATE TABLE reservations;
TRUNCATE TABLE trajets;
TRUNCATE TABLE vehicules;
TRUNCATE TABLE users;
SET FOREIGN_KEY_CHECKS = 1;


-- ---------------------------------------------------------------------
-- users — 1 admin, 2 employés, 6 utilisateurs (dont 3 chauffeurs).
-- La colonne `credits` est exactement la somme des mouvements de
-- l'utilisateur (lignes user_id NULL exclues, elles sont à la plateforme).
--   user 4 Sophie : 20 -10 +6 -7           =  9
--   user 5 Thomas : 20 +4  -7              = 17
--   user 6 Amina  : 20 +8  +8  +8          = 44
--   user 7 Lucas  : 20 -8  -6  +6          = 12
--   user 8 Chloe  : 20 -10 -7              =  3
--   user 9 Kevin  : 20 -6  -10             =  4
--   users 1,2,3   : ni dotation ni mouvement =  0
-- ---------------------------------------------------------------------
INSERT INTO users
  (id, pseudo, email, mot_de_passe, type_compte, est_passager, est_chauffeur, credits, suspendu, created_at)
VALUES
  -- Admin précréé — mot de passe : Admin1234!
  -- Solde nul : les commissions ne sont créditées à personne.
  (1, 'admin', 'admin@ecoride.test',
   '$2b$10$f3F8weSIBtt53cjfe4mU1O0ncXvBxbmZRqB5/Kx56C51EZoWESA32',
   'admin', FALSE, FALSE, 0, FALSE, '2026-01-05 09:00:00'),

  -- Employés — mot de passe : Employe1234!
  (2, 'employe.marie', 'marie.employe@ecoride.test',
   '$2b$10$ua9OMF8rnP.3yRGmo46eWeXAM8VxnE7EaAG4CQ7N0.OPBcj2xhW5O',
   'employe', FALSE, FALSE, 0, FALSE, '2026-01-08 10:30:00'),
  (3, 'employe.karim', 'karim.employe@ecoride.test',
   '$2b$10$ua9OMF8rnP.3yRGmo46eWeXAM8VxnE7EaAG4CQ7N0.OPBcj2xhW5O',
   'employe', FALSE, FALSE, 0, FALSE, '2026-01-08 10:45:00'),

  -- Utilisateurs — mot de passe : User1234!
  -- Chauffeurs (est_chauffeur = TRUE), également passagers.
  (4, 'sophie.durand', 'sophie.durand@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, TRUE, 9, FALSE, '2026-02-02 14:10:00'),
  (5, 'thomas.leroy', 'thomas.leroy@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, TRUE, 17, FALSE, '2026-02-04 08:25:00'),
  (6, 'amina.benali', 'amina.benali@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, TRUE, 44, FALSE, '2026-02-06 19:40:00'),

  -- Passagers seuls.
  (7, 'lucas.martin', 'lucas.martin@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 12, FALSE, '2026-02-10 11:05:00'),
  (8, 'chloe.petit', 'chloe.petit@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 3, FALSE, '2026-02-12 16:20:00'),
  -- Compte suspendu : sert à tester le blocage de connexion.
  (9, 'kevin.roux', 'kevin.roux@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 4, TRUE, '2026-02-14 21:00:00');


-- ---------------------------------------------------------------------
-- vehicules — 4 véhicules dont 1 électrique.
-- Sophie (4) en possède deux, Thomas (5) et Amina (6) un chacun.
-- RAPPEL : un trajet ne peut utiliser qu'un véhicule de son chauffeur
-- (clé étrangère composite trajets(vehicule_id, chauffeur_id)).
-- ---------------------------------------------------------------------
INSERT INTO vehicules
  (id, user_id, immatriculation, date_immat, marque, modele, couleur, energie, places)
VALUES
  -- Le seul véhicule électrique du jeu de données.
  (1, 4, 'AB-123-CD', '2023-04-15', 'Renault', 'Zoe',    'Blanc', 'electrique', 3),
  (2, 4, 'EF-456-GH', '2019-09-01', 'Peugeot', '308',    'Gris',  'thermique',  4),
  (3, 5, 'IJ-789-KL', '2021-06-20', 'Toyota',  'Yaris',  'Bleu',  'hybride',    3),
  -- 3 places : rend les trajets 3 et 6 d'Amina complets.
  (4, 6, 'MN-012-OP', '2020-11-08', 'Citroen', 'C3',     'Rouge', 'thermique',  3);


-- ---------------------------------------------------------------------
-- trajets — 8 trajets répartis sur 3 dates.
-- Dates utilisées : 2026-03-10, 2026-03-15, 2026-03-22.
--
-- Chaque trajet roule avec un véhicule de SON chauffeur :
--   chauffeur 4 -> véhicules 1 et 2 | chauffeur 5 -> véhicule 3
--   chauffeur 6 -> véhicule 4
--
-- places_restantes = places du véhicule - réservations occupantes,
-- une réservation étant « occupante » si son statut est 'acceptee' ou
-- 'terminee' (en_attente / refusee / annulee ne consomment pas de place).
-- Les trajets 3 et 6 sont COMPLETS (places_restantes = 0).
-- ---------------------------------------------------------------------
INSERT INTO trajets
  (id, chauffeur_id, vehicule_id, ville_depart, ville_arrivee, depart_at, arrivee_at, prix, places_restantes, statut)
VALUES
  -- === Date 1 : 2026-03-10 (trajets passés, déjà terminés) ===
  -- Véhicule 1 (3 places, Sophie), 1 réservation terminée -> 2 restantes.
  (1, 4, 1, 'Paris',     'Orleans',   '2026-03-10 07:30:00', '2026-03-10 09:00:00',  8, 2, 'termine'),
  -- Véhicule 3 (3 places, Thomas), 1 réservation terminée -> 2 restantes.
  (2, 5, 3, 'Lyon',      'Grenoble',  '2026-03-10 08:00:00', '2026-03-10 09:30:00',  6, 2, 'termine'),
  -- COMPLET : véhicule 4 (3 places, Amina), 3 réservations terminées -> 0.
  (3, 6, 4, 'Bordeaux',  'Toulouse',  '2026-03-10 14:00:00', '2026-03-10 16:30:00', 10, 0, 'termine'),

  -- === Date 2 : 2026-03-15 ===
  -- Véhicule 2 (4 places, Sophie), aucune réservation occupante -> 4.
  (4, 4, 2, 'Paris',     'Lille',     '2026-03-15 09:00:00', '2026-03-15 12:00:00', 12, 4, 'publie'),
  -- Véhicule 3 (3 places, Thomas), la réservation 8 est en_attente -> 3.
  (5, 5, 3, 'Lyon',      'Marseille', '2026-03-15 10:15:00', '2026-03-15 13:45:00', 15, 3, 'publie'),
  -- COMPLET et déjà démarré : véhicule 4 d'Amina (3 places), 3 acceptées.
  -- Autre date que le trajet 3 : le même véhicule peut donc resservir.
  (6, 6, 4, 'Nantes',    'Rennes',    '2026-03-15 17:00:00', '2026-03-15 18:30:00',  7, 0, 'demarre'),

  -- === Date 3 : 2026-03-22 ===
  -- Véhicule 1 (3 places, Sophie), la réservation 10 est refusee -> 3.
  (7, 4, 1, 'Orleans',   'Paris',     '2026-03-22 18:00:00', '2026-03-22 19:30:00',  8, 3, 'publie'),
  -- Trajet annulé par le chauffeur : sert à tester le remboursement.
  -- Véhicule 3 (3 places, Thomas), la réservation 6 est annulee -> 3.
  (8, 5, 3, 'Grenoble',  'Lyon',      '2026-03-22 20:00:00', '2026-03-22 21:30:00',  6, 3, 'annule');


-- ---------------------------------------------------------------------
-- reservations — 11 réservations couvrant les 5 statuts.
--   terminee   : 1, 2, 3, 4, 5
--   annulee    : 6
--   en_attente : 7, 8
--   acceptee   : 9, 10, 11
--   refusee    : 12
-- La contrainte UNIQUE(trajet_id, passager_id) est respectée :
-- aucun couple (trajet, passager) n'apparaît deux fois.
-- ---------------------------------------------------------------------
INSERT INTO reservations
  (id, trajet_id, passager_id, statut, created_at)
VALUES
  -- Trajets terminés du 2026-03-10.
  (1,  1, 7, 'terminee',   '2026-03-05 12:00:00'),
  (2,  2, 9, 'terminee',   '2026-03-06 09:30:00'),
  -- Trajet 3 complet : trois passagers (Chloe, Kevin, Sophie).
  (3,  3, 8, 'terminee',   '2026-03-06 15:45:00'),
  (4,  3, 9, 'terminee',   '2026-03-07 10:10:00'),
  (5,  3, 4, 'terminee',   '2026-03-07 11:00:00'),

  -- Annulation sur le trajet annulé (8) : passager remboursé.
  (6,  8, 7, 'annulee',    '2026-03-18 08:00:00'),

  -- Demandes non encore traitées par le chauffeur.
  (7,  4, 8, 'en_attente', '2026-03-12 19:20:00'),
  (8,  5, 7, 'en_attente', '2026-03-13 07:45:00'),

  -- Acceptées, trajet 6 en cours : 3 passagers -> trajet complet.
  (9,  6, 8, 'acceptee',   '2026-03-13 14:00:00'),
  (10, 6, 5, 'acceptee',   '2026-03-13 15:10:00'),
  (11, 6, 4, 'acceptee',   '2026-03-13 16:25:00'),

  -- Refusée par le chauffeur.
  (12, 7, 9, 'refusee',    '2026-03-19 22:30:00');


-- ---------------------------------------------------------------------
-- avis — 3 avis, dont 1 en attente de modération.
-- Portent uniquement sur des réservations terminées.
-- ---------------------------------------------------------------------
INSERT INTO avis
  (id, reservation_id, note, commentaire, statut_moderation)
VALUES
  (1, 1, 5, 'Trajet parfait, conduite souple et voiture électrique très confortable.', 'valide'),
  (2, 2, 4, 'Ponctuel et sympathique. Je recommande.', 'valide'),
  -- En attente : à traiter dans l'espace employé.
  (3, 3, 2, 'Départ avec 40 minutes de retard et aucune explication.', 'en_attente');


-- ---------------------------------------------------------------------
-- litiges — 1 litige ouvert, pris en charge par l'employée Marie (2).
-- Rattaché à la réservation 3, celle du trajet en retard.
-- ---------------------------------------------------------------------
INSERT INTO litiges
  (id, reservation_id, description, statut, employe_id)
VALUES
  (1, 3,
   'Le passager signale un retard important au départ de Bordeaux et demande un geste commercial. Chauffeur contacté, en attente de sa réponse.',
   'ouvert', 2);


-- ---------------------------------------------------------------------
-- mouvements_credits — journal cohérent avec tout ce qui précède.
-- Rappel : montant signé (négatif = sortie, positif = entrée).
--
-- Les lignes `commission` portent user_id = NULL : elles constatent le
-- prélèvement de la plateforme sans créditer aucun compte. Il y en a
-- exactement une par trajet (8 trajets x 2 crédits = 16).
-- ---------------------------------------------------------------------
INSERT INTO mouvements_credits
  (id, user_id, reservation_id, montant, type, created_at)
VALUES
  -- === Dotations d'inscription : 20 crédits, pour tous (US7) ===
  (1, 4, NULL, 20, 'dotation', '2026-02-02 14:10:00'),
  (2, 5, NULL, 20, 'dotation', '2026-02-04 08:25:00'),
  (3, 6, NULL, 20, 'dotation', '2026-02-06 19:40:00'),
  (4, 7, NULL, 20, 'dotation', '2026-02-10 11:05:00'),
  (5, 8, NULL, 20, 'dotation', '2026-02-12 16:20:00'),
  (6, 9, NULL, 20, 'dotation', '2026-02-14 21:00:00'),

  -- === Réservation 1 : Lucas (7) → trajet 1 de Sophie (4), prix 8 ===
  (7,  7, 1,  -8, 'debit_reservation',   '2026-03-05 12:00:00'),
  (8,  4, 1,   6, 'transfert_chauffeur', '2026-03-10 09:00:00'),

  -- === Réservation 2 : Kevin (9) → trajet 2 de Thomas (5), prix 6 ===
  (9,  9, 2,  -6, 'debit_reservation',   '2026-03-06 09:30:00'),
  (10, 5, 2,   4, 'transfert_chauffeur', '2026-03-10 09:30:00'),

  -- === Réservations 3, 4, 5 : trajet 3 d'Amina (6), prix 10 ===
  -- Trois passagers : Chloe (8), Kevin (9) et Sophie (4).
  (11, 8, 3, -10, 'debit_reservation',   '2026-03-06 15:45:00'),
  (12, 6, 3,   8, 'transfert_chauffeur', '2026-03-10 16:30:00'),
  (13, 9, 4, -10, 'debit_reservation',   '2026-03-07 10:10:00'),
  (14, 6, 4,   8, 'transfert_chauffeur', '2026-03-10 16:30:00'),
  (15, 4, 5, -10, 'debit_reservation',   '2026-03-07 11:00:00'),
  (16, 6, 5,   8, 'transfert_chauffeur', '2026-03-10 16:30:00'),

  -- === Réservation 6 : annulée (trajet 8 annulé) → remboursement ===
  (17, 7, 6,  -6, 'debit_reservation',   '2026-03-18 08:00:00'),
  (18, 7, 6,   6, 'remboursement',       '2026-03-19 09:00:00'),

  -- === Réservations 9, 10, 11 : acceptées, trajet 6 en cours (prix 7) ===
  -- Les passagers sont débités dès l'acceptation ; le transfert au
  -- chauffeur n'aura lieu qu'à la fin du trajet : il n'apparaît pas encore.
  (19, 8, 9,  -7, 'debit_reservation',   '2026-03-13 14:00:00'),
  (20, 5, 10, -7, 'debit_reservation',   '2026-03-13 15:10:00'),
  (21, 4, 11, -7, 'debit_reservation',   '2026-03-13 16:25:00'),

  -- === Commissions plateforme : user_id NULL, 2 crédits par trajet ===
  -- Une ligne par trajet publié, soit 8 x 2 = 16 crédits.
  (22, NULL, NULL, 2, 'commission', '2026-03-10 09:00:00'),  -- trajet 1
  (23, NULL, NULL, 2, 'commission', '2026-03-10 09:30:00'),  -- trajet 2
  (24, NULL, NULL, 2, 'commission', '2026-03-10 16:30:00'),  -- trajet 3
  (25, NULL, NULL, 2, 'commission', '2026-03-15 12:00:00'),  -- trajet 4
  (26, NULL, NULL, 2, 'commission', '2026-03-15 13:45:00'),  -- trajet 5
  (27, NULL, NULL, 2, 'commission', '2026-03-15 18:30:00'),  -- trajet 6
  (28, NULL, NULL, 2, 'commission', '2026-03-22 19:30:00'),  -- trajet 7
  (29, NULL, NULL, 2, 'commission', '2026-03-22 21:30:00');  -- trajet 8
