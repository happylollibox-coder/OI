-- =============================================
-- V_LAUNCH_EXEMPTION — the launch families' licence to lose money, written down as data
-- (v27.56, Ori 2026-08-13: "the launch exemption — but make it as a new criteria in the weekly run
--  page"). One row per ENABLED campaign whose FAMILY is in launch phase.
--
-- WHY (the standing doctrine this enforces): "launch = FIND THE RIGHT BID, never loss-cut; bleed via
-- search-term negate." The coach's launch track already implements that at TARGET grain — but its
-- BUDGET rows carry launch_phase = NULL, so nothing ever stopped the campaign-budget engine from
-- loss-cutting a launch family. On 2026-08-13 that hole was live and expensive: 9 of the 12 coach
-- budget decisions standing on Bunny + LolliBall were cuts (5 CAMPAIGN_STOP, 4 GUARDIAN_BUDGET_
-- DECREASE) against families 3 and 2 months old. This view is the gate's data; the gate itself is
-- one CTE in V_ADS_COACH (`scored_exempt`) that turns those cuts into LAUNCH_EXEMPT_HOLD.
--
-- MEMBERSHIP IS COMPUTED FROM DATA, NOT A LIST. family_first_sale = MIN(date) over T_UNIFIED_DAILY
-- where units > 0 (the same first-sale definition V_PRODUCT_LAUNCH_MODEL and V_LAUNCH_RAMP already
-- use), so a family enters and leaves launch phase on its own record with no code change.
--   Ages 2026-08-13: LolliBall 1.6mo · Bunny 2.7mo · LolliME 13.4 · Bottle 13.7 · Fresh 23.9 · Lollibox 28.5
--
-- THE BOUNDARY = 183 DAYS (6 months) FROM FIRST SALE, and WHY:
--   (a) Today's data CANNOT pick it. The age distribution has a ten-month hole between 2.7 and 13.4
--       months — every cut anywhere in (3mo, 13mo) selects exactly the same two families. So the
--       boundary is a doctrine choice and must be justified as one, not fitted to today's six rows.
--   (b) 183d is the tightest boundary the rest of the system already agrees with:
--       V_PRODUCT_LAUNCH_MODEL requires >= 180 days before a product's own history is allowed to be
--       a pattern — i.e. the warehouse already treats the first ~6 months as "too young to judge".
--   (c) 12 months (the forecast's first-year run-rate guard) was rejected as too generous: a family
--       a year old that still loses money is a business problem, not a launch, and an exemption that
--       long would have covered LolliME and Bottle for most of their lives.
--   (d) It is a BACKSTOP, not the driver. Where Ori has recorded a sanction, its dated stop gate
--       binds first — and today it does for both families (Bunny 2026-10-31 vs the age boundary
--       2026-11-23; LolliBall 2026-11-30 vs 2026-12-26). The exemption ends at the EARLIER of the two.
--
-- AN EXEMPTION IS NOT A BLANK CHEQUE — three bounds, all published as data:
--   1. exempt_until — the earlier of (first sale + 183d) and the sanctioned stop_date. Past it,
--      exempt_active = FALSE and normal coaching resumes with no code change.
--   2. envelope_state — the family's real trailing-7d daily spend vs DE_LAUNCH_INVESTMENT.
--      OVER_ENVELOPE is Ori's budget decision (take money out deliberately, worst settled GP-ROAS
--      first, protected winners last), NOT a licence for the coach to ROAS-cut. Today BOTH families
--      are over: Bunny ~$43.6/day vs $30 sanctioned; LolliBall ~$150/day vs $55.
--   3. The exemption blocks ONE class of decision — campaign-level ROAS-driven money cuts. Every
--      other lever stays live (see `allows`), because bleed control on a launch is a search-term
--      and bid problem, not a budget problem.
--
-- WHAT IS BLOCKED vs WHAT IS ONLY DECLARED (the honesty split — read both columns):
--   blocks_enforced  wired TODAY, in V_ADS_COACH.scored_exempt: CAMPAIGN_STOP,
--                    GUARDIAN_BUDGET_DECREASE, BLITZ_BUDGET_DECREASE, COOLDOWN_BUDGET_REDUCE,
--                    RESTORE_BUDGET_PRE_PEAK, and GUARDIAN_BUDGET_CONTAIN *post-grace only*.
--   blocks_pending   policy Ori named that is NOT wired in this pass: the coach's target-grain
--                    ROAS park (STOP_TARGET — 4 rows / $78 spend_4w on these families today) and
--                    the engine parks in V_OOB_KEYWORD / V_KEYWORD_LIFT. Left alone deliberately:
--                    the OOB seat model's PARK_WAIT is CAPACITY-driven and is the sanctioned launch
--                    mechanism ("winner-as-main is emergent"), so blanket-blocking parks would
--                    break the launch engine it is meant to protect. Ori's call, one WHEN each.
--
-- GRACE IS NOT LOSS-CUTTING — the one containment that survives. V_ADS_COACH's 14-day grace arm
-- contains a BROKEN launch (>$25 spent, ZERO orders, first 14 days) at $10/day. That is a
-- zero-order waste trim, not a ROAS verdict, and it exists FOR launches — so CONTAIN is blocked
-- only for campaigns PAST their grace window (in_grace_window = FALSE). Both arms emit the same
-- action string, which is why the distinction has to be made here, on campaign age.
--
-- STOP_SEASONAL is never blocked: it is calendar-driven (a seasonal campaign past its season),
-- not a profit verdict.
--
-- EVIDENCE IS SETTLED. Every GP-ROAS here is measured over a 28-day window ending settle_days
-- before today — 7 for SP, 14 for SB (SP sales accrue to D+7, SB to D+14). Judging a launch on
-- unsettled clicks condemns keywords whose orders have not landed yet, which is the exact failure
-- V_PARK_REVERDICT was built to undo. GP = FACT_AMAZON_ADS.GROSS_PROFIT (tier COGS already
-- charged) over Ads_cost — the SAME currency the budget engine's own cw.* windows use, so the
-- evidence on the panel and the number that drives the suppressed decision cannot disagree.
--
-- v27.59 — THE ONE DOWNWARD LEVER THE EXEMPTION NOW CARRIES (Ori 2026-08-13). "launch_bid ok
-- between 0.5 and 0.7 trim keyword bid 5% and use launch_bid / improving between 0.7 and 0.9 do not
-- do / profitable ... <0.5 trim keyword bid 10%", judged on the SHORT window. That ladder lives in
-- V_LAUNCH_BID_LADDER, at TARGET grain, and is NOT wired into this view or into the gate — it emits
-- no budget column and no stop/park verb, so every block above stands exactly as it did. THIS VIEW
-- IS DELIBERATELY UNCHANGED IN GRAIN AND DEPENDENCIES: it is read by V_ADS_COACH, and the ladder
-- reads FACT_ADS_COACH_ACTIONS (which V_ADS_COACH materialises), so pulling ladder columns in here
-- would close a stale-data loop around the coach engine and add cost to a view already near
-- BigQuery's planner limit. The ladder reads the exemption, never the other way round. Its
-- existence is declared in `allows` below, which is the published policy the panel prints.
--
-- NOTHING AUTO-APPLIES. Advisory, like every other Weekly Run panel. The only thing this view
-- CHANGES is that a suppressed cut never reaches the bulksheet.
--
-- Consumers: V_ADS_COACH (the gate) · V_COACH_CAMPAIGN_BUDGET (passthrough) · V_LAUNCH_BID_LADDER
-- (population for the bid ladder) · cube/schema/LaunchExemption.js (Weekly Run "Launch exemption"
-- criteria panel, live read).
-- SOP: architecture/LAUNCH_EXEMPTION.md
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_EXEMPTION` AS

WITH k AS (
  SELECT
    183   AS launch_window_days,  -- 6 months from first sale (see header (b)/(c))
    1.00  AS winner_gp_roas,      -- settled GP-ROAS that makes a campaign a protected winner
    10    AS winner_min_clicks,   -- settled clicks before "winner" means anything
    28    AS evidence_days,       -- length of the settled evidence window
    7     AS settle_days_sp,      -- SP sales accrue to D+7
    14    AS settle_days_sb,      -- SB sales accrue to D+14
    14    AS grace_days,          -- V_ADS_COACH's broken-launch grace window
    180   AS fact_scan_days       -- bounds the FACT scan; older campaigns simply read "past grace"
),
anchor AS (SELECT CURRENT_DATE('America/Los_Angeles') AS today),

-- ─── Family age from the family's own first sale (never a hardcoded list) ───
fam_age AS (
  SELECT family AS parent_name, MIN(date) AS first_sale_date
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND family IS NOT NULL
  GROUP BY 1
),

-- ─── The sanction on record (latest row per family; absence is meaningful, not an error) ───
inv AS (
  SELECT parent_name, daily_investment, stop_date, sanctioned_on, note
  FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY parent_name
    ORDER BY updated_at DESC NULLS LAST, stop_date DESC, daily_investment DESC
  ) = 1
),

fam AS (
  SELECT
    a.parent_name,
    a.first_sale_date,
    DATE_DIFF(t.today, a.first_sale_date, DAY) AS family_age_days,
    ROUND(DATE_DIFF(t.today, a.first_sale_date, DAY) / 30.44, 1) AS family_age_months,
    DATE_ADD(a.first_sale_date, INTERVAL k.launch_window_days DAY) AS age_window_end,
    i.daily_investment AS sanctioned_daily_investment,
    ROUND(i.daily_investment * 30.44, 0) AS sanctioned_monthly_investment,
    i.stop_date        AS sanctioned_stop_date,
    i.sanctioned_on    AS sanctioned_on,
    i.note             AS sanctioned_note,
    -- the exemption ends at the EARLIER of the age boundary and the dated stop gate
    LEAST(
      DATE_ADD(a.first_sale_date, INTERVAL k.launch_window_days DAY),
      COALESCE(i.stop_date, DATE_ADD(a.first_sale_date, INTERVAL k.launch_window_days DAY))
    ) AS exempt_until,
    k.launch_window_days,
    t.today
  FROM fam_age a
  CROSS JOIN k
  CROSS JOIN anchor t
  LEFT JOIN inv i ON i.parent_name = a.parent_name
),

-- ─── Every ENABLED campaign of a launch family (V_CAMPAIGN_FAMILY_MAP = the ONE attribution) ───
camp AS (
  SELECT
    CAST(c.campaign_id AS STRING) AS campaign_id,
    c.campaign_name,
    c.campaign_type,
    c.campaign_state,
    c.daily_budget AS current_budget,
    c.creation_date,
    f.*
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m
  JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
    ON CAST(c.campaign_id AS STRING) = CAST(m.campaign_id AS STRING)
  JOIN fam f ON f.parent_name = m.parent_name
  WHERE f.today <= f.exempt_until          -- launch phase; expires by itself
),

-- ─── Per-campaign spend + SETTLED evidence (channel-aware settle) ───
ev AS (
  SELECT
    c.campaign_id,
    MIN(fa.date) AS first_activity,
    ROUND(SUM(IF(fa.date >= DATE_SUB(c.today, INTERVAL 7 DAY) AND fa.date < c.today, fa.Ads_cost, 0)), 2) AS spend_7d,
    ROUND(SUM(IF(fa.date BETWEEN c.settle_start AND c.settle_end, fa.Ads_cost, 0)), 2)     AS settled_spend,
    ROUND(SUM(IF(fa.date BETWEEN c.settle_start AND c.settle_end, fa.GROSS_PROFIT, 0)), 2) AS settled_gp,
    SUM(IF(fa.date BETWEEN c.settle_start AND c.settle_end, fa.Ads_clicks, 0))  AS settled_clicks,
    SUM(IF(fa.date BETWEEN c.settle_start AND c.settle_end, fa.Ads_orders, 0))  AS settled_orders
  FROM (
    SELECT
      c0.campaign_id, c0.today,
      DATE_SUB(c0.today, INTERVAL IF(c0.campaign_type = 'SB', kk.settle_days_sb, kk.settle_days_sp) DAY) AS settle_end,
      DATE_SUB(
        DATE_SUB(c0.today, INTERVAL IF(c0.campaign_type = 'SB', kk.settle_days_sb, kk.settle_days_sp) DAY),
        INTERVAL kk.evidence_days - 1 DAY) AS settle_start,
      DATE_SUB(c0.today, INTERVAL kk.fact_scan_days DAY) AS scan_from
    FROM camp c0 CROSS JOIN k kk
  ) c
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON CAST(fa.campaign_id AS STRING) = c.campaign_id
   AND fa.date >= c.scan_from
   AND fa.date <  c.today               -- complete days only
  GROUP BY 1
),

joined AS (
  SELECT
    c.*,
    COALESCE(e.spend_7d, 0)       AS spend_7d,
    COALESCE(e.settled_spend, 0)  AS settled_spend,
    COALESCE(e.settled_gp, 0)     AS settled_gp,
    COALESCE(e.settled_clicks, 0) AS settled_clicks,
    COALESCE(e.settled_orders, 0) AS settled_orders,
    e.first_activity,
    -- two SUMs, never two ANY_VALUEs
    ROUND(SAFE_DIVIDE(e.settled_gp, NULLIF(e.settled_spend, 0)), 2) AS settled_gp_roas
  FROM camp c
  LEFT JOIN ev e ON e.campaign_id = c.campaign_id
),

rolled AS (
  SELECT
    j.*,
    kk.winner_gp_roas, kk.winner_min_clicks, kk.evidence_days, kk.grace_days,
    ROUND(SUM(j.spend_7d) OVER (PARTITION BY j.parent_name) / 7.0, 2) AS family_daily_spend_7d,
    ROUND(SUM(j.current_budget) OVER (PARTITION BY j.parent_name), 2) AS family_budget_total,
    COUNT(*) OVER (PARTITION BY j.parent_name) AS family_campaigns
  FROM joined j CROSS JOIN k kk
)

SELECT
  -- ─── identity ───
  campaign_id,
  campaign_name,
  campaign_type,                                    -- SP | SB (drives the settle window)
  campaign_state,
  parent_name                       AS family,
  current_budget,

  -- ─── membership: computed from the family's own first sale, never a list ───
  first_sale_date                   AS family_first_sale,
  family_age_days,
  family_age_months,
  launch_window_days,                               -- 183 — the boundary, exposed so it is auditable
  age_window_end,                                   -- first sale + launch_window_days
  exempt_until,                                     -- EARLIER of age_window_end and sanctioned_stop_date
  DATE_DIFF(exempt_until, today, DAY) AS exempt_days_left,
  TRUE                              AS exempt_active,   -- camp already filters today <= exempt_until
  IF(sanctioned_stop_date IS NOT NULL AND sanctioned_stop_date <= age_window_end,
     'SANCTIONED_STOP_DATE', 'FAMILY_AGE_183D')     AS exempt_until_source,

  -- ─── the sanction on record (NULL = none; the exemption then rests on age alone) ───
  sanctioned_daily_investment,
  sanctioned_monthly_investment,
  sanctioned_stop_date,
  sanctioned_on,
  sanctioned_note,

  -- ─── bound 2: is the family inside the envelope it was given? ───
  family_daily_spend_7d,
  family_budget_total,
  family_campaigns,
  ROUND(family_daily_spend_7d - sanctioned_daily_investment, 2) AS envelope_over_by_daily,
  CASE
    WHEN sanctioned_daily_investment IS NULL                     THEN 'NO_SANCTION'
    WHEN family_daily_spend_7d <= sanctioned_daily_investment    THEN 'WITHIN_ENVELOPE'
    ELSE 'OVER_ENVELOPE'
  END AS envelope_state,
  -- Over-envelope is a BUDGET decision for Ori, never a coach ROAS cut. TRUE = route it to Ori.
  (sanctioned_daily_investment IS NOT NULL
     AND family_daily_spend_7d > sanctioned_daily_investment) AS escalate_to_ori,

  -- ─── settled evidence for this campaign (28 settled days, tier-COGS GP over spend) ───
  settled_spend,
  settled_gp,
  settled_gp_roas,
  settled_clicks,
  settled_orders,
  spend_7d,
  evidence_days,
  -- winners are never pulled down — if money must come out, it comes out of these LAST
  (settled_clicks >= winner_min_clicks AND COALESCE(settled_gp_roas, 0) >= winner_gp_roas) AS protected_winner,
  -- "if you must take money out, take it here first": worst settled GP-ROAS first, biggest spender
  -- as the tiebreak, protected winners always last. Deterministic (campaign_id closes every tie).
  ROW_NUMBER() OVER (
    PARTITION BY parent_name
    ORDER BY
      (settled_clicks >= winner_min_clicks AND COALESCE(settled_gp_roas, 0) >= winner_gp_roas),
      COALESCE(settled_gp_roas, 0) ASC,
      spend_7d DESC,
      campaign_id
  ) AS envelope_trim_rank,

  -- ─── grace: the ONE containment that is not a loss-cut and therefore survives ───
  first_activity,
  (first_activity IS NOT NULL AND DATE_DIFF(today, first_activity, DAY) < grace_days) AS in_grace_window,
  -- the gate's CONTAIN flag: block the ROAS-driven contain, keep the broken-launch contain
  NOT (first_activity IS NOT NULL AND DATE_DIFF(today, first_activity, DAY) < grace_days) AS blocks_contain,

  -- ─── the policy, in words, decided here so the panel only prints it ───
  'CAMPAIGN_STOP · GUARDIAN_BUDGET_DECREASE · BLITZ_BUDGET_DECREASE · COOLDOWN_BUDGET_REDUCE · RESTORE_BUDGET_PRE_PEAK · GUARDIAN_BUDGET_CONTAIN (post-grace only)' AS blocks_enforced,
  'Coach target-grain ROAS park (STOP_TARGET) · engine parks in V_OOB_KEYWORD / V_KEYWORD_LIFT — named in the doctrine, NOT wired in v27.56 (the OOB seat model parks by CAPACITY and is the sanctioned launch mechanism; blocking it would break the engine the exemption protects)' AS blocks_pending,
  'Search-term negation (NEGATE_TERM / STOP_TERM) — the sanctioned bleed control · THE LAUNCH BID LADDER (v27.59, V_LAUNCH_BID_LADDER: GP-ROAS on the SHORT window — 7d off peak, 3d in peak — under 0.5 trims the bid 10%, 0.5-0.7 trims 5%, 0.7-0.9 improving and >=0.9 profitable do nothing; never below the per-format floor, never a budget number) · obvious-waste bid trims (DARK_BRAKE / TRIM_BID / FIT_CPC) · the wake step-down · LAUNCH_TAPER at EXIT/POST · budget INCREASES · DEFENSE_BUDGET_FLOOR · STOP_SEASONAL (calendar, not profit) · broken-launch containment inside the first 14 days (>$25 spent, ZERO orders) · bringing the family back inside its sanctioned envelope' AS allows,

  CONCAT(
    CAST(family_age_months AS STRING), '-month-old launch family — ',
    'exempt from budget loss-cuts until ', CAST(exempt_until AS STRING),
    ' (', IF(sanctioned_stop_date IS NOT NULL AND sanctioned_stop_date <= age_window_end,
             'sanctioned stop date', 'family age boundary, 183d from first sale'), ', ',
    CAST(DATE_DIFF(exempt_until, today, DAY) AS STRING), ' days left). ',
    CASE
      WHEN sanctioned_daily_investment IS NULL
        THEN 'No sanctioned investment on record — the exemption rests on family age alone.'
      WHEN family_daily_spend_7d > sanctioned_daily_investment
        THEN CONCAT('OVER ENVELOPE: the family is spending $', CAST(family_daily_spend_7d AS STRING),
                    '/day against a sanctioned $', CAST(sanctioned_daily_investment AS STRING),
                    '/day. Taking money out is YOUR budget decision (worst settled GP-ROAS first, winners last) — not a coach ROAS cut.')
      ELSE CONCAT('Within envelope: $', CAST(family_daily_spend_7d AS STRING), '/day of a sanctioned $',
                  CAST(sanctioned_daily_investment AS STRING), '/day.')
    END
  ) AS exempt_reason

FROM rolled;
