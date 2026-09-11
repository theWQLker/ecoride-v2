# GATES — Corrections db/schema.sql + db/seed.sql (CP5)

Scope: db/schema.sql, db/seed.sql
Verification target: real MySQL 8.4.11 (container `ecoride-v2-mysql-1`), scratch DB `ecoride_gatecheck`.
The project database `ecoride` is never touched — audited: 0 tables in `ecoride` after the full sweep.
Shell: Git Bash (POSIX sh) on win32. CWD: D:\Dev\projects\ecoride-v2.

Checker positive control: G2 and G4 were each made to fail on purpose (credits 9 -> 999; dotation 20 -> 35),
both exited 1 with the correct diagnostic, then seed.sql was restored byte-identical
(sha256 7e1425349b7807108036c1d6125d34a43c055ba2b2c37db3de02b048f061e77e, empty diff).

- [x] G1: schema.sql then seed.sql run clean on real MySQL 8.4, two consecutive passes
    CHECK: node scripts/gate-run.mjs pass2
    EXPECT: G1_PASS2_OK
    EVIDENCE: exit 0, G1_PASS2_OK — schema+seed replayed over an already-populated DB, 9 users after pass 2.
- [x] G2: every user's credits equals SUM(mouvements_credits.montant), excluding user_id NULL rows
    CHECK: node scripts/gate-run.mjs solde
    EXPECT: G2_SOLDE_OK
    EVIDENCE: exit 0, G2_SOLDE_OK — 0 discrepancies across all 9 users.
- [x] G3: total commissions equals 2 x number of CLOSED reservations, every commission row user_id NULL
    CHECK: node scripts/gate-run.mjs commission
    EXPECT: G3_COMMISSION_OK
    EVIDENCE: exit 0, G3_COMMISSION_OK — 0 commission rows with non-NULL user_id; 5 lines,
      total 10 = 2 x 5 clôturées. Rule changed 2026-09-11: the commission is levied at closure,
      not at trajet publication (the earlier "2 x trajets" evidence is superseded).
- [x] G4: every dotation is exactly 20 credits, for every user (US7)
    CHECK: node scripts/gate-run.mjs dotation
    EXPECT: G4_DOTATION_OK
    EVIDENCE: exit 0, G4_DOTATION_OK — 6 dotations, none outside 20.
- [x] G5: users.deleted_at exists, DATETIME, nullable, default NULL
    CHECK: node scripts/gate-run.mjs deletedat
    EXPECT: G5_DELETEDAT_OK
    EVIDENCE: exit 0, G5_DELETEDAT_OK — information_schema reports "datetime|YES|NULL".
- [x] G6: a trajet using another driver's vehicle is rejected by the composite FK
    CHECK: node scripts/gate-run.mjs fkcomposite
    EXPECT: G6_FK_REJECTED_OK
    EVIDENCE: exit 0, G6_FK_REJECTED_OK. Positive control first: a legitimate trajet (chauffeur 4 + vehicule 1)
      INSERTs fine. Negative: chauffeur 6 + vehicule 1 (Sophie's) rejected with **ERROR 1452 (23000)**,
      constraint `fk_trajets_vehicule_proprietaire`. Second probe (chauffeur 5 + vehicule 2) also ERROR 1452.
- [x] G7: all 8 trajets use a vehicle owned by their own chauffeur
    CHECK: node scripts/gate-run.mjs proprio
    EXPECT: G7_PROPRIO_OK
    EVIDENCE: exit 0, G7_PROPRIO_OK — 0 trajets whose vehicule.user_id <> chauffeur_id, 8 trajets total.
- [x] G8: the 10 reservation statuses are all covered by the dataset
    CHECK: node scripts/gate-run.mjs statuts
    EXPECT: G8_STATUTS_OK
    EVIDENCE: exit 0, G8_STATUTS_OK. All 10 ENUM values present, counted individually:
      en_attente 2, confirmee 3, refusee 1, annulee 1, annulee_tardive 1, terminee 1,
      a_regulariser 2, en_litige 1, cloturee 5, remboursee 1.
      An earlier run failed on a bug in the ORACLE, not the data: GROUP_CONCAT(DISTINCT ... ORDER BY)
      sorts an ENUM by ordinal position, not alphabetically. Rewritten as a set comparison.
- [x] G9: no user holds a negative credit balance
    CHECK: node scripts/gate-run.mjs negatif
    EXPECT: G9_NEGATIF_OK
    EVIDENCE: exit 0, G9_NEGATIF_OK — 0 users with credits < 0 (lowest: chloe.petit = 3).
- [x] G10: places_restantes equals vehicle capacity minus occupying reservations, on all trajets
    CHECK: node scripts/gate-run.mjs places
    EXPECT: G10_PLACES_OK
    EVIDENCE: exit 0, G10_PLACES_OK — 0 mismatches across the 8 trajets. Occupancy rule updated
      2026-09-11: a reservation occupies a seat when its status is confirmee, annulee_tardive
      or cloturee. A LATE cancellation does NOT return its seat — verified on reservation 13
      (cancelled 1 h before departure): trajet 5 shows 2 seats left on a 3-seat vehicle, and
      0 remboursement rows exist for it.
- [x] G11: seed counts still match the CP5 spec
    CHECK: node scripts/gate-run.mjs comptes
    EXPECT: G11_COMPTES_OK
    EVIDENCE: exit 0, G11_COMPTES_OK — 1 admin, 2 employes, 7 utilisateurs, 3 chauffeurs, 4 vehicules,
      1 electrique, 8 trajets, 3 dates, 2 complets, 3 avis, 1 en attente, 1 litige ouvert.
      7 utilisateurs (was 6): manon.faure added for the US6 insufficient-balance case.

## Demonstration cases required by the 2026-09-11 credits decision

Verified by direct query against the rebuilt scratch DB, not by inspection:

- **US6, insufficient balance** — manon.faure holds 5 credits; trajet 4 (Paris→Lille) costs 12
  and has 4 free seats. Query verdict: "REFUS ATTENDU (solde insuffisant)".
- **Late cancellation, seat not returned** — reservation 13, cancelled 1 h before departure
  (annulee_at 2026-03-15 08:30 vs depart_at 10:15). Vehicle capacity 3, occupants 1,
  places_restantes 2. Zero remboursement rows: the debit stays acquired.
- **a_regulariser + regularisation litige** — reservations 14 (Kevin) and 15 (Manon), each paired
  with a litige of origine='regularisation' (litiges 2 and 3), both statut='ouvert', and each with
  0 rows in mouvements_credits: an unhonoured balance produces a case file, not a phantom debit.
- [x] G12: db/ committed to git
    CHECK: node scripts/gate-run.mjs commit
    EXPECT: G12_COMMIT_OK
    EVIDENCE: exit 0, G12_COMMIT_OK — db/schema.sql and db/seed.sql tracked, `git status --porcelain db/` empty.
      Commit 3ee528b, 793 insertions across 4 files. Working tree fully clean afterwards.

## Result

12 gates declared, 12 met, 0 unmet, 0 abandoned.

Two defects were found by the gates rather than by inspection:
- G8 failed on a bug in the oracle itself (ENUM ordinal vs alphabetical sort in GROUP_CONCAT), now fixed.
- The checker was positive-controlled: G2 and G4 were deliberately broken and both failed correctly.

Secrets: `.env` is git-ignored and untracked; `scripts/gate-run.mjs` reads MYSQL_ROOT_PASSWORD from it at
runtime and hardcodes no credential. The application database `ecoride` was never written to (0 tables).
