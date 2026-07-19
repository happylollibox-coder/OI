-- V_WEEKLY_RUN_CAMPAIGN — EVERY ad campaign attributed to a product, for the Weekly Run.
-- Req1 completeness: all campaigns present. product = single family (dominant most-advertised family),
-- 'Store' if the campaign's ads span >1 product line (cross-family), 'Unknown' if no family maps.
-- Carries the coacher's campaign budget recommendation (where it has one) + plain reason + recent perf,
-- so Step 3 can show campaign budgets (level 1) under each product, capped by the product budget.
-- Backend-owned (all-logic-in-backend). 60-day window = active-campaign inventory.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_RUN_CAMPAIGN` AS
WITH fact AS (
  SELECT
    campaign_id,
    -- LATEST name per campaign (not ANY_VALUE): the 60-day window spans renames, and a stale pick
    -- showed old names like "p1 ME-SP/PHRASE …" for campaigns Amazon has since renamed. Use the most
    -- recent day's name so the dashboard matches Amazon.
    ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name,
    ANY_VALUE(campaign_type) AS campaign_type,
    SUM(Ads_cost)          AS spend_60d,
    SUM(GROSS_PROFIT)      AS gp_60d,
    SUM(Ads_impressions)   AS imp_60d,
    SUM(IF(advertised_asins_count > 1, Ads_impressions, 0)) AS multi_imp_60d,
    -- windowed net ROAS inputs (net ROAS = GROSS_PROFIT / Ads_cost) — LA tz to match the keyword rows.
    -- last 7 days · last 14 days (trailing, incl. the 7d) · last 28 days. (spend_pw/gp_pw = the 14d window.)
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), Ads_cost, 0))     AS spend_1w,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), GROSS_PROFIT, 0)) AS gp_1w,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY), Ads_cost, 0))     AS spend_pw,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY), GROSS_PROFIT, 0)) AS gp_pw,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY), Ads_cost, 0))     AS spend_4w,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY), GROSS_PROFIT, 0)) AS gp_4w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    -- complete days only — the windowed net-ROAS columns must match the engine's decision windows
    AND date < CURRENT_DATE('America/Los_Angeles')
  GROUP BY campaign_id
),
-- families a campaign touches (via every advertised ASIN) → detects cross-family 'Store'
camp_fams AS (
  SELECT f.campaign_id, COUNT(DISTINCT p.parent_name) AS fam_ct
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f,
       UNNEST(SPLIT(f.advertised_asins, ", ")) AS a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON CAST(p.asin AS STRING) = TRIM(a)
  WHERE f.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
  GROUP BY f.campaign_id
),
-- dominant family per campaign (most-advertised ASIN, weighted by impressions) — engine-consistent
dom_fam AS (
  SELECT campaign_id, family FROM (
    SELECT f.campaign_id, p.parent_name AS family,
      ROW_NUMBER() OVER (PARTITION BY f.campaign_id ORDER BY SUM(f.Ads_impressions) DESC) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
    JOIN `onyga-482313.OI.DIM_PRODUCT` p
      ON CAST(p.asin AS STRING) = CAST(f.most_advertised_asin_impressions AS STRING)
    WHERE f.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    GROUP BY f.campaign_id, p.parent_name
  ) WHERE rn = 1
),
-- Days since WE last uploaded a budget/any change for this campaign (FACT_PPC_CHANGE_LOG =
-- authoritative upload time). Drives the "✓ applied Nd ago" badge on campaign budget rows.
last_change AS (
  SELECT campaign_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since_suggestion
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE campaign_id IS NOT NULL AND campaign_id != ''
  GROUP BY campaign_id
),
-- Authoritative CURRENT campaign name from the campaign dimension (tracks renames even for campaigns
-- that went inactive — FACT only carries a name on days the campaign had activity, so a renamed-then-
-- paused campaign keeps its OLD name in FACT). DIM is the source of truth; FACT-latest is the fallback.
dim_name AS (
  SELECT CAST(campaign_id AS STRING) AS dcid, ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(DATE(creation_date)) AS created
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  WHERE is_current AND campaign_name IS NOT NULL
  GROUP BY 1
)
SELECT
  fact.campaign_id,
  COALESCE(dn.campaign_name, fact.campaign_name) AS campaign_name,
  fact.campaign_type,
  CASE
    WHEN COALESCE(cf.fam_ct, 0) > 1 THEN 'Store'      -- ad spans >1 product line → can't attribute
    WHEN df.family IS NULL         THEN 'Unknown'     -- no family maps → assign it
    ELSE df.family
  END AS product,
  ROUND(fact.spend_60d / 60.0, 2)                              AS recent_daily_spend,
  ROUND(fact.gp_60d - fact.spend_60d, 2)                       AS ads_net_60d,
  -- age bucket (matches V_BUDGET_STEP1_CAMPAIGN) so the "Budget by age" filter can gate step-4 keywords
  CASE
    WHEN dn.created IS NULL THEN 'UNKNOWN'
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), dn.created, DAY) <= 20  THEN 'NEW'
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), dn.created, DAY) <= 90  THEN '1-3MO'
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), dn.created, DAY) <= 270 THEN '4-9MO'
    ELSE '10MO+' END                                           AS age_bucket,
  ROUND(SAFE_DIVIDE(fact.gp_60d, NULLIF(fact.spend_60d, 0)), 2) AS ads_net_roas_60d,
  -- per-campaign net ROAS by window (NULL when the window had no spend)
  ROUND(SAFE_DIVIDE(fact.gp_1w, NULLIF(fact.spend_1w, 0)), 2) AS ads_net_roas_1w,
  ROUND(SAFE_DIVIDE(fact.gp_pw, NULLIF(fact.spend_pw, 0)), 2) AS ads_net_roas_prev_1w,
  ROUND(SAFE_DIVIDE(fact.gp_4w, NULLIF(fact.spend_4w, 0)), 2) AS ads_net_roas_4w,
  ROUND(SAFE_DIVIDE(fact.multi_imp_60d, NULLIF(fact.imp_60d, 0)), 2) AS multi_product_share,
  -- strategic bucket (hierarchy 0): SCALE = wants more budget to grow · CUT = losing, trim · MARGIN = profitable, hold
  CASE
    WHEN b.budget_action = 'CAMPAIGN_STOP' OR b.budget_action LIKE '%CONTAIN%' THEN 'CUT'
    WHEN b.budget_action = 'DEFENSE_BUDGET_FLOOR' THEN 'MARGIN'
    WHEN b.budget_action LIKE '%INCREASE%' THEN 'SCALE'
    WHEN b.budget_action LIKE '%DECREASE%' THEN 'CUT'
    WHEN COALESCE(b.effective_roas, SAFE_DIVIDE(fact.gp_60d, NULLIF(fact.spend_60d, 0))) < 0.9 THEN 'CUT'
    WHEN COALESCE(b.effective_roas, SAFE_DIVIDE(fact.gp_60d, NULLIF(fact.spend_60d, 0))) >= 1.1
         AND COALESCE(b.util_pct, 0) >= 90 THEN 'SCALE'
    ELSE 'MARGIN'
  END AS strategy_type,
  -- coacher budget recommendation (NULL for unmapped/non-coach campaigns)
  b.budget_action,
  b.current_budget,
  b.recommended_budget,
  b.util_pct,
  b.effective_roas,      -- engine's decision ROAS (drives the cut/raise) — NOT the 60d FACT roas above
  b.is_new_campaign,
  b.coach_mode,
  lc.days_since_suggestion,
  -- Strategy-mapping status (drives the "⚠ assign strategy" badge + prefills the manage popup).
  -- needs_strategy = truly unmapped. Authoritative source is V_CAMPAIGN_ROLE.strategy_id (DIM_EXPERIMENT):
  -- V_CAMPAIGN_MAPPING_STATUS covers only a subset (67 mapped campaigns were missing from it, so the old
  -- COALESCE flagged them as unmapped and hid their keywords). Fixed 2026-07-18.
  (cr.strategy_id IS NULL) AS needs_strategy,
  ms.current_strategy_id,
  ms.suggested_family,
  ms.suggested_strategy,
  -- Coverage role — the grain the Weekly Run strategy filter uses, so steps 2-4 slice the same way.
  -- Canonical definition lives in V_CAMPAIGN_ROLE (shared with /api/coverage).
  COALESCE(cr.role, 'OTHER') AS strategy_role,
  -- Strategy grain (cross-pool) for the "Budget by strategy" filter over step-4 keywords.
  COALESCE(cr.strategy_category, 'OTHER') AS strategy_category,
  (b.budget_action IS NULL) AS no_coach_decision
FROM fact
LEFT JOIN dim_name dn ON dn.dcid = CAST(fact.campaign_id AS STRING)
LEFT JOIN camp_fams cf USING (campaign_id)
LEFT JOIN dom_fam   df USING (campaign_id)
LEFT JOIN last_change lc USING (campaign_id)
-- Deduped to ONE row per campaign_id: the mapping-status view can carry multiple candidate rows per
-- campaign (suggestion variants), and a raw join fans campaign rows out (Weekly Run showed the same
-- campaign 2-3×). ANY_VALUE keeps the semantics; the fields agree across a campaign's rows.
LEFT JOIN (
  SELECT campaign_id,
    ANY_VALUE(current_strategy_id) AS current_strategy_id,
    ANY_VALUE(suggested_family)    AS suggested_family,
    ANY_VALUE(suggested_strategy)  AS suggested_strategy,
    ANY_VALUE(source)              AS source
  FROM `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS`
  GROUP BY campaign_id
) ms USING (campaign_id)
LEFT JOIN `onyga-482313.OI.T_COACH_CAMPAIGN_BUDGET` b ON b.campaign_id = fact.campaign_id
-- Joined last, with an explicit ON: V_CAMPAIGN_ROLE carries its own campaign_id, which would make the
-- USING (campaign_id) joins above ambiguous if it entered scope before them.
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_ROLE` cr ON cr.campaign_id = CAST(fact.campaign_id AS STRING);
