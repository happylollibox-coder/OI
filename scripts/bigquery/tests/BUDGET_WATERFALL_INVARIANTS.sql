-- Budget-waterfall invariants. Each SELECT must return ZERO rows to pass.
-- Run each statement independently: bq query --use_legacy_sql=false '<one statement>'

-- 1. Coverage: every enabled campaign maps to exactly one family.
SELECT e.campaign_id
FROM (SELECT campaign_id FROM `onyga-482313.OI.DIM_CAMPAIGN`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC)=1 AND state='ENABLED') e
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m USING (campaign_id)
WHERE m.parent_name IS NULL;

-- 2. Family allocation sums to the total (±$1), when no MANUAL_DAILY override exists.
SELECT ABS(SUM(allocated_daily) - MAX(t.total)) AS drift
FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION`
CROSS JOIN (SELECT config_value total FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE config_key='total_daily_budget') t
WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` WHERE source='MANUAL_DAILY')
HAVING drift > 1;

-- 3. Coverage: campaign count in the base == enabled campaign count (no campaign dropped).
SELECT in_base, enabled FROM (
  SELECT (SELECT COUNT(DISTINCT campaign_id) FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE`) AS in_base,
         (SELECT COUNT(*) FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`) AS enabled
) WHERE in_base != enabled;

-- 4. Per-family, per-pool: defense sums EXACTLY to its budget; offense never falls SHORT of its budget
--    (offense may EXCEED it when product-defense $30 learning floors are larger than the family offense budget).
SELECT parent_name, is_defense, drift FROM (
  SELECT parent_name, is_defense,
    CASE WHEN is_defense THEN ABS(SUM(base_daily) - MAX(family_budget))
         ELSE GREATEST(MAX(family_budget) - SUM(base_daily), 0) END AS drift
  FROM `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE`
  GROUP BY parent_name, is_defense
) WHERE drift > 1;

-- 5. Daily move: per-family SUM(proposed_daily) never exceeds the family cap (±$1).
SELECT d.parent_name, SUM(d.proposed_daily) - ANY_VALUE(f.allocated_daily) AS over_by
FROM `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` d
JOIN `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` f USING (parent_name)
GROUP BY d.parent_name HAVING over_by > 1;
