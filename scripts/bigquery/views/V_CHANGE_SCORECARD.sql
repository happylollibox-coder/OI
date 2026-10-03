-- =============================================
-- V_CHANGE_SCORECARD — settled outcome grading of every applied PPC change
-- (2026-08-12). Spec: architecture/PPC_CLOSE_THE_LOOP.md §V_CHANGE_SCORECARD.
--
-- WHY THIS EXISTS: Ori changes bids/budgets/negatives daily and, until this view, NOTHING ever
-- told him whether a change worked. His doctrine — "1 day for opportunity, 7 days for OUTCOME"
-- (2026-08-11) — was tested end to end: the opportunity half was REJECTED (a standout day marks
-- the stretch you were already in), the outcome half measured as the best instrument in the
-- system: settled 7-day verdicts separate the FOLLOWING FORTNIGHT by +0.598 GP-ROAS
-- (FAIL 0.342 -> next-14d 0.993; STRONG 2.129 -> next-14d 1.591). This is that half.
--
-- ############################################################################
-- # THE LAG IS THE VIEW. DO NOT "OPTIMISE" THE FRESHNESS GUARD AWAY.         #
-- ############################################################################
-- A change applied on day T is graded on [T+1, T+7] and MAY BE READ NO EARLIER THAN T+14.
-- SB is slower (14-day attribution tail): graded on [T+1, T+14], read no earlier than T+21.
-- Encoded once, as the load-bearing predicate:
--     WHERE DATE_ADD(window_end, INTERVAL 7 DAY) <= CURRENT_DATE('America/Los_Angeles')
-- A change that is not old enough DOES NOT APPEAR IN THIS VIEW AT ALL — there is deliberately no
-- TOO_EARLY row for anyone to misread as a signal.
--
-- WHY: a trailing 7-day window ending yesterday reads ~89.5% of its FINAL sales, and the shortfall
-- is worst on the NEWEST day — which is exactly the day the change affected most. Measured on
-- V_ADS_SETTLE_CURVE (sales pct_of_final, median): age 1 = 67.0%, age 2 = 87.4%, age 4 = 93.0%,
-- age 7 = 95.0%, age 11 = 100%. Spend closes at age 2 (99.9%); the whole distortion lives in sales,
-- therefore in ROAS. Grading early does not add noise, it adds BIAS in one direction: it
-- systematically UNDER-reads your own change, so you reverse winners — and then, once the sales
-- accrue, you reverse the reversal. That is churn manufactured by the instrument, and the two
-- errors do not cost the same (a false cut kills a winner forever; a false restore delays a day).
-- Same rule, same reason as V_PARK_REVERDICT (SEASON_CONTEXT_LEDGER.md §7) and SETTLE_HOLD (§7.6).
--
-- Residual, documented and ACCEPTED: at the read gate the newest window day is age 7 (~95% of final
-- sales), not age 11 (100%); for SB the last window day is read at age 7 of a 14-day tail, so SB GP
-- is understated. The error direction is SAFE — an understated window can only manufacture a false
-- REVERSED, whose remedy is "restore the pre-change value", never a cut — and it self-heals because
-- the view re-reads today's restatement on every run.
--
-- MONEY METRIC: GP-ROAS on FACT_AMAZON_ADS.GROSS_PROFIT, the stored column,
--   gp = a.GROSS_PROFIT
-- exactly as V_OOB_KEYWORD / V_PARK_REVERDICT now read it, so a revive bar and a scorecard verdict
-- are stated in the same currency. (V_PPC_ACTION_OUTCOMES deliberately uses a different margin —
-- the coach's listing_price - TOTAL_COST_PER_UNIT — because it grades the coach THRESHOLD. This
-- view grades the MONEY.)
--
-- ############################################################################
-- # v27.62 — THE GP RULE: READ FACT_AMAZON_ADS.GROSS_PROFIT. NEVER RECOMPUTE. #
-- ############################################################################
-- (Ori 2026-08-13, found by checking the panel against Amazon.) Until v27.62 the line above read
--     gp = Ads_sales - COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) * Ads_units
--   LEFT JOIN T_PRICE_COST_TIER pct ON Ads_units > 0
--     AND pct.unit_price = ROUND(SAFE_DIVIDE(Ads_sales, Ads_units), 2)
-- and that formula and its join ARE NOW GONE. The join looked the cost tier up by an "implied unit
-- price" of Ads_sales / Ads_units — which is NOT the product's price: Ads_sales carries HALO sales
-- of OTHER products (~79% purchased-vs-advertised divergence in this account) while Ads_units does
-- not correspond to them. PROVEN on VIDEO- BALL / 2026-08-12: implied $24.39 for a $13.99 product
-- matched a ~$21.50 tier, overrode the real TOTAL_COST_PER_UNIT of $9.77, and collapsed
-- GP $229.16 -> $37.17 — a GP-ROAS of 3.69x read as 0.60x, on a campaign Amazon's own console
-- reports at $331.08 sales / $64.05 spend that day. Arithmetic: 317.09 - 9.77 x 13 = 229.16 =
-- FACT.GROSS_PROFIT exactly. WHY IT EXISTED: FACT began charging tier COGS at LOAD time on
-- 2026-08-01; these views predate that and were never updated, so they re-derived a number that
-- was already correct — and got it wrong. WHY IT HID: account-wide over 30 days the two agree to
-- ~3% (0.845 vs 0.817). The damage is PER ROW, on exactly the rows a decision is made about.
-- NOTE FOR THIS VIEW SPECIFICALLY: verdicts recorded before v27.62 were graded in the old,
-- corrupted currency. The view is a pure function of today's FACT, so every historical verdict
-- REGRADES on the next read — do not reconcile a screenshot taken before 2026-08-13 against it.
-- Same fix, same day: V_LOW_STOCK_ADS (v27.61) and the other seven engine views.
--
-- PRIOR RECORD: the entity's OWN settled [T-28, T-1]. The freshness guard already puts T-1 at
-- >= 15 days old, so the prior needs no separate settle guard.
--   /!\ KNOWN BIAS, stated plainly: the engines select entities on their two worst days, so a
--   bounce toward the mean is the NULL, not the treatment effect. Grading against the entity's own
--   prior therefore FLATTERS every change, NEUTRAL most of all. The 28-day prior is much wider than
--   the selection window, which damps but does not remove it. The honest instrument is a matched
--   untouched control cohort — a separate build. Read CONFIRMED/REVERSED as directional; never read
--   NEUTRAL as proof a change helped.
--
-- VERDICTS (precedence INSUFFICIENT -> CONFIRMED -> NEUTRAL -> REVERSED):
--   CONFIRMED     window GP-ROAS >= 1.0                                -> hold; ONE more step in
--                                                                         the same direction allowed
--   NEUTRAL       >= its own prior, but < 1.0 absolute                 -> hold, NO further step
--   REVERSED      < 1.0 AND below its own prior record                 -> restore the PRE-CHANGE
--                                                                         value, NEVER lower
--   INSUFFICIENT  < 10 settled clicks in the window                    -> re-graded on [T+1, T+21]
--                                                                         once T+28 <= today
-- REVERSED IS NOT A DISASTER VERDICT: measured, REVERSED rows land near 0.993 GP-ROAS (breakeven).
-- The remedy is "put it back" (remedy_value = the logged old_bid / old_budget), never "punish it
-- further" — this view never emits a value below the pre-change one.
-- NO COMPARABLE PRIOR (< 10 settled clicks in [T-28,T-1], e.g. a newly added target): the relative
-- test is undefined, so the row is judged ABSOLUTE ONLY and prior_available = FALSE says so.
--
-- HOW EACH ACTION TYPE IS SCORED:
--   BID_DOWN / BID_UP / PAUSE_TARGET  target grain (campaign_id + keyword_id; falls back to
--                                     LOWER(targeting) when that keyword_id has never appeared in
--                                     FACT) — GP-ROAS ladder.
--   BUDGET_UP / BUDGET_DOWN           CAMPAIGN grain (campaign_id only) — a budget change moves the
--                                     whole campaign, so the campaign's own settled GP-ROAS is the
--                                     only honest measure. budget_utilization = window spend/day
--                                     over new_budget shows whether the budget ever bound.
--   NEGATE                            term grain — scored on THE TERM DISAPPEARING, NOT ON ROAS.
--                                     CONFIRMED = window spend/day fell to <= 15% of the prior
--                                     daily rate, OR the residual is under 3 clicks (negatives
--                                     propagate with a lag and the change is marked uploaded
--                                     mid-day, so a click or two on T+1 is expected — without this
--                                     floor a $0.58 / 1-click tail reads 19% and false-alarms).
--                                     REVERSED = still spending (the negative did NOT land: wrong
--                                     match type/level, or a failed upload) -> remedy is RE-APPLY,
--                                     not restore a bid.
--                                     INSUFFICIENT = prior term clicks < 10, disappearance proves
--                                     nothing. prior_gp_roas rides along so the PREMISE ("was it
--                                     losing money?") is auditable next to the EXECUTION.
--   UNNEGATE / ADD_TARGET             absolute-only ladder (prior ~0 by construction).
--   OTHER                             campaign grain, listed for completeness, not decision-grade.
-- DELIBERATE SCOPE LIMIT: PROMOTE_* is scored inside its logged campaign, not across all campaigns
-- the way V_PPC_ACTION_OUTCOMES does. There are zero PROMOTE_* rows in the log today; revisit when
-- promotes resume.
--
-- CONTAMINATION FLAGS (audit, never verdict): superseded_in_window / next_change_date mark a LATER
-- change on the SAME entity inside the graded window — the row is FLAGGED, NOT DROPPED (dropping
-- would silently hide the most-worked-on entities). Any threshold-tuning pass must exclude them.
--
-- SPREAD RE-MEASURED AT DEPLOY (2026-08-12, n=119 PRIMARY rows with a settled next-14d window —
-- small, so read it as corroboration, not as a re-estimate). The MECHANISM reproduces and the
-- ordering is monotone across quartiles of window GP-ROAS (next-14d 0.919 / 0.886 / 1.099 / 2.012).
-- The FAIL side lands almost exactly where the original put it: bucket < 0.8 has mean window
-- GP-ROAS 0.352 (original 0.342) and next-14d 0.945 (original 0.993) — "REVERSED is breakeven, not
-- disaster" holds. The STRONG side runs HOTTER here (>= 1.2 -> window 2.293, next-14d 2.030 vs the
-- original 2.129 -> 1.591), so the spread comes out LARGER, not smaller: +1.085 at (0.8 / 1.2),
-- +0.772 at the view's own 1.0 bar unweighted, +0.370 spend-weighted. The exact +0.598 is NOT
-- reproducible without the original's bucket definition and population; the direction, the
-- monotonicity and the breakeven landing are.
--
-- SELF-VALIDATION: next14_gp_roas over [window_end+1, window_end+14] (populated only when that
-- window is itself settled) exists so the +0.598 spread can be RE-MEASURED from the view rather
-- than taken on faith. Restrict such a check to window_used = 'PRIMARY' — the EXTENDED window
-- overlaps next14 and would be circular.
--
-- SOURCE: V_PPC_CHANGE_LOG_LANDED (since 2026-10-01), never raw FACT_PPC_CHANGE_LOG. LANDED is
-- V_PPC_CHANGE_LOG_APPLIED — which drops the FAILED_UPLOAD rows of the 2026-08-06 silent upload
-- failure, the superseded and the still-pending books, because grading a change that never landed
-- in Amazon is grading noise — PLUS the changes SP_RECORD_OBSERVED_CHANGES reads off the DIM SCD2
-- trail from 2026-08-20 (source = 'OBSERVED'): the hand changes made in the console, which the log
-- never saw. A logged change whose landing was also observed is ONE row (the logged one, marked
-- landed_evidence = 'LOGGED_AND_SEEN_ON_AMAZON'); see V_PPC_CHANGE_LOG_LANDED for the pairing.
-- Observed rows are graded by exactly the logic above: same windows, same read gate, same verdict
-- ladder, and they count as later changes in the contamination flags of the rows around them.
-- Split them with `source` (COACH / MANUAL / OBSERVED / the books' BRAIN:*, CATALOG:*, PACING:*).
-- The observed rows carry no coach snapshot (target_*_8w NULL, coach_mode NULL). Their action
-- names are the log's (INCREASE_BID / REDUCE_BID / BUDGET_CHANGE / KEYWORD_PAUSE / ...), so
-- KEYWORD_PAUSE, KEYWORD_ENABLE and CAMPAIGN_PAUSE land in OTHER (campaign grain, not
-- decision-grade) exactly as the logged pauses always have.
-- DOWNSTREAM: V_DAILY_BRIEF and V_ENGINE_HEALTH read this view WITHOUT the observed rows
-- (source != 'OBSERVED' in each) so the morning brief and the health board read what they read
-- before the ledger existed. V_THRESHOLD_TUNER reads them since Ori's ruling of 2026-10-02 and
-- labels each cell with how many were his hand changes. Cube ChangeScorecard
-- (cube/schema/ChangeScorecard.js, a live read with a 15-minute cache), which feeds the Weekly
-- Run panel "How did last week's changes do?" (dashboard-react/src/pages/ChangeScorecardPanel.tsx),
-- reads every row since 2026-10-03 under the same ruling: the panel labels hand changes OBSERVED,
-- and a REVERSED one shows its value to put back like any other row. Letting graded hand changes
-- into the brief or the board is Ori's decision. V_MANUAL_DIVERGENCE reads source = 'MANUAL'
-- only. Checks: OBSERVED_CHANGES_acceptance.sql C09 (the three views),
-- check_change_scorecard_cube.py (the cube drops no row).
--
-- DETERMINISM: plain SUMs over fixed date windows; no ANY_VALUE pairs (v27.46 lesson — never divide
-- two ANY_VALUEs out of one GROUP BY); the dedup QUALIFY is fully tie-broken on (applied_at,
-- change_id). Two pulls within a day are byte-identical.
-- TIMEZONE: applied_at is UTC; every window is computed on DATE(applied_at, 'America/Los_Angeles')
-- so it aligns with FACT_AMAZON_ADS.date (FACT_PPC_CHANGE_LOG doctrine).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CHANGE_SCORECARD` AS
WITH
k AS (
  SELECT 10       AS min_clicks,          -- thin-evidence bar, both windows
         1.0      AS bar_roas,            -- absolute GP-ROAS bar
         7        AS settle_lag_days,     -- read gate = window_end + this
         21       AS ext_days,            -- extended window end = T + this
         28       AS prior_days,          -- prior record = [T-28, T-1]
         14       AS next_days,           -- self-validation fortnight
         180      AS chg_lookback_days,   -- changes considered
         230      AS fact_lookback_days,  -- static FACT bound (partition pruning)
         0.15     AS negate_residual_max, -- "the term disappeared" threshold (daily-rate ratio)
         3        AS negate_min_clk       -- ...or fewer than this many residual clicks (propagation tail)
),
d AS (SELECT CURRENT_DATE('America/Los_Angeles') AS today),

-- ── 1. the change log, deduped to one row per logical change per LA day ──────────────────────
-- (older rows predate the deterministic change_id, so one decision could be logged N times)
chg_raw AS (
  SELECT
    c.change_id, c.batch_id, c.applied_at,
    DATE(c.applied_at, 'America/Los_Angeles')       AS change_date,
    c.action,
    NULLIF(TRIM(c.search_term), '')                 AS search_term,
    NULLIF(TRIM(c.targeting), '')                   AS targeting,
    NULLIF(CAST(c.keyword_id AS STRING), '')        AS keyword_id,
    c.match_type,
    CAST(c.campaign_id AS STRING)                   AS campaign_id,
    c.campaign_name, c.campaign_type,
    CAST(c.ad_group_id AS STRING)                   AS ad_group_id,
    c.product,
    c.old_bid, c.new_bid, c.old_budget, c.new_budget,
    c.target_spend_8w, c.target_orders_8w, c.target_net_roas_8w,
    c.coach_mode, c.source,
    c.landed_evidence, c.paired_change_id
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED` c
  WHERE DATE(c.applied_at, 'America/Los_Angeles')
        >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 180 DAY)
    AND c.campaign_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CAST(c.campaign_id AS STRING), c.action,
      COALESCE(NULLIF(CAST(c.keyword_id AS STRING), ''), NULLIF(TRIM(c.targeting), ''),
               NULLIF(TRIM(c.search_term), ''), ''),
      IFNULL(CAST(c.new_bid AS STRING), ''), IFNULL(CAST(c.new_budget AS STRING), ''),
      DATE(c.applied_at, 'America/Los_Angeles')
    ORDER BY c.applied_at, c.change_id
  ) = 1
),

