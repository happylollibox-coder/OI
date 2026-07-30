-- =============================================
-- 2026-07-23 — COMPETITOR campaign templates + plan knobs
-- =============================================
--
-- The 9-strategy taxonomy has COMPETITOR, but DIM_STRATEGY_CAMPAIGN_TEMPLATE never gained rows
-- for it (it still carries the pre-migration ids: EXACT_BOOST, INTENT, TOS_DOMINATION, ...).
-- Without them the competitor bulksheet writer would have to hardcode budget/bid bounds in React,
-- which the "thresholds live in DE_/DIM_ tables, not code" rule forbids. These two rows are what
-- FN_COMPETITOR_CAMPAIGN_PLAN and DoPage's ADD_COMPETITOR_TARGET branch read.
--
-- bid_max = 2.00 deliberately matches the existing BID_CAP_SUGGESTION / COMPETITOR / GUARDIAN
-- ceiling ($2) rather than the observed max target_cpc ($3.86). The plan still publishes the
-- UNCAPPED suggested_bid_raw plus a bid_capped flag, so a target worth more than the ceiling is
-- visible rather than silently truncated.
--
-- product_page_pct = 200: ASIN targets serve on competitors' detail pages, so that placement is
-- the whole point. Set below PRODUCT_DEFENSE's 300 — defending our own listing is worth more per
-- impression than conquesting someone else's.
--
-- Idempotent: DELETEs only the two COMPETITOR rows this migration owns, then re-inserts.
-- =============================================

DELETE FROM `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` WHERE strategy_id = 'COMPETITOR';

INSERT INTO `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE`
  (strategy_id, campaign_seq, ad_format, match_type, bidding_strategy,
   bid_min, bid_max, daily_budget, top_of_search_pct, product_page_pct,
   purpose, naming_hint, is_required, notes)
VALUES
('COMPETITOR', 1, 'SP', 'PRODUCT_TARGETING', 'DOWN_ONLY',
  0.25, 2.00, 10.0, 0, 200,
  'SP product targeting on competitor ASINs proven profitable in Auto/Broad discovery',
  '{PRODUCT}-SP/PT (Competitors, {VARIATION}, {TIER})',
  TRUE, 'One campaign per winner variation x bid tier, max 10 ASINs. Bid = group MIN(target_cpc) so every ASIN in the campaign clears the profit floor. DOWN_ONLY: conquest clicks are dear, do not let Amazon bid up.'),

('COMPETITOR', 2, 'SB_VIDEO', 'PRODUCT_TARGETING', 'DOWN_ONLY',
  0.25, 1.50, 10.0, 0, 0,
  'SB Video on competitor detail pages — the creative features the winner variation',
  '{PRODUCT}-VIDEO/PT (Competitors, {VARIATION}, {TIER})',
  FALSE, 'Optional. Needs a video asset for the winner variation (DIM_PRODUCT_CREATIVES); the writer skips it when none exists. Grouping by winner variation exists precisely so one video fits every ASIN in the campaign.');


-- ── Plan knob: how many ASINs may share one competitor campaign ────────────────────────────────
-- A campaign shares one bid; 10 keeps a group tight enough that the group MIN(target_cpc) is not
-- a big compromise for the strongest ASIN in it. Ori-editable without a deploy.
DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE threshold_key = 'COMPETITOR_MAX_ASINS_PER_CAMPAIGN';

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, coach_mode, threshold_value, description, peak_multiplier, boost_peak_multiplier, source)
VALUES
  ('COMPETITOR_MAX_ASINS_PER_CAMPAIGN', 'COMPETITOR', 'GUARDIAN', 10,
   'Max competitor ASIN targets per generated campaign (FN_COMPETITOR_CAMPAIGN_PLAN chunk size)', 1, 1, 'MANUAL');
