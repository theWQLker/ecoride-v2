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
-- Convention de crédits (décision crédits du 2026-09-11) :
--   - US7 : 20 crédits de dotation à l'inscription, pour TOUS ;
--   - une réservation débite le passager du prix du trajet ;
--   - la COMMISSION de 2 crédits est prélevée à la CLÔTURE de la
--     réservation, et seulement là : total = 2 x nombre de clôturées.
--     Ces lignes portent user_id = NULL (mouvement de la plateforme) ;
--   - le reste (prix - 2) est transféré au chauffeur à la clôture ;
--   - une annulation NORMALE rembourse intégralement le passager et rend
--     la place ; une annulation TARDIVE ne rembourse pas et ne rend pas
--     la place (d'où le statut distinct `annulee_tardive`).
--
-- Occupation d'un trajet : une réservation occupe une place si son
-- statut est 'confirmee', 'annulee_tardive' ou 'cloturee'.
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
-- users — 1 admin, 2 employés, 7 utilisateurs (dont 3 chauffeurs).
-- La colonne `credits` est exactement la somme des mouvements de
-- l'utilisateur (lignes user_id NULL exclues : plateforme).
--   user  4 Sophie : 20 -10 +6 -7                =  9
--   user  5 Thomas : 20 +4  -7                   = 17
--   user  6 Amina  : 20 +8  +8  +8               = 44
--   user  7 Lucas  : 20 -8 -6 +6 -8 +8           = 12
--   user  8 Chloe  : 20 -10 -7                   =  3
--   user  9 Kevin  : 20 -6 -10                   =  4
--   user 10 Manon  : 20 -15                      =  5
--   users 1,2,3    : ni dotation ni mouvement    =  0
-- NOTE sur les réservations `a_regulariser` (14 pour Kevin, 15 pour
-- Manon) : le débit n'a PAS pu être passé faute de solde suffisant.
-- Elles ne génèrent donc AUCUNE ligne au journal — c'est exactement ce
-- que les litiges 2 et 3, d'origine `regularisation`, ont pour objet de
-- rattraper. Un solde non honoré ne se traduit pas par un mouvement
-- négatif fantôme : il se traduit par un dossier à régulariser.
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
  -- Lucas cumule deux annulations REMBOURSÉES (réservations 6 et 17) :
  -- d'où 20 -8 -6 +6 -8 +8 = 12.
  (7, 'lucas.martin', 'lucas.martin@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 12, FALSE, '2026-02-10 11:05:00'),
  (8, 'chloe.petit', 'chloe.petit@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 3, FALSE, '2026-02-12 16:20:00'),
  -- Compte suspendu : sert à tester le blocage de connexion.
  (9, 'kevin.roux', 'kevin.roux@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 4, TRUE, '2026-02-14 21:00:00'),

  -- US6 — SOLDE VOLONTAIREMENT INSUFFISANT.
  -- Après son annulation tardive (réservation 13, -15 non remboursés),
  -- Manon ne dispose plus que de 5 crédits. Le trajet 4 (Paris -> Lille)
  -- en coûte 12 et a 4 places libres : toute tentative de réservation
  -- doit être refusée par la vérification de solde. C'est le cas de
  -- démonstration de l'US6, et c'est aussi pourquoi sa réservation 15
  -- est restée `a_regulariser` sans débit au journal.
  (10, 'manon.faure', 'manon.faure@ecoride.test',
   '$2b$10$LWXGLweVFNvyvtnomNW2W.rCO7rMxF/zx/YAmnqvOyBpM6wn4sthq',
   'utilisateur', TRUE, FALSE, 5, FALSE, '2026-02-18 09:15:00');


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
-- places_restantes = places du véhicule - réservations OCCUPANTES,
-- une réservation occupant une place si son statut est 'confirmee',
-- 'annulee_tardive' ou 'cloturee'. Une annulation tardive ne rend pas
-- la place : c'est tout l'intérêt de la distinguer.
-- Les trajets 3 et 6 sont COMPLETS (places_restantes = 0).
-- ---------------------------------------------------------------------
INSERT INTO trajets
  (id, chauffeur_id, vehicule_id, ville_depart, ville_arrivee, depart_at, arrivee_at, prix, places_restantes, statut)
VALUES
  -- === Date 1 : 2026-03-10 (trajets passés, déjà terminés) ===
  -- Véhicule 1 (3 places, Sophie), 1 clôturée -> 2 restantes.
  (1, 4, 1, 'Paris',     'Orleans',   '2026-03-10 07:30:00', '2026-03-10 09:00:00',  8, 2, 'termine'),
  -- Véhicule 3 (3 places, Thomas), 1 clôturée -> 2 restantes.
  (2, 5, 3, 'Lyon',      'Grenoble',  '2026-03-10 08:00:00', '2026-03-10 09:30:00',  6, 2, 'termine'),
  -- COMPLET : véhicule 4 (3 places, Amina), 3 clôturées -> 0.
  (3, 6, 4, 'Bordeaux',  'Toulouse',  '2026-03-10 14:00:00', '2026-03-10 16:30:00', 10, 0, 'termine'),

  -- === Date 2 : 2026-03-15 ===
  -- Véhicule 2 (4 places, Sophie) : la réservation 7 est en_attente et
  -- la 15 est a_regulariser -> aucune n'occupe -> 4 restantes.
  -- C'est le trajet visé par le cas US6 (Manon, 3 crédits contre 12).
  (4, 4, 2, 'Paris',     'Lille',     '2026-03-15 09:00:00', '2026-03-15 12:00:00', 12, 4, 'publie'),
  -- Véhicule 3 (3 places, Thomas) : réservation 8 en_attente, 13 annulée
  -- TARDIVE (occupe malgré tout) -> 3 - 1 = 2 restantes.
  (5, 5, 3, 'Lyon',      'Marseille', '2026-03-15 10:15:00', '2026-03-15 13:45:00', 15, 2, 'publie'),
  -- COMPLET et déjà démarré : véhicule 4 d'Amina (3 places), 3 confirmées.
  -- Autre date que le trajet 3 : le même véhicule peut donc resservir.
  (6, 6, 4, 'Nantes',    'Rennes',    '2026-03-15 17:00:00', '2026-03-15 18:30:00',  7, 0, 'demarre'),

  -- === Date 3 : 2026-03-22 ===
  -- Véhicule 1 (3 places, Sophie) : réservation 12 refusée, 16 en_litige,
  -- 17 remboursée -> aucune n'occupe -> 3 restantes.
  (7, 4, 1, 'Orleans',   'Paris',     '2026-03-22 18:00:00', '2026-03-22 19:30:00',  8, 3, 'publie'),
  -- Trajet annulé par le chauffeur : sert à tester le remboursement.
  -- Véhicule 3 (3 places, Thomas), la réservation 6 est annulee -> 3.
  (8, 5, 3, 'Grenoble',  'Lyon',      '2026-03-22 20:00:00', '2026-03-22 21:30:00',  6, 3, 'annule');


-- ---------------------------------------------------------------------
-- reservations — 17 réservations couvrant les 10 statuts de l'ENUM.
--   cloturee        : 1, 2, 3, 4, 5   (commission prélevée)
--   annulee         : 6               (remboursée, place rendue)
--   en_attente      : 7, 8
--   confirmee       : 9, 10, 11
--   refusee         : 12
--   annulee_tardive : 13              (NON remboursée, place NON rendue)
--   a_regulariser   : 14, 15          (litige d'origine regularisation)
--   en_litige       : 16
--   remboursee      : 17
--   terminee        : 18              (arrivée déclarée, délai 48 h en cours)
--
-- Les trois colonnes d'horodatage ne sont renseignées que lorsque
-- l'événement correspondant a eu lieu :
--   annulee_at          -> annulee / annulee_tardive / remboursee
--   arrivee_declaree_at -> terminee / a_regulariser / cloturee / en_litige
--   cloturee_at         -> cloturee uniquement
-- ---------------------------------------------------------------------
INSERT INTO reservations
  (id, trajet_id, passager_id, statut, created_at, annulee_at, arrivee_declaree_at, cloturee_at)
VALUES
  -- === Clôturées : arrivée déclarée puis délai de 48 h écoulé ===
  (1,  1, 7, 'cloturee',  '2026-03-05 12:00:00', NULL, '2026-03-10 09:05:00', '2026-03-12 09:05:00'),
  (2,  2, 9, 'cloturee',  '2026-03-06 09:30:00', NULL, '2026-03-10 09:35:00', '2026-03-12 09:35:00'),
  (3,  3, 8, 'cloturee',  '2026-03-06 15:45:00', NULL, '2026-03-10 16:35:00', '2026-03-12 16:35:00'),
  (4,  3, 9, 'cloturee',  '2026-03-07 10:10:00', NULL, '2026-03-10 16:35:00', '2026-03-12 16:35:00'),
  (5,  3, 4, 'cloturee',  '2026-03-07 11:00:00', NULL, '2026-03-10 16:35:00', '2026-03-12 16:35:00'),

  -- === Annulation NORMALE : trajet 8 annulé, passager remboursé ===
  -- Annulée bien avant le départ -> la place est rendue.
  (6,  8, 7, 'annulee',   '2026-03-18 08:00:00', '2026-03-19 09:00:00', NULL, NULL),

  -- === Demandes non encore traitées par le chauffeur ===
  (7,  4, 8, 'en_attente','2026-03-12 19:20:00', NULL, NULL, NULL),
  (8,  5, 7, 'en_attente','2026-03-13 07:45:00', NULL, NULL, NULL),

  -- === Confirmées, trajet 6 en cours : 3 passagers -> trajet complet ===
  (9,  6, 8, 'confirmee', '2026-03-13 14:00:00', NULL, NULL, NULL),
  (10, 6, 5, 'confirmee', '2026-03-13 15:10:00', NULL, NULL, NULL),
  (11, 6, 4, 'confirmee', '2026-03-13 16:25:00', NULL, NULL, NULL),

  -- === Refusée par le chauffeur ===
  (12, 7, 9, 'refusee',   '2026-03-19 22:30:00', NULL, NULL, NULL),

  -- === ANNULATION TARDIVE (trajet 5, départ le 2026-03-15 10:15) ======
  -- Annulée à 08:30 le jour même, soit moins de 2 h avant le départ :
  -- le passager n'est PAS remboursé et la place n'est PAS réincrémentée.
  -- C'est pourquoi le trajet 5 affiche 2 places restantes et non 3.
  (13, 5, 10, 'annulee_tardive', '2026-03-14 18:00:00', '2026-03-15 08:30:00', NULL, NULL),

  -- === À RÉGULARISER ===============================================
  -- Kevin (9) : arrivée déclarée, mais le solde n'a pas permis
  -- d'honorer le débit. Le dossier part en régularisation (litige 2).
  (14, 4, 9, 'a_regulariser', '2026-03-12 08:00:00', NULL, '2026-03-15 12:10:00', NULL),
  -- Manon (10) : même file, montant partiel non réglé (litige 3).
  (15, 4, 10, 'a_regulariser', '2026-03-12 08:30:00', NULL, '2026-03-15 12:15:00', NULL),

  -- === EN LITIGE : incident signalé par le passager (litige 4) ======
  (16, 7, 8, 'en_litige', '2026-03-20 10:00:00', NULL, '2026-03-22 19:40:00', NULL),

  -- === REMBOURSÉE : annulation acceptée, crédits rendus =============
  (17, 7, 7, 'remboursee', '2026-03-20 11:00:00', '2026-03-21 09:00:00', NULL, NULL),

  -- === TERMINÉE : arrivée déclarée, délai de 48 h NON écoulé ========
  -- Pas encore clôturée : aucune commission n'est donc prélevée ici.
  (18, 2, 10, 'terminee', '2026-03-06 10:00:00', NULL, '2026-03-10 09:40:00', NULL);


-- ---------------------------------------------------------------------
-- avis — 3 avis, dont 1 en attente de modération.
-- Portent uniquement sur des réservations clôturées.
-- ---------------------------------------------------------------------
INSERT INTO avis
  (id, reservation_id, note, commentaire, statut_moderation)
VALUES
  (1, 1, 5, 'Trajet parfait, conduite souple et voiture électrique très confortable.', 'valide'),
  (2, 2, 4, 'Ponctuel et sympathique. Je recommande.', 'valide'),
  -- En attente : à traiter dans l'espace employé.
  (3, 3, 2, 'Départ avec 40 minutes de retard et aucune explication.', 'en_attente');


-- ---------------------------------------------------------------------
-- litiges — 4 dossiers, 2 origines distinctes, tous dans la même file.
--   origine 'signalement_passager' : incident déclaré par un passager
--   origine 'regularisation'       : solde non honoré, à régulariser
-- ---------------------------------------------------------------------
INSERT INTO litiges
  (id, reservation_id, description, origine, statut, employe_id)
VALUES
  (1, 3,
   'Le passager signale un retard important au départ de Bordeaux et demande un geste commercial. Chauffeur contacté, en attente de sa réponse.',
   'signalement_passager', 'ouvert', 2),

  -- Dossier de RÉGULARISATION lié à la réservation 14 (a_regulariser).
  (2, 14,
   'Solde insuffisant au moment du débit : la réservation n a pas pu être honorée. Régularisation à demander au passager.',
   'regularisation', 'ouvert', 2),

  -- Second dossier de régularisation, non encore assigné (employe_id NULL).
  (3, 15,
   'Montant partiellement réglé, reliquat à recouvrer auprès du passager.',
   'regularisation', 'ouvert', NULL),

  -- Incident classique, déjà résolu par Karim (3).
  (4, 16,
   'Désaccord sur le lieu de dépose exact. Médiation effectuée, les deux parties ont été entendues.',
   'signalement_passager', 'resolu', 3);


-- ---------------------------------------------------------------------
-- mouvements_credits — journal cohérent avec tout ce qui précède.
-- Rappel : montant signé (négatif = sortie, positif = entrée).
--
-- Les lignes `commission` portent user_id = NULL : elles constatent le
-- prélèvement de la plateforme sans créditer aucun compte. Il y en a
-- exactement une par réservation CLÔTURÉE, soit 5 x 2 = 10 crédits.
-- ---------------------------------------------------------------------
INSERT INTO mouvements_credits
  (id, user_id, reservation_id, montant, type, created_at)
VALUES
  -- === Dotations d'inscription : 20 crédits, pour tous (US7) ===
  (1, 4,  NULL, 20, 'dotation', '2026-02-02 14:10:00'),
  (2, 5,  NULL, 20, 'dotation', '2026-02-04 08:25:00'),
  (3, 6,  NULL, 20, 'dotation', '2026-02-06 19:40:00'),
  (4, 7,  NULL, 20, 'dotation', '2026-02-10 11:05:00'),
  (5, 8,  NULL, 20, 'dotation', '2026-02-12 16:20:00'),
  (6, 9,  NULL, 20, 'dotation', '2026-02-14 21:00:00'),
  (7, 10, NULL, 20, 'dotation', '2026-02-18 09:15:00'),

  -- === Réservation 1 (clôturée) : Lucas (7) → trajet 1, prix 8 ===
  (8,  7, 1,  -8, 'debit_reservation',   '2026-03-05 12:00:00'),
  (9,  4, 1,   6, 'transfert_chauffeur', '2026-03-12 09:05:00'),

  -- === Réservation 2 (clôturée) : Kevin (9) → trajet 2, prix 6 ===
  (10, 9, 2,  -6, 'debit_reservation',   '2026-03-06 09:30:00'),
  (11, 5, 2,   4, 'transfert_chauffeur', '2026-03-12 09:35:00'),

  -- === Réservations 3, 4, 5 (clôturées) : trajet 3 d'Amina, prix 10 ===
  (12, 8, 3, -10, 'debit_reservation',   '2026-03-06 15:45:00'),
  (13, 6, 3,   8, 'transfert_chauffeur', '2026-03-12 16:35:00'),
  (14, 9, 4, -10, 'debit_reservation',   '2026-03-07 10:10:00'),
  (15, 6, 4,   8, 'transfert_chauffeur', '2026-03-12 16:35:00'),
  (16, 4, 5, -10, 'debit_reservation',   '2026-03-07 11:00:00'),
  (17, 6, 5,   8, 'transfert_chauffeur', '2026-03-12 16:35:00'),

  -- === Réservation 6 : annulation NORMALE → remboursement intégral ===
  (18, 7, 6,  -6, 'debit_reservation',   '2026-03-18 08:00:00'),
  (19, 7, 6,   6, 'remboursement',       '2026-03-19 09:00:00'),

  -- === Réservations 9, 10, 11 : confirmées, trajet 6 en cours (prix 7) ==
  -- Débitées dès la confirmation ; le transfert au chauffeur et la
  -- commission n'auront lieu qu'à la clôture.
  (20, 8, 9,  -7, 'debit_reservation',   '2026-03-13 14:00:00'),
  (21, 5, 10, -7, 'debit_reservation',   '2026-03-13 15:10:00'),
  (22, 4, 11, -7, 'debit_reservation',   '2026-03-13 16:25:00'),

  -- === Réservation 13 : annulation TARDIVE → AUCUN remboursement =====
  -- Manon (10), trajet 5 (prix 15). Le débit reste acquis : c'est la
  -- sanction de l'annulation tardive, et la place n'est pas rendue.
  (23, 10, 13, -15, 'debit_reservation', '2026-03-14 18:00:00'),

  -- === Réservation 17 : remboursée → débit puis remboursement ========
  (25, 7, 17, -8, 'debit_reservation',   '2026-03-20 11:00:00'),
  (26, 7, 17,  8, 'remboursement',       '2026-03-21 09:00:00'),

  -- === Commissions plateforme : user_id NULL, 2 crédits par CLÔTURE ===
  -- Une ligne par réservation clôturée (1 à 5), soit 5 x 2 = 10 crédits.
  -- Les réservations 'terminee' (18) n'ont pas encore été clôturées :
  -- elles ne génèrent donc aucune commission.
  (27, NULL, 1, 2, 'commission', '2026-03-12 09:05:00'),
  (28, NULL, 2, 2, 'commission', '2026-03-12 09:35:00'),
  (29, NULL, 3, 2, 'commission', '2026-03-12 16:35:00'),
  (30, NULL, 4, 2, 'commission', '2026-03-12 16:35:00'),
  (31, NULL, 5, 2, 'commission', '2026-03-12 16:35:00');
