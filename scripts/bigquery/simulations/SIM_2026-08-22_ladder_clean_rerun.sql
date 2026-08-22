-- =====================================================================================
-- SIMULATION ONLY — 2026-08-22 — A1 CLEAN RERUN of the bar/SE ladder, post-refresh.
-- Gates implementation. Creates only TMP_SIM_LADDER_CLEAN (7-day auto-expiry, disposable).
-- Snapshot consistency verified before this run: orchestrator 2026-08-22 05:07-05:41 UTC,
-- all OK in LOG_PIPELINE_RUNS; T_FAMILY_BAR 05:12:51 ahead of preflight 05:29:02 ahead of
-- FACT_KEYWORD_STATE 05:29:11; state snapshot_date = ads watermark = anchor cap = 2026-08-21.
--
-- ADDITIONS OVER SIM_2026-08-22_ladder_bar_se.sql (the mid-pipeline sim), all Ori-approved:
--   RULING 1  per-family N_f = CEIL((bar_f/(1-bar_f))^2) from T_FAMILY_BAR at run time.
--   RULING 4  at-floor kill: LOSER = below bar beyond noise AND failed AT its price
--             (cpc already at/below afford, or no affordable price above floor, or bid at
--             platform floor). The old "zero below-floor LOSERs" assertion is REPEALED;
--             S5 now asserts the kill clause on every LOSER instead.
--   A2        click-space sufficiency beside the order SE. DERIVATION (clicks-per-order
--             arithmetic): at the family's measured GP-per-order gpo_f =
--             SUM(settled_gp90)/SUM(settled_ord90), a keyword running AT the family bar on
--             its measured settled spend would have produced ord_bar = spend * bar / gpo_f
--             orders (spend = clicks x cpc; ÷ gpo_f/bar = affordable GP per order-equivalent).
--             Poisson noise on that expected count is SQRT(ord_bar). If observed orders fall
--             short beyond that noise (ord_bar - ord > SQRT(ord_bar)), the click record
--             itself rules the bar out and the order-SE band may NOT hide the row.
--             Family GP-per-order is used because the keyword's own GP/order is exactly the
--             quantity that is noisy at low orders.
--   A2b       AT_BAR floor guard: a would-be AT_BAR row with current_bid below the platform
--             floor is unexecutable and resolves to LOSER (ruling 4).
--   A3        one window: verdict AND price both read settled-90 (cpc = settled_cpc90 or the
--             cleaned same-window cpc); live 7d appears only as labelled context (spd).
--   A7        DEAD re-evaluated every run from current data (clk>=15 AND ord=0), never
--             passed through.
--   A8        bar_exempt families (Bunny, LolliBall): flat-era LOSER_BLEED relabels to
--             LAUNCH_CONTAINED; no profit verdict ever.
--   GUARD     clean-then-judge: before any REPRICE/LOSER verdict, the share of judging-window
--             clicks on search terms never seen for that keyword in the prior comparison
--             window is computed ON MEASURABLE TERMS (term >= 5 judging clicks — the one-off
--             long-tail churns ~100% in every window pair and is background in both windows;
--             measured here: raw exact-term background 52.6% click-weighted vs 12.0% on
--             measurable terms, which matches the investigation's year-scale 5-15% band).
--             The materiality bar is DERIVED AT RUN TIME as the account click-weighted
--             never-seen share on measurable terms over keys with a measurable prior record
--             (prior clicks >= 10) — a keyword defers only when its own mix drifted beyond
--             the account's measured background. Guard applies only where a prior record
--             exists (prior clicks >= 10): a keyword absent from the prior window has no
--             comparison and its record IS its record. Deferred rows are re-read excluding
--             zero-order never-seen terms (the negate-valve population); only the cleaned
--             reading may downgrade.
--
-- Windows (the guard view's own settled frames): SP [wm-92, wm-3], SB [wm-103, wm-14];
-- prior comparison window = the preceding 90d: SP [wm-182, wm-93], SB [wm-193, wm-104].
-- =====================================================================================

CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_SIM_LADDER_CLEAN`
OPTIONS (description='SIMULATION ONLY (2026-08-22 clean rerun) — bar/SE ladder with per-family N_f, click sufficiency, clean-then-judge guard. Disposable; safe to drop.', expiration_timestamp=TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH
k AS (SELECT 10 AS vol_floor, 0.25 AS platform_floor, 0.05 AS reprice_material,
             5 AS term_meas_clk, 10 AS prior_meas_clk),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
fb AS (SELECT campaign_id, family, keyword_bar, bar_exempt FROM `onyga-482313.OI.T_FAMILY_BAR`),
nf AS (SELECT family, CAST(CEIL(POW(keyword_bar/(1.0-keyword_bar),2)) AS INT64) AS nf_orders
       FROM (SELECT DISTINCT family, keyword_bar FROM `onyga-482313.OI.T_FAMILY_BAR`
             WHERE NOT bar_exempt AND keyword_bar < 1.0)),
g AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, channel,
             settled_gp90, settled_sp90, settled_clk90 g_clk, settled_ord90 g_ord,
             settled_roas90 g_roas, settled_cpc90 g_cpc, current_bid g_bid, parent_name g_family
      FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
gpo AS (SELECT fb.family, SAFE_DIVIDE(SUM(g.settled_gp90), NULLIF(SUM(g.g_ord),0)) AS gpo_f
        FROM g JOIN fb ON fb.campaign_id = g.cid GROUP BY 1),
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
         st.target_text, st.match_type, st.channel, st.campaign_name,
         COALESCE(st.family, g.g_family) family_st,
         COALESCE(st.current_bid, g.g_bid) current_bid,
         COALESCE(st.state, 'ABSENT_FROM_STATE') old_state,
         COALESCE(st.settled_clk90, g.g_clk, 0) clk,
         COALESCE(st.settled_ord90, g.g_ord, 0) ord,
         COALESCE(st.settled_roas90, g.g_roas, 0) roas,
         COALESCE(st.settled_cpc90, g.g_cpc) cpc,
         COALESCE(g.settled_gp90, 0) gp,
         COALESCE(g.settled_sp90, 0) spb,
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
    SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)) gp_click,
    SAFE_DIVIDE(SAFE_DIVIDE(p.gp, NULLIF(p.clk,0)), COALESCE(fb.keyword_bar,1.0)) afford,
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
    IF(COALESCE(w.c_ord,0) >= COALESCE(nf.nf_orders, 999999), 0.0,
       IF(COALESCE(w.c_ord,0) > 0, SAFE_DIVIDE(w.c_gp, NULLIF(w.c_sp,0)) / SQRT(w.c_ord), NULL)) c_se_eff,
    SAFE_DIVIDE(w.c_sp * COALESCE(fb.keyword_bar,1.0), gpo.gpo_f) c_ord_bar
  FROM pop p
  LEFT JOIN fb ON fb.campaign_id = p.cid
  LEFT JOIN nf ON nf.family = fb.family
  LEFT JOIN gpo ON gpo.family = fb.family
  LEFT JOIN kwg w ON w.cid = p.cid AND w.kid = p.kid
  CROSS JOIN bg),
verd AS (
  SELECT c.*, k.platform_floor, k.reprice_material,
    (c.roas < c.bar AND c.ord_bar IS NOT NULL AND (c.ord_bar - c.ord) > SQRT(c.ord_bar)) AS click_collapse,
    (COALESCE(c.c_roas,0) < c.bar AND c.c_ord_bar IS NOT NULL
     AND (c.c_ord_bar - COALESCE(c.c_ord,0)) > SQRT(c.c_ord_bar)) AS c_click_collapse,
    (COALESCE(c.pclk,0) >= k.prior_meas_clk) AS guard_applicable
  FROM calc c CROSS JOIN k),
rawv AS (
  SELECT v.*,
    CASE
      WHEN old_state IN ('PARKED','PENDING_SETTLE','REVIVED_SETTLING') THEN old_state
      WHEN old_state = 'ABSENT_FROM_STATE' AND no_guard_row THEN 'UNTRACKED'
      WHEN clk >= 15 AND ord = 0 THEN 'DEAD'
      WHEN exempt THEN CASE WHEN old_state = 'LOSER_BLEED' THEN 'LAUNCH_CONTAINED'
                            WHEN old_state IN ('ABSENT_FROM_STATE','DEAD') THEN 'TRIAL'
                            ELSE old_state END
      WHEN clk < 10 THEN 'TRIAL'
      WHEN ord = 0 THEN 'TRIAL'
      WHEN roas - bar > COALESCE(se_eff, 0) THEN IF(old_state = 'PACED_WINNER', 'PACED_WINNER', 'WINNER')
      WHEN ABS(roas - bar) <= COALESCE(se_eff, 0) AND NOT click_collapse
        THEN IF(COALESCE(current_bid, 999) < platform_floor, 'LOSER', 'AT_BAR')
      WHEN COALESCE(afford, 0) > platform_floor
           AND cpc > COALESCE(afford, 0) * (1 + reprice_material)
           AND COALESCE(current_bid, 999) > platform_floor THEN 'REPRICE'
      ELSE 'LOSER'
    END AS raw_state,
    CASE
      WHEN COALESCE(c_clk, 0) < 10 THEN 'TRIAL'
      WHEN COALESCE(c_ord, 0) = 0 THEN IF(c_clk >= 15, 'DEAD', 'TRIAL')
      WHEN c_roas - bar > COALESCE(c_se_eff, 0) THEN 'WINNER'
      WHEN ABS(c_roas - bar) <= COALESCE(c_se_eff, 0) AND NOT c_click_collapse
        THEN IF(COALESCE(current_bid, 999) < platform_floor, 'LOSER', 'AT_BAR')
      WHEN COALESCE(c_afford, 0) > platform_floor
           AND c_cpc > COALESCE(c_afford, 0) * (1 + reprice_material)
           AND COALESCE(current_bid, 999) > platform_floor THEN 'REPRICE'
      ELSE 'LOSER'
    END AS clean_state
  FROM verd v)
SELECT r.*, ROUND(r.sp7/7.0, 4) spd,
  (r.guard_applicable AND COALESCE(r.ns_share, 0) > r.bar_material
   AND r.raw_state IN ('REPRICE','LOSER')) AS guard_deferred,
  IF(r.guard_applicable AND COALESCE(r.ns_share, 0) > r.bar_material
     AND r.raw_state IN ('REPRICE','LOSER'), r.clean_state, r.raw_state) AS new_state,
  (r.guard_applicable AND COALESCE(r.ns_share, 0) > r.bar_material
   AND r.raw_state IN ('REPRICE','LOSER')
   AND r.clean_state NOT IN ('REPRICE','LOSER')) AS guard_flip
FROM rawv r;
