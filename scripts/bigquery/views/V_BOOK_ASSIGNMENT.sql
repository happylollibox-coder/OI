-- =============================================
-- V_BOOK_ASSIGNMENT — which book each family is in (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §2.
--
-- HARVEST IS THE DEFAULT AND THAT IS THE POINT. A family becomes INVEST only through a live
-- declaration in DE_LAUNCH_INVESTMENT. Undeclared spend is Harvest spend and is judged on money like
-- everything else — which is what makes an undeclared launch immediately visible instead of quietly
-- exempt. Expiry needs no code change: past stop_date the family simply reverts to Harvest.
--
-- THE BINDING CONSTRAINT IS daily_investment, THE SPEND RATE (Ori 2026-08-19: "spend rate binds").
-- That is the number actually sanctioned. monthly_loss_ceiling rides along as a catastrophe backstop
-- because a net-profit ceiling on a product that nearly covers its costs almost never fires —
-- measured 2026-08-19, both families ran 1.5-1.8x over sanctioned spend while losing only $259 and
-- $74 against ceilings of $913 and $1,674.
--
-- AGE COMES FROM FIRST SALE, NOT FROM THE DECLARATION. sanctioned_on is when Ori signed the
-- investment off (2026-08-13 for both families), months after either launch actually began. Same
-- first-sale definition as V_LAUNCH_EXEMPTION / V_PRODUCT_LAUNCH_MODEL so nothing can disagree.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BOOK_ASSIGNMENT` AS
WITH fam AS (
  -- 'Unknown' is NOT a family. It is the literal fallback V_CAMPAIGN_FAMILY_MAP emits
  -- (COALESCE(cf.parent_name, af.parent_name, 'Unknown')) for a campaign whose family it cannot
  -- resolve — 9 of 97 enabled campaigns on 2026-08-19. It has no row in V_UNIFIED_DAILY and so no
  -- row in V_FAMILY_PNL, the measurement spine. Admitting it here would hand the two-book system a
  -- seventh "family" with a book but no P&L to judge it against, and every downstream join would
  -- carry the orphan. Unmapped ad spend is a campaign-MAPPING coverage problem, surfaced by the
  -- Campaign Mapping panel, not a book to assign. Excluding it makes this view's family universe
  -- exactly V_FAMILY_PNL's, so the two can never disagree about who exists.
  SELECT DISTINCT parent_name AS family
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`
  WHERE parent_name IS NOT NULL
    AND parent_name != 'Unknown'
),
first_sale AS (
  SELECT family, MIN(date) AS first_sale_date
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE units > 0 AND family IS NOT NULL
  GROUP BY family
),
decl AS (
  SELECT
    parent_name AS family,
    daily_investment,                      -- THE binding sanction
    monthly_loss_ceiling,                  -- catastrophe backstop only
    takeover_target_organic_units,         -- NULL until Ori supplies it
    stop_date,
    sanctioned_on,
    (CURRENT_DATE('America/Los_Angeles') <= stop_date) AS in_window
  FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`
  -- one live declaration per family; newest sanction wins if two ever overlap
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY sanctioned_on DESC) = 1
)
SELECT
  f.family,
  IF(COALESCE(d.in_window, FALSE), 'INVEST', 'HARVEST')                     AS book,
  COALESCE(d.in_window, FALSE)                                             AS declaration_valid,
  d.daily_investment,
  d.monthly_loss_ceiling,
  d.takeover_target_organic_units,
  d.stop_date,
  d.sanctioned_on,
  fs.first_sale_date,
  -- RAMP vs PROOF selector in V_INVEST_STATUS, measured from the launch, not the paperwork
  IF(fs.first_sale_date IS NULL, NULL,
     DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), fs.first_sale_date, MONTH)) AS launch_age_months
FROM fam f
LEFT JOIN decl d       ON d.family  = f.family
LEFT JOIN first_sale fs ON fs.family = f.family;
