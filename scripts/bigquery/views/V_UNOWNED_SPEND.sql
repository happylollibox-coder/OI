-- =============================================
-- V_UNOWNED_SPEND — the money the three layers cannot see (2026-08-25).
-- Doctrine: architecture/THREE_LAYERS.md §1.4 (a layer must be independently queryable, and asking
-- must change nothing), §10.1 row "Outside the Catalog entirely". SOP: architecture/UNOWNED_SPEND.md.
--
-- WHAT THIS IS. One row per SPENDING SUBJECT that has no row in FACT_KEYWORD_STATE — the table the
-- Catalog's universe is materialised into. A subject with no row there is invisible to all three
-- layers at once: the Catalog never valued it, the Brain never funded it, Pacing never priced it,
-- and no park, no ceiling and no stop can ever reach it. It spends anyway. This view makes that
-- money countable daily instead of rediscoverable once a quarter.
--
-- THIS VIEW IS REPORTING ONLY, AND DELIBERATELY SO. It reads. It writes nothing, it is read by no
-- engine, no book and no generator, and it is not in the orchestrator. Wiring these subjects INTO
-- the universe would change what the account does and is Ori's decision, not this view's — see the
-- SOP. The measurement half of violations 4 and 21 is what closes here; the fix half stays open.
--
-- IT ISSUES NO VERDICT, AND THAT IS THE POINT. §1.1: a catalog does not issue commands, and this
-- view is not even a catalog — it is a census of subjects the catalog has never met. Where a bar
-- exists it prints the bar and the return side by side and stops. Where no family maps to the
-- campaign there is no bar, so there is nothing to compare and the row says so in words. HOUSE
-- RULE: unmeasured never reads as bad. A subject with no clicks in the window carries
-- reading = 'NO_EVIDENCE' (§2.7) and its GP-ROAS of 0.0 is a division by nothing, not a loss.
--
-- WHERE IT IMPROVES ON THE BASELINE QUERY (docs/superpowers/specs/2026-08-24-three-layers-baseline.md,
-- probe "OUTSIDE THE CATALOG ENTIRELY"). That query is the ancestor of this view and its population
-- test — LEFT JOIN the window's spending (keyword_id, campaign_id) pairs to FACT_KEYWORD_STATE and
-- keep the misses — is reproduced here exactly. Four things are different, each on purpose:
--
--   1. GRAIN. The baseline counts (campaign, keyword) PAIRS. Under the sentinel that collapses every
--      product target in an SB campaign into ONE row, because they all arrive as keyword_id '-1' —
--      the largest baseline row is really a bundle of targets. This view is at TARGET grain
--      (campaign, keyword_id, targeting), so a product target is its own subject, which is what the
--      doctrine means by a subject (§2.1). The pair count is still recoverable
--      (COUNT(DISTINCT campaign_id || keyword_id)) and still reconciles to the baseline's, and the
--      spend total is identical either way — regrouping moves no dollars.
--   2. TWO WINDOWS, NOT ONE. The baseline quotes a 28-day average. A subject whose campaign was
--      paused three weeks ago still carries 28-day spend and is NOT a live leak. Every row and the
--      summary carry the 7-day figure beside the 28-day one so a live leak can be told from a tail.
--      Read both before quoting a total. This is the single most misreadable thing about the
--      headline number.
--   3. A CLASSIFIED REASON. The baseline says how much; it does not say why, so it cannot be acted
--      on. Every row here carries reason_class (four) and reason (six) — see below — and the
--      classification is exhaustive by construction: the final arm is an explicit reason, never a
--      blank or a NULL, and the acceptance test counts rows outside the declared vocabulary.
--   4. NO DECLARED REFERENCE BAR. The baseline scored the population against 0.8431, the median of
--      the six live family bars, and marked that figure MEDIUM for exactly the right reason — these
--      subjects do not own that bar. This view refuses the substitute. It reads the bar the campaign
--      actually maps to in T_FAMILY_BAR and leaves the rest NULL.
--
-- THE FOUR REASON CLASSES, AND THE SIX REASONS INSIDE THEM. Precedence is top-down and every row
-- takes the FIRST arm that matches, so the classification is a partition and not a set of tags. The
-- order is by what BINDS: a target in a paused campaign cannot be made visible by fixing the target.
--
--   SENTINEL                    1. SENTINEL_TARGET_ID           keyword_id = '-1'. Not an id at all.
--   CAMPAIGN_OUTSIDE_UNIVERSE   2. CAMPAIGN_ABSENT_FROM_DIM     no campaign row to join.
--                               3. CAMPAIGN_NOT_ENABLED         campaign state is not ENABLED.
--   SUBJECT_OUTSIDE_UNIVERSE    4. SUBJECT_ABSENT_FROM_DIM_KEYWORD  no DIM_KEYWORD row, ever.
--                               5. SUBJECT_NOT_ENABLED          no CURRENT + ENABLED DIM_KEYWORD row.
--   DROPPED_DOWNSTREAM          6. IN_UNIVERSE_NO_STATE_ROW     passes every gate above and still has
--                                                               no state row — a build defect, not a
--                                                               wiring gap.
--
-- The gates in arms 2-5 are not invented here: they are V_KEYWORD_GUARD's own `kw` CTE, which is
-- what defines the universe FACT_KEYWORD_STATE is built from — DIM_KEYWORD rows that are is_current
-- and ENABLED, joined to V_DIM_CAMPAIGN_CURRENT campaigns whose campaign_state is ENABLED. If that
-- CTE changes, arms 2-5 must change with it or this view will start lying about why.
--
-- WINDOW. 28 complete days ending at the ADS WATERMARK MINUS ONE (house convention: FACT_AMAZON_ADS
-- day-1 is only ~88-90% loaded, so the newest day is dropped). The watermark is read from the fact
-- table itself, so the view re-anchors on its own the moment the feed advances.
--
-- HOW LONG IT HAS BEEN SPENDING UNSEEN — READ THE COLUMN NAME LITERALLY. days_in_current_run counts
-- days of SPENDING, from the start of the current run (a run breaks on a gap longer than
-- run_gap_days) inside a 365-day lookback. It is NOT "days unowned", and it cannot be: the Catalog
-- is replaced nightly and holds one snapshot (violation 6), so nothing in this warehouse knows what
-- FACT_KEYWORD_STATE contained last month. A long run means the money is old, not that the hole is.
--
-- GP RULE. Gross profit is the stored FACT_AMAZON_ADS.GROSS_PROFIT column, never recomputed — see
-- the rule in V_KEYWORD_GUARD's header, and the $229.16 -> $37.17 collapse that put it there.
--
-- DETERMINISM. No ANY_VALUE anywhere: the descriptive strings are MAX() over the window, which is a
-- total ordering, and no two aggregates are ever divided into each other except SUM/SUM over the
-- same rows. The Catalog side reads the latest snapshot_date explicitly rather than the whole table,
-- so the answer does not change shape if FACT_KEYWORD_STATE ever starts keeping history.
--
-- RE-RUN THE HEADLINE (do not quote a number from this comment — Standing Rule 0):
--   SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND_SUMMARY` WHERE reason_class = '__ALL__';
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNOWNED_SPEND`
OPTIONS (
  description = "THE MONEY THE THREE LAYERS CANNOT SEE (2026-08-25). One row per spending SUBJECT — (campaign_id, keyword_id, targeting) — that has NO row in FACT_KEYWORD_STATE, over the 28 complete days ending at the ads watermark minus one. A subject with no state row is invisible to all three layers at once: never valued by the Catalog, never funded by the Brain, never priced by Pacing, and unreachable by any park, ceiling or stop. It spends anyway. REPORTING ONLY: reads everything, writes nothing, is read by no engine or book, and is not in the orchestrator — asking changes nothing (THREE_LAYERS.md §1.4). IT ISSUES NO VERDICT: where the campaign maps to a family it prints family_bar beside gp_roas_28d and stops; where it does not, bar-derived columns are NULL and judgeability says so. Unmeasured never reads as bad — a subject with no clicks carries reading = 'NO_EVIDENCE' and its 0.0 GP-ROAS is a division by nothing. WHY EACH ROW IS INVISIBLE, exhaustively and by first-match precedence: SENTINEL (keyword_id '-1', an SB product target arriving under a sentinel that is not an id) | CAMPAIGN_OUTSIDE_UNIVERSE (campaign absent from the campaign dimension, or not ENABLED) | SUBJECT_OUTSIDE_UNIVERSE (no DIM_KEYWORD row at all, or no current ENABLED one) | DROPPED_DOWNSTREAM (passes every universe gate and still has no state row — a build defect). The gates mirror V_KEYWORD_GUARD's own kw CTE; if that changes, this must change with it. READ THE TWO WINDOWS TOGETHER: spend_per_day_28d and spend_per_day_7d. A subject whose campaign was paused three weeks ago still carries 28-day spend and is not a live leak. days_in_current_run counts days of SPENDING inside a 365-day lookback, NOT days unowned — the Catalog keeps one snapshot (violation 6) so nothing knows what it held last month. Improves on the baseline probe in docs/superpowers/specs/2026-08-24-three-layers-baseline.md by moving to target grain (the sentinel bundled many targets into one row), adding the 7-day window, classifying the reason, and refusing the declared reference bar the baseline itself marked MEDIUM. Account-level totals and the daily number to watch: V_UNOWNED_SPEND_SUMMARY. SOP: architecture/UNOWNED_SPEND.md."
)
AS
WITH
-- ---------------------------------------------------------------------------------------------
-- THE DECLARED CONSTANTS. Changing one of these changes the answer; nothing else in this file does.
-- ---------------------------------------------------------------------------------------------
k AS (
  SELECT
    28  AS window_days,             -- complete days the headline is measured over. Matches the
                                    -- baseline probe this view descends from, so the two compare.
    7   AS recent_days,             -- the live-leak window, published beside the headline so a tail
                                    -- from a paused campaign cannot be read as money burning today.
    1   AS watermark_lag_days,      -- days dropped off the end of the ads feed (day-1 ~88-90% loaded)
    365 AS history_days,            -- lookback for "how long has this been spending"
    14  AS run_gap_days,            -- a spending run breaks on a gap LONGER than this many days
    30  AS min_clicks_for_a_reading -- the clicks below which a return is not a reading. DERIVED, not
                                    -- picked: roughly the clicks that produce one expected order at
                                    -- this account's own conversion rate, so below it a zero return
                                    -- is the ORDINARY outcome of a perfectly good subject and says
                                    -- nothing. Re-derive it if that rate moves materially. It is a
                                    -- LABEL ONLY: it gates nothing, hides no row and moves no total —
                                    -- it exists so that unmeasured can never read as bad.
),
wm AS (
  SELECT DATE_SUB(MAX(a.date), INTERVAL k.watermark_lag_days DAY) AS wm_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN k
  GROUP BY k.watermark_lag_days
),
-- ---------------------------------------------------------------------------------------------
-- THE CATALOG'S UNIVERSE, as materialised. The latest snapshot only — explicit, so the population
-- test does not silently widen if this table ever starts keeping history (violation 6, unfixed).
-- ---------------------------------------------------------------------------------------------
cat AS (
  SELECT DISTINCT campaign_id, keyword_id
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
-- ---------------------------------------------------------------------------------------------
-- SPENDING SUBJECTS in the window, at target grain.
-- ---------------------------------------------------------------------------------------------
sp AS (
  SELECT
    a.campaign_id,
    a.keyword_id,
    a.targeting,
    MAX(a.campaign_name)                                                   AS campaign_name,
    MAX(a.campaign_type)                                                   AS campaign_type,
    SUM(a.Ads_cost)                                                        AS spend_w,
    SUM(a.GROSS_PROFIT)                                                    AS gp_w,
    SUM(a.Ads_clicks)                                                      AS clicks_w,
    SUM(a.Ads_orders)                                                      AS orders_w,
    SUM(a.Ads_sales)                                                       AS sales_w,
    SUM(IF(a.date > DATE_SUB(w.wm_date, INTERVAL k.recent_days DAY), a.Ads_cost, 0))     AS spend_r,
    SUM(IF(a.date > DATE_SUB(w.wm_date, INTERVAL k.recent_days DAY), a.GROSS_PROFIT, 0)) AS gp_r,
    SUM(IF(a.date > DATE_SUB(w.wm_date, INTERVAL k.recent_days DAY), a.Ads_clicks, 0))   AS clicks_r,
    MAX(IF(a.Ads_cost > 0, a.date, NULL))                                  AS last_spend_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN k
  CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.wm_date, INTERVAL k.window_days - 1 DAY) AND w.wm_date
    AND a.keyword_id IS NOT NULL
  GROUP BY a.campaign_id, a.keyword_id, a.targeting
  HAVING SUM(a.Ads_cost) > 0
),
-- ---------------------------------------------------------------------------------------------
-- HOW LONG IT HAS BEEN SPENDING. Days of spending, not days unowned — see the header.
-- ---------------------------------------------------------------------------------------------
daily AS (
  SELECT a.campaign_id, a.keyword_id, a.targeting, a.date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN k
  CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.wm_date, INTERVAL k.history_days - 1 DAY) AND w.wm_date
    AND a.keyword_id IS NOT NULL
  GROUP BY a.campaign_id, a.keyword_id, a.targeting, a.date
  HAVING SUM(a.Ads_cost) > 0
),
gaps AS (
  SELECT d.campaign_id, d.keyword_id, d.targeting, d.date,
         DATE_DIFF(d.date,
                   LAG(d.date) OVER (PARTITION BY d.campaign_id, d.keyword_id, d.targeting
                                     ORDER BY d.date),
                   DAY) AS gap_days
  FROM daily d
),
runs AS (
  SELECT g.campaign_id, g.keyword_id, g.targeting,
         MIN(g.date)                                                            AS first_spend_date,
         COUNT(*)                                                               AS spending_days,
         MAX(IF(g.gap_days IS NULL OR g.gap_days > k.run_gap_days, g.date, NULL)) AS run_start
  FROM gaps g CROSS JOIN k
  GROUP BY g.campaign_id, g.keyword_id, g.targeting
),
-- ---------------------------------------------------------------------------------------------
-- THE UNIVERSE GATES, exactly as V_KEYWORD_GUARD's kw CTE applies them.
-- ---------------------------------------------------------------------------------------------
dk AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         LOGICAL_OR(is_current AND UPPER(state) = 'ENABLED')                AS has_current_enabled,
         MAX(IF(is_current, UPPER(state), NULL))                            AS current_state
  FROM `onyga-482313.OI.DIM_KEYWORD`
  GROUP BY 1, 2
),
cc AS (
  SELECT campaign_id, campaign_state
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
),
-- ---------------------------------------------------------------------------------------------
-- THE BAR IT WOULD BE JUDGED AGAINST, IF IT HAD ONE. T_FAMILY_BAR is the nightly snapshot and is
-- campaign-grain — the same source SP_SNAPSHOT_KEYWORD_STATE reads. Never V_FAMILY_BAR (ceiling).
-- No fallback and no substitute bar: a campaign with no family here has no bar, full stop.
-- ---------------------------------------------------------------------------------------------
fb AS (
  SELECT campaign_id, family, keyword_bar, bar_exempt, book
  FROM `onyga-482313.OI.T_FAMILY_BAR`
),
-- ---------------------------------------------------------------------------------------------
-- THE POPULATION: spending subjects with no Catalog row, classified.
-- ---------------------------------------------------------------------------------------------
base AS (
  SELECT
    w.wm_date                                                                       AS as_of,
    k.window_days,
    k.recent_days,
    sp.campaign_id,
    sp.keyword_id,
    sp.targeting                                                                    AS target_text,
    sp.campaign_name,
    IF(UPPER(COALESCE(sp.campaign_type, 'SP')) = 'SB', 'SB', 'SP')                  AS channel,
    CASE
      WHEN LOWER(sp.targeting) IN ('close-match', 'loose-match', 'substitutes', 'complements')
        THEN 'AUTO_CLAUSE'
      WHEN LOWER(sp.targeting) LIKE 'asin%'     THEN 'PRODUCT_TARGET'
      WHEN LOWER(sp.targeting) LIKE 'category%' THEN 'CATEGORY_TARGET'
      ELSE 'KEYWORD'
    END                                                                             AS subject_kind,
    ROUND(sp.spend_w / k.window_days, 4)                                            AS spend_per_day_28d,
    ROUND(sp.gp_w    / k.window_days, 4)                                            AS gp_per_day_28d,
    ROUND(sp.spend_r / k.recent_days, 4)                                            AS spend_per_day_7d,
    ROUND(sp.gp_r    / k.recent_days, 4)                                            AS gp_per_day_7d,
    sp.clicks_w                                                                     AS clicks_28d,
    sp.orders_w                                                                     AS orders_28d,
    ROUND(sp.sales_w, 2)                                                            AS sales_28d,
    sp.clicks_r                                                                     AS clicks_7d,
    ROUND(SAFE_DIVIDE(sp.gp_w, sp.spend_w), 4)                                      AS gp_roas_28d,
    ROUND(SAFE_DIVIDE(sp.gp_r, sp.spend_r), 4)                                      AS gp_roas_7d,
    sp.last_spend_date,
    r.first_spend_date,
    r.spending_days                                                                 AS spending_days_365d,
    r.run_start                                                                     AS current_run_start,
    DATE_DIFF(w.wm_date, r.run_start, DAY) + 1                                      AS days_in_current_run,
    DATE_DIFF(w.wm_date, sp.last_spend_date, DAY)                                   AS days_since_last_spend,
    (sp.spend_r > 0)                                                                AS spending_in_last_7d,
    fb.family,
    fb.book                                                                         AS family_book,
    IF(COALESCE(fb.bar_exempt, FALSE), NULL, fb.keyword_bar)                        AS family_bar,
    COALESCE(fb.bar_exempt, FALSE)                                                  AS bar_exempt,
    cc.campaign_state,
    dkw.current_state                                                               AS subject_state,
    CASE WHEN sp.clicks_w = 0                             THEN 'NO_EVIDENCE'
         WHEN sp.clicks_w < k.min_clicks_for_a_reading    THEN 'THIN'
         ELSE 'MEASURED' END                                                        AS reading,
    -- THE PARTITION. First match wins; the last arm is a named reason, never a blank.
    CASE
      WHEN sp.keyword_id = '-1'                    THEN 'SENTINEL_TARGET_ID'
      WHEN cc.campaign_id IS NULL                  THEN 'CAMPAIGN_ABSENT_FROM_DIM'
      WHEN cc.campaign_state <> 'ENABLED'          THEN 'CAMPAIGN_NOT_ENABLED'
      WHEN dkw.keyword_id IS NULL                  THEN 'SUBJECT_ABSENT_FROM_DIM_KEYWORD'
      WHEN NOT dkw.has_current_enabled             THEN 'SUBJECT_NOT_ENABLED'
      ELSE 'IN_UNIVERSE_NO_STATE_ROW'
    END                                                                             AS reason,
    CASE
      WHEN sp.keyword_id = '-1'                    THEN 'SENTINEL'
      WHEN cc.campaign_id IS NULL                  THEN 'CAMPAIGN_OUTSIDE_UNIVERSE'
      WHEN cc.campaign_state <> 'ENABLED'          THEN 'CAMPAIGN_OUTSIDE_UNIVERSE'
      WHEN dkw.keyword_id IS NULL                  THEN 'SUBJECT_OUTSIDE_UNIVERSE'
      WHEN NOT dkw.has_current_enabled             THEN 'SUBJECT_OUTSIDE_UNIVERSE'
      ELSE 'DROPPED_DOWNSTREAM'
    END                                                                             AS reason_class
  FROM sp
  CROSS JOIN k
  CROSS JOIN wm w
  LEFT JOIN cat ON cat.campaign_id = sp.campaign_id AND cat.keyword_id = sp.keyword_id
  LEFT JOIN runs r ON r.campaign_id = sp.campaign_id AND r.keyword_id = sp.keyword_id
                  AND r.targeting  = sp.targeting
  LEFT JOIN dk dkw ON dkw.campaign_id = sp.campaign_id AND dkw.keyword_id = sp.keyword_id
  LEFT JOIN cc      ON cc.campaign_id = sp.campaign_id
  LEFT JOIN fb      ON fb.campaign_id = sp.campaign_id
  WHERE cat.keyword_id IS NULL
)
SELECT
  b.as_of,
  b.window_days,
  b.recent_days,
  b.reason_class,
  b.reason,
  b.subject_kind,
  b.channel,
  b.campaign_id,
  b.keyword_id,
  b.target_text,
  b.campaign_name,
  b.campaign_state,
  b.subject_state,
  b.family,
  b.family_book,
  b.family_bar,
  b.bar_exempt,
  b.spend_per_day_28d,
  b.gp_per_day_28d,
  b.gp_roas_28d,
  b.spend_per_day_7d,
  b.gp_per_day_7d,
  b.gp_roas_7d,
  b.clicks_28d,
  b.orders_28d,
  b.sales_28d,
  b.clicks_7d,
  b.spending_in_last_7d,
  b.reading,
  b.first_spend_date,
  b.current_run_start,
  b.days_in_current_run,
  b.spending_days_365d,
  b.last_spend_date,
  b.days_since_last_spend,
  -- JUDGEABILITY. Three states, and none of them is a verdict. A row is judgeable only when a real
  -- family bar exists for its campaign; everything else prints its return and stops.
  CASE
    WHEN b.reading = 'NO_EVIDENCE'       THEN 'NO_EVIDENCE'
    WHEN b.reading = 'THIN'              THEN 'TOO_THIN_TO_READ'
    WHEN b.bar_exempt                    THEN 'BAR_EXEMPT_INVEST_FAMILY'
    WHEN b.family_bar IS NULL            THEN 'NO_BAR_NO_FAMILY'
    ELSE 'HAS_BAR'
  END                                                                     AS judgeability,
  -- The one arithmetic comparison this view is entitled to make, and only where a bar exists and a
  -- reading exists. It is a DISTANCE, not a verdict: nothing here says what to do about it.
  IF(b.family_bar IS NOT NULL AND b.reading = 'MEASURED',
     ROUND(b.gp_roas_28d - b.family_bar, 4), NULL)                        AS gp_roas_minus_bar_28d,
  CASE
    WHEN b.reading = 'NO_EVIDENCE'
      THEN 'No verdict: it took no clicks in the window, so there is nothing here to read.'
    WHEN b.reading = 'THIN'
      THEN 'No verdict: it took fewer clicks than one expected order needs, so a zero or a low return is the ordinary outcome of a good subject and carries no information.'
    WHEN b.bar_exempt
      THEN 'No verdict: its family is an INVEST family, judged on budget and trajectory rather than a bar.'
    WHEN b.family_bar IS NULL
      THEN 'No verdict: its campaign maps to no family, so there is no bar to judge it against.'
    ELSE 'No verdict here by design: this view is a census, not a catalog. The Catalog has never seen this subject, so nothing has valued it.'
  END                                                                     AS verdict_withheld_because,
  -- ---------------------------------------------------------------------------------------------
  -- ONE PLAIN SENTENCE PER ROW: what it is, what it costs, why no layer can see it, and what it
  -- would take to make it visible. Written so a row can be pasted into a brief unedited.
  -- ---------------------------------------------------------------------------------------------
  CONCAT(
    CASE b.subject_kind
      WHEN 'PRODUCT_TARGET'  THEN CONCAT(b.channel, ' product target ')
      WHEN 'CATEGORY_TARGET' THEN CONCAT(b.channel, ' category target ')
      WHEN 'AUTO_CLAUSE'     THEN CONCAT(b.channel, ' auto clause ')
      ELSE CONCAT(b.channel, ' keyword ')
    END,
    IF(STRPOS(b.target_text, '"') > 0, b.target_text, CONCAT('"', b.target_text, '"')),
    ' in campaign "', COALESCE(b.campaign_name, b.campaign_id), '" spent $',
    FORMAT('%.2f', b.spend_per_day_28d), '/day over the last ', CAST(b.window_days AS STRING),
    ' complete days ($', FORMAT('%.2f', b.spend_per_day_7d), '/day in the last ',
    CAST(b.recent_days AS STRING), ', ', CAST(b.clicks_28d AS STRING), ' clicks, ',
    CAST(b.orders_28d AS STRING), ' orders) and has no row in the Catalog\'s keyword state, so no ',
    'layer can value it, fund it, price it, park it or stop it. ',
    CASE b.reason
      WHEN 'SENTINEL_TARGET_ID' THEN CONCAT(
        'It arrives under the sentinel target id "-1", which is not a real Amazon target id, so no ',
        '(campaign, keyword) key exists for it and it can never join DIM_KEYWORD. To make it ',
        'visible, SB product targets must be keyed on campaign plus target text — or resolved to ',
        'their real target ids — before the keyword universe is built.')
      WHEN 'CAMPAIGN_ABSENT_FROM_DIM' THEN CONCAT(
        'Its campaign has no row in the campaign dimension at all, so every target under it falls ',
        'outside the universe. To make it visible, the campaign must first appear in DIM_CAMPAIGN.')
      WHEN 'CAMPAIGN_NOT_ENABLED' THEN CONCAT(
        'Its campaign reads ', COALESCE(b.campaign_state, 'UNKNOWN'), ' in the campaign dimension, ',
        'and the universe is built from ENABLED campaigns only. ',
        IF(b.spending_in_last_7d,
           CONCAT('It is still spending, so the dimension and the ads feed disagree — check the ',
                  'campaign feed before reading this as a tail.'),
           CONCAT('It last spent on ', CAST(b.last_spend_date AS STRING),
                  ', so this is a tail from before the pause rather than money burning today.')))
      WHEN 'SUBJECT_ABSENT_FROM_DIM_KEYWORD' THEN CONCAT(
        'It has no row in the keyword dimension at all, current or historical, so nothing can look ',
        'it up. To make it visible, the target must be synced into DIM_KEYWORD.')
      WHEN 'SUBJECT_NOT_ENABLED' THEN CONCAT(
        'The keyword dimension reads it as ', COALESCE(b.subject_state, 'ABSENT'),
        ' while the ads feed still books spend against it, and the universe takes current ENABLED ',
        'rows only. ',
        IF(b.spending_in_last_7d,
           'It is still spending, so either the dimension is stale or it was re-enabled outside our books.',
           CONCAT('It last spent on ', CAST(b.last_spend_date AS STRING),
                  ', so this is most likely a tail from before it was paused.')))
      ELSE CONCAT(
        'It passes every universe gate — an enabled target in an enabled campaign — and the state ',
        'build still produced no row for it. That is a defect in SP_SNAPSHOT_KEYWORD_STATE or its ',
        'inputs, not a wiring gap.')
    END,
    ' ',
    CASE
      WHEN b.reading <> 'MEASURED'
        THEN CONCAT('It took ', CAST(b.clicks_28d AS STRING), ' clicks in the window — fewer than ',
                    'one expected order needs — so its return is not a measurement and must never ',
                    'be read as a loss.')
      WHEN b.bar_exempt
        THEN CONCAT('Its campaign maps to family ', b.family,
                    ', which is bar-exempt (INVEST), so no bar comparison applies; it returned ',
                    FORMAT('%.3f', b.gp_roas_28d), ' gross-profit dollars per ad dollar.')
      WHEN b.family_bar IS NULL
        THEN CONCAT('Its campaign maps to no family, so it has no bar and this view issues no ',
                    'verdict: it returned ', FORMAT('%.3f', b.gp_roas_28d),
                    ' gross-profit dollars per ad dollar, stated and not scored.')
      ELSE CONCAT('Its campaign maps to family ', b.family, ', whose bar is ',
                  FORMAT('%.3f', b.family_bar), '; it returned ', FORMAT('%.3f', b.gp_roas_28d),
                  ' gross-profit dollars per ad dollar. Both are stated here and neither is a ',
                  'verdict — the Catalog has never seen this subject.')
    END,
    ' It has been spending for ', CAST(COALESCE(b.days_in_current_run, 0) AS STRING),
    ' days in its current run (days of spending, not days unowned — the Catalog keeps one snapshot).'
  )                                                                       AS sentence,
  CURRENT_DATE('America/Los_Angeles')                                     AS computed_on
FROM base b
ORDER BY b.spend_per_day_28d DESC, b.campaign_id, b.keyword_id, b.target_text;
