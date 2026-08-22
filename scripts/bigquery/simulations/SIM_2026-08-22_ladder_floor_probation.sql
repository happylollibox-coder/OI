-- =====================================================================================
-- SIMULATION ONLY — 2026-08-22 — THE FLOOR RERUN of the bar/SE ladder (v27.104 gate).
-- Creates only TMP_SIM_LADDER_FLOOR (7-day auto-expiry, disposable). Base: the A1 clean rerun
-- (SIM_2026-08-22_ladder_clean_rerun.sql); everything there stands except the floor arm.
--
-- WHAT CHANGED vs the clean rerun (Ori's floor ruling, verbatim: "floor question bid-up-to-floor
-- if after a few days still loosing kill it" + "i think it is not 0.25 (we already checked it)"):
--   FLOOR     per CHANNEL and CREATIVE, from the ONE shared definition FN_BID_FLOOR via
--             V_BID_FLOOR (SP $0.20 house; SB video/unknown $0.25; SB collection/spotlight
--             $0.10). The flat $0.25 "platform_floor" was V_OOB_KEYWORD's bid_park — a PARKING
--             price, not a floor — and it manufactured three phantom kills (two above-bar SP
--             auto clauses at $0.21/$0.24; `tween girl gifts`, an SB collection keyword with a
--             $0.10 floor and an executable $0.49 price).
--   A4 PRICE  affordable BID = affordable CPC / the campaign's measured placement multiplier
--             (V_BID_CPC_TRANSFER.m_effective, MAX over target kinds as the book reads it).
--             The floor is a BID floor, so executability is tested in bid space.
--   FLOOR_PROBATION (NEW)  below bar beyond noise AND (bid at/below its channel floor OR no
--             affordable bid at/above the floor): the move is TO THE FLOOR (up from under it,
--             down to it from above), and the keyword is re-judged after a few settled days AT
--             the floor. "A few days" is DERIVED, never a round number: the first date by which
--             vol_floor (10) settled clicks can exist at the floor = floor_since + settle_days_eff
--             (the guard's own settle discipline: SP 3 / SB 14) + CEIL(10 / the keyword's own
--             90d click pace). Probation ELAPSES on evidence, not on the calendar: >= 10 settled
--             clicks dated on/after floor_since.
--   LOSER     ONLY a keyword whose probation has elapsed and still reads below bar beyond noise.
--             No snapshot has ever recorded a FLOOR_PROBATION, so floor_since is NULL for every
--             key today and the sim asserts ZERO LOSERs. An above-bar keyword is NEVER a kill,
--             whatever its bid (the A2b "unexecutable AT_BAR -> LOSER" arm is REPEALED).
--   REPRICE   below bar beyond noise, an affordable bid exists at/above the floor and the bid is
--             above the floor: move to it, re-judge after settle. The v27.103 "failed AT its
--             price" CPC-materiality kill arm is gone — a keyword is only ever killed at the
--             floor (the book still applies the 5% materiality step to whether a row is emitted).
--   GUARD     clean-then-judge now also defers FLOOR_PROBATION (every deterioration verdict).
--
-- Snapshot consistency (all from the 2026-08-22 07:41-08:09 UTC orchestrator chain, LOG_PIPELINE_RUNS
-- all OK): FACT_AMAZON_ADS 07:41:30 -> FACT_KEYWORD_GUARD 07:47:57 -> T_FAMILY_BAR 07:48:05 ->
-- T_ENGINE_PREFLIGHT 08:08:57 -> FACT_KEYWORD_STATE 08:09:13 (v27.103 states, snapshot 2026-08-22);
-- ads watermark = anchor cap = 2026-08-21. old_state here is the LIVE v27.103 state (flat $0.25);
-- flat_state is the pre-v27.103 label carried from TMP_SIM_LADDER_CLEAN for the three-way read.
-- =====================================================================================

CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_SIM_LADDER_FLOOR`
OPTIONS (description='SIMULATION ONLY (2026-08-22 floor rerun) — bar/SE ladder with per-channel floors from FN_BID_FLOOR, bid-space affordability, FLOOR_PROBATION. Disposable; safe to drop.', expiration_timestamp=TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH
k AS (SELECT 10 AS vol_floor, 0.05 AS reprice_material, 5 AS term_meas_clk, 10 AS prior_meas_clk),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
fb AS (SELECT campaign_id, family, keyword_bar, bar_exempt FROM `onyga-482313.OI.T_FAMILY_BAR`),
nf AS (SELECT family, CAST(CEIL(POW(keyword_bar/(1.0-keyword_bar),2)) AS INT64) AS nf_orders
       FROM (SELECT DISTINCT family, keyword_bar FROM `onyga-482313.OI.T_FAMILY_BAR`
             WHERE NOT bar_exempt AND keyword_bar < 1.0)),
g AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, channel,
             settled_gp90, settled_sp90, settled_clk90 g_clk, settled_ord90 g_ord,
             settled_roas90 g_roas, settled_cpc90 g_cpc, current_bid g_bid, parent_name g_family,
             settle_days_eff, last_bid_change_date
      FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
gpo AS (SELECT fb.family, SAFE_DIVIDE(SUM(g.settled_gp90), NULLIF(SUM(g.g_ord),0)) AS gpo_f
        FROM g JOIN fb ON fb.campaign_id = g.cid GROUP BY 1),
-- THE FLOOR: keyword -> ad group (DIM_KEYWORD, latest row) -> V_BID_FLOOR; a key with no ad-group
-- row resolves through FN_BID_FLOOR on its channel alone (SB unknown creative -> $0.25)
kag AS (SELECT CAST(keyword_id AS STRING) kid, CAST(ad_group_id AS STRING) ad_group_id
        FROM `onyga-482313.OI.DIM_KEYWORD`
        QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY is_current DESC, effective_from DESC) = 1),
bf AS (SELECT ad_group_id, bid_floor, bid_floor_source, creative_type FROM `onyga-482313.OI.V_BID_FLOOR`),
-- A4: the campaign's measured placement multiplier (MAX over target kinds, as the book reads it)
m AS (SELECT CAST(campaign_id AS STRING) cid, MAX(m_effective) m_eff, LOGICAL_OR(is_brand_defense) is_brand_defense
      FROM `onyga-482313.OI.V_BID_CPC_TRANSFER` GROUP BY 1),
sp7 AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         SUM(Ads_cost) AS sp7, SUM(Ads_clicks) AS clk7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm
  WHERE date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND keyword_id IS NOT NULL
  GROUP BY 1,2),
st AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
              target_text, match_type, channel, campaign_name, family, current_bid, state,
              settled_clk90, settled_ord90, settled_roas90, settled_cpc90
       FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
flat AS (SELECT cid, kid, old_state AS flat_state, new_state AS clean_sim_state
         FROM `onyga-482313.OI.TMP_SIM_LADDER_CLEAN`),
tg AS (
  SELECT CAST(f.campaign_id AS STRING) cid, CAST(f.keyword_id AS STRING) kid,
         COALESCE(f.search_term, '(none)') term,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',103,92) DAY)
                           AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',14,3) DAY), f.Ads_clicks, 0)) t_jclk,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',103,92) DAY)
                           AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',14,3) DAY), f.Ads_cost, 0)) t_jsp,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',103,92) DAY)
                           AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',14,3) DAY), f.GROSS_PROFIT, 0)) t_jgp,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',103,92) DAY)
                           AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',14,3) DAY), f.Ads_orders, 0)) t_jord,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',193,182) DAY)
                           AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',104,93) DAY), f.Ads_impressions, 0)) t_pimp,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',193,182) DAY)
                           AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',104,93) DAY), f.Ads_clicks, 0)) t_pclk
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN g ON g.cid = CAST(f.campaign_id AS STRING) AND g.kid = CAST(f.keyword_id AS STRING)
  CROSS JOIN wm
  GROUP BY 1,2,3),
kwg AS (
  SELECT cid, kid,
         SUM(t_pclk) AS pclk,
         SUM(t_jclk) AS jclk_all,
         SUM(IF(t_jclk >= 5, t_jclk, 0)) AS jclk_meas,
         SUM(IF(t_pimp = 0 AND t_jclk >= 5, t_jclk, 0)) AS ns_meas_clk,
         SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jclk)) AS c_clk,
         SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jsp)) AS c_sp,
         SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jgp)) AS c_gp,
         SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jord)) AS c_ord,
         COUNTIF(t_pimp = 0 AND t_jord = 0 AND t_jclk > 0) AS ns_zero_ord_terms,
         SUM(IF(t_pimp = 0 AND t_jord = 0, t_jclk, 0)) AS ns_zero_ord_clicks
  FROM tg GROUP BY 1,2),
bg AS (
  SELECT SAFE_DIVIDE(SUM(IF(w.pclk >= 10, w.ns_meas_clk, 0)),
                     NULLIF(SUM(IF(w.pclk >= 10, w.jclk_meas, 0)),0)) AS bar_material
  FROM kwg w JOIN g ON g.cid = w.cid AND g.kid = w.kid
  WHERE g.g_clk >= 10),
pop AS (
  SELECT COALESCE(st.cid, sp7.cid) cid, COALESCE(st.kid, sp7.kid) kid,
         st.target_text, st.match_type, COALESCE(st.channel, g.channel) channel, st.campaign_name,
         COALESCE(st.family, g.g_family) family_st,
         COALESCE(st.current_bid, g.g_bid) current_bid,
         COALESCE(st.state, 'ABSENT_FROM_STATE') old_state,
         COALESCE(st.settled_clk90, g.g_clk, 0) clk,
         COALESCE(st.settled_ord90, g.g_ord, 0) ord,
         COALESCE(st.settled_roas90, g.g_roas, 0) roas,
         COALESCE(st.settled_cpc90, g.g_cpc) cpc,
         COALESCE(g.settled_gp90, 0) gp,
         COALESCE(g.settled_sp90, 0) spb,
         g.settle_days_eff, g.last_bid_change_date,
         COALESCE(sp7.sp7, 0) sp7, COALESCE(sp7.clk7, 0) clk7,
         (st.cid IS NULL) is_unstated, (g.cid IS NULL) no_guard_row
  FROM st
  FULL OUTER JOIN sp7 ON sp7.cid = st.cid AND sp7.kid = st.kid
  LEFT JOIN g ON g.cid = COALESCE(st.cid, sp7.cid) AND g.kid = COALESCE(st.kid, sp7.kid)
  WHERE st.cid IS NOT NULL OR sp7.sp7 > 0),
calc AS (
  SELECT p.*, bg.bar_material,
    COALESCE(fb.family, p.family_st) family,
    COALESCE(fb.keyword_bar, 1.0) bar,
    (fb.campaign_id IS NULL) null_bar,
    COALESCE(fb.bar_exempt, FALSE) exempt,
    nf.nf_orders,
    gpo.gpo_f,
    kag.ad_group_id, bf.creative_type,
    COALESCE(bf.bid_floor, `onyga-482313.OI.FN_BID_FLOOR`(p.channel, NULL).bid_floor) bid_floor,
    COALESCE(bf.bid_floor_source, CONCAT(`onyga-482313.OI.FN_BID_FLOOR`(p.channel, NULL).bid_floor_source, '_NO_ADGROUP')) bid_floor_source,
    m.m_eff, COALESCE(m.is_brand_defense, FALSE) is_brand_defense,
    SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)) gp_click,
    SAFE_DIVIDE(SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)), COALESCE(fb.keyword_bar,1.0)) afford,
    -- A4: the affordable BID, through the placement multiplier (no multiplier -> CPC = bid)
    SAFE_DIVIDE(SAFE_DIVIDE(SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)), COALESCE(fb.keyword_bar,1.0)),
                COALESCE(m.m_eff, 1.0)) afford_bid,
    IF(p.ord > 0, p.roas / SQRT(p.ord), NULL) se_raw,
    IF(p.ord >= COALESCE(nf.nf_orders, 999999), 0.0,
       IF(p.ord > 0, p.roas / SQRT(p.ord), NULL)) se_eff,
    SAFE_DIVIDE(p.spb * COALESCE(fb.keyword_bar,1.0), gpo.gpo_f) ord_bar,
    w.pclk, w.jclk_meas, w.ns_meas_clk,
    SAFE_DIVIDE(w.ns_meas_clk, NULLIF(w.jclk_meas,0)) ns_share,
    w.c_clk, w.c_sp, w.c_gp, w.c_ord, w.ns_zero_ord_terms, w.ns_zero_ord_clicks,
    SAFE_DIVIDE(w.c_gp, NULLIF(w.c_sp,0)) c_roas,
    SAFE_DIVIDE(w.c_sp, NULLIF(w.c_clk,0)) c_cpc,
    SAFE_DIVIDE(SAFE_DIVIDE(w.c_gp, NULLIF(w.c_clk,0)), COALESCE(fb.keyword_bar,1.0)) c_afford,
    SAFE_DIVIDE(SAFE_DIVIDE(SAFE_DIVIDE(w.c_gp, NULLIF(w.c_clk,0)), COALESCE(fb.keyword_bar,1.0)),
                COALESCE(m.m_eff, 1.0)) c_afford_bid,
    IF(COALESCE(w.c_ord,0) >= COALESCE(nf.nf_orders, 999999), 0.0,
       IF(COALESCE(w.c_ord,0) > 0, SAFE_DIVIDE(w.c_gp, NULLIF(w.c_sp,0)) / SQRT(w.c_ord), NULL)) c_se_eff,
    SAFE_DIVIDE(w.c_sp * COALESCE(fb.keyword_bar,1.0), gpo.gpo_f) c_ord_bar,
    -- PROBATION MEMORY: the date the state machine put the keyword at its floor. No snapshot has
    -- ever recorded FLOOR_PROBATION, so it is NULL for every key today (seeded by the first v27.104
    -- run; carried forward by the SP from its own prior row thereafter).
    CAST(NULL AS DATE) floor_since,
    0 AS clk_since_floor_settled
  FROM pop p
  LEFT JOIN fb ON fb.campaign_id = p.cid
  LEFT JOIN nf ON nf.family = fb.family
  LEFT JOIN gpo ON gpo.family = fb.family
  LEFT JOIN kwg w ON w.cid = p.cid AND w.kid = p.kid
  LEFT JOIN kag ON kag.kid = p.kid
  LEFT JOIN bf ON bf.ad_group_id = kag.ad_group_id
  LEFT JOIN m ON m.cid = p.cid
  CROSS JOIN bg),
verd AS (
  SELECT c.*, k.vol_floor, k.reprice_material,
    (c.roas < c.bar AND c.ord_bar IS NOT NULL AND (c.ord_bar - c.ord) > SQRT(c.ord_bar)) AS click_collapse,
    (COALESCE(c.c_roas,0) < c.bar AND c.c_ord_bar IS NOT NULL
     AND (c.c_ord_bar - COALESCE(c.c_ord,0)) > SQRT(c.c_ord_bar)) AS c_click_collapse,
    (COALESCE(c.pclk,0) >= k.prior_meas_clk) AS guard_applicable,
    -- the bid sits at/below its channel floor (half a cent of tolerance: bulk uploads round)
    (COALESCE(c.current_bid, 999) <= c.bid_floor + 0.005) AS at_floor,
    -- probation elapsed = >= vol_floor settled clicks dated on/after floor_since
    (c.floor_since IS NOT NULL AND c.clk_since_floor_settled >= k.vol_floor) AS probation_elapsed
  FROM calc c CROSS JOIN k),
rawv AS (
  SELECT v.*,
    CASE
      WHEN old_state IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING') THEN old_state
      WHEN old_state = 'ABSENT_FROM_STATE' AND no_guard_row THEN 'UNTRACKED'
      WHEN clk >= 15 AND ord = 0 THEN 'DEAD'
      WHEN exempt THEN CASE WHEN old_state = 'LAUNCH_CONTAINED' THEN 'LAUNCH_CONTAINED'
                            WHEN old_state IN ('ABSENT_FROM_STATE','DEAD') THEN 'TRIAL'
                            ELSE old_state END
      WHEN clk < 10 THEN 'TRIAL'
      WHEN ord = 0 THEN 'TRIAL'
      WHEN roas - bar > COALESCE(se_eff, 0) THEN IF(old_state = 'PACED_WINNER', 'PACED_WINNER', 'WINNER')
      -- at the bar within noise: AT_BAR whatever the bid — an above/at-bar keyword is never a kill
      WHEN ABS(roas - bar) <= COALESCE(se_eff, 0) AND NOT click_collapse THEN 'AT_BAR'
      -- below bar beyond noise, from here down
      WHEN probation_elapsed AND at_floor THEN 'LOSER'
      WHEN at_floor OR COALESCE(afford_bid, 0) < bid_floor THEN 'FLOOR_PROBATION'
      ELSE 'REPRICE'
    END AS raw_state,
    CASE
      WHEN COALESCE(c_clk, 0) < 10 THEN 'TRIAL'
      WHEN COALESCE(c_ord, 0) = 0 THEN IF(c_clk >= 15, 'DEAD', 'TRIAL')
      WHEN c_roas - bar > COALESCE(c_se_eff, 0) THEN 'WINNER'
      WHEN ABS(c_roas - bar) <= COALESCE(c_se_eff, 0) AND NOT c_click_collapse THEN 'AT_BAR'
      WHEN probation_elapsed AND at_floor THEN 'LOSER'
      WHEN at_floor OR COALESCE(c_afford_bid, 0) < bid_floor THEN 'FLOOR_PROBATION'
      ELSE 'REPRICE'
    END AS clean_state
  FROM verd v),
fin AS (
  SELECT r.*, ROUND(r.sp7/7.0, 4) spd,
    (r.guard_applicable AND COALESCE(r.ns_share, 0) > r.bar_material
     AND r.raw_state IN ('REPRICE','FLOOR_PROBATION','LOSER')) AS guard_deferred,
    IF(r.guard_applicable AND COALESCE(r.ns_share, 0) > r.bar_material
       AND r.raw_state IN ('REPRICE','FLOOR_PROBATION','LOSER'), r.clean_state, r.raw_state) AS new_state,
    (r.guard_applicable AND COALESCE(r.ns_share, 0) > r.bar_material
     AND r.raw_state IN ('REPRICE','FLOOR_PROBATION','LOSER')
     AND r.clean_state NOT IN ('REPRICE','FLOOR_PROBATION','LOSER')) AS guard_flip
  FROM rawv r)
SELECT f.*,
  fl.flat_state, fl.clean_sim_state,
  -- the move FLOOR_PROBATION would book: to the floor, from either side
  IF(f.new_state = 'FLOOR_PROBATION', f.bid_floor, NULL) AS probation_bid,
  -- "a few days", derived: settle discipline + the days the keyword's own 90d pace needs for
  -- vol_floor clicks (pace at the floor is unknown a priori; the 90d pace is the upper bound, so
  -- this is the EARLIEST the probation can be read — it elapses on clicks, not on this date)
  IF(f.new_state = 'FLOOR_PROBATION',
     f.settle_days_eff + CAST(CEIL(SAFE_DIVIDE(f.vol_floor, NULLIF(f.clk / 90.0, 0))) AS INT64), NULL) AS probation_days_forecast
FROM fin f
LEFT JOIN flat fl ON fl.cid = f.cid AND fl.kid = f.kid;
