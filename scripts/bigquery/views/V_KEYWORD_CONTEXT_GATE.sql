-- =============================================
-- V_KEYWORD_CONTEXT_GATE — the season-context contradiction gate (phase 3, v27.43, 2026-08-08).
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md §5 (wiring) + §6 (calibration record).
--
-- One row per keyword_text, KEYWORD GRAIN ONLY — auto clauses (close/loose/substitutes/
-- complements), asin%/category% targets and '*' are excluded up front: the ledger pools text
-- account-wide and those texts pool meaninglessly across campaigns (grain hazard). The engines
-- additionally join with NOT is_auto AND NOT is_pt so a gate can never touch a non-keyword row.
--
-- gate_action (precedence BLOCK_CUT > ENTRY_BLOCK > PARK_CONTEXT > NONE):
--   BLOCK_CUT    (WIRED)    current occurrence SETTLED clicks >= 15 AND GP-ROAS >= 1.0 — veto
--                           cuts/parks/brakes. Calibration 2026-08-08: bar 15 net +$2,080 strict /
--                           +$21,386 wide; protected winners earn ~3x what wrong protections lose.
--   ENTRY_BLOCK  (WIRED)    most recent CLOSED same-family occurrence MATURE verdict = LOSS ->
--                           half-allowance re-probe, never a hard block (hard block measured
--                           -$6,578; block+reprobe +$551, 12/13 stops correct). entry_state
--                           (v27.43: evaluated on the NEAR-SETTLED ns_* numbers, anchor-3):
--                             PROBING  ns_spend < probe_cap — engines let it run, funding bids
--                                      clamped to remaining_allowance (engine-side, v27.43)
--                             STOP     ns_spend >= cap AND ns_gp < ns_spend — stop funding,
--                                      UNLESS the 90d hatch releases it (>= 100 clicks at
--                                      GP-ROAS >= 1.0 over [anchor-89, anchor] -> RELEASED)
--                             RELEASED ns paid back OR 90d hatch — dissolves to NONE
--                           probe_cap (v27.46 TWO-TIER, evidence-scaled) =
--                             m x GREATEST(15 x COALESCE(tcpc, band), $5), where m keys on the
--                             DEEPEST same-family mature LOSS prior of the text (MAX clicks
--                             across all such priors - most evidence governs):
--                               m = 0.5  when MAX(clicks) >= 40  (tier DEEP - original half)
--                               m = 1.0  when 15-39             (tier THIN - full allowance)
--                             Rationale: a healthy ~6%-CVR keyword shows 0 orders in 20 clicks
--                             ~29% of the time - a thin LOSS is weak evidence. Exposed as
--                             loss_evidence_tier / loss_prior_max_clicks. LOSS thresholds and
--                             BLOCK_CUT untouched; the tier flows into probe_cap/
--                             remaining_allowance so the engines pick it up with ZERO edits.
--                           remaining_allowance = GREATEST(probe_cap - ns_spend, 0).
--                           OFF runs carry NO entry memory (never calibrated).
--   PARK_CONTEXT (ADVISORY) calibration FAIL — may NEVER move an action or bid. Best cell (flat
--                           $25 + GP-ROAS < 0.6 at >= 15 clicks) = +$1,274 but -$1,420 inside
--                           XMAS_PEAK (111% of net) -> suppressed inside XMAS_PEAK occurrences
--                           (the +$2,694 shape). Shown so Ori can see what it WOULD do.
--
-- BLOCK_CUT / PARK_CONTEXT stats are SETTLED (ledger discipline, date <= anchor-7): an
-- occurrence's first ~7 days read zero — those gates ARM as the occurrence settles. v27.43: the
-- ENTRY_BLOCK allowance alone reads the NEAR-SETTLED slice (date <= anchor-3, the spend settle
-- point). tcpc proxy = keyword's settled CPC over the 90d
-- before occurrence start (>=4 clicks) else the median keyword CPC of that window — deliberately
-- NOT the engines' target_cpc (v27.40 CPC-vs-bid unit hazard).
--
-- PLAN-COST NOTE (2026-08-08): the current-occurrence stats are THE LEDGER'S current-occurrence
-- slice, computed directly from FACT_AMAZON_ADS over [occurrence_start, LEAST(occurrence_end,
-- anchor-7)] with the doctrine GP formula verbatim — identical numbers to
-- V_KEYWORD_CONTEXT_LEDGER's row for this occurrence_key by construction (same source, same
-- formula, same date set: an occurrence is a contiguous date run). Reading the ledger VIEW here
-- dragged its full-history FACT x calendar join into BOTH engines' plans (V_OOB_KEYWORD also
-- re-plans V_KEYWORD_LIFT via lift_probes, so the subtree appeared twice) and pushed V_OOB_KEYWORD
-- from ~25s to ~176s. Verdict-writing still reads the ledger view — this slice is engine-side only.
--
-- v27.43 (2026-08-08): the ENTRY_BLOCK allowance goes NEAR-SETTLED + the 90d escape hatch.
-- FIX A — the settled ledger (anchor-7) left the re-probe allowance blind to money already out the
--   door: at wiring time all 54 ENTRY_BLOCK caps read "$0.00 spent" while raw FACT showed $733.68
--   spent Aug 1-7 against $261.00 of total caps (15 of 19 spending texts already over cap, worst
--   39.8x). entry_state (PROBING/STOP/RELEASED) is now evaluated on a NEAR-SETTLED slice of the
--   same FACT formula over [occurrence_start, anchor-3] — spend settles ~D+3 (measured settle
--   curve); sales accrue to D+7/D+14, so the early GP read biases verdicts toward STOP, which is
--   the conservative direction, and FIX B protects proven winners from it. New columns: ns_clicks,
--   ns_spend, ns_gp, ns_gp_roas, remaining_allowance = GREATEST(probe_cap - ns_spend, 0).
--   The SETTLED (cur_*) columns are untouched and keep feeding BLOCK_CUT — BLOCK_CUT stays on
--   fully-settled data by design.
-- FIX B — 90d escape hatch: a would-be STOP whose trailing-90d record (FACT, [anchor-89, anchor])
--   is GP-ROAS >= 1.0 on >= 100 clicks resolves to RELEASED instead ("90d: Nc at R.RRx - proven
--   earner, released"). A keyword's own proven recent record must never be contradicted by an
--   occurrence-window read on unsettled-sales days ('tween birthday gifts for girls' 3,862c at
--   1.17x was forecast to STOP without this). released_by_90d flags hatch releases.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE` AS
WITH
anchor AS (
  SELECT LEAST((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
               `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS a
),
cur AS (
  SELECT context_label, occurrence_key, occurrence_start, occurrence_end,
         REGEXP_REPLACE(context_label, r'_\d{4}$', '') AS family
  FROM `onyga-482313.OI.V_SEASON_CONTEXT`
  WHERE date = CURRENT_DATE('America/Los_Angeles')
),
-- current-occurrence SETTLED record (keyword rows only) — the ledger's current-occurrence slice
-- computed directly from FACT (see PLAN-COST NOTE): doctrine GP formula verbatim, settled days only
led AS (
  SELECT LOWER(TRIM(f.targeting)) AS keyword_text,
         SUM(f.Ads_clicks) AS clicks,
         SUM(f.Ads_cost) AS spend,
         SUM(f.Ads_sales - IFNULL(f.TOTAL_COST_PER_UNIT, 0) * f.Ads_units) AS gross_profit,
         SUM(f.Ads_sales - IFNULL(f.TOTAL_COST_PER_UNIT, 0) * f.Ads_units) - SUM(f.Ads_cost) AS net,
         SUM(f.Ads_orders) AS orders,
         SAFE_DIVIDE(SUM(f.Ads_sales - IFNULL(f.TOTAL_COST_PER_UNIT, 0) * f.Ads_units),
                     NULLIF(SUM(f.Ads_cost), 0)) AS gp_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, cur, anchor an
  WHERE f.date BETWEEN cur.occurrence_start
                   AND LEAST(cur.occurrence_end, DATE_SUB(an.a, INTERVAL 7 DAY))
    AND f.targeting IS NOT NULL AND TRIM(f.targeting) != ''
    AND NOT (LOWER(TRIM(f.targeting)) IN ('close-match', 'loose-match', 'substitutes', 'complements')
             OR LOWER(TRIM(f.targeting)) LIKE 'asin%' OR LOWER(TRIM(f.targeting)) LIKE 'category%'
             OR LOWER(TRIM(f.targeting)) = '*')
  GROUP BY 1
  HAVING SUM(f.Ads_clicks) > 0 OR SUM(f.Ads_cost) > 0
),
-- v27.43 FIX A: NEAR-SETTLED current-occurrence slice — same source/formula as led, but through
-- anchor-3 (spend settles ~D+3). ONLY entry_state and the allowance read this; BLOCK_CUT and the
-- PARK advisory stay on the settled led numbers.
led_ns AS (
  SELECT LOWER(TRIM(f.targeting)) AS keyword_text,
         SUM(f.Ads_clicks) AS clicks,
         SUM(f.Ads_cost) AS spend,
         SUM(f.Ads_sales - IFNULL(f.TOTAL_COST_PER_UNIT, 0) * f.Ads_units) AS gross_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, cur, anchor an
  WHERE f.date BETWEEN cur.occurrence_start
                   AND LEAST(cur.occurrence_end, DATE_SUB(an.a, INTERVAL 3 DAY))
    AND f.targeting IS NOT NULL AND TRIM(f.targeting) != ''
    AND NOT (LOWER(TRIM(f.targeting)) IN ('close-match', 'loose-match', 'substitutes', 'complements')
             OR LOWER(TRIM(f.targeting)) LIKE 'asin%' OR LOWER(TRIM(f.targeting)) LIKE 'category%'
             OR LOWER(TRIM(f.targeting)) = '*')
  GROUP BY 1
  HAVING SUM(f.Ads_clicks) > 0 OR SUM(f.Ads_cost) > 0
),
-- v27.43 FIX B: trailing-90d record for the escape hatch — full 90-day window ending at the
-- anchor ([anchor-89, anchor], inclusive). Deliberately NOT settle-capped: the hatch asks "has
-- this keyword proven itself recently at scale" (>= 100 clicks, GP-ROAS >= 1.0), and at 100+
-- clicks the unsettled tail only UNDERSTATES GP — a keyword that clears 1.0x here clears it
-- settled too. Deterministic within a data day (plain SUMs over a fixed date window).
r90 AS (
  SELECT LOWER(TRIM(f.targeting)) AS keyword_text,
         SUM(f.Ads_clicks) AS clicks,
         SAFE_DIVIDE(SUM(f.Ads_sales - IFNULL(f.TOTAL_COST_PER_UNIT, 0) * f.Ads_units),
                     NULLIF(SUM(f.Ads_cost), 0)) AS gp_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, anchor an
  WHERE f.date BETWEEN DATE_SUB(an.a, INTERVAL 89 DAY) AND an.a
    AND f.targeting IS NOT NULL AND TRIM(f.targeting) != ''
    AND NOT (LOWER(TRIM(f.targeting)) IN ('close-match', 'loose-match', 'substitutes', 'complements')
             OR LOWER(TRIM(f.targeting)) LIKE 'asin%' OR LOWER(TRIM(f.targeting)) LIKE 'category%'
             OR LOWER(TRIM(f.targeting)) = '*')
  GROUP BY 1
),
-- most recent CLOSED same-family occurrence verdict, MATURE only (maturity guard §4); no OFF memory
-- v27.46: loss_prior_max_clicks = MAX(clicks) over ALL same-family mature LOSS priors of the
-- text (analytic, evaluated before the QUALIFY keeps the most recent row) - the two-tier
-- allowance keys on the DEEPEST evidence, not just the arming (most recent) prior.
prior AS (
  SELECT v.keyword_text,
         v.occurrence_key AS prior_occurrence_key, v.context_label AS prior_label,
         v.verdict AS prior_verdict, v.clicks AS prior_clicks,
         ROUND(v.net, 2) AS prior_net,
         ROUND(SAFE_DIVIDE(v.gross_profit, NULLIF(v.spend, 0)), 2) AS prior_gp_roas,
         MAX(IF(v.verdict = 'LOSS', v.clicks, NULL))
           OVER (PARTITION BY v.keyword_text) AS loss_prior_max_clicks
  FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` v
  JOIN cur ON REGEXP_REPLACE(v.context_label, r'_\d{4}$', '') = cur.family
          AND v.occurrence_end < cur.occurrence_start
  WHERE cur.family != 'OFF'
    AND v.mature_at_start
    AND NOT (v.keyword_text IN ('close-match', 'loose-match', 'substitutes', 'complements')
             OR v.keyword_text LIKE 'asin%' OR v.keyword_text LIKE 'category%'
             OR v.keyword_text = '*')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY v.keyword_text ORDER BY v.occurrence_end DESC) = 1
),
-- tcpc proxy: settled CPC over the 90d BEFORE occurrence start (all-history days there are settled
-- once the occurrence is >= 7d old; at occurrence start they already are)
tc AS (
  SELECT LOWER(TRIM(f.targeting)) AS keyword_text,
         ROUND(SAFE_DIVIDE(SUM(f.Ads_cost), NULLIF(SUM(f.Ads_clicks), 0)), 2) AS tcpc,
         SUM(f.Ads_clicks) AS pre_clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, cur, anchor an
  WHERE f.date >= DATE_SUB(cur.occurrence_start, INTERVAL 90 DAY)
    AND f.date < cur.occurrence_start
    AND f.date <= DATE_SUB(an.a, INTERVAL 7 DAY)
    AND f.targeting IS NOT NULL AND TRIM(f.targeting) != ''
  GROUP BY 1
  HAVING SUM(f.Ads_clicks) >= 4
),
band AS (
  -- v27.42.1 (safety-live verifier, 2026-08-08): APPROX_QUANTILES is a nondeterministic
  -- sketch -- back-to-back queries returned different medians (0.63 vs 0.62), flipping the
  -- probe cap on 28 of 54 ENTRY_BLOCK rows ($4.72 vs $4.65). At the PROBING->STOP boundary
  -- that is a coin-flip verdict, and LIFT/OOB query this gate independently so they could
  -- disagree on the same keyword in the same minute. Exact median instead.
  SELECT DISTINCT PERCENTILE_CONT(tcpc, 0.5) OVER () AS med_cpc
  FROM tc
  WHERE NOT (keyword_text IN ('close-match', 'loose-match', 'substitutes', 'complements')
             OR keyword_text LIKE 'asin%' OR keyword_text LIKE 'category%' OR keyword_text = '*')
),
pop AS (
  SELECT keyword_text FROM led
  UNION DISTINCT
  SELECT keyword_text FROM prior
),
calc AS (
  SELECT
    p.keyword_text,
    cur.context_label, cur.occurrence_key, cur.occurrence_start, cur.occurrence_end, cur.family,
    DATE_SUB(an.a, INTERVAL 7 DAY) AS settled_through,
    COALESCE(led.clicks, 0)        AS cur_clicks,
    ROUND(COALESCE(led.spend, 0), 2)        AS cur_spend,
    ROUND(COALESCE(led.gross_profit, 0), 2) AS cur_gross_profit,
    ROUND(COALESCE(led.net, 0), 2)          AS cur_net,
    ROUND(led.gp_roas, 2)          AS cur_gp_roas,
    COALESCE(led.orders, 0)        AS cur_orders,
    -- v27.43 FIX A: near-settled occurrence record (anchor-3) — entry_state + allowance read THESE
    COALESCE(ns.clicks, 0)                  AS ns_clicks,
    ROUND(COALESCE(ns.spend, 0), 2)         AS ns_spend,
    ROUND(COALESCE(ns.gross_profit, 0), 2)  AS ns_gp,
    ROUND(SAFE_DIVIDE(ns.gross_profit, NULLIF(ns.spend, 0)), 2) AS ns_gp_roas,
    DATE_SUB(an.a, INTERVAL 3 DAY)          AS near_settled_through,
    -- v27.43 FIX B: trailing-90d record for the escape hatch
    COALESCE(r.clicks, 0)      AS r90_clicks,
    ROUND(r.gp_roas, 2)        AS r90_gp_roas,
    (COALESCE(r.clicks, 0) >= 100 AND COALESCE(r.gp_roas, 0) >= 1.0) AS q_hatch90,
    pr.prior_occurrence_key, pr.prior_label, pr.prior_verdict, pr.prior_clicks,
    pr.prior_net, pr.prior_gp_roas,
    pr.loss_prior_max_clicks,
    -- v27.46 A1: two-tier evidence-scaled allowance. DEEP (deepest same-family LOSS prior
    -- >= 40 clicks) keeps the original 0.5x half allowance - bit-identical caps to v27.43.
    -- THIN (15-39) gets the full 1.0x allowance. Rows with no LOSS prior default to the DEEP
    -- multiplier (their probe_cap is inert - only q_entry rows consume it) so their published
    -- column values do not move.
    CASE WHEN pr.prior_verdict = 'LOSS' AND pr.loss_prior_max_clicks < 40 THEN 'THIN'
         WHEN pr.prior_verdict = 'LOSS' THEN 'DEEP' END AS loss_evidence_tier,
    tc.tcpc AS tcpc_pre90,
    ROUND(IF(pr.prior_verdict = 'LOSS' AND pr.loss_prior_max_clicks < 40, 1.0, 0.5)
          * GREATEST(15 * COALESCE(tc.tcpc, band.med_cpc), 5.0), 2) AS probe_cap,
    -- gate predicates (raw, before precedence)
    (COALESCE(led.clicks, 0) >= 15 AND COALESCE(led.gp_roas, 0) >= 1.0) AS q_block_cut,
    (pr.prior_verdict = 'LOSS') AS q_entry,
    (COALESCE(led.clicks, 0) >= 15 AND COALESCE(led.net, 0) <= -25.0
     AND COALESCE(led.gp_roas, 0) < 0.6 AND cur.family != 'XMAS_PEAK') AS q_park_advisory
  FROM pop p
  CROSS JOIN cur CROSS JOIN anchor an CROSS JOIN band
  LEFT JOIN led    ON led.keyword_text = p.keyword_text
  LEFT JOIN led_ns ns ON ns.keyword_text = p.keyword_text
  LEFT JOIN r90    r  ON r.keyword_text = p.keyword_text
  LEFT JOIN prior pr ON pr.keyword_text = p.keyword_text
  LEFT JOIN tc    ON tc.keyword_text = p.keyword_text
),
staged AS (
  SELECT c.*,
    -- v27.42.1: q_entry is NULL (not FALSE) for keywords with no prior verdict at all;
    -- 'NOT NULL' is NULL, so those rows fell through to the PROBING/STOP labels with no
    -- memory behind them. Label must be NULL unless q_entry IS TRUE.
    -- v27.43 FIX A: evaluated on the NEAR-SETTLED numbers (ns_*), not the settled ledger — the
    -- allowance must see money that is already out the door. FIX B: a would-be STOP whose
    -- trailing-90d record is proven (>= 100c at >= 1.0x GP-ROAS) resolves to RELEASED instead.
    CASE WHEN c.q_entry IS NOT TRUE THEN NULL
         WHEN c.ns_spend >= c.probe_cap AND c.ns_gp >= c.ns_spend THEN 'RELEASED'
         WHEN c.ns_spend >= c.probe_cap AND c.q_hatch90 THEN 'RELEASED'  -- v27.43 FIX B hatch
         WHEN c.ns_spend >= c.probe_cap THEN 'STOP'
         ELSE 'PROBING' END AS entry_state,
    (c.q_entry IS TRUE AND c.ns_spend >= c.probe_cap
     AND c.ns_gp < c.ns_spend AND c.q_hatch90) AS released_by_90d,
    ROUND(GREATEST(c.probe_cap - c.ns_spend, 0), 2) AS remaining_allowance
  FROM calc c
)
SELECT
  s.keyword_text,
  CASE
    WHEN s.q_block_cut THEN 'BLOCK_CUT'
    WHEN s.q_entry AND s.entry_state != 'RELEASED' THEN 'ENTRY_BLOCK'
    WHEN s.q_park_advisory THEN 'PARK_CONTEXT'
    ELSE 'NONE'
  END AS gate_action,
  CASE
    WHEN s.q_block_cut THEN
      CONCAT('this context (', s.context_label, '): ', CAST(s.cur_clicks AS STRING), 'c at ',
             FORMAT('%.2f', COALESCE(s.cur_gp_roas, 0)), 'x settled (net ',
             IF(s.cur_net < 0, CONCAT('-$', FORMAT('%.2f', ABS(s.cur_net))), CONCAT('$', FORMAT('%.2f', s.cur_net))),
             ') — protect from cuts (bar 15c, GP-ROAS >= 1.0)')
    WHEN s.q_entry AND s.entry_state = 'STOP' THEN
      CONCAT('prior ', s.prior_label, ': LOSS (', CAST(s.prior_clicks AS STRING), 'c, net -$',
             FORMAT('%.2f', ABS(s.prior_net)), ', mature) — ',
             IF(s.loss_evidence_tier = 'THIN', 'full', 'half'), '-allowance re-probe $',
             FORMAT('%.2f', s.probe_cap), ' spent: $', FORMAT('%.2f', s.ns_spend), ' near-settled at ',
             FORMAT('%.2f', COALESCE(s.ns_gp_roas, 0)), 'x without paying back — stop funding this occurrence')
    WHEN s.q_entry AND s.entry_state = 'PROBING' THEN
      CONCAT('prior ', s.prior_label, ': LOSS (', CAST(s.prior_clicks AS STRING), 'c, net -$',
             FORMAT('%.2f', ABS(s.prior_net)), ', mature) — re-probe running: $',
             FORMAT('%.2f', s.ns_spend), ' of the $', FORMAT('%.2f', s.probe_cap), ' ',
             IF(s.loss_evidence_tier = 'THIN', 'full', 'half'),
             ' allowance spent (near-settled), $', FORMAT('%.2f', s.remaining_allowance),
             ' remaining')
    WHEN s.q_park_advisory THEN
      CONCAT('ADVISORY ONLY (calibration FAIL — must not act): this context (', s.context_label,
             '): ', CAST(s.cur_clicks AS STRING), 'c, net -$', FORMAT('%.2f', ABS(s.cur_net)),
             ' at ', FORMAT('%.2f', COALESCE(s.cur_gp_roas, 0)),
             'x settled — WOULD park to floor for the rest of the occurrence (flat $25 allowance + <0.6 co-gate)')
    -- v27.43 FIX B: hatch release — the 90d record outranks the occurrence-window read
    WHEN s.q_entry AND s.entry_state = 'RELEASED' AND s.released_by_90d THEN
      CONCAT('prior ', s.prior_label, ' LOSS re-probe hit its $', FORMAT('%.2f', s.probe_cap),
             ' cap — 90d: ', CAST(s.r90_clicks AS STRING), 'c at ',
             FORMAT('%.2f', COALESCE(s.r90_gp_roas, 0)), 'x - proven earner, released')
    WHEN s.q_entry AND s.entry_state = 'RELEASED' THEN
      CONCAT('prior ', s.prior_label, ' LOSS released — re-probe paid back: $',
             FORMAT('%.2f', s.ns_gp), ' GP on $', FORMAT('%.2f', s.ns_spend),
             ' near-settled spend this occurrence')
    ELSE CONCAT('no gate — ', s.context_label, ' settled record: ', CAST(s.cur_clicks AS STRING),
                'c, $', FORMAT('%.2f', s.cur_spend), ' spend')
  END AS gate_reason,
  s.entry_state,
  s.context_label, s.occurrence_key, s.occurrence_start, s.occurrence_end, s.settled_through,
  s.cur_clicks, s.cur_spend, s.cur_gross_profit, s.cur_net, s.cur_gp_roas, s.cur_orders,
  -- v27.43: near-settled occurrence record + remaining re-probe allowance (FIX A) and the
  -- trailing-90d hatch record (FIX B). Settled cur_* columns above are unchanged (BLOCK_CUT).
  s.near_settled_through, s.ns_clicks, s.ns_spend, s.ns_gp, s.ns_gp_roas,
  s.remaining_allowance,
  s.r90_clicks, s.r90_gp_roas, s.released_by_90d,
  s.prior_occurrence_key, s.prior_label, s.prior_verdict, s.prior_clicks, s.prior_net, s.prior_gp_roas,
  -- v27.46 A1: the two-tier allowance evidence, exposed for verification + the negate surface
  s.loss_prior_max_clicks, s.loss_evidence_tier,
  s.tcpc_pre90, s.probe_cap,
  s.q_park_advisory AS park_context_would_fire
FROM staged s;
