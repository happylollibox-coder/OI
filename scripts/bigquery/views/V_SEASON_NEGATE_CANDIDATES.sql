-- =============================================
-- V_SEASON_NEGATE_CANDIDATES — v27.46 A6 (2026-08-09). ADVISORY-ONLY surface for the negatives
-- workflow. Spec: architecture/SEASON_CONTEXT_LEDGER.md §5.7 A6.
--
-- Population: keyword texts whose season-context gate reads ENTRY_BLOCK / entry_state = 'STOP'
-- with a mature same-family LOSS prior — the text failed this season family before AND its
-- current-occurrence re-probe allowance is spent (near-settled) without paying back. The 90d
-- escape hatch STRUCTURALLY precedes STOP in the gate (>= 100 clicks at GP-ROAS >= 1.0 resolves
-- RELEASED before STOP can be emitted), so every row here is hatch-INELIGIBLE — the r90_*
-- columns carry the proof alongside the prior-occurrence and re-probe evidence.
--
-- GRAIN: one row per (keyword_text, campaign) where the text is CURRENTLY TARGETED by an
-- ENABLED campaign — SP from DIM_KEYWORD current+ENABLED rows, SB from the live sb_keyword
-- config mirror. Multiple match types collapse into match_types (STRING_AGG).
--
-- EXCLUSIONS:
--   * DEFENSE campaigns entirely — brand terms are never negated in defense (doctrine).
--   * auto clauses / product targets — the gate does not govern them (keyword grain only); the
--     gate's population already excludes those texts, so the equality join enforces this.
--
-- suggested_scope = 'SEARCH_TERM_NEGATE': the remedy is negating the TERM at the campaigns
-- that target the text. DE_NEGATIVE_KEYWORDS is the negatives AUTHORITY — this view suggests,
-- NOTHING auto-uploads (coacher no-auto-fill doctrine).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEASON_NEGATE_CANDIDATES` AS
WITH stops AS (
  SELECT keyword_text, context_label, occurrence_key,
         prior_label, prior_occurrence_key, prior_clicks, prior_net, prior_gp_roas,
         loss_evidence_tier, probe_cap, ns_clicks, ns_spend, ns_gp_roas,
         r90_clicks, r90_gp_roas
  FROM `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE`
  WHERE gate_action = 'ENTRY_BLOCK' AND entry_state = 'STOP' AND prior_verdict = 'LOSS'
),
camp AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_name,
         campaign_type AS channel
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE campaign_state = 'ENABLED'
    AND LOWER(campaign_name) NOT LIKE '%brand defense%'
),
tgt AS (
  SELECT CAST(k.campaign_id AS STRING) AS campaign_id,
         LOWER(TRIM(k.keyword_text)) AS kw, UPPER(k.match_type) AS match_type
  FROM `onyga-482313.OI.DIM_KEYWORD` k
  WHERE k.is_current AND UPPER(k.state) = 'ENABLED'
  UNION DISTINCT
  SELECT CAST(k.campaign_id AS STRING), LOWER(TRIM(k.keyword_text)), UPPER(k.match_type)
  FROM `fivetran-hl.amazon_ads.sb_keyword` k
  WHERE NOT k._fivetran_deleted AND k.state = 'enabled'
)
SELECT
  s.keyword_text, t.campaign_id, c.campaign_name, c.channel,
  STRING_AGG(DISTINCT t.match_type, ', ' ORDER BY t.match_type) AS match_types,
  s.context_label, s.occurrence_key,
  s.prior_label, s.prior_occurrence_key, s.prior_clicks, s.prior_net, s.prior_gp_roas,
  s.loss_evidence_tier, s.probe_cap,
  s.ns_clicks AS reprobe_clicks_near_settled,
  s.ns_spend AS reprobe_spend_near_settled,
  s.ns_gp_roas AS reprobe_gp_roas_near_settled,
  s.r90_clicks, s.r90_gp_roas,
  'SEARCH_TERM_NEGATE' AS suggested_scope,
  CONCAT('ADVISORY (nothing auto-uploads; DE_NEGATIVE_KEYWORDS is the authority): prior ',
         s.prior_label, ' LOSS (', CAST(s.prior_clicks AS STRING), 'c, net -$',
         FORMAT('%.2f', ABS(s.prior_net)), ', mature) and the ', s.context_label,
         ' re-probe spent $', FORMAT('%.2f', s.ns_spend), ' near-settled at ',
         FORMAT('%.2f', COALESCE(s.ns_gp_roas, 0)),
         'x without paying back — negate the term at this campaign; 90d record ',
         CAST(s.r90_clicks AS STRING), 'c at ', FORMAT('%.2f', COALESCE(s.r90_gp_roas, 0)),
         'x (hatch-ineligible by construction)') AS reason
FROM stops s
JOIN tgt t ON t.kw = s.keyword_text
JOIN camp c ON c.campaign_id = t.campaign_id
GROUP BY s.keyword_text, t.campaign_id, c.campaign_name, c.channel, s.context_label,
         s.occurrence_key, s.prior_label, s.prior_occurrence_key, s.prior_clicks, s.prior_net,
         s.prior_gp_roas, s.loss_evidence_tier, s.probe_cap, s.ns_clicks, s.ns_spend,
         s.ns_gp_roas, s.r90_clicks, s.r90_gp_roas;
