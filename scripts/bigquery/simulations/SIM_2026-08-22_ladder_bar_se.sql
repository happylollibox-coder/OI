-- =====================================================================================
-- SIMULATION ONLY — 2026-08-22 — proposed bar/SE keyword-state ladder vs the current one.
-- Approved scope: "run the impact simulation for 1 + 2 + 4, with 3 as the tightener
-- before implementing." NOTHING here deploys. The one table this creates is
-- TMP_SIM_LADDER_BARSE (TMP_-prefixed, 7-day auto-expiry, description marks it disposable).
--
-- Every number reported to Ori comes from a query in this file (Standing Rule 0).
-- Run context: snapshot_date 2026-08-21 in FACT_KEYWORD_STATE; ads watermark 2026-08-21;
-- 7-complete-day spend window = [wm-7, wm-1] = 2026-08-14 .. 2026-08-20.
--
-- DERIVED (unstated in the approved design, derivation stated here):
--   · volume floor        = 10 settled clicks — the current ladder's own floor
--                           (min_settled_clk in V_KEYWORD_GUARD k CTE). Not re-derived:
--                           the design only redraws verdicts AT volume, not the floor.
--   · "materially above"  = current CPC > affordable CPC * 1.05. 5% is one daily ease
--                           step (the engine's smallest standing move, ease −5%/day),
--                           so "within one day's move of its price" counts as AT price.
--   · platform floor      = $0.25, the account's operative park/floor price (V_KEYWORD_LIFT
--                           parks at $0.25 throughout; design S7 names $0.25).
--   · zero-order SE       = undefined (no return distribution without an order). A row at
--                           click-volume with 0 orders and <15 clicks is TRIAL (thin), never
--                           a bar verdict — an unmeasured value must never read as bad.
--   · zero/negative GP    = affordable CPC <= 0 < floor: REPRICE is unreachable (requires
--                           afford > floor), so a below-bar row falls to LOSER — there is no
--                           price at which it is affordable. (Population today: 0 rows.)
--   · NULL bar            = COALESCE 1.0 (unmapped campaigns judged as today).
--   · current CPC         = settled_cpc90 for the LADDER (same window as the verdict);
--                           sp7/clk7 (live price) for the REPRICE BOOK's dollar deltas.
--   · N*                  = 306, derived in S3 below, never a round number.
--   · PACED overlay       = a row whose new verdict is WINNER keeps PACED_WINNER if a pace
--                           GO is live today (old_state carries it).
--   · exempt treatment    = bar_exempt (INVEST: Bunny, LolliBall) rows keep their CURRENT
--                           state verbatim — no AT_BAR/REPRICE/LOSER ever.
--   · held aside          = PARKED / PENDING_SETTLE / REVIVED_SETTLING pass through
--                           unchanged (reverdict machinery is out of scope), as is DEAD.
-- =====================================================================================

-- ── S0: THE SIMULATION TABLE ─────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
OPTIONS (description='SIMULATION ONLY (2026-08-22) — proposed bar/SE keyword ladder vs current. Disposable; safe to drop.', expiration_timestamp=TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH
k AS (SELECT 10 AS vol_floor, 0.25 AS platform_floor, 0.05 AS reprice_material, -- 5% = one daily ease step
             (SELECT CAST(CEIL(MAX(POW(keyword_bar/(1.0-keyword_bar),2))) AS INT64)
              FROM (SELECT DISTINCT family, keyword_bar, bar_exempt FROM `onyga-482313.OI.T_FAMILY_BAR`)
              WHERE NOT bar_exempt AND keyword_bar < 1.0) AS n_star),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
sp7 AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         SUM(Ads_cost) AS sp7, SUM(Ads_clicks) AS clk7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm
  WHERE date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND keyword_id IS NOT NULL
  GROUP BY 1,2),
g AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
             settled_gp90, settled_sp90, settled_clk90 g_clk, settled_ord90 g_ord,
             settled_roas90 g_roas, settled_cpc90 g_cpc, current_bid g_bid, parent_name g_family
      FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
fb AS (SELECT campaign_id, keyword_bar, bar_exempt FROM `onyga-482313.OI.T_FAMILY_BAR`),
st AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
              target_text, match_type, channel, campaign_name, family, current_bid, state,
              settled_clk90, settled_ord90, settled_roas90, settled_cpc90
       FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
