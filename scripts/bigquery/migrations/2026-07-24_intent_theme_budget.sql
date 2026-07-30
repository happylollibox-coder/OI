-- 2026-07-24 — review pass 4, found by Ori on the Intent Configuration page.
--
-- "gifts for girls 8-12 deals" was resolving to tween-gift. The word "deals" is price intent,
-- which the vocabulary had no word for at all — so deal-seekers were being folded in with
-- full-price shoppers and priced identically.
--
-- Measured over the trailing 365 days, price-qualified queries against everything else:
--
--                   terms    clicks    CVR     CPC    GP/click   GP-ROAS
--   price intent     3,789     8,438   1.47%   $0.34    $0.302      0.90
--   everything else 197,350  825,147   3.99%   $0.52    $0.696      1.33
--
-- 37% of the conversion rate, and the only bucket in the account that loses money on a gross
-- profit basis. The direct bleed is small (~$320/yr) but the real damage is contamination:
-- mixing deal-seekers into tween-gift depresses that theme's base_cvr, so V_INTENT_BID_BASE
-- underbids the genuinely good tween traffic to compensate for traffic that should not be
-- bought at all.
--
-- PRIORITY 4 — immediately after asin/auto-target (1), brand (2) and competitor (3), and ahead
-- of every topical theme. Price sensitivity is the strongest CVR predictor found so far in this
-- account (2.7x), so it belongs near the top of the resolution order.
--
-- TWO THEMES because specificity is compared before priority:
--   budget-gift (price AND gift) = specificity 2, so it ties tween-gift's 2 and wins on
--                                  priority. This is the common case.
--   budget      (price alone)    = specificity 1, catching non-gift price queries like
--                                  "cheap school supplies".
--
-- KNOWN LIMITATION: price is really a MODIFIER, like age — "cheap birthday gifts for a 10 year
-- old" still resolves to tween-birthday-gift (specificity 3) and the price signal is lost.
-- The correct fix is a price flag on the curve grain rather than a competing theme, so the
-- model can learn "tween-gift, price-sensitive" as distinct from "tween-gift". Logged as a
-- follow-up; this migration handles the common case.
--
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

DELETE FROM `onyga-482313.OI.DE_INTENT_THEMES` WHERE intent_key IN ('budget', 'budget-gift');

INSERT INTO `onyga-482313.OI.DE_INTENT_THEMES`
  (intent_key, label, intent_type, match_ads_regex, match_keyword_regex, cross_family,
   is_active, priority, notes, created_at, updated_at)
VALUES
  ('budget-gift', 'Budget Gift', 'GENERIC',
   r'\bdeals?\b|\bcheap(er|est)?\b|\bbudget\b|\bon sale\b|\baffordable\b|\binexpensive\b|under \$?\d|\$\d+|\bdollar\b|\bbargain\b|\bdiscount',
   r'\b(gifts?|presents?|regalos?)\b',
   FALSE, TRUE, 4,
   'Price-qualified gift queries. Found by Ori 2026-07-24 on "gifts for girls 8-12 deals" (3,418 clicks, 1.8% CVR vs 3-4.4% for the same tween-gift terms without a price word). Price intent overall: 1.47% CVR and 0.90 GP-ROAS vs 3.99% and 1.33. Specificity 2 so it beats tween-gift on priority.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),

  ('budget', 'Budget / Deal Seeker', 'GENERIC',
   r'\bdeals?\b|\bcheap(er|est)?\b|\bbudget\b|\bon sale\b|\baffordable\b|\binexpensive\b|under \$?\d|\$\d+|\bdollar\b|\bbargain\b|\bdiscount',
   NULL,
   FALSE, TRUE, 4,
   'Price-qualified queries with no gift word ("cheap school supplies"). Specificity 1, so any two-condition theme still outranks it — deliberate, it is the catch-all arm.',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
