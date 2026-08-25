CREATE OR REPLACE VIEW `onyga-482313.OI.V_SUBJECT_FLOW_CHOICE`
OPTIONS (description = "For every forecastable subject, WHICH flow level the Catalog should use, and why (THREE_LAYERS.md §2.0.3; Ori 2026-08-25: 'the catalog should try to find the flow that most chances will get the estimate accurate'). Walks the subject's ten-level ladder and takes THE DEEPEST LEVEL THAT IS STILL LEARNED FROM ENOUGH EVIDENCE — deeper is more specific and measurably tighter (dispersion falls monotonically 0.933 at level 1 to 0.274 at level 10), but a deep flow with two members is one subject wearing a general name, so depth is taken only while the evidence holds. LEVEL 1 IS UNIVERSAL, so a subject can always be answered and the view never returns nothing. Publishes the chosen level's whole profile, the level it FELL BACK FROM if any, and should_split — Ori's rule that a flow with enough clicks yet still dispersed is too coarse and needs a further dimension rather than more patience. Nothing reads it yet and it decides nothing. Acceptance: scripts/bigquery/tests/CUSTOMER_PURCHASE_FLOW_acceptance.sql.")
AS
WITH k AS (SELECT 200 AS min_flow_clicks),   -- a level must have been learned from real traffic
cand AS (
  SELECT
    s.campaign_id, s.keyword_id, s.target_text, s.family,
    l.level, l.flow_key, l.adds,
    f.members_teaching, f.clicks AS flow_clicks, f.is_usable,
    f.flow_cpc, f.flow_cvr, f.flow_gp_per_order, f.flow_clicks_per_active_day, f.flow_gp_roas,
    f.cvr_dispersion, f.should_split, f.should_split_because,
    -- a level is ELIGIBLE when it is usable AND was learned from real traffic. Both are needed:
    -- members without clicks is a crowd that never bought, clicks without members is one subject.
    (f.is_usable AND f.clicks >= (SELECT min_flow_clicks FROM k)) AS eligible
  FROM `onyga-482313.OI.T_SUBJECT_FLOW` s, UNNEST(s.flow_ladder) l
  LEFT JOIN `onyga-482313.OI.V_CUSTOMER_PURCHASE_FLOW` f
    ON f.level = l.level AND f.flow_key = l.flow_key
  WHERE l.flow_key IS NOT NULL
),
chosen AS (
  SELECT *, 
         -- the DEEPEST eligible level, and the deepest level that EXISTED at all, so the answer can
         -- say what it gave up rather than silently returning something shallow
         MAX(IF(eligible, level, NULL)) OVER (PARTITION BY campaign_id, keyword_id) AS use_level,
         MAX(level)                     OVER (PARTITION BY campaign_id, keyword_id) AS deepest_level
  FROM cand
)
SELECT
  campaign_id, keyword_id, target_text, family,
  level AS chosen_level, flow_key AS chosen_flow_key, adds AS chosen_level_adds,
  deepest_level,
  deepest_level - level AS levels_given_up,
  members_teaching, flow_clicks,
  flow_cpc, flow_cvr, flow_gp_per_order, flow_clicks_per_active_day, flow_gp_roas,
  cvr_dispersion, should_split, should_split_because,
  -- §2.0.2 disclosure: the answer always says where it came from and how specific it is
  FORMAT('FLOW L%d (%s) — learned from %d members and %d clicks, members scatter %s around its CVR.%s%s',
         level, flow_key, members_teaching, flow_clicks,
         IFNULL(FORMAT('%.0f%%', 100*cvr_dispersion), 'an unmeasured amount'),
         IF(deepest_level > level,
            FORMAT(' Fell back %d level(s): the deeper flow had too little evidence to trust.',
                   deepest_level - level), ''),
         IF(should_split, ' THIS FLOW IS TOO COARSE — it has enough clicks and still scatters, so it needs a further dimension.', ''))
    AS basis
FROM chosen
WHERE level = use_level
ORDER BY chosen_level DESC, flow_clicks DESC;
