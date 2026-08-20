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
-- WINDOW HONESTY: the P&L columns are the settled 90-day window; the spend rate is the SHORT,
-- CURRENT window, because a rate must be current to bind. The two are deliberately different
-- windows, so every verdict string says which one it is quoting ("over the last 90 days" vs the
-- rate window named in dates), and both windows ride on the row as money_window and rate_window.
-- Do not silently align them — a 90-day average spend rate would not bind on anything.
--
-- AND THE RATE WINDOW IS NEVER "THIS MONTH". Upstream the sanctioned rate is measured on a TRAILING
-- window of complete days ending one day behind the ads feed — the sanction is denominated as a rate
-- ("$30 a day"), not as a monthly budget, so it is measured as one. Nothing here may say "so far this
-- month": rate_window, rate_window_start/_end/_days and the phrase inside every rate sentence are all
-- READ from V_INVEST_STATUS, which measured the window, and rate_window_is_stale is published so a
-- consumer can branch on a frozen ads feed without parsing English.
--
-- VERDICTS ARE PLAIN SENTENCES ON PURPOSE. No rule names, no engine internals, no bare metric codes:
-- ROAS is written as "$1.41 back for every ad dollar", the halo as "counting everything the family
-- earned, attributed to the ads or not", the exemption as "launch protection". Ori has repeatedly
-- filed unreadable output as a defect against the page, and he is right to.
--
-- PLAIN IS NOT THE SAME AS LOOSE, AND THIS IS WHERE THAT COST SOMETHING. The halo used to be glossed
-- as "the organic sales those ads pull in" — readable, and a causal claim nothing in this pipeline
-- measures. Plain English makes a metric easy to describe as MORE than it is; that is the failure
-- this object keeps having. If you add a branch here, read it aloud before you deploy, and then ask
-- what the sentence asserts that the arithmetic behind it does not establish.
--
-- ---------------------------------------------------------------------------------------------
-- 2026-08-20 (ROUND 1) — SEVEN REVIEW FINDINGS CLOSED.
--   1. The spine became a FULL OUTER JOIN of the two family universes, so a declared family with no
--      measured P&L gets a visible row instead of being joined away behind a confident total.
--   2. sort_order and loss_rank are published; the morning read no longer arrives shuffled.
--   3. The windows are on the row (money_window / period_start / period_end, and rate_window with
--      rate_window_start / _end / _days), not only inside the prose.
--   4. The advertising that reaches NEITHER book is published and named in the harvest verdict.
--   5. The NULL branch leads the harvest CASE, so an unmeasured family cannot print a blank line.
--   6. The raw token 'RAMP' became launch_stage in words; the sanctioned rate stopped rounding
--      inside the one instruction on the object that tells Ori to do something.
--   7. The trajectory is projected, and both book totals name the families their money leaves out.
--
-- 2026-08-20 (ROUND 4) — THE RATE WINDOW STRING WAS FALSE, AND ITS COMMENT ASSERTED SOMETHING THAT
-- HAD STOPPED BEING TRUE. rate_window was built here as CONCAT('month to date, from ', the 1st of
-- CURRENT_DATE's month), under a comment explaining that it named a start and no end "because the
-- month-to-date rate upstream has no upper bound". The upstream rate had HAD an upper bound since
-- commit 0e4e568, published as rate_window_start / _end / _days precisely so this could be read
-- instead of guessed. Today the guess and the fact coincide; on 1 and 2 September the brief would
-- have printed a September start over an August window. Two earlier rounds flagged it and neither
-- fixed it. It is now read, not derived — and it had to be, because the upstream window is not a
-- month at all: it is a TRAILING span of complete days, which the words "month to date" describe
-- backwards on most days of the year. Every rate sentence takes its phrase from the same source, and
-- mtd_spend_per_day became spend_per_day for the same reason its window string had to change.
--
-- 2026-08-20 (ROUND 5) — THE FALLBACK IS GONE, AND WITH IT EVERY SENTENCE ABOUT IT. The round-4
-- upstream substituted the LAST COMPLETE CALENDAR MONTH's rate whenever the running month held fewer
-- than 11 loaded ads days, and this object faithfully carried that substitution into words on both
-- the family rows and the book totals. The rate now runs on a trailing window, which is always full,
-- so there is nothing left to fall back to: rate_window_is_last_complete_month and both "that spend
-- figure is last month's" clauses are deleted rather than reworded. What replaces them is the only
-- way a trailing window can go wrong — the ads feed freezing under it — carried as
-- rate_window_is_stale and said out loud in the same two places the fallback caveat used to sit.
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
--   reads neither that flag nor V_INVEST_STATUS.protection_qualified (called exemption_live then). On the strength of that protection the
--   coach was holding 10 budget decisions (Bunny 4, LolliBall 6). Round 3 priced them at $188.86 a
--   day, which was wrong — see ROUND 4 below; the true figure is $147.86.
--   So Ori would read "now judged on money", conclude the trimming had started, leave the budgets
--   alone, and the only instruction on the row asked him to restore a protection nobody had withdrawn.
--
--   TWO STATES, NOT ONE, AND BOTH AS NUMBERS. Being over the sanction and being cut are different
--   facts and this object may never again publish one as the other. protection_qualified is what the
--   sanction rules say (V_INVEST_STATUS.protection_qualified, which fails closed); protection_enforced is
--   what the machine is doing; the held decisions and what applying them would free carry the size of
--   the gap in dollars, on the family row AND on the book total, because that is the number Ori acts
--   on. (Round 3 called the columns "the size of the gap in dollars" while summing something else
--   entirely — that phrasing is what let the error through, and ROUND 4 below is the correction.)
--   Every Invest sentence now states both, and states them apart. The old exemption_live column is
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
--
-- 2026-08-20 (ROUND 4) — THE REPAIR ROUND PUBLISHED A NUMBER 28% TOO HIGH, AND TWO SENTENCES THAT
-- OVERSTATED. Seven findings, every one re-derived against live data before it was touched.
--
--   1. THE HELD-CUTS DOLLARS WERE THE WRONG MEASURE (critical, and the wrong figure had already been
--      handed to Ori). Round 3 summed current_budget over every held decision whatever the decision
--      was. A held CAMPAIGN_STOP is worth its whole budget; a held GUARDIAN_BUDGET_DECREASE is worth
--      only current_budget minus the budget the coach wanted. Measured on T_COACH_CAMPAIGN_BUDGET:
--      Bunny 4 stops $59.00; LolliBall 2 stops $32.50 plus 4 decreases $97.36 -> $41.00, worth $56.36.
--      TRUE $147.86 a day; PUBLISHED $188.86 — 28% high at book level and 46% high on LolliBall's own
--      row ($129.86 against $88.86). Priced per decision kind now, and the two kinds are published
--      and spoken separately, because "stop this campaign" and "trim this budget" are different jobs.
--      An unsized trim contributes ZERO dollars and is counted instead, so the figure can only run low.
--      (The action MIX moves intraday — an earlier read saw Bunny 3 stops + 1 decrease. Nothing here
--      pins the mix; every count and every dollar is read from the table.)
--   2. "MOST OF WHAT IT EARNS ARRIVES AS ORGANIC SALES" WAS FALSE AT THE GATE THAT SPOKE IT. The gate
--      is halo >= 1.30, where the organic share of the return is 1 - 1/1.30 = 23% — and the sentence
--      called that "most". Bottle, the family it fires on, is 36% (halo 1.57). A majority needs halo
--      above 2.00, which nothing in the account reaches, so raising the gate would have silenced the
--      warning instead of fixing it. The gate is unchanged; the sentence prints the MEASURED share.
--   3. "A FAMILY THAT IS PAYING ITS WAY" WAS ASSERTED ON A FAMILY THAT IS NOT. Bottle: net profit
--      -$7.54 over the window, return 0.998. The verdict rounded 0.998 to "$1.00" and made a
--      categorical claim on the rounded value. The claim is gone, the ratio can no longer round
--      itself across $1.00 (it reads "just under $1.00"), and the point that actually mattered — do
--      not cut this on the ads figure alone — is made without it.
--   4. THE BAR RULE WAS STATED AND BROKEN IN THE SAME OBJECT. The file said printing a computed bar
--      would imply a test that is not being applied, blanked it on INVEST, and printed 0.88 / 0.83 /
--      0.78 / 0.94 on the HARVEST rows — where nothing applies it either, because Task 8 is unbuilt
--      and on hold. The bar is now published for every family under a name that says what it is:
--      keyword_bar_computed_not_applied.
--   5. THE LOSS ALLOWANCE BELONGED TO NO PUBLISHED WINDOW. The row carried money_window and
--      rate_window; loss_allowance_used_pct was measured over a THIRD span (month-to-date net profit,
--      cut at the orders watermark). It now carries loss_allowance_window and its name says "so far".
--   6. organic_units_1_month_ago WAS NOT THE MOST RECENT MONTH. It sat beside organic_units_last_month
--      reading 44 and 69 on Bunny: "last month" was July and "1 month ago" was June, the opposite of
--      the plain reading. Relative English cannot carry this; the names are ordinals off the most
--      recent COMPLETE calendar month.
--   7. IT IS ONE KEY, NOT "PRODUCTS". The $8,765 that reaches neither book resolves to a SINGLE key
--      and that key is the literal placeholder 'Unknown' — rows that name no advertised product at
--      all. "Products that are not carrying a family name" made a one-line mapping gap sound
--      systemic, and pointed at a fix that cannot work: no product mapping reaches a row with no
--      product on it. The clause branches on the measured count so it stays true if the shape changes.
--
--   NOTHING IN THE ENGINE WAS TOUCHED, AGAIN. Ori 2026-08-20: "Tell the truth now, release nothing."
--   V_LAUNCH_EXEMPTION, V_ADS_COACH and V_COACH_CAMPAIGN_BUDGET are unchanged, not one held decision
--   was released, Task 8b is still unbuilt and Task 8 is still on hold. Everything above is a change
--   to what this object SAYS about what the machine is already doing.
--   COST: the two new coverage measures read columns that scan already reads (dry run identical at
--   56,742,327 bytes standalone); counting distinct campaigns there would have cost +14.9 MB and this
--   view has no room for it.
-- ---------------------------------------------------------------------------------------------
--
-- 2026-08-20 (ROUND 6) — THREE SENTENCES CLAIMED MORE THAN THE DATA SUPPORTED, AND SEVEN SMALLER
-- THINGS DID NOT SAY WHAT THEY MEANT. Nothing in the engine was touched and no held decision was
-- released; every change here is to what this object SAYS and to how its columns are named.
--
--   I1. THE HARVEST VERDICTS ASSERTED A CAUSE NOTHING MEASURES (critical). All three Harvest money
--       branches glossed total_net_roas as the return "once the organic sales those ads pull in are
--       counted". total_net_roas is SUM(sales - cogs) / SUM(ad_cost) over the WHOLE family
--       (V_FAMILY_PNL), so its numerator is 100% of the family's gross profit — including every sale
--       that would have happened with no advertising. No object in this pipeline decides which
--       organic sales the ads caused. That is the founding error of this design pointing the other
--       way: the ads-only lens understated by excluding earned profit, and this sentence overstated
--       by handing the ads credit for profit nobody showed they produced. Each branch now says what
--       the ratio is — everything the family earned against what the ads cost, attributed or not —
--       and the point that matters survives untouched: judged on the ads-only figure alone, a family
--       carrying the account gets cut.
--
--   I2. organic_share_of_return_pct WAS NAMED FOR A CAUSE, NOT A MEASUREMENT. 1 - 1/halo is the share
--       of family gross profit carrying NO AD ATTRIBUTION: organic demand PLUS every ad-driven sale
--       the attribution missed. Renamed share_of_return_with_no_ad_attribution_pct.
--       THE MISSED PART IS NOT SMALL, AND IT WAS RE-DERIVED RATHER THAN QUOTED. Ori's recorded
--       finding is ~79% of ads-driven purchases being of a different ASIN than the advertised one; on
--       the settled 90-day window this view actually publishes it measures HIGHER. As of 2026-08-20,
--       over 20 May to 17 Aug 2026: 4,133 ad orders, 3,569 of them (86.4%) with a purchased ASIN
--       different from the advertised one, 84.3% of the ad sales dollars; and 25.1% of those orders
--       (22.9% of the dollars) crossed to a different FAMILY. RE-RUN BEFORE QUOTING ANY OF THESE —
--       they are one day's measurement, not constants:
--       THIS QUERY RUNS AS WRITTEN — verified 2026-08-20, and it reproduces all four figures above
--       plus the window it measured them on. It is written with a CTE and a CROSS JOIN rather than
--       scalar subqueries in the WHERE, because the scalar form is rejected outright by BigQuery
--       ("Correlated subqueries that reference other tables are not supported"):
--         WITH w AS (SELECT MIN(period_start) AS s, MAX(period_end) AS e
--                    FROM `onyga-482313.OI.V_FAMILY_PNL` WHERE period_label='M3')
--         SELECT MIN(pp.DATE) AS window_start, MAX(pp.DATE) AS window_end,
--                SUM(pp.PURCHASED_ORDERS) AS ad_orders,
--                ROUND(100*SAFE_DIVIDE(SUM(IF(pp.PURCHASED_ASIN<>pp.advertised_asin,pp.PURCHASED_ORDERS,0)),
--                                      SUM(pp.PURCHASED_ORDERS)),1) AS pct_orders_different_asin,
--                ROUND(100*SAFE_DIVIDE(SUM(IF(pp.PURCHASED_ASIN<>pp.advertised_asin,pp.PURCHASED_AMOUNT_USD,0)),
--                                      SUM(pp.PURCHASED_AMOUNT_USD)),1) AS pct_sales_different_asin,
--                ROUND(100*SAFE_DIVIDE(SUM(IF(fp.family IS DISTINCT FROM fa.family,pp.PURCHASED_ORDERS,0)),
--                                      SUM(pp.PURCHASED_ORDERS)),1) AS pct_orders_different_family,
--                ROUND(100*SAFE_DIVIDE(SUM(IF(fp.family IS DISTINCT FROM fa.family,pp.PURCHASED_AMOUNT_USD,0)),
--                                      SUM(pp.PURCHASED_AMOUNT_USD)),1) AS pct_sales_different_family
--         FROM `onyga-482313.OI.STG_AmazonAds_purchased_product` pp
--         CROSS JOIN w
--         LEFT JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fp ON fp.asin = pp.PURCHASED_ASIN
--         LEFT JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fa ON fa.asin = pp.advertised_asin
--         WHERE pp.DATE BETWEEN w.s AND w.e;
--       Returned 2026-05-20 / 2026-08-17 / 4133 / 86.4 / 84.3 / 25.1 / 22.9 on 2026-08-20.
--       WHY THAT MATTERS HERE: V_UNIFIED_DAILY books ad GROSS_PROFIT against the ADVERTISED asin and
--       books sales and COGS against the PURCHASED asin, so a purchase that crosses families is
--       credited to one family's ads and one family's revenue. The no-attribution bucket therefore
--       contains real ad-driven profit, and calling it "organic" was a claim, not a reading.
--
--   I3. "AND THE REST IS WORKING" SURVIVED ON THE ROW READ FIRST. Round 4 removed "a family that is
--       paying its way" from Bottle's own row and left the HARVEST TOTAL — printed above it — saying
--       "Fresh is the only one losing real money, at $1,776 — fix that one and the rest is working."
--       "The rest" included Bottle, whose row two lines later says it is short of covering its costs.
--       real_loss is a THREE-way split (earning / short by less than the breakeven band / losing real
--       money) and the total was using two sides of it. The counts n_earning and n_small_shortfall
--       and the names small_shortfall_families are computed in `agg`, the claim is deleted, and the
--       remainder is now described instead of implied.
--
--   I4. SEVEN SMALLER ONES, ALL ACCEPTED:
--     (a) loss_allowance_used_pct_so_far published a percentage whose denominator was nowhere on the
--         row. loss_allowance_dollars_for_the_month and loss_so_far_dollars_against_that_allowance
--         now sit beside it, both already published by V_INVEST_STATUS, so no extra scan.
--     (b) Bottle's total_net_roas COLUMN read 1.0 beside net_profit -8. Round 4 made the VERDICT
--         rounding-proof and left the column at ROUND(x,2). Where 2 decimals would land a value on
--         1.00 from the wrong side, the 4-decimal upstream figure is published instead — more
--         precision, not a nudged number.
--     (c) spend_coverage_pct and unattributed_spend are ACCOUNT-wide and sat three columns from
--         book='HARVEST' under names that did not say so. Renamed
--         account_ad_spend_reaching_a_family_pct and account_ad_spend_in_neither_book.
--     (d) organic_pct (organic UNITS / units) sat beside the I2 column, both starting "organic...pct",
--         neither naming its denominator — and round 2's own implementer misread this one as a share
--         of sales. It is organic_share_of_units_pct now.
--     (e) THE TRAJECTORY CLAUSE, three defects: the trend word was decided on the last two months
--         while three were printed (a V read as "climbing"); the series was called "sales" over a
--         count of units; and LolliBall's leading 0 was May 2026, a month before its first sale on
--         2026-06-26 — a zero meaning "not born yet" printed as a measurement, understating the start
--         and flattering the ramp. The word is decided on every month printed, the sentence says
--         units at both ends, and pre-existence months are dropped with a clause saying why. The
--         pre-existence test re-derives no window: launch_age_months is DATE_DIFF(today,
--         first_sale_date, MONTH) computed upstream, and BigQuery's MONTH difference counts month
--         boundaries, so it is identically the number of months back that the first-sale month sits.
--         Verified on all six families 2026-08-20; re-check with:
--           SELECT family, launch_age_months,
--                  DATE_DIFF(DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'),MONTH),
--                            DATE_TRUNC(first_sale_date,MONTH),MONTH) AS months_back
--           FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`;
--     (f) The INVEST total's spend_per_day was a SUM OF ROUNDED per-family rates. It is now the
--         book's own spend over the book's own window: SUM(rate_window_spend) / rate_window_days.
--     (g) "The $3,622 they cost over the last 90 days is money you agreed to spend" conflated a NET
--         PROFIT shortfall with sanctioned SPEND. The sanction is denominated in dollars a day of
--         spending; the ad spend behind that same window was $9,651 as of 2026-08-20, and nothing
--         anywhere sanctions a loss. Both figures move with the window — read them off the row, do
--         not quote them from here. The clause names the spend as the sanctioned quantity and the
--         shortfall as its consequence, and keeps them apart.
--
--   COST: no new source and no new join. The two loss-allowance columns and rate_window_spend come
--   from V_INVEST_STATUS, which was already joined; everything else is a rename or a rewritten
--   string. Measure the dry run yourself before adding anything — rule 7 of the house rules, and the
--   reason this round added two published columns and not five.
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
    -- loud. Bottle reads 1.57 — the strongest in the account — and cutting it on the ads number is
    -- precisely the mistake this whole design exists to prevent.
    --
    -- THE GATE STAYS AT 1.30; THE WORD "MOST" HAD TO GO. The verdict behind this gate said "Most of
    -- what it earns arrives as organic sales", which is a claim about a MAJORITY and the gate does not
    -- buy one. halo is total gross profit / ads-attributed gross profit, so the share carrying no ad
    -- attribution is 1 - 1/halo: at the gate that is 23%, and the sentence would have called 23%
    -- "most". Bottle itself is 36% (halo 1.57), still not most. A majority needs halo above 2.00,
    -- which no family in this account reaches, so raising the gate there would have silenced the one
    -- warning it exists to give. The gate is therefore unchanged and the sentence prints the measured
    -- share instead of naming a size — share_of_return_with_no_ad_attribution_pct, computed off this
    -- same published halo.
    --
    -- AND THE SHARE IS NOT "ORGANIC". Round 6 renamed the column: 1 - 1/halo is the share of gross
    -- profit that Amazon's ad attribution did not claim, which is organic demand PLUS ad-driven sales
    -- the attribution missed. Nothing measures the split. What the gate is for is unchanged — a
    -- family whose earnings mostly sit outside the ads-only number must not be cut on that number.
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
                            NULLIF(SUM(a.Ads_cost), 0)), 2)                          AS spend_coverage_pct,
    -- HOW MANY ADVERTISED PRODUCTS THAT MONEY ACTUALLY COVERS, AND WHICH ONE IF IT IS JUST ONE.
    -- The sentence used to say "products that are not carrying a family name" — plural, which reads
    -- as a systemic mapping failure. Re-derived 2026-08-20: it is ONE key, and the key is the literal
    -- placeholder 'Unknown' that FACT_AMAZON_ADS writes when a row names no advertised product at all
    -- (all of it Sponsored Brands). That is not a family name missing from a product; it is a row with
    -- no product on it, which no product mapping can ever reach. The sentence now branches on the
    -- measured count instead of asserting a shape, so it stays true when the shape changes.
    -- COSTS NOTHING: both expressions read columns this scan already reads (dry run 56,742,327 bytes
    -- with and without them). Counting DISTINCT campaign_id here would have cost +14.9 MB and this
    -- view has no room for it.
    COUNT(DISTINCT IF(fm.asin IS NULL,
      COALESCE(a.most_advertised_asin_impressions, a.advertised_asins, a.ASIN_BY_CAMPAIGN_NAME),
      NULL))                                                                         AS unattributed_products,
    MIN(IF(fm.asin IS NULL,
      COALESCE(a.most_advertised_asin_impressions, a.advertised_asins, a.ASIN_BY_CAMPAIGN_NAME),
      NULL))                                                                         AS unattributed_product_key
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
  -- What that protection is costing in withheld decisions.
  --
  -- A STOP AND A TRIM ARE NOT WORTH THE SAME MONEY, AND ROUND 3 PRICED THEM AS IF THEY WERE. It summed
  -- current_budget over every held decision, whatever the decision was, and published the answer as
  -- "the gap in dollars". A held CAMPAIGN_STOP is indeed worth its whole budget: apply it and all of
  -- that daily money stops. A held GUARDIAN_BUDGET_DECREASE is worth only current_budget MINUS the
  -- budget the coach wanted (budget_suppressed_to) — the rest keeps running either way. Re-derived
  -- 2026-08-20 on this table: Bunny 4 stops / $59.00; LolliBall 2 stops / $32.50 plus 4 decreases from
  -- $97.36 down to $41.00, worth $56.36. TRUE gap $147.86 a day. The published figure was $188.86 —
  -- 28% too high at book level, and LolliBall's own row was 46% high ($129.86 against a true $88.86).
  -- Ori has already been given the wrong number once; it is priced per decision kind from here on.
  --
  -- PUBLISHED SEPARATELY, because they are different jobs. "Stop these two campaigns" and "trim these
  -- four budgets" are not one instruction, and a reader deciding what to do by hand needs to know
  -- which is which before they can do either.
  --
  -- NO TARGET ON RECORD MEANS NO DOLLARS, NEVER THE WHOLE BUDGET. COALESCE(budget_suppressed_to, 0)
  -- would have priced an unsized trim at its full budget — the exact overstatement above, rebuilt. An
  -- unsized trim contributes ZERO to the money and is counted instead, so the figure can only ever be
  -- low, and the row says when it is. (None exist today: every decrease carries a target.)
  SELECT
    parent_name                                                                 AS family,
    COUNTIF(launch_exempt)                                                      AS campaigns_protected,
    COUNTIF(budget_action_suppressed IS NOT NULL)                               AS cuts_held,
    COUNTIF(budget_action_suppressed = 'CAMPAIGN_STOP')                         AS stops_held,
    COUNTIF(budget_action_suppressed IS NOT NULL
            AND budget_action_suppressed <> 'CAMPAIGN_STOP')                    AS trims_held,
    COUNTIF(budget_action_suppressed IS NOT NULL
            AND budget_action_suppressed <> 'CAMPAIGN_STOP'
            AND budget_suppressed_to IS NULL)                                   AS trims_unsized,
    ROUND(SUM(IF(budget_action_suppressed = 'CAMPAIGN_STOP', current_budget, 0)), 2) AS stops_budget,
    ROUND(SUM(IF(budget_action_suppressed IS NOT NULL
                 AND budget_action_suppressed <> 'CAMPAIGN_STOP'
                 AND budget_suppressed_to IS NOT NULL,
                 GREATEST(current_budget - budget_suppressed_to, 0), 0)), 2)    AS trims_budget,
    ROUND(SUM(CASE
                WHEN budget_action_suppressed IS NULL                THEN 0
                WHEN budget_action_suppressed = 'CAMPAIGN_STOP'      THEN current_budget
                WHEN budget_suppressed_to IS NULL                    THEN 0
                ELSE GREATEST(current_budget - budget_suppressed_to, 0)
              END), 2)                                                          AS cuts_budget
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
    -- ─── THE COLUMN MAY NOT ROUND ITSELF ONTO $1.00 EITHER ───
    -- Round 4 made the VERDICT rounding-proof (total_net_roas_text below) and left the COLUMN at
    -- ROUND(x, 2). Bottle's return is 0.998, so the grid printed 1.0 beside net_profit -8: a reader
    -- scanning columns — which is what a grid is for — saw breakeven next to a loss, while the
    -- sentence two lines away said "just under $1.00". Same defect, one row over.
    -- THE FIX PUBLISHES MORE PRECISION, NOT A NUDGED NUMBER. Where 2 decimals would land the value on
    -- 1.00 from the wrong side, the 4-decimal upstream figure is published instead (0.998), so the
    -- column is more exact than before rather than bent toward the answer. Everywhere else it is the
    -- same 2 decimals it always was. The test is on the UNROUNDED upstream value, as the text
    -- columns' is, so column and sentence can never disagree about which side of $1.00 this is.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       CASE WHEN p.total_net_roas IS NULL                                   THEN NULL
            WHEN p.total_net_roas < 1 AND ROUND(p.total_net_roas, 2) >= 1   THEN ROUND(p.total_net_roas, 4)
            WHEN p.total_net_roas > 1 AND ROUND(p.total_net_roas, 2) <= 1   THEN ROUND(p.total_net_roas, 4)
            ELSE ROUND(p.total_net_roas, 2) END)                             AS total_net_roas,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       CASE WHEN p.ads_net_roas IS NULL                                     THEN NULL
            WHEN p.ads_net_roas < 1 AND ROUND(p.ads_net_roas, 2) >= 1       THEN ROUND(p.ads_net_roas, 4)
            WHEN p.ads_net_roas > 1 AND ROUND(p.ads_net_roas, 2) <= 1       THEN ROUND(p.ads_net_roas, 4)
            ELSE ROUND(p.ads_net_roas, 2) END)                               AS ads_net_roas,
    -- ─── THE RATIO IN WORDS, AND IT MAY NOT ROUND ITSELF ACROSS $1.00 ───
    -- Bottle's return is 0.998. FORMAT('$%.2f') prints that as "$1.00", and a verdict then read
    -- "$1.00 back for every ad dollar" beside a 90-day loss of $8 — the rounding said the family
    -- covered its costs and the dollars said it did not. Rounding may not decide that question, so a
    -- value on the wrong side of $1.00 that rounds onto it says which side it is on instead. Built
    -- from the UNROUNDED upstream figure on purpose: the published column is already rounded to 1.00,
    -- so a test against the published column can no longer see the difference.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       CASE WHEN p.total_net_roas IS NULL                                   THEN NULL
            WHEN p.total_net_roas < 1 AND ROUND(p.total_net_roas, 2) >= 1   THEN 'just under $1.00'
            WHEN p.total_net_roas > 1 AND ROUND(p.total_net_roas, 2) <= 1   THEN 'just over $1.00'
            ELSE FORMAT('$%.2f', p.total_net_roas) END)                      AS total_net_roas_text,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       CASE WHEN p.ads_net_roas IS NULL                                     THEN NULL
            WHEN p.ads_net_roas < 1 AND ROUND(p.ads_net_roas, 2) >= 1       THEN 'just under $1.00'
            WHEN p.ads_net_roas > 1 AND ROUND(p.ads_net_roas, 2) <= 1       THEN 'just over $1.00'
            ELSE FORMAT('$%.2f', p.ads_net_roas) END)                        AS ads_net_roas_text,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, ROUND(p.halo_factor, 2))    AS halo_factor,
    -- ─── HOW MUCH OF THE RETURN CARRIES NO AD ATTRIBUTION — AND THAT IS NOT THE SAME AS "ORGANIC" ───
    -- This was called organic_share_of_return_pct and the name asserted a cause the pipeline does not
    -- measure. The arithmetic is 1 - 1/halo, where halo = total gross profit / AD-ATTRIBUTED gross
    -- profit, so what the number actually isolates is the share of the family's gross profit that
    -- Amazon's ad attribution did not claim. That bucket is organic demand PLUS every ad-driven sale
    -- the attribution missed, and the missed part is not a rounding error: the ads fact books
    -- GROSS_PROFIT against the ADVERTISED asin (V_UNIFIED_DAILY `ads` CTE) while sales and COGS are
    -- keyed to the PURCHASED asin (`perf` CTE), and on the same settled 90-day window this view
    -- measures, 86.4% of ad orders were for a different asin than the one advertised and 25.1% were
    -- for a different FAMILY. Re-derive both before quoting them — they are as of 2026-08-20 and the
    -- query is in the file header.
    -- Computed off the SAME halo the row publishes, so the sentence and the column cannot disagree.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL OR COALESCE(p.halo_factor, 0) <= 0, NULL,
       CAST(ROUND(100 * (1 - SAFE_DIVIDE(1, ROUND(p.halo_factor, 2)))) AS INT64))    AS share_of_return_with_no_ad_attribution_pct,
    -- A DIFFERENT DENOMINATOR AND A DIFFERENT NUMERATOR FROM THE COLUMN ABOVE. This one is organic
    -- UNITS over total UNITS (V_FAMILY_PNL.organic_pct). It sat beside the column above under two
    -- names that both began "organic...pct" and neither of which named its denominator, and round 2's
    -- own implementer read this one as a share of sales. Both names now say what they divide.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.organic_pct)              AS organic_share_of_units_pct,
    -- ─── THE BAR IS COMPUTED AND NOTHING APPLIES IT — SAY SO ON EVERY ROW ───
    -- This file used to state the rule "printing a bar would imply a test that is not being applied",
    -- blank it on the INVEST rows because those families are bar-exempt (V_FAMILY_BAR.bar_exempt) —
    -- and then print the bar on the four HARVEST rows, where NO engine applies it either, because
    -- Task 8 is unbuilt and Ori has it on hold. The rule was stated and broken in the same object.
    -- Resolved by keeping the number and fixing the claim: the bar is published for EVERY family
    -- under a name that says what it is. Nothing reads it today. When Task 8 ships and something
    -- does, rename this column — do not quietly start relying on it under a name that says otherwise.
    ROUND(b.keyword_bar, 2)                                             AS keyword_bar_computed_not_applied,
    i.phase, i.launch_age_months, i.stop_date,
    i.daily_investment, i.spend_per_day, i.spend_rate_ratio, i.spend_breached,
    -- NOT PUBLISHED, USED ONLY BY THE BOOK TOTAL. The dollars behind spend_per_day over the same
    -- window, so the INVEST total can compute a rate over the BOOK — total spend / window days —
    -- instead of summing per-family rates that have each already been rounded to the cent. See the
    -- spend_per_day note in `agg`.
    i.rate_window_spend,
    -- ─── THE RATE WINDOW IS READ, NEVER RE-DERIVED ───
    -- It used to be built here as CONCAT('month to date, from ', the 1st of CURRENT_DATE's month).
    -- That string was a guess dressed as a fact and it was wrong on two counts. It named a start with
    -- no end, on the grounds that the upstream rate had no upper bound — untrue since the upstream
    -- view began publishing rate_window_start/_end/_days. And it named TODAY's month, while the rate
    -- is measured to the ads watermark: on 1 and 2 September the brief would have printed a September
    -- start over an August window. It also could not survive the change immediately upstream, where
    -- the rate is now measured on a TRAILING window of complete days — a span the words "month to
    -- date" describe backwards on most days of the year. The upstream view publishes it as dates, as
    -- a count, and in two ready-made English forms; this object reads them.
    i.rate_window_start, i.rate_window_end, i.rate_window_days,
    i.rate_window_basis, i.rate_window_phrase,
    -- A TRAILING WINDOW IS ALWAYS FULL, SO THE ONLY THING THAT CAN GO WRONG WITH IT IS ITS AGE.
    -- Upstream this is TRUE when the ads feed has not moved for longer than OI's own staleness
    -- threshold, in which case the window has frozen in place and protection_qualified fails closed.
    i.rate_window_is_stale,
    -- THE SANCTIONED RATE, WRITTEN THE WAY IT WAS AGREED. It used to be printed with FORMAT('$%.0f')
    -- inside the one instruction on the whole object that tells Ori to do something ("Bring spend
    -- back to $55 a day to restore it"). Harmless at $30 and $55; a $27.50 sanction would have
    -- printed an order to spend back to $28 — a wrong number in the only actionable sentence here.
    -- Whole dollars still read as whole dollars, and cents survive.
    IF(i.daily_investment = TRUNC(i.daily_investment),
       FORMAT("$%'d", CAST(i.daily_investment AS INT64)),
       FORMAT('$%.2f', i.daily_investment))                             AS daily_investment_text,
    -- The upstream column was called exemption_live until 2026-08-20. This object renamed its own
    -- copy because "live" reads as "in force", which is the thing it does not mean; the ambiguous
    -- name then survived one join upstream, where a new consumer would meet it first. Both are now
    -- protection_qualified, so the rename is no longer a local translation of a misleading name.
    i.ceiling_used_pct, i.days_left,
    -- ─── THE LOSS ALLOWANCE HAS ITS OWN WINDOW AND IT IS A THIRD ONE ───
    -- This row already publishes two windows: money_window (the settled 90 days) and rate_window (a
    -- trailing span of complete days ending at the ads watermark). The loss allowance percentage
    -- belonged to NEITHER.
    -- It is month-to-date NET PROFIT against a monthly ceiling, and its money is cut at the ORDERS
    -- watermark, not the ads one (1 to 17 August 2026 as of 2026-08-20 — read mtd_money_start /
    -- mtd_money_end for what it is now), a different span from both. An unnamed
    -- third window in a grid of two named ones is how a reader compares two numbers that do not cover
    -- the same days. It comes straight from V_INVEST_STATUS (mtd_money_start / mtd_money_end), which
    -- reads it from V_FAMILY_PNL rather than recomputing it, so there is no second definition of it.
    -- AND THE COLUMN NAME SAYS "SO FAR": this is a running month, always a partial one, and a bare
    -- percentage of a monthly allowance reads as a finished month unless the name refuses to.
    i.mtd_money_start, i.mtd_money_end,
    -- ─── AND THE PERCENTAGE MUST CARRY ITS OWN DENOMINATOR ───
    -- loss_allowance_used_pct_so_far published 22.3 on Bunny and 0.9 on LolliBall with nothing on the
    -- row to convert either into money: the allowances are $913 and $1,674, both on record in
    -- DE_LAUNCH_INVESTMENT, and a reader had to leave the object to find them. Both sides of the
    -- fraction now ride on the row beside the percentage. They cost no extra scan — V_INVEST_STATUS
    -- is already joined and already publishes both.
    i.monthly_loss_ceiling,
    i.mtd_net_profit,
    IF(i.ceiling_used_pct IS NULL OR i.mtd_money_start IS NULL OR i.mtd_money_end IS NULL, NULL,
       CONCAT(FORMAT_DATE('%-d %B', i.mtd_money_start), ' to ',
              FORMAT_DATE('%-d %B %Y', i.mtd_money_end),
              ', the part of this month that is measured'))            AS loss_allowance_window,
    i.org_m2, i.org_m1, i.org_m0, i.takeover_target_organic_units,
    -- NULL, not FALSE, when the family is unmeasured: "we did not measure it" is not "it is fine".
    -- COUNTIF and the loss ranking both skip NULLs, so an unmeasured family cannot be quietly
    -- counted as healthy — it is named as unmeasured instead, in the total's own sentence.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       (p.net_profit < 0 AND -p.net_profit > k.breakeven_band * p.ad_spend)) AS real_loss,
    (COALESCE(p.halo_factor, 0) >= k.wide_halo)                         AS wide_halo,
    -- ─── THE TWO PROTECTION STATES, KEPT APART ───
    -- QUALIFIED: what the sanction rules say. The upstream column is already the fail-closed answer —
    -- protection only on positive evidence of a rate on file, a measured spend at or under it, a loss
    -- ceiling on file and a measured loss under it. Renamed here because "live" reads as "in force",
    -- which is precisely the thing it does not mean.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.protection_qualified, NULL) AS protection_qualified,
    -- ENFORCED: what the machine is doing. TRUE if either source can see a protected campaign; FALSE
    -- only when a source has campaigns for this family and none of them is protected; NULL when
    -- neither source has heard of the family at all. That third state matters more than it looks: a
    -- missing measurement printed as FALSE would put "the coach has withdrawn it" back on the page,
    -- which is the sentence this whole round exists to delete.
    IF(COALESCE(bk.book, 'HARVEST') <> 'INVEST'
       OR (e.family IS NULL AND h.family IS NULL), NULL,
       COALESCE(e.campaigns_protected, 0) > 0
       OR COALESCE(h.campaigns_protected, 0) > 0)                       AS protection_enforced,
    -- THE GAP AS A NUMBER, PRICED PER DECISION KIND. NULL — never 0 — where the coach's budget pass
    -- has no row for the family: "it is holding nothing" and "we cannot see what it is holding" are
    -- different sentences, and only one of them is safe to print beside a live protection. Harvest
    -- families carry NULL because launch protection is not a concept in that book and an unexplained
    -- 0 in a grid is noise. The dollars are what applying the held decisions would FREE — a stop
    -- frees its whole budget, a trim frees only the part the coach wanted removed. See `held`.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.cuts_held,     NULL)  AS cuts_held,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.stops_held,    NULL)  AS stops_held,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.trims_held,    NULL)  AS trims_held,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.trims_unsized, NULL)  AS trims_unsized,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.stops_budget,  NULL)  AS stops_budget,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.trims_budget,  NULL)  AS trims_budget,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', h.cuts_budget,   NULL)  AS cuts_budget
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
    -- The share of the family's gross profit that Amazon's ad attribution did NOT claim, in whole
    -- percent: 1 - 1/halo, off the halo column immediately to its left. It is not a measure of
    -- organic demand — nothing here separates organic sales from ad-driven sales the attribution
    -- missed, and on this window 86.4% of ad orders were for a different asin than the advertised one
    -- (as of 2026-08-20; re-derive before quoting). See the note on the definition in `base`.
    b.share_of_return_with_no_ad_attribution_pct,
    -- COMPUTED, AND NOTHING APPLIES IT — the name is the caveat. Published on every family now,
    -- Harvest included, because no engine tests any family against it while Task 8 is on hold.
    b.keyword_bar_computed_not_applied,
    -- ORGANIC UNITS OVER TOTAL UNITS — a different fraction from the column three lines above, which
    -- is a share of gross profit. Both names now carry their denominator.
    b.organic_share_of_units_pct,
    -- 1 = the biggest real loss in the harvest book, the one the verdict says to fix first.
    b.loss_rank,
    -- WHICH WINDOW THE RATE COLUMNS BELOW BELONG TO. Deliberately a different, shorter window from
    -- the one above: a spend rate has to be current to bind on anything. Both are now on the row, so
    -- the mismatch is visible to someone reading the grid rather than the sentences. It names a real
    -- start AND a real end, in dates, off the upstream columns — no month name is inferred from
    -- today's calendar, and the string says in words how many complete days it holds.
    IF(b.spend_per_day IS NULL, NULL, b.rate_window_basis)              AS rate_window,
    b.rate_window_start,
    b.rate_window_end,
    b.rate_window_days,
    -- TRUE when the ads feed has stopped moving under the window, so the dates above are older than
    -- they should be and nothing can be certified against them. Published as a boolean as well as in
    -- words, because a consumer that has to branch on it should not have to read English to do it.
    b.rate_window_is_stale,
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
    -- NOT mtd_spend_per_day any more. The window behind it is a TRAILING span of complete days, not
    -- the month the reader is standing in, so a name containing "month to date" is false every day of
    -- the year. rate_window above says which days it covers.
    b.spend_per_day,
    b.spend_rate_ratio      AS times_over_agreed_rate,
    -- ─── THE TWO STATES, PUBLISHED SEPARATELY, AND THE GAP BETWEEN THEM IN DOLLARS ───
    -- QUALIFIED = has this launch earned protection under the rules Ori set (rate, end date, loss
    -- allowance). ENFORCED = is the coach actually applying protection to its campaigns. They are
    -- currently allowed to disagree and on 2026-08-20 they did, on both families: false and true.
    -- Named so a cold reader cannot read one as the other; the verdict says both out loud as well,
    -- because a column nobody explains is how the last three defects on this object got shipped.
    b.protection_qualified,
    b.protection_enforced,
    -- The size of that disagreement, SPLIT BY WHAT THE DECISION ACTUALLY IS, because "stop this
    -- campaign" and "trim this budget" are different jobs and are worth different money. The dollar
    -- columns are what APPLYING the held decisions would take off the daily budgets — round 3 published
    -- the full current budget of every held decision instead and overstated the book by 28%.
    b.cuts_held             AS cuts_the_coach_is_holding,
    b.stops_held            AS stops_the_coach_is_holding,
    b.trims_held            AS trims_the_coach_is_holding,
    b.stops_budget          AS daily_budget_the_held_stops_would_free,
    b.trims_budget          AS daily_budget_the_held_trims_would_free,
    b.cuts_budget           AS daily_budget_all_held_cuts_would_free,
    -- Trims the coach recorded with no target budget on record. They cannot be sized, so they add
    -- nothing to the dollars above and are counted here instead — the figure can only run low.
    b.trims_unsized         AS held_trims_with_no_target_on_record,
    -- MONTH-TO-DATE AND ON ITS OWN WINDOW, which is neither of the other two on this row.
    -- AND THE TWO SIDES OF THE FRACTION SIT BESIDE IT. The percentage alone published 22.3 and 0.9
    -- with its denominator nowhere on the row: the allowances are on record in DE_LAUNCH_INVESTMENT
    -- and a reader had to leave the object to turn either figure into money. Now the allowance and
    -- the loss so far are both here, in dollars, on the same window as the percentage.
    b.ceiling_used_pct      AS loss_allowance_used_pct_so_far,
    b.monthly_loss_ceiling  AS loss_allowance_dollars_for_the_month,
    -- The numerator, positive for a loss. NULL where the month's profit is not measured.
    IF(b.mtd_net_profit IS NULL, NULL, ROUND(-b.mtd_net_profit, 2))
                            AS loss_so_far_dollars_against_that_allowance,
    b.loss_allowance_window,
    b.days_left             AS days_left_on_sanction,
    -- THE TRAJECTORY, PUBLISHED. Absolute organic units over the last three complete months. This is
    -- the PRIMARY evidence an Invest family is judged on; it was read into the verdict and then
    -- discarded, so anyone charting the ramp or sorting on it had to re-derive it from upstream.
    -- The old names (org_m2 / org_m1 / org_m0) counted DOWN while their values ran FORWARD in time,
    -- so "0, 1, 126" only read as climbing if you already knew the convention.
    -- ROUND 2 RENAMED THEM INTO A WORSE AMBIGUITY AND NOBODY READ THE RESULT ALOUD. It shipped
    -- organic_units_1_month_ago beside organic_units_last_month — and on Bunny those read 44 and 69.
    -- "Last month" was July; "1 month ago" was JUNE. The plain reading of "1 month ago" is July, so a
    -- cold reader got the trajectory backwards from the column names alone. Relative English cannot
    -- carry this: "last" and "1 ago" are the same month in ordinary speech. The names are ORDINALS
    -- now, counted off the most recent COMPLETE calendar month (upstream: the three most recent months
    -- whose period_end falls before the start of the current month, newest first).
    b.org_m2                AS organic_units_3rd_last_complete_month,
    b.org_m1                AS organic_units_2nd_last_complete_month,
    b.org_m0                AS organic_units_last_complete_month,
    b.takeover_target_organic_units AS organic_units_to_stand_alone,
    -- ACCOUNT-LEVEL, AND THE NAMES NOW SAY SO. These two lived on the HARVEST TOTAL row under the
    -- names unattributed_spend and spend_coverage_pct — three columns from book = 'HARVEST', with
    -- nothing in either name to stop a reader taking 90.73% for the harvest book's coverage. The
    -- header explained it; the names did not, and a name is what a grid reader reads. They are
    -- account-wide figures published on one row because they belong to NEITHER book.
    CAST(NULL AS FLOAT64)   AS account_ad_spend_in_neither_book,
    CAST(NULL AS FLOAT64)   AS account_ad_spend_reaching_a_family_pct,
    CASE
      -- ───────── INVEST: sanction adherence + trajectory. Never a profit verdict. ─────────
      WHEN b.book = 'INVEST' THEN CONCAT(
        -- ───────────────────────────────────────────────────────────────────────────────────
        -- THE RATE, THE RULE, AND THE MACHINE — three clauses, in that order, never merged.
        -- Until 2026-08-20 this branch collapsed the last two: being over the sanctioned rate was
        -- reported, present indicative, as "it has lost its launch protection and is now judged on
        -- money like every other family". Nothing had withdrawn anything. The coach reads
        -- V_LAUNCH_EXEMPTION, whose exempt_active is hardcoded TRUE, and on the strength of it was
        -- holding 10 budget decisions worth $147.86 a day on exactly the two families this sentence
        -- told Ori were already being trimmed. The rule clause may now only describe the RULE, and the
        -- machine clause must follow it and say what is actually happening — including, in dollars,
        -- what is not.
        -- ───────────────────────────────────────────────────────────────────────────────────
        CASE
          WHEN b.daily_investment IS NULL THEN CONCAT(
            b.family, ' is in the investment book, but there is no approved daily spend on record for it, ',
            'so nothing is holding it. Write the sanction down or move it back to being judged on money.')
          ELSE CONCAT(
            -- 1. THE RATE.
            -- "so far this month" was never right: the rate is measured on a trailing span of
            -- complete days ending one day behind the ads feed, which is not the month the reader
            -- is standing in. The phrase comes from the same upstream window the rate_window column
            -- publishes, so the sentence and the column can never disagree.
            b.family, ' is spending ', FORMAT('$%.2f', b.spend_per_day), ' a day ',
            b.rate_window_phrase, ' ',
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
                -- NAME THE DECISIONS, THEN PRICE THEM. "6 cuts worth $130 a day" was two errors in one
                -- clause: it hid that four of those six only trim a budget rather than end a campaign,
                -- and it priced all six at their full current budget, which read $130 against a true
                -- $89. What a reader wants to know is what to do and what it is worth.
                CASE
                  WHEN COALESCE(b.stops_held, 0) > 0 AND COALESCE(b.trims_held, 0) > 0 THEN CONCAT(
                    CAST(b.stops_held AS STRING), IF(b.stops_held = 1, ' campaign stop', ' campaign stops'),
                    ' and ', CAST(b.trims_held AS STRING),
                    IF(b.trims_held = 1, ' budget trim', ' budget trims'))
                  WHEN COALESCE(b.stops_held, 0) > 0 THEN CONCAT(
                    CAST(b.stops_held AS STRING), IF(b.stops_held = 1, ' campaign stop', ' campaign stops'))
                  ELSE CONCAT(
                    CAST(b.trims_held AS STRING), IF(b.trims_held = 1, ' budget trim', ' budget trims'))
                END,
                ' on this family. Applying them would take ',
                FORMAT("$%'d", CAST(ROUND(b.cuts_budget) AS INT64)), ' a day off its budgets',
                IF(COALESCE(b.stops_held, 0) > 0 AND COALESCE(b.trims_held, 0) > 0,
                   CONCAT(' — ', FORMAT("$%'d", CAST(ROUND(b.stops_budget) AS INT64)),
                          ' by stopping campaigns and ',
                          FORMAT("$%'d", CAST(ROUND(b.trims_budget) AS INT64)),
                          ' by trimming the rest'),
                   ''),
                '. ',
                IF(COALESCE(b.trims_unsized, 0) > 0,
                   CONCAT(CAST(b.trims_unsized AS STRING),
                          IF(b.trims_unsized = 1,
                             ' of those trims has no target budget on record, so the real figure is higher. ',
                             ' of those trims have no target budget on record, so the real figure is higher. ')),
                   ''),
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
        -- ─────────────────────────────────────────────────────────────────────────────────────
        -- THE TRAJECTORY CLAUSE, AND THREE THINGS IT USED TO GET WRONG.
        --
        -- 1. IT DECIDED THE WORD ON TWO MONTHS AND THEN PRINTED THREE. "Climbing" was org_m0 >
        --    org_m1 and nothing else, so a V — down, then up past the start — read as "climbing"
        --    beside a series that showed the dip. The word is now decided on every month it prints:
        --    climbing means each step up, falling means each step down, and a series that turns is
        --    described as a series that turns rather than collapsed into one direction.
        -- 2. IT SAID "SALES" OVER A COUNT OF UNITS. org_m0/m1/m2 are organic UNITS
        --    (V_FAMILY_PNL.organic_units) and the sentence ended in "units" while it began in
        --    "sales". It says units at both ends now.
        -- 3. A LEADING ZERO THAT MEANT "NOT BORN YET" READ AS A MEASUREMENT. LolliBall printed
        --    "0, then 1, then 126" — and its first sale was 2026-06-26, so the 0 is a month in which
        --    the product did not exist. A zero that means "there was nothing to measure" is not a
        --    measurement, and putting it at the head of a ramp understates the start and flatters the
        --    climb. Months before the product existed are dropped and the count in the sentence
        --    follows what is actually printed.
        --    HOW THE PRE-EXISTENCE TEST IS MADE WITHOUT RE-DERIVING A WINDOW: launch_age_months is
        --    DATE_DIFF(today, first_sale_date, MONTH) computed in V_BOOK_ASSIGNMENT, and BigQuery's
        --    MONTH difference counts month boundaries, so it is identically the number of months back
        --    that the first-sale MONTH sits. The printed months are 1, 2 and 3 months back
        --    (org_m0 / org_m1 / org_m2 are the last three COMPLETE calendar months), so org_m2 is a
        --    month the product existed in exactly when launch_age_months >= 3, and org_m1 exactly
        --    when it is >= 2. Verified 2026-08-20 on all six families: launch_age_months equals
        --    DATE_DIFF(DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH),
        --              DATE_TRUNC(first_sale_date, MONTH), MONTH) on every row. Nothing here reads
        --    CURRENT_DATE; a family with no first sale on record keeps every month it has.
        -- ─────────────────────────────────────────────────────────────────────────────────────
        CASE
          -- Two months of existence are the minimum for a direction. org_m1 present is not enough on
          -- its own: if the product did not exist that month, there is one real month, not two.
          WHEN b.org_m1 IS NULL OR COALESCE(b.launch_age_months, 99) < 2
            THEN ' There is not enough history yet to tell whether organic units are climbing.'
          ELSE CONCAT(
            ' Organic units are ',
            -- THREE PRINTED MONTHS -> decided on all three.
            IF(b.org_m2 IS NOT NULL AND COALESCE(b.launch_age_months, 99) >= 3,
               CASE WHEN b.org_m0 = b.org_m1 AND b.org_m1 = b.org_m2            THEN 'flat'
                    WHEN b.org_m0 > b.org_m1 AND b.org_m1 >= b.org_m2           THEN 'climbing'
                    WHEN b.org_m0 < b.org_m1 AND b.org_m1 <= b.org_m2           THEN 'falling'
                    WHEN b.org_m0 > b.org_m1                                    THEN 'up on the month before but not climbing steadily'
                    WHEN b.org_m0 < b.org_m1                                    THEN 'down on the month before, after rising into it'
                    ELSE 'level with the month before, but not steady across the three' END,
               -- TWO PRINTED MONTHS -> two is all there is to decide on.
               CASE WHEN b.org_m0 > b.org_m1 THEN 'climbing'
                    WHEN b.org_m0 < b.org_m1 THEN 'falling'
                    ELSE 'flat' END),
            ' — ',
            IF(b.org_m2 IS NULL OR COALESCE(b.launch_age_months, 99) < 3, '',
               CONCAT(CAST(b.org_m2 AS STRING), ', then ')),
            CAST(b.org_m1 AS STRING), ', then ', CAST(b.org_m0 AS STRING),
            ' units over the last ',
            IF(b.org_m2 IS NULL OR COALESCE(b.launch_age_months, 99) < 3, 'two', 'three'),
            ' complete months',
            -- Say why a month is missing, so a two-month series does not read as missing data.
            IF(b.org_m2 IS NOT NULL AND COALESCE(b.launch_age_months, 99) < 3,
               CONCAT('. The month before those is left out because ', b.family,
                      ' had not sold anything yet.'),
               '.'))
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
        END,
        -- WHEN THE WINDOW HAS FROZEN, SAY SO IN THE SENTENCE, not only in the window column. The
        -- window always holds its full count of complete days, but it is anchored on the ads feed:
        -- if the feed stops arriving the window stops moving and the rate above describes days that
        -- are no longer recent. A reader who assumes it is current would read a frozen rate as a live
        -- one — the same class of error as the window string an earlier round replaced, just made in
        -- the reader's head. Upstream, this state also withdraws protection.
        IF(COALESCE(b.rate_window_is_stale, FALSE),
           CONCAT(' The advertising figures behind that rate have stopped arriving, so it describes ',
                  'the days named above and not the days since — nothing can be certified against it ',
                  'until the feed catches up.'),
           ''))

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

      -- ───────────────────────────────────────────────────────────────────────────────────────
      -- THE RATIO COUNTS EVERYTHING THE FAMILY EARNED. IT DOES NOT COUNT WHAT THE ADS CAUSED.
      -- Every Harvest branch below used to gloss total_net_roas as "once the organic sales those ads
      -- pull in are counted" — a causal claim, and nothing in this pipeline measures it.
      -- total_net_roas is SUM(sales - cogs) / SUM(ad_cost) over the WHOLE family
      -- (V_FAMILY_PNL.sql), so its numerator is 100% of the family's gross profit, including every
      -- sale that would have happened with no advertising at all. Nothing anywhere decides which
      -- organic sales the ads caused; the halo is a measured RATIO, not an attributed effect.
      -- This is the founding error of this design pointing the other way. The ads-only lens
      -- understated a family by excluding profit it had earned; "the organic sales those ads pull in"
      -- overstates by handing the ads credit for profit nobody showed they produced. Both are the
      -- same mistake — a number described as more than it measured.
      -- WHAT SURVIVES IS THE POINT THAT MATTERS: judged on the ads-only figure alone, a family that
      -- is carrying the account gets cut. Every branch says what the ratio is — everything earned
      -- against what the ads cost, attributed or not — and leaves causation unclaimed.
      -- ───────────────────────────────────────────────────────────────────────────────────────
      WHEN b.net_profit >= 0 THEN CONCAT(
        b.family, ' made ', FORMAT("$%'d", CAST(b.net_profit AS INT64)), ' over the last 90 days on ',
        FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend — ', b.total_net_roas_text,
        ' of profit for every ad dollar counting everything the family earned, attributed to the ads ',
        'or not, against ', b.ads_net_roas_text,
        ' counting only the sales the ads were credited with. Keep it running.')

      -- ───────────────────────────────────────────────────────────────────────────────────────
      -- THE BREAK-EVEN BRANCH MAY NOT CALL A LOSS A PROFIT, AND ROUNDING MAY NOT DECIDE IT.
      -- This branch fires on a family whose loss is smaller than the breakeven band — real money, just
      -- too little to be worth a job. On 2026-08-20 that was Bottle: net profit -$7.54, return 0.998.
      -- The sentence rounded 0.998 to "$1.00" and then asserted, categorically, "a family that is
      -- paying its way" — on a family a hair SHORT of paying its way, in the same session whose own
      -- documentation called that 0.998 a known knife edge. The useful point is the one that survives:
      -- do not cut this on the ads figure. It is made now WITHOUT claiming profitability, the ratio is
      -- written so it cannot round across $1.00 (total_net_roas_text), and the halo clause prints a
      -- MEASURED share instead of the word "most" — see the wide_halo note in k.
      -- THE HALO CLAUSE NAMES WHAT IT MEASURES. It read "36% of that return comes from the organic
      -- sales rather than from the ads themselves", which is 1 - 1/halo under a description it does
      -- not fit: that share is gross profit Amazon's ad attribution did not CLAIM, and the missed
      -- attribution inside it is large — 86.4% of ad orders on this window were for a different asin
      -- than the advertised one (as of 2026-08-20, re-derive before quoting). The clause states the
      -- share and stops there; the conclusion it supports is unchanged and does not need the cause.
      -- ───────────────────────────────────────────────────────────────────────────────────────
      WHEN NOT b.real_loss THEN CONCAT(
        b.family, ' came within ', FORMAT("$%'d", CAST(-b.net_profit AS INT64)),
        ' of covering its costs over the last 90 days on ', FORMAT("$%'d", CAST(b.ad_spend AS INT64)),
        ' of ad spend — a shortfall too small to be worth acting on, but a shortfall, not a profit. ',
        'It brings back ', b.total_net_roas_text,
        ' for every ad dollar counting everything it earned, attributed to the ads or not, against ',
        b.ads_net_roas_text, ' counting only the sales the ads were credited with.',
        IF(b.wide_halo AND b.share_of_return_with_no_ad_attribution_pct IS NOT NULL,
           CONCAT(' ', CAST(b.share_of_return_with_no_ad_attribution_pct AS STRING),
                  '% of what it earned carries no ad attribution at all, so the ads-only figure ',
                  'understates what this family is doing — do not cut it on that figure alone.'),
           ''))

      ELSE CONCAT(
        b.family, ' lost ', FORMAT("$%'d", CAST(-b.net_profit AS INT64)), ' over the last 90 days on ',
        FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend',
        IF(b.loss_rank = 1,
           ' — the biggest loss in the harvest book, so this is the one to fix first. ',
           CONCAT(' — a smaller loss than ', b.worst_family, "'s ",
                  FORMAT("$%'d", CAST(-b.worst_net_profit AS INT64)), ', so it waits behind that one. ')),
        'It brings back ', b.total_net_roas_text,
        ' for every ad dollar even counting everything it earned, attributed to the ads or not, ',
        'against ', b.ads_net_roas_text, ' counting only the sales the ads were credited with.')
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
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL) AS n_priced,
    SUM(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, daily_investment, NULL)) AS daily_investment,
    -- ─── THE BOOK'S RATE IS COMPUTED OVER THE BOOK, NOT ADDED UP FROM ROUNDED FAMILY RATES ───
    -- This was SUM(spend_per_day), and every term in that sum had already been rounded to the cent
    -- upstream, so the book rate was a sum of roundings rather than a rate: nothing guaranteed it
    -- equalled the book's own spend over the book's own window, and the error grows with the number
    -- of families. It is now the same arithmetic the family rate uses, one level up — the dollars the
    -- book spent inside the window, divided by the days in it. The window is a single span shared by
    -- every family (derived once upstream), so MAX(rate_window_days) is picking a constant.
    -- Measured 2026-08-20: the two agree at $161.30 today, because two families rounding by fractions
    -- of a cent cannot separate them. That agreement is a coincidence of this day's data, not a
    -- property — re-derive, do not assume it holds.
    ROUND(SAFE_DIVIDE(
      SUM(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_spend, NULL)),
      NULLIF(MAX(rate_window_days), 0)), 2)                             AS spend_per_day,
    -- ONE window covers every family in the book — it is derived once upstream, not per family — so
    -- MAX is picking a constant, not choosing between rival answers. Carried onto the total so the
    -- book row names the same days its family rows do.
    MAX(rate_window_basis)                         AS rate_window_basis,
    MAX(rate_window_phrase)                        AS rate_window_phrase,
    MAX(rate_window_start)                         AS rate_window_start,
    MAX(rate_window_end)                           AS rate_window_end,
    MAX(rate_window_days)                          AS rate_window_days,
    -- NOT LOGICAL_OR(COALESCE(..., FALSE)). Coalescing first turns "this book has no rate window at
    -- all" into a confident FALSE — "no, the window has not frozen" — on the HARVEST total, which has
    -- no rate. LOGICAL_OR ignores NULLs and returns NULL when every input is NULL, which is the
    -- honest answer for a book that never had a window.
    LOGICAL_OR(rate_window_is_stale)               AS rate_window_is_stale,
    COUNTIF(real_loss)                             AS n_real_losses,
    -- ─── THE OTHER TWO STATES A MEASURED FAMILY CAN BE IN, BECAUSE THE TOTAL SPOKE FOR THEM ───
    -- The harvest total said "fix that one and the rest is working" while Bottle's own row, printed
    -- two lines below it, said Bottle was short of covering its costs. "The rest" included Bottle.
    -- The total is the first thing anyone reads, so a claim it makes about families it does not name
    -- has to be true of every one of them. real_loss is a THREE-way split, not two: earning, short by
    -- less than the breakeven band, and losing real money. All three are counted here so the sentence
    -- can describe the book instead of implying the remainder.
    COUNTIF(money_measured AND net_profit >= 0)    AS n_earning,
    COUNTIF(money_measured AND net_profit < 0 AND NOT COALESCE(real_loss, FALSE)) AS n_small_shortfall,
    -- Named, and ordered by family so two consecutive pulls are byte-identical.
    STRING_AGG(IF(money_measured AND net_profit < 0 AND NOT COALESCE(real_loss, FALSE), family, NULL),
               ' and ' ORDER BY family)            AS small_shortfall_families,
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
    -- SUMMED PER DECISION KIND, so the book total is priced the same way the family rows are: stops at
    -- their whole budget, trims at only the part the coach wanted removed. Summing current_budget over
    -- both kinds is what published $188.86 against a true $147.86.
    SUM(cuts_held)                                 AS cuts_held,
    SUM(stops_held)                                AS stops_held,
    SUM(trims_held)                                AS trims_held,
    SUM(trims_unsized)                             AS trims_unsized,
    SUM(stops_budget)                              AS stops_budget,
    SUM(trims_budget)                              AS trims_budget,
    SUM(cuts_budget)                               AS cuts_budget,
    ARRAY_AGG(IF(COALESCE(real_loss, FALSE), family, NULL)
              IGNORE NULLS ORDER BY net_profit ASC, family ASC LIMIT 1)[SAFE_OFFSET(0)] AS worst_family,
    ARRAY_AGG(IF(COALESCE(real_loss, FALSE), net_profit, NULL)
              IGNORE NULLS ORDER BY net_profit ASC, family ASC LIMIT 1)[SAFE_OFFSET(0)] AS worst_net_profit,
    -- Named, not just counted: "one family is missing" sends nobody anywhere. Ordered by family so
    -- the sentence is byte-identical on two consecutive pulls.
    STRING_AGG(IF(money_measured, NULL, family), ' and ' ORDER BY family) AS unmeasured_families,
    STRING_AGG(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, NULL, family),
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
    CAST(NULL AS INT64)                              AS share_of_return_with_no_ad_attribution_pct,
    CAST(NULL AS FLOAT64)                            AS keyword_bar_computed_not_applied,
    CAST(NULL AS FLOAT64)                            AS organic_share_of_units_pct,
    CAST(NULL AS INT64)                              AS loss_rank,
    -- Same window, same words, same source as the family rows — never re-derived from today's
    -- calendar, which is what let this string name a month the rate was not measured over.
    IF(a.spend_per_day IS NULL, NULL, a.rate_window_basis)              AS rate_window,
    a.rate_window_start,
    a.rate_window_end,
    a.rate_window_days,
    a.rate_window_is_stale,
    CAST(NULL AS STRING)                             AS launch_stage,
    CAST(NULL AS INT64)                              AS launch_age_months,
    a.daily_investment,
    a.spend_per_day,
    ROUND(SAFE_DIVIDE(a.spend_per_day, NULLIF(a.daily_investment, 0)), 2) AS times_over_agreed_rate,
    -- A BOOK IS NOT IN ONE PROTECTION STATE, so these two stay NULL on a total and the counts behind
    -- them are spoken in the verdict instead. The two columns that DO belong on a total are the held
    -- decisions and the budget they cover: those add up honestly, they are the number Ori acts on,
    -- and Harvest sums to NULL rather than 0 because no family in that book contributes one.
    CAST(NULL AS BOOL)                               AS protection_qualified,
    CAST(NULL AS BOOL)                               AS protection_enforced,
    a.cuts_held                                      AS cuts_the_coach_is_holding,
    a.stops_held                                     AS stops_the_coach_is_holding,
    a.trims_held                                     AS trims_the_coach_is_holding,
    a.stops_budget                                   AS daily_budget_the_held_stops_would_free,
    a.trims_budget                                   AS daily_budget_the_held_trims_would_free,
    a.cuts_budget                                    AS daily_budget_all_held_cuts_would_free,
    a.trims_unsized                                  AS held_trims_with_no_target_on_record,
    -- A loss allowance is a per-family sanction; a book has no single one, and no window of its own
    -- for one either.
    CAST(NULL AS FLOAT64)                            AS loss_allowance_used_pct_so_far,
    CAST(NULL AS FLOAT64)                            AS loss_allowance_dollars_for_the_month,
    CAST(NULL AS FLOAT64)                            AS loss_so_far_dollars_against_that_allowance,
    CAST(NULL AS STRING)                             AS loss_allowance_window,
    CAST(NULL AS INT64)                              AS days_left_on_sanction,
    -- A trajectory is a per-family fact; summing organic units across a book would invite exactly the
    -- kind of blended number this object exists to refuse.
    CAST(NULL AS INT64)                              AS organic_units_3rd_last_complete_month,
    CAST(NULL AS INT64)                              AS organic_units_2nd_last_complete_month,
    CAST(NULL AS INT64)                              AS organic_units_last_complete_month,
    CAST(NULL AS INT64)                              AS organic_units_to_stand_alone,
    -- ACCOUNT-LEVEL, BELONGING TO NEITHER BOOK, AND ON THE HARVEST TOTAL ROW ONLY — the one row that
    -- carries the sentence explaining it. Published on both totals it read as $8,765 twice, next to
    -- an INVEST spend total, with nothing on that row saying what it was.
    IF(s.book = 'HARVEST', c.unattributed_spend, NULL)  AS account_ad_spend_in_neither_book,
    IF(s.book = 'HARVEST', c.spend_coverage_pct, NULL)  AS account_ad_spend_reaching_a_family_pct,
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
              -- ─────────────────────────────────────────────────────────────────────────────
              -- "AND THE REST IS WORKING" WAS A CLAIM ABOUT FAMILIES THIS ROW DOES NOT NAME.
              -- Round 2 took "a family that is paying its way" off Bottle's own row and left the
              -- harvest TOTAL saying "fix that one and the rest is working" — printed ABOVE Bottle,
              -- and the first thing anyone reads. "The rest" included Bottle, whose own row two lines
              -- later said it was short of covering its costs. The total and the family row said
              -- opposite things about the same family, and the total said it first.
              -- The claim is gone. What replaces it is not a hedge: the remainder is COUNTED and
              -- described, in the clause below, so the total says how many are earning and names the
              -- ones that are short. real_loss is a three-way split and this sentence now uses all
              -- three sides of it.
              -- ─────────────────────────────────────────────────────────────────────────────
              WHEN a.n_real_losses = 1 THEN CONCAT(
                a.worst_family, ' is the only one losing real money, at ',
                FORMAT("$%'d", CAST(-a.worst_net_profit AS INT64)),
                ' — fix that one first.')
              ELSE CONCAT(
                CAST(a.n_real_losses AS STRING), ' of them are losing real money, and the biggest is ',
                a.worst_family, ' at ',
                FORMAT("$%'d", CAST(-a.worst_net_profit AS INT64)),
                ' — start there, because that is where the dollars are.')
            END,
            -- ─── AND THE REST OF THE BOOK, STATED RATHER THAN LEFT TO BE INFERRED ───
            -- A family short of covering its costs by less than the breakeven band is neither a job
            -- nor a success, and it is the state the total used to swallow. It is named here, with
            -- the same words its own row uses, so the two rows cannot disagree; and where every other
            -- measured family IS earning, the total is free to say so, because then it is true.
            CASE
              WHEN COALESCE(a.n_small_shortfall, 0) > 0 THEN CONCAT(
                ' ', a.small_shortfall_families,
                IF(a.n_small_shortfall = 1, ' is', ' are'), ' short of covering ',
                IF(a.n_small_shortfall = 1, 'its', 'their'), ' costs',
                IF(a.n_real_losses > 0, ' too', ''),
                ', by too little to be worth acting on.',
                IF(COALESCE(a.n_earning, 0) > 0,
                   CONCAT(' The other ', CAST(a.n_earning AS STRING),
                          IF(a.n_earning = 1, ' family is earning.', ' families are earning.')),
                   ''))
              WHEN a.n_real_losses > 0 AND COALESCE(a.n_earning, 0) > 0 THEN CONCAT(
                ' The other ', CAST(a.n_earning AS STRING),
                IF(a.n_earning = 1, ' family is earning.', ' families are earning.'))
              ELSE ''
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
        -- AND SAY WHAT IT ACTUALLY IS. This clause used to end "Those ads ran against products that
        -- are not carrying a family name" — plural, which reads as a scattered mapping failure across
        -- the catalogue. Re-derived 2026-08-20: ONE key, and the key is the literal placeholder
        -- 'Unknown' that the ads fact writes when a row names no advertised product at all. That is not
        -- a product missing its family name; it is a row with no product on it, which no amount of
        -- product mapping will ever reach. The branch reads the measured count, so it cannot go stale
        -- into a different lie: one placeholder, one real product, or several, each said plainly.
        IF(c.unattributed_spend > 0,
           CONCAT(' Separately, ', FORMAT("$%'d", CAST(c.unattributed_spend AS INT64)),
                  ' of advertising over the same 90 days — ', FORMAT('%.1f', 100 - c.spend_coverage_pct),
                  '% of everything the account spent — reached no family at all and is in neither book. ',
                  CASE
                    WHEN c.unattributed_products = 1 AND c.unattributed_product_key = 'Unknown' THEN
                      CONCAT('None of those ads records the product it was selling: every one of them ',
                             'carries "Unknown" where the product should be, so no product name can ',
                             'attach that money to a family. It has to be attributed by campaign instead.')
                    WHEN c.unattributed_products = 1 THEN
                      CONCAT('All of it ran against one product that is not carrying a family name — ',
                             'check the product mapping.')
                    ELSE
                      CONCAT('Those ads ran against ', CAST(c.unattributed_products AS STRING),
                             ' products that are not carrying a family name — check the product mapping.')
                  END),
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
            FORMAT('$%.2f', a.spend_per_day),
            ' a day in total ', a.rate_window_phrase, ' against the ',
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
            -- was simply false: the coach was protecting both of them and holding 10 decisions worth
            -- $147.86 a day on the strength of it. Qualifying for protection is what the rate decides;
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
              -- PRICED THE SAME WAY THE FAMILY ROWS ARE. This sentence said "10 budget cuts worth $189
              -- a day", which was the full current budget of every held decision — six of them stops,
              -- worth their whole budget, and four of them trims, worth only the part being trimmed.
              -- The true figure is $148. It is the one number on this row Ori acts on, and he was
              -- handed it 28% high.
              WHEN a.n_protection_gap > 0 AND COALESCE(a.cuts_held, 0) > 0 THEN CONCAT(
                'The coach is not enforcing that: it is still protecting ',
                CAST(a.n_protection_gap AS STRING),
                IF(a.n_protection_gap = 1, ' family that no longer qualifies', ' families that no longer qualify'),
                ', and it is holding ',
                CASE
                  WHEN COALESCE(a.stops_held, 0) > 0 AND COALESCE(a.trims_held, 0) > 0 THEN CONCAT(
                    CAST(a.stops_held AS STRING), IF(a.stops_held = 1, ' campaign stop', ' campaign stops'),
                    ' and ', CAST(a.trims_held AS STRING),
                    IF(a.trims_held = 1, ' budget trim', ' budget trims'))
                  WHEN COALESCE(a.stops_held, 0) > 0 THEN CONCAT(
                    CAST(a.stops_held AS STRING), IF(a.stops_held = 1, ' campaign stop', ' campaign stops'))
                  ELSE CONCAT(
                    CAST(a.trims_held AS STRING), IF(a.trims_held = 1, ' budget trim', ' budget trims'))
                END,
                ' between them. Applying those would take ',
                FORMAT("$%'d", CAST(ROUND(a.cuts_budget) AS INT64)), ' a day off their budgets',
                IF(COALESCE(a.stops_held, 0) > 0 AND COALESCE(a.trims_held, 0) > 0,
                   CONCAT(' — ', FORMAT("$%'d", CAST(ROUND(a.stops_budget) AS INT64)),
                          ' by stopping campaigns and ',
                          FORMAT("$%'d", CAST(ROUND(a.trims_budget) AS INT64)),
                          ' by trimming the rest'),
                   ''),
                '. ',
                IF(COALESCE(a.trims_unsized, 0) > 0,
                   CONCAT(CAST(a.trims_unsized AS STRING),
                          IF(a.trims_unsized = 1,
                             ' of those trims has no target budget on record, so the real figure is higher. ',
                             ' of those trims have no target budget on record, so the real figure is higher. ')),
                   ''),
                'Nothing is touching those budgets today — bring the rates back inside the sanctions, ',
                'or pull the budgets yourself. ')
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
            -- AND IT MAY NOT CALL A LOSS A SANCTION. It said "The $3,622 they cost over the last 90
            -- days is money you agreed to spend" — but $3,622 is NET PROFIT (sales minus COGS minus
            -- ad cost), and what Ori sanctioned is a SPEND RATE in dollars a day. The two are
            -- different quantities: the ad spend behind that same window is $9,651, and no
            -- declaration anywhere says "you may lose $3,622". Calling the loss the agreed thing
            -- makes any loss look pre-approved however far the spending has run past its rate, which
            -- is the opposite of what the sanction does. The clause now names the spend as the
            -- sanctioned quantity, the shortfall as its consequence, and keeps them apart.
            CASE
              WHEN COALESCE(a.n_measured, 0) = 0 OR a.net_profit IS NULL THEN CONCAT(
                'Nothing they sell is being counted under their family names yet, so there is no ',
                'measured cost for them over the last 90 days — check the product mapping.')
              WHEN a.net_profit < 0 THEN CONCAT(
                'What you sanctioned is the spending, not the shortfall: they spent ',
                FORMAT("$%'d", CAST(a.ad_spend AS INT64)),
                ' on advertising over the last 90 days and finished ',
                FORMAT("$%'d", CAST(-a.net_profit AS INT64)), ' behind after costs. ',
                IF(a.n_over_rate = 0,
                   CONCAT('That spending is inside the rates you approved, so the shortfall is the ',
                          'price of the investment, not a loss to chase.'),
                   CONCAT('The shortfall is the price of the investment and not a loss to chase — but ',
                          'right now they are spending ',
                          FORMAT('$%.2f', a.spend_per_day - a.daily_investment),
                          ' a day above the rates you approved, and that part of the spending you ',
                          'never agreed to.',
                          -- ...and do not ask for the correction twice. Where the coach is still
                          -- protecting families that no longer qualify, the clause above has already
                          -- given the instruction, with the budgets attached; repeating a thinner
                          -- version of it here is how a reader learns to skim the last sentence.
                          IF(COALESCE(a.n_protection_gap, 0) > 0, '',
                             ' Bring the rate back inside the sanction.'))))
              ELSE CONCAT(
                'They spent ', FORMAT("$%'d", CAST(a.ad_spend AS INT64)),
                ' on advertising over the last 90 days and still finished ',
                FORMAT("$%'d", CAST(a.net_profit AS INT64)), ' ahead after costs, while building.')
            END,
            -- ...unless NOTHING in the book is measured, in which case the branch above has already
            -- said so and there are no figures left for this clause to point at.
            IF(a.n_families = a.n_measured OR COALESCE(a.n_measured, 0) = 0, '',
               CONCAT(' ', a.unmeasured_families,
                      IF(a.n_families - a.n_measured = 1, ' has', ' have'),
                      ' nothing measured at all, so neither of those figures includes ',
                      IF(a.n_families - a.n_measured = 1, 'it.', 'them.'))),
            -- Same caveat as the family rows carry, for the same reason: the window holds its full
            -- count of complete days, but it is anchored on the ads feed, and a feed that stops
            -- arriving freezes it in place.
            IF(COALESCE(a.rate_window_is_stale, FALSE),
               CONCAT(' The advertising figures behind those rates have stopped arriving, so they ',
                      'describe the days named above and not the days since — nothing can be ',
                      'certified against them until the feed catches up.'),
               ''))
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
