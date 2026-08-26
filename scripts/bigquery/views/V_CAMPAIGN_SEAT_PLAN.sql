CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_SEAT_PLAN`
OPTIONS (description = "HOW MANY SEATS EACH CAMPAIGN GETS, AND WHAT THEY ARE FOR. Brain-layer rule, ruled by Ori 2026-08-25. ALLOWANCE IS EARNED, NOT GRANTED: a campaign clearing its family bar earns an allowance of 20% of its daily budget and spends it on UNPROFITABLE keywords at one seat per 7 dollars; a campaign BELOW its bar earns no allowance at all and gets exactly ONE seat, aimed at its MOST PROFITABLE keyword, with the bid free to move either way toward the campaign's break-even. That inversion is the point and it is new: every seat in the plan today goes to a not-good candidate, so there was no way to mend a campaign by leaning on the thing that already works. It follows Ori's earlier ruling that an unprofitable campaign is MENDED before it is GROWN. WHY THIS DOES NOT CONTRADICT THE FAMILY ALLOWANCE: the 80/20 doctrine sizes a FAMILY'S pot in dollars; this sizes a CAMPAIGN'S seat COUNT. They bind in different dimensions, so a plan must satisfy both -- the family pot still caps the money, and this caps how thinly one campaign may spread it. A campaign on 10 dollars a day carrying four keywords under repair cannot buy any of them enough clicks to reach a verdict, which is the failure this rule exists to stop. PROFITABILITY IS MEASURED AT THE BAR, NOT AT 1.0: the bar already credits the family halo at the house rate, so judging against 1.0 would hold campaigns to a stricter test than the engine's own. The window is the settled 28 days, so a campaign is not judged on sales that have not landed. THE REPAIR SEAT'S TARGET is the keyword's own affordable CPC -- gross profit per click over the bar -- which is the price at which it contributes nothing; the direction is RAISE when it is paying under that and LOWER when over. The size of the move is NOT decided here: Pacing owns how fast a price walks. DECIDES NOTHING AND MOVES NO BID -- it publishes seat entitlement, and the plan builder is what would consume it. Read by nothing yet.")
AS
WITH k AS (
  SELECT 0.20 AS allowance_share,   -- Ori: "20% of budget is allowance"
         7.0  AS dollars_per_seat,  -- Ori: "each 7 dollars is a seat"
         28   AS window_days,
         7    AS settle_days
),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- The campaign's own economics over the SETTLED window. Judging on unsettled days would mark a
-- campaign unprofitable for sales that simply have not been attributed yet.
econ AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
         SUM(a.Ads_cost) AS cost, SUM(a.GROSS_PROFIT) AS gross_profit,
         SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_orders) AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm, k
  WHERE a.date <= DATE_SUB(wm.watermark, INTERVAL k.settle_days DAY)
    AND a.date >  DATE_SUB(wm.watermark, INTERVAL k.settle_days + k.window_days DAY)
  GROUP BY 1
),
bar AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, ANY_VALUE(family) AS family,
         ANY_VALUE(keyword_bar) AS keyword_bar, ANY_VALUE(halo_factor) AS halo_factor,
         ANY_VALUE(bar_exempt) AS bar_exempt
  FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1
),
bud AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         ANY_VALUE(campaign_name) AS campaign_name,
         ANY_VALUE(campaign_current_budget) AS budget
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
    AND campaign_current_budget IS NOT NULL
  GROUP BY 1
),
c AS (
  SELECT b.campaign_id, bud.campaign_name, b.family, bud.budget,
         b.keyword_bar, b.halo_factor, b.bar_exempt,
         e.cost, e.gross_profit, e.clicks, e.orders,
         SAFE_DIVIDE(e.gross_profit, NULLIF(e.cost, 0)) AS ads_net_roas
  FROM bar b JOIN bud USING (campaign_id) LEFT JOIN econ e USING (campaign_id)
),
graded AS (
  SELECT c.*,
         -- A campaign with no settled spend has not been measured; it is not "unprofitable", and
         -- calling it so would hand it a repair seat on evidence that does not exist.
         CASE WHEN c.cost IS NULL OR c.cost = 0 THEN NULL
              ELSE c.ads_net_roas >= c.keyword_bar END AS profitable
  FROM c
),
sized AS (
  SELECT g.*,
         IF(g.profitable, g.budget * (SELECT allowance_share FROM k), 0.0) AS allowance_per_day,
         CASE
           WHEN g.profitable IS NULL THEN 0
           WHEN g.profitable THEN CAST(FLOOR(g.budget * (SELECT allowance_share FROM k)
                                            / (SELECT dollars_per_seat FROM k)) AS INT64)
           ELSE 1
         END AS seats_allowed,
         CASE WHEN g.profitable IS NULL THEN 'UNMEASURED'
              WHEN g.profitable THEN 'EXPERIMENT'
              ELSE 'REPAIR' END AS seat_purpose
  FROM graded g
),
-- For a REPAIR campaign, which keyword the single seat is aimed at: the one earning most per
-- click. Ranked on gross profit per click rather than total, because the seat prices ONE keyword
-- and the question is what a click there is worth, not how many clicks it happens to take.
best_kw AS (
  SELECT r.campaign_id, r.keyword_id, r.target_text, r.gp_per_click, r.weighted_orders,
         SAFE_DIVIDE(r.gp_per_click, NULLIF(b.keyword_bar, 0)) AS affordable_cpc,
         ks.current_bid,
         -- EVIDENCE FIRST, THEN EARNINGS. Ranking on gross profit per click alone handed the
         -- seat to keywords resting on one or two lucky orders: measured, 6 of 29 repair keywords
         -- had 1-2 weighted orders and the worst target came out at 16.5x its current bid. A
         -- keyword with real evidence outranks a richer-looking one without it.
         ROW_NUMBER() OVER (PARTITION BY r.campaign_id
                            ORDER BY (r.weighted_orders >= 3) DESC,
                                     r.gp_per_click DESC, r.weighted_orders DESC) AS rn
  FROM `onyga-482313.OI.V_KEYWORD_RATES` r
  JOIN bar b USING (campaign_id)
  LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
                    ANY_VALUE(current_bid) current_bid
             FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
             WHERE snapshot_date=(SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
             GROUP BY 1,2) ks
    ON ks.cid = r.campaign_id AND ks.kid = r.keyword_id
  WHERE r.gp_per_click > 0 AND r.weighted_orders > 0
)
SELECT
  s.campaign_id, s.campaign_name, s.family,
  ROUND(s.budget, 2) AS budget_per_day,
  ROUND(s.cost, 2) AS settled_cost, ROUND(s.gross_profit, 2) AS settled_gross_profit,
  ROUND(s.ads_net_roas, 4) AS ads_net_roas, ROUND(s.keyword_bar, 4) AS bar,
  s.profitable, s.bar_exempt,
  ROUND(s.allowance_per_day, 2) AS allowance_per_day,
  s.seats_allowed, s.seat_purpose,

  -- the repair seat's subject and its target price (only meaningful when seat_purpose = REPAIR)
  IF(s.seat_purpose = 'REPAIR', bk.keyword_id,    NULL) AS repair_keyword_id,
  IF(s.seat_purpose = 'REPAIR', bk.target_text,   NULL) AS repair_target_text,
  IF(s.seat_purpose = 'REPAIR', ROUND(bk.gp_per_click, 4),   NULL) AS repair_gp_per_click,
  IF(s.seat_purpose = 'REPAIR', ROUND(bk.current_bid, 4),    NULL) AS repair_current_bid,
  -- The uncapped truth, and the price the seat is actually allowed to walk toward.
  IF(s.seat_purpose = 'REPAIR', ROUND(bk.affordable_cpc, 4), NULL) AS repair_affordable_cpc,
  IF(s.seat_purpose = 'REPAIR', bk.weighted_orders, NULL) AS repair_evidence_orders,
  -- A SINGLE SEAT NUDGES, IT DOES NOT LEAP. Ori's ruling is that an unprofitable campaign is
  -- mended SLOWLY, and an affordable CPC computed off one order is not a target, it is an
  -- artefact. The walk is bounded to half and double the current bid; Pacing still owns the step.
  IF(s.seat_purpose = 'REPAIR',
     ROUND(LEAST(GREATEST(bk.affordable_cpc, bk.current_bid * 0.5), bk.current_bid * 2.0), 4),
     NULL) AS repair_target_cpc,
  IF(s.seat_purpose = 'REPAIR',
     bk.affordable_cpc > bk.current_bid * 2.0 OR bk.affordable_cpc < bk.current_bid * 0.5,
     NULL) AS repair_target_capped,
  CASE WHEN s.seat_purpose <> 'REPAIR' OR bk.affordable_cpc IS NULL OR bk.current_bid IS NULL
         THEN NULL
       WHEN bk.affordable_cpc > bk.current_bid THEN 'RAISE'
       WHEN bk.affordable_cpc < bk.current_bid THEN 'LOWER'
       ELSE 'HOLD' END AS repair_direction,

  CASE
    WHEN s.seat_purpose = 'UNMEASURED' THEN CONCAT(
      s.campaign_name, ' spent nothing in the settled window, so it is not judged and takes no seat.')
    WHEN s.seat_purpose = 'EXPERIMENT' THEN CONCAT(
      s.campaign_name, ' clears its bar (', CAST(ROUND(s.ads_net_roas,2) AS STRING), ' vs ',
      CAST(ROUND(s.keyword_bar,2) AS STRING), '), so it earns $',
      CAST(ROUND(s.allowance_per_day,2) AS STRING), ' a day of allowance — ',
      CAST(s.seats_allowed AS STRING), ' seat(s) at $7 for keywords being repaired.')
    ELSE CONCAT(
      s.campaign_name, ' is under its bar (', CAST(ROUND(s.ads_net_roas,2) AS STRING), ' vs ',
      CAST(ROUND(s.keyword_bar,2) AS STRING), '), so it earns no allowance and gets ONE seat: ',
      IFNULL(CONCAT('lean on ', bk.target_text, ' — ', 
                    CASE WHEN bk.affordable_cpc > bk.current_bid THEN 'raise' ELSE 'lower' END,
                    ' from $', CAST(ROUND(bk.current_bid,2) AS STRING), ' toward $',
                    CAST(ROUND(bk.affordable_cpc,2) AS STRING)),
             'no keyword in it earns anything per click yet'), '.')
  END AS sentence
FROM sized s
LEFT JOIN best_kw bk ON bk.campaign_id = s.campaign_id AND bk.rn = 1;
