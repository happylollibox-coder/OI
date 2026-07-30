-- =============================================
-- OI — DE_COMPETITOR_BID_TIER
-- =============================================
--
-- Purpose: tunable bid bands over target_cpc for the COMPETITOR campaign plan.
--
-- WHY TIERS EXIST: an Amazon campaign shares ONE bid across every target in it. If a campaign
-- mixes an ASIN that breaks even at $0.31 with one that breaks even at $2.90, no single bid is
-- right — bid low and you never win the expensive one, bid high and you lose money on the cheap
-- one. Grouping by band means every ASIN in a campaign wants roughly the same bid, so one bid
-- setting is defensible for all of them.
--
-- Consumed by FN_COMPETITOR_CAMPAIGN_PLAN. Ori-editable without a deploy: change a boundary here
-- and the plan regroups on the next read (no view/function change, per the "thresholds live in
-- DE_ tables" rule).
--
-- BANDS (chosen 2026-07-23 against REAL candidate distributions, all families):
--   The originally-proposed A>=2.50 / B 1.75 / C 1.25 / D<1.25 was DEGENERATE on this account:
--   at 12mo it put 87 of 127 candidates (69%) into D, and that single D band spanned $0.31–$1.16
--   — a 3.7x bid range inside one campaign, i.e. exactly the problem tiering is meant to solve.
--   The bands below follow where the mass actually sits (the account's competitor economics
--   cluster around $0.70–$1.20 target CPC) and keep every bounded band under a ~1.35x internal
--   spread:
--     tier  band            n(12mo)  n(90d)   in-band cpc spread
--     A     >= 2.00            14       7     1.83x (open top)
--     B     1.40 – 1.99        19       4     1.33x
--     C     1.00 – 1.39        31       9     1.33x
--     D     0.80 – 0.99        27       8     1.21x
--     E     <  0.80            36       9     2.52x (open bottom)
--   The open-ended A and E tails are inherently wider; the max-10-per-campaign chunking (highest
--   target_cpc first) narrows them further in practice.
--
-- min_target_cpc is INCLUSIVE, max_target_cpc is EXCLUSIVE. NULL max = open top,
-- NULL min = open bottom. Bands must not overlap and must cover (0, +inf).
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COMPETITOR_BID_TIER` (
  tier_code       STRING NOT NULL,   -- 'A'..'E' — also the campaign-name token
  tier_label      STRING,            -- human label for the UI
  min_target_cpc  FLOAT64,           -- inclusive lower bound; NULL = open bottom
  max_target_cpc  FLOAT64,           -- EXCLUSIVE upper bound; NULL = open top
  sort_order      INT64 NOT NULL,    -- 1 = richest tier
  description     STRING,
  updated_at      DATETIME DEFAULT CURRENT_DATETIME(),
  updated_by      STRING
);

-- Seed / re-seed. Safe to re-run: this table holds only band definitions (no user rows).
DELETE FROM `onyga-482313.OI.DE_COMPETITOR_BID_TIER` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DE_COMPETITOR_BID_TIER`
  (tier_code, tier_label, min_target_cpc, max_target_cpc, sort_order, description, updated_by)
VALUES
  ('A', 'A · premium ($2.00+)',   2.00, NULL, 1, 'Converts hard enough to justify a $2+ bid. Smallest, richest group.', 'SEED'),
  ('B', 'B · strong ($1.40-1.99)', 1.40, 2.00, 2, 'Comfortably above the account mean competitor CPC.',                 'SEED'),
  ('C', 'C · solid ($1.00-1.39)',  1.00, 1.40, 3, 'Around the account mean. The largest band at 12mo.',                 'SEED'),
  ('D', 'D · thin ($0.80-0.99)',   0.80, 1.00, 4, 'Profitable but only just; bid discipline matters most here.',        'SEED'),
  ('E', 'E · marginal (<$0.80)',   NULL, 0.80, 5, 'Clears the floor only at a low bid. Cheapest group.',                'SEED');
