-- V_WEEKLY_PLAN_CELL — DE_WEEKLY_PLAN cells + the SAME cell's actual net from the prior week,
-- and the cell's trailing-8w ACTUAL CPC (spend/clicks) so the plan detail can flag when the plan's
-- target_cpc is ABOVE what the cell actually pays (i.e. the plan wants to bid the price up).
-- Backend-owned join (all decision/derivation logic lives in SQL, per the standing rule).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_CELL` AS
SELECT
  p.*,
  l.last_net,
  l.last_spend,
  l.last_units,
  l.last_cpc,
  ac.actual_cpc,
  ac.units_8w,
  sn.avg_net_day_off,
  sn.avg_net_day_peak
FROM `onyga-482313.OI.DE_WEEKLY_PLAN` p
LEFT JOIN (   -- prior week's actual net + units per FINE cell (campaign_type × ad_format)
  SELECT
    parent_name,
    week_start,
    match_type,
    intent_class,
    campaign_type,
    ad_format,
    SUM(net_profit) AS last_net,
    SUM(spend)      AS last_spend,
    SUM(units)      AS last_units,
    ROUND(SAFE_DIVIDE(SUM(spend), NULLIF(SUM(clicks), 0)), 2) AS last_cpc   -- prior-week actual CPC
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  GROUP BY 1, 2, 3, 4, 5, 6
) l
  ON  l.parent_name   = p.parent_name
  AND l.match_type    = p.match_type
  AND l.intent_class  = p.intent_class
  AND l.campaign_type = p.campaign_type
  AND l.ad_format     = p.ad_format
  AND l.week_start    = DATE_SUB(p.week_start, INTERVAL 1 WEEK)
LEFT JOIN (   -- trailing-8w actual CPC per FINE cell (CPC doesn't swing by season → no season key)
  SELECT
    parent_name,
    match_type,
    intent_class,
    campaign_type,
    ad_format,
    ROUND(SAFE_DIVIDE(SUM(spend), NULLIF(SUM(clicks), 0)), 2) AS actual_cpc,
    SUM(units) AS units_8w     -- ad units sold over the trailing 8w (stable volume for the halo read)
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  WHERE week_start >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(SUNDAY)), INTERVAL 8 WEEK)
  GROUP BY 1, 2, 3, 4, 5
) ac
  ON  ac.parent_name   = p.parent_name
  AND ac.match_type    = p.match_type
  AND ac.intent_class  = p.intent_class
  AND ac.campaign_type = p.campaign_type
  AND ac.ad_format     = p.ad_format
LEFT JOIN (   -- lifetime avg ad net profit / DAY per FINE cell, split by season (relevant peak vs off).
  -- Denominator = 7 × active weeks in that season, so it's the mean over days the cell actually ran.
  SELECT
    parent_name,
    match_type,
    intent_class,
    campaign_type,
    ad_format,
    ROUND(SAFE_DIVIDE(SUM(IF(season='OFF',  net_profit, 0)), 7 * NULLIF(COUNTIF(season='OFF'),  0)), 2) AS avg_net_day_off,
    ROUND(SAFE_DIVIDE(SUM(IF(season='PEAK', net_profit, 0)), 7 * NULLIF(COUNTIF(season='PEAK'), 0)), 2) AS avg_net_day_peak
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  GROUP BY 1, 2, 3, 4, 5
) sn
  ON  sn.parent_name   = p.parent_name
  AND sn.match_type    = p.match_type
  AND sn.intent_class  = p.intent_class
  AND sn.campaign_type = p.campaign_type
  AND sn.ad_format     = p.ad_format;
