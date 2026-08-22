-- =============================================
-- SP_SNAPSHOT_KEYWORD_STATE — the roadmap of each keyword (2026-08-16, Task 2.1).
-- v27.103 (2026-08-22): THE BAR/SE LADDER — Ori's four rulings + the clean-then-judge guard.
-- v27.104 (2026-08-22): THE FLOOR RULING — one floor per channel and creative (FN_BID_FLOOR via
--   V_BID_FLOOR), affordability tested in BID space, FLOOR_PROBATION, the kill only at the floor,
--   and the guard extended to AT_BAR's standing price. Spec: architecture/KEYWORD_STATE.md.
--   Simulation of record: TMP_SIM_LADDER_FLOOR
--   (scripts/bigquery/simulations/SIM_2026-08-22_ladder_floor_probation.sql) — the gate this
--   implementation had to reproduce row for row (855 tracked keys).
-- v27.105 (2026-08-22): THE CLOCK STARTS WHEN THE FLOOR BID LANDS. The v27.104 clock started at
--   the later of floor_since and the last bid change — which stamped a running clock and a due
--   date on keywords whose floor bid had never been uploaded (the two BOTTLE-SP/AUTO clauses sat
--   at $0.22 / $0.24 over a $0.20 floor with a clock "running"). Now: the clock starts only once
--   the live bid is OBSERVED at the floor (at_floor — a change-log row is a claim until the
--   Fivetran mirror confirms it; a book logged at build time and never uploaded must never start
--   a clock), and probation_clock_start is the date the floor bid LANDED: the earliest applied
--   row in V_PPC_CHANGE_LOG_APPLIED at/below the floor (half a cent of tolerance) after the last
--   row above it and on/after floor_since — so the 1-2 day mirror lag only delays the start, it
--   does not shift the date — else the last bid change. Until then the clock, the settled-click
--   count and the due date are NULL and the state publishes "waiting for the floor bid"; the
--   appointment falls back to the 7d re-read so invariant 2 holds. Nothing else in the ladder
--   changed — state counts are identical to v27.104 except these probation fields.
--
-- WHAT CHANGED vs v27.103 (Ori, verbatim: "floor question bid-up-to-floor if after a few days
-- still loosing kill it" and "i think it is not 0.25 (we already checked it)"):
--   FLOOR     the flat $0.25 "platform_floor" is GONE. It was V_OOB_KEYWORD's bid_park — a PARKING
--             price, not a floor — and it manufactured three phantom kills. A keyword's floor is
--             its CHANNEL's and CREATIVE's: DIM_KEYWORD -> ad_group_id -> V_BID_FLOOR
--             (FN_BID_FLOOR: SP $0.20 house; SB collection/spotlight $0.10; SB video / unknown
--             creative $0.25). A keyword whose ad group cannot be resolved falls back to
--             FN_BID_FLOOR(channel, NULL) and says so in bid_floor_source.
--   A4 PRICE  affordable BID = affordable CPC / the campaign's measured placement multiplier
--             (V_BID_CPC_TRANSFER.m_effective, MAX over target kinds — the book's own reading).
--             The floor is a BID floor, so executability is tested in bid space.
--   FLOOR_PROBATION (NEW)  below bar beyond noise AND (the bid sits at/below its floor OR no
--             affordable bid exists at/above it): the move is TO THE FLOOR, from either side, and
--             the keyword is re-judged after a few settled days AT the floor. "A few days" is
--             DERIVED, never a round number: probation ELAPSES on evidence — >= vol_floor (10)
--             settled clicks dated on/after the probation clock start — and its appointment is
--             the earliest date that evidence can exist: clock start + settle_days_eff (the
--             guard's own discipline, SP 3 / SB 14) + CEIL(10 / the keyword's own 90d click pace).
--   MEMORY    floor_since is the date this state machine put the keyword on probation. It is
--             carried forward from THIS TABLE's OWN PRIOR ROW (read into a temp table before the
--             rebuild — the SP reading its own previous output is not an engine reading the
--             table) and seeded on the first v27.104 run. The probation CLOCK (v27.105 rule, see
--             above) starts only once the floor bid has landed. Leaving probation for any
--             non-kill state clears the memory.
--   LOSER     ONLY a keyword whose probation has ELAPSED, whose bid sits at its floor, and which
--             still reads below bar beyond noise. An above-bar keyword is NEVER a kill, whatever
--             its bid (the v27.103 A2b "unexecutable AT_BAR -> LOSER" arm is REPEALED); the
--             v27.103 "failed AT its price" CPC-materiality kill arm is REPEALED too — a keyword
--             is only ever killed at the floor.
--   GUARD     clean-then-judge now defers EVERY verdict that can move a bid DOWN: the three
--             deterioration verdicts (REPRICE / FLOOR_PROBATION / LOSER — re-read cleaned; only
--             the cleaned reading may downgrade the LABEL) and AT_BAR's standing price when it
--             would cut the bid (guard_scope = AT_BAR_PRICE: the label stays AT_BAR — the raw
--             record is what it is and the band is terminal — but guard_deferred is TRUE and
--             the book prices the row on its cleaned record, never on a mix the guard already
--             knows is drifted). Step-1 finding: `complements` BOX-SP/AUTO (Purple), 0.57x shown
--             / 1.90x on its own terms, would otherwise have booked a cut to the floor.
--   A9        next_check_date is NULL only on DEAD. AT_BAR gets the EARLIER of its forecast N_f
--             collapse date (from its own 90d order pace) and the 7d re-read; REPRICE gets
--             last-applied + 14d when that date is still ahead, else the 7d re-read;
--             FLOOR_PROBATION gets its derived probation due date; LOSER the 7d re-read.
--
-- Everything below that is not named above is v27.103 unchanged: rulings 1/2 (family bar, SE band
-- collapsing at per-family N_f computed at run time, winner demotion), A2 click-space
-- sufficiency, A3 one window, A7 DEAD re-derived every run, A8 launch exemption, the guard's
-- run-time-derived background bar, and the assembly of reverdict / ownership / pacing verdicts.
--
-- NO ENGINE reads FACT_KEYWORD_STATE. The only executor is the manual reprice book
-- (tools/build_reprice_bulksheet.py) Ori uploads by hand. Orchestrator Task 20.8, after the
-- preflight (20.7) and after SP_SNAPSHOT_FAMILY_BAR (T_FAMILY_BAR must be fresh).
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE`()
OPTIONS (
  description = "Keyword state machine, bar/SE ladder with per-channel floors (v27.105, 2026-08-22 — the probation clock starts only when the live bid is observed at the floor, dated by the applied change-log row that landed it; NULL = waiting for the floor bid): one row per (campaign, keyword) — state (DEAD | PENDING_SETTLE | REVIVED_SETTLING | PARKED | PACED_WINNER | WINNER | AT_BAR | REPRICE | FLOOR_PROBATION | LOSER | LAUNCH_CONTAINED | TRIAL, first-match ladder), judged against the FAMILY bar (T_FAMILY_BAR) inside an SE noise band that collapses at per-family N_f orders, the A2 click-space sufficiency check, the A8 launch exemption, affordability in BID space (affordable CPC / V_BID_CPC_TRANSFER.m_effective) against the keyword's OWN floor (DIM_KEYWORD -> V_BID_FLOOR -> FN_BID_FLOOR: SP $0.20, SB collection $0.10, SB video/unknown $0.25), FLOOR_PROBATION (bid to the floor, re-judged when >= 10 settled clicks exist at the floor — floor_since carried forward from this table's own prior row), LOSER only after an elapsed probation at the floor, and the clean-then-judge guard over every verdict that can move a bid down (deterioration labels re-read cleaned; AT_BAR's standing price deferred to its cleaned record). NO ENGINE reads this table — the only executor is the manual reprice book (tools/build_reprice_bulksheet.py). Invariants read by V_ENGINE_HEALTH. Spec: architecture/KEYWORD_STATE.md."
)
BEGIN
  DECLARE has_table BOOL DEFAULT FALSE;
  DECLARE has_memory BOOL DEFAULT FALSE;

  -- PROBATION MEMORY: read this table's own prior row BEFORE the rebuild. The column is absent
  -- before the first v27.104 run (and the table itself is absent on a fresh project), so the
  -- read is shaped by what exists — never a failure on first run.
  SET has_table = (SELECT COUNT(*) > 0 FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
                   WHERE table_name = 'FACT_KEYWORD_STATE');
  SET has_memory = (SELECT COUNT(*) > 0 FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
                    WHERE table_name = 'FACT_KEYWORD_STATE' AND column_name = 'floor_since');
  IF has_memory THEN
    CREATE TEMP TABLE prior_snapshot AS
    SELECT campaign_id, keyword_id, state AS prior_state, floor_since AS prior_floor_since
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;
  ELSEIF has_table THEN
    CREATE TEMP TABLE prior_snapshot AS
    SELECT campaign_id, keyword_id, state AS prior_state, CAST(NULL AS DATE) AS prior_floor_since
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;
  ELSE
    CREATE TEMP TABLE prior_snapshot AS
    SELECT CAST(NULL AS STRING) AS campaign_id, CAST(NULL AS STRING) AS keyword_id,
           CAST(NULL AS STRING) AS prior_state, CAST(NULL AS DATE) AS prior_floor_since
    WHERE FALSE;
  END IF;

  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_KEYWORD_STATE` AS
  WITH
  -- Declared constants (Standing Rule 0 exempt), each with its derivation:
  --   vol_floor 10        the guard's own settled-click floor (V_KEYWORD_GUARD min_settled_clk);
  --                       also the evidence a probation needs before it can elapse
  --   reprice_material 5% one daily ease step — the engine's smallest standing move; the book's
  --                       materiality step and the guard's "would this cut the bid" test
  --   term_meas_clk 5     a term is measurable in the judging window at >= 5 clicks
  --   prior_meas_clk 10   a prior record exists at >= 10 prior-window clicks
  --   bid_tol 0.005       half a cent: bulk uploads round to the cent, so a bid within half a
  --                       cent of its floor IS at its floor
  k AS (SELECT 10 AS vol_floor, 0.05 AS reprice_material,
               5 AS term_meas_clk, 10 AS prior_meas_clk, 0.005 AS bid_tol),
  today AS (SELECT CURRENT_DATE('America/Los_Angeles') AS d),
  wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
         FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
  g AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           keyword_text, match_type, channel, is_auto, is_pt, current_bid, parent_name,
           settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
           settled_gp90, settled_sp90,
           settle_ok, settle_due, last_click_date, season_win_prior, last_bid_change_date,
           CAST(settle_days_eff AS INT64) AS settle_days_eff
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
  -- THE FLOOR: keyword -> ad group (DIM_KEYWORD, current row first) -> V_BID_FLOOR (the one
  -- definition, resolved per ad group from its creative_type)
  kag AS (SELECT CAST(keyword_id AS STRING) kid, CAST(ad_group_id AS STRING) ad_group_id
          FROM `onyga-482313.OI.DIM_KEYWORD`
          QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY is_current DESC, effective_from DESC) = 1),
  bf AS (SELECT ad_group_id, bid_floor, bid_floor_source, creative_type
         FROM `onyga-482313.OI.V_BID_FLOOR`),
  -- A4: the campaign's measured placement multiplier (MAX over target kinds, as the book reads it)
  m AS (SELECT CAST(campaign_id AS STRING) cid, MAX(m_effective) AS m_eff,
               LOGICAL_OR(is_brand_defense) AS is_brand_defense
        FROM `onyga-482313.OI.V_BID_CPC_TRANSFER` GROUP BY 1),
  pr AS (SELECT campaign_id cid, keyword_id kid, prior_state, prior_floor_since FROM prior_snapshot),
  -- v27.105 THE FLOOR BID LANDED: for a keyword on probation, the date the applied change log
  -- first shows a bid at/below its channel floor (bid_tol) after the last applied bid ABOVE it,
  -- on/after floor_since. A book row that is never uploaded never appears here.
  landed AS (
    SELECT pr.cid, pr.kid, MIN(DATE(l.applied_at, 'America/Los_Angeles')) AS floor_bid_landed
    FROM pr
    JOIN kag ON kag.kid = pr.kid
    JOIN bf ON bf.ad_group_id = kag.ad_group_id
    JOIN `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` l
      ON CAST(l.campaign_id AS STRING) = pr.cid AND CAST(l.keyword_id AS STRING) = pr.kid
     AND l.new_bid IS NOT NULL
    CROSS JOIN k
    WHERE pr.prior_floor_since IS NOT NULL
      AND DATE(l.applied_at, 'America/Los_Angeles') >= pr.prior_floor_since
      AND l.new_bid <= bf.bid_floor + k.bid_tol
      AND DATE(l.applied_at, 'America/Los_Angeles') > COALESCE((
            SELECT MAX(DATE(a.applied_at, 'America/Los_Angeles'))
            FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` a
            WHERE CAST(a.campaign_id AS STRING) = pr.cid AND CAST(a.keyword_id AS STRING) = pr.kid
              AND a.new_bid > bf.bid_floor + k.bid_tol), DATE '1900-01-01')
    GROUP BY 1, 2),
  -- THE PROBATION CLOCK (v27.105): starts only once the live bid is OBSERVED at the floor (a
  -- logged row is a claim until the mirror confirms it — a book logged at build time and never
  -- uploaded must never start a clock); the applied log supplies the landing DATE (the mirror
  -- lags 1-2 days, so the start is back-dated to the day the floor bid was applied), else the
  -- last bid change dates it. Not at the floor -> NULL: the clock has not started.
  clock AS (
    SELECT pr.cid, pr.kid,
           IF(COALESCE(g.current_bid, 999) <= bf.bid_floor + k.bid_tol,
              COALESCE(ld.floor_bid_landed,
                       GREATEST(pr.prior_floor_since, COALESCE(g.last_bid_change_date, pr.prior_floor_since))),
              NULL) AS clock_start
    FROM pr
    JOIN g ON g.cid = pr.cid AND g.kid = pr.kid
    LEFT JOIN kag ON kag.kid = pr.kid
    LEFT JOIN bf ON bf.ad_group_id = kag.ad_group_id
    LEFT JOIN landed ld ON ld.cid = pr.cid AND ld.kid = pr.kid
    CROSS JOIN k
    WHERE pr.prior_floor_since IS NOT NULL AND bf.bid_floor IS NOT NULL),
  -- PROBATION EVIDENCE: settled clicks since the probation clock started (the day the floor bid
  -- landed — v27.105), inside the guard's own settle discipline
  cs AS (
    SELECT c.cid, c.kid, ANY_VALUE(c.clock_start) AS clock_start,
           SUM(f.Ads_clicks) AS clk_since_floor_settled
    FROM clock c
    JOIN g ON g.cid = c.cid AND g.kid = c.kid
    LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
      ON CAST(f.campaign_id AS STRING) = c.cid AND CAST(f.keyword_id AS STRING) = c.kid
     AND f.date >= c.clock_start
    CROSS JOIN wm
    WHERE c.clock_start IS NOT NULL
      AND (f.date IS NULL OR f.date <= DATE_SUB(wm.d, INTERVAL COALESCE(g.settle_days_eff, IF(g.channel = 'SB', 14, 3)) DAY))
    GROUP BY 1, 2),
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
      COALESCE(g.settle_days_eff, IF(COALESCE(g.channel, rv.channel) = 'SB', 14, 3)) AS settle_days_eff,
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
      -- THE FLOOR (one definition; unresolved ad group -> the channel's conservative floor)
      kag.ad_group_id, bf.creative_type,
      COALESCE(bf.bid_floor, `onyga-482313.OI.FN_BID_FLOOR`(b.channel, NULL).bid_floor) AS bid_floor,
      COALESCE(bf.bid_floor_source,
               CONCAT(`onyga-482313.OI.FN_BID_FLOOR`(b.channel, NULL).bid_floor_source, '_NO_ADGROUP')) AS bid_floor_source,
      m.m_eff AS m_effective,
      COALESCE(m.is_brand_defense, FALSE) AS is_brand_defense,
      SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_clk90, 0)) AS gp_per_click,
      -- the price this record affords at the family bar (settled window — A3), in CPC space...
      SAFE_DIVIDE(SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_clk90, 0)),
                  COALESCE(fb.keyword_bar, 1.0)) AS affordable_cpc,
      -- ...and translated to BID space through the campaign's placement multiplier (A4)
      SAFE_DIVIDE(SAFE_DIVIDE(SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_clk90, 0)),
                              COALESCE(fb.keyword_bar, 1.0)),
                  COALESCE(m.m_eff, 1.0)) AS affordable_bid,
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
      SAFE_DIVIDE(SAFE_DIVIDE(SAFE_DIVIDE(w.c_gp, NULLIF(w.c_clk, 0)),
                              COALESCE(fb.keyword_bar, 1.0)),
                  COALESCE(m.m_eff, 1.0)) AS clean_affordable_bid,
      IF(COALESCE(w.c_ord, 0) >= COALESCE(nf.nf_orders, 999999), 0.0,
         IF(COALESCE(w.c_ord, 0) > 0,
            SAFE_DIVIDE(w.c_gp, NULLIF(w.c_sp, 0)) / SQRT(w.c_ord), NULL)) AS clean_se_eff,
      SAFE_DIVIDE(w.c_sp * COALESCE(fb.keyword_bar, 1.0), gpo.gpo_f) AS clean_ord_bar,
      w.ns_zero_ord_terms, w.ns_zero_ord_clicks,
      -- probation memory (this table's own prior row) and the evidence gathered since
      pr.prior_state, pr.prior_floor_since,
      cs.clk_since_floor_settled,
      cs.clock_start AS floor_clock_start   -- v27.105: NULL until the floor bid has landed
    FROM base b
    LEFT JOIN po ON po.cid = b.campaign_id
    LEFT JOIN pf ON pf.cid = b.campaign_id AND pf.kid = b.keyword_id
    LEFT JOIN lc ON lc.cid = b.campaign_id AND lc.kid = b.keyword_id
    LEFT JOIN fb ON fb.campaign_id = b.campaign_id
    LEFT JOIN nf ON nf.family = fb.family
    LEFT JOIN gpo ON gpo.family = fb.family
    LEFT JOIN kwg w ON w.cid = b.campaign_id AND w.kid = b.keyword_id
    LEFT JOIN pw ON pw.cid = b.campaign_id AND pw.kid = b.keyword_id
    LEFT JOIN kag ON kag.kid = b.keyword_id
    LEFT JOIN bf ON bf.ad_group_id = kag.ad_group_id
    LEFT JOIN m ON m.cid = b.campaign_id
    LEFT JOIN pr ON pr.cid = b.campaign_id AND pr.kid = b.keyword_id
    LEFT JOIN cs ON cs.cid = b.campaign_id AND cs.kid = b.keyword_id
    CROSS JOIN bg
  ),
  verd AS (
    SELECT c.*, k.reprice_material, k.vol_floor, k.prior_meas_clk, k.bid_tol,
      (COALESCE(c.settled_roas90, 0) < c.family_bar AND c.ord_bar_expected IS NOT NULL
       AND (c.ord_bar_expected - COALESCE(c.settled_ord90, 0)) > SQRT(c.ord_bar_expected)) AS click_collapse,
      (COALESCE(c.clean_roas90, 0) < c.family_bar AND c.clean_ord_bar IS NOT NULL
       AND (c.clean_ord_bar - COALESCE(c.clean_ord90, 0)) > SQRT(c.clean_ord_bar)) AS clean_click_collapse,
      (COALESCE(c.guard_prior_clk, 0) >= k.prior_meas_clk) AS guard_applicable,
      -- the bid sits at/below its own floor (half a cent of tolerance: bulk uploads round)
      (COALESCE(c.current_bid, 999) <= c.bid_floor + k.bid_tol) AS at_floor,
      -- probation elapsed = the clock has started (the floor bid landed — v27.105) AND
      -- >= vol_floor settled clicks since it started
      (c.prior_floor_since IS NOT NULL AND c.floor_clock_start IS NOT NULL
       AND COALESCE(c.clk_since_floor_settled, 0) >= k.vol_floor) AS probation_elapsed,
      -- would AT_BAR's standing price move the bid DOWN by more than the book's materiality step?
      (GREATEST(COALESCE(c.affordable_bid, 0), c.bid_floor)
         < COALESCE(c.current_bid, 0) - GREATEST(k.reprice_material * COALESCE(c.current_bid, 0), 0.01)) AS at_bar_would_cut
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
        -- the noise band (A2: click sufficiency may forbid hiding). AT_BAR whatever the bid —
        -- an at/above-bar keyword is NEVER a kill.
        WHEN ABS(COALESCE(v.settled_roas90, 0) - v.family_bar) <= COALESCE(v.se_eff, 0)
             AND NOT v.click_collapse THEN 'AT_BAR'
        -- below bar beyond noise, from here down. The ONLY kill: probation elapsed AT the floor.
        WHEN v.probation_elapsed AND v.at_floor THEN 'LOSER'
        -- at/below the floor, or no affordable bid at/above it: to the floor, then re-judge
        WHEN v.at_floor OR COALESCE(v.affordable_bid, 0) < v.bid_floor THEN 'FLOOR_PROBATION'
        -- an affordable bid exists at/above the floor and the bid is above the floor: move to it
        ELSE 'REPRICE'
      END AS raw_state,
      -- THE CLEAN LADDER (same shape, cleaned numbers) — consulted when the guard defers
      CASE
        WHEN COALESCE(v.clean_clk90, 0) < v.vol_floor THEN 'TRIAL'
        WHEN COALESCE(v.clean_ord90, 0) = 0 THEN IF(COALESCE(v.clean_clk90, 0) >= 15, 'DEAD', 'TRIAL')
        WHEN COALESCE(v.clean_roas90, 0) - v.family_bar > COALESCE(v.clean_se_eff, 0) THEN 'WINNER'
        WHEN ABS(COALESCE(v.clean_roas90, 0) - v.family_bar) <= COALESCE(v.clean_se_eff, 0)
             AND NOT v.clean_click_collapse THEN 'AT_BAR'
        WHEN v.probation_elapsed AND v.at_floor THEN 'LOSER'
        WHEN v.at_floor OR COALESCE(v.clean_affordable_bid, 0) < v.bid_floor THEN 'FLOOR_PROBATION'
        ELSE 'REPRICE'
      END AS clean_state,
      (v.guard_applicable AND COALESCE(v.guard_ns_share, 0) > v.guard_bar_material) AS guard_fires
    FROM verd v
  ),
  fin AS (
    SELECT s.*,
      -- THE GUARD covers every verdict that can move a bid DOWN:
      --   DETERIORATION  REPRICE / FLOOR_PROBATION / LOSER on a drifted mix — re-read cleaned;
      --                  only the cleaned reading may downgrade the label
      --   AT_BAR_PRICE   AT_BAR whose standing price would cut the bid — label stays, the
      --                  price the book may act on is the cleaned one
      CASE WHEN s.guard_fires AND s.raw_state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER') THEN 'DETERIORATION'
           WHEN s.guard_fires AND s.raw_state = 'AT_BAR' AND s.at_bar_would_cut THEN 'AT_BAR_PRICE'
           ELSE NULL END AS guard_scope,
      IF(s.guard_fires AND s.raw_state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER'),
         s.clean_state, s.raw_state) AS state_c
    FROM st s
  ),
  fin2 AS (
    SELECT f.*, today.d AS today_d,
      (f.guard_scope IS NOT NULL) AS guard_deferred_c,
      -- PROBATION MEMORY, written: kept while on probation or condemned by it; cleared otherwise
      CASE WHEN f.state_c IN ('FLOOR_PROBATION', 'LOSER') THEN COALESCE(f.prior_floor_since, today.d)
           ELSE NULL END AS floor_since_c,
      -- the keyword's own 90d click pace (clicks/day) — the rate at which evidence can arrive
      SAFE_DIVIDE(f.settled_clk90, 90.0) AS click_pace,
      -- N_f collapse forecast from the keyword's own order pace (AT_BAR appointment, A9)
      IF(f.nf_orders IS NOT NULL AND COALESCE(f.settled_ord90, 0) > 0
         AND f.nf_orders > COALESCE(f.settled_ord90, 0),
         DATE_ADD(today.d, INTERVAL CAST(CEIL((f.nf_orders - f.settled_ord90) / (f.settled_ord90 / 90.0)) AS INT64) DAY),
         NULL) AS nf_collapse_forecast_date
    FROM fin f CROSS JOIN today
  ),
  fin3 AS (
    SELECT f.*,
      -- the probation clock (v27.105): the day the floor bid LANDED (applied log, or a bid
      -- observed at the floor dated by its last change); NULL until then — no fiction
      IF(f.floor_since_c IS NOT NULL, f.floor_clock_start, NULL) AS probation_clock_start,
      -- "a few days", derived: clock start + settle discipline + the days this keyword's own
      -- pace needs for vol_floor clicks; never earlier than tomorrow (a past appointment is
      -- no appointment); no pace measured -> settle + the 7d re-read cadence; NO CLOCK -> NULL
      IF(f.state_c = 'FLOOR_PROBATION' AND f.floor_clock_start IS NOT NULL,
         GREATEST(
           DATE_ADD(
             DATE_ADD(f.floor_clock_start, INTERVAL f.settle_days_eff DAY),
             INTERVAL COALESCE(CAST(CEIL(SAFE_DIVIDE(f.vol_floor, NULLIF(f.click_pace, 0))) AS INT64), 7) DAY),
           DATE_ADD(f.today_d, INTERVAL 1 DAY)),
         NULL) AS probation_due_date
    FROM fin2 f
  )
  SELECT
    s.today_d AS snapshot_date,
    s.campaign_id, s.keyword_id, s.target_text, s.match_type, s.channel, s.is_auto, s.is_pt,
    s.campaign_name, s.family, s.current_bid,
    s.state_c AS state,
    CASE WHEN s.reverdict = 'REVIVE' AND COALESCE(s.campaign_owner, 'LIFT') = 'LIFT'
         THEN 'REVERDICT' ELSE COALESCE(s.campaign_owner, 'LIFT') END AS owner_engine,
    CASE WHEN s.state_c IN ('PARKED', 'PENDING_SETTLE') THEN s.park_date
         WHEN s.state_c IN ('FLOOR_PROBATION', 'LOSER') THEN s.floor_since_c
         ELSE COALESCE(s.last_bid_change_date, s.last_applied) END AS state_since,
    s.settled_clk90, s.settled_ord90, s.settled_roas90, s.settled_cpc90,
    s.settled_gp90, s.settled_sp90,
    s.season_win_prior AS season_context,
    -- NEXT APPOINTMENT (invariant 2: NULL only on DEAD — A9)
    CASE s.state_c
      WHEN 'DEAD' THEN CAST(NULL AS DATE)
      WHEN 'PENDING_SETTLE' THEN COALESCE(s.rv_settle_due, DATE_ADD(s.today_d, INTERVAL 7 DAY))
      WHEN 'REVIVED_SETTLING' THEN COALESCE(s.rv_settle_due, DATE_ADD(s.today_d, INTERVAL 7 DAY))
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN s.today_d
          WHEN 'SIBLING_REVIVE' THEN s.today_d
          WHEN 'CONFIRM_PARK' THEN DATE_ADD(s.today_d, INTERVAL 14 DAY)
          WHEN 'REDUNDANT' THEN DATE_ADD(s.today_d, INTERVAL 14 DAY)
          ELSE COALESCE(s.rv_settle_due, DATE_ADD(s.today_d, INTERVAL 14 DAY)) END
      WHEN 'PACED_WINNER' THEN DATE_ADD(s.today_d, INTERVAL 1 DAY)
      -- A9: AT_BAR — the earlier of its forecast N_f collapse and the 7d re-read, never before
      -- tomorrow
      WHEN 'AT_BAR' THEN GREATEST(
          LEAST(COALESCE(s.nf_collapse_forecast_date, DATE_ADD(s.today_d, INTERVAL 7 DAY)),
                DATE_ADD(s.today_d, INTERVAL 7 DAY)),
          DATE_ADD(s.today_d, INTERVAL 1 DAY))
      -- A9: REPRICE is re-judged after the price move lands (T+14 = the scorecard's settled
      -- read) when that date is still ahead; otherwise the 7d re-read stands
      WHEN 'REPRICE' THEN IF(s.last_applied IS NOT NULL
                             AND DATE_ADD(s.last_applied, INTERVAL 14 DAY) > s.today_d,
                             DATE_ADD(s.last_applied, INTERVAL 14 DAY),
                             DATE_ADD(s.today_d, INTERVAL 7 DAY))
      -- A9: FLOOR_PROBATION — its derived due date
      WHEN 'FLOOR_PROBATION' THEN COALESCE(s.probation_due_date, DATE_ADD(s.today_d, INTERVAL 7 DAY))
      WHEN 'LOSER' THEN DATE_ADD(s.today_d, INTERVAL 7 DAY)
      WHEN 'LAUNCH_CONTAINED' THEN DATE_ADD(s.today_d, INTERVAL 7 DAY)
      ELSE COALESCE(
        IF(NOT COALESCE(s.settle_ok, TRUE), s.settle_due, NULL),
        IF(s.last_applied IS NOT NULL AND DATE_ADD(s.last_applied, INTERVAL 14 DAY) > s.today_d,
           DATE_ADD(s.last_applied, INTERVAL 14 DAY), NULL),
        DATE_ADD(s.today_d, INTERVAL 7 DAY)) END AS next_check_date,
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
      WHEN 'AT_BAR' THEN IF(s.nf_collapse_forecast_date IS NOT NULL
                            AND s.nf_collapse_forecast_date <= DATE_ADD(s.today_d, INTERVAL 7 DAY),
                            'at its family bar within noise — its band is forecast to collapse at N_f orders by this date',
                            'at its family bar within noise — 7d re-read; the band collapses at N_f orders')
      WHEN 'REPRICE' THEN 'an affordable bid exists above its floor — the reprice book carries the move; re-judged after it settles'
      WHEN 'FLOOR_PROBATION' THEN IF(s.probation_clock_start IS NULL,
          'waiting for the floor bid to land — the reprice book carries the move to the floor; the probation clock starts the day it lands (7d re-read until then)',
          'on probation at its floor — re-judged once 10 settled clicks exist at the floor (this is the earliest that evidence can exist)')
      WHEN 'LOSER' THEN 'probation at the floor elapsed, still below bar — kill candidate in the reprice book (CHECK FIRST)'
      WHEN 'LAUNCH_CONTAINED' THEN 'launch family — never judged on profit; contained by the launch model'
      ELSE 'gathering evidence at seat pace' END AS next_check_what,
    -- STATE REASON: one plain sentence per state, on the numbers the verdict actually used
    CASE s.state_c
      WHEN 'DEAD' THEN CONCAT(CAST(s.settled_clk90 AS STRING), ' settled clicks, 0 orders')
      WHEN 'WINNER' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x vs bar ',
          FORMAT('%.2f', s.family_bar), ' over ', CAST(s.settled_clk90 AS STRING), ' settled clicks')
      WHEN 'PACED_WINNER' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)),
          'x proven; a GO pace instruction is live today')
      WHEN 'AT_BAR' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x vs bar ',
          FORMAT('%.2f', s.family_bar), ' within its noise band (se ',
          FORMAT('%.2f', COALESCE(s.se_eff, 0)), ') at ', CAST(COALESCE(s.settled_ord90, 0) AS STRING),
          ' orders; band collapses at ', CAST(COALESCE(s.nf_orders, 0) AS STRING),
          '; standing price $', FORMAT('%.2f', GREATEST(COALESCE(s.affordable_bid, 0), s.bid_floor)),
          ' bid vs $', FORMAT('%.2f', COALESCE(s.current_bid, 0)), ' now',
          IF(s.guard_scope = 'AT_BAR_PRICE',
             CONCAT(' — the mix-drift guard holds that cut: ', FORMAT('%.0f', COALESCE(s.guard_ns_share, 0) * 100),
                    '% of judged clicks are on never-seen terms, so the book prices the cleaned record ($',
                    FORMAT('%.2f', COALESCE(s.clean_affordable_bid, 0)), ' bid, ',
                    FORMAT('%.2f', COALESCE(s.clean_roas90, 0)), 'x on its own terms)'),
             ''))
      WHEN 'REPRICE' THEN CONCAT(FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_roas90, s.settled_roas90), 0)),
          'x vs bar ', FORMAT('%.2f', s.family_bar), ' beyond noise; the record affords a $',
          FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_affordable_bid, s.affordable_bid), 0)),
          ' bid ($', FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_affordable_cpc, s.affordable_cpc), 0)),
          ' CPC through a ', FORMAT('%.2f', COALESCE(s.m_effective, 1.0)), ' placement multiplier) against $',
          FORMAT('%.2f', COALESCE(s.current_bid, 0)), ' now, above its $', FORMAT('%.2f', s.bid_floor),
          ' floor', IF(s.guard_deferred_c, ' — judged on its own terms (mix-drift guard)', ''))
      WHEN 'FLOOR_PROBATION' THEN CONCAT(FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_roas90, s.settled_roas90), 0)),
          'x vs bar ', FORMAT('%.2f', s.family_bar), ' beyond noise — ',
          CASE WHEN s.at_floor THEN CONCAT('its bid $', FORMAT('%.2f', COALESCE(s.current_bid, 0)),
                                            ' already sits at its $', FORMAT('%.2f', s.bid_floor), ' floor')
               ELSE CONCAT('the record affords only a $',
                           FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_affordable_bid, s.affordable_bid), 0)),
                           ' bid, under its $', FORMAT('%.2f', s.bid_floor), ' floor; the move is $',
                           FORMAT('%.2f', COALESCE(s.current_bid, 0)), ' -> $', FORMAT('%.2f', s.bid_floor)) END,
          '; on probation since ', CAST(s.floor_since_c AS STRING),
          IF(s.probation_clock_start IS NULL,
             ' — WAITING FOR THE FLOOR BID TO LAND: the live bid is not at the floor, so the probation clock has not started (re-read in 7d; the day an applied floor bid is confirmed, the clock back-dates to it)',
             CONCAT(' with ', CAST(COALESCE(s.clk_since_floor_settled, 0) AS STRING), ' of ', CAST(s.vol_floor AS STRING),
                    ' settled clicks at the floor since it landed on ', CAST(s.probation_clock_start AS STRING),
                    ' — re-judged on ', CAST(COALESCE(s.probation_due_date, DATE_ADD(s.today_d, INTERVAL 7 DAY)) AS STRING),
                    ' at the earliest (', CAST(s.settle_days_eff AS STRING), 'd settle + its own click pace)')),
          IF(s.guard_deferred_c, ' — judged on its own terms (mix-drift guard)', ''))
      WHEN 'LOSER' THEN CONCAT(FORMAT('%.2f', COALESCE(IF(s.guard_deferred_c, s.clean_roas90, s.settled_roas90), 0)),
          'x vs bar ', FORMAT('%.2f', s.family_bar), ' beyond noise AFTER its probation at the $',
          FORMAT('%.2f', s.bid_floor), ' floor: ', CAST(COALESCE(s.clk_since_floor_settled, 0) AS STRING),
          ' settled clicks at the floor since ', CAST(s.probation_clock_start AS STRING),
          ' (probation began ', CAST(s.floor_since_c AS STRING),
          ') and the record still does not clear the bar — no cheaper price exists, the move is a pause (CHECK FIRST)',
          IF(s.guard_deferred_c, ' — judged on its own terms (mix-drift guard)', ''))
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
    (s.guard_scope = 'DETERIORATION' AND s.clean_state NOT IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER')) AS guard_flip,
    s.clean_clk90, s.clean_ord90, s.clean_roas90, s.clean_cpc90, s.clean_affordable_cpc,
    s.ns_zero_ord_terms, s.ns_zero_ord_clicks,
    -- v27.104: the floor, the bid-space price, the guard's scope, the probation record
    s.ad_group_id, s.creative_type, s.bid_floor, s.bid_floor_source,
    s.m_effective, s.is_brand_defense,
    s.affordable_bid, s.clean_affordable_bid,
    s.at_floor,
    s.guard_scope,
    s.raw_state, s.clean_state,
    s.settle_days_eff,
    s.floor_since_c AS floor_since,
    s.probation_clock_start,
    -- v27.105: NULL until the clock has started (no floor bid landed = no evidence at the floor)
    IF(s.floor_since_c IS NOT NULL AND s.probation_clock_start IS NOT NULL,
       COALESCE(s.clk_since_floor_settled, 0), NULL) AS probation_clk_settled,
    s.probation_elapsed,
    s.probation_due_date,
    IF(s.state_c = 'FLOOR_PROBATION', s.bid_floor, NULL) AS probation_bid,
    s.nf_collapse_forecast_date,
    s.prior_state
  FROM fin3 s;
END;