-- ── 2. action grouping, scope grain, channel, and every window boundary ─────────────────────
chg_typed AS (
  SELECT
    r.*,
    CASE
      WHEN r.action = 'REDUCE_BID'                                        THEN 'BID_DOWN'
      WHEN r.action IN ('INCREASE_BID', 'BOOST', 'SCALE_UP')              THEN 'BID_UP'
      WHEN r.action = 'STOP_TARGET'                                       THEN 'PAUSE_TARGET'
      WHEN r.action LIKE '%BUDGET%' THEN
        CASE WHEN r.new_budget IS NOT NULL AND r.old_budget IS NOT NULL
                  AND r.new_budget < r.old_budget                         THEN 'BUDGET_DOWN'
             WHEN r.action LIKE '%DECREASE%' OR r.action LIKE '%CONTAIN%' THEN 'BUDGET_DOWN'
             ELSE 'BUDGET_UP' END
      WHEN r.action LIKE 'NEGATE%' OR r.action IN ('STOP_TERM', 'STOP')   THEN 'NEGATE'
      WHEN r.action IN ('REMOVE_NEGATIVE', 'REMOVE_CONFLICTING_NEGATIVE') THEN 'UNNEGATE'
      WHEN r.action LIKE 'PROMOTE%' OR r.action LIKE 'ADD_%'
           OR r.action IN ('START_TERM', 'START')                         THEN 'ADD_TARGET'
      ELSE 'OTHER'
    END AS action_group,
    -- channel: the campaign dimension is authoritative; the log's own campaign_type is the fallback
    CASE
      WHEN UPPER(COALESCE(dc.campaign_type, '')) = 'SB'            THEN 'SB'
      WHEN UPPER(COALESCE(dc.campaign_type, '')) = 'SP'            THEN 'SP'
      WHEN UPPER(COALESCE(r.campaign_type, '')) LIKE '%BRAND%'     THEN 'SB'
      WHEN UPPER(COALESCE(r.campaign_type, '')) = 'SB'             THEN 'SB'
      ELSE 'SP'
    END AS channel,
    dc.campaign_name AS campaign_name_current,
    fam.parent_name  AS family
  FROM chg_raw r
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = r.campaign_id
  LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` fam
    ON CAST(fam.campaign_id AS STRING) = r.campaign_id
),

chg_win AS (
  SELECT
    t.*,
    CASE WHEN t.action_group IN ('BID_DOWN', 'BID_UP', 'PAUSE_TARGET', 'ADD_TARGET') THEN 'TARGET'
         WHEN t.action_group IN ('NEGATE', 'UNNEGATE')                               THEN 'TERM'
         ELSE 'CAMPAIGN' END AS scope_grain,
    LOWER(TRIM(CASE
      WHEN t.action_group IN ('NEGATE', 'UNNEGATE') THEN COALESCE(t.search_term, t.targeting)
      ELSE COALESCE(t.targeting, t.search_term)
    END)) AS entity_lc,
    IF(t.channel = 'SB', 14, 7) AS window_days
  FROM chg_typed t
),

chg AS (
  SELECT
    w.*,
    DATE_ADD(w.change_date, INTERVAL 1 DAY)                        AS window_start,
    DATE_ADD(w.change_date, INTERVAL w.window_days DAY)            AS window_end,
    DATE_SUB(w.change_date, INTERVAL x.prior_days DAY)             AS prior_start,
    DATE_SUB(w.change_date, INTERVAL 1 DAY)                        AS prior_end,
    DATE_ADD(w.change_date, INTERVAL x.ext_days DAY)               AS ext_end,
    DATE_ADD(w.change_date, INTERVAL w.window_days + 1 DAY)        AS next14_start,
    DATE_ADD(w.change_date, INTERVAL w.window_days + x.next_days DAY) AS next14_end,
    -- ###### THE FRESHNESS GUARD ###### read gate = window_end + 7 (SP T+14 / SB T+21)
    DATE_ADD(DATE_ADD(w.change_date, INTERVAL w.window_days DAY),
             INTERVAL x.settle_lag_days DAY)                       AS read_gate_date,
    DATE_ADD(DATE_ADD(w.change_date, INTERVAL x.ext_days DAY),
             INTERVAL x.settle_lag_days DAY)                       AS ext_read_gate_date,
    DATE_ADD(DATE_ADD(w.change_date, INTERVAL w.window_days + x.next_days DAY),
             INTERVAL x.settle_lag_days DAY)                       AS next14_read_gate_date
  FROM chg_win w CROSS JOIN k x
),

-- ── 3. graded population = ONLY changes whose window has settled ─────────────────────────────
graded AS (
  SELECT c.* FROM chg c CROSS JOIN d
  WHERE c.read_gate_date <= d.today          -- <<< the load-bearing predicate
),

-- ── 4. FACT, restricted to the campaigns that were actually touched. GP = the STORED
--       FACT_AMAZON_ADS.GROSS_PROFIT column — see THE GP RULE in the header ──────────────────────
fa AS (
  SELECT
    CAST(a.campaign_id AS STRING)     AS cid,
    NULLIF(CAST(a.keyword_id AS STRING), '') AS kid,
    LOWER(TRIM(a.targeting))          AS tgt_lc,
    LOWER(TRIM(a.search_term))        AS st_lc,
    a.date,
    a.Ads_clicks AS clk, a.Ads_cost AS sp, a.Ads_orders AS ord,
    a.Ads_units AS un,  a.Ads_sales AS sales,
    a.GROSS_PROFIT AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN (SELECT DISTINCT campaign_id FROM graded) g
    ON CAST(a.campaign_id AS STRING) = g.campaign_id
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 230 DAY)
),
kid_index AS (SELECT DISTINCT cid, kid FROM fa WHERE kid IS NOT NULL),

fa_kid  AS (SELECT cid, kid,    date, SUM(clk) clk, SUM(sp) sp, SUM(ord) ord, SUM(un) un, SUM(sales) sales, SUM(gp) gp FROM fa WHERE kid IS NOT NULL GROUP BY 1,2,3),
fa_tgt  AS (SELECT cid, tgt_lc, date, SUM(clk) clk, SUM(sp) sp, SUM(ord) ord, SUM(un) un, SUM(sales) sales, SUM(gp) gp FROM fa GROUP BY 1,2,3),
fa_term AS (SELECT cid, st_lc,  date, SUM(clk) clk, SUM(sp) sp, SUM(ord) ord, SUM(un) un, SUM(sales) sales, SUM(gp) gp FROM fa GROUP BY 1,2,3),
fa_camp AS (SELECT cid,         date, SUM(clk) clk, SUM(sp) sp, SUM(ord) ord, SUM(un) un, SUM(sales) sales, SUM(gp) gp FROM fa GROUP BY 1,2),

-- how each target-scoped change resolves against FACT: exact Amazon keyword_id where that id has
-- ever been seen, else the campaign+targeting text (V_PARK_REVERDICT's grain)
resolved AS (
  SELECT g.change_id,
         IF(g.scope_grain = 'TARGET' AND g.keyword_id IS NOT NULL AND ki.kid IS NOT NULL,
            'KID', IF(g.scope_grain = 'TARGET', 'TEXT', g.scope_grain)) AS match_mode
  FROM graded g
  LEFT JOIN kid_index ki ON ki.cid = g.campaign_id AND ki.kid = g.keyword_id
),

-- ── 5. one daily row per (change, date) at the action's own scope ────────────────────────────
matched AS (
  SELECT g.change_id, f.date, f.clk, f.sp, f.ord, f.un, f.sales, f.gp
  FROM graded g
  JOIN resolved r USING (change_id)
  JOIN fa_kid f ON f.cid = g.campaign_id AND f.kid = g.keyword_id
               AND f.date BETWEEN g.prior_start AND g.next14_end
  WHERE r.match_mode = 'KID'
  UNION ALL
  SELECT g.change_id, f.date, f.clk, f.sp, f.ord, f.un, f.sales, f.gp
  FROM graded g
  JOIN resolved r USING (change_id)
  JOIN fa_tgt f ON f.cid = g.campaign_id AND f.tgt_lc = g.entity_lc
               AND f.date BETWEEN g.prior_start AND g.next14_end
  WHERE r.match_mode = 'TEXT' AND g.entity_lc IS NOT NULL
  UNION ALL
  SELECT g.change_id, f.date, f.clk, f.sp, f.ord, f.un, f.sales, f.gp
  FROM graded g
  JOIN fa_term f ON f.cid = g.campaign_id AND f.st_lc = g.entity_lc
                AND f.date BETWEEN g.prior_start AND g.next14_end
  WHERE g.scope_grain = 'TERM' AND g.entity_lc IS NOT NULL
  UNION ALL
  SELECT g.change_id, f.date, f.clk, f.sp, f.ord, f.un, f.sales, f.gp
  FROM graded g
  JOIN fa_camp f ON f.cid = g.campaign_id
                AND f.date BETWEEN g.prior_start AND g.next14_end
  WHERE g.scope_grain = 'CAMPAIGN'
),

agg AS (
  SELECT
    g.change_id,
    -- prior [T-28, T-1]
    SUM(IF(m.date BETWEEN g.prior_start AND g.prior_end, m.clk, 0))   AS prior_clicks,
    SUM(IF(m.date BETWEEN g.prior_start AND g.prior_end, m.sp,  0))   AS prior_spend,
    SUM(IF(m.date BETWEEN g.prior_start AND g.prior_end, m.ord, 0))   AS prior_orders,
    SUM(IF(m.date BETWEEN g.prior_start AND g.prior_end, m.un,  0))   AS prior_units,
    SUM(IF(m.date BETWEEN g.prior_start AND g.prior_end, m.sales,0))  AS prior_sales,
    SUM(IF(m.date BETWEEN g.prior_start AND g.prior_end, m.gp,  0))   AS prior_gp,
    -- primary window [T+1, T+7]  (SB [T+1, T+14])
    SUM(IF(m.date BETWEEN g.window_start AND g.window_end, m.clk, 0)) AS win_clicks,
    SUM(IF(m.date BETWEEN g.window_start AND g.window_end, m.sp,  0)) AS win_spend,
    SUM(IF(m.date BETWEEN g.window_start AND g.window_end, m.ord, 0)) AS win_orders,
    SUM(IF(m.date BETWEEN g.window_start AND g.window_end, m.un,  0)) AS win_units,
    SUM(IF(m.date BETWEEN g.window_start AND g.window_end, m.sales,0))AS win_sales,
    SUM(IF(m.date BETWEEN g.window_start AND g.window_end, m.gp,  0)) AS win_gp,
    -- extended window [T+1, T+21] — only consulted when the primary window is thin
    SUM(IF(m.date BETWEEN g.window_start AND g.ext_end, m.clk, 0))    AS ext_clicks,
    SUM(IF(m.date BETWEEN g.window_start AND g.ext_end, m.sp,  0))    AS ext_spend,
    SUM(IF(m.date BETWEEN g.window_start AND g.ext_end, m.ord, 0))    AS ext_orders,
    SUM(IF(m.date BETWEEN g.window_start AND g.ext_end, m.un,  0))    AS ext_units,
    SUM(IF(m.date BETWEEN g.window_start AND g.ext_end, m.sales,0))   AS ext_sales,
    SUM(IF(m.date BETWEEN g.window_start AND g.ext_end, m.gp,  0))    AS ext_gp,
    -- the following fortnight — self-validation only, never part of a verdict
    SUM(IF(m.date BETWEEN g.next14_start AND g.next14_end, m.clk, 0)) AS next14_clicks,
    SUM(IF(m.date BETWEEN g.next14_start AND g.next14_end, m.sp,  0)) AS next14_spend,
    SUM(IF(m.date BETWEEN g.next14_start AND g.next14_end, m.ord, 0)) AS next14_orders,
    SUM(IF(m.date BETWEEN g.next14_start AND g.next14_end, m.gp,  0)) AS next14_gp
  FROM graded g
  JOIN matched m USING (change_id)
  GROUP BY 1
),

-- ── 6. contamination: a LATER change on the SAME entity inside the graded window ─────────────
-- v2 FIX (verifier, 2026-08-11): the "b" side must come from the FULL change set (chg), not from
-- `graded`. Built off `graded` it could only see later changes that had THEMSELVES passed the read
-- gate, so a fresh change landing inside an older change's window went uncounted: 137 rows are
-- genuinely contaminated, only 88 were flagged, 49 silently unflagged (zero false flags). Verdicts
-- are unaffected either way — this flag exists so nobody tunes a threshold off a polluted row,
-- which is exactly the moment the undercount would bite.
scope_keyed_all AS (
  SELECT change_id, change_date,
         CONCAT(scope_grain, '|', campaign_id, '|',
                CASE scope_grain
                  WHEN 'CAMPAIGN' THEN ''
                  ELSE COALESCE(entity_lc, COALESCE(keyword_id, '')) END) AS scope_key,
         window_end
  FROM chg                                     -- <<< full set, gated or not
),
scope_keyed AS (
  SELECT s.* FROM scope_keyed_all s
  JOIN graded g USING (change_id)              -- the "a" side stays the graded population
),
supersede AS (
  SELECT a.change_id,
         COUNTIF(b.change_date > a.change_date AND b.change_date <= a.window_end) AS n_later_changes,
         MIN(IF(b.change_date > a.change_date AND b.change_date <= a.window_end,
                b.change_date, NULL))                                            AS next_change_date
  FROM scope_keyed a
  JOIN scope_keyed_all b ON b.scope_key = a.scope_key AND b.change_id != a.change_id
  GROUP BY 1
),

-- ── 7. ratios, window selection, verdict ─────────────────────────────────────────────────────
calc AS (
  SELECT
    g.*,
    x.min_clicks, x.bar_roas, x.negate_residual_max, x.negate_min_clk,
    COALESCE(a.prior_clicks, 0)  AS prior_clicks,
    ROUND(COALESCE(a.prior_spend, 0), 2)  AS prior_spend,
    COALESCE(a.prior_orders, 0)  AS prior_orders,
    COALESCE(a.prior_units, 0)   AS prior_units,
    ROUND(COALESCE(a.prior_sales, 0), 2)  AS prior_sales,
    ROUND(COALESCE(a.prior_gp, 0), 2)     AS prior_gp,
    COALESCE(a.win_clicks, 0)    AS p_clicks,
    ROUND(COALESCE(a.win_spend, 0), 2)    AS p_spend,
    COALESCE(a.win_orders, 0)    AS p_orders,
    COALESCE(a.win_units, 0)     AS p_units,
    ROUND(COALESCE(a.win_sales, 0), 2)    AS p_sales,
    ROUND(COALESCE(a.win_gp, 0), 2)       AS p_gp,
    COALESCE(a.ext_clicks, 0)    AS e_clicks,
    ROUND(COALESCE(a.ext_spend, 0), 2)    AS e_spend,
    COALESCE(a.ext_orders, 0)    AS e_orders,
    COALESCE(a.ext_units, 0)     AS e_units,
    ROUND(COALESCE(a.ext_sales, 0), 2)    AS e_sales,
    ROUND(COALESCE(a.ext_gp, 0), 2)       AS e_gp,
    COALESCE(a.next14_clicks, 0) AS next14_clicks,
    ROUND(COALESCE(a.next14_spend, 0), 2) AS next14_spend,
    COALESCE(a.next14_orders, 0) AS next14_orders,
    ROUND(COALESCE(a.next14_gp, 0), 2)    AS next14_gp,
    COALESCE(s.n_later_changes, 0) AS n_later_changes,
    s.next_change_date,
    -- extension fires only when the primary window is thin AND the extension itself has settled
    (COALESCE(a.win_clicks, 0) < x.min_clicks
     AND g.ext_read_gate_date <= dd.today
     AND COALESCE(a.ext_clicks, 0) >= x.min_clicks) AS use_ext,
    (g.next14_read_gate_date <= dd.today)           AS next14_readable
  FROM graded g
  CROSS JOIN k x CROSS JOIN d dd
  LEFT JOIN agg a       USING (change_id)
  LEFT JOIN supersede s USING (change_id)
),

pick AS (
  SELECT
    c.*,
    IF(c.use_ext, 'EXTENDED', 'PRIMARY')                                   AS window_used,
    IF(c.use_ext, c.ext_end, c.window_end)                                 AS graded_through,
    IF(c.use_ext, c.e_clicks, c.p_clicks)                                  AS win_clicks,
    IF(c.use_ext, c.e_spend,  c.p_spend)                                   AS win_spend,
    IF(c.use_ext, c.e_orders, c.p_orders)                                  AS win_orders,
    IF(c.use_ext, c.e_units,  c.p_units)                                   AS win_units,
    IF(c.use_ext, c.e_sales,  c.p_sales)                                   AS win_sales,
    IF(c.use_ext, c.e_gp,     c.p_gp)                                      AS win_gp,
    IF(c.use_ext, DATE_DIFF(c.ext_end, c.window_start, DAY) + 1,
                  DATE_DIFF(c.window_end, c.window_start, DAY) + 1)        AS win_days,
    (c.prior_clicks >= c.min_clicks)                                       AS prior_available
  FROM calc c
),

fin AS (
  SELECT
    p.*,
    ROUND(SAFE_DIVIDE(p.win_gp,    NULLIF(p.win_spend, 0)),   3) AS win_gp_roas,
    ROUND(SAFE_DIVIDE(p.prior_gp,  NULLIF(p.prior_spend, 0)), 3) AS prior_gp_roas,
    ROUND(SAFE_DIVIDE(p.next14_gp, NULLIF(p.next14_spend, 0)),3) AS next14_gp_roas_raw,
    ROUND(SAFE_DIVIDE(p.win_spend,   NULLIF(p.win_clicks, 0)),3) AS win_cpc,
    ROUND(SAFE_DIVIDE(p.prior_spend, NULLIF(p.prior_clicks, 0)),3) AS prior_cpc,
    ROUND(SAFE_DIVIDE(p.win_spend,   NULLIF(p.win_days, 0)),  2) AS win_spend_per_day,
    ROUND(SAFE_DIVIDE(p.prior_spend, 28.0),                   2) AS prior_spend_per_day,
    ROUND(SAFE_DIVIDE(p.win_orders,  NULLIF(p.win_days, 0)),  3) AS win_orders_per_day,
    ROUND(SAFE_DIVIDE(p.prior_orders, 28.0),                  3) AS prior_orders_per_day,
    ROUND(p.win_gp - p.win_spend, 2)                             AS win_net_profit,
    -- negate execution test: window daily spend rate vs the prior daily spend rate
    ROUND(SAFE_DIVIDE(SAFE_DIVIDE(p.win_spend, NULLIF(p.win_days, 0)),
                      NULLIF(SAFE_DIVIDE(p.prior_spend, 28.0), 0)), 3) AS negate_residual_ratio
  FROM pick p
),

-- the negate execution test, resolved once so verdict / reason / remedy can never disagree
fin2 AS (
  SELECT f.*,
         (f.win_spend = 0
          OR f.win_clicks < f.negate_min_clk
          OR COALESCE(f.negate_residual_ratio, 0) <= f.negate_residual_max) AS negate_landed
  FROM fin f
)

SELECT
  -- ── identity ────────────────────────────────────────────────────────────────────────────────
  f.change_id, f.batch_id, f.applied_at,
  f.change_date, f.source, f.coach_mode, f.action, f.action_group, f.scope_grain, f.channel,
  -- ── entity ──────────────────────────────────────────────────────────────────────────────────
  f.campaign_id,
  COALESCE(f.campaign_name_current, f.campaign_name) AS campaign_name,
  f.family, f.ad_group_id, f.keyword_id, f.targeting, f.search_term, f.match_type, f.product,
  -- ── what changed ────────────────────────────────────────────────────────────────────────────
  CASE WHEN f.action_group IN ('BUDGET_UP', 'BUDGET_DOWN') THEN 'BUDGET'
       WHEN f.old_bid IS NOT NULL OR f.new_bid IS NOT NULL THEN 'BID'
       ELSE 'NA' END AS value_kind,
  COALESCE(f.old_bid, f.old_budget) AS old_value,
  COALESCE(f.new_bid, f.new_budget) AS new_value,
  ROUND(SAFE_DIVIDE(COALESCE(f.new_bid, f.new_budget) - COALESCE(f.old_bid, f.old_budget),
                    NULLIF(COALESCE(f.old_bid, f.old_budget), 0)) * 100, 1) AS pct_change,
  -- ── windows ─────────────────────────────────────────────────────────────────────────────────
  f.window_start, f.window_end, f.read_gate_date, f.window_used, f.graded_through, f.win_days,
  f.prior_start, f.prior_end,
  -- ── graded window ───────────────────────────────────────────────────────────────────────────
  f.win_clicks, f.win_spend, f.win_orders, f.win_units, f.win_sales, f.win_gp,
  f.win_gp_roas, f.win_cpc, f.win_spend_per_day, f.win_orders_per_day, f.win_net_profit,
  -- ── prior record ────────────────────────────────────────────────────────────────────────────
  f.prior_clicks, f.prior_spend, f.prior_orders, f.prior_units, f.prior_sales, f.prior_gp,
  f.prior_gp_roas, f.prior_cpc, f.prior_spend_per_day, f.prior_orders_per_day, f.prior_available,
  -- ── deltas ──────────────────────────────────────────────────────────────────────────────────
  ROUND(COALESCE(f.win_gp_roas, 0) - COALESCE(f.prior_gp_roas, 0), 3) AS gp_roas_delta,
  ROUND(COALESCE(f.win_spend_per_day, 0) - COALESCE(f.prior_spend_per_day, 0), 2) AS spend_per_day_delta,
  -- budget rows: did the new budget ever bind?
  IF(f.action_group IN ('BUDGET_UP', 'BUDGET_DOWN'),
     ROUND(SAFE_DIVIDE(f.win_spend_per_day, NULLIF(f.new_budget, 0)), 3), NULL) AS budget_utilization,
  f.negate_residual_ratio,
  -- ── contamination flags (audit, never verdict) ──────────────────────────────────────────────
  (f.n_later_changes > 0) AS superseded_in_window,
  f.n_later_changes, f.next_change_date,
  -- ── decision-time coach snapshot ────────────────────────────────────────────────────────────
  f.target_spend_8w, f.target_orders_8w, f.target_net_roas_8w,

  -- ── VERDICT ─────────────────────────────────────────────────────────────────────────────────
  CASE
    -- negates are scored on the term DISAPPEARING, not on ROAS
    WHEN f.action_group = 'NEGATE' THEN
      CASE
        WHEN f.prior_clicks < f.min_clicks THEN 'INSUFFICIENT'
        WHEN f.negate_landed                THEN 'CONFIRMED'
        ELSE 'REVERSED'
      END
    -- everything else: the GP-ROAS ladder
    WHEN f.win_clicks < f.min_clicks THEN 'INSUFFICIENT'
    WHEN COALESCE(f.win_gp_roas, 0) >= f.bar_roas THEN 'CONFIRMED'
    WHEN NOT f.prior_available THEN 'REVERSED'   -- absolute-only: no comparable prior to be neutral against
    WHEN COALESCE(f.win_gp_roas, 0) >= COALESCE(f.prior_gp_roas, 0) THEN 'NEUTRAL'
    ELSE 'REVERSED'
  END AS verdict,

  -- ── plain-English reason ────────────────────────────────────────────────────────────────────
  CASE
    WHEN f.action_group = 'NEGATE' AND f.prior_clicks < f.min_clicks THEN
      CONCAT('term had only ', CAST(f.prior_clicks AS STRING), ' clicks in the 28 days before the negate ',
             '(< ', CAST(f.min_clicks AS STRING), ') — its disappearance proves nothing either way')
    WHEN f.action_group = 'NEGATE' AND f.negate_landed THEN
      CONCAT('negative landed: term spend fell from $', FORMAT('%.2f', f.prior_spend_per_day), '/day to $',
             FORMAT('%.2f', COALESCE(f.win_spend_per_day, 0)), '/day over [', CAST(f.window_start AS STRING),
             ', ', CAST(f.graded_through AS STRING), '] — saving ~$',
             FORMAT('%.2f', f.prior_spend_per_day * 7), '/wk; premise: the term ran ',
             FORMAT('%.2f', COALESCE(f.prior_gp_roas, 0)), 'x GP-ROAS on ',
             CAST(f.prior_clicks AS STRING), ' clicks before the cut')
    WHEN f.action_group = 'NEGATE' THEN
      CONCAT('negative did NOT land: term still spending $',
             FORMAT('%.2f', COALESCE(f.win_spend_per_day, 0)), '/day (',
             FORMAT('%.0f', COALESCE(f.negate_residual_ratio, 0) * 100),
             '% of its pre-negate rate) over [', CAST(f.window_start AS STRING), ', ',
             CAST(f.graded_through AS STRING), '] — check the match type and the level it was added at, then re-apply')
    WHEN f.win_clicks < f.min_clicks THEN
      CONCAT('only ', CAST(f.win_clicks AS STRING), ' settled clicks in [', CAST(f.window_start AS STRING),
             ', ', CAST(f.graded_through AS STRING), '] (< ', CAST(f.min_clicks AS STRING),
             ') — no verdict on thin evidence',
             IF(f.window_used = 'EXTENDED', ' even after extending to T+21',
                IF(f.ext_read_gate_date > f.read_gate_date, '; re-graded on [T+1, T+21] once T+28 lands', '')))
    WHEN COALESCE(f.win_gp_roas, 0) >= f.bar_roas THEN
      CONCAT('settled ', CAST(f.win_clicks AS STRING), 'c at ', FORMAT('%.2f', COALESCE(f.win_gp_roas, 0)),
             'x GP-ROAS ($', FORMAT('%.2f', f.win_gp), ' GP on $', FORMAT('%.2f', f.win_spend), ') over [',
             CAST(f.window_start AS STRING), ', ', CAST(f.graded_through AS STRING), '] vs ',
             FORMAT('%.2f', COALESCE(f.prior_gp_roas, 0)), 'x prior — the change paid; hold, one more step in the same direction allowed')
    WHEN NOT f.prior_available THEN
      CONCAT('settled ', CAST(f.win_clicks AS STRING), 'c at ', FORMAT('%.2f', COALESCE(f.win_gp_roas, 0)),
             'x GP-ROAS, below 1.0, and there is no comparable prior record (',
             CAST(f.prior_clicks AS STRING), ' clicks in [T-28, T-1]) — judged absolute only')
    WHEN COALESCE(f.win_gp_roas, 0) >= COALESCE(f.prior_gp_roas, 0) THEN
      CONCAT('settled ', CAST(f.win_clicks AS STRING), 'c at ', FORMAT('%.2f', COALESCE(f.win_gp_roas, 0)),
             'x GP-ROAS — better than its own prior ', FORMAT('%.2f', COALESCE(f.prior_gp_roas, 0)),
             'x but still under 1.0 — hold, no further step')
    ELSE
      CONCAT('settled ', CAST(f.win_clicks AS STRING), 'c at ', FORMAT('%.2f', COALESCE(f.win_gp_roas, 0)),
             'x GP-ROAS — under 1.0 AND below its own prior ', FORMAT('%.2f', COALESCE(f.prior_gp_roas, 0)),
             'x — put it back')
  END AS verdict_reason,

  -- ── remedy (only ever "restore", never lower) ───────────────────────────────────────────────
  CASE
    WHEN f.action_group = 'NEGATE'
      AND f.prior_clicks >= f.min_clicks AND NOT f.negate_landed THEN 'RE_APPLY_NEGATIVE'
    WHEN f.action_group = 'NEGATE' THEN NULL
    WHEN f.win_clicks < f.min_clicks THEN NULL
    WHEN COALESCE(f.win_gp_roas, 0) >= f.bar_roas THEN NULL
    WHEN NOT f.prior_available OR COALESCE(f.win_gp_roas, 0) < COALESCE(f.prior_gp_roas, 0) THEN
      CASE WHEN f.action_group IN ('BUDGET_UP', 'BUDGET_DOWN') THEN 'RESTORE_BUDGET'
           WHEN f.old_bid IS NOT NULL                          THEN 'RESTORE_BID'
           ELSE 'REVIEW' END
    ELSE NULL
  END AS remedy,
  CASE
    WHEN f.action_group = 'NEGATE' THEN NULL
    WHEN f.win_clicks < f.min_clicks THEN NULL
    WHEN COALESCE(f.win_gp_roas, 0) >= f.bar_roas THEN NULL
    WHEN NOT f.prior_available OR COALESCE(f.win_gp_roas, 0) < COALESCE(f.prior_gp_roas, 0) THEN
      IF(f.action_group IN ('BUDGET_UP', 'BUDGET_DOWN'), f.old_budget, f.old_bid)
    ELSE NULL
  END AS remedy_value,

  -- ── self-validation (never part of a verdict; use window_used='PRIMARY' rows only) ──────────
  f.next14_start, f.next14_end, f.next14_readable,
  IF(f.next14_readable, f.next14_clicks, NULL) AS next14_clicks,
  IF(f.next14_readable, f.next14_spend,  NULL) AS next14_spend,
  IF(f.next14_readable, f.next14_orders, NULL) AS next14_orders,
  IF(f.next14_readable, f.next14_gp,     NULL) AS next14_gp,
  IF(f.next14_readable, f.next14_gp_roas_raw, NULL) AS next14_gp_roas,

  -- ── provenance of the action record (2026-10-01; see V_PPC_CHANGE_LOG_LANDED) ───────────────
  f.landed_evidence, f.paired_change_id
FROM fin2 f;