pop AS (
  SELECT COALESCE(st.cid, sp7.cid) cid, COALESCE(st.kid, sp7.kid) kid,
         st.target_text, st.match_type, st.channel, st.campaign_name,
         COALESCE(st.family, g.g_family) family,
         COALESCE(st.current_bid, g.g_bid) current_bid,
         COALESCE(st.state, 'ABSENT_FROM_STATE') old_state,
         COALESCE(st.settled_clk90, g.g_clk, 0) clk,
         COALESCE(st.settled_ord90, g.g_ord, 0) ord,
         COALESCE(st.settled_roas90, g.g_roas, 0) roas,
         COALESCE(st.settled_cpc90, g.g_cpc) cpc,
         COALESCE(g.settled_gp90, 0) gp,
         COALESCE(sp7.sp7, 0) sp7, COALESCE(sp7.clk7, 0) clk7,
         (st.cid IS NULL) is_unstated, (g.cid IS NULL) no_guard_row
  FROM st
  FULL OUTER JOIN sp7 ON sp7.cid = st.cid AND sp7.kid = st.kid
  LEFT JOIN g ON g.cid = COALESCE(st.cid, sp7.cid) AND g.kid = COALESCE(st.kid, sp7.kid)
  WHERE st.cid IS NOT NULL OR sp7.sp7 > 0),
calc AS (
  SELECT p.*, k.n_star,
    COALESCE(fb.keyword_bar, 1.0) bar,
    (fb.campaign_id IS NULL) null_bar,
    COALESCE(fb.bar_exempt, FALSE) exempt,
    SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)) gp_click,
    SAFE_DIVIDE(SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)), COALESCE(fb.keyword_bar,1.0)) afford,
    IF(p.ord > 0, IF(p.ord >= k.n_star, 0.0, p.roas / SQRT(p.ord)), NULL) se,
    IF(p.ord > 0, p.roas / SQRT(p.ord), NULL) se_raw
  FROM pop p LEFT JOIN fb ON fb.campaign_id = p.cid CROSS JOIN k)
SELECT c.*, ROUND(c.sp7/7.0, 4) spd,
  CASE
    WHEN old_state IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING') THEN old_state
    WHEN old_state = 'DEAD' THEN 'DEAD'
    WHEN old_state = 'ABSENT_FROM_STATE' AND no_guard_row THEN 'UNTRACKED'
    WHEN exempt THEN IF(old_state='ABSENT_FROM_STATE','TRIAL',old_state)
    WHEN clk < (SELECT vol_floor FROM k) THEN 'TRIAL'
    WHEN ord = 0 THEN 'TRIAL'
    WHEN roas - bar > se THEN IF(old_state = 'PACED_WINNER', 'PACED_WINNER', 'WINNER')
    WHEN ABS(roas - bar) <= se THEN 'AT_BAR'
    WHEN COALESCE(afford, 0) > (SELECT platform_floor FROM k)
         AND cpc > COALESCE(afford,0) * (1 + (SELECT reprice_material FROM k))
         AND COALESCE(current_bid, 999) > (SELECT platform_floor FROM k) THEN 'REPRICE'
    ELSE 'LOSER'
  END AS new_state
FROM calc c;

-- ── S1: TRANSITION MATRIX (keys, spend/day, zero-spend keys per cell) ────────────────
SELECT old_state, new_state, COUNT(*) keys, ROUND(SUM(spd),2) spend_day,
       COUNTIF(sp7=0) zero_spend_keys
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
GROUP BY 1,2 ORDER BY old_state, spend_day DESC;

-- ── S2a: PER FAMILY, proposed-state mix ─────────────────────────────────────────────
SELECT COALESCE(family,'(NULL family)') family, new_state, COUNT(*) keys, ROUND(SUM(spd),2) spend_day
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
GROUP BY 1,2 ORDER BY family, spend_day DESC;

-- ── S2b: newly WINNER-protected spend per family (result: ZERO ROWS) ────────────────
SELECT family, COUNT(*) keys, ROUND(SUM(spd),2) newly_winner_spd
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
WHERE new_state IN ('WINNER','PACED_WINNER') AND old_state NOT IN ('WINNER','PACED_WINNER')
GROUP BY 1 ORDER BY 3 DESC;

-- ── S3: N* DERIVATION ────────────────────────────────────────────────────────────────
-- se(roas, N) = roas/sqrt(N). A keyword hides when se >= |roas - bar|; the worst hider sits
-- AT its bar, so its hiding half-width is bar/sqrt(N). The finest distinction the account
-- draws is the smallest judged-family gap to 1.0 (also the smallest gap between any two
-- adjacent bars): 1.0 - 0.9459 = 0.0541 (Fresh). Collapse when the worst-case half-width
-- is no longer small relative to that spacing:  bar/sqrt(N) <= (1 - bar)  =>
-- N >= (bar/(1-bar))^2, binding at the largest judged bar (Fresh) = 305.7  =>  N* = 306.
SELECT family, keyword_bar, ROUND(1.0-keyword_bar,4) AS gap_to_1,
       ROUND(POW(keyword_bar/(1.0-keyword_bar),2),1) AS n_family
