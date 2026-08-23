-- =============================================================================================
-- SEAT_MOVES_LEAK_ARM_probe — the TMP_ copies that exercise the leak arm's branches the live day
-- does not reach (family seat register Task 3, 2026-08-23).
--
-- WHY IT EXISTS. On the day the leak arm shipped the register published 16 LEAK rows, every one of
-- them pausable, and three negate candidates, every one of them refused for the same measured
-- reason. That proves two branches and leaves a dozen untested. Shipping an arm whose refusal
-- branches have never run is shipping an untested arm.
--
-- WHAT IT INJECTS, AND WHAT IT NEVER INJECTS. It injects MEMBERSHIP — "treat this real keyword as
-- a leak", "treat this real search term as a negate candidate". It never injects EVIDENCE: every
-- block-grain figure the generator judges a candidate on is re-derived from FACT_AMAZON_ADS
-- unchanged, so a branch that fires here fires on a real record. House rule: synthetic rows go in
-- TMP_ copies only; no live table is touched by this file.
--
-- HOW TO RUN (never `cat` a .sql into bq):
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
--     "$(grep -v '^ *--' scripts/bigquery/tests/SEAT_MOVES_LEAK_ARM_probe.sql)"
--   .venv/bin/python tools/build_seat_moves_bulksheet.py \
--     --register-table TMP_SEATREG_T3 --negates-table TMP_NEGATES_T3 -o .tmp/probe.xlsx
--   .venv/bin/python tools/build_seat_moves_bulksheet.py \
--     --register-table TMP_SEATREG_T3 --negates-table TMP_NEGATES_T3 --as-of 2026-09-01 \
--     -o .tmp/probe_holdout.xlsx
--   .venv/bin/python tools/build_restore_seat_moves_bulksheet.py --audit .tmp/probe_audit.csv
--
-- WHAT EACH RUN MUST SHOW (read the audit's `disposition` column):
--   pass 1  PAUSE on the live leaks and on the injected DEAD rows; SEASON_BLOCKED,
--           APPOINTMENT_PENDING, DEFENSE_EXEMPT, ALREADY_PAUSED and LIVE_STATE_UNKNOWN each on
--           their own injected row; NEGATE_KEYWORD, NEGATE_TARGET, EARNS_AT_BLOCK_GRAIN,
--           PAID_ITS_KEEP_LIFETIME, SELLS_ORGANICALLY, TOO_FEW_CLICKS and NOT_BLEEDING_NOW each
--           on a candidate. SELF_TARGET_PAUSE_COVERS is NOT among them and must not be: the
--           candidate table this file writes holds only the injected rows, and that branch is the
--           one the LIVE run exercises (the live negate list is all self-targets today), so
--           between the two runs every branch of both classifiers has fired on real evidence.
--   pass 2  HOLDOUT_EXCLUDED on the leak AND on the negate candidate in the holdout campaign,
--           and on nothing else (the arm dates from 2026-09-01).
--
-- The rows chosen are named by what they PROVE, not by what they are, so a future reader can
-- re-pick them when the account moves. If a chosen keyword leaves FACT_KEYWORD_STATE the injected
-- row silently disappears (the join drops it) — the dispositions above are the check that it has
-- not, and the fix is to pick another row that measures the same way.
--
-- TIDY UP when you are done:
--   DROP TABLE `onyga-482313.OI.TMP_SEATREG_T3`; DROP TABLE `onyga-482313.OI.TMP_NEGATES_T3`;
-- =============================================================================================
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_SEATREG_T3` AS
WITH live AS (
  SELECT row_type, family, book, campaign_id, campaign_name, keyword_id, target_text, match_type,
         state, current_bid, bid_floor, cost_per_day, holdout, holdout_eligible_from
  FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` WHERE row_type = 'LEAK'
),
inj AS (
  SELECT * FROM UNNEST([
    -- (probe, campaign_id, keyword_id, state) — every other field is read from the warehouse
    STRUCT('NEGATE_KEYWORD + LIFETIME_POSITIVE' AS probe, '527422818407259' AS cid, '304542923249526' AS kid, 'DEAD' AS st),
    ('FEW_CLICKS',            '527422818407259', '373381078695862', 'DEAD'),
    ('NEGATE_TARGET',         '193631713358335', '482252635124194', 'DEAD'),
    ('EARNS + ORGANIC',       '53930235252947',  '53149191928594',  'DEAD'),
    ('NOT_BLEEDING_NOW',      '31841446209422',  '192508201227958', 'DEAD'),
    ('HOLDOUT',               '446868628489343', '397102684127255', 'DEAD'),
    ('SEASON_BLOCKED',        '146179760782525', '25172753137819',  'DEAD'),
    ('APPOINTMENT_PENDING',   '146179760782525', '50973110902185',  'PARKED'),
    ('DEFENSE_EXEMPT',        '103820198708330', '287236609998468', 'DEAD')
  ])
)
SELECT * FROM live
UNION ALL
SELECT 'LEAK', f.family, 'HARVEST', inj.cid, f.campaign_name, inj.kid, f.target_text, f.match_type,
       inj.st, f.current_bid, f.bid_floor, 1.11, FALSE, CAST(NULL AS DATE)
