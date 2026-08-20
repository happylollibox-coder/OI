-- =============================================
-- V_TWO_BOOK_BRIEF — the morning read: two books, never blended (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §6.
--
-- THE POINT OF THE WHOLE DESIGN IS THIS ONE SENTENCE. July 2026 read as "the account lost $5,612",
-- which was never true: it was Harvest earning money while a deliberate, undeclared launch
-- investment spent some of it, and an ads-attributed lens that excluded 30-40% of units. Including
-- the organic halo, July made +$3,682. The brief reports "Harvest earned X; Invest spent Y of its
-- declared budget" and NEVER adds those two together.
--
-- THE TWO BOOKS ARE NEVER ADDED. There is one TOTAL row PER BOOK and there is no grand total, by
-- construction: the totals are built off a two-row book spine and nothing in this view ever
-- aggregates across `book`. A single combined number would recreate the exact lie this design
-- exists to kill, so the acceptance assertion pins total_rows = 2 forever.
--
-- NET PROFIT LEADS, THE RATIO EXPLAINS IT (Ori's framing is total dollars). Bottle and Fresh look
-- like the same problem by ratio but cost $8 and $1,776 over the 90-day window — ranked by ratio you
-- fix Bottle, ranked by dollars you fix Fresh, and Fresh is the right answer. So the Harvest losers
-- are RANKED BY DOLLARS and the worst one is named in its own verdict and in the book total; and a
-- loss smaller than the breakeven band is called noise in words, so an $8 loss can never read as a job.
--
-- THE INVEST ROWS DO NOT CARRY A PROFIT VERDICT. Months 0-3 are judged on improvement, never on
-- profitability (Ori 2026-08-19: "the question of launch products is are they improving — not are
-- they profitable — in the first 3 months"). So an Invest verdict says four things and no fifth: the
-- spend rate against what was sanctioned, whether the launch still QUALIFIES for protection under
-- that sanction, whether the coach is actually ENFORCING protection (and what it is holding back if
-- it is), and the organic trajectory in absolute units. Its net_profit column is still published — it
-- is the cost of the investment, and the verdict frames it as money agreed to, not as a loss to chase.
--
-- WINDOW HONESTY: the P&L columns are the settled 90-day window; the spend rate is MONTH-TO-DATE,
-- because a rate must be current to bind. The two are deliberately different windows, so every
-- verdict string says which one it is quoting ("over the last 90 days" vs "so far this month") and
-- both windows ride on the row as money_window and rate_window. Do not silently align them — a
-- 90-day average spend rate would not bind on anything.
--
-- VERDICTS ARE PLAIN SENTENCES ON PURPOSE. No rule names, no engine internals, no bare metric codes:
-- ROAS is written as "$1.41 back for every ad dollar", the halo as "the organic sales those ads pull
-- in", the exemption as "launch protection". Ori has repeatedly filed unreadable output as a defect
-- against the page, and he is right to. If you add a branch here, read it aloud before you deploy.
--
-- ---------------------------------------------------------------------------------------------
-- 2026-08-20 (ROUND 1) — SEVEN REVIEW FINDINGS CLOSED.
--   1. The spine became a FULL OUTER JOIN of the two family universes, so a declared family with no
--      measured P&L gets a visible row instead of being joined away behind a confident total.
--   2. sort_order and loss_rank are published; the morning read no longer arrives shuffled.
--   3. The windows are on the row (money_window / period_start / period_end, and rate_window), not
--      only inside the prose.
--   4. The advertising that reaches NEITHER book is published and named in the harvest verdict.
--   5. The NULL branch leads the harvest CASE, so an unmeasured family cannot print a blank line.
--   6. The raw token 'RAMP' became launch_stage in words; the sanctioned rate stopped rounding
--      inside the one instruction on the object that tells Ori to do something.
--   7. The trajectory is projected, and both book totals name the families their money leaves out.
--
-- 2026-08-20 (ROUND 2) — WHAT THE ADVERSARIAL REVIEW FOUND AFTERWARDS, AND WHAT CHANGED.
--
-- A. "MEASURED" NOW MEANS THE MONEY IS THERE, NOT THAT A ROW IS THERE (critical). Round 1 defined
--    measured as "this family has a P&L row". A row whose net_profit is NULL but whose ad_spend is
--    not — the exact shape of a launch advertising before its first mapped sale, since V_FAMILY_PNL
--    computes profit as SUM(sales - cogs) - SUM(ad_cost) and the first term is NULL when nothing is
--    mapped — therefore counted as measured, and EVERY honesty mechanism switched off at once: the
--    book total paired a 3-family profit with a 4-family spend and called it "across 4 families",
--    the unmeasured-family clause was suppressed, a genuinely losing family fell out of the "fix
--    this first" queue so the total could say "none of them is losing real money", and the family
--    row asserted "no ad spend" beside a column showing $13,782.
--    A PARTIALLY MEASURED FAMILY IS NOT MEASURED. money_measured requires BOTH money columns. When
--    it is false, every money column on the row is NULL — half a P&L published as if it were a whole
--    one is worse than a blank, because it silently changes what the total means — and the verdict
--    says WHICH half is missing. Both book sums are taken over exactly that same money_measured
--    subset, so the count in the sentence, the two money columns and the reconciliation all describe
--    one identical set of families. money_measured is published, so a machine can see the state too
--    instead of having to parse an English sentence.
--
-- B. THE INVEST BOOK CONTRADICTED ITSELF, AND THE REASSURING HALF LANDED LAST (critical, and older
--    than round 1). The total said "Every one of them is over its agreed rate, so none is protected
--    right now." and then immediately "The $3,622 they cost is money you agreed to spend while they
--    build, not a loss to chase." Read aloud, the second sentence cancels the first — and it was not
--    even true of the money: at $151.70/day against $85/day approved, a large part of the current
--    burn was never agreed to. The family rows carried the mirror image: "now judged on money like
--    every other family" followed three sentences later by "what matters is whether it is improving,
--    not whether it is profitable yet." The single question this book exists to answer is whether a
--    launch is currently being judged on money or exempted from it, and the page answered it twice,
--    differently. Now: when anything is over its rate, the cost sentence keeps the agreement but ends
--    on the overspend and what to do about it; and the age clause is subordinated to the protection
--    state instead of contradicting it.
--
-- C. ONE RAW INTERNAL CODE WENT OUT AND ANOTHER CAME IN. Round 1 removed 'RAMP' from 2 rows and
--    round 1's own window fix published period_label = 'M3' on all 8. Same defect, wider. The column
--    is now money_window, in words: "the settled 90 days to 17 August 2026".
--
-- D. THE COVERAGE CLAUSE WAS THE ONLY SENTENCE ON THE PAGE WITH NOTHING TO DO. Every other verdict
--    ends in a next step, and the two sibling sentences about this same root cause both end "check
--    the product mapping". It does now too.
--
-- E. THE COVERAGE COLUMNS ARE ON THE HARVEST TOTAL ONLY. They are account-level and belonged to
--    neither book, so round 1 put them on both TOTAL rows — where anyone reading columns rather than
--    prose sees $8,765 twice and adds it to $17,530, on the one row that carries no sentence
--    explaining what it is. One row carries the sentence, so one row carries the columns.
--
-- F. THE COLUMN NAMES ARE THE LEGEND. org_m2/org_m1/org_m0 counted DOWN while their values ran
--    FORWARD in time, and takeover_target_organic_units / ceiling_used_pct / spend_rate_ratio were
--    engine vocabulary in a grid whose stated rule is plain English. Renamed to say what they are.
--
-- G. THE TOTAL ROWS NO LONGER COERCE AN UNMEASURED BOOK TO ZERO, and their verdicts guard on the
--    money being NULL rather than only on the family count — the same two defects round 1 fixed on
--    the family rows, left standing one level up on the row that is hardest to notice is wrong.
--
-- H. PLANNER. The view is read through a fan-out over V_UNIFIED_DAILY, and BigQuery inlines a CTE at
--    every reference, so `base` — which joins THREE such views — was being expanded four times
--    (lr, worst, agg, fam). loss_rank and the worst-loser lookup are now window functions and an
--    ARRAY_AGG computed in the passes that already existed, so base is expanded TWICE. That also
--    removes the fam-to-lr self-join, which squared any future duplicate upstream row into four
--    identical family rows and two wrong money columns while total_rows sat at 2 looking fine.
--    THE CEILING IS STILL REAL AND STILL BINDS ON CONSUMERS — see the block above the final SELECT.
--
-- 2026-08-20 (ROUND 3) — THE BRIEF CLAIMED AN ENFORCEMENT THAT IS NOT HAPPENING (critical).
--   Both Invest family rows and the Invest total spoke in the present indicative about an effect no
--   machine was producing: "it has lost its launch protection and is now judged on money like every
--   other family", and "Every one of them is over its agreed rate, so none is protected right now."
--   Verified the same morning: V_LAUNCH_EXEMPTION — the object the coach actually reads — returns
--   protection ACTIVE on all 14 launch campaigns (Bunny 6 to 31 October, LolliBall 8 to 30 November),
--   because exempt_active is a hardcoded TRUE and the coach's gate keys on campaign presence alone; it
--   reads neither that flag nor V_INVEST_STATUS.exemption_live. On the strength of that protection the
--   coach was holding 10 budget cuts covering $188.86 a day (Bunny 4 / $59.00, LolliBall 6 / $129.86).
--   So Ori would read "now judged on money", conclude the trimming had started, leave the budgets
--   alone, and the only instruction on the row asked him to restore a protection nobody had withdrawn.
--
--   TWO STATES, NOT ONE, AND BOTH AS NUMBERS. Being over the sanction and being cut are different
--   facts and this object may never again publish one as the other. protection_qualified is what the
--   sanction rules say (V_INVEST_STATUS.exemption_live, which fails closed); protection_enforced is
--   what the machine is doing; cuts_the_coach_is_holding and budget_those_cuts_cover are the size of
--   the gap in dollars, on the family row AND on the book total, because that is the number Ori acts
--   on. Every Invest sentence now states both, and states them apart. The old exemption_live column is
--   gone: one word cannot carry two states, and "live" was the ambiguity itself.
--   THE ENGINE WAS NOT TOUCHED. Ori 2026-08-20: "Tell the truth now, release nothing." Wiring the
--   sanction to the coach is Task 8b and Task 8b is not built; until it is, the only thing standing
--   between an over-sanction launch and the money is a person reading this row, and the row now says
--   so out loud instead of implying otherwise.
--
--   WHERE THE ENFORCEMENT FACT COMES FROM, AND WHY NOT FROM THE OBVIOUS PLACE. This view sits AT
--   BigQuery's planning ceiling, so every source was measured alone before it was joined.
--   V_COACH_CAMPAIGN_BUDGET — the view that carries the held decisions — dry-runs at 283,900,961 bytes
--   and takes ~47s just to PLAN and ~113s to run; inlining it here would have been the same fatal move
--   that stopped V_PANEL_OWNERSHIP planning on 2026-08-17. Its daily materialisation
--   T_COACH_CAMPAIGN_BUDGET is 78 rows and 10 KB, built by SP_REFRESH_CUBE_TABLES in the same daily
--   pass, and carries every column needed — so no new table and no orchestrator change were required.
--   V_LAUNCH_EXEMPTION is genuinely light (17,551,398 bytes, ~3s) and is the authority the coach reads,
--   so it is joined directly. Measured: 82,048,475 -> 82,249,465 dry-run bytes (+0.2%), plan 5.7s ->
--   4.5s. BOTH sources are read, deliberately: either one alone can be silent about a family the other
--   can see, and a protection state that cannot be observed must read NULL, never FALSE — "we could
--   not check" is not "the coach has stopped", and it is the second of those two that would put the
--   original lie straight back on the page.
-- ---------------------------------------------------------------------------------------------
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_TWO_BOOK_BRIEF` AS
WITH k AS (
  SELECT
    -- A loss smaller than this share of the family's OWN ad spend is noise, not a job. Declared
    -- tunable, not a buried constant: it is the thing that stops Bottle's $8 reading like Fresh's
    -- $1,776 just because both ratios sit under 1.0.
    0.05 AS breakeven_band,
    -- Above this measured halo the ads-only number is misleading enough that the verdict says so out
    -- loud. Bottle reads 1.59 — the strongest in the account — and cutting it on the ads number is
    -- precisely the mistake this whole design exists to prevent.
    1.30 AS wide_halo
),
pnl AS (
  -- The window is carried THROUGH TO THE OUTPUT on purpose. This view publishes two different
  -- windows side by side and used to name them only inside the prose, so a reader scanning the grid
  -- — which is what a grid is for — compared a 90-day profit against a 17-day rate with nothing on
  -- screen to stop them. The window is now a column, and it is a sentence rather than the code 'M3'.
  SELECT family, period_start, period_end,
         net_profit, total_net_roas, ads_net_roas, halo_factor, organic_pct, ad_spend
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'          -- settled 90 complete days, same window the bars are set from
),
-- The book spine. Both books are published EVERY day even when one is empty, so the shape of the
-- brief never changes under Ori and total_rows is structurally 2 rather than data-dependent. An
-- empty Invest book is a real and useful sentence ("nothing is on approved launch investment").
books AS (SELECT 'HARVEST' AS book UNION ALL SELECT 'INVEST' AS book),
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE SPEND THAT REACHES NEITHER BOOK. Measured on the same 90-day window: the account spent
-- $94,579 on advertising; $85,814 of it reached a family; $8,765 — 9.3% — reached none, all of it on
-- advertised ASINs that carry no family name. It reconciles exactly (94,579 - 8,765 = 85,814 = the
-- two book ad_spend totals summed). That money was in NEITHER book and this object said nothing
-- about it, while presenting its spend total as though it were the account's advertising. The
-- founding complaint behind this whole design is a number that lied by omission; a silent 9.3% is
-- the same defect wearing a smaller coat.
-- IT IS NOT A THIRD ROW. A third row_kind would break the structural total_rows = 2 guarantee, which
-- is this design's single best property. It rides as two COLUMNS on the HARVEST TOTAL row plus one
-- clause in that row's verdict. ON THAT ROW ONLY: the money belongs to neither book, so it cannot be
-- apportioned to one, and publishing it on both totals invited a reader scanning columns to add
-- $8,765 to itself. One row carries the sentence, so one row carries the columns.
-- WHY THIS SOURCE: the window comes from `pnl` itself, so the coverage figure and the P&L can never
-- drift onto different windows — a recomputed watermark here would have been a second definition of
-- the same date. The spend comes straight off FACT_AMAZON_ADS joined to the same ASIN-to-family map
-- V_UNIFIED_DAILY uses, which is the lightest source that reproduces the number exactly (verified
-- 2026-08-20: attributed side matches V_UNIFIED_DAILY's family ad_cost to the cent, 85,813.31).
-- ─────────────────────────────────────────────────────────────────────────────────────────────
win AS (SELECT MIN(period_start) AS s, MAX(period_end) AS e FROM pnl),
cov AS (
  SELECT
    ROUND(SUM(IF(fm.asin IS NULL, a.Ads_cost, 0)), 0)                                AS unattributed_spend,
    ROUND(100 * SAFE_DIVIDE(SUM(IF(fm.asin IS NULL, 0, a.Ads_cost)),
                            NULLIF(SUM(a.Ads_cost), 0)), 2)                          AS spend_coverage_pct
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN win w
  -- Same ASIN resolution V_UNIFIED_DAILY applies, so "reached a family" means the same thing here as
  -- it does in every money column on this page.
  LEFT JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    ON fm.asin = COALESCE(a.most_advertised_asin_impressions, a.advertised_asins, a.ASIN_BY_CAMPAIGN_NAME)
  WHERE a.date BETWEEN w.s AND w.e
),
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE SPINE IS THE UNION OF BOTH UNIVERSES, NOT THE P&L ALONE.
-- The two upstream universes are keyed differently and CAN disagree: V_FAMILY_PNL's families come
-- from V_UNIFIED_DAILY, which is ASIN-keyed through DIM_PRODUCT; V_BOOK_ASSIGNMENT's come from
-- V_CAMPAIGN_FAMILY_MAP, which is campaign-keyed, and it is not windowed at all while this P&L is
-- cut to the settled 90 days. A family that has a book but no measured P&L used to be joined away by
-- an inner spine — and the book total still printed a fluent, confident, complete sentence with no
-- sign that anything was missing. That is not theoretical: a newly declared INVEST family whose
-- ASINs do not yet carry a parent_name has no row on this window at all, so the one family this
-- whole design exists to keep visible would have been invisible while spending real money every day.
-- (One entrance to that failure is still open ABOVE this view: a family sanctioned in
-- DE_LAUNCH_INVESTMENT whose campaigns are not yet mapped resolves to 'Unknown' inside
-- V_CAMPAIGN_FAMILY_MAP and is dropped before V_BOOK_ASSIGNMENT ever sees it. This spine cannot
-- reach it; the mapping has to.)
--
-- MEASURED MEANS THE MONEY IS THERE. A family can hold a P&L row with only half a P&L on it — ad
-- spend counted, sales not — and that half is exactly what a launch looks like before its first
-- mapped sale. Publishing the half we have would put a 4-family spend beside a 3-family profit on
-- one TOTAL row and call it complete. So when either money column is missing, ALL of them are NULL
-- (never zero — zero claims "measured, and it was nothing", which is a different and false
-- statement), the row is excluded from both book sums, and the verdict says which half is missing.
-- SUM ignores NULLs, so an unmeasured family can neither move a book total nor open a gap in the
-- reconciliation — it can only be seen.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- WHAT THE MACHINE IS ACTUALLY DOING — read from the two lightest objects that carry it.
-- QUALIFYING FOR PROTECTION AND BEING PROTECTED ARE DIFFERENT FACTS. V_INVEST_STATUS answers the
-- first: is this launch inside the rate, the date and the loss allowance Ori sanctioned. Nothing
-- reads that answer. The coach's gate keys on a campaign being present in V_LAUNCH_EXEMPTION, whose
-- exempt_active is a hardcoded TRUE, so a launch keeps its protection however far over sanction it
-- runs. These two CTEs measure the second fact so the brief can print both and never conflate them.
--
-- TWO SOURCES ON PURPOSE, AND NEITHER IS REDUNDANT. V_LAUNCH_EXEMPTION is the authority the coach
-- reads and it is campaign-complete for protected campaigns (Bunny 6, LolliBall 8 @ 2026-08-20).
-- T_COACH_CAMPAIGN_BUDGET is where the CONSEQUENCE lives — the decisions the exemption suppressed and
-- the budget they cover — but it holds only campaigns that reached a budget decision (5 and 6 of those
-- same campaigns), so it can be silent about a protected campaign the exemption view can see. Reading
-- both means "no evidence anywhere" stays distinguishable from "evidence that the coach has let go",
-- which is the whole point: FALSE here would reprint the exact claim this round exists to remove.
--
-- WHY THE TABLE AND NOT THE VIEW. V_COACH_CAMPAIGN_BUDGET dry-runs at 283,900,961 bytes, ~47s to plan
-- and ~113s to run, and this view is already at the planning ceiling. Its daily materialisation is 78
-- rows / 10 KB and is built by SP_REFRESH_CUBE_TABLES in the same daily pass that feeds everything
-- else here, so it costs essentially nothing and needs no new object (house pattern for planner
-- blowups: never inline a ceiling view, read the T_ built earlier in the pass).
-- THE FIGURES ARE AS OF THAT DAILY BUILD, like every other coach number in the account.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
enf AS (
  -- The exemption the coach reads. A family with no row here has no protected campaign today: the
  -- upstream view already filters to campaigns still inside their exemption window.
  SELECT family, COUNTIF(exempt_active) AS campaigns_protected
  FROM `onyga-482313.OI.V_LAUNCH_EXEMPTION`
  GROUP BY family
),
held AS (
  -- What that protection is costing in withheld decisions. budget_action_suppressed records exactly
  -- what the coach WOULD have done — a campaign stop or a budget decrease — and current_budget is the
  -- daily money still flowing because it did not. Summed to the family, that is the number to act on.
  SELECT
    parent_name                                                                 AS family,
    COUNTIF(launch_exempt)                                                      AS campaigns_protected,
    COUNTIF(budget_action_suppressed IS NOT NULL)                               AS cuts_held,
    ROUND(SUM(IF(budget_action_suppressed IS NOT NULL, current_budget, 0)), 2)  AS cuts_budget
  FROM `onyga-482313.OI.T_COACH_CAMPAIGN_BUDGET`
  GROUP BY parent_name
),
base AS (
  SELECT
    -- HARVEST IS THE DEFAULT (V_BOOK_ASSIGNMENT header). A family with no book row is Harvest, not a
    -- third book: COALESCE here keeps its money inside the Harvest total instead of letting a NULL
    -- book silently open a third TOTAL group and drop the dollars out of the reconciliation.
    COALESCE(bk.book, 'HARVEST')                                        AS book,
    COALESCE(p.family, bk.family)                                       AS family,
    -- BOTH money columns, or the family is not measured. See the block above.
    (p.net_profit IS NOT NULL AND p.ad_spend IS NOT NULL)               AS money_measured,
    -- Kept apart from money_measured so the verdict can say WHICH of the three states this is:
    -- no row at all, a row with no profit side, or a row with no advertising side. They must be read
    -- off the UPSTREAM columns, not off the published ones: an unmeasured row has both money columns
    -- blanked below, so asking the published columns which half is missing always answers "both" —
    -- which is how round 1's sentence came to assert "no ad spend" over a family that had $13,782 of it.
    (p.net_profit IS NOT NULL)                                          AS pnl_has_profit,
    (p.ad_spend   IS NOT NULL)                                          AS pnl_has_spend,
    -- The window behind every money column on this row, in words. NULL on a family with nothing
    -- measured, which is itself the correct statement: no window was measured for it.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       CONCAT('the settled ', CAST(DATE_DIFF(p.period_end, p.period_start, DAY) + 1 AS STRING),
              ' days to ', FORMAT_DATE('%-d %B %Y', p.period_end)))     AS money_window,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.period_start) AS period_start,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.period_end)   AS period_end,
    -- Half a P&L is published as no P&L. The raw halves are still reachable one view upstream; what
    -- must never happen is a money column here that a book total does not contain.
    IF(p.ad_spend   IS NULL, NULL, ROUND(p.net_profit, 0))              AS net_profit,
    IF(p.net_profit IS NULL, NULL, ROUND(p.ad_spend, 0))                AS ad_spend,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, ROUND(p.total_net_roas, 2)) AS total_net_roas,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, ROUND(p.ads_net_roas, 2))   AS ads_net_roas,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, ROUND(p.halo_factor, 2))    AS halo_factor,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.organic_pct)              AS organic_pct,
    -- INVEST families are bar-exempt (V_FAMILY_BAR.bar_exempt): they are governed by budget and
    -- trajectory, not by a keyword bar. Printing their computed bar on the brief would imply a test
    -- that is not being applied, so it is blanked here rather than shown and explained away.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', NULL, ROUND(b.keyword_bar, 2)) AS keyword_bar,
    i.phase, i.launch_age_months, i.stop_date,
    i.daily_investment, i.mtd_spend_per_day, i.spend_rate_ratio, i.spend_breached,
    -- THE SANCTIONED RATE, WRITTEN THE WAY IT WAS AGREED. It used to be printed with FORMAT('$%.0f')
    -- inside the one instruction on the whole object that tells Ori to do something ("Bring spend
    -- back to $55 a day to restore it"). Harmless at $30 and $55; a $27.50 sanction would have
    -- printed an order to spend back to $28 — a wrong number in the only actionable sentence here.
    -- Whole dollars still read as whole dollars, and cents survive.
    IF(i.daily_investment = TRUNC(i.daily_investment),
       FORMAT("$%'d", CAST(i.daily_investment AS INT64)),
       FORMAT('$%.2f', i.daily_investment))                             AS daily_investment_text,
    -- exemption_live is NOT carried under its own name any more: it is one of two protection states
    -- and the old name claimed to be both. It is read once, below, as protection_qualified.
    i.ceiling_used_pct, i.days_left,
    i.org_m2, i.org_m1, i.org_m0, i.takeover_target_organic_units,
    -- NULL, not FALSE, when the family is unmeasured: "we did not measure it" is not "it is fine".
    -- COUNTIF and the loss ranking both skip NULLs, so an unmeasured family cannot be quietly
    -- counted as healthy — it is named as unmeasured instead, in the total's own sentence.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       (p.net_profit < 0 AND -p.net_profit > k.breakeven_band * p.ad_spend)) AS real_loss,
    (COALESCE(p.halo_factor, 0) >= k.wide_halo)                         AS wide_halo,
    -- ─── THE TWO PROTECTION STATES, KEPT APART ───
    -- QUALIFIED: what the sanction rules say. exemption_live is already the fail-closed answer —
    -- protection only on positive evidence of a rate on file, a measured spend at or under it, a loss
    -- ceiling on file and a measured loss under it. Renamed here because "live" reads as "in force",
    -- which is precisely the thing it does not mean.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.exemption_live, NULL)  AS protection_qualified,
    -- ENFORCED: what the machine is doing. TRUE if either source can see a protected campaign; FALSE
    -- only when a source has campaigns for this family and none of them is protected; NULL when
    -- neither source has heard of the family at all. That third state matters more than it looks: a
    -- missing measurement printed as FALSE would put "the coach has withdrawn it" back on the page,
    -- which is the sentence this whole round exists to delete.
    IF(COALESCE(bk.book, 'HARVEST') <> 'INVEST'
       OR (e.family IS NULL AND h.family IS NULL), NULL,
       COALESCE(e.campaigns_protected, 0) > 0
       OR COALESCE(h.campaigns_protected, 0) > 0)                       AS protection_enforced,
    -- THE GAP AS A NUMBER. NULL — never 0 — where the coach's budget pass has no row for the family:
    -- "it is holding nothing" and "we cannot see what it is holding" are different sentences, and
    -- only one of them is safe to print beside a live protection. Harvest families carry NULL because
    -- launch protection is not a concept in that book and an unexplained 0 in a grid is noise.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.cuts_held,   NULL)    AS cuts_held,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.cuts_budget, NULL)    AS cuts_budget
  FROM pnl p
  FULL OUTER JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` bk ON bk.family = p.family
  LEFT JOIN `onyga-482313.OI.V_FAMILY_BAR`    b ON b.family = COALESCE(p.family, bk.family)
  LEFT JOIN `onyga-482313.OI.V_INVEST_STATUS` i ON i.family = COALESCE(p.family, bk.family)
  -- Both one row per family by construction (GROUP BY family above), so neither can fan the spine out.
  LEFT JOIN enf  e ON e.family = COALESCE(p.family, bk.family)
  LEFT JOIN held h ON h.family = COALESCE(p.family, bk.family)
  -- k LAST, and never before the FULL OUTER JOIN: cross-joined earlier, the outer join would null
  -- out the tunables on exactly the book-only rows this fix exists to create.
  CROSS JOIN k
),
-- DOLLARS, NOT RATIOS, DECIDE THE QUEUE. Ordering is TOTAL (family breaks the tie) so the "fix this
-- first" sentence can never coin-flip between two families that happen to lose the same amount.
-- loss_rank IS PUBLISHED: it used to be computed and thrown away, so the "fix this first" queue that
-- the whole net-profit-leads argument rests on could not be reproduced by any reader of the output.
-- WHY A WINDOW AND NOT A JOIN: this was a separate CTE joined back onto the family rows, which cost
-- a second and third full expansion of `base` (BigQuery inlines a CTE at every reference, and base
-- fans out over V_UNIFIED_DAILY three times) and, worse, SQUARED any duplicate upstream row into
-- four identical family rows with two wrong money columns while total_rows sat at 2 looking healthy.
-- Computed here it cannot fan out at all, and it is the same total ordering the verdict quotes, so
-- the column and the sentence can never disagree.
ranked AS (
  SELECT
    b.*,
    IF(b.book = 'HARVEST' AND COALESCE(b.real_loss, FALSE),
       ROW_NUMBER() OVER (PARTITION BY (b.book = 'HARVEST' AND COALESCE(b.real_loss, FALSE))
                          ORDER BY b.net_profit ASC, b.family ASC), NULL)          AS loss_rank,
    IF(b.book = 'HARVEST' AND COALESCE(b.real_loss, FALSE),
       FIRST_VALUE(b.family) OVER (PARTITION BY (b.book = 'HARVEST' AND COALESCE(b.real_loss, FALSE))
                                   ORDER BY b.net_profit ASC, b.family ASC), NULL) AS worst_family,
    IF(b.book = 'HARVEST' AND COALESCE(b.real_loss, FALSE),
       FIRST_VALUE(b.net_profit) OVER (PARTITION BY (b.book = 'HARVEST' AND COALESCE(b.real_loss, FALSE))
                                       ORDER BY b.net_profit ASC, b.family ASC), NULL) AS worst_net_profit
  FROM base b
),
fam AS (
  SELECT
    b.book,
    'FAMILY'                AS row_kind,
    b.family,
    -- PUBLISHED, not just spoken. A consumer seeing NULL money must be able to tell "in the book,
    -- nothing mapped" from "measured, and the value happened to be NULL" without parsing English.
    b.money_measured,
    -- WHICH WINDOW THE MONEY COLUMNS BELONG TO — on the row, in words, not only in the prose.
    b.money_window,
    b.period_start,
    b.period_end,
    b.net_profit,
    b.ad_spend,
    b.total_net_roas,
    b.ads_net_roas,
    b.halo_factor,
    b.keyword_bar,
    b.organic_pct,
    -- 1 = the biggest real loss in the harvest book, the one the verdict says to fix first.
    b.loss_rank,
    -- WHICH WINDOW THE RATE COLUMNS BELOW BELONG TO. Deliberately a different, shorter window from
    -- the one above: a spend rate has to be current to bind on anything. Both are now on the row, so
    -- the mismatch is visible to someone reading the grid rather than the sentences. It names a
    -- start and no end because the month-to-date rate upstream has no upper bound — its end is
    -- "the latest day loaded", which is not necessarily period_end, and a fabricated end date here
    -- would be worse than an absent one.
    IF(b.mtd_spend_per_day IS NULL, NULL,
       CONCAT('month to date, from ',
              FORMAT_DATE('%-d %B %Y', DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)))) AS rate_window,
    -- 'RAMP' used to be published raw here — a bare internal token in a grid of plain English.
    -- Same meaning, said the way the verdict already says it.
    CASE b.phase WHEN 'RAMP'  THEN 'in the early stretch'
                 WHEN 'PROOF' THEN 'past the early stretch'
                 ELSE NULL END AS launch_stage,
    b.launch_age_months,
    -- The BINDING sanction trio leads. The loss allowance trails it as the catastrophe backstop it
    -- is (V_INVEST_STATUS header: a loss ceiling on a product that nearly covers its costs never
    -- fires). Every one of these names itself now: spend_rate_ratio, ceiling_used_pct and days_left
    -- were engine vocabulary sitting in a grid whose stated rule is plain English.
    b.daily_investment,
    b.mtd_spend_per_day,
    b.spend_rate_ratio      AS times_over_agreed_rate,
    -- ─── THE TWO STATES, PUBLISHED SEPARATELY, AND THE GAP BETWEEN THEM IN DOLLARS ───
    -- QUALIFIED = has this launch earned protection under the rules Ori set (rate, end date, loss
    -- allowance). ENFORCED = is the coach actually applying protection to its campaigns. They are
    -- currently allowed to disagree and on 2026-08-20 they did, on both families: false and true.
    -- Named so a cold reader cannot read one as the other; the verdict says both out loud as well,
    -- because a column nobody explains is how the last three defects on this object got shipped.
    b.protection_qualified,
    b.protection_enforced,
    -- The size of that disagreement: decisions the coach computed and did not apply, and the daily
    -- budget still running because it did not. This is the number to act on.
    b.cuts_held             AS cuts_the_coach_is_holding,
    b.cuts_budget           AS budget_those_cuts_cover,
    b.ceiling_used_pct      AS loss_allowance_used_pct,
    b.days_left             AS days_left_on_sanction,
    -- THE TRAJECTORY, PUBLISHED. Absolute organic units over the last three complete months. This is
    -- the PRIMARY evidence an Invest family is judged on; it was read into the verdict and then
    -- discarded, so anyone charting the ramp or sorting on it had to re-derive it from upstream.
    -- The old names (org_m2 / org_m1 / org_m0) counted DOWN while their values ran FORWARD in time,
    -- so "0, 1, 126" only read as climbing if you already knew the convention. Now they say it.
    b.org_m2                AS organic_units_2_months_ago,
    b.org_m1                AS organic_units_1_month_ago,
    b.org_m0                AS organic_units_last_month,
    b.takeover_target_organic_units AS organic_units_to_stand_alone,
    -- Account-level coverage lives on the HARVEST TOTAL row only; a family row has no share of it.
    CAST(NULL AS FLOAT64)   AS unattributed_spend,
    CAST(NULL AS FLOAT64)   AS spend_coverage_pct,
    CASE
      -- ───────── INVEST: sanction adherence + trajectory. Never a profit verdict. ─────────
      WHEN b.book = 'INVEST' THEN CONCAT(
        -- ───────────────────────────────────────────────────────────────────────────────────
        -- THE RATE, THE RULE, AND THE MACHINE — three clauses, in that order, never merged.
        -- Until 2026-08-20 this branch collapsed the last two: being over the sanctioned rate was
        -- reported, present indicative, as "it has lost its launch protection and is now judged on
        -- money like every other family". Nothing had withdrawn anything. The coach reads
        -- V_LAUNCH_EXEMPTION, whose exempt_active is hardcoded TRUE, and on the strength of it was
        -- holding 10 budget cuts across $188.86 a day on exactly the two families this sentence told
        -- Ori were already being trimmed. The rule clause may now only describe the RULE, and the
        -- machine clause must follow it and say what is actually happening — including, in dollars,
        -- what is not.
        -- ───────────────────────────────────────────────────────────────────────────────────
        CASE
          WHEN b.daily_investment IS NULL THEN CONCAT(
            b.family, ' is in the investment book, but there is no approved daily spend on record for it, ',
            'so nothing is holding it. Write the sanction down or move it back to being judged on money.')
          ELSE CONCAT(
            -- 1. THE RATE.
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month ',
            CASE
              WHEN b.spend_breached THEN CONCAT(
                'against the ', b.daily_investment_text, ' a day you approved — about ',
                FORMAT('%.1f', b.spend_rate_ratio), ' times the agreed rate. ')
              WHEN b.spend_breached IS NULL THEN CONCAT(
                'against the ', b.daily_investment_text, ' a day you approved. ')
              ELSE CONCAT('inside the ', b.daily_investment_text, ' a day you approved. ')
            END,
            -- 2. WHAT THE RULES SAY. Qualification only — no claim about any consequence.
            CASE
              WHEN COALESCE(b.spend_breached, FALSE) THEN 'That forfeits its launch protection'
              WHEN COALESCE(b.protection_qualified, FALSE) THEN
                CONCAT('It qualifies for launch protection until ', FORMAT_DATE('%-d %B %Y', b.stop_date))
              WHEN COALESCE(b.days_left, -1) < 0 THEN
                'The agreed end date has passed, so it no longer qualifies for launch protection'
              WHEN COALESCE(b.ceiling_used_pct, 0) >= 100 THEN
                CONCAT('It has already used up the losses you allowed it this month, ',
                       'so it no longer qualifies for launch protection')
              ELSE
                'It does not qualify for launch protection right now, and not everything the sanction needs is on record'
            END,
            -- 3. WHAT THE MACHINE IS DOING. This clause is the whole repair. It always speaks, it
            -- never guesses, and where the two states disagree it carries the size of the gap.
            CASE
              WHEN b.protection_enforced IS NULL THEN CONCAT(
                '. Whether the coach is still protecting it could not be checked today, so do not ',
                'assume anything is being cut — check the launch exemption.')
              WHEN COALESCE(b.protection_qualified, FALSE) AND b.protection_enforced THEN
                ', and the coach is applying it.'
              WHEN COALESCE(b.protection_qualified, FALSE) THEN CONCAT(
                ', but the coach is not applying it — this family is being judged on money already. ',
                'Check the launch exemption.')
              WHEN NOT b.protection_enforced THEN
                ', and the coach has withdrawn it: this family is now judged on money like every other family.'
              WHEN COALESCE(b.cuts_held, 0) > 0 THEN CONCAT(
                ', but the coach is not enforcing that yet: it is still holding ',
                CAST(b.cuts_held AS STRING),
                IF(b.cuts_held = 1, ' cut on this family, worth ', ' cuts on this family, worth '),
                FORMAT("$%'d", CAST(ROUND(b.cuts_budget) AS INT64)), ' a day of budget. ',
                IF(COALESCE(b.spend_breached, FALSE),
                   CONCAT('Bring spend back to ', b.daily_investment_text,
                          ' a day, or pull those budgets yourself.'),
                   'Extend the sanction if you still want it, or pull those budgets yourself.'))
              ELSE CONCAT(
                ', but the coach is not enforcing that yet: this family is still protected, so no ',
                'budget cut can reach it — there is simply none queued today. ',
                IF(COALESCE(b.spend_breached, FALSE),
                   CONCAT('Bring spend back to ', b.daily_investment_text,
                          ' a day, or pull its budgets down yourself.'),
                   'Extend the sanction if you still want it, or pull its budgets down yourself.'))
            END)
        END,
        CASE
          WHEN b.org_m1 IS NULL THEN ' There is not enough history yet to tell whether organic sales are climbing.'
          ELSE CONCAT(
            ' Organic sales are ',
            CASE WHEN b.org_m0 > b.org_m1 THEN 'climbing'
                 WHEN b.org_m0 < b.org_m1 THEN 'falling'
                 ELSE 'flat' END,
            ' — ',
            IF(b.org_m2 IS NULL, '', CONCAT(CAST(b.org_m2 AS STRING), ', then ')),
            CAST(b.org_m1 AS STRING), ', then ', CAST(b.org_m0 AS STRING),
            ' units over the last ', IF(b.org_m2 IS NULL, 'two', 'three'), ' complete months.')
        END,
        -- THE AGE CLAUSE MUST NOT CANCEL THE SENTENCE ABOVE IT. "It is 2 months old, so what matters
        -- is whether it is improving, not whether it is profitable yet" is TRUE of a protected
        -- launch and FALSE of one that has just been told it is now judged on money like every other
        -- family — and it landed last, so the reassurance was the part that stuck. The improvement
        -- still matters when protection has stopped; it is just no longer what is holding the line.
        CASE
          WHEN b.launch_age_months IS NULL THEN ''
          WHEN b.phase = 'RAMP' AND COALESCE(b.protection_qualified, FALSE) THEN CONCAT(
            ' It is ', CAST(b.launch_age_months AS STRING), IF(b.launch_age_months = 1, ' month', ' months'),
            ' old, so what matters is whether it is improving, not whether it is profitable yet.')
          -- "and that has stopped" was the same false claim in a second place: protection had not
          -- stopped, the family had only stopped EARNING it. The clause now says exactly that, which
          -- is true whatever the coach is or is not doing.
          WHEN b.phase = 'RAMP' THEN CONCAT(
            ' It is only ', CAST(b.launch_age_months AS STRING), IF(b.launch_age_months = 1, ' month', ' months'),
            ' old, so the improvement still matters — but it is outside the terms that were protecting it.')
          WHEN b.takeover_target_organic_units IS NULL THEN CONCAT(
            ' It is ', CAST(b.launch_age_months AS STRING), IF(b.launch_age_months = 1, ' month', ' months'),
            ' old and past the early stretch, so it now has to stand on its own organic sales — but you have not ',
            'yet said how many organic sales a month would mean it does.')
          ELSE CONCAT(
            ' It is ', CAST(b.launch_age_months AS STRING), IF(b.launch_age_months = 1, ' month', ' months'),
            ' old and past the early stretch: ', CAST(b.org_m0 AS STRING), ' organic units last month against the ',
            CAST(b.takeover_target_organic_units AS STRING), ' you said would mean it can stand on its own, ',
            IF(COALESCE(b.days_left, -1) >= 0,
               CONCAT('with ', CAST(b.days_left AS STRING), ' days left.'),
               'and the agreed end date has passed.'))
        END,
        -- A declared launch whose ASINs are not yet mapped to the family has no measured P&L at all.
        -- It still spends every day, so it must never read as a normal row with quiet blank columns.
        -- AND IT MUST SAY WHICH HALF IS MISSING: a row carrying ad spend but no profit is a
        -- different problem from a row carrying nothing, and round 1 said nothing at all about it.
        CASE
          WHEN b.money_measured THEN ''
          WHEN NOT b.pnl_has_profit AND NOT b.pnl_has_spend THEN
            CONCAT(' None of the money columns are filled in for it, because nothing it sells is being ',
                   'counted under this family yet — check that its products carry the family name.')
          WHEN NOT b.pnl_has_profit THEN
            CONCAT(' Its advertising is being counted but its sales are not, so there is no profit figure ',
                   'for it and none of its cost is in the investment total above — check that its products ',
                   'carry the family name.')
          ELSE
            CONCAT(' Its sales are being counted but its advertising is not, so none of its cost is in the ',
                   'investment total above — check that its products carry the family name.')
        END)

      -- ───────── HARVEST: dollars lead, the ratio explains them. ─────────
      -- NULL FIRST. A harvest family with no measured profit fell through every branch below (NULL >= 0
      -- is NULL, NOT NULL is NULL) into a CONCAT over NULLs, which prints as a BLANK LINE on the
      -- morning read — the one place in this file a NULL had no written fallback. And the branch has
      -- to name the actual gap: round 1 asserted "no sales, no ad spend, no profit" on every one of
      -- these rows, which is false the moment a family has ad spend and no profit side.
      WHEN NOT b.money_measured THEN CONCAT(
        b.family, ' is being judged on money, but ',
        CASE
          WHEN NOT b.pnl_has_profit AND NOT b.pnl_has_spend THEN
            'nothing it sells is being counted under this family name — no sales, no ad spend and no profit over the last 90 days'
          WHEN NOT b.pnl_has_profit THEN
            'only its advertising is being counted — there is ad spend against it and no profit figure at all'
          ELSE
            'its advertising is not being counted — there is a profit figure for it with no ad spend behind it'
        END,
        '. That is a mapping gap, not a quiet quarter, and it is left out of the harvest total above, ',
        'so that total is not the whole book. Check the product mapping before you trust it.')

      WHEN b.net_profit >= 0 THEN CONCAT(
        b.family, ' made ', FORMAT("$%'d", CAST(b.net_profit AS INT64)), ' over the last 90 days on ',
        FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend — ', FORMAT('$%.2f', b.total_net_roas),
        ' back for every ad dollar once the organic sales those ads pull in are counted, against ',
        FORMAT('$%.2f', b.ads_net_roas), ' counting ads alone. Keep it running.')

      WHEN NOT b.real_loss THEN CONCAT(
        b.family, ' broke even over the last 90 days — down ', FORMAT("$%'d", CAST(-b.net_profit AS INT64)),
        ' on ', FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend, which is too small to be worth acting on. ',
        'It brings back ', FORMAT('$%.2f', b.total_net_roas),
        ' for every ad dollar once the organic sales those ads pull in are counted, against ',
        FORMAT('$%.2f', b.ads_net_roas), ' counting ads alone.',
        IF(b.wide_halo,
           CONCAT(' Most of what it earns arrives as organic sales, so cutting it on the ads number alone would ',
                  'take down a family that is paying its way.'),
           ''))

      ELSE CONCAT(
        b.family, ' lost ', FORMAT("$%'d", CAST(-b.net_profit AS INT64)), ' over the last 90 days on ',
        FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend',
        IF(b.loss_rank = 1,
           ' — the biggest loss in the harvest book, so this is the one to fix first. ',
           CONCAT(' — a smaller loss than ', b.worst_family, "'s ",
                  FORMAT("$%'d", CAST(-b.worst_net_profit AS INT64)), ', so it waits behind that one. ')),
        'It brings back ', FORMAT('$%.2f', b.total_net_roas),
        ' for every ad dollar even after counting the organic sales those ads pull in, against ',
        FORMAT('$%.2f', b.ads_net_roas), ' counting ads alone.')
    END                     AS verdict
  FROM ranked b
),
-- One aggregate per book. NOTHING here groups across books, and there is no second aggregation
-- above this: that absence IS the no-grand-total guarantee.
-- The worst Harvest loser is computed HERE rather than in its own CTE. It used to be a one-row
-- aggregate cross-joined in, which cost a whole extra expansion of `base` for two scalars; ARRAY_AGG
-- inside the aggregate that already exists gets the same two values off the pass already being made,
-- with the same ordering and the same total tie-break as loss_rank, so the two can never disagree.
agg AS (
  SELECT
    book,
    COUNT(*)                                       AS n_families,
    COUNTIF(money_measured)                         AS n_measured,
    -- Every measured family shares one window, so MIN/MAX are the window itself; NULL when the book
    -- measured nothing, which is the honest answer rather than a borrowed date.
    MIN(period_start)                              AS period_start,
    MAX(period_end)                                AS period_end,
    -- BOTH SUMS OVER THE SAME SUBSET AS THE COUNT. A family with only half a P&L contributes to
    -- NEITHER, so the count in the sentence, the two money columns and the reconciliation all
    -- describe one identical set of families — the defect that let a 4-family spend sit beside a
    -- 3-family profit on one row and read as complete.
    SUM(IF(money_measured, net_profit, NULL))       AS net_profit,
    SUM(IF(money_measured, ad_spend,   NULL))       AS ad_spend,
    -- THE SANCTION SUMS COVER EXACTLY THE FAMILIES THEY CAN COVER. An INVEST family with no
    -- V_INVEST_STATUS row, or no approved rate written down, contributes NULL to both sums — so the
    -- old sentence said "3 families spending $X against $Y" while X and Y described 2. Both sides
    -- are now taken over the SAME priced subset, the count of that subset is published, and the
    -- families outside it are named in words instead of silently thinned out of the money.
    COUNTIF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL) AS n_priced,
    SUM(IF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL, daily_investment,   NULL)) AS daily_investment,
    SUM(IF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL, mtd_spend_per_day, NULL)) AS mtd_spend_per_day,
    COUNTIF(real_loss)                             AS n_real_losses,
    COUNTIF(COALESCE(spend_breached, FALSE))       AS n_over_rate,
    -- ─── THE TWO PROTECTION STATES AT BOOK LEVEL, AND THE GAP BETWEEN THEM ───
    -- n_protection_gap IS THE HEADLINE NUMBER OF THIS ROUND: families the coach is still protecting
    -- that no longer qualify for it. It was 2 on 2026-08-20, worth 10 held cuts and $189 a day, while
    -- this row said "none is protected right now". Counted, not inferred from a sentence.
    COUNTIF(COALESCE(protection_qualified, FALSE))                          AS n_qualified,
    COUNTIF(COALESCE(protection_enforced,  FALSE))                          AS n_enforced,
    COUNTIF(protection_enforced IS NOT NULL)                                AS n_enforcement_known,
    COUNTIF(COALESCE(protection_enforced, FALSE)
            AND NOT COALESCE(protection_qualified, FALSE))                  AS n_protection_gap,
    -- NULL, not 0, when nothing in the book could be checked — SUM ignores NULLs, and a book of
    -- families the coach's budget pass has never seen must not report "holding nothing".
    SUM(cuts_held)                                 AS cuts_held,
    SUM(cuts_budget)                               AS cuts_budget,
    ARRAY_AGG(IF(COALESCE(real_loss, FALSE), family, NULL)
              IGNORE NULLS ORDER BY net_profit ASC, family ASC LIMIT 1)[SAFE_OFFSET(0)] AS worst_family,
    ARRAY_AGG(IF(COALESCE(real_loss, FALSE), net_profit, NULL)
              IGNORE NULLS ORDER BY net_profit ASC, family ASC LIMIT 1)[SAFE_OFFSET(0)] AS worst_net_profit,
    -- Named, not just counted: "one family is missing" sends nobody anywhere. Ordered by family so
    -- the sentence is byte-identical on two consecutive pulls.
    STRING_AGG(IF(money_measured, NULL, family), ' and ' ORDER BY family) AS unmeasured_families,
    STRING_AGG(IF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL, NULL, family),
               ' and ' ORDER BY family)                                 AS unpriced_families
  FROM base
  GROUP BY book
),
tot AS (
  SELECT
    s.book,
    'TOTAL'                                          AS row_kind,
    CAST(NULL AS STRING)                             AS family,
    -- TRUE only if at least one family in this book has a whole P&L behind the two money columns.
    (COALESCE(a.n_measured, 0) > 0)                  AS money_measured,
    IF(a.period_end IS NULL, NULL,
       CONCAT('the settled ', CAST(DATE_DIFF(a.period_end, a.period_start, DAY) + 1 AS STRING),
              ' days to ', FORMAT_DATE('%-d %B %Y', a.period_end))) AS money_window,
    a.period_start,
    a.period_end,
    -- NOT IFNULL(...,0). A book with nothing measured has no total, and a zero here would claim it
    -- was measured and found to be nothing — the exact error this file forbids on the family rows,
    -- and it would sit next to a verdict saying nothing was measured at all.
    a.net_profit,
    a.ad_spend,
    CAST(NULL AS FLOAT64)                            AS total_net_roas,
    CAST(NULL AS FLOAT64)                            AS ads_net_roas,
    CAST(NULL AS FLOAT64)                            AS halo_factor,
    CAST(NULL AS FLOAT64)                            AS keyword_bar,
    CAST(NULL AS FLOAT64)                            AS organic_pct,
    CAST(NULL AS INT64)                              AS loss_rank,
    IF(a.mtd_spend_per_day IS NULL, NULL,
       CONCAT('month to date, from ',
              FORMAT_DATE('%-d %B %Y', DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)))) AS rate_window,
    CAST(NULL AS STRING)                             AS launch_stage,
    CAST(NULL AS INT64)                              AS launch_age_months,
    a.daily_investment,
    a.mtd_spend_per_day,
    ROUND(SAFE_DIVIDE(a.mtd_spend_per_day, NULLIF(a.daily_investment, 0)), 2) AS times_over_agreed_rate,
    -- A BOOK IS NOT IN ONE PROTECTION STATE, so these two stay NULL on a total and the counts behind
    -- them are spoken in the verdict instead. The two columns that DO belong on a total are the held
    -- decisions and the budget they cover: those add up honestly, they are the number Ori acts on,
    -- and Harvest sums to NULL rather than 0 because no family in that book contributes one.
    CAST(NULL AS BOOL)                               AS protection_qualified,
    CAST(NULL AS BOOL)                               AS protection_enforced,
    a.cuts_held                                      AS cuts_the_coach_is_holding,
    a.cuts_budget                                    AS budget_those_cuts_cover,
    CAST(NULL AS FLOAT64)                            AS loss_allowance_used_pct,
    CAST(NULL AS INT64)                              AS days_left_on_sanction,
    -- A trajectory is a per-family fact; summing organic units across a book would invite exactly the
    -- kind of blended number this object exists to refuse.
    CAST(NULL AS INT64)                              AS organic_units_2_months_ago,
    CAST(NULL AS INT64)                              AS organic_units_1_month_ago,
    CAST(NULL AS INT64)                              AS organic_units_last_month,
    CAST(NULL AS INT64)                              AS organic_units_to_stand_alone,
    -- ACCOUNT-LEVEL, BELONGING TO NEITHER BOOK, AND ON THE HARVEST TOTAL ROW ONLY — the one row that
    -- carries the sentence explaining it. Published on both totals it read as $8,765 twice, next to
    -- an INVEST spend total, with nothing on that row saying what it was.
    IF(s.book = 'HARVEST', c.unattributed_spend, NULL)  AS unattributed_spend,
    IF(s.book = 'HARVEST', c.spend_coverage_pct, NULL)  AS spend_coverage_pct,
    CASE
      WHEN s.book = 'HARVEST' THEN CONCAT(
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'No family is being judged on money right now, which should never happen — check the book assignments.'
          -- The NULL-money guard belongs here too, not only on the family rows: with no measured
          -- family the sum below is NULL, IF(NULL >= 0, ...) is NULL, and a CONCAT over a NULL
          -- prints as a BLANK LINE on the row that is hardest to notice is missing.
          WHEN COALESCE(a.n_measured, 0) = 0 OR a.net_profit IS NULL
            THEN CONCAT(
              'The harvest book holds ', CAST(a.n_families AS STRING),
              IF(a.n_families = 1, ' family', ' families'),
              ', and there is no measured profit for any of them over the last 90 days, which should ',
              'never happen — nothing they sell is being counted under their family names. Fix the ',
              'product mapping before you read anything else on this page.')
          ELSE CONCAT(
            'The harvest book ',
            IF(a.net_profit >= 0,
               CONCAT('made ', FORMAT("$%'d", CAST(a.net_profit AS INT64))),
               CONCAT('lost ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)))),
            ' over the last 90 days across ', CAST(a.n_measured AS STRING),
            IF(a.n_measured = 1, ' family', ' families'), '. ',
            CASE
              -- SCOPED WHENEVER THE SETS DIFFER. "None of them is losing real money" over a set that
              -- excludes an unmeasured family is the July-2026 false comfort in miniature.
              WHEN a.n_real_losses = 0 THEN
                IF(a.n_families = a.n_measured,
                   'None of them is losing real money.',
                   'None of the ones with anything measured is losing real money.')
              WHEN a.n_real_losses = 1 THEN CONCAT(
                a.worst_family, ' is the only one losing real money, at ',
                FORMAT("$%'d", CAST(-a.worst_net_profit AS INT64)),
                ' — fix that one and the rest is working.')
              ELSE CONCAT(
                CAST(a.n_real_losses AS STRING), ' of them are losing real money, and the biggest is ',
                a.worst_family, ' at ',
                FORMAT("$%'d", CAST(-a.worst_net_profit AS INT64)),
                ' — start there, because that is where the dollars are.')
            END,
            -- A family in this book with nothing measured is not in that total, and the sentence has
            -- to say so out loud or the total reads complete when it is not.
            IF(a.n_families = a.n_measured, '',
               CONCAT(' ', a.unmeasured_families,
                      IF(a.n_families - a.n_measured = 1, ' is also in this book but has', ' are also in this book but have'),
                      ' nothing measured at all, so none of it is in that number — check the product mapping.')))
        END,
        -- The one clause that stops this page presenting its spend total as the account's
        -- advertising. It used to be the only sentence on the object that told the reader nothing to
        -- do, while its two siblings about this identical root cause both end the same four words.
        IF(c.unattributed_spend > 0,
           CONCAT(' Separately, ', FORMAT("$%'d", CAST(c.unattributed_spend AS INT64)),
                  ' of advertising over the same 90 days — ', FORMAT('%.1f', 100 - c.spend_coverage_pct),
                  '% of everything the account spent — reached no family at all and is in neither book. ',
                  'Those ads ran against products that are not carrying a family name, so none of the ',
                  'money on this page accounts for it — check the product mapping.'),
           ''))
      ELSE
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'Nothing is on approved launch investment right now, so every family is being judged on money.'
          WHEN COALESCE(a.n_priced, 0) = 0
            THEN CONCAT(
              'You have ', CAST(a.n_families AS STRING), IF(a.n_families = 1, ' family', ' families'),
              ' in the investment book, but not one of them has an approved daily spend on record, so ',
              'nothing is holding them. Write those sanctions down or move them back to being judged on money.')
          ELSE CONCAT(
            'You have ', CAST(a.n_families AS STRING), IF(a.n_families = 1, ' family', ' families'),
            ' on approved launch investment',
            IF(a.n_families = a.n_priced, ', spending ',
               IF(a.n_priced = 1,
                  '. The one with an approved rate on record is spending ',
                  CONCAT('. The ', CAST(a.n_priced AS STRING),
                         ' with approved rates on record are spending '))),
            FORMAT('$%.2f', a.mtd_spend_per_day),
            ' a day in total so far this month against the ',
            IF(a.daily_investment = TRUNC(a.daily_investment),
               FORMAT("$%'d", CAST(a.daily_investment AS INT64)),
               FORMAT('$%.2f', a.daily_investment)),
            ' a day you approved. ',
            IF(a.n_families = a.n_priced, '',
               IF(a.n_families - a.n_priced = 1,
                  CONCAT(a.unpriced_families, ' has no approved rate on record, so none of its spending is in ',
                         'that figure — write the sanction down or move it back to being judged on money. '),
                  CONCAT(a.unpriced_families, ' have no approved rate on record, so none of their spending is in ',
                         'that figure — write those sanctions down or move them back to being judged on money. '))),
            -- SAY WHICH FAMILIES THE RATE SENTENCE IS ABOUT. n_over_rate can only be counted over the
            -- families that have an agreed rate, so once one family has none, "every one of them" would
            -- claim more than was checked.
            -- AND SAY ONLY WHAT THE RULE SAYS. This clause read "so none is protected right now" and
            -- was simply false: the coach was protecting both of them and holding 10 cuts across
            -- $188.86 a day on the strength of it. Qualifying for protection is what the rate decides;
            -- being protected is what the machine decides, and that is the next clause's job.
            CASE
              WHEN a.n_over_rate = 0          THEN CONCAT('All ', IF(a.n_families = a.n_priced, 'of them', 'of those with a rate on record'),
                                                          ' are inside their agreed rate and still qualify for launch protection. ')
              WHEN a.n_over_rate = a.n_priced THEN CONCAT('Every one ', IF(a.n_families = a.n_priced, 'of them', 'of those with a rate on record'),
                                                          ' is over its agreed rate, so none of them still qualifies for launch protection. ')
              ELSE CONCAT(CAST(a.n_over_rate AS STRING), ' ', IF(a.n_families = a.n_priced, 'of them', 'of those with a rate on record'),
                          ' are over their agreed rate and no longer qualify for launch protection. ')
            END,
            -- ─── WHAT THE COACH IS ACTUALLY DOING ABOUT THAT, IN DOLLARS ───
            -- The clause that did not exist, and whose absence let the sentence above be read as an
            -- enforcement report. Nothing withdraws protection today: V_LAUNCH_EXEMPTION hardcodes it
            -- on and the coach's gate keys on campaign presence alone. Wiring the sanction to the
            -- engine is Task 8b and Task 8b is not built, so this clause names the gap and hands the
            -- job to the only enforcer there is — Ori.
            CASE
              WHEN COALESCE(a.n_enforcement_known, 0) = 0 THEN
                'Whether the coach is still protecting them could not be checked today — check the launch exemption. '
              WHEN a.n_protection_gap > 0 AND COALESCE(a.cuts_held, 0) > 0 THEN CONCAT(
                'The coach is not enforcing that: it is still protecting ',
                CAST(a.n_protection_gap AS STRING),
                IF(a.n_protection_gap = 1, ' family that no longer qualifies', ' families that no longer qualify'),
                ', and it is holding ', CAST(a.cuts_held AS STRING),
                IF(a.cuts_held = 1, ' budget cut worth ', ' budget cuts worth '),
                FORMAT("$%'d", CAST(ROUND(a.cuts_budget) AS INT64)),
                ' a day between them. Nothing is trimming those budgets — bring the rates back inside ',
                'the sanctions, or pull the budgets yourself. ')
              WHEN a.n_protection_gap > 0 THEN CONCAT(
                'The coach is not enforcing that: it is still protecting ',
                CAST(a.n_protection_gap AS STRING),
                IF(a.n_protection_gap = 1, ' family that no longer qualifies', ' families that no longer qualify'),
                ', so no budget cut can reach ', IF(a.n_protection_gap = 1, 'it', 'them'),
                ' — there is simply none queued today. Bring the rates back inside the sanctions, ',
                'or pull the budgets yourself. ')
              WHEN a.n_enforced < a.n_qualified THEN CONCAT(
                'The coach is protecting only ', CAST(a.n_enforced AS STRING), ' of the ',
                CAST(a.n_qualified AS STRING), ' that qualify, so the rest are being judged on money ',
                'already — check the launch exemption. ')
              WHEN a.n_enforced = 0 THEN
                'The coach is not protecting any of them either, so they are being judged on money like every other family. '
              ELSE 'The coach is applying that protection to all of them. '
            END,
            -- THE COST SENTENCE MUST NOT CANCEL THE RATE SENTENCE ABOVE IT. "Money you agreed to
            -- spend, not a loss to chase" is the right frame for an investment and the WRONG last
            -- word when they are running above the rate that was agreed: the overspend is precisely
            -- the part nobody approved. The agreement still stands; it just is not what is happening,
            -- and the sentence now ends on the gap and the correction rather than on the comfort.
            CASE
              WHEN COALESCE(a.n_measured, 0) = 0 OR a.net_profit IS NULL THEN CONCAT(
                'Nothing they sell is being counted under their family names yet, so there is no ',
                'measured cost for them over the last 90 days — check the product mapping.')
              WHEN a.net_profit < 0 THEN CONCAT(
                'The ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)),
                ' they cost over the last 90 days is money you agreed to spend while they build, ',
                IF(a.n_over_rate = 0,
                   'not a loss to chase.',
                   CONCAT('so it is not a loss to chase — but right now they are running ',
                          FORMAT('$%.2f', a.mtd_spend_per_day - a.daily_investment),
                          ' a day above what you approved, and that part you never agreed to.',
                          -- ...and do not ask for the correction twice. Where the coach is still
                          -- protecting families that no longer qualify, the clause above has already
                          -- given the instruction, with the budgets attached; repeating a thinner
                          -- version of it here is how a reader learns to skim the last sentence.
                          IF(COALESCE(a.n_protection_gap, 0) > 0, '',
                             ' Bring the rate back inside the sanction.'))))
              ELSE CONCAT(
                'They also made ', FORMAT("$%'d", CAST(a.net_profit AS INT64)),
                ' over the last 90 days while building, ahead of what you agreed to spend on them.')
            END,
            -- ...unless NOTHING in the book is measured, in which case the branch above has already
            -- said so and there is no "that cost" left for this clause to point at.
            IF(a.n_families = a.n_measured OR COALESCE(a.n_measured, 0) = 0, '',
               CONCAT(' ', a.unmeasured_families,
                      IF(a.n_families - a.n_measured = 1, ' has', ' have'),
                      ' nothing measured at all, so none of that cost includes ',
                      IF(a.n_families - a.n_measured = 1, 'it.', 'them.'))))
        END
    END                                              AS verdict
  FROM books s
  LEFT JOIN agg a ON a.book = s.book
  -- A one-row aggregate with no GROUP BY, so it returns exactly one row (all-NULL if there is
  -- nothing to measure) and cannot multiply the two TOTAL rows.
  CROSS JOIN cov c
)
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE MORNING READ MUST NOT ARRIVE SHUFFLED. A view cannot guarantee row order and this one shipped
-- no sort key at all, so two consecutive pulls came back in different orders with the two books
-- interleaved. It cannot force the order, but it MUST ship the key: read this object with
-- ORDER BY sort_order and it reads top to bottom the way it is meant to — Harvest before Invest,
-- each book's TOTAL above its families, then families by net profit, biggest earner first and the
-- losses last. The tie-break on family is TOTAL, so two families losing the same amount can never
-- swap places between pulls. Unmeasured families sort last within their book: they have no number,
-- and NULLS LAST is the only honest place to put "not measured" on a money ranking.
--
-- THE PLANNING CEILING IS REAL AND IT BINDS ON CONSUMERS, NOT ON THIS VIEW.
-- Reading the view is healthy: ~15-20s, 78.2 MiB, deterministic, 8 rows. WRAPPING it is not. Because
-- BigQuery inlines a view at every reference and this one fans out over V_UNIFIED_DAILY through
-- three separate views, a query that touches V_TWO_BOOK_BRIEF more than about twice degrades hard
-- and then stops planning altogether: measured 2026-08-20, three scalar subqueries over it cost ~49s
-- and NINE fail outright with "Not enough resources for query planning - query is too complex".
-- Round 2 halved the internal expansion (see H in the header) but it did NOT move that ceiling.
--   * WRITE CHECKS AS A SINGLE PASS. COUNTIF/SUM(IF(...)) over one SELECT from the view, never one
--     subquery per check. The natural five-self-reference form takes minutes or fails.
--   * ANY PAGE, CUBE MODEL OR SOP QUERY MUST READ A MATERIALISED COPY, NOT THIS VIEW. One reference
--     plans fine, so the copy is a one-liner and it is the ONLY supported way to consume this:
--       CREATE OR REPLACE TABLE `onyga-482313.OI.T_TWO_BOOK_BRIEF` AS
--       SELECT * FROM `onyga-482313.OI.V_TWO_BOOK_BRIEF`;
--     That table does not exist yet and nothing in the repo builds it. It has to land BEFORE the
--     first consumer, not after the first timeout.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
SELECT
  r.*,
  ROW_NUMBER() OVER (
    ORDER BY IF(r.book = 'HARVEST', 1, 2),
             IF(r.row_kind = 'TOTAL', 1, 2),
             r.net_profit DESC NULLS LAST,
             r.family
  )                                                AS sort_order
FROM (
  SELECT * FROM fam
  UNION ALL
  SELECT * FROM tot
) r;