FROM (SELECT DISTINCT family, keyword_bar, bar_exempt FROM `onyga-482313.OI.T_FAMILY_BAR`)
WHERE NOT bar_exempt AND keyword_bar < 1.0 ORDER BY keyword_bar;
-- what the collapse moves today, single N*=306 vs per-family N_f:
WITH per_family_n AS (
  SELECT family, CAST(CEIL(POW(keyword_bar/(1.0-keyword_bar),2)) AS INT64) nf
  FROM (SELECT DISTINCT family, keyword_bar FROM `onyga-482313.OI.T_FAMILY_BAR` WHERE NOT bar_exempt AND keyword_bar < 1.0))
SELECT
  COUNTIF(ord >= 306) keys_over_nstar,
  COUNTIF(ord >= 306 AND se_raw IS NOT NULL AND ABS(roas-bar) <= se_raw AND NOT exempt
          AND old_state NOT IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING','DEAD')) verdicts_changed_by_collapse,
  ROUND(SUM(IF(ord >= 306, spd, 0)),2) spd_over_nstar,
  (SELECT COUNT(*) FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` t JOIN per_family_n f USING(family)
   WHERE t.ord >= f.nf AND t.ord < 306 AND NOT t.exempt AND t.se_raw IS NOT NULL
     AND ABS(t.roas-t.bar) <= t.se_raw
     AND t.old_state NOT IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING','DEAD')) extra_keys_perfamily_collapse,
  (SELECT ROUND(SUM(t.spd),2) FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` t JOIN per_family_n f USING(family)
   WHERE t.ord >= f.nf AND t.ord < 306 AND NOT t.exempt AND t.se_raw IS NOT NULL
     AND ABS(t.roas-t.bar) <= t.se_raw
     AND t.old_state NOT IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING','DEAD')) extra_spd_perfamily_collapse
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`;

-- ── S4: THE NAMED LIST (three stuck keywords + top 25 spenders) ─────────────────────
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY spd DESC, cid, kid) rk
  FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` WHERE old_state != 'ABSENT_FROM_STATE'),
picked AS (
  SELECT * FROM ranked WHERE rk <= 25
  UNION DISTINCT
  SELECT * FROM ranked WHERE (LOWER(target_text)='girls gifts age 8-10' OR LOWER(target_text)='tween girl gifts'
    OR (LOWER(target_text)='gift for girls' AND campaign_name LIKE 'BALLS%')))
SELECT rk, target_text, campaign_name, family, old_state, new_state, clk, ord,
       ROUND(roas,3) roas, ROUND(bar,4) bar, ROUND(COALESCE(se_raw,-1),3) se_raw, ord >= 306 collapsed,
       ROUND(COALESCE(cpc,-1),3) cpc, ROUND(COALESCE(afford,-1),3) afford,
       ROUND(COALESCE(current_bid,-1),2) bid, ROUND(spd,2) spd, exempt
FROM picked ORDER BY spd DESC;

-- ── S5: THE REPRICE BOOK ─────────────────────────────────────────────────────────────
-- price for the dollar delta = the LIVE 7d price sp7/clk7 (falls back to settled_cpc90);
-- implied change/day = (clk7/7) * (afford - live price), clicks held constant.
WITH book AS (
  SELECT target_text, campaign_name, family, new_state, clk7, spd,
    COALESCE(SAFE_DIVIDE(sp7, NULLIF(clk7,0)), cpc) cpc_now, afford,
    ROUND((clk7/7.0) * (afford - COALESCE(SAFE_DIVIDE(sp7, NULLIF(clk7,0)), cpc)), 2) delta_spd
  FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
  WHERE new_state IN ('AT_BAR','REPRICE'))
SELECT new_state, COUNT(*) keys, COUNTIF(delta_spd < 0) bid_down_keys, COUNTIF(delta_spd > 0) bid_up_keys,
  ROUND(SUM(IF(delta_spd<0, delta_spd, 0)),2) bid_down_day, ROUND(SUM(IF(delta_spd>0, delta_spd, 0)),2) bid_up_day,
  ROUND(SUM(delta_spd),2) net_day, ROUND(SUM(spd),2) spd_covered, COUNTIF(clk7=0) inactive7
FROM book GROUP BY 1
UNION ALL
SELECT 'TOTAL', COUNT(*), COUNTIF(delta_spd<0), COUNTIF(delta_spd>0),
  ROUND(SUM(IF(delta_spd<0, delta_spd, 0)),2), ROUND(SUM(IF(delta_spd>0, delta_spd, 0)),2),
  ROUND(SUM(delta_spd),2), ROUND(SUM(spd),2), COUNTIF(clk7=0)
FROM book ORDER BY 1;
-- (row-level book: SELECT * FROM book ORDER BY delta_spd)

-- ── S6: SAFETY ASSERTIONS ────────────────────────────────────────────────────────────
SELECT
 COUNTIF(exempt AND new_state IN ('AT_BAR','REPRICE','LOSER')) a1_exempt_profit_verdicts,       -- expect 0
 COUNTIF(COALESCE(current_bid,999) < 0.25 AND new_state IN ('LOSER','REPRICE')) a2_strict_below_floor, -- see note
 COUNTIF(COALESCE(current_bid,999) <= 0.25 AND new_state = 'REPRICE') a2b_atfloor_reprice,      -- expect 0
 COUNTIF(COALESCE(current_bid,999) <= 0.25 AND new_state = 'LOSER') a2c_atfloor_loser,          -- by-design kills
 COUNTIF(old_state='DEAD') != COUNTIF(new_state='DEAD')
   OR COUNTIF(old_state='DEAD' AND new_state!='DEAD') > 0
   OR COUNTIF(new_state='DEAD' AND old_state!='DEAD') > 0 a3_dead_moved,                        -- expect false
 COUNTIF(old_state IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING') AND new_state != old_state) a4_park_touched, -- 0
 COUNTIF(new_state IS NULL) a5_null_state,                                                      -- expect 0
 COUNT(*) - COUNT(DISTINCT CONCAT(cid,'|',kid)) a5_dup_keys                                     -- expect 0
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`;
-- the single a2 row, for the eye:
SELECT target_text, campaign_name, family, old_state, new_state, clk, ord, roas, ROUND(bar,3) bar,
       cpc, ROUND(afford,3) afford, current_bid, ROUND(spd,2) spd
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
WHERE new_state='LOSER' OR (COALESCE(current_bid,999)<0.25 AND new_state IN ('LOSER','REPRICE'));

-- ── S7: EDGE CASES ───────────────────────────────────────────────────────────────────
WITH judged AS (
  SELECT * FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE`
  WHERE old_state NOT IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING','DEAD','ABSENT_FROM_STATE') AND NOT exempt)
SELECT
 (SELECT COUNT(*) FROM judged WHERE gp <= 0 AND clk >= 10 AND ord >= 1) zero_gp_at_volume,
 (SELECT COUNT(*) FROM judged WHERE clk >= 10 AND clk < 15 AND ord = 0) zero_ord_over_clickfloor,
 (SELECT COUNT(*) FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` WHERE null_bar AND old_state NOT IN ('ABSENT_FROM_STATE')) null_bar_keys,
 (SELECT ROUND(SUM(spd),2) FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` WHERE null_bar AND old_state NOT IN ('ABSENT_FROM_STATE')) null_bar_spd,
 (SELECT COUNT(*) FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` t
  WHERE t.null_bar AND t.old_state NOT IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING','DEAD','ABSENT_FROM_STATE')) judged_null_bar, -- 0: all NULL-bar keys sit in held-aside states
 (SELECT COUNT(*) FROM judged WHERE COALESCE(current_bid,999) <= 0.25) at_floor_bids,
 (SELECT COUNT(*) FROM judged WHERE sp7 = 0 AND clk >= 10) dormant_large_record,
 (SELECT STRING_AGG(DISTINCT new_state, ',') FROM judged WHERE sp7 = 0 AND clk >= 10) dormant_states;

-- ── the 29 spending keys the state table lacks (characterisation) ───────────────────
WITH kd AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         keyword_text, UPPER(state) kw_state,
         ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING), CAST(keyword_id AS STRING)
                            ORDER BY effective_from DESC) rn
  FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current)
SELECT c.campaign_name, c.campaign_state, kd.keyword_text, kd.kw_state, ROUND(t.spd,2) spd, t.clk7
FROM `onyga-482313.OI.TMP_SIM_LADDER_BARSE` t
LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c ON c.campaign_id = t.cid
LEFT JOIN kd ON kd.cid = t.cid AND kd.kid = t.kid AND kd.rn = 1
WHERE t.old_state='ABSENT_FROM_STATE' ORDER BY t.spd DESC;
