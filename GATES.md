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
- [x] G3: total commissions equals 2 x number of trajets, and every commission row has user_id NULL
    CHECK: node scripts/gate-run.mjs commission
    EXPECT: G3_COMMISSION_OK
    EVIDENCE: exit 0, G3_COMMISSION_OK — 0 commission rows with non-NULL user_id; total 16 = 2 x 8 trajets.
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
- [x] G8: the 5 reservation statuses remain covered
    CHECK: node scripts/gate-run.mjs statuts
    EXPECT: G8_STATUTS_OK
    EVIDENCE: exit 0, G8_STATUTS_OK. First run failed on a bug in the ORACLE, not the data:
      GROUP_CONCAT(DISTINCT ... ORDER BY) sorts an ENUM by ordinal position, not alphabetically.
      Rewritten as an order-independent set comparison; all 5 statuses present.
- [x] G9: no user holds a negative credit balance
    CHECK: node scripts/gate-run.mjs negatif
    EXPECT: G9_NEGATIF_OK
    EVIDENCE: exit 0, G9_NEGATIF_OK — 0 users with credits < 0 (lowest: chloe.petit = 3).
- [x] G10: places_restantes equals vehicle capacity minus occupying reservations, on all trajets
    CHECK: node scripts/gate-run.mjs places
    EXPECT: G10_PLACES_OK
    EVIDENCE: exit 0, G10_PLACES_OK — 0 mismatches across the 8 trajets.
- [x] G11: seed counts still match the CP5 spec
    CHECK: node scripts/gate-run.mjs comptes
    EXPECT: G11_COMPTES_OK
    EVIDENCE: exit 0, G11_COMPTES_OK — 1 admin, 2 employes, 6 utilisateurs, 3 chauffeurs, 4 vehicules,
      1 electrique, 8 trajets, 3 dates, 2 complets, 3 avis, 1 en attente, 1 litige ouvert.
- [ ] G12: db/ committed to git
    CHECK: node scripts/gate-run.mjs commit
    EXPECT: G12_COMMIT_OK
