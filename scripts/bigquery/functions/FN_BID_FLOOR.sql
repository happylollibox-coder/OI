-- FN_BID_FLOOR — THE ONE DEFINITION of a target's platform/house bid floor (v27.104, 2026-08-22).
--
-- WHY ONE PLACE. Three engines carried the same three numbers as private constants, and one of them
-- (the keyword state ladder, v27.103) carried a FOURTH — a flat $0.25 "platform_floor" borrowed from
-- V_OOB_KEYWORD's bid_park, which is a PARKING price, not a floor. Judged against that flat number the
-- ladder manufactured three phantom kills: two SP auto clauses sitting at $0.21/$0.24 (above the real
-- $0.20 SP floor, and above their family bar) and an SB product-collection keyword whose real floor is
-- $0.10 and whose affordable price ($0.49) was perfectly executable. A floor is a property of the
-- CHANNEL and the CREATIVE, and it lives here so no engine can hold a private copy again.
--
-- THE RULE (verbatim from V_LAUNCH_BID_LADDER v27.59, which V_OOB_KEYWORD / V_KEYWORD_LIFT match):
--   SP (and anything not SB)                $0.20  HOUSE floor. Amazon's own SP minimum is $0.02, but a
--                                                  bid that low buys no placement worth having.
--   SB, PRODUCT_COLLECTION / STORE_SPOTLIGHT $0.10  Amazon's minBid for those creatives.
--   SB, video (BRAND_VIDEO / VIDEO)          $0.25  Amazon's SB minBid — under it the row is REJECTED
--                                                  ($0.15 rejected in r32, $0.20 in r33, both quoting
--                                                  minBid 0.25).
--   SB, creative_type NULL                   $0.25  conservative: bidding too high is recoverable, a
--                                                  rejected row is a wasted upload. 192 of 273 current
--                                                  SB ad groups carry a NULL creative_type today.
-- Creative type is resolved by the caller from DIM_AD_GROUP.creative_type (is_current) — V_BID_FLOOR
-- does that resolution once at ad-group grain for callers that do not already carry it.
--
-- Declared constants (Standing Rule 0 exempt — platform minimums and one house choice, not measurements).
-- Readers: V_LAUNCH_BID_LADDER (bid_floor / bid_floor_source), V_BID_FLOOR -> SP_SNAPSHOT_KEYWORD_STATE
-- and tools/build_reprice_bulksheet.py. Spec: architecture/KEYWORD_STATE.md "The floors".
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_BID_FLOOR`(channel STRING, creative_type STRING)
RETURNS STRUCT<bid_floor FLOAT64, bid_floor_source STRING> AS (
  CASE
    WHEN channel <> 'SB'                                                 THEN STRUCT(0.20, 'SP_HOUSE_0.20')   -- NULL channel falls through to $0.25 (conservative), as the ladder's CASE always did
    WHEN creative_type IN ('PRODUCT_COLLECTION', 'STORE_SPOTLIGHT')     THEN STRUCT(0.10, 'SB_COLLECTION_0.10')
    ELSE                                                                      STRUCT(0.25, 'SB_VIDEO_0.25')
  END
);
