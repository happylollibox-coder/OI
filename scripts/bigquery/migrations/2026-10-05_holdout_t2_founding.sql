-- =============================================
-- 2026-10-05 — holdout trial 2: the founding cohort, written once from the approved literal list
-- (plan docs/superpowers/plans/2026-10-03-holdout-restart.md §2.6, Task 3; deploy step 2 of Task 8).
-- The statements below are Task 3's script verbatim.
--
-- RUN ORDER: after 2026-10-05_holdout_t2_registry_rows.sql (the second ASSERT needs trial 2
-- registered as the live trial in V_HOLDOUT_TRIAL), as ONE script: it writes 59 rows or nothing.
--
-- RUN-ONCE. The first ASSERT refuses when trial 2 already has rows in DE_HOLDOUT_ASSIGNMENT, so a
-- second run stops there and writes nothing. The third ASSERT checks the literal against the list
-- Ori approved on 2026-10-04 ("ok seed 5, deploy it"): 59 rows, 12 HOLDOUT, fingerprint
-- 4171456845817687166 over unit_id|arm|stratum|seq ordered by unit_id. The fourth re-derives every
-- arm from its stored stratum and seq with seed OI-HOLDOUT-v2|5.
--
-- NOT IN THIS FILE: the DE_HOLDOUT_BASELINE append of plan Task 3 (amendment 2026-10-04, Task 2
-- Step 3b).
--
-- Rehearsed on TMP_HT2_ copies 2026-10-04 (registry rows first): wrote 59 rows, 12 HOLDOUT, every
-- ASSERT passed; a second run failed the first ASSERT and wrote nothing; run with no registry row it
-- failed the second ASSERT and wrote nothing.
-- =============================================
ASSERT (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
        WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2') = 0
  AS 'trial 2 already has rows: the founding insert runs once';
ASSERT (SELECT COUNTIF(is_live AND trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2')
        FROM `onyga-482313.OI.V_HOLDOUT_TRIAL`) = 1
  AS 'trial 2 is not registered as the live trial (Task 2 first)';
CREATE TEMP TABLE v AS
SELECT * FROM UNNEST(ARRAY<STRUCT<unit_id STRING, unit_name STRING, arm STRING, stratum STRING,
  seq_in_stratum INT64, channel STRING, family STRING, is_capped BOOL, is_launch BOOL,
  spend_28d FLOAT64, gp_28d FLOAT64, net_28d FLOAT64>>[
  ('369056697567588', 'ME-VIDEO/BROAD (Hunter)', 'TREATED', 'SB|CAP|GRD', 0, 'SB', 'LolliME', TRUE, FALSE, 1693.58, 2272.3, 578.72),
  ('424256831364046', 'BOX- STORE/ BROAD', 'TREATED', 'SB|CAP|GRD', 1, 'SB', 'Lollibox', TRUE, FALSE, 1525.93, 1736.12, 210.19),
  ('27660342907703', 'BOX-VIDEO/PT (Competitors, Purple, A1)', 'HOLDOUT', 'SB|CAP|GRD', 2, 'SB', 'Lollibox', TRUE, FALSE, 1385.21, 745.73, -639.48),
  ('501467313119574', 'BOX-SBS/BROAD (Hunter, By Age)', 'TREATED', 'SB|CAP|GRD', 3, 'SB', 'Lollibox', TRUE, FALSE, 907.92, 799.09, -108.83),
  ('342313119548309', 'FRESH - SB\\BROAD (Hunter, FRESH)', 'TREATED', 'SB|CAP|LNC', 0, 'SB', 'Fresh', TRUE, TRUE, 1486.16, 1097.37, -388.79),
  ('537046793426450', 'ME-SBS/BROAD (Discovery, Journal)', 'HOLDOUT', 'SB|CAP|LNC', 1, 'SB', 'LolliME', TRUE, TRUE, 1380.97, 1078.29, -302.68),
  ('176884360124879', 'ME-VIDEO/PT (Competitors, Pink, D1)', 'TREATED', 'SB|CAP|LNC', 2, 'SB', 'LolliME', TRUE, TRUE, 506.17, 436.97, -69.2),
  ('446868628489343', 'FRESH-VIDEO/ BROAD', 'TREATED', 'SB|UNC|GRD', 0, 'SB', 'Fresh', FALSE, FALSE, 2375.81, 1455.48, -920.33),
  ('292848303399755', 'FRESH SP/BROAD (Hunter ,Pink, Gift)', 'TREATED', 'SB|UNC|GRD', 1, 'SB', 'Fresh', FALSE, FALSE, 1488.62, 833.73, -654.89),
  ('491652134548478', 'BRAND-STORE/BROAD (Me,Box,Bottle)', 'TREATED', 'SB|UNC|GRD', 2, 'SB', 'LolliME', FALSE, FALSE, 1034.45, 1076.07, 41.62),
  ('435692261851957', 'ME-VIDEO/EXACT (age8-14-girl-journal-diary, Purple)', 'TREATED', 'SB|UNC|GRD', 3, 'SB', 'LolliME', FALSE, FALSE, 524.11, 417.72, -106.39),
  ('274922784647676', 'BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, E1)', 'TREATED', 'SB|UNC|LNC', 0, 'SB', 'Bottle', FALSE, TRUE, 225.31, 154.46, -70.85),
  ('107017178352577', 'BUNNY-VIDEO/BROAD (Hunter)', 'TREATED', 'SB|UNC|LNC', 1, 'SB', 'Bunny', FALSE, TRUE, 103.72, 26.16, -77.56),
  ('47108762429478', 'BOX-VIDEO Competitor', 'TREATED', 'SB|UNC|LNC', 2, 'SB', 'Lollibox', FALSE, TRUE, 90.09, 98.77, 8.68),
  ('66467422009617', 'BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, D1)', 'TREATED', 'SB|UNC|LNC', 3, 'SB', 'Bottle', FALSE, TRUE, 19.7, 17.78, -1.92),
  ('71317833591283', 'BOTTLE-VIDEO/EXACT (social-game, Truth)', 'HOLDOUT', 'SB|UNC|LNC', 4, 'SB', 'Bottle', FALSE, TRUE, 18.67, 0.0, -18.67),
  ('26332659728861', 'ME-VIDEO/PT (Competitors, Pink, E1)', 'TREATED', 'SB|UNC|LNC', 5, 'SB', 'LolliME', FALSE, TRUE, 3.56, 0.0, -3.56),
  ('266634740728451', 'BOX-VIDEO/ BROAD (Pink, gift)', 'TREATED', 'SB|UNC|LNC', 6, 'SB', 'Lollibox', FALSE, TRUE, 2.53, 98.4, 95.87),
  ('200171414843593', 'BOX-SP/BROAD (Hunter, Gift for Girl)', 'TREATED', 'SP|CAP|GRD', 0, 'SP', 'Lollibox', TRUE, FALSE, 2196.89, 2087.63, -109.26),
  ('488973733209950', 'BOX-SP/AUTO (White)', 'TREATED', 'SP|CAP|GRD', 1, 'SP', 'Lollibox', TRUE, FALSE, 2045.43, 1454.26, -591.17),
  ('365568042533669', 'ME-COMPETE (Nollh Mint)', 'HOLDOUT', 'SP|CAP|GRD', 2, 'SP', 'LolliME', TRUE, FALSE, 1253.37, 1089.08, -164.29),
  ('531456687555062', 'ME-SP/PT (Conquest, Competitors)', 'TREATED', 'SP|CAP|LNC', 0, 'SP', 'LolliME', TRUE, TRUE, 1342.01, 1514.26, 172.25),
  ('350259814389755', 'BOX-SP/BROAD- gifts for girls 10-12', 'TREATED', 'SP|CAP|LNC', 1, 'SP', 'Lollibox', TRUE, TRUE, 715.65, 670.49, -45.16),
  ('51727823265377', 'MINT-SP/BROAD (Back to School)', 'HOLDOUT', 'SP|CAP|LNC', 2, 'SP', 'LolliME', TRUE, TRUE, 646.31, 663.0, 16.69),
  ('190387447939462', 'ME-SP/BROAD (Mint, journaling kit for g)', 'TREATED', 'SP|CAP|LNC', 3, 'SP', 'LolliME', TRUE, TRUE, 490.78, 541.41, 50.63),
  ('2626284884970', 'ME-SP/PT (Competitors, Mint, D3)', 'TREATED', 'SP|CAP|LNC', 4, 'SP', 'LolliME', TRUE, TRUE, 441.3, 242.25, -199.05),
  ('19013742686856', 'ME-SP/PT (Competitors, Mint, D1)', 'TREATED', 'SP|CAP|LNC', 5, 'SP', 'LolliME', TRUE, TRUE, 421.76, 471.75, 49.99),
  ('279837860088128', 'BOTTLE-SP/AUTO', 'TREATED', 'SP|CAP|LNC', 6, 'SP', 'Bottle', TRUE, TRUE, 413.65, 550.67, 137.02),
  ('130115986205897', 'ME-SP/EXACT (tween-girl-journal-diary, Purple)', 'HOLDOUT', 'SP|CAP|LNC', 7, 'SP', 'LolliME', TRUE, TRUE, 357.73, 323.11, -34.62),
  ('163079264356669', 'ME-SP/AUTO (Pink)', 'TREATED', 'SP|CAP|LNC', 8, 'SP', 'LolliME', TRUE, TRUE, 357.22, 442.83, 85.61),
  ('227290137740434', 'FRESH-SP/PT (Competitors, Pink, A1)', 'TREATED', 'SP|CAP|LNC', 9, 'SP', 'Fresh', TRUE, TRUE, 127.29, 61.83, -65.46),
  ('527422818407259', 'ME-SP/AUTO (Mint)', 'HOLDOUT', 'SP|UNC|GRD', 0, 'SP', 'LolliME', FALSE, FALSE, 961.64, 1172.93, 211.29),
  ('28526809722181', 'FRESH-SP/BROAD (Back to School)', 'TREATED', 'SP|UNC|GRD', 1, 'SP', 'Fresh', FALSE, FALSE, 714.56, 298.14, -416.42),
  ('158989642962021', 'ME-SP/AUTO (Purple)', 'TREATED', 'SP|UNC|GRD', 2, 'SP', 'LolliME', FALSE, FALSE, 450.55, 612.57, 162.02),
  ('193631713358335', 'BOX-SP/AUTO (Pink)', 'TREATED', 'SP|UNC|GRD', 3, 'SP', 'Lollibox', FALSE, FALSE, 310.8, 268.58, -42.22),
  ('104973644967484', 'ME-SP/PT (Competitors, Mint, B2)', 'TREATED', 'SP|UNC|GRD', 4, 'SP', 'LolliME', FALSE, FALSE, 143.39, 63.75, -79.64),
  ('271009556929636', 'FRESH -SP/AUTO (Purple)', 'HOLDOUT', 'SP|UNC|GRD', 5, 'SP', 'Fresh', FALSE, FALSE, 103.4, 95.92, -7.48),
  ('60344378778716', 'ME-SP/PHRASE (age8-14-girl-journal-diary, Mint)', 'TREATED', 'SP|UNC|LNC', 0, 'SP', 'LolliME', FALSE, TRUE, 293.49, 255.0, -38.49),
  ('185651228688176', 'FRESH -SP/AUTO (Pink)', 'TREATED', 'SP|UNC|LNC', 1, 'SP', 'Fresh', FALSE, TRUE, 274.67, 369.46, 94.79),
  ('146179760782525', 'BUNNY-SP/BROAD (Hunter, Gift for Girl , keychain)', 'TREATED', 'SP|UNC|LNC', 2, 'SP', 'Bunny', FALSE, TRUE, 223.57, 114.93, -108.64),
  ('112036454757078', 'BUNNY-SP/AUTO (Brave)', 'TREATED', 'SP|UNC|LNC', 3, 'SP', 'Bunny', FALSE, TRUE, 210.87, 65.4, -145.47),
  ('273898143987321', 'BUNNY-SP/AUTO (Birthday)', 'HOLDOUT', 'SP|UNC|LNC', 4, 'SP', 'Bunny', FALSE, TRUE, 157.34, 203.35, 46.01),
  ('172872442210536', 'BOX-SP/AUTO (Purple)', 'TREATED', 'SP|UNC|LNC', 5, 'SP', 'Lollibox', FALSE, TRUE, 150.89, 107.16, -43.73),
  ('71460479938206', 'BOX-SP/EXACT (teen-girl-gift, White 2)', 'TREATED', 'SP|UNC|LNC', 6, 'SP', 'Lollibox', FALSE, TRUE, 144.98, 12.75, -132.23),
  ('67504198774096', 'FRESH-SP/AUTO (Blue)', 'TREATED', 'SP|UNC|LNC', 7, 'SP', 'Fresh', FALSE, TRUE, 83.7, 20.61, -63.09),
  ('275295641745590', 'ME-SP/PHRASE (tween-girl-birthday-gift, Purple 3)', 'TREATED', 'SP|UNC|LNC', 8, 'SP', 'LolliME', FALSE, TRUE, 79.13, 51.0, -28.13),
  ('230219410635024', 'ME-SP/PT (Competitors, Mint, D2)', 'HOLDOUT', 'SP|UNC|LNC', 9, 'SP', 'LolliME', FALSE, TRUE, 45.83, 25.5, -20.33),
  ('52908075625268', 'BOX -SP/AUTO (Blue)', 'TREATED', 'SP|UNC|LNC', 10, 'SP', 'Lollibox', FALSE, TRUE, 41.28, 102.76, 61.48),
  ('43890791772293', 'ME-SP/PT (Competitors, Mint, A1)', 'TREATED', 'SP|UNC|LNC', 11, 'SP', 'LolliME', FALSE, TRUE, 32.61, 12.75, -19.86),
  ('3918431774030', 'BOTTLE- COPYCAT', 'TREATED', 'SP|UNC|LNC', 12, 'SP', 'Bottle', FALSE, TRUE, 31.59, 8.89, -22.7),
  ('358247566911916', 'BOX-COMPETE (Copycat)', 'TREATED', 'SP|UNC|LNC', 13, 'SP', 'Lollibox', FALSE, TRUE, 22.38, 20.61, -1.77),
  ('222497123677300', 'ME-SP/PT (Competitors, Mint, C2)', 'HOLDOUT', 'SP|UNC|LNC', 14, 'SP', 'LolliME', FALSE, TRUE, 15.86, 38.25, 22.39),
  ('224831787476880', 'FRESH-SP/EXACT (teen-girl-gift, Fresh)', 'TREATED', 'SP|UNC|LNC', 15, 'SP', 'Fresh', FALSE, TRUE, 12.8, 0.0, -12.8),
  ('32239413784257', 'ME-SP/EXACT (kid-girl-birthday-gift, Purple)', 'TREATED', 'SP|UNC|LNC', 16, 'SP', 'LolliME', FALSE, TRUE, 12.19, 0.0, -12.19),
  ('272919287610543', 'ME-SP/PT (Competitors, Mint, E1)', 'TREATED', 'SP|UNC|LNC', 17, 'SP', 'LolliME', FALSE, TRUE, 11.04, 0.0, -11.04),
  ('206332152032611', 'BUNNY-SP/EXACT (backpack charms for girls)', 'TREATED', 'SP|UNC|LNC', 18, 'SP', 'Bunny', FALSE, TRUE, 2.63, 0.0, -2.63),
  ('53343800376430', 'BOTTLE-SP/PHRASE (tween-girl-birthday-gift, Truth)', 'HOLDOUT', 'SP|UNC|LNC', 19, 'SP', 'Bottle', FALSE, TRUE, 0.7, 0.0, -0.7),
  ('366680190861213', 'BOX-SP/EXACT (tween-girl-gift, Blue)', 'TREATED', 'SP|UNC|LNC', 20, 'SP', 'Lollibox', FALSE, TRUE, 0.3, 0.0, -0.3),
  ('130253181662559', 'ME-SP/PHRASE (tween-girl-birthday-gift, Purple)', 'TREATED', 'SP|UNC|LNC', 21, 'SP', 'LolliME', FALSE, TRUE, 0.25, 0.0, -0.25)]);
ASSERT (SELECT COUNT(*) = 59 AND COUNTIF(arm = 'HOLDOUT') = 12
          AND FARM_FINGERPRINT(STRING_AGG(FORMAT('%s|%s|%s|%d', unit_id, arm, stratum, seq_in_stratum), ','
                                          ORDER BY unit_id)) = 4171456845817687166
        FROM v) AS 'the literal is not the approved list';
ASSERT (SELECT COUNTIF(arm != IF(MOD(seq_in_stratum + MOD(ABS(FARM_FINGERPRINT(CONCAT('OI-HOLDOUT-v2|5', '|', stratum))), 5), 5) = 0,
                                 'HOLDOUT', 'TREATED')) FROM v) = 0
  AS 'an arm does not follow the rule';
INSERT INTO `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  (trial_id, unit_type, unit_id, unit_name, arm, stratum, seq_in_stratum, seed,
   assigned_at, eligible_from, trial_end, channel, family, is_capped, is_launch,
   spend_28d_at_assign, gp_28d_at_assign, net_28d_at_assign, assignment_rule)
SELECT 'HOLDOUT-2026Q4-CAMPAIGN-T2', 'CAMPAIGN', unit_id, unit_name, arm, stratum, seq_in_stratum,
       'OI-HOLDOUT-v2|5', CURRENT_TIMESTAMP(), DATE '2026-10-06', DATE '2027-01-26',
       channel, family, is_capped, is_launch, spend_28d, gp_28d, net_28d,
       FORMAT('FOUNDING (approved list): systematic 1-in-5 within stratum ordered by spend_28d DESC; offset %d from seed OI-HOLDOUT-v2|5 (first seed_index passing A1-A3); facts as of FACT anchor 2026-10-02, read 2026-10-03',
              MOD(ABS(FARM_FINGERPRINT(CONCAT('OI-HOLDOUT-v2|5', '|', stratum))), 5))
FROM v;
