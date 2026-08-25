CREATE OR REPLACE VIEW `onyga-482313.OI.V_CUSTOMER_PURCHASE_FLOW`
OPTIONS (description = "CUSTOMER PURCHASE FLOWS, TEN NESTED LEVELS — THREE_LAYERS.md §2.0.2/§2.0.3 (Ori, 2026-08-25: 'flow should have 10 levels between 1 level (generic) and 10 levels (detailed)... 1 level should return a generic result to any keyword'). ONE ROW PER (level, flow_key), each carrying its learned profile ON EACH LINK OF THE CHAIN SEPARATELY — CPC, CVR, gross profit per order, clicks per active day — because the purpose is to SPLIT the forecast and see which link is wrong; a flow publishing only a blended contribution could never name the broken link. Level 1 is universal, so every subject always has an answer. Learned over 365 days from members carrying at least min_member_clicks: a subject with 3 clicks in a year belongs to the flow but must not shape it. PUBLISHES ITS OWN SPREAD (cvr_dispersion) so a caller sees whether a flow is a tight pattern or a label over a crowd, and SHOULD_SPLIT flags a flow that has plenty of clicks yet stays dispersed — Ori's rule that a flow which is inaccurate WITH enough evidence needs splitting further. is_usable is FALSE below a declared minimum member count. NOTHING READS IT YET and it decides nothing. Acceptance: scripts/bigquery/tests/CUSTOMER_PURCHASE_FLOW_acceptance.sql.")
AS
WITH k AS (
  SELECT 365  AS window_days,       -- §2.0.2: a year spans a full seasonal cycle
         3    AS min_members,       -- fewer than this is one subject wearing a general name
         30   AS min_member_clicks, -- below this a member teaches the flow nothing
         500  AS split_min_clicks,  -- "enough clicks" for Ori's split rule
         0.60 AS split_dispersion   -- above this the flow is a label over a crowd
),
wm AS (SELECT MAX(date) AS w FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

member_daily AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, LOWER(TRIM(a.targeting)) AS target_text,
         a.date, SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_cost) AS cost,
         SUM(a.Ads_orders) AS orders, SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm CROSS JOIN k
  WHERE a.date BETWEEN DATE_SUB(wm.w, INTERVAL k.window_days - 1 DAY) AND wm.w
    AND a.campaign_id IS NOT NULL
  GROUP BY 1,2,3 HAVING SUM(a.Ads_clicks) > 0
),
-- every subject's own record, once, before it is spread across the ten levels it belongs to
member AS (
  SELECT s.campaign_id, s.keyword_id, s.flow_ladder,
         COUNT(*) AS days_with_clicks,
         SUM(d.clicks) AS clicks, SUM(d.orders) AS orders, SUM(d.cost) AS cost, SUM(d.gp) AS gp,
         SAFE_DIVIDE(SUM(d.orders), NULLIF(SUM(d.clicks),0)) AS cvr,
         SAFE_DIVIDE(SUM(d.clicks), COUNT(*))                AS clicks_per_active_day,
         MAX(SAFE_DIVIDE(d.cost, NULLIF(d.clicks,0)))
           - MIN(SAFE_DIVIDE(d.cost, NULLIF(d.clicks,0)))    AS cpc_spread
  FROM `onyga-482313.OI.T_SUBJECT_FLOW` s
  JOIN member_daily d ON d.campaign_id = s.campaign_id AND d.target_text = s.target_text
  GROUP BY 1,2,3
),
-- ONE ROW PER (member, level). A member of a level-7 flow is necessarily a member of its level-6
-- parent, so the same record teaches every level it belongs to — which is what makes the levels
-- nest and lets a caller step up the ladder when the deep flow is too thin.
exploded AS (
  SELECT l.level, l.flow_key, l.adds, m.*
  FROM member m, UNNEST(m.flow_ladder) l
  WHERE l.flow_key IS NOT NULL
),
teaching AS (SELECT e.* FROM exploded e CROSS JOIN k WHERE e.clicks >= k.min_member_clicks),

totals AS (
  SELECT level, flow_key, COUNT(*) AS members_total
  FROM exploded GROUP BY 1,2
)
SELECT
  t.level, t.flow_key, ANY_VALUE(t.adds) AS level_adds,
  COUNT(*)                          AS members_teaching,
  ANY_VALUE(tot.members_total)      AS members_total,
  SUM(t.clicks)                     AS clicks,
  SUM(t.orders)                     AS orders,
  ROUND(SUM(t.cost), 2)             AS cost,

  -- THE PROFILE, ONE FIGURE PER LINK. Split on purpose (Ori: "split the forecast in order to
  -- understand what is working good and what is not").
  ROUND(SAFE_DIVIDE(SUM(t.cost),   NULLIF(SUM(t.clicks),0)), 4) AS flow_cpc,
  ROUND(SAFE_DIVIDE(SUM(t.orders), NULLIF(SUM(t.clicks),0)), 5) AS flow_cvr,
  ROUND(SAFE_DIVIDE(SUM(t.gp),     NULLIF(SUM(t.orders),0)), 4) AS flow_gp_per_order,
  ROUND(AVG(t.clicks_per_active_day), 3)                        AS flow_clicks_per_active_day,
  ROUND(SAFE_DIVIDE(SUM(t.gp),     NULLIF(SUM(t.cost),0)), 4)   AS flow_gp_roas,

  ROUND(SAFE_DIVIDE(STDDEV(t.cvr), NULLIF(AVG(t.cvr),0)), 3)    AS cvr_dispersion,
  COUNTIF(t.days_with_clicks >= 30 AND t.cpc_spread >= 0.20)    AS members_fittable,

  (COUNT(*) >= (SELECT min_members FROM k))                     AS is_usable,
  CASE WHEN COUNT(*) < (SELECT min_members FROM k)
       THEN FORMAT('learned from only %d member(s), below the declared minimum of %d — one subject wearing a general name rather than a pattern',
                   COUNT(*), (SELECT min_members FROM k))
       ELSE NULL END                                            AS not_usable_because,

  -- ORI'S SPLIT RULE: enough clicks to have been learnable, yet still dispersed. That combination
  -- means the flow is too COARSE — not that the data is thin — so the answer is a further split
  -- rather than more patience. A dispersed flow with few clicks is simply unproven and is left alone.
  (SUM(t.clicks) >= (SELECT split_min_clicks FROM k)
     AND SAFE_DIVIDE(STDDEV(t.cvr), NULLIF(AVG(t.cvr),0)) > (SELECT split_dispersion FROM k))
                                                                AS should_split,
  CASE WHEN SUM(t.clicks) >= (SELECT split_min_clicks FROM k)
             AND SAFE_DIVIDE(STDDEV(t.cvr), NULLIF(AVG(t.cvr),0)) > (SELECT split_dispersion FROM k)
       THEN FORMAT('%d clicks is enough evidence, yet members still scatter %.0f%% around the CVR of this flow — it is too coarse, so go one level deeper rather than wait for more data',
                   SUM(t.clicks),
                   100 * SAFE_DIVIDE(STDDEV(t.cvr), NULLIF(AVG(t.cvr),0)))
       ELSE NULL END                                            AS should_split_because,

  (SELECT window_days FROM k) AS window_days,
  (SELECT w FROM wm)          AS as_of
FROM teaching t
JOIN totals tot ON tot.level = t.level AND tot.flow_key = t.flow_key
GROUP BY t.level, t.flow_key
ORDER BY t.level, clicks DESC;
