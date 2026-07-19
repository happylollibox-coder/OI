-- V_CAMPAIGN_BID_CUT — the worst-keyword bid cuts for out-of-budget, sub-0.8 campaigns.
-- For every campaign V_CAMPAIGN_DAILY_MOVE flagged BID_CUT: the keywords with negative net (net_proxy)
-- over trailing 8wk AND >= 15 clicks (enough to judge) get bid cut by bid_cut_pct, floored at $0.02.
-- Cut ALL that qualify (not a top-N) so the campaign's net ROAS actually moves; feeds the existing
-- REDUCE_BID apply path. One row per keyword to change.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_BID_CUT` AS
WITH cut AS (SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_DAILY_MOVE` WHERE move_type = 'BID_CUT'),
pct AS (SELECT config_value AS p FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE config_key = 'bid_cut_pct'),
kw AS (
  SELECT k.campaign_id, k.keyword_id,
    ANY_VALUE(k.keyword_text) AS keyword_text,
    ANY_VALUE(k.match_type)   AS match_type,
    ANY_VALUE(k.keyword_bid HAVING MAX k.date) AS current_bid,
    SUM(k.net_proxy) AS net_8w,
    SUM(k.clicks)    AS clicks_8w
  FROM `onyga-482313.OI.V_KEYWORD_DAILY` k
  WHERE k.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
    AND k.keyword_id IS NOT NULL
  GROUP BY k.campaign_id, k.keyword_id
)
SELECT kw.campaign_id, kw.keyword_id, kw.keyword_text, kw.match_type,
  ROUND(kw.current_bid, 2) AS current_bid,
  GREATEST(ROUND(kw.current_bid * (1 - (SELECT p FROM pct)), 2), 0.02) AS new_bid,
  'REDUCE_BID' AS target_action,
  'out-of-budget campaign below 0.8 net ROAS — trimming the worst clicks' AS reason
FROM kw JOIN cut USING (campaign_id)
WHERE kw.net_8w < 0 AND kw.clicks_8w >= 15 AND kw.current_bid IS NOT NULL;