FROM inj JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` f
  ON CAST(f.campaign_id AS STRING) = inj.cid AND CAST(f.keyword_id AS STRING) = inj.kid
UNION ALL
-- a keyword Amazon already switched off between the snapshot and this build (the race the guard covers)
SELECT * FROM (
  SELECT 'LEAK', 'LolliME', 'HARVEST', CAST(d.campaign_id AS STRING), 'TMP paused-in-Amazon probe',
         CAST(d.keyword_id AS STRING), d.keyword_text, d.match_type, 'DEAD', d.bid, 0.20, 0.99, FALSE, CAST(NULL AS DATE)
  FROM `onyga-482313.OI.DIM_KEYWORD` d
  WHERE d.is_current AND UPPER(d.state) = 'PAUSED' AND d.keyword_text IS NOT NULL
  LIMIT 1)
UNION ALL
-- a keyword with no live record at all in either feed
SELECT 'LEAK', 'LolliME', 'HARVEST', '527422818407259', 'TMP no-live-record probe',
       '999999999999999', 'tmp phantom keyword', 'BROAD', 'DEAD', 0.30, 0.20, 0.88, FALSE, CAST(NULL AS DATE);

CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_NEGATES_T3` AS
SELECT * FROM UNNEST([
  STRUCT('527422818407259' AS campaign_id, '304542923249526' AS keyword_id, '436092532090167' AS ad_group_id,
         'bscool' AS search_term, 'ME-SP/AUTO (Mint)' AS campaign_name, 'TMP probe: clears every gate' AS reason),
  ('527422818407259','304542923249526','436092532090167','girls stationery set','ME-SP/AUTO (Mint)','TMP probe: lifetime positive'),
  ('527422818407259','373381078695862','436092532090167','art supplies for kids','ME-SP/AUTO (Mint)','TMP probe: too few clicks'),
  ('193631713358335','482252635124194','379299666728484','b0flg9rvrv','BOX-SP/AUTO (Pink)','TMP probe: asin term, other targets draw it'),
  ('53930235252947','53149191928594','219707504132375','teen girl gifts trendy stuff','BALLS- BROAD','TMP probe: the ad group orders on it'),
  ('53930235252947','53149191928594','219707504132375','surprise toys for girls','BALLS- BROAD','TMP probe: sells organically'),
  ('31841446209422','192508201227958','13836490969800','diary ideas','ME-SP/PT (Competitors, Mint, B1)','TMP probe: not bleeding now'),
  ('446868628489343','397102684127255','302639242934323','teen gifts for girls','FRESH-VIDEO/ BROAD','TMP probe: holdout campaign')
]);

-- the two probes swapped in after the first run: the NOT_BLEEDING_NOW candidate must sit on a
-- keyword the LADDER carries (the first pick was off-ladder, so its injected leak row vanished
-- in the join and the branch never ran)
DELETE FROM `onyga-482313.OI.TMP_NEGATES_T3` WHERE search_term = 'diary ideas';
INSERT INTO `onyga-482313.OI.TMP_NEGATES_T3` (campaign_id, keyword_id, ad_group_id, search_term, campaign_name, reason)
VALUES ('135553284530895', '275249053174848', '167543832740880', 'b0flg9rvrv',
        'FRESH-SP/PT (Competitors, Blue, A1)', 'TMP probe: not bleeding now');
INSERT INTO `onyga-482313.OI.TMP_SEATREG_T3` (row_type, family, book, campaign_id, campaign_name, keyword_id, target_text, match_type, state, current_bid, bid_floor, cost_per_day, holdout, holdout_eligible_from)
SELECT 'LEAK', 'Fresh', 'HARVEST', '135553284530895', f.campaign_name, '275249053174848',
       f.target_text, f.match_type, 'DEAD', f.current_bid, f.bid_floor, 1.11, FALSE, NULL
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` f
WHERE CAST(f.campaign_id AS STRING) = '135553284530895'
  AND CAST(f.keyword_id AS STRING) = '275249053174848';
