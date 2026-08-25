CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_FORECAST`
OPTIONS (description = "THE CATALOG'S ANSWER: the full chain at a price, and the price that maximises it. Forecast chain step 2 (spec docs/superpowers/specs/2026-08-25-catalog-forecast-chain-design.md, THREE_LAYERS.md 2.0.1). For one subject in one SEASON it publishes clicks -> orders -> cost -> ads net ROAS -> net ROAS -> contribution to family net profit, per DAY, at the CPC that maximises contribution; the caller multiplies by the length of the window it asked about. Season is the level, so a December question reads the HOLIDAY row and an August question the BACK_TO_SCHOOL row -- a year-long average would blend a 1.577 holiday into a 0.947 back-to-school and predict profit where there are losses. A GRID is published beside the maximum because the Brain's real question is often how much it loses by bidding less, and a flat peak and a sharp peak are different risks. THE OPTIMUM HAS A CLOSED FORM and the grid must agree with it: gross profit per click does not depend on price, so contribution is clicks0*(cpc/cpc0)^e*(A-cpc) with A the affordable CPC, maximised at A*e/(1+e) -- about 0.60*A on SB and 0.52*A on SP. Acceptance pins the grid against that identity, so a broken grid cannot quietly return a plausible price. THE CEILING IS THE HOUSE'S OWN affordable_cpc, not a new number: contribution per click is gp_per_click/keyword_bar - cpc, which is zero exactly at gp_per_click/keyword_bar, and that is how FACT_KEYWORD_STATE already defines affordable_cpc. The chain therefore reproduces house pricing rather than competing with it, and acceptance checks that it does. HALO IS CREDITED AT HALF, DELIBERATELY. gp_per_click is raw; the halo enters through keyword_bar = 1/(1+0.5*(halo_factor-1)), which credits half the lift. The spec's literal chain (gp*halo - cost) credits it all, and the gap is material -- on Bottle, full credit values a keyword 27% above what the bar permits. Optimising on full credit would make the Catalog recommend prices the house's own pricing rule forbids, so the OPTIMUM is computed at half credit and the full-halo figures are published beside it for comparison, pending a ruling. THE GRID IS BOUNDED BY EVIDENCE. The response curve is a power law: at 3x baseline it claims 3^1.49 = 5.3x the clicks, which is extrapolation, not measurement. Measured, the median keyword has never been priced above 1.36x its current baseline and only 39% have ever seen 1.5x, so the grid stops at the highest CPC that keyword has actually been priced at, and best_cpc_at_grid_edge flags every answer where the true optimum may lie beyond the evidence. WHAT IT ASSUMES AND DISCLOSES: that marginal clicks convert as well as average clicks. Bidding up buys weaker placements and queries, so this biases the optimum UP; it is stated here because it cannot be measured from what the account records. BASIS IS NEVER BLANK -- DATA for a subject's own settled rates, FLOW:<node> when a customer purchase flow answers for it, UNKNOWN publishing NULLs and never numbers. Decides nothing and moves no bid.")
AS
WITH k AS (
  SELECT 7     AS min_orders_own,     -- below this a subject's own CVR is dice (spec 6: +/-1 sale)
         100.0 AS cvr_prior_clicks,   -- DECLARED, UNTESTED: the k in the 4.1 shrinkage. See header.
         0.01  AS grid_step,
         365   AS lookback_days
),
-- SEASON IS DERIVED THE SAME WAY THE FLOW TREE DERIVES IT. If these two definitions ever drift, a
-- subject would be forecast in one season and its flow learned in another, silently.
season_def AS (
  SELECT * FROM UNNEST([
    STRUCT('HOLIDAY' AS season, [11,12] AS months),
    STRUCT('BACK_TO_SCHOOL',    [8,9]),
    STRUCT('POST_HOLIDAY',      [1,2]),
    STRUCT('OFF_SEASON',        [3,4,5,6,7,10])])
),
ks AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         CAST(keyword_id  AS STRING) AS keyword_id,
         LOWER(TRIM(target_text)) AS targeting,
         target_text AS target_text_raw, campaign_name, family, channel, match_type, state,
         settled_clk90, settled_ord90, settled_gp90,
         gp_per_click, affordable_cpc, family_bar, m_effective, bid_floor,
         SAFE_DIVIDE(settled_ord90, NULLIF(settled_clk90, 0)) AS own_cvr,
         SAFE_DIVIDE(settled_gp90,  NULLIF(settled_ord90, 0)) AS own_gp_per_order
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
-- HALO JOINS ON FAMILY, NOT ON CAMPAIGN. Measured: T_FAMILY_BAR is one row per (campaign_id, family)
-- with halo constant inside a family, so a family join cannot fan out and it also covers subjects
-- whose campaign is absent from the table.
-- ONE HALO CREDIT, SHARED, NOT A SECOND COPY OF THE RULE. The Catalog does not re-derive how much
-- of the halo to credit; it divides by the SAME keyword_bar the engine judges against, so the two
-- layers cannot be spending against different definitions of money. halo_credit is carried through
-- purely so acceptance can prove the agreement rather than assume it -- the failure this guards is
-- a future edit that reaches for halo_factor directly and quietly re-credits at 1.0.
halo AS (
  SELECT family, ANY_VALUE(halo_factor) AS halo_factor, ANY_VALUE(keyword_bar) AS keyword_bar,
         ANY_VALUE(halo_credit) AS halo_credit
  FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY family
),
curve AS (
  SELECT campaign_id, targeting, baseline_cpc, baseline_clicks_per_day, elasticity, elasticity_basis
  FROM `onyga-482313.OI.V_CPC_RESPONSE`
  WHERE elasticity IS NOT NULL AND baseline_cpc > 0 AND baseline_clicks_per_day > 0
),
-- THE EVIDENCE BOUND. The highest price this keyword has actually been priced at over the lookback;
-- the grid stops here rather than extrapolating a power law past anything ever observed.
priced AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, LOWER(TRIM(targeting)) AS targeting,
         MAX(wk_cpc) AS max_priced_cpc, MIN(wk_cpc) AS min_priced_cpc
  FROM (
    SELECT campaign_id, targeting,
           SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks), 0)) AS wk_cpc
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`, k
    WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL k.lookback_days DAY)
      AND targeting IS NOT NULL
    GROUP BY campaign_id, targeting, DATE_TRUNC(date, WEEK(SUNDAY))
    HAVING SUM(Ads_clicks) >= 2 AND SUM(Ads_cost) > 0)
  GROUP BY 1, 2
),
-- THE CLICKS LEG MUST SIT IN THE SAME SEASON AS THE MONEY LEG. Without this the HOLIDAY row would
-- carry December conversion rates on August traffic -- the two legs describing different months
-- inside one answer. Measured, 157 live subjects have real November-December history carrying
-- 197,521 clicks (more than back-to-school), so for those the December question is answered with
-- December evidence rather than seasonally translated.
-- The denominator is every calendar day of that season PRESENT IN THE DATA, so the rate reads
-- "clicks per day across the Novembers and Decembers we have", not "per day it happened to run".
season_days AS (
  SELECT season, COUNT(DISTINCT date) AS days
  FROM (
    SELECT date,
           CASE WHEN EXTRACT(MONTH FROM date) IN (11,12) THEN 'HOLIDAY'
                WHEN EXTRACT(MONTH FROM date) IN (8,9)   THEN 'BACK_TO_SCHOOL'
                WHEN EXTRACT(MONTH FROM date) IN (1,2)   THEN 'POST_HOLIDAY'
                ELSE 'OFF_SEASON' END AS season
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`)
  GROUP BY season
),
season_kw AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, LOWER(TRIM(a.targeting)) AS targeting,
         CASE WHEN EXTRACT(MONTH FROM a.date) IN (11,12) THEN 'HOLIDAY'
              WHEN EXTRACT(MONTH FROM a.date) IN (8,9)   THEN 'BACK_TO_SCHOOL'
              WHEN EXTRACT(MONTH FROM a.date) IN (1,2)   THEN 'POST_HOLIDAY'
              ELSE 'OFF_SEASON' END AS season,
         SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_cost) AS cost,
         COUNT(DISTINCT a.date) AS active_days
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.targeting IS NOT NULL
  GROUP BY 1, 2, 3
  HAVING SUM(a.Ads_clicks) >= 5 AND SUM(a.Ads_cost) > 0
),
season_base AS (
  SELECT k.campaign_id, k.targeting, k.season,
         SAFE_DIVIDE(k.clicks, d.days)          AS season_clicks_per_day,
         SAFE_DIVIDE(k.cost, NULLIF(k.clicks,0)) AS season_cpc,
         k.clicks AS season_clicks, k.active_days AS season_active_days, d.days AS season_calendar_days
  FROM season_kw k JOIN season_days d USING (season)
),
flow AS (
  SELECT CAST(n.campaign_id AS STRING) AS campaign_id, CAST(n.keyword_id AS STRING) AS keyword_id,
         n.season, n.node_id, n.depth,
         f.flow_cvr, f.flow_gp_per_order, f.members AS flow_members, f.clicks AS flow_clicks,
         f.split_dim, f.split_value
  FROM `onyga-482313.OI.T_SUBJECT_FLOW_NODE` n
  JOIN `onyga-482313.OI.T_CUSTOMER_PURCHASE_FLOW` f USING (node_id)
),
subject_season AS (
  SELECT ks.*, sd.season,
         c.elasticity, c.elasticity_basis,
         -- Season evidence first; the recent settled window only when the season has none.
         COALESCE(sb.season_cpc, c.baseline_cpc) AS baseline_cpc,
         COALESCE(sb.season_clicks_per_day, c.baseline_clicks_per_day) AS baseline_clicks_per_day,
         sb.season_clicks, sb.season_active_days, sb.season_calendar_days,
         CASE WHEN sb.season_clicks_per_day IS NOT NULL
                THEN CONCAT('DATA: ', CAST(sb.season_clicks AS STRING), ' clicks over ',
                            CAST(sb.season_calendar_days AS STRING), ' days of ', sd.season)
              WHEN c.baseline_clicks_per_day IS NOT NULL
                THEN 'CARRIED: no history in this season, using the recent settled window'
              ELSE 'UNKNOWN: no click history' END AS clicks_basis,
         p.max_priced_cpc, p.min_priced_cpc,
         h.halo_factor, h.keyword_bar, h.halo_credit,
         fl.node_id, fl.depth AS flow_depth, fl.flow_cvr, fl.flow_gp_per_order,
         fl.flow_members, fl.split_dim, fl.split_value
  FROM ks
  CROSS JOIN (SELECT season FROM season_def) sd
  LEFT JOIN curve c ON c.campaign_id = ks.campaign_id AND c.targeting = ks.targeting
  LEFT JOIN season_base sb ON sb.campaign_id = ks.campaign_id AND sb.targeting = ks.targeting
                          AND sb.season = sd.season
  LEFT JOIN priced p ON p.campaign_id = ks.campaign_id AND p.targeting = ks.targeting
  LEFT JOIN halo h ON h.family = ks.family
  LEFT JOIN flow fl ON fl.campaign_id = ks.campaign_id AND fl.keyword_id = ks.keyword_id
                   AND fl.season = sd.season
),
-- THE TWO MODELLED LINKS. Everything after this is arithmetic, which is the point of a chain:
-- when the money is wrong, only CVR or GP-per-order can be the culprit.
links AS (
  SELECT s.*,
         -- 4.1 shrinkage: the subject's own rate pulled toward its flow's by evidence. A subject
         -- with no clicks reads exactly its flow; one with many reads itself.
         CASE
           WHEN s.flow_cvr IS NOT NULL AND s.settled_clk90 > 0
             THEN SAFE_DIVIDE((SELECT cvr_prior_clicks FROM k) * s.flow_cvr
                              + s.settled_clk90 * s.own_cvr,
                              (SELECT cvr_prior_clicks FROM k) + s.settled_clk90)
           WHEN s.settled_ord90 >= (SELECT min_orders_own FROM k) THEN s.own_cvr
           WHEN s.flow_cvr IS NOT NULL THEN s.flow_cvr
           ELSE NULL END AS cvr_used,
         CASE
           WHEN s.settled_ord90 >= (SELECT min_orders_own FROM k) THEN s.own_gp_per_order
           WHEN s.flow_gp_per_order IS NOT NULL THEN s.flow_gp_per_order
           ELSE NULL END AS gp_per_order_used,
         CASE
           WHEN s.settled_ord90 >= (SELECT min_orders_own FROM k) AND s.flow_cvr IS NOT NULL
             THEN CONCAT('DATA: own settled rates, blended with FLOW:', CAST(s.node_id AS STRING))
           WHEN s.settled_ord90 >= (SELECT min_orders_own FROM k) THEN 'DATA: own settled rates'
           WHEN s.flow_cvr IS NOT NULL
             THEN CONCAT('FLOW:', CAST(s.node_id AS STRING), ' (', IFNULL(s.split_dim,'root'), '=',
                         IFNULL(CAST(s.split_value AS STRING),'all'), ', ',
                         CAST(s.flow_members AS STRING), ' members)')
           ELSE 'UNKNOWN: no settled orders and no flow for this season' END AS rate_basis
  FROM subject_season s
),
econ AS (
  SELECT l.*,
         l.cvr_used * l.gp_per_order_used AS gp_per_click_modelled,
         -- The ceiling: contribution per click is gp_per_click/keyword_bar - cpc, zero exactly at
         -- gp_per_click/keyword_bar. That IS the house's affordable_cpc, by construction.
         SAFE_DIVIDE(l.cvr_used * l.gp_per_order_used, NULLIF(l.keyword_bar, 0)) AS ceiling_cpc,
         -- Closed form: contribution peaks at ceiling * e/(1+e). The grid must agree.
         SAFE_DIVIDE(l.cvr_used * l.gp_per_order_used, NULLIF(l.keyword_bar, 0))
           * SAFE_DIVIDE(l.elasticity, 1 + l.elasticity) AS best_cpc_closed_form
  FROM links l
),
bounds AS (
  SELECT e.*,
         GREATEST(IFNULL(e.bid_floor, 0.02), 0.02) AS grid_lo,
         -- Evidence bound. Never above the highest price actually paid for this keyword.
         GREATEST(GREATEST(IFNULL(e.bid_floor, 0.02), 0.02),
                  IFNULL(e.max_priced_cpc, e.baseline_cpc)) AS grid_hi
  FROM econ e
),
grid AS (
  SELECT b.*,
         -- CONTRIBUTION IS KEPT UNROUNDED FOR THE COMPARISON THAT PICKS THE WINNER. Rounding it
         -- here to 4 places made many points around a flat peak compare EQUAL, and the tie-break
         -- (cpc ASC) then handed the answer to the cheapest tied price every time -- a silent,
         -- systematically low recommendation on 60 subjects. Display rounding happens on output.
         -- cpc is rounded first and then used, so every published number is consistent with the
         -- published price rather than with an unrounded one behind it.
         ARRAY(
           SELECT AS STRUCT
             ROUND(cpc, 4) AS cpc,
             b.baseline_clicks_per_day * POW(ROUND(cpc, 4) / b.baseline_cpc, b.elasticity)
               AS clicks_per_day,
             b.baseline_clicks_per_day * POW(ROUND(cpc, 4) / b.baseline_cpc, b.elasticity)
                   * (SAFE_DIVIDE(b.gp_per_click_modelled, NULLIF(b.keyword_bar,0)) - ROUND(cpc, 4))
               AS contribution_per_day
           FROM UNNEST(GENERATE_ARRAY(b.grid_lo, b.grid_hi, (SELECT grid_step FROM k))) AS cpc
         ) AS curve_points
  FROM bounds b
  WHERE b.elasticity IS NOT NULL AND b.gp_per_click_modelled IS NOT NULL
    AND b.baseline_cpc > 0 AND b.grid_hi >= b.grid_lo
    -- HALO MUST BE PRESENT AND SANE, AND IS NEVER DEFAULTED TO 1.0. Without keyword_bar every
    -- contribution in the grid is NULL, and the "best" point would then be chosen by ORDER BY over
    -- a column that is NULL everywhere -- an arbitrary price published as a recommendation. A
    -- missing halo is a reason to say nothing, not a reason to assume no halo exists.
    AND b.keyword_bar IS NOT NULL AND b.keyword_bar > 0
    AND b.halo_factor IS NOT NULL AND b.halo_factor > 0
),
picked AS (
  SELECT g.*,
         (SELECT AS STRUCT cpc, clicks_per_day, contribution_per_day
          FROM UNNEST(g.curve_points) ORDER BY contribution_per_day DESC, cpc ASC LIMIT 1) AS best
  FROM grid g
)
SELECT
  campaign_id, keyword_id, target_text_raw AS target_text, campaign_name, family, channel,
  match_type, state, season,

  -- the answer
  ROUND(best.cpc, 4)                                              AS best_cpc,
  ROUND(best.clicks_per_day, 3)                                   AS clicks_per_day,
  ROUND(best.clicks_per_day * cvr_used, 4)                        AS orders_per_day,
  ROUND(best.clicks_per_day * best.cpc, 4)                        AS cost_per_day,
  ROUND(best.clicks_per_day * cvr_used * gp_per_order_used, 4)    AS gross_profit_per_day,
  ROUND(SAFE_DIVIDE(cvr_used * gp_per_order_used, NULLIF(best.cpc, 0)), 4) AS ads_net_roas,
  ROUND(SAFE_DIVIDE(cvr_used * gp_per_order_used * halo_factor, NULLIF(best.cpc, 0)), 4) AS net_roas,
  ROUND(best.contribution_per_day, 4)                             AS contribution_per_day,

  -- the same answer at FULL halo credit, for comparison only (see header: the optimum is half credit)
  ROUND(best.clicks_per_day * (cvr_used * gp_per_order_used * halo_factor - best.cpc), 4)
                                                                  AS contribution_per_day_full_halo,

  -- the shape around the answer
  ROUND(ceiling_cpc, 4)                                           AS ceiling_cpc,
  ROUND(best_cpc_closed_form, 4)                                  AS best_cpc_closed_form,
  ROUND(grid_lo, 4) AS grid_lo, ROUND(grid_hi, 4) AS grid_hi,
  -- COMPARED TO THE LAST GRID POINT, NOT TO grid_hi. GENERATE_ARRAY stops short of the bound
  -- whenever the span is not a whole number of steps -- measured, about two thirds of a cent -- so
  -- a test against grid_hi silently cleared 65 of 67 answers that were in fact sitting on the edge.
  -- The distinction matters to the Brain: "this is the best price" and "this is as far as the
  -- evidence goes, and the optimum is beyond it" are different statements.
  best.cpc >= (SELECT MAX(cpc) FROM UNNEST(curve_points)) - 0.0001 AS best_cpc_at_grid_edge,
  -- The mirror case, and it is a finding rather than a nuisance: the profit-maximising price is
  -- BELOW the platform minimum, so this subject is not worth even its floor price.
  best_cpc_closed_form < grid_lo                                  AS optimum_below_floor,
  ARRAY(SELECT AS STRUCT cpc, ROUND(clicks_per_day, 4) AS clicks_per_day,
               ROUND(contribution_per_day, 4) AS contribution_per_day
        FROM UNNEST(curve_points)) AS curve_points,

  -- the links, published so a wrong answer names its own fault
  ROUND(cvr_used, 6)          AS cvr_used,
  ROUND(gp_per_order_used, 4) AS gp_per_order_used,
  ROUND(gp_per_click_modelled, 4) AS gp_per_click_modelled,
  ROUND(elasticity, 3)        AS elasticity,
  ROUND(baseline_cpc, 4)      AS baseline_cpc,
  ROUND(baseline_clicks_per_day, 3) AS baseline_clicks_per_day,
  clicks_basis, season_clicks, season_active_days, season_calendar_days,
  ROUND(halo_factor, 4)       AS halo_factor,
  ROUND(keyword_bar, 4)       AS keyword_bar,
  halo_credit,
  settled_clk90, settled_ord90,
  ROUND(affordable_cpc, 4)    AS house_affordable_cpc,   -- the ceiling this chain must reproduce
  node_id AS flow_node_id, flow_depth, flow_members,

  -- disclosure
  rate_basis, elasticity_basis,
  CONCAT('At $', CAST(ROUND(best.cpc, 2) AS STRING), ' this buys ',
         CAST(ROUND(best.clicks_per_day, 1) AS STRING), ' clicks and ',
         CAST(ROUND(best.clicks_per_day * cvr_used, 2) AS STRING), ' orders a day, costs $',
         CAST(ROUND(best.clicks_per_day * best.cpc, 2) AS STRING), ', returns ',
         CAST(ROUND(SAFE_DIVIDE(cvr_used * gp_per_order_used, NULLIF(best.cpc,0)), 2) AS STRING),
         'x on ad spend, and contributes $',
         CAST(ROUND(best.contribution_per_day, 2) AS STRING), ' a day to ', family,
         ' in ', season, '. Basis: ', rate_basis, '.') AS sentence
FROM picked;
