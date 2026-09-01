-- 2026-09-01 — Task 10 of the intent CVR index registry: the support gate for a product's own
-- margin, when V_INTENT_BID_BASE stops computing gp_per_order and starts reading the house's
-- shared definition (V_KEYWORD_RATES).
--
-- WHY A GATE AT ALL. Sourcing gp_per_order from V_KEYWORD_RATES makes it available at PRODUCT
-- grain, which is what the account's own measurement says it should be: gp_per_order is a family
-- property with eta-squared 0.794, and Lollibox SP breakeven is $0.737 against SB's $0.395. But
-- the finest grain the shared view reaches is only honest where that product carries enough
-- orders for a MEAN to be a mean. Without a gate, Blue Lollibox's 20 weighted orders would price
-- an entire product's catalog off a handful of transactions.
--
-- HOW 125 WAS DERIVED, AND AT WHICH GRAIN. Measured 2026-09-01 over the last 400 days of
-- FACT_AMAZON_ADS joined to DIM_PRODUCT, at the product x calendar-month grain, by splitting each
-- cell into odd and even days and comparing the two halves' gp_per_order:
--
--   orders in cell | cells | median half-split gap | p75 half-split gap
--   <10            |  10   | 0.069                 | 0.286
--   10-19          |  13   | 0.039                 | 0.133
--   20-39          |  11   | 0.064                 | 0.208
--   40-79          |   8   | 0.091                 | 0.148
--   80-159         |  13   | 0.037                 | 0.058
--   160+           |  45   | 0.027                 | 0.052
--
-- The p75 column is the one that matters — the median is quiet everywhere and hides the tail.
-- It collapses from 0.148 to 0.058 between the 40-79 and 80-159 buckets and does not improve
-- materially above it, so 80 RAW orders is where a product-level gp_per_order stops being a
-- coin flip. That break is measured in RAW orders; the gate is applied to V_KEYWORD_RATES'
-- weighted_orders, which is the nested 3/7/28/90 sum and therefore larger. Measured ratio
-- weighted_orders / orders_90_settled across the nine products the shared view covers today:
-- 1.14, 1.37, 1.43, 1.54, 1.58, 1.58, 1.74, 1.77, 2.37 — median 1.58. 80 x 1.58 = 126, taken
-- as 125.
--
-- THIS CONSTANT IS A PRECISION REQUIREMENT, NOT A PRIOR. That is why the same number is applied
-- at both the product and the family rung of the ladder in V_INTENT_BID_BASE: it asks "does this
-- bucket hold enough orders for its mean to be stable", a question about n, not about which key
-- the bucket is named by. It is NOT interchangeable with INTENT_CVR_BASE_PRIOR_CLICKS or the two
-- season priors, which shrink a RATE toward a pooled level and are counted in clicks.
--
-- Re-runnable: DELETE/INSERT.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md section 7.

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_GP_MIN_ORDERS';

-- coach_mode = GUARDIAN and product_family = NULL are load-bearing, not decorative: thresholds
-- resolve strategy_id+coach_mode -> GLOBAL+coach_mode -> strategy_id+GUARDIAN -> GLOBAL+GUARDIAN.
-- V_INTENT_BID_BASE's params CTE reads strategy_id='INTENT' AND coach_mode='GUARDIAN' AND
-- product_family IS NULL, so a row landing under any other mode is invisible to it and the gate
-- resolves NULL — which, because `wo >= NULL` is NULL, would silently drop every row to the
-- account rung rather than erroring.
INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('INTENT_GP_MIN_ORDERS', 'INTENT', 125.0,
   'Minimum V_KEYWORD_RATES weighted_orders for a bucket to price V_INTENT_BID_BASE off its OWN gp_per_order rather than dropping a rung (product -> family -> account). Derived 2026-09-01 from an odd/even day half-split of gp_per_order at the product x month grain over 400 days: the p75 half-split gap collapses 0.148 -> 0.058 between the 40-79 and 80-159 raw-order buckets, so 80 raw orders is the stability break; converted to weighted units at the measured median weighted_orders / orders_90_settled ratio of 1.58 across the nine covered products, 80 x 1.58 = 126, taken as 125. A PRECISION REQUIREMENT counted in ORDERS, not a shrink prior counted in clicks -- do not substitute INTENT_CVR_BASE_PRIOR_CLICKS, INTENT_CVR_SEASON_PRIOR_CLICKS or INTENT_PHASE_PRIOR_CLICKS. Applied at both the product and family rung on purpose: it asks whether a bucket holds enough orders for its mean to be stable, which is a question about n and not about the key.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN');
