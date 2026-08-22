-- =============================================
-- SP_SNAPSHOT_KEYWORD_STATE — the roadmap of each keyword (2026-08-16, Task 2.1).
-- v27.103 (2026-08-22): THE BAR/SE LADDER — Ori's four rulings + the clean-then-judge guard.
-- Spec: architecture/KEYWORD_STATE.md. Simulation of record: TMP_SIM_LADDER_CLEAN
-- (scripts/bigquery/simulations/SIM_2026-08-22_ladder_clean_rerun.sql, the A1 clean rerun that
-- gated this implementation).
--
-- WHAT CHANGED vs the flat ladder (all Ori-approved, 2026-08-22):
--   RULING 1  a keyword is judged against ITS FAMILY'S bar (T_FAMILY_BAR.keyword_bar), inside a
--             noise band se = settled_roas90/SQRT(settled_ord90). The band COLLAPSES at the
--             per-family order count N_f = CEIL((bar_f/(1-bar_f))^2), computed from T_FAMILY_BAR
--             AT RUN TIME, never hardcoded — above N_f orders the verdict is wherever the number
--             sits.
--   RULING 2  WINNER DEMOTION: a winner that does not clear its family bar beyond its own noise
--             relabels AT_BAR. Labels only — no bid is ever moved by a relabel; NO ENGINE reads
--             this table and the only executor is the manual reprice book.
--   RULING 4  AT-FLOOR KILL: LOSER = below bar beyond noise AND already failed AT its price —
--             its settled CPC is at/below its affordable price, or no affordable price exists
--             above the platform floor, or its bid already sits at/below the floor. The former
--             safety assertion ("zero below-floor LOSERs") is REPEALED; the SOP asserts the kill
--             clause instead.
--   A2        CLICK-SPACE SUFFICIENCY beside the order SE: at the family's measured GP-per-order
--             gpo_f, a keyword running AT the bar on its settled spend would have produced
--             ord_bar = spend x bar / gpo_f orders; if observed orders fall short beyond
--             SQRT(ord_bar), the click record rules the bar out and the order-SE band may NOT
--             hide the row (the 489-click/4-order bleeder never re-enters a band).
--   A2b       a would-be AT_BAR row whose bid sits below the platform floor is unexecutable and
--             resolves to LOSER (ruling 4).
--   A3        ONE WINDOW: verdict and price both read the settled-90 window (settled_cpc90 /
--             affordable_cpc, or their cleaned same-window equivalents). Live 7d CPC appears
--             only in the reprice book, labelled as context, never in a verdict.
--   A7        DEAD is re-derived from current data every run (clk90>=15 AND ord90=0), never
--             passed through from yesterday's state.
--   A8        bar_exempt families (INVEST book: launches) are never judged on profit, including
--             in their label: the would-be flat-era LOSER_BLEED reads LAUNCH_CONTAINED.
--   GUARD     CLEAN-THEN-JUDGE: before any deterioration verdict (REPRICE or LOSER), the share
--             of the judging window's clicks on search terms NEVER SEEN for that keyword in the
--             prior comparison window is measured ON MEASURABLE TERMS (>= 5 judging clicks; the
--             one-off long-tail churns ~100% in every window pair and is background in both).
--             The materiality bar is DERIVED AT RUN TIME as the account click-weighted
--             never-seen share on the same measurable-term basis. A keyword above the bar is
--             judged on its CLEANED reading (zero-order never-seen terms excluded — that
--             excluded population is the negate valve's, exposed here as ns_zero_ord_*); only
--             the cleaned reading may downgrade. Guard applies only where a prior record exists
--             (prior clicks >= prior_meas_clk): a keyword with no prior window has no comparison
--             and its record IS its record.
--
-- STILL ASSEMBLY WHERE VERDICTS EXIST ELSEWHERE: reverdict rules (PARKED / PENDING_SETTLE /
-- REVIVED_SETTLING), ownership, pacing and appointments are other objects' verdicts, assembled
-- unchanged. The bar/SE ladder is THIS object's own judgment now — the one place the account
-- says what a keyword's record is worth against its family's bar.
--
-- READS FACT_AMAZON_ADS at term grain for the guard (two 90d windows) — no longer a
-- seconds-only snapshot assembly; measured ~40s standalone. Orchestrator Task 20.8, after the
-- preflight (20.7) and after SP_SNAPSHOT_FAMILY_BAR (T_FAMILY_BAR must be fresh).
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE`()
OPTIONS (
  description = "Keyword state machine, bar/SE ladder (v27.103, 2026-08-22): one row per (campaign, keyword) — state (DEAD | PENDING_SETTLE | REVIVED_SETTLING | PARKED | PACED_WINNER | WINNER | AT_BAR | REPRICE | LOSER | LAUNCH_CONTAINED | TRIAL, first-match ladder), judged against the FAMILY bar (T_FAMILY_BAR) inside an SE noise band that collapses at per-family N_f orders, with the A2 click-space sufficiency check, the ruling-4 at-floor kill, the A8 launch exemption and the clean-then-judge mix-drift guard (deterioration verdicts re-read on the keyword's own terms before they stand). Owner ladder + appointments unchanged. NO ENGINE reads this table — the only executor is the manual reprice book (tools/build_reprice_bulksheet.py). Invariants read by V_ENGINE_HEALTH. Spec: architecture/KEYWORD_STATE.md."
)
BEGIN
  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_KEYWORD_STATE` AS
  WITH
  -- Declared constants (Standing Rule 0 exempt), each with its derivation:
  --   vol_floor 10        the guard's own settled-click floor (V_KEYWORD_GUARD min_settled_clk)
  --   platform_floor 0.25 the account's operative park/floor price (V_KEYWORD_LIFT parks at $0.25)
  --   reprice_material 5% one daily ease step — the engine's smallest standing move; within one
  --                       day's move of its affordable price counts as AT price
  --   term_meas_clk 5     a term is measurable in the judging window at >= 5 clicks
  --   prior_meas_clk 10   a prior record exists at >= 10 prior-window clicks
  k AS (SELECT 10 AS vol_floor, 0.25 AS platform_floor, 0.05 AS reprice_material,
               5 AS term_meas_clk, 10 AS prior_meas_clk),
  wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
         FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
  g AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           keyword_text, match_type, channel, is_auto, is_pt, current_bid, parent_name,
           settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
           settled_gp90, settled_sp90,
           settle_ok, settle_due, last_click_date, season_win_prior, last_bid_change_date
    FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`
  ),
  -- family bar + exemption, campaign grain (T_FAMILY_BAR is the nightly snapshot — READ THE
  -- TABLE, NEVER V_FAMILY_BAR, which sits at the planner ceiling)
  fb AS (SELECT campaign_id, family, keyword_bar, bar_exempt
         FROM `onyga-482313.OI.T_FAMILY_BAR`),
  -- RULING 1: per-family N_f, from the bar itself, at run time
  nf AS (SELECT family, CAST(CEIL(POW(keyword_bar/(1.0-keyword_bar), 2)) AS INT64) AS nf_orders
         FROM (SELECT DISTINCT family, keyword_bar FROM `onyga-482313.OI.T_FAMILY_BAR`
               WHERE NOT bar_exempt AND keyword_bar < 1.0)),
  -- A2: family GP-per-order — the family's is used because the keyword's own is exactly the
  -- quantity that is noisy at low orders
  gpo AS (SELECT fb.family, SAFE_DIVIDE(SUM(g.settled_gp90), NULLIF(SUM(g.settled_ord90), 0)) AS gpo_f
          FROM g JOIN fb ON fb.campaign_id = g.cid GROUP BY 1),
  -- GUARD term grain: judging window = the guard view's own settled frame (SP [wm-92, wm-3],
  -- SB [wm-103, wm-14]); prior comparison window = the preceding 90d
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
                             AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',104,93) DAY), f.Ads_impressions, 0)) t_pimp
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
    JOIN g ON g.cid = CAST(f.campaign_id AS STRING) AND g.kid = CAST(f.keyword_id AS STRING)
    CROSS JOIN wm
    GROUP BY 1, 2, 3),
  kwg AS (
    SELECT cid, kid,
           SUM(t_jclk) AS jclk_all,
           SUM(IF(t_jclk >= k.term_meas_clk, t_jclk, 0)) AS jclk_meas,
           SUM(IF(t_pimp = 0 AND t_jclk >= k.term_meas_clk, t_jclk, 0)) AS ns_meas_clk,
           -- cleaned record: the judging window EXCLUDING zero-order never-seen terms
           SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jclk)) AS c_clk,
           SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jsp)) AS c_sp,
           SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jgp)) AS c_gp,
           SUM(IF(t_pimp = 0 AND t_jord = 0, 0, t_jord)) AS c_ord,
           -- the negate valve's population (routes through the coach pipeline, never a raw list)
           COUNTIF(t_pimp = 0 AND t_jord = 0 AND t_jclk > 0) AS ns_zero_ord_terms,
           SUM(IF(t_pimp = 0 AND t_jord = 0, t_jclk, 0)) AS ns_zero_ord_clicks
    FROM tg CROSS JOIN k GROUP BY 1, 2),
  -- prior-window clicks per key (for guard applicability)
  pw AS (
    SELECT CAST(f.campaign_id AS STRING) cid, CAST(f.keyword_id AS STRING) kid,
           SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',193,182) DAY)
                             AND DATE_SUB(wm.d, INTERVAL IF(g.channel='SB',104,93) DAY), f.Ads_clicks, 0)) pclk
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
    JOIN g ON g.cid = CAST(f.campaign_id AS STRING) AND g.kid = CAST(f.keyword_id AS STRING)
    CROSS JOIN wm
    GROUP BY 1, 2),
  -- the account's measured mix-drift background, derived at run time (never pinned)
  bg AS (
    SELECT SAFE_DIVIDE(SUM(IF(pw.pclk >= k.prior_meas_clk, w.ns_meas_clk, 0)),
                       NULLIF(SUM(IF(pw.pclk >= k.prior_meas_clk, w.jclk_meas, 0)), 0)) AS bar_material
    FROM kwg w
    JOIN pw ON pw.cid = w.cid AND pw.kid = w.kid
    JOIN g ON g.cid = w.cid AND g.kid = w.kid
    CROSS JOIN k
    WHERE g.settled_clk90 >= k.vol_floor),
  rv AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           keyword_text, match_type, channel, current_bid,
           reverdict, revive_bid, revive_settling, park_date, settle_due AS rv_settle_due,
           s90_gp_roas AS rv_roas90, s90_clk AS rv_clk90
    FROM `onyga-482313.OI.FACT_PARK_REVERDICT`
    WHERE reverdict IN ('REVIVE', 'SIBLING_REVIVE', 'CONFIRM_PARK', 'REDUNDANT', 'PENDING_SETTLE', 'INSUFFICIENT')
       OR COALESCE(revive_settling, FALSE)
  ),
  po AS (
    SELECT CAST(campaign_id AS STRING) cid, campaign_name, family, owner
    FROM `onyga-482313.OI.FACT_PANEL_OWNERSHIP`
  ),
  pf AS (
    SELECT campaign_id cid, COALESCE(keyword_id, '') kid,
           LOGICAL_OR(verdict = 'GO' AND lever = 'BID'
                      AND suggested_bid IS NOT NULL AND current_bid IS NOT NULL
                      AND suggested_bid < current_bid - 0.005) AS go_bid_down
    FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`
    GROUP BY 1, 2
  ),
  lc AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           MAX(DATE(applied_at, 'America/Los_Angeles')) AS last_applied
    FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
    WHERE keyword_id IS NOT NULL
    GROUP BY 1, 2
  ),
  base AS (
    SELECT
      COALESCE(g.cid, rv.cid) AS campaign_id,
      COALESCE(g.kid, rv.kid) AS keyword_id,
      COALESCE(g.keyword_text, rv.keyword_text) AS target_text,
      COALESCE(g.match_type, rv.match_type) AS match_type,
      COALESCE(g.channel, rv.channel) AS channel,
      g.is_auto, g.is_pt,
      COALESCE(g.current_bid, rv.current_bid) AS current_bid,
      g.settled_clk90, g.settled_ord90, g.settled_roas90, g.settled_cpc90,
      g.settled_gp90, g.settled_sp90,
      g.settle_ok, g.settle_due, g.last_click_date, g.season_win_prior, g.last_bid_change_date,
      rv.reverdict, rv.revive_bid, rv.revive_settling, rv.park_date, rv.rv_settle_due,
      rv.rv_roas90, rv.rv_clk90
    FROM g
    FULL OUTER JOIN rv ON rv.cid = g.cid AND rv.kid = g.kid
  ),
  calc AS (
    SELECT b.*,
      po.campaign_name, COALESCE(fb.family, po.family) AS family, po.owner AS campaign_owner,
      COALESCE(pf.go_bid_down, FALSE) AS paced_today,
      lc.last_applied,
      COALESCE(fb.keyword_bar, 1.0) AS family_bar,
      COALESCE(fb.bar_exempt, FALSE) AS bar_exempt,
      nf.nf_orders,
      gpo.gpo_f,
      SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_clk90, 0)) AS gp_per_click,
      -- the price this record affords at the family bar (settled window — A3)
      SAFE_DIVIDE(SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_clk90, 0)),
                  COALESCE(fb.keyword_bar, 1.0)) AS affordable_cpc,
      -- SE band, collapsed above N_f (RULING 1)
      IF(COALESCE(b.settled_ord90, 0) >= COALESCE(nf.nf_orders, 999999), 0.0,
         IF(COALESCE(b.settled_ord90, 0) > 0,
            COALESCE(b.settled_roas90, 0) / SQRT(b.settled_ord90), NULL)) AS se_eff,
      -- A2 click-space expected orders at the bar
      SAFE_DIVIDE(b.settled_sp90 * COALESCE(fb.keyword_bar, 1.0), gpo.gpo_f) AS ord_bar_expected,
      pw.pclk AS guard_prior_clk,
      w.jclk_meas, w.ns_meas_clk,
      SAFE_DIVIDE(w.ns_meas_clk, NULLIF(w.jclk_meas, 0)) AS guard_ns_share,
      bg.bar_material AS guard_bar_material,
      w.c_clk AS clean_clk90, w.c_ord AS clean_ord90,
      SAFE_DIVIDE(w.c_gp, NULLIF(w.c_sp, 0)) AS clean_roas90,
      SAFE_DIVIDE(w.c_sp, NULLIF(w.c_clk, 0)) AS clean_cpc90,
      SAFE_DIVIDE(SAFE_DIVIDE(w.c_gp, NULLIF(w.c_clk, 0)),
                  COALESCE(fb.keyword_bar, 1.0)) AS clean_affordable_cpc,
      IF(COALESCE(w.c_ord, 0) >= COALESCE(nf.nf_orders, 999999), 0.0,
         IF(COALESCE(w.c_ord, 0) > 0,
            SAFE_DIVIDE(w.c_gp, NULLIF(w.c_sp, 0)) / SQRT(w.c_ord), NULL)) AS clean_se_eff,
      SAFE_DIVIDE(w.c_sp * COALESCE(fb.keyword_bar, 1.0), gpo.gpo_f) AS clean_ord_bar,
      w.ns_zero_ord_terms, w.ns_zero_ord_clicks
    FROM base b
    LEFT JOIN po ON po.cid = b.campaign_id
    LEFT JOIN pf ON pf.cid = b.campaign_id AND pf.kid = b.keyword_id
    LEFT JOIN lc ON lc.cid = b.campaign_id AND lc.kid = b.keyword_id
    LEFT JOIN fb ON fb.campaign_id = b.campaign_id
    LEFT JOIN nf ON nf.family = fb.family
    LEFT JOIN gpo ON gpo.family = fb.family
    LEFT JOIN kwg w ON w.cid = b.campaign_id AND w.kid = b.keyword_id
    LEFT JOIN pw ON pw.cid = b.campaign_id AND pw.kid = b.keyword_id
    CROSS JOIN bg
  ),
  verd AS (
    SELECT c.*, k.platform_floor, k.reprice_material, k.vol_floor, k.prior_meas_clk,
      (COALESCE(c.settled_roas90, 0) < c.family_bar AND c.ord_bar_expected IS NOT NULL
       AND (c.ord_bar_expected - COALESCE(c.settled_ord90, 0)) > SQRT(c.ord_bar_expected)) AS click_collapse,
      (COALESCE(c.clean_roas90, 0) < c.family_bar AND c.clean_ord_bar IS NOT NULL
       AND (c.clean_ord_bar - COALESCE(c.clean_ord90, 0)) > SQRT(c.clean_ord_bar)) AS clean_click_collapse,
      (COALESCE(c.guard_prior_clk, 0) >= k.prior_meas_clk) AS guard_applicable
    FROM calc c CROSS JOIN k
  ),
  st AS (
    SELECT v.*,
      -- THE RAW LADDER (first match wins — order is doctrine, see the SOP table)
      CASE
        -- A7: DEAD re-derived from current data every run. A tested loser carrying a SIBLING
        -- verdict must SURFACE, not vanish into DEAD.
        WHEN COALESCE(v.settled_clk90, 0) >= 15 AND COALESCE(v.settled_ord90, 0) = 0
         AND COALESCE(v.reverdict, '') NOT IN ('SIBLING_REVIVE', 'REDUNDANT') THEN 'DEAD'
        WHEN v.reverdict = 'PENDING_SETTLE' THEN 'PENDING_SETTLE'
        WHEN COALESCE(v.revive_settling, FALSE) THEN 'REVIVED_SETTLING'
        WHEN v.reverdict IN ('REVIVE', 'SIBLING_REVIVE', 'CONFIRM_PARK', 'REDUNDANT', 'INSUFFICIENT') THEN 'PARKED'
        -- A8: a launch is never judged on profit, including in its label
        WHEN v.bar_exempt THEN
          CASE WHEN COALESCE(v.settled_roas90, 1) < 0.6 AND COALESCE(v.settled_clk90, 0) >= v.vol_floor
                 THEN 'LAUNCH_CONTAINED'
               WHEN COALESCE(v.settled_roas90, 0) >= 1.0 AND COALESCE(v.settled_clk90, 0) >= v.vol_floor
                 THEN IF(v.paced_today, 'PACED_WINNER', 'WINNER')
               ELSE 'TRIAL' END
        WHEN COALESCE(v.settled_clk90, 0) < v.vol_floor THEN 'TRIAL'
        WHEN COALESCE(v.settled_ord90, 0) = 0 THEN 'TRIAL'
        WHEN COALESCE(v.settled_roas90, 0) - v.family_bar > COALESCE(v.se_eff, 0)
          THEN IF(v.paced_today, 'PACED_WINNER', 'WINNER')
        -- the noise band (A2: click sufficiency may forbid hiding; A2b: an unexecutable price
        -- resolves to LOSER per ruling 4)
        WHEN ABS(COALESCE(v.settled_roas90, 0) - v.family_bar) <= COALESCE(v.se_eff, 0)
             AND NOT v.click_collapse
          THEN IF(COALESCE(v.current_bid, 999) < v.platform_floor, 'LOSER', 'AT_BAR')
        -- below bar beyond noise, but an affordable price EXISTS above the floor and it is not
        -- there yet: the move is a REPRICE, not a kill
        WHEN COALESCE(v.affordable_cpc, 0) > v.platform_floor
             AND COALESCE(v.settled_cpc90, 0) > COALESCE(v.affordable_cpc, 0) * (1 + v.reprice_material)
             AND COALESCE(v.current_bid, 999) > v.platform_floor THEN 'REPRICE'
        -- RULING 4: failed AT its price
        ELSE 'LOSER'
      END AS raw_state,
      -- THE CLEAN LADDER (same shape, cleaned numbers) — only consulted when the guard defers
      CASE
        WHEN COALESCE(v.clean_clk90, 0) < v.vol_floor THEN 'TRIAL'
        WHEN COALESCE(v.clean_ord90, 0) = 0 THEN IF(COALESCE(v.clean_clk90, 0) >= 15, 'DEAD', 'TRIAL')
        WHEN COALESCE(v.clean_roas90, 0) - v.family_bar > COALESCE(v.clean_se_eff, 0) THEN 'WINNER'
        WHEN ABS(COALESCE(v.clean_roas90, 0) - v.family_bar) <= COALESCE(v.clean_se_eff, 0)
             AND NOT v.clean_click_collapse
          THEN IF(COALESCE(v.current_bid, 999) < v.platform_floor, 'LOSER', 'AT_BAR')
        WHEN COALESCE(v.clean_affordable_cpc, 0) > v.platform_floor
             AND COALESCE(v.clean_cpc90, 0) > COALESCE(v.clean_affordable_cpc, 0) * (1 + v.reprice_material)
             AND COALESCE(v.current_bid, 999) > v.platform_floor THEN 'REPRICE'
        ELSE 'LOSER'
      END AS clean_state
    FROM verd v
  ),
  fin AS (
    SELECT s.*,
      -- THE GUARD: a deterioration verdict on a drifted mix is deferred and re-read cleaned
      (s.guard_applicable AND COALESCE(s.guard_ns_share, 0) > s.guard_bar_material
       AND s.raw_state IN ('REPRICE', 'LOSER')) AS guard_deferred_c,
      IF(s.guard_applicable AND COALESCE(s.guard_ns_share, 0) > s.guard_bar_material
         AND s.raw_state IN ('REPRICE', 'LOSER'), s.clean_state, s.raw_state) AS state_c
    FROM st s
  )
  SELECT
    CURRENT_DATE('America/Los_Angeles') AS snapshot_date,
    s.campaign_id, s.keyword_id, s.target_text, s.match_type, s.channel, s.is_auto, s.is_pt,
    s.campaign_name, s.family, s.current_bid,
    s.state_c AS state,
    CASE WHEN s.reverdict = 'REVIVE' AND COALESCE(s.campaign_owner, 'LIFT') = 'LIFT'
         THEN 'REVERDICT' ELSE COALESCE(s.campaign_owner, 'LIFT') END AS owner_engine,
    CASE WHEN s.state_c IN ('PARKED', 'PENDING_SETTLE') THEN s.park_date
         ELSE COALESCE(s.last_bid_change_date, s.last_applied) END AS state_since,
    s.settled_clk90, s.settled_ord90, s.settled_roas90, s.settled_cpc90,
    s.settled_gp90, s.settled_sp90,
    s.season_win_prior AS season_context,
    -- NEXT APPOINTMENT (invariant 2: NULL only on DEAD — A9)
    CASE s.state_c
      WHEN 'DEAD' THEN CAST(NULL AS DATE)
      WHEN 'PENDING_SETTLE' THEN COALESCE(s.rv_settle_due, DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY))
      WHEN 'REVIVED_SETTLING' THEN COALESCE(s.rv_settle_due, DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY))
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN CURRENT_DATE('America/Los_Angeles')
          WHEN 'SIBLING_REVIVE' THEN CURRENT_DATE('America/Los_Angeles')
          WHEN 'CONFIRM_PARK' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
          WHEN 'REDUNDANT' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
          ELSE COALESCE(s.rv_settle_due, DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)) END
      WHEN 'PACED_WINNER' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
      -- A9: AT_BAR gets a real appointment — the 7d re-read cadence (its N_f collapse date
      -- cannot be forecast from a rate; the re-read reads it when it lands)
      WHEN 'AT_BAR' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      -- A9: REPRICE is re-judged after the price move lands (T+14 = the scorecard's settled
      -- read); until a move is applied, the 7d re-read stands
      WHEN 'REPRICE' THEN COALESCE(
          IF(s.last_applied IS NOT NULL, DATE_ADD(s.last_applied, INTERVAL 14 DAY), NULL),
          DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY))
      WHEN 'LOSER' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      WHEN 'LAUNCH_CONTAINED' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      ELSE COALESCE(
        IF(NOT COALESCE(s.settle_ok, TRUE), s.settle_due, NULL),
        IF(s.last_applied IS NOT NULL, DATE_ADD(s.last_applied, INTERVAL 14 DAY), NULL),
        DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)) END AS next_check_date,
    CASE s.state_c
      WHEN 'DEAD' THEN 'tested loser — thesis falsified; only family sibling evidence reopens it'
      WHEN 'PENDING_SETTLE' THEN 'park re-judged when its clicks settle'
      WHEN 'REVIVED_SETTLING' THEN 'revived — new clicks settling before the next verdict'
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN "revival proposed — in today's plan"
          WHEN 'CONFIRM_PARK' THEN 'park confirmed on settled evidence — 14d revival sweep re-checks'
          ELSE 'parked, record too thin to judge — re-read at settle' END
      WHEN 'PACED_WINNER' THEN 'winner being paced today (capped budget) — pace re-fires daily'
      WHEN 'WINNER' THEN 'clears its family bar beyond noise — holding; the budget raise is the lever'
      WHEN 'AT_BAR' THEN 'at its family bar within noise — 7d re-read; the band collapses at N_f orders'
      WHEN 'REPRICE' THEN 'affordable price exists below its CPC — the reprice book carries the move'
      WHEN 'LOSER' THEN 'failed at its price — kill candidate in the reprice book (CHECK FIRST)'
      WHEN 'LAUNCH_CONTAINED' THEN 'launch family — never judged on profit; contained by the launch model'
      ELSE 'gathering evidence at seat pace' END AS next_check_what,
    CASE s.state_c
      WHEN 'DEAD' THEN CONCAT(CAST(s.settled_clk90 AS STRING), ' settled clicks, 0 orders')
      WHEN 'WINNER' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x vs bar ',
          FORMAT('%.2f', s.family_bar), ' over ', CAST(s.settled_clk90 AS STRING), ' settled clicks')
      WHEN 'PACED_WINNER' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)),
          'x proven; a GO pace instruction is live today')
      WHEN 'AT_BAR' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x vs bar ',
          FORMAT('%.2f', s.family_bar), ' within its noise band (se ',
          FORMAT('%.2f', COALESCE(s.se_eff, 0)), ') at ', CAST(COALESCE(s.settled_ord90, 0) AS STRING),
          ' orders; band collapses at ', CAST(COALESCE(s.nf_orders, 0) AS STRING))
      WHEN 'REPRICE' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x vs bar ',
          FORMAT('%.2f', s.family_bar), ' beyond noise; settled CPC $',
          FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_cpc90, s.settled_cpc90), 0)),
          ' vs affordable $',
          FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_affordable_cpc, s.affordable_cpc), 0)))
      WHEN 'LOSER' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x vs bar ',
          FORMAT('%.2f', s.family_bar),
          -- ruling 4 has three kill paths; name the one that actually fired
          CASE
            WHEN COALESCE(s.current_bid, 999) < s.platform_floor THEN
              CONCAT(' — bid $', FORMAT('%.2f', COALESCE(s.current_bid, 0)),
                     ' already sits below the $', FORMAT('%.2f', s.platform_floor),
                     ' floor: no executable price left, and the record does not clear the bar beyond its noise')
            WHEN COALESCE(IF(s.guard_deferred_c, s.clean_affordable_cpc, s.affordable_cpc), 0)
                 <= s.platform_floor THEN
              CONCAT(' beyond noise — no price above the $', FORMAT('%.2f', s.platform_floor),
                     ' floor is affordable at this record')
            ELSE ' beyond noise, and already at/below its affordable price — failed AT its price'
          END)
      WHEN 'LAUNCH_CONTAINED' THEN CONCAT('launch family (bar-exempt): ',
          FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x over ',
          CAST(COALESCE(s.settled_clk90, 0) AS STRING), ' clicks — contained, not condemned')
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN CONCAT('settled record overturns the park — revival proposed at $',
                                    FORMAT('%.2f', COALESCE(s.revive_bid, 0)))
          WHEN 'SIBLING_REVIVE' THEN 'a sibling campaign proves this term — revival proposed (hand-check)'
          WHEN 'REDUNDANT' THEN 'family already serves this term elsewhere — stays parked (no double-bid)'
          WHEN 'CONFIRM_PARK' THEN CONCAT('re-checked on full 90d data (',
              CAST(COALESCE(s.settled_clk90, s.rv_clk90, 0) AS STRING), ' clicks) — the park stands')
          ELSE CONCAT('only ', CAST(COALESCE(s.settled_clk90, s.rv_clk90, 0) AS STRING),
                      ' settled clicks — too thin to judge either way yet') END
      ELSE CONCAT(CAST(COALESCE(s.settled_clk90, 0) AS STRING), ' settled clicks so far') END AS state_reason,
    -- bar/SE machinery, published for the book and the morning read
    s.family_bar, s.bar_exempt, s.nf_orders, s.se_eff, s.gp_per_click, s.affordable_cpc,
    s.ord_bar_expected, s.click_collapse,
    -- clean-then-judge guard, published
    s.guard_prior_clk, s.guard_ns_share, s.guard_bar_material,
    s.guard_deferred_c AS guard_deferred,
    (s.guard_deferred_c AND s.clean_state NOT IN ('REPRICE', 'LOSER')) AS guard_flip,
    s.clean_clk90, s.clean_ord90, s.clean_roas90, s.clean_cpc90, s.clean_affordable_cpc,
    s.ns_zero_ord_terms, s.ns_zero_ord_clicks
  FROM fin s;
END;
