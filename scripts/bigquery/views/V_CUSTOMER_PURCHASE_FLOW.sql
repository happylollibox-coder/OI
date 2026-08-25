CREATE OR REPLACE VIEW `onyga-482313.OI.V_CUSTOMER_PURCHASE_FLOW`
OPTIONS (description = "CUSTOMER PURCHASE FLOWS — THREE_LAYERS.md §2.0.2, ruled by Ori 2026-08-25: 'the catalog should create assumptions based on other changes it created... so when there is no data you can use a customer purchase flow you know is working in order to estimate it'. A flow is a PATTERN OF HOW A CUSTOMER ARRIVES AND BUYS, learned from subjects that HAVE data and applied to subjects that do not. Step 0 of the forecast chain (docs/superpowers/specs/2026-08-25-catalog-forecast-chain-design.md). ONE ROW PER FLOW, carrying its learned profile on each LINK of the chain separately — clicks per day, CPC, CVR, gross profit per order — because the purpose is to SPLIT the forecast and see which link is wrong (Ori: 'the meaning is to split the forecast in order to understand what is working good and what is not'). A flow that is only an average of contribution cannot tell you whether the problem is traffic, price or conversion. Membership is DECLARED from fields with full coverage — channel x subject_kind — refined by the supervised intent where it exists (V_INTENT_RESOLVED covers 44.2% of forecast subjects, so intent can refine a flow but can never define one, or 56% of subjects would belong to nothing). Learned over 365 days (§2.0.2). A flow with fewer than min_members fittable members is published with is_usable FALSE: a flow with one member is that member wearing a general name. NOTHING READS IT YET and it decides nothing. Acceptance: scripts/bigquery/tests/CUSTOMER_PURCHASE_FLOW_acceptance.sql.")
AS
WITH k AS (
  -- DECLARED CONSTANTS (§1.5 — porting sets a value rather than hunting a literal)
  SELECT 365 AS window_days,      -- §2.0.2: a year spans a full seasonal cycle
         3   AS min_members,      -- a flow learned from fewer than this is not a pattern
         30  AS min_member_clicks -- a member with less than this teaches the flow nothing
),
wm AS (SELECT MAX(date) AS w FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- EVERY FORECASTABLE SUBJECT AND ITS FLOW, read from the materialised map. Resolved once in
-- T_SUBJECT_FLOW rather than joined here: V_INTENT_RESOLVED classifies ~350k terms and is CPU-heavy,
-- and joining it on LOWER(TRIM(...)) inside this view AND again inside its acceptance suite exceeded
-- the on-demand CPU limit outright (42,184 CPU seconds against a 37,300 ceiling, on 146 MB).
subjects AS (
  SELECT campaign_id, keyword_id, target_text, family, channel, subject_kind, intent_type, term_kind
  FROM `onyga-482313.OI.T_SUBJECT_FLOW`
),

-- WHAT EACH SUBJECT ACTUALLY DID over the window, split BY LINK rather than rolled into one number.
member_daily AS (
  SELECT
    CAST(a.campaign_id AS STRING) AS campaign_id,
    LOWER(TRIM(a.targeting))      AS target_text,
    a.date,
    SUM(a.Ads_clicks)   AS clicks,
    SUM(a.Ads_cost)     AS cost,
    SUM(a.Ads_orders)   AS orders,
    SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm CROSS JOIN k
  WHERE a.date BETWEEN DATE_SUB(wm.w, INTERVAL k.window_days - 1 DAY) AND wm.w
    AND a.campaign_id IS NOT NULL
  GROUP BY 1,2,3
  HAVING SUM(a.Ads_clicks) > 0
),
member AS (
  SELECT
    s.campaign_id, s.keyword_id, s.family, s.channel, s.subject_kind,
    s.intent_type, s.term_kind,
    COUNT(*)                                   AS days_with_clicks,
    SUM(d.clicks)                              AS clicks,
    SUM(d.orders)                              AS orders,
    SUM(d.cost)                                AS cost,
    SUM(d.gp)                                  AS gp,
    SAFE_DIVIDE(SUM(d.cost), NULLIF(SUM(d.clicks), 0))   AS cpc,
    SAFE_DIVIDE(SUM(d.orders), NULLIF(SUM(d.clicks), 0)) AS cvr,
    SAFE_DIVIDE(SUM(d.gp), NULLIF(SUM(d.orders), 0))     AS gp_per_order,
    SAFE_DIVIDE(SUM(d.clicks), COUNT(*))                 AS clicks_per_active_day,
    MAX(SAFE_DIVIDE(d.cost, NULLIF(d.clicks,0)))
      - MIN(SAFE_DIVIDE(d.cost, NULLIF(d.clicks,0)))     AS cpc_spread
  FROM subjects s
  JOIN member_daily d
    ON d.campaign_id = s.campaign_id AND d.target_text = s.target_text
  GROUP BY 1,2,3,4,5,6,7
),

-- A FLOW IS LEARNED ONLY FROM MEMBERS THAT ACTUALLY TAUGHT IT SOMETHING. A subject with 3 clicks in a
-- year is a member of the flow but must not shape its profile, or the flow becomes an average of noise.
teaching AS (SELECT m.* FROM member m CROSS JOIN k WHERE m.clicks >= k.min_member_clicks)

SELECT
  FORMAT('%s|%s|%s', t.channel, t.subject_kind, t.intent_type) AS flow_key,
  t.channel, t.subject_kind, t.intent_type,

  COUNT(*)                                            AS members_teaching,
  (SELECT COUNT(*) FROM member m
    WHERE m.channel = t.channel AND m.subject_kind = t.subject_kind
      AND m.intent_type = t.intent_type)              AS members_total,
  SUM(t.clicks)                                       AS clicks,
  SUM(t.orders)                                       AS orders,
  ROUND(SUM(t.cost), 2)                               AS cost,

  -- THE PROFILE, ONE FIGURE PER LINK OF THE CHAIN. Split on purpose: a flow that published only a
  -- blended contribution could never say WHICH link a member departs on, which is the whole point.
  ROUND(SAFE_DIVIDE(SUM(t.cost),   NULLIF(SUM(t.clicks), 0)), 4) AS flow_cpc,
  ROUND(SAFE_DIVIDE(SUM(t.orders), NULLIF(SUM(t.clicks), 0)), 5) AS flow_cvr,
  ROUND(SAFE_DIVIDE(SUM(t.gp),     NULLIF(SUM(t.orders), 0)), 4) AS flow_gp_per_order,
  ROUND(AVG(t.clicks_per_active_day), 3)                         AS flow_clicks_per_active_day,
  ROUND(SAFE_DIVIDE(SUM(t.gp), NULLIF(SUM(t.cost), 0)), 4)       AS flow_gp_roas,

  -- spread of the members around the flow, so a caller can see whether the flow is a tight pattern
  -- or a label over a crowd. A wide flow is a weak assumption and must look like one.
  ROUND(STDDEV(t.cvr), 5)                             AS cvr_stddev_across_members,
  ROUND(SAFE_DIVIDE(STDDEV(t.cvr), NULLIF(AVG(t.cvr),0)), 3) AS cvr_dispersion,

  COUNTIF(t.days_with_clicks >= 30 AND t.cpc_spread >= 0.20) AS members_fittable,

  -- IS IT USABLE AS AN ASSUMPTION? A flow with one member is that member wearing a general name.
  (COUNT(*) >= (SELECT min_members FROM k))           AS is_usable,
  CASE WHEN COUNT(*) < (SELECT min_members FROM k)
       THEN FORMAT('learned from only %d member(s) — below the declared minimum of %d, so it is one subject wearing a general name rather than a pattern',
                   COUNT(*), (SELECT min_members FROM k))
       ELSE NULL END                                  AS not_usable_because,

  (SELECT window_days FROM k)                         AS window_days,
  (SELECT w FROM wm)                                  AS as_of
FROM teaching t
GROUP BY t.channel, t.subject_kind, t.intent_type
ORDER BY clicks DESC;
