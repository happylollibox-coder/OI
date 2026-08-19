-- V_TARGET_BID_SHADOW — the target-bid model at today's settled anchor.
-- =============================================================================
-- SHADOW VIEW. NOTHING READS THIS. It is not referenced by V_ADS_COACH,
-- V_OOB_KEYWORD, V_KEYWORD_LIFT, V_COACH_APPLY, the bulksheet generator, Cube or
-- any dashboard endpoint. v27.40 shipped a target-CPC bid model straight into the
-- engine and was reverted the same day (267 rows / $2,457 per week of harm); this
-- one is published to be argued with, backtested and audited before anything acts
-- on it. Wiring it in is a separate, explicit decision.
--
-- All logic lives in FN_TARGET_BID_SHADOW(anchor, apply_season_gate) — edit that
-- file, not this one, or the view and the backtest drift apart. This view exists
-- only to pin the two arguments:
--
--   anchor            = MAX(FACT_AMAZON_ADS.date) - 30 days.
--                       SP Ads_orders come from purchases_30_d (see
--                       V_SRC_AmazonAds_SearchTerms lines 68/89), SB from
--                       attributed_conversions_14_d (lines 110/132), so the
--                       binding settle constraint is SP at D-30, NOT the D+7
--                       usually quoted. Anything fresher under-measures CVR.
--                       CONSEQUENCE, and it is a real one: the freshest account
--                       CVR level this view can honestly carry is ~4-6 weeks old,
--                       and level drift is the largest single error source in the
--                       whole model (see architecture/TARGET_BID_SHADOW.md §Level).
--   apply_season_gate = TRUE. V_KEYWORD_CONTEXT_GATE is current state, which is
--                       correct here and wrong for any historical evaluation —
--                       the backtest calls the FN with FALSE.
--
-- FILTERED to live rows only: campaign ENABLED and target ENABLED. The function
-- returns the full priceable universe; use the function directly if you want the
-- paused/archived rows too.
--
-- Read the two output columns as different objects:
--   target_cpc  what a click is worth — a CPC.
--   target_bid  what to actually type into the bid field — a BID.
-- They differ by the measured transfer realized_CPC = k x bid^0.686. Assigning
-- target_cpc to a bid field IS the v27.40 defect.
--
-- Dependencies: FN_TARGET_BID_SHADOW, FACT_AMAZON_ADS
-- SOP: architecture/TARGET_BID_SHADOW.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_TARGET_BID_SHADOW` AS
SELECT *
FROM `onyga-482313.OI.FN_TARGET_BID_SHADOW`(
  (SELECT DATE_SUB(MAX(date), INTERVAL 30 DAY) FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
  TRUE
)
WHERE is_live;
