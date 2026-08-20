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
-- only, and WHY IT ALMOST NEVER FIRES IS A PROPERTY OF HOW IT WAS DERIVED, not a reading of a
-- particular day: the ceiling was backfilled as the sanctioned SPEND rate monthised, and a launch
-- family with real sales loses far less than it spends, so it is a loose bound by construction. A
-- family can therefore sit a long way inside its ceiling while running well over its sanctioned
-- daily rate — which is exactly why the rate is the clause that binds.
--
-- NO RATE, RATIO OR CEILING PERCENTAGE IS WRITTEN IN THIS HEADER (Standing Rule 0 — describe the
-- mechanism, publish the query, never pin a measurement; the figures that used to sit here moved
-- twice in two days, once because the rate moved and once because the WINDOW under it was replaced).
-- Run this instead, and NEVER restore a sanctioned value from a number written in a file:
--   SELECT family, daily_investment, spend_per_day, spend_rate_ratio, ceiling_used_pct,
--          rate_window_basis, protection_qualified
--   FROM `onyga-482313.OI.V_INVEST_STATUS`;
-- (Column names checked against INFORMATION_SCHEMA. This header once published a query naming
-- times_over_agreed_rate and loss_allowance_used_pct_so_far, which had been renamed away — it did
-- not fail quietly, it failed to compile.)
--
-- AGE COMES FROM FIRST SALE, NOT FROM THE DECLARATION. sanctioned_on is when Ori signed the
-- investment off (2026-08-13 for both families — a declared date on DE_LAUNCH_INVESTMENT, not a
-- measurement), months after either launch actually began.
--
-- SAME ANCHOR AS V_LAUNCH_EXEMPTION, DELIBERATELY DIFFERENT UNITS — AND THEY WILL NOT MATCH
-- (corrected 2026-08-20; this comment used to claim "so nothing can disagree", which was false).
-- Both views date the launch from the family's first sale in V_UNIFIED_DAILY, so the ANCHOR is
-- shared and neither can invent a different launch date. The UNITS are not shared and are not meant
-- to be: this view counts CALENDAR-MONTH boundaries crossed (DATE_DIFF ... MONTH, a whole number),
-- V_LAUNCH_EXEMPTION divides elapsed days by 30.44 (one decimal). EXPECT A GAP OF UP TO ABOUT A
-- MONTH, in either direction, and never treat a difference as a defect. Compare them yourself
-- rather than reading two numbers out of this comment:
--   SELECT family, first_sale_date, launch_age_months FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`;
--
-- WHY THE CALENDAR COUNT IS RIGHT HERE, AND MUST NOT BE "HARMONISED" TO THE OTHER ONE: this number
-- selects RAMP vs PROOF in V_INVEST_STATUS, a test that reads COMPLETE CALENDAR MONTHS. Counting
-- month boundaries lands the change on the 1st, the same grain the measurement uses, instead of
-- mid-month on an arbitrary day. It is also the pattern already used in V_LOW_STOCK_ADS.sql:860.
-- THE FLIP DATE IS A RULE, NOT A DATE TO WRITE DOWN: a family moves RAMP -> PROOF on the FIRST of
-- the calendar month in which DATE_DIFF(today, first_sale_date, MONTH) reaches 4. Derive it from the
-- query above. (Under elapsed-days/30.44 the same flip would land mid-month, splitting the very
-- month the trajectory test measures — which is the whole reason this view counts boundaries.)
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BOOK_ASSIGNMENT` AS
WITH fam AS (
  -- 'Unknown' is NOT a family. It is the literal fallback V_CAMPAIGN_FAMILY_MAP emits
  -- (COALESCE(cf.parent_name, af.parent_name, 'Unknown')) for a campaign whose family it cannot
  -- resolve. How many campaigns are in that bucket today is a measurement and is not written here;
  -- count it with SELECT COUNTIF(parent_name = 'Unknown'), COUNT(*) FROM
  -- `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`. It has no row in V_UNIFIED_DAILY and so no
  -- row in V_FAMILY_PNL, the measurement spine. Admitting it here would hand the two-book system a
  -- seventh "family" with a book but no P&L to judge it against, and every downstream join would
  -- carry the orphan. Unmapped ad spend is a campaign-MAPPING coverage problem, surfaced by the
  -- Campaign Mapping panel, not a book to assign.
  --
  -- THIS DOES NOT MAKE THE TWO FAMILY UNIVERSES THE SAME, AND AN EARLIER VERSION OF THIS COMMENT
  -- CLAIMED IT DID (corrected 2026-08-20). Excluding 'Unknown' removes the ONE sentinel they were
  -- guaranteed to differ on; it does not align the keys. This view is CAMPAIGN-keyed (through
  -- V_CAMPAIGN_FAMILY_MAP), ENABLED-campaign-only, override-first and not windowed. V_FAMILY_PNL is
  -- ASIN-keyed (through DIM_PRODUCT) over a dated window. TWO LIVE DIVERGENCE MECHANISMS, either of
  -- which can open on any day:
  --   · DE_CAMPAIGN_FAMILY can override a campaign to a parent_name that NO ASIN carries. While
  --     every such campaign is PAUSED the value does not reach this view; enable one and this view
  --     publishes a family with a book and no P&L to judge it against. That is not a hypothetical —
  --     override rows of that shape are already in the table.
  --   · an ASIN with oi_is_active = TRUE can carry parent_name NULL, so its sales belong to no
  --     family on either side.
  -- Whether either is open TODAY is a measurement, not an invariant, and it is not written here.
  -- Check it: SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` against
  -- SELECT DISTINCT family FROM `onyga-482313.OI.V_FAMILY_PNL` — the two lists may differ.
  -- V_TWO_BOOK_BRIEF therefore joins the two universes with a FULL OUTER JOIN (review round 1,
  -- 2026-08-20) so a family present on one side and absent on the other is published rather than
  -- silently joined away. DO NOT SIMPLIFY THAT JOIN to an inner or left join because the two
  -- universes "look identical" on the day you check.
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
  -- TIE-BREAK MUST MATCH V_LAUNCH_EXEMPTION EXACTLY (fixed 2026-08-19 after Task 3 review).
  -- Both views answer "which declaration is live" off the same table, and about THAT they really
  -- must not disagree — which declaration is live is a fact, not a unit of measurement — so the
  -- ordering has to be identical, not merely similar. (Re-verified 2026-08-20: both order by
  -- updated_at DESC NULLS LAST, stop_date DESC, daily_investment DESC — V_LAUNCH_EXEMPTION.sql:120.
  -- This is the ONE thing the two views are pinned together on; their family universes and their
  -- age UNITS are not, see the header.) The table's own
  -- documented convention is "re-sanctioning = INSERT a row with a later updated_at (latest wins)",
  -- and V_LAUNCH_EXEMPTION orders by updated_at DESC NULLS LAST, stop_date DESC, daily_investment
  -- DESC. Ordering by sanctioned_on instead was harmless today (exactly one row per family) but
  -- would have named a different declaration live the moment Ori inserts a correction — the exact
  -- disagreement this design exists to prevent. The trailing keys break the tie between two rows
  -- sharing an updated_at. THEY DO NOT MAKE THE PICK TOTAL, and an earlier version of this comment
  -- claimed they did (corrected 2026-08-20 in the same sweep that deleted this file's two other
  -- false invariants). Three rows for one family sharing updated_at AND stop_date AND
  -- daily_investment would still coin-flip. AND THE SHARED ORDERING DOES NOT CLOSE THAT — a previous
  -- version of this comment said "BOTH views coin-flip the SAME way off the same ordering, so they
  -- cannot pick different declarations", and that claim is false (corrected 2026-08-20). These are
  -- two independently planned, independently executed queries. A shared ORDER BY makes them agree on
  -- the ORDERING; across rows tied on every ordering key it says nothing about WHICH tied row each
  -- one keeps, and BigQuery promises nothing there. Over a full tie the two views CAN name different
  -- declarations live. THAT RISK IS STATED, NOT ELIMINATED, and it is left open deliberately: the
  -- only fix is a unique trailing key added to BOTH views in ONE commit, and V_LAUNCH_EXEMPTION is
  -- under Ori's 2026-08-20 "release nothing" hold and may not be edited. So the residual stands and
  -- is written down here rather than papered over. IS IT REACHABLE TODAY? No. Re-derived 2026-08-20
  -- against the live table: 2 rows, 2 families, 1 row per family, and 0 (parent_name, updated_at,
  -- stop_date, daily_investment) groups with more than one row — nothing ties, so neither view has a
  -- choice to make. The risk opens only if Ori ever inserts two rows for one family sharing all three
  -- ordering keys. Re-run before relying on that:
  --   SELECT COUNTIF(n > 1) AS tied_groups FROM (SELECT COUNT(*) n
  --     FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`
  --     GROUP BY parent_name, updated_at, stop_date, daily_investment);
  -- When the hold lifts, the deterministic fix is a unique trailing key (e.g. sanctioned_on, then a
  -- row identifier) added to the ORDER BY of BOTH views in one commit, never to one alone.
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY parent_name
    ORDER BY updated_at DESC NULLS LAST, stop_date DESC, daily_investment DESC) = 1
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
