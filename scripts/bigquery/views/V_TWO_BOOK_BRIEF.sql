-- =============================================
-- V_TWO_BOOK_BRIEF — the morning read: two books, never blended.
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §6.
--
-- WHY THIS OBJECT EXISTS. An ads-attributed, single-book reading of a month can show an account loss
-- while the mature families are earning and a deliberate, declared launch is spending — because the
-- ads-only lens excludes the units it did not get to claim. This view reports "Harvest earned X;
-- Invest spent Y of its declared budget" and NEVER adds those two together.
--
-- THE FIGURES BEHIND THAT STORY ARE NOT REPEATED HERE, ON PURPOSE. The spec's §1 quarantine box
-- carries the one-off findings that caused this design, and it says of them: "never copy one into a
-- header, a registry entry, a plan step or an SOP." Three of those figures used to sit in this
-- header. THE BOX IS RIGHT AND THE HEADER WAS WRONG — a quarantine that the quarantined document's
-- own consumers copy out of is not a quarantine. They are deleted from here. Read them in §1, where
-- they are dated and labelled as history.
--
-- THE TWO BOOKS ARE NEVER ADDED. One TOTAL row per book, no grand total, by construction: the totals
-- are built off a two-row book spine and nothing here ever aggregates across `book`. A single
-- combined number would recreate the exact lie this design exists to kill, so the acceptance
-- assertion pins total_rows = 2 forever.
--
-- NET PROFIT LEADS, THE RATIO EXPLAINS IT. Two families can look identical by ratio and differ by
-- three orders of magnitude in dollars; ranked by ratio you fix the small one. So the Harvest losers
-- are RANKED BY DOLLARS, the worst is named in its own verdict and in the book total, and a loss
-- smaller than the declared breakeven band is called noise in words.
--
-- THE INVEST ROWS DO NOT CARRY A PROFIT VERDICT. Months 0-3 are judged on adherence to the sanction
-- and on organic trajectory, never on profitability (Ori 2026-08-19). An Invest verdict says: the
-- spend rate against what was sanctioned, what the sanction rules make of that, what the coach is
-- actually doing, and the organic trajectory in absolute units. net_profit is still published — it
-- is the cost of the investment, and the book name on the row is the frame.
--
-- WINDOW HONESTY. The P&L columns are the settled 90-day window; the spend rate is a SHORT, CURRENT
-- window, because a rate must be current to bind. Both windows ride on the row (money_window,
-- rate_window) and every sentence names the one it is quoting. The rate window is READ from
-- V_INVEST_STATUS, never re-derived from a calendar here — it is a trailing span of complete days
-- ending behind the ads feed, and any string built from CURRENT_DATE will eventually describe a
-- different span from the one the number was measured on.
--
-- VERDICTS ARE PLAIN SENTENCES. No rule names, no engine internals, no bare metric codes. Plain is
-- not the same as loose: plain English makes a metric easy to describe as MORE than it is. If you
-- add a branch, read it aloud, then ask what the sentence asserts that the arithmetic behind it does
-- not establish.
--
-- ---------------------------------------------------------------------------------------------
-- THE MECHANICAL RULES THE VERDICTS MUST OBEY.
--
-- Five repair rounds each fixed a real defect and each shipped a NEW self-contradiction in the
-- prose. Ori has kept the prose format. So the constraints on it are mechanical and ASSERTED, not
-- stylistic: the next agent to touch a verdict trips a check rather than a reviewer. Every rule
-- below is enforced by the acceptance query at the foot of this file, which runs against the
-- DEPLOYED view in a single pass.
--
-- FIRST, HONESTLY, ABOUT WHAT A RULE HERE CAN AND CANNOT BE. A rule that keys on a FIXED LIST OF
-- WORDS is a TRIPWIRE: it catches the exact evasion that was found last time and nothing else. Round
-- 5 banned the concessive connectives and round 6 found the same self-contradiction rebuilt out of
-- "so". A rule that keys on a PUBLISHED COLUMN is a CONSTRAINT: the column is computed from the data
-- by the same expression the prose is built from, so prose and column cannot disagree without the
-- check firing, and no rewrite of the sentence can move the column. Rules 5 and 6 are constraints.
-- Rules 1 and 4 are tripwires with a constraint bolted to each of them, and they are labelled as
-- such below rather than presented as more than they are.
--
-- RULE 1 — NO CONCESSIVE CONNECTIVE INSIDE A VERDICT. TRIPWIRE, AND IT WAS ROUTED AROUND ONCE.
--   Every self-contradiction found up to round 4 lived in one: a clause that takes back what the
--   sentence just said. Two independent sentences that each stand alone cannot do that. Split them.
--   THE FIFTH DID NOT LIVE IN ONE. It used "so" — a consequence connective, which no ban on
--   concessives reaches, and which cannot be banned because the prose is built out of consequence.
--   The word list is KEPT, because it costs nothing and it does catch the cheap version. It is NOT
--   the protection. Rule 5 is, and Rule 5 does not read words at all.
--   ASSERT: no verdict matches ' but | however| though | still matters| even so| that said'.
--
-- RULE 2 — A VERDICT MAY NOT CONVICT WHERE NO WINDOW CARRIES A FINDING. CONSTRAINT, RE-KEYED.
--   It used to key on sanction_adherence_judged, a PER-FAMILY flag, which was the wrong grain under
--   Ori's per-window ruling: it withheld the verdict on a short window that WAS wholly inside the
--   sanction because the long one was not, going quiet exactly where Ori wanted a finding. It now
--   keys on sanction_breach_finding, the per-window answer, three-valued, published as a column.
--   The flag is PUBLISHED, and on a TOTAL row it is the fail-closed ALL over the priced families, so
--   a book cannot convict on the strength of one judged family. A withheld flag never renders as a
--   pass: on Harvest rows, where the concept does not apply, it is NULL rather than TRUE.
--   THE ASSERTION KEYS ON A COUNT, NOT ON THE BOOLEAN, AND IT HOLDS AT BOTH GRAINS. A book total may
--   truthfully say that SOME of its families forfeit protection while the book itself carries no
--   finding, so testing the total against its own all-or-nothing boolean would forbid a true
--   sentence. families_with_a_sanction_finding is 1 or 0 on a family row and the count of convicted
--   families on a total, and the conviction word is licensed by exactly that being above zero.
--   "No longer qualifies" is deliberately NOT in the pattern: the end-date and loss-ceiling branches
--   say it about the calendar and the ceiling, which convict nobody of breaking an agreement.
--   ASSERT: COUNTIF(REGEXP_CONTAINS(verdict, r'forfeit')
--                   AND COALESCE(families_with_a_sanction_finding, 0) = 0) = 0.
--
-- RULE 3 — A WORD CAP PER VERDICT, ASSERTED OVER THE LONGEST REACHABLE VERDICT AND NOT OVER TODAY.
--   DECLARED CONSTANT: 190 words, and it is the LONGEST REACHABLE VERDICT itself, enumerated below.
--   It is a reading-time budget, not a measurement of anything: at an ordinary adult silent reading
--   speed of 240 words a minute — the second declared constant of the rule — 190 words is 48 seconds.
--   THAT IS THE WORST CASE AND IT IS NOT WHAT AN ORDINARY MORNING COSTS; the rows that actually fire are far under it, and verdict_words on the row is how you see
--   which. A word is a whitespace-separated token containing at least one letter or digit, so a bare
--   dash is not a word. The count is published per row as verdict_words, so the rule is checkable
--   without re-deriving the tokeniser.
--   THE OLD CAP OF 100 WAS BROKEN BY THE CALENDAR AND BY THE DATA, AND THE HEADROOM HID IT. It was
--   asserted over the rows that happened to fire, which left 7 words of slack against three optional
--   clauses that each cost more than that when they fire — one of them on a dated event. A cap that
--   only holds until a clause fires is not a cap.
--   WORSE: TWO OF THE LISTS IN THE PROSE WERE UNBOUNDED IN THE DATA. Family-name lists and sanction
--   end-date lists grow one term per family, so NO constant could ever have bounded the verdict.
--   That is fixed at the source: k.list_terms_max (a DECLARED CONSTANT, 3) is the most terms any
--   verdict may spell out, past which the sentence gives a count and the whole list is read off the
--   column beside it (sanction_end_dates, families_inside_break_even_band,
--   families_with_nothing_measured, families_with_no_approved_rate). Only with those bounds is a
--   longest reachable verdict a finite thing to measure.
--   THE ENUMERATION THAT SETS THE CAP — REDO IT WHEN YOU ADD OR WIDEN A CLAUSE. Each slot below is a
--   CASE or an optional IF in one verdict; the figure is the word count of its longest alternative,
--   over combinations that are JOINTLY REACHABLE ONLY (the arm clause is forced by the branch chosen
--   below it; a finding and a comparison cannot be the same arm's verdict; a list is capped at
--   k.list_terms_max terms). The counts use the same tokeniser as verdict_words.
--     INVEST FAMILY, comparison path — the longest of the family paths, because the uncovered long
--       window and the covered short window BOTH get a sentence:
--         rate 24 + arm 14 + comparison 35 + coach 39 + trajectory 15 + proof 18
--         + unmeasured-money 23 + stale 15                                            = 183
--     INVEST FAMILY, finding path:  24 + 12 + 30 + 37 + 15 + 18 + 23 + 15             = 174
--     INVEST TOTAL, finding path — THE LONGEST VERDICT THIS VIEW CAN PRODUCE:
--         opening with three end dates 44 + no-end-date 14 + unpriced 18 + arms 17
--         + finding 28 + coach 39 + unmeasured 15 + stale 15                          = 190
--     INVEST TOTAL, comparison path 186.  INVEST TOTAL, mixed path 183.
--     HARVEST FAMILY 86.  HARVEST TOTAL 102.
--   THE CAP IS THE WORST CASE EXACTLY, WITH NO SLACK, ON PURPOSE. Slack is what let the last cap rot:
--   100 words of budget against a 93-word maximum looked healthy right up to the day a clause fired.
--   At zero slack the next clause added to any verdict fails the assertion immediately and the agent
--   who added it has to redo the arithmetic above and move the constant deliberately. That is the
--   instrument. The assertion is only the guard.
--   ASSERT: MAX(verdict_words) <= 190.
--
-- RULE 4 — NO VERDICT MAY WITHHOLD AND THEN ASSERT ON THE SAME SUBJECT. TRIPWIRE PLUS CONSTRAINT.
--   A row that publishes no trend direction (organic_units_trend IS NULL) may contain no word
--   implying one. The old text said "N organic units in it — which is not enough to call a direction
--   yet" and two sentences later referred to "the improvement": it refused to say whether there was
--   one, then referred to the improvement. The age clause that carried the second half is deleted
--   outright — launch_age_months is a column — and the withholding branch prints a number and stops.
--   THE WORD LIST IS A TRIPWIRE AND CANNOT BE ANYTHING ELSE: a rewrite that says "the second month is
--   bigger than the first" asserts a direction in words the list does not hold, and no closed list of
--   stems can be complete over English. Two things are bolted on that do not read words:
--     (i) THE COLUMN AND THE PROSE MUST AGREE. Where a direction IS published, the verdict must
--         contain that exact word, so the sentence cannot print one trend and the grid another.
--     (ii) THE EVIDENCE PATTERN, NOT ONLY THE WORD. The series construction ", then " is what turns
--         two figures into a claim about direction. A row publishing no direction may not use it.
--   ASSERT: COUNTIF(organic_units_trend IS NULL
--                   AND REGEXP_CONTAINS(LOWER(verdict),
--                       r'\b(climb|fall|ris|improv|grow|declin|trend|trajector|momentum|steady|steadily|upward|downward)\w*\b')) = 0
--       AND COUNTIF(organic_units_trend IS NULL AND STRPOS(verdict, ', then ') > 0) = 0
--       AND COUNTIF(organic_units_trend IS NOT NULL
--                   AND STRPOS(verdict, organic_units_trend) = 0) = 0.
--
-- RULE 5 — NO VERDICT MAY RETRACT A FINDING AND THEN GIVE AN ORDER ABOUT IT. CONSTRAINT. NEW.
--   THE FIFTH SELF-CONTRADICTION WAS A SHAPE, NOT A WORD. All three Invest verdicts said the family
--   was over its approved rate, then said the excess is a comparison and not a finding, then said
--   "Pull those budgets yourself." Retraction, then order, about the same subject, in one paragraph.
--   Rule 1 could not reach it and no word list can: the offending sentence contains no marked word at
--   all, only an imperative verb.
--   SO THE MOOD IS A FUNCTION OF THE DATA. An ORDER may appear only on a row where
--   sanction_breach_finding is TRUE — at least one window lying wholly inside the sanction and over
--   its rate. Everywhere else the coach's held decisions are still named, the dollars are still
--   priced, and Ori may still act: in the OPTION mood, which states the choice as his rather than as
--   an instruction resting on a finding that was withdrawn a sentence earlier.
--   BOTH THE SENTENCE AND THE COLUMN COME FROM ONE EXPRESSION (`voiced`), and the row publishes the
--   sentence its mood FORBIDS (verdict_forbidden_sentence) so the acceptance query can test the
--   coupling with no string literal of its own.
--   WHAT IT DOES NOT CATCH, SAID PLAINLY: a rewrite that invents a NEW imperative instead of editing
--   k.order_sentence escapes the string half. It cannot escape verdict_action_mood, which is data.
--   ASSERT: COUNTIF(verdict_forbidden_sentence IS NOT NULL
--                   AND STRPOS(verdict, verdict_forbidden_sentence) > 0) = 0
--       AND COUNTIF(verdict_action_mood = 'ORDER'
--                   AND NOT COALESCE(sanction_finding_published, FALSE)) = 0.
--
-- RULE 6 — A FINDING MAY NOT EXIST ON A WINDOW THE SANCTION DOES NOT WHOLLY COVER. CONSTRAINT. NEW.
--   Ori's ruling of 2026-08-20 in its structural form, testable without reading a single word of
--   prose. A per-arm finding implies its arm is covered; the row's finding implies at least one arm's
--   finding; a book's finding implies every priced family's finding.
--   ASSERT: COUNTIF(sanction_finding_in_rate_window IS NOT NULL
--                   AND NOT COALESCE(sanction_covers_rate_window, FALSE)) = 0
--       AND COUNTIF(sanction_finding_in_short_window IS NOT NULL
--                   AND NOT COALESCE(sanction_covers_short_window, FALSE)) = 0
--       AND COUNTIF(row_kind = 'FAMILY' AND COALESCE(sanction_breach_finding, FALSE)
--                   AND NOT (COALESCE(sanction_finding_in_rate_window,  FALSE)
--                         OR COALESCE(sanction_finding_in_short_window, FALSE))) = 0.
--
-- ---------------------------------------------------------------------------------------------
-- STANDING RULE 0 — DESCRIBE THE MECHANISM, PUBLISH THE QUERY, NEVER PIN A MEASUREMENT.
-- (Ori, 2026-08-20.) A DECLARED CONSTANT — a sanctioned $/day, a stop date, the 0.05 breakeven band,
-- the 1.30 halo gate, a 28-day window, the 100-word cap — is true because a person decided it. It may
-- be written down and it may gate an assertion. A MEASUREMENT — a rate, a ratio, a ROAS, a halo, a
-- net profit, a count, a percentage, a BYTE COUNT — is true only because something was computed from
-- data on a day. It does not go in prose here and it may never gate anything.
--
-- THIS FILE WAS THE LARGEST PIN CONCENTRATION IN THE DESIGN. It carried a round-by-round narrative
-- whose every paragraph quoted the numbers it was arguing about; several were false by the time they
-- were read, including a byte count used to justify a source choice and a held-cut figure that
-- contradicted the verdict on the same day. All of it is deleted. The narrative is not lost: it is in
-- git (`git log -p --follow scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql`), where a dated commit is the
-- right home for a dated number. What stays here is the MECHANISM and the QUERY that measures it.
--
-- MEASURE, DO NOT QUOTE — the three things this file used to pin, and how to get them today:
--   * The view's cost and whether it still plans:
--       bq query --dry_run --use_legacy_sql=false "SELECT * FROM \`onyga-482313.OI.V_TWO_BOOK_BRIEF\`"
--   * Whether a source is light enough to join here, before you join it:
--       bq query --dry_run --use_legacy_sql=false "SELECT * FROM \`onyga-482313.OI.<candidate>\`"
--   * How far ad attribution moves between the advertised and the purchased ASIN on this window
--     (the reason the no-attribution share is NOT called organic):
--       WITH w AS (SELECT MIN(period_start) AS s, MAX(period_end) AS e
--                  FROM \`onyga-482313.OI.V_FAMILY_PNL\` WHERE period_label='M3')
--       SELECT MIN(pp.DATE) AS window_start, MAX(pp.DATE) AS window_end,
--              SUM(pp.PURCHASED_ORDERS) AS ad_orders,
--              ROUND(100*SAFE_DIVIDE(SUM(IF(pp.PURCHASED_ASIN<>pp.advertised_asin,pp.PURCHASED_ORDERS,0)),
--                                    SUM(pp.PURCHASED_ORDERS)),1) AS pct_orders_different_asin,
--              ROUND(100*SAFE_DIVIDE(SUM(IF(fp.family IS DISTINCT FROM fa.family,pp.PURCHASED_ORDERS,0)),
--                                    SUM(pp.PURCHASED_ORDERS)),1) AS pct_orders_different_family
--       FROM \`onyga-482313.OI.STG_AmazonAds_purchased_product\` pp
--       CROSS JOIN w
--       LEFT JOIN \`onyga-482313.OI.V_PRODUCT_FAMILY_MAP\` fp ON fp.asin = pp.PURCHASED_ASIN
--       LEFT JOIN \`onyga-482313.OI.V_PRODUCT_FAMILY_MAP\` fa ON fa.asin = pp.advertised_asin
--       WHERE pp.DATE BETWEEN w.s AND w.e;
--     Written as a CTE + CROSS JOIN because the scalar-subquery form is rejected outright
--     ("Correlated subqueries that reference other tables are not supported").
--
-- ---------------------------------------------------------------------------------------------
-- MECHANISMS THAT ARE EASY TO BREAK, AND WHY THEY ARE THE WAY THEY ARE.
--
-- MEASURED MEANS THE MONEY IS THERE, BOTH HALVES. A family can hold a P&L row with ad spend counted
-- and sales not — the exact shape of a launch before its first mapped sale. Publishing that half
-- would put a 4-family spend beside a 3-family profit on one TOTAL row and call it complete. So when
-- either money column is missing, ALL of them are NULL (never zero — zero claims "measured, and it
-- was nothing"), the row is excluded from both book sums, and the verdict says which half is missing.
-- SUM ignores NULLs, so an unmeasured family can neither move a total nor open a reconciliation gap.
-- The old money_measured boolean is CUT: it is exactly (net_profit IS NOT NULL AND ad_spend IS NOT
-- NULL) off two published columns, so it is recomputable — the same criterion that cut a dozen
-- columns before it — and a NULL money column cannot be misread as a pass the way a flag can.
--
-- THE SPINE IS THE UNION OF BOTH UNIVERSES. V_FAMILY_PNL's families are ASIN-keyed through
-- DIM_PRODUCT and windowed; V_BOOK_ASSIGNMENT's are campaign-keyed and unwindowed. A declared INVEST
-- family whose ASINs carry no parent_name has no P&L row at all, and an inner spine would join away
-- the one family this design exists to keep visible while it spends every day. FULL OUTER JOIN.
-- (One entrance to that failure is still open ABOVE this view: a family sanctioned in
-- DE_LAUNCH_INVESTMENT whose campaigns are unmapped resolves to 'Unknown' inside
-- V_CAMPAIGN_FAMILY_MAP and never reaches V_BOOK_ASSIGNMENT. This spine cannot reach it.)
--
-- QUALIFYING FOR PROTECTION AND BEING PROTECTED ARE DIFFERENT FACTS, AND THIS OBJECT MAY NEVER AGAIN
-- PUBLISH ONE AS THE OTHER. protection_qualified is what the sanction rules say (V_INVEST_STATUS,
-- fail-closed). protection_enforced is what the machine is doing. They are allowed to disagree, and
-- when they do the held decisions and the dollars behind them carry the size of the gap. A state that
-- cannot be observed reads NULL, never FALSE: "we could not check" is not "the coach has stopped".
--
-- TWO ENFORCEMENT SOURCES, NEITHER REDUNDANT. V_LAUNCH_EXEMPTION is the authority the coach reads and
-- is campaign-complete for protected campaigns. T_COACH_CAMPAIGN_BUDGET is where the CONSEQUENCE
-- lives — the decisions the exemption suppressed and the budget they cover. It holds only
-- campaigns that reached a budget decision, so it can be silent about a campaign the exemption view
-- can see. Reading both keeps "no evidence anywhere" distinguishable from "evidence the coach let go".
-- WHY THE TABLE AND NOT THE VIEW: V_COACH_CAMPAIGN_BUDGET is a planning-ceiling view and this view is
-- already at the ceiling; its daily materialisation is built by SP_REFRESH_CUBE_TABLES in the same
-- pass and carries every column needed. House pattern: never inline a ceiling view, read the T_ built
-- earlier in the pass. Dry-run both before changing this (query above).
--
-- A STOP AND A TRIM ARE NOT WORTH THE SAME MONEY. A held CAMPAIGN_STOP is worth its whole budget; a
-- held GUARDIAN_BUDGET_DECREASE is worth only current_budget minus the budget the coach wanted.
-- Summing current_budget over both kinds overstates the book, and that number is the one Ori acts on.
-- Priced per decision kind, and the two kinds are counted, priced and spoken separately, because
-- "stop these campaigns" and "trim these budgets" are different jobs. An unsized trim contributes
-- ZERO dollars and is counted instead, so the figure can only run low, and the row says when it does.
--
-- THE TRAJECTORY IS DECIDED ON WHOLE MONTHS ONLY, AND THE TEST IS SYMMETRIC IN TIME. A month that is
-- partial FOR THE FAMILY is an incomplete window, and Ori's rule about incomplete windows is
-- withhold, never substitute — so the series is cut to months the family sold through IN FULL
-- (m0_whole / m1_whole / m2_whole). Exclusion needs no window of its own; a per-day rate would need
-- each month's start and end, which upstream does not publish beside the values, and deriving them
-- from CURRENT_DATE would be a second definition of a window this object must READ.
-- THE WORD IS DECIDED ON STEP SIGNS, NOT ON INEQUALITY CHAINS. The old chains were asymmetric:
-- climbing allowed a flat step on one side of the series and falling required a strict step on the
-- same side, so a flat-then-up series and its own time-reversal got opposite treatment rather than
-- mirror treatment. Now: count the strictly-up steps and the strictly-down steps. Up only is
-- climbing, down only is falling, none of either is flat, both is mixed. Reversing the series swaps
-- the two counts and therefore swaps climbing and falling, which is what symmetric means. The word is
-- PUBLISHED as organic_units_trend so the column and the sentence cannot disagree, and NULL there is
-- what Rule 4 keys on.
--
-- WINDOWS ARE NAMED IN THE COLUMN NAMES, NOT ONLY IN THE PROSE. Two spend columns used to sit on one
-- row over different windows with neither name carrying its window, so a reader dividing one by the
-- other got a third number that meant nothing. They are ad_spend_in_money_window and
-- spend_per_day_in_rate_window now, and the second window's rate rides beside it as
-- spend_per_day_last_7_days with spend_breach_window naming the arm that actually fired — because
-- the breach test is dual-window and the long-window ratio alone will read below the rate on the day
-- the short arm fires by itself.
--
-- A BOOK HAS NO SINGLE END DATE, SO THE COLUMN NAMES NONE — AND A SECOND COLUMN NAMES THEM ALL.
-- sanction_end_date used to hold MAX over the book, which let the book inherit the more generous of
-- two terms. On a TOTAL row it is NULL.
-- WHERE EVERY DATE ACTUALLY LIVES, AND WHAT THE VERDICT PROMISES. The header used to claim "the
-- verdict names every end date the book actually holds" while the code printed the first and the
-- last joined by "and" — a complete-looking list with the middle terms deleted, true at exactly two
-- dates and false at three. The CLAIM now matches the CODE, in both directions:
--   * sanction_end_dates, on the INVEST TOTAL row, holds EVERY distinct end date the priced families
--     hold, in date order. No bound, no elision. That is the guarantee.
--   * The VERDICT spells them all out while there are at most k.list_terms_max of them and otherwise
--     says how many there are and names the column. It never prints a partial list as a whole one.
-- The same split applies to every other data-shaped list on a total row — see Rule 3.
--
-- ---------------------------------------------------------------------------------------------
-- ACCEPTANCE — ONE PASS OVER THE DEPLOYED VIEW. Run it after every change to this file.
-- Write it as a SINGLE SELECT. This view is at BigQuery's planning ceiling and it is inlined at every
-- reference, so a check-per-subquery form degrades hard and then fails to plan altogether.
--
--   SELECT
--     COUNT(*)                                                              AS n_rows,
--     COUNTIF(row_kind = 'TOTAL')                                           AS total_rows,
--     COUNTIF(book NOT IN ('HARVEST','INVEST'))                             AS bad_books,
--     COUNTIF(row_kind NOT IN ('FAMILY','TOTAL'))                           AS bad_row_kinds,
--     COUNTIF(verdict IS NULL OR TRIM(verdict) = '')                        AS blank_verdicts,
--     COUNTIF(REGEXP_CONTAINS(LOWER(verdict),
--             r' but | however| though | still matters| even so| that said')) AS rule1_concessives,
--     COUNTIF(REGEXP_CONTAINS(verdict, r'forfeit')
--             AND COALESCE(families_with_a_sanction_finding, 0) = 0)        AS rule2_convictions,
--     MAX(verdict_words)                                                    AS rule3_max_words,
--     COUNTIF(organic_units_trend IS NULL AND REGEXP_CONTAINS(LOWER(verdict),
--             r'\b(climb|fall|ris|improv|grow|declin|trend|trajector|momentum|steady|steadily|upward|downward)\w*\b'))
--                                                                           AS rule4_direction_without_trend,
--     COUNTIF(organic_units_trend IS NULL AND STRPOS(verdict, ', then ') > 0)
--                                                                           AS rule4_series_without_trend,
--     COUNTIF(organic_units_trend IS NOT NULL AND STRPOS(verdict, organic_units_trend) = 0)
--                                                                           AS rule4_word_column_disagree,
--     COUNTIF(verdict_forbidden_sentence IS NOT NULL
--             AND STRPOS(verdict, verdict_forbidden_sentence) > 0)          AS rule5_wrong_mood,
--     COUNTIF(verdict_action_mood = 'ORDER'
--             AND NOT COALESCE(sanction_finding_published, FALSE))          AS rule5_order_without_finding,
--     COUNTIF(sanction_finding_in_rate_window IS NOT NULL
--             AND NOT COALESCE(sanction_covers_rate_window, FALSE))         AS rule6_finding_off_window_28,
--     COUNTIF(sanction_finding_in_short_window IS NOT NULL
--             AND NOT COALESCE(sanction_covers_short_window, FALSE))        AS rule6_finding_off_window_7,
--     COUNTIF(row_kind = 'FAMILY' AND COALESCE(sanction_breach_finding, FALSE)
--             AND NOT (COALESCE(sanction_finding_in_rate_window,  FALSE)
--                   OR COALESCE(sanction_finding_in_short_window, FALSE)))  AS rule6_finding_from_nowhere,
--     COUNTIF(verdict_words <> ARRAY_LENGTH(REGEXP_EXTRACT_ALL(verdict, r'[^\s]*[A-Za-z0-9][^\s]*')))
--                                                                           AS word_count_disagrees,
--     ROUND(SUM(IF(book='HARVEST' AND row_kind='TOTAL',  net_profit, 0))
--         - SUM(IF(book='HARVEST' AND row_kind='FAMILY', net_profit, 0)), 2) AS gap_harvest_net_profit,
--     ROUND(SUM(IF(book='HARVEST' AND row_kind='TOTAL',  ad_spend_in_money_window, 0))
--         - SUM(IF(book='HARVEST' AND row_kind='FAMILY', ad_spend_in_money_window, 0)), 2) AS gap_harvest_ad_spend,
--     ROUND(SUM(IF(book='INVEST'  AND row_kind='TOTAL',  net_profit, 0))
--         - SUM(IF(book='INVEST'  AND row_kind='FAMILY', net_profit, 0)), 2) AS gap_invest_net_profit,
--     ROUND(SUM(IF(book='INVEST'  AND row_kind='TOTAL',  ad_spend_in_money_window, 0))
--         - SUM(IF(book='INVEST'  AND row_kind='FAMILY', ad_spend_in_money_window, 0)), 2) AS gap_invest_ad_spend
--   FROM `onyga-482313.OI.V_TWO_BOOK_BRIEF`;
--
-- PASS = total_rows 2, bad_books 0, bad_row_kinds 0, blank_verdicts 0, rule1_concessives 0,
--        rule2_convictions 0, rule3_max_words <= 190, rule4_* 0, rule5_* 0, rule6_* 0,
--        word_count_disagrees 0, all four gaps 0.
-- DETERMINISM: two consecutive full pulls must be byte-identical.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT THIS VIEW GUARANTEES, AND WHAT IT ONLY DISCLOSES.
--   GUARANTEED — two book totals and no third, no grand total, by construction (a two-row spine and
--     no aggregation across `book` anywhere above it).
--   GUARANTEED — a family with either money column missing contributes to NEITHER book sum and is
--     named in words, so no total can be complete-looking and short.
--   GUARANTEED — every sanction figure on a TOTAL row is taken over the PRICED families, and every
--     count the prose compares is taken over that same set.
--   GUARANTEED — a book publishes a rate window, a rate and a window phrase only when every priced
--     family is on one identical window; otherwise all three are NULL and the verdict says so.
--   GUARANTEED — sanction_end_dates on the INVEST TOTAL holds every distinct end date the book holds.
--   GUARANTEED — a conviction ("forfeits") appears only where at least one window lies WHOLLY inside
--     its sanction and is over its rate, and an ORDER appears only on a row carrying such a finding.
--   DISCLOSED, NOT CLOSED — the LEADING edge of the rate window. Upstream cannot tell a family that
--     began advertising inside the window from one whose older rows were lost, so a contiguous loss
--     of older rows still zero-fills the front of the window and lowers the rate. It rides on the row
--     as family_leading_silent_window_days and is stated in rate_window_basis. Nothing here claims it
--     is closed.
--   NOT ASSERTABLE — that no future rewrite invents a new imperative or a new way to assert a
--     direction. Rules 1 and 4 are word tripwires; Rules 2, 5 and 6 key on published columns and are
--     the part that cannot be talked around.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_TWO_BOOK_BRIEF` AS
WITH k AS (
  SELECT
    -- DECLARED CONSTANT. A result smaller than this share of the family's OWN ad spend is noise, not
    -- a job. It is what stops a trivial shortfall reading like a real one just because both ratios
    -- sit under 1.0.
    -- THE BAND IS SYMMETRIC IN SIGN, AND IT WAS NOT. It used to gate only the LOSS side: a family
    -- $77 short on $3,595 of ad spend was called noise, and the same family $77 AHEAD on the same
    -- spend took the "made money" branch and was told to keep running. Same distance from break-even,
    -- opposite treatment decided by sign alone — which is the one thing a band is supposed to stop.
    -- Three states now, decided on |net_profit| against band * ad_spend: real profit, inside the
    -- band, real loss. See real_profit / inside_band / real_loss in `base`.
    0.05 AS breakeven_band,
    -- DECLARED CONSTANT. Above this measured halo the ads-only number is misleading enough that the
    -- verdict says so out loud. The share of gross profit carrying no ad attribution is 1 - 1/halo,
    -- so at this gate that share is well short of a majority: the clause prints the MEASURED share
    -- and never calls it "most". Raising the gate to buy the word would silence the one warning it
    -- exists to give. AND THE SHARE IS NOT "ORGANIC": it is gross profit Amazon's ad attribution did
    -- not claim, which is organic demand PLUS ad-driven sales the attribution missed, and nothing
    -- here measures the split.
    1.30 AS wide_halo,
    -- ─── RULE 5: THE TWO MOODS, EACH WRITTEN ONCE, IN ONE PLACE ───
    -- The fifth self-contradiction was not a word, it was a SHAPE: the verdict said the family was
    -- over its approved rate, then said the excess is a comparison and not a finding, then ORDERED
    -- the budgets pulled. It withdrew the conviction and then acted on it. A ban on "but" did not
    -- reach it; the prose routed around the list with "so".
    -- The fix is that the MOOD of the closing sentence is a FUNCTION of whether a finding was
    -- published, and both the sentence and the column naming its mood come from the same expression
    -- (`voiced`). An ORDER may be given only where at least one window lies wholly inside the
    -- sanction and is over it. Otherwise the coach's held budgets are still reported and Ori may
    -- still act — as an option that is his to take, not as an instruction justified by a finding that
    -- was withdrawn one sentence earlier.
    -- THESE TWO STRINGS ARE THE ONLY IMPERATIVE ABOUT BUDGETS IN THE FILE, and the acceptance query
    -- tests the coupling against them, so a rewrite that changes the wording has to change it here.
    'Pull those budgets yourself.'                  AS order_sentence,
    'Those budgets are yours to pull.'              AS option_sentence,
    -- DECLARED CONSTANT. The most terms a verdict may SPELL OUT of a data-shaped list — family names,
    -- sanction end dates. Past it the sentence gives the count and the full list is read off the
    -- column beside it. This is what makes Rule 3 provable at all: without a bound here the verdict
    -- grows one term per family and no constant cap can hold, which is the same defect as a cap a
    -- calendar breaks, wearing a different coat.
    3                                               AS list_terms_max
),
pnl AS (
  -- The window is carried THROUGH TO THE OUTPUT. This view publishes two windows side by side, so a
  -- reader scanning the grid must be able to see which is which without reading prose.
  SELECT family, period_start, period_end,
         net_profit, total_net_roas, ads_net_roas, halo_factor, organic_pct, ad_spend
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'          -- settled 90 complete days, same window the bars are set from
),
-- The book spine. Both books are published EVERY day even when one is empty, so the shape of the
-- brief never changes and total_rows is structurally 2 rather than data-dependent. An empty Invest
-- book is a real and useful sentence ("nothing is on approved launch investment").
books AS (SELECT 'HARVEST' AS book UNION ALL SELECT 'INVEST' AS book),
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE SPEND THAT REACHES NEITHER BOOK. Advertising on the same window whose advertised key carries
-- no family name belongs to neither book, and this object used to present its spend total as though
-- it were the account's advertising. The founding complaint behind this design is a number that lied
-- by omission; a silent share of the spend is the same defect wearing a smaller coat.
-- IT IS NOT A THIRD ROW. A third row_kind would break the structural total_rows = 2 guarantee. It
-- rides as two COLUMNS on the HARVEST TOTAL row plus one clause in that row's verdict, ON THAT ROW
-- ONLY: the money belongs to neither book, so it cannot be apportioned to one, and publishing it on
-- both totals invites a reader scanning columns to add it to itself.
-- WHY THIS SOURCE: the window comes from `pnl` itself, so the coverage figure and the P&L can never
-- drift onto different windows. The spend comes off FACT_AMAZON_ADS joined to the same
-- ASIN-to-family map V_UNIFIED_DAILY uses, which is the lightest source that reproduces the
-- attributed side exactly. Verify that reconciliation, do not assume it:
--   SELECT SUM(ad_cost) FROM `onyga-482313.OI.V_UNIFIED_DAILY` ... over the same window and families.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
win AS (SELECT MIN(period_start) AS s, MAX(period_end) AS e FROM pnl),
cov AS (
  SELECT
    ROUND(SUM(IF(fm.asin IS NULL, a.Ads_cost, 0)), 0)                                AS unattributed_spend,
    ROUND(100 * SAFE_DIVIDE(SUM(IF(fm.asin IS NULL, 0, a.Ads_cost)),
                            NULLIF(SUM(a.Ads_cost), 0)), 2)                          AS spend_coverage_pct,
    -- HOW MANY ADVERTISED PRODUCTS THAT MONEY COVERS, AND WHICH ONE IF IT IS JUST ONE. The clause
    -- used to say "products that are not carrying a family name" — plural, which reads as a
    -- systemic mapping failure and points at a fix that cannot work when the rows name no product at
    -- all. The sentence branches on the MEASURED count, so it stays true when the shape changes.
    -- Both expressions read columns this scan already reads. Counting DISTINCT campaign_id here
    -- would cost real bytes and this view has no room for it — dry-run before adding.
    COUNT(DISTINCT IF(fm.asin IS NULL,
      COALESCE(a.most_advertised_asin_impressions, a.advertised_asins, a.ASIN_BY_CAMPAIGN_NAME),
      NULL))                                                                         AS unattributed_products,
    MIN(IF(fm.asin IS NULL,
      COALESCE(a.most_advertised_asin_impressions, a.advertised_asins, a.ASIN_BY_CAMPAIGN_NAME),
      NULL))                                                                         AS unattributed_product_key,
    -- The window itself, carried out of the aggregate so the sentence names the span `pnl` measured
    -- rather than a literal that goes stale if the P&L window ever stops being 90 days.
    MAX(w.s)                                                                         AS win_start,
    MAX(w.e)                                                                         AS win_end
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN win w
  LEFT JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    ON fm.asin = COALESCE(a.most_advertised_asin_impressions, a.advertised_asins, a.ASIN_BY_CAMPAIGN_NAME)
  WHERE a.date BETWEEN w.s AND w.e
),
enf AS (
  -- The exemption the coach reads. A family with no row here has no protected campaign today: the
  -- upstream view already filters to campaigns still inside their exemption window.
  SELECT family, COUNTIF(exempt_active) AS campaigns_protected
  FROM `onyga-482313.OI.V_LAUNCH_EXEMPTION`
  GROUP BY family
),
held AS (
  -- What that protection is costing in withheld decisions, priced per decision kind. See the header.
  -- NO TARGET ON RECORD MEANS NO DOLLARS, NEVER THE WHOLE BUDGET: COALESCE(budget_suppressed_to, 0)
  -- would price an unsized trim at its full budget. An unsized trim contributes ZERO and is counted.
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
    -- third book: a NULL book would open a third TOTAL group and drop the dollars out of the
    -- reconciliation.
    COALESCE(bk.book, 'HARVEST')                                        AS book,
    COALESCE(p.family, bk.family)                                       AS family,
    -- BOTH money columns, or the family is not measured. Not published — it is exactly
    -- (net_profit IS NOT NULL AND ad_spend IS NOT NULL) on the output row.
    (p.net_profit IS NOT NULL AND p.ad_spend IS NOT NULL)               AS money_measured,
    -- Read off the UPSTREAM columns, not the published ones: an unmeasured row has both money
    -- columns blanked below, so asking the published columns which half is missing always answers
    -- "both" — which is how a verdict once asserted "no ad spend" over a family that had plenty.
    (p.net_profit IS NOT NULL)                                          AS pnl_has_profit,
    (p.ad_spend   IS NOT NULL)                                          AS pnl_has_spend,
    -- The window behind every money column on this row, in words. NULL on a family with nothing
    -- measured, which is itself the correct statement: no window was measured for it.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       CONCAT('the settled ', CAST(DATE_DIFF(p.period_end, p.period_start, DAY) + 1 AS STRING),
              ' days to ', FORMAT_DATE('%-d %B %Y', p.period_end)))     AS money_window,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.period_start) AS period_start,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.period_end)   AS period_end,
    IF(p.ad_spend   IS NULL, NULL, ROUND(p.net_profit, 0))              AS net_profit,
    IF(p.net_profit IS NULL, NULL, ROUND(p.ad_spend, 0))                AS ad_spend,
    -- ─── NEITHER THE COLUMN NOR THE SENTENCE MAY ROUND ITSELF ACROSS $1.00 ───
    -- A return a hair under 1.0 printed at two decimals reads as breakeven beside a loss. Where two
    -- decimals would land the value on 1.00 from the wrong side, the 4-decimal upstream figure is
    -- published instead — more precision, not a nudged number — and the text form says which side it
    -- is on. Both tests are on the UNROUNDED upstream value, so column and sentence cannot disagree.
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
    -- ─── THE SHARE OF GROSS PROFIT CARRYING NO AD ATTRIBUTION ───
    -- 1 - 1/halo, where halo = total gross profit / AD-ATTRIBUTED gross profit. That bucket is
    -- organic demand PLUS every ad-driven sale the attribution missed, and the missed part is not a
    -- rounding error: the ads fact books GROSS_PROFIT against the ADVERTISED asin while sales and
    -- COGS are keyed to the PURCHASED asin, and those two disagree on most ad orders (query in the
    -- header — run it, do not quote a number for it). Computed off the SAME halo the row publishes.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL OR COALESCE(p.halo_factor, 0) <= 0, NULL,
       CAST(ROUND(100 * (1 - SAFE_DIVIDE(1, ROUND(p.halo_factor, 2)))) AS INT64))    AS share_of_return_with_no_ad_attribution_pct,
    -- A DIFFERENT DENOMINATOR AND NUMERATOR from the column above: organic UNITS over total UNITS.
    -- Both names now say what they divide.
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL, p.organic_pct)              AS organic_share_of_units_pct,
    i.phase, i.launch_age_months, i.stop_date, i.sanctioned_on,
    -- ─── WHICH OF THE THREE MONTHS THE FAMILY LIVED THROUGH FROM END TO END ───
    -- launch_age_months is DATE_DIFF(today, first_sale_date, MONTH) computed in V_BOOK_ASSIGNMENT,
    -- and BigQuery's MONTH difference counts month boundaries, so it is identically the number of
    -- months back that the first-sale MONTH sits. org_m0 / org_m1 / org_m2 are 1, 2 and 3 months
    -- back. So month k back was lived end to end when the first-sale month is FURTHER back than k —
    -- or sits exactly at k and began on the 1st, the only way a first month is also a whole one.
    -- COALESCE(..., FALSE) fails CLOSED: with no first sale on record nothing establishes that any
    -- month was fully lived, so no trend word is printed. Re-check the identity with:
    --   SELECT family, launch_age_months,
    --          DATE_DIFF(DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'),MONTH),
    --                    DATE_TRUNC(first_sale_date,MONTH),MONTH) AS months_back
    --   FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`;
    COALESCE(i.launch_age_months > 1
             OR (i.launch_age_months = 1
                 AND EXTRACT(DAY FROM bk.first_sale_date) = 1), FALSE)  AS m0_whole,
    COALESCE(i.launch_age_months > 2
             OR (i.launch_age_months = 2
                 AND EXTRACT(DAY FROM bk.first_sale_date) = 1), FALSE)  AS m1_whole,
    COALESCE(i.launch_age_months > 3
             OR (i.launch_age_months = 3
                 AND EXTRACT(DAY FROM bk.first_sale_date) = 1), FALSE)  AS m2_whole,
    -- The date a dropped part month is read from. PUBLISHED, because the verdict no longer has the
    -- words to spare for it: a reader who wants to know why a series starts where it does reads the
    -- first-sale date beside the whole-month columns.
    bk.first_sale_date,
    -- ─── THE SECOND BINDING FIELD OF THE DECLARATION ───
    -- Ori's ruling: a sanction is a rate AND an end date, and both bind. A reader cannot act on a
    -- term they are never told, so the date travels with the dollars everywhere the dollars go.
    IF(i.stop_date IS NULL, ', with no end date on record',
       CONCAT(' through ', FORMAT_DATE('%-d %B %Y', i.stop_date)))       AS sanction_end_text,
    i.daily_investment, i.spend_per_day, i.spend_rate_ratio,
    -- ─── THE BREACH TEST IS DUAL-WINDOW, SO THE ROW CARRIES BOTH ARMS ───
    -- spend_breached is the OR of the two arms. Publishing only the long-window rate beside it means
    -- that on the day the short arm fires alone the grid shows a rate under the sanction next to a
    -- breach. Both rates and the arm that fired are published, and the prose names both windows.
    i.spend_breached, i.spend_breached_28d, i.spend_breached_7d, i.spend_breach_arm,
    i.spend_per_day_7d, i.short_window_days,
    -- ─── WHAT THE UPSTREAM WILL AND WILL NOT ASSERT (Rule 2) ───
    -- FALSE means no complete window lies inside the agreement yet, so a rate above the agreed rate
    -- is a COMPARISON and not a finding that the agreement was broken. The verdict may not convict
    -- on such a row. rate_window_days_before_sanction is how many days of the window predate the
    -- agreement, which is the fact the honest sentence is built from.
    -- Gated on the book, like every other launch concept on this row: on a Harvest family the
    -- question does not arise, and a flag that reads TRUE there would let a Harvest verdict convict
    -- under a rule that was never applied to it.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_adherence_judged, NULL)
                                                                        AS sanction_adherence_judged,
    i.rate_window_days_before_sanction,
    i.short_window_days_before_sanction,
    -- ─── ORI'S PER-WINDOW RULING (2026-08-20), READ, NEVER RE-DERIVED ───
    -- "Finding on the short window, comparison on the long." A window may carry a FINDING — a verdict
    -- that the agreement was broken, which forfeits launch protection — only when it lies WHOLLY
    -- inside the sanction: zero of its days precede sanctioned_on. Otherwise its excess is a
    -- COMPARISON, stated in full and convicting nobody.
    -- THE RULE IS PER WINDOW, NOT PER FAMILY, and this object used to apply the family flag
    -- (sanction_adherence_judged) to both arms at once — stricter than Ori asked for, going quiet on
    -- the short window on the grounds that the long one was not yet judgeable. Every arm now answers
    -- for its own days. Whether a given arm is a finding TODAY is a calendar fact and therefore a
    -- MEASUREMENT: it is not written down anywhere here, it is read off these columns.
    -- Gated on the book like every other launch concept on this row: on a Harvest family the question
    -- does not arise, and a flag reading TRUE there would let a Harvest verdict convict under a rule
    -- that was never applied to it. Three-valued throughout — NULL is "no finding is available",
    -- never "no breach".
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_covers_28d_window, NULL)
                                                                        AS sanction_covers_rate_window,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_covers_7d_window, NULL)
                                                                        AS sanction_covers_short_window,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_finding_28d, NULL)
                                                                        AS sanction_finding_in_rate_window,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_finding_7d, NULL)
                                                                        AS sanction_finding_in_short_window,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_breach_finding, NULL)
                                                                        AS sanction_breach_finding,
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.sanction_breach_finding_arm, NULL)
                                                                        AS sanction_breach_finding_window,
    -- ─── WHY PROTECTION IS BLOCKED, WHEN IT IS NOT THE BREACH AND NOT THE CALENDAR ───
    -- The verdict used to end a family with adherence judged, no breach and protection FALSE on
    -- "the sanction is not fully on record", which names a cause that is not the cause. The real
    -- blockers upstream are a withheld window, a stale or uncertifiable window, and a family that
    -- does not resolve to exactly one book assignment row. All three ride here so the sentence can
    -- name the one that actually fired.
    i.rate_window_data_complete,
    i.short_window_data_complete,
    i.book_assignment_rows,
    -- NOT PUBLISHED, used only by the book total: the dollars behind spend_per_day over the same
    -- window, so the INVEST total can compute a rate over the BOOK rather than summing per-family
    -- rates that have each already been rounded to the cent.
    i.rate_window_spend,
    -- ─── THE RATE WINDOW IS READ, NEVER RE-DERIVED ───
    -- Upstream measures a TRAILING span of complete days ending behind the ads feed and publishes it
    -- as dates, as a count, and in two ready-made English forms. Any string built here from
    -- CURRENT_DATE eventually names a different span from the one the number was measured on.
    i.rate_window_start, i.rate_window_end, i.rate_window_days,
    i.rate_window_basis, i.rate_window_phrase,
    -- A trailing window is always full, so the only thing that can go wrong with it is its age.
    -- TRUE when the ads feed has stopped moving; upstream the same state withdraws protection.
    i.rate_window_is_stale,
    -- THE SANCTIONED RATE, WRITTEN THE WAY IT WAS AGREED. Whole dollars read as whole dollars and
    -- cents survive: rounding here would put a wrong number inside the one instruction on this
    -- object that tells Ori to do something.
    IF(i.daily_investment = TRUNC(i.daily_investment),
       FORMAT("$%'d", CAST(i.daily_investment AS INT64)),
       FORMAT('$%.2f', i.daily_investment))                             AS daily_investment_text,
    i.ceiling_used_pct, i.days_left,
    -- ─── THE LOSS ALLOWANCE HAS ITS OWN WINDOW AND IT IS A THIRD ONE ───
    -- Month-to-date net profit against a monthly ceiling, cut at the ORDERS watermark rather than the
    -- ads one — a different span from both money_window and rate_window. It is read from
    -- V_INVEST_STATUS (mtd_money_start / mtd_money_end), so there is no second definition of it, and
    -- the window is named on the row because an unnamed third window in a grid of two named ones is
    -- how a reader compares two numbers that do not cover the same days.
    i.mtd_money_start, i.mtd_money_end,
    -- Both sides of the fraction ride on the row in dollars. A bare percentage of a monthly allowance
    -- reads as a finished month, and its denominator was nowhere on the row.
    i.monthly_loss_ceiling,
    i.mtd_net_profit,
    IF(i.ceiling_used_pct IS NULL OR i.mtd_money_start IS NULL OR i.mtd_money_end IS NULL, NULL,
       CONCAT(FORMAT_DATE('%-d %B', i.mtd_money_start), ' to ',
              FORMAT_DATE('%-d %B %Y', i.mtd_money_end),
              ', the part of this month that is measured'))            AS loss_allowance_window,
    i.org_m2, i.org_m1, i.org_m0, i.takeover_target_organic_units,
    -- ─── THE BREAK-EVEN BAND, APPLIED TO BOTH SIDES OF ZERO ───
    -- Three states off one comparison, |net_profit| against band * ad_spend. The band used to gate
    -- the loss side only, so the same distance from break-even was "noise" below zero and "made
    -- money, keep it running" above it. A band that only holds in one direction is not a band, it is
    -- a floor with a story attached.
    -- NULL, not FALSE, when the family is unmeasured: "we did not measure it" is not "it is fine".
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       (p.net_profit < 0 AND -p.net_profit > k.breakeven_band * p.ad_spend)) AS real_loss,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       (p.net_profit > 0 AND p.net_profit > k.breakeven_band * p.ad_spend))  AS real_profit,
    IF(p.net_profit IS NULL OR p.ad_spend IS NULL, NULL,
       (ABS(p.net_profit) <= k.breakeven_band * p.ad_spend))                 AS inside_band,
    (COALESCE(p.halo_factor, 0) >= k.wide_halo)                         AS wide_halo,
    -- Rule 5's two moods, carried down from `k` so the prose and the acceptance query read one string.
    k.order_sentence, k.option_sentence,
    -- ─── THE TWO PROTECTION STATES, KEPT APART ───
    -- QUALIFIED: what the sanction rules say (already the fail-closed answer upstream).
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', i.protection_qualified, NULL) AS protection_qualified,
    -- ENFORCED: what the machine is doing. TRUE if either source can see a protected campaign; FALSE
    -- only when a source has campaigns for this family and none is protected; NULL when neither
    -- source has heard of the family. A missing measurement printed as FALSE would put "the coach has
    -- withdrawn it" back on the page.
    IF(COALESCE(bk.book, 'HARVEST') <> 'INVEST'
       OR (e.family IS NULL AND h.family IS NULL), NULL,
       COALESCE(e.campaigns_protected, 0) > 0
       OR COALESCE(h.campaigns_protected, 0) > 0)                       AS protection_enforced,
    -- THE GAP AS A NUMBER, PRICED PER DECISION KIND. NULL — never 0 — where the coach's budget pass
    -- has no row for the family: "it is holding nothing" and "we cannot see what it is holding" are
    -- different sentences. Harvest families carry NULL because launch protection is not a concept in
    -- that book.
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
  -- k LAST, and never before the FULL OUTER JOIN: cross-joined earlier, the outer join would null out
  -- the tunables on exactly the book-only rows the outer join exists to create.
  CROSS JOIN k
),
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE TREND WORD, DECIDED ON STEP SIGNS SO IT IS SYMMETRIC IN TIME.
-- The series runs oldest to newest: org_m2, org_m1, org_m0, restricted to whole-months-lived. A step
-- exists between two adjacent months that are both present. Count the strictly-up steps and the
-- strictly-down steps; up only is climbing, down only is falling, neither is flat, both is mixed.
-- Reversing the series exchanges the two counts and therefore exchanges climbing and falling, which
-- is the property the old inequality chains did not have: they allowed a flat step on one side of the
-- series for climbing and demanded a strict step on that same side for falling, so a flat-then-up
-- series read as a climb while its own mirror read as neither.
-- NULL means no step exists, which is the withholding state Rule 4 keys on.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
stepped AS (
  SELECT
    b.*,
    (b.m0_whole AND b.org_m0 IS NOT NULL)                               AS has_m0,
    (b.m1_whole AND b.org_m1 IS NOT NULL)                               AS has_m1,
    (b.m2_whole AND b.org_m2 IS NOT NULL)                               AS has_m2
  FROM base b
),
trended AS (
  SELECT
    s.*,
    IF(s.has_m0 AND s.has_m1, 1, 0) + IF(s.has_m1 AND s.has_m2, 1, 0)   AS n_steps,
    IF(s.has_m0 AND s.has_m1 AND s.org_m0 > s.org_m1, 1, 0)
      + IF(s.has_m1 AND s.has_m2 AND s.org_m1 > s.org_m2, 1, 0)         AS steps_up,
    IF(s.has_m0 AND s.has_m1 AND s.org_m0 < s.org_m1, 1, 0)
      + IF(s.has_m1 AND s.has_m2 AND s.org_m1 < s.org_m2, 1, 0)         AS steps_down
  FROM stepped s
),
-- DOLLARS, NOT RATIOS, DECIDE THE QUEUE. Ordering is TOTAL (family breaks the tie) so the "fix this
-- first" sentence can never coin-flip between two families losing the same amount.
-- WHY A WINDOW AND NOT A JOIN: as its own CTE joined back on, this cost extra full expansions of
-- `base` (BigQuery inlines a CTE at every reference, and base fans out over V_UNIFIED_DAILY) and it
-- SQUARED any duplicate upstream row into four identical family rows with two wrong money columns
-- while total_rows sat at 2 looking healthy. Computed here it cannot fan out at all.
-- loss_rank IS NOT PUBLISHED: it is 1 on exactly one row, whose verdict already names it as the
-- biggest loss in the book, and NULL everywhere else — no information the row does not already carry.
ranked AS (
  SELECT
    t.*,
    IF(t.book = 'HARVEST' AND COALESCE(t.real_loss, FALSE),
       ROW_NUMBER() OVER (PARTITION BY (t.book = 'HARVEST' AND COALESCE(t.real_loss, FALSE))
                          ORDER BY t.net_profit ASC, t.family ASC), NULL)          AS loss_rank,
    IF(t.book = 'HARVEST' AND COALESCE(t.real_loss, FALSE),
       FIRST_VALUE(t.family) OVER (PARTITION BY (t.book = 'HARVEST' AND COALESCE(t.real_loss, FALSE))
                                   ORDER BY t.net_profit ASC, t.family ASC), NULL) AS worst_family,
    IF(t.book = 'HARVEST' AND COALESCE(t.real_loss, FALSE),
       FIRST_VALUE(t.net_profit) OVER (PARTITION BY (t.book = 'HARVEST' AND COALESCE(t.real_loss, FALSE))
                                       ORDER BY t.net_profit ASC, t.family ASC), NULL) AS worst_net_profit
  FROM trended t
),
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- RULE 5 — THE MOOD OF THE CLOSING SENTENCE IS A FUNCTION OF WHETHER A FINDING WAS PUBLISHED.
-- The fifth self-contradiction was a shape, not a word: over the approved rate → "so this is a
-- comparison and not a finding" → "Pull those budgets yourself." Retraction, then order, about the
-- same subject, in one paragraph. Round 5's ban on "but" could not reach it; the prose used "so".
-- A word list cannot carry this, so the constraint is a COUPLING instead: an ORDER may be issued only
-- on a row where sanction_breach_finding is TRUE — at least one window lying wholly inside the
-- sanction and over its rate. Everywhere else the held budgets are still named and Ori may still act,
-- in the OPTION mood: the choice is stated as his, not as an instruction resting on a withdrawn
-- finding.
-- BOTH THE SENTENCE AND THE COLUMN THAT NAMES ITS MOOD COME FROM THIS ONE EXPRESSION, so they cannot
-- drift apart, and the acceptance query tests the coupling in both directions.
-- WHAT THIS DOES NOT CATCH, SAID PLAINLY: a rewrite that invents a NEW imperative sentence rather
-- than editing k.order_sentence escapes the string half of the check. What it cannot escape is the
-- mood column, which is published and which no prose can move.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
voiced AS (
  SELECT
    r.*,
    -- TRUE only where a window the sanction wholly covers is over its rate. NULL upstream means "no
    -- finding is available", which is not a finding, so COALESCE to FALSE is the correct read here
    -- and it fails in the safe direction: no finding, no order.
    COALESCE(r.sanction_breach_finding, FALSE)                          AS sanction_finding_published,
    CASE
      WHEN r.book <> 'INVEST'                          THEN NULL
      WHEN COALESCE(r.sanction_breach_finding, FALSE)  THEN 'ORDER'
      ELSE                                                  'OPTION'
    END                                                                 AS action_mood,
    IF(r.book <> 'INVEST', NULL,
       IF(COALESCE(r.sanction_breach_finding, FALSE), r.order_sentence, r.option_sentence))
                                                                        AS action_sentence,
    -- THE SENTENCE THIS ROW'S MOOD FORBIDS. Published so the acceptance query can test the coupling
    -- with NO string literal of its own: a verdict may never contain the sentence in the mood it was
    -- refused. Editing the wording in `k` moves the prose and the check together.
    IF(r.book <> 'INVEST', NULL,
       IF(COALESCE(r.sanction_breach_finding, FALSE), r.option_sentence, r.order_sentence))
                                                                        AS forbidden_sentence
  FROM ranked r
),
fam AS (
  SELECT
    b.book,
    'FAMILY'                AS row_kind,
    b.family,
    -- WHICH WINDOW THE MONEY COLUMNS BELONG TO — on the row, in words, not only in the prose.
    b.money_window,
    b.period_start,
    b.period_end,
    b.net_profit,
    -- NAMED FOR ITS WINDOW. It is the settled 90-day figure and it used to sit two columns from a
    -- 28-day spend rate with neither name saying so.
    b.ad_spend              AS ad_spend_in_money_window,
    b.total_net_roas,
    b.ads_net_roas,
    -- The share of the family's gross profit that Amazon's ad attribution did NOT claim: 1 - 1/halo.
    -- Not a measure of organic demand — see the note in `base`.
    b.share_of_return_with_no_ad_attribution_pct,
    -- Organic UNITS over total UNITS. A different fraction from the column above, which is a share of
    -- gross profit. Both names carry their denominator.
    b.organic_share_of_units_pct,
    -- WHICH WINDOW THE RATE COLUMNS BELOW BELONG TO. Deliberately shorter than the money window: a
    -- spend rate has to be current to bind. It names a real start AND a real end, off the upstream
    -- columns, and says in words how many complete days it holds.
    IF(b.spend_per_day IS NULL, NULL, b.rate_window_basis)              AS rate_window,
    b.rate_window_start,
    b.rate_window_end,
    -- TRUE when the ads feed has stopped moving under the window. Published as a boolean as well as
    -- in words, because a consumer that has to branch on it should not have to read English.
    b.rate_window_is_stale,
    b.launch_age_months,
    -- Why a trajectory series starts where it does, without spending verdict words on it.
    b.first_sale_date,
    -- The BINDING sanction trio: the rate, the date it was agreed, the date it runs to.
    b.daily_investment,
    b.sanctioned_on,
    b.stop_date             AS sanction_end_date,
    -- ─── BOTH ARMS OF A DUAL-WINDOW BREACH TEST ───
    b.spend_per_day         AS spend_per_day_in_rate_window,
    b.spend_per_day_7d      AS spend_per_day_last_7_days,
    b.spend_breach_arm      AS spend_breach_window,
    -- ─── WHAT THE UPSTREAM WILL ASSERT (Rule 2) ───
    -- FALSE means the agreement is too new for a complete window to sit inside it, so a rate above
    -- the agreed rate is a comparison. NULL on Harvest rows, where the concept does not apply — a
    -- withheld flag must not render downstream as a pass.
    b.sanction_adherence_judged,
    -- ─── ORI'S PER-WINDOW RULING, PUBLISHED AS COLUMNS AND NOT ONLY AS PROSE ───
    -- covers_* : does the sanction wholly cover this window (zero pre-sanction days in it).
    -- finding_*: the per-arm FINDING — TRUE only on a window the sanction covers AND that is over its
    --            rate. NULL is "no finding is available on this arm", never "this arm is clean".
    -- The COMPARISON is untouched and still rides beside them as spend_breached_28d /
    -- spend_breached_7d / spend_breach_window, which is what a reader needs to see the excess on a
    -- window nobody may be convicted on.
    -- These roll on the calendar with no code change: a window whose oldest day passes sanctioned_on
    -- flips covers_* to TRUE by itself, and the finding becomes available on that arm alone.
    b.sanction_covers_rate_window,
    b.sanction_covers_short_window,
    b.sanction_finding_in_rate_window,
    b.sanction_finding_in_short_window,
    b.sanction_breach_finding,
    b.sanction_breach_finding_window,
    -- Rule 5's coupling, published: whether this row carries a finding at all, and therefore whether
    -- its closing sentence is allowed to be an order. A consumer branching on the mood never has to
    -- parse the prose, and the acceptance query checks the two against each other.
    b.sanction_finding_published,
    -- HOW MANY FAMILIES ON THIS ROW CARRY A FINDING. On a family row it is 1 or 0; on a book total it
    -- is the count over the priced families. Rule 2's assertion keys on it, so the conviction word
    -- can be tested at BOTH grains with one expression: a total may say that some families forfeit
    -- protection while the BOOK does not, and that sentence is true exactly when this count is > 0.
    IF(b.book <> 'INVEST', NULL, IF(b.sanction_finding_published, 1, 0))
                            AS families_with_a_sanction_finding,
    b.action_mood           AS verdict_action_mood,
    b.action_sentence       AS verdict_action_sentence,
    b.forbidden_sentence    AS verdict_forbidden_sentence,
    -- ─── THE TWO PROTECTION STATES, PUBLISHED SEPARATELY ───
    -- QUALIFIED = has this launch earned protection under the rules. ENFORCED = is the coach applying
    -- protection to its campaigns. They are allowed to disagree, and when they do the verdict says
    -- both out loud as well.
    b.protection_qualified,
    b.protection_enforced,
    -- The size of that disagreement, SPLIT BY WHAT THE DECISION IS, because "stop this campaign" and
    -- "trim this budget" are different jobs worth different money. The dollar columns are what
    -- APPLYING the held decisions would take off the daily budgets.
    b.stops_held            AS stops_the_coach_is_holding,
    b.trims_held            AS trims_the_coach_is_holding,
    b.stops_budget          AS daily_budget_the_held_stops_would_free,
    b.trims_budget          AS daily_budget_the_held_trims_would_free,
    -- MONTH-TO-DATE AND ON ITS OWN WINDOW, which is neither of the other two on this row, with both
    -- sides of the fraction beside it in dollars.
    b.monthly_loss_ceiling  AS loss_allowance_dollars_for_the_month,
    IF(b.mtd_net_profit IS NULL, NULL, ROUND(-b.mtd_net_profit, 2))
                            AS loss_so_far_dollars_against_that_allowance,
    b.loss_allowance_window,
    -- THE TRAJECTORY, PUBLISHED. Absolute organic units, ORDINALS counted off the most recent whole
    -- month the family lived through — "last" and "1 ago" are the same month in ordinary speech and
    -- relative English cannot carry this. The columns hold only whole-months-lived, exactly the
    -- series the verdict prints, so column and sentence cannot disagree about the trajectory, and a
    -- NULL here means "not a whole month for this family", never "no units".
    IF(b.has_m2, b.org_m2, NULL) AS organic_units_3rd_last_whole_month,
    IF(b.has_m1, b.org_m1, NULL) AS organic_units_2nd_last_whole_month,
    IF(b.has_m0, b.org_m0, NULL) AS organic_units_last_whole_month,
    -- THE WORD ITSELF, so the sentence cannot claim a direction the column does not, and so Rule 4
    -- has something mechanical to key on. NULL = no direction is being published.
    -- GATED ON THE BOOK, like every other launch concept. The organic series is read from
    -- V_INVEST_STATUS, which holds only Invest families, so a Harvest row's steps are already zero —
    -- but Rule 4 now asserts that a published direction APPEARS in the verdict, and only the Invest
    -- verdict prints one. Leaving the gate implicit would make that assertion depend on the shape of
    -- an upstream universe rather than on this row's book.
    CASE WHEN b.book <> 'INVEST'                           THEN NULL
         WHEN b.n_steps = 0                                THEN NULL
         WHEN b.steps_up > 0 AND b.steps_down = 0          THEN 'climbing'
         WHEN b.steps_down > 0 AND b.steps_up = 0          THEN 'falling'
         WHEN b.steps_up = 0 AND b.steps_down = 0          THEN 'flat'
         ELSE 'mixed' END                                  AS organic_units_trend,
    -- ACCOUNT-LEVEL, BELONGING TO NEITHER BOOK, ON THE HARVEST TOTAL ROW ONLY.
    CAST(NULL AS FLOAT64)   AS account_ad_spend_in_neither_book,
    -- ─── THE FOUR BOOK-LEVEL LISTS, COMPLETE, ON THE TOTAL ROWS ───
    -- Rule 3 is a bound on a verdict's LENGTH, and a verdict that spells out a list is as long as the
    -- list. Every list here is data-shaped — one term per family, one per distinct sanction end date
    -- — so a constant cap over the prose was never provable: a fifth family broke it exactly the way
    -- the calendar broke it. The lists live in these columns IN FULL and the verdicts name at most
    -- three terms before switching to a count. Nothing is withheld; it moved to where a list belongs.
    -- NULL on family rows: a family has one end date (sanction_end_date) and is not a list.
    CAST(NULL AS STRING)    AS sanction_end_dates,
    CAST(NULL AS STRING)    AS families_inside_break_even_band,
    CAST(NULL AS STRING)    AS families_with_nothing_measured,
    CAST(NULL AS STRING)    AS families_with_no_approved_rate,
    CASE
      -- ───────── INVEST: sanction adherence + trajectory. Never a profit verdict. ─────────
      WHEN b.book = 'INVEST' THEN CONCAT(
        -- THE RATE, WHAT THE RULES MAKE OF IT, AND WHAT THE MACHINE IS DOING — three clauses, in
        -- that order, never merged, and each a sentence that stands alone (Rule 1).
        CASE
          WHEN b.daily_investment IS NULL THEN CONCAT(
            b.family, ' is in the investment book with no approved daily spend on record. ',
            'Nothing is holding it. Write the sanction down.')
          -- Every clause below formats spend_per_day, and FORMAT('$%.2f', NULL) is NULL, which turns
          -- the whole CONCAT into NULL and prints an empty line on the morning read.
          WHEN b.spend_per_day IS NULL THEN CONCAT(
            b.family, ' has an approved rate of ', b.daily_investment_text, ' a day',
            b.sanction_end_text,
            '. Nothing it spent could be measured over the rate window, so none of its spending is ',
            'in the investment total. Check that its campaigns carry the family name.')
          ELSE CONCAT(
            -- 1. THE RATE, on the window upstream measured it over.
            b.family, ' spent ', FORMAT('$%.2f', b.spend_per_day), ' a day ',
            b.rate_window_phrase, ' against ', b.daily_investment_text, ' a day approved',
            b.sanction_end_text, '. ',
            -- 1b. WHICH ARM OF THE DUAL-WINDOW TEST IS OVER. The long-window rate alone beside the
            -- word "breached" is false on the day the short arm fires by itself.
            CASE
              WHEN b.spend_breached IS NULL THEN ''
              WHEN COALESCE(b.spend_breached_28d, FALSE) AND COALESCE(b.spend_breached_7d, FALSE)
                THEN 'It is over on that window and on the last 7 days. '
              WHEN COALESCE(b.spend_breached_28d, FALSE)
                THEN 'It is over on that window. The last 7 days are inside the rate. '
              WHEN COALESCE(b.spend_breached_7d, FALSE)
                THEN 'It is inside the rate on that window. The last 7 days are over it. '
              ELSE 'It is inside the rate on both windows. '
            END,
            -- 2. WHAT THE RULES SAY — AND ONLY IF THE UPSTREAM WILL SAY IT (Rule 2).
            -- When sanction_adherence_judged is FALSE the agreement is too new for a complete window
            -- to lie inside it, so the comparison is stated as a comparison and no protection is
            -- forfeited, lost or retained in words. This branch is the live one today.
            CASE
              -- (a) A FINDING. At least one window lies WHOLLY inside the agreement and is over its
              -- rate, so the agreement was broken over days it actually covered. This is the only
              -- state in which this object convicts, and it is also the only state in which the
              -- closing sentence may be an order (Rule 5).
              WHEN b.sanction_finding_published THEN CONCAT(
                CASE
                  WHEN b.sanction_breach_finding_window = 'both windows' THEN
                    'Both windows lie wholly inside the agreement, so that forfeits its launch protection. '
                  WHEN b.sanction_breach_finding_window = '28-day window' THEN
                    CONCAT('Those ', CAST(b.rate_window_days AS STRING),
                           ' days lie wholly inside the agreement, so that forfeits its launch protection. ')
                  ELSE
                    CONCAT('The last ', CAST(b.short_window_days AS STRING),
                           ' days lie wholly inside the agreement, so that forfeits its launch protection. ')
                END,
                -- AND THE OTHER ARM DOES NOT INHERIT THAT STANDING. The short window is a suffix of
                -- the long one, so the long window is the only arm that can still reach back before
                -- the agreement. When it does and it is over its rate, its excess is named as the
                -- comparison it is, in the same breath as the finding on the arm that earned one.
                IF(NOT COALESCE(b.sanction_covers_rate_window, FALSE)
                   AND COALESCE(b.spend_breached_28d, FALSE),
                   CONCAT('The ', CAST(b.rate_window_days AS STRING),
                          '-day window still reaches back before the agreement, so its excess is a comparison. '),
                   ''))
              -- (b) AN EXCESS WITH NO ARM ENTITLED TO A FINDING. State it in full and convict nobody.
              WHEN COALESCE(b.spend_breached, FALSE) THEN CONCAT(
                IF(b.rate_window_days_before_sanction IS NULL,
                   'The agreement does not yet wholly cover either window, so this is a comparison and not a finding. ',
                   CONCAT(CAST(b.rate_window_days_before_sanction AS STRING), ' of those ',
                          CAST(b.rate_window_days AS STRING), ' days sit before the rate was agreed',
                          IF(COALESCE(b.short_window_days_before_sanction, 0) > 0,
                             CONCAT(', and ', CAST(b.short_window_days_before_sanction AS STRING),
                                    ' of the last ', CAST(b.short_window_days AS STRING),
                                    ', so both are comparisons and not findings. '),
                             ', so that excess is a comparison and not a finding. '))),
                -- The arm that DOES have standing and is clean says so on its own account. Withholding
                -- the finding is not the same as having nothing to report about that window.
                IF(COALESCE(b.sanction_covers_short_window, FALSE)
                   AND b.spend_breached_7d IS NOT NULL AND NOT b.spend_breached_7d,
                   CONCAT('The last ', CAST(b.short_window_days AS STRING),
                          ' days lie wholly inside the agreement and are inside the rate. '),
                   ''))
              -- (c) NO EXCESS ON EITHER ARM. Say whether protection holds, and when it does not, name
              -- the test that actually failed.
              -- THE OLD ELSE NAMED A CAUSE THAT WAS NOT THE CAUSE: a family with no breach and
              -- protection FALSE fell past a days_left test and a ceiling test into "the sanction is
              -- not fully on record", when the real blocker upstream is a withheld window day, a rate
              -- that cannot be certified as current, or a family that does not resolve to one book
              -- assignment row. Every one of those is on the row now and each has its own sentence.
              -- ORDER MATTERS AND stop_date COMES FIRST: days_left is derived from it, so a missing
              -- end date used to read as "the agreed end date has passed".
              WHEN COALESCE(b.protection_qualified, FALSE) THEN
                'It still qualifies for launch protection. '
              WHEN b.stop_date IS NULL THEN
                'No end date is on record for the sanction, so protection cannot be certified. '
              WHEN COALESCE(b.days_left, 0) < 0 THEN
                'The agreed end date has passed, so it no longer qualifies for launch protection. '
              WHEN COALESCE(b.ceiling_used_pct, 0) >= 100 THEN
                'It has used up the losses allowed this month, so it no longer qualifies for launch protection. '
              WHEN b.monthly_loss_ceiling IS NULL THEN
                'No monthly loss ceiling is on record, so protection cannot be certified. '
              WHEN COALESCE(b.rate_window_is_stale, FALSE) THEN
                'Its rate is not current, so it does not qualify for launch protection. '
              WHEN b.rate_window_is_stale IS NULL THEN
                'Its rate could not be certified as current, so it does not qualify for launch protection. '
              WHEN NOT COALESCE(b.rate_window_data_complete, FALSE)
                OR NOT COALESCE(b.short_window_data_complete, FALSE) THEN
                'A day of one of those windows never arrived, so protection cannot be certified. '
              WHEN COALESCE(b.book_assignment_rows, 0) <> 1 THEN
                'It does not resolve to a single book assignment, so protection cannot be certified. '
              WHEN NOT COALESCE(b.sanction_adherence_judged, FALSE) THEN
                'No window lies wholly inside the agreement yet, so protection cannot be certified. '
              ELSE
                'It does not qualify for launch protection, and no test on this row says which one it failed. '
            END,
            -- 3. WHAT THE MACHINE IS DOING. It always speaks, it never guesses, and where the two
            -- states disagree it carries the size of the gap in dollars.
            CASE
              WHEN b.protection_enforced IS NULL THEN
                'Whether the coach is protecting it could not be checked today. Check the launch exemption.'
              WHEN COALESCE(b.protection_qualified, FALSE) AND b.protection_enforced THEN
                'The coach is applying that protection.'
              WHEN COALESCE(b.protection_qualified, FALSE) THEN
                'The coach is not applying it, so it is judged on money already. Check the launch exemption.'
              WHEN NOT b.protection_enforced THEN
                'The coach has withdrawn protection, so it is judged on money like every other family.'
              WHEN COALESCE(b.cuts_held, 0) > 0 THEN CONCAT(
                'The coach is still protecting it: it holds ',
                -- NAME THE DECISIONS, THEN PRICE THEM PER KIND.
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
                ' worth ', FORMAT("$%'d", CAST(ROUND(b.cuts_budget) AS INT64)), ' a day. ',
                IF(COALESCE(b.trims_unsized, 0) > 0,
                   CONCAT(CAST(b.trims_unsized AS STRING),
                          IF(b.trims_unsized = 1,
                             ' of those trims has no target on record, so that figure runs low. ',
                             ' of those trims have no target on record, so that figure runs low. ')),
                   ''),
                -- RULE 5. An ORDER here only where a finding was published one clause above; an
                -- OPTION everywhere else. Same expression that fills verdict_action_mood.
                b.action_sentence)
              ELSE CONCAT(
                'The coach is still protecting it, and no budget cut is queued today. ',
                b.action_sentence)
            END)
        END,
        -- ─────────────────────────────────────────────────────────────────────────────────────
        -- THE TRAJECTORY CLAUSE — the primary evidence an Invest family is judged on.
        -- RULE 4 LIVES HERE. When organic_units_trend is NULL this clause prints a number and stops:
        -- no word that implies a direction may appear anywhere in the verdict, because the row is
        -- refusing to publish one. The old text withheld the direction and then referred to "the
        -- improvement" two sentences later.
        -- The series is whole-months-lived only; first_sale_date is on the row for a reader who wants
        -- to know why it starts where it does.
        -- ─────────────────────────────────────────────────────────────────────────────────────
        CASE
          WHEN NOT b.has_m0 THEN ' No whole calendar month of organic units yet.'
          WHEN b.n_steps = 0 THEN CONCAT(
            ' ', CAST(b.org_m0 AS STRING), ' organic units in its one whole calendar month.')
          ELSE CONCAT(
            ' Organic units are ',
            CASE WHEN b.steps_up > 0 AND b.steps_down = 0   THEN 'climbing'
                 WHEN b.steps_down > 0 AND b.steps_up = 0   THEN 'falling'
                 WHEN b.steps_up = 0 AND b.steps_down = 0   THEN 'flat'
                 ELSE 'mixed' END,
            ': ',
            IF(b.has_m2, CONCAT(CAST(b.org_m2 AS STRING), ', then '), ''),
            CAST(b.org_m1 AS STRING), ', then ', CAST(b.org_m0 AS STRING),
            ', over its ', IF(b.has_m2, 'three', 'two'), ' whole calendar months.')
        END,
        -- THE AGE CLAUSE IS GONE FROM THE RAMP BRANCH. It was the site of two of the four
        -- self-contradictions ("what matters is whether it is improving" cancelling the sentence
        -- above it; a second clause asserting an improvement the clause above it had
        -- withheld). launch_age_months is a column, and a clause that only restates a column is not
        -- worth the risk. What survives is the PROOF-phase clause, which asks for something.
        CASE
          WHEN b.launch_age_months IS NULL OR b.phase = 'RAMP' THEN ''
          WHEN b.takeover_target_organic_units IS NULL THEN
            ' It is past the early stretch. Say how many organic units a month would let it stand alone.'
          WHEN b.org_m0 IS NULL THEN
            ' It is past the early stretch. Last month\'s organic units are not measured for it.'
          ELSE CONCAT(
            ' It is past the early stretch: ', CAST(b.org_m0 AS STRING),
            ' organic units last month against the ',
            CAST(b.takeover_target_organic_units AS STRING), ' you set.')
        END,
        -- A declared launch whose ASINs are not yet mapped has no measured P&L. It spends every day,
        -- so it must never read as a normal row with quiet blank columns — and the sentence has to
        -- say WHICH half is missing.
        CASE
          WHEN b.money_measured THEN ''
          WHEN NOT b.pnl_has_profit AND NOT b.pnl_has_spend THEN
            ' None of its money is measured, so none of it is in the investment total. Check the product mapping.'
          WHEN NOT b.pnl_has_profit THEN
            ' Its advertising is counted and its sales are not, so none of its cost is in the investment total. Check the product mapping.'
          ELSE
            ' Its sales are counted and its advertising is not, so none of its cost is in the investment total. Check the product mapping.'
        END,
        -- A FROZEN FEED FAILS CLOSED. The window always holds its full count of complete days. It
        -- is anchored on the ads feed: if the feed stops, the window stops and the rate describes days
        -- that are no longer recent. Three-state, because upstream the same unknown withdraws
        -- protection and a COALESCE to FALSE here would print "we could not check" as "it is fine".
        CASE
          WHEN b.rate_window_is_stale THEN
            ' That rate\'s advertising has stopped arriving; nothing can be certified against it.'
          WHEN b.rate_window_is_stale IS NULL AND b.spend_per_day IS NOT NULL THEN
            ' Whether that advertising is still arriving could not be checked; treat the rate as uncertified.'
          ELSE ''
        END)

      -- ───────── HARVEST: dollars lead, the ratio explains them. ─────────
      -- NULL FIRST. A harvest family with no measured profit falls through every branch below
      -- (NULL >= 0 is NULL, NOT NULL is NULL) into a CONCAT over NULLs, which prints as a BLANK LINE.
      -- And the branch has to name the actual gap rather than assert a shape.
      WHEN NOT b.money_measured THEN CONCAT(
        b.family, ' is judged on money. ',
        CASE
          -- money_window is NULL on exactly these rows — this branch fires when no window was
          -- measured for the family — so naming a span here would be inventing one.
          WHEN NOT b.pnl_has_profit AND NOT b.pnl_has_spend THEN
            'Nothing it sells is counted under this family name: no sales, no ad spend, no profit'
          WHEN NOT b.pnl_has_profit THEN
            'Only its advertising is counted: ad spend against it and no profit figure'
          ELSE
            'Its advertising is not counted: a profit figure with no ad spend behind it'
        END,
        '. That is a mapping gap, and it is left out of the harvest total. ',
        'Check the product mapping before you trust that total.')

      -- ───────────────────────────────────────────────────────────────────────────────────────
      -- WHAT THE RATIO DIVIDES, IN THE FEWEST WORDS THAT KEEP IT TRUE.
      -- V_FAMILY_PNL: net_profit = SUM(sales - cogs) - SUM(ad_cost) while
      -- total_net_roas = SUM(sales - cogs) / SUM(ad_cost). The ratio's numerator is the family's
      -- GROSS profit, taken BEFORE advertising; the net_profit column the same sentence leads with
      -- subtracts it, and the difference between the two readings is the entire ad budget. So the
      -- gloss names the quantity and where the ad cost sits in it: "family gross profit before ad
      -- cost". It also may NOT say the ads "pull in" the rest — total_net_roas counts every sale that
      -- would have happened with no advertising, and nothing in this pipeline decides which organic
      -- sales the ads caused. "Attributed or not" is a statement about attribution, not causation.
      -- ads_net_roas is glossed the same way and for the same reason: its numerator is
      -- FACT_AMAZON_ADS.GROSS_PROFIT, which is also before ad cost.
      -- ───────────────────────────────────────────────────────────────────────────────────────
      WHEN b.real_profit THEN CONCAT(
        b.family, ' made ', FORMAT("$%'d", CAST(b.net_profit AS INT64)), ' over ', b.money_window,
        ' on ', FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend. Every ad dollar returns ',
        b.total_net_roas_text, ' of family gross profit before ad cost, attributed or not, and ',
        b.ads_net_roas_text, ' counting only ad-attributed gross profit. Keep it running.')

      -- ───────────────────────────────────────────────────────────────────────────────────────
      -- THE BREAK-EVEN BRANCH MAY NOT CALL A LOSS A PROFIT, AND ROUNDING MAY NOT DECIDE IT.
      -- It fires on a family whose result — EITHER SIGN — is smaller than the declared breakeven
      -- band. The sentence used to round a return a hair under 1.00 up to "$1.00" and
      -- then assert "a family that is paying its way". The claim is gone, the ratio cannot round
      -- across $1.00 (total_net_roas_text), and the point that matters — do not cut this on the
      -- ads-only figure — is made without it. Rule 1: the old "too small to act on, BUT a shortfall"
      -- is two sentences now.
      -- AND IT NOW FIRES ON BOTH SIDES OF ZERO. It used to be reachable only from below, so a family
      -- inside the band on the profit side was sent to the "made money, keep it running" branch and a
      -- family the same distance below it was called noise. Same distance, opposite verdict, decided
      -- by sign. The branch keeps the sign in the words — ahead of its costs or short of them — and
      -- says of both that the distance is too small to act on.
      -- ───────────────────────────────────────────────────────────────────────────────────────
      WHEN b.inside_band THEN CONCAT(
        b.family,
        IF(b.net_profit >= 0,
           CONCAT(' finished ', FORMAT("$%'d", CAST(b.net_profit AS INT64)), ' ahead of its costs over '),
           CONCAT(' came within ', FORMAT("$%'d", CAST(-b.net_profit AS INT64)),
                  ' of covering its costs over ')),
        b.money_window, ' on ',
        FORMAT("$%'d", CAST(b.ad_spend AS INT64)),
        ' of ad spend. That is inside the break-even band, so it is too small to be worth acting on. ',
        IF(b.net_profit >= 0,
           'It is a margin, not evidence that the family is earning. ',
           'It is a shortfall, not a profit. '),
        'Every ad dollar returns ', b.total_net_roas_text,
        ' of family gross profit before ad cost, attributed or not, and ', b.ads_net_roas_text,
        ' counting only ad-attributed gross profit.',
        IF(b.wide_halo AND b.share_of_return_with_no_ad_attribution_pct IS NOT NULL,
           CONCAT(' ', CAST(b.share_of_return_with_no_ad_attribution_pct AS STRING),
                  '% of that gross profit carries no ad attribution, so do not cut this family on ',
                  'the ads-only figure.'),
           ''))

      ELSE CONCAT(
        b.family, ' lost ', FORMAT("$%'d", CAST(-b.net_profit AS INT64)), ' over ', b.money_window,
        ' on ', FORMAT("$%'d", CAST(b.ad_spend AS INT64)), ' of ad spend',
        IF(b.loss_rank = 1,
           ' — the biggest loss in the harvest book, so this is the one to fix first. ',
           CONCAT(' — a smaller loss than ', b.worst_family, "'s ",
                  FORMAT("$%'d", CAST(-b.worst_net_profit AS INT64)), ', so it waits behind that one. ')),
        'Every ad dollar returns ', b.total_net_roas_text,
        ' of family gross profit before ad cost, attributed or not, and ', b.ads_net_roas_text,
        ' counting only ad-attributed gross profit.')
    END                     AS verdict
  FROM voiced b
),
-- One aggregate per book. NOTHING here groups across books, and there is no second aggregation above
-- this: that absence IS the no-grand-total guarantee.
-- The worst Harvest loser is computed HERE rather than in its own CTE — an extra one-row aggregate
-- cross-joined in would cost a whole extra expansion of `base` for two scalars. ARRAY_AGG inside the
-- aggregate that already exists gets the same two values with the same ordering and the same total
-- tie-break as loss_rank, so the two can never disagree.
agg AS (
  SELECT
    book,
    COUNT(*)                                       AS n_families,
    COUNTIF(money_measured)                        AS n_measured,
    -- Every measured family shares one window, so MIN/MAX are the window itself; NULL when the book
    -- measured nothing, which is the honest answer rather than a borrowed date.
    MIN(period_start)                              AS period_start,
    MAX(period_end)                                AS period_end,
    -- THE WINDOW IN WORDS, BUILT ONCE, so the column and every sentence quoting it move together.
    IF(MAX(period_end) IS NULL, NULL,
       CONCAT('the settled ', CAST(DATE_DIFF(MAX(period_end), MIN(period_start), DAY) + 1 AS STRING),
              ' days to ', FORMAT_DATE('%-d %B %Y', MAX(period_end)))) AS money_window,
    -- BOTH SUMS OVER THE SAME SUBSET AS THE COUNT. A family with only half a P&L contributes to
    -- NEITHER, so the count in the sentence, the two money columns and the reconciliation all
    -- describe one identical set of families.
    SUM(IF(money_measured, net_profit, NULL))      AS net_profit,
    SUM(IF(money_measured, ad_spend,   NULL))      AS ad_spend,
    -- THE SANCTION SUMS COVER EXACTLY THE FAMILIES THEY CAN COVER. An INVEST family with no
    -- V_INVEST_STATUS row, or no approved rate written down, contributes NULL to both sums. Both
    -- sides are taken over the SAME priced subset, the count of that subset is published, and the
    -- families outside it are named in words instead of silently thinned out of the money.
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL) AS n_priced,
    SUM(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, daily_investment, NULL)) AS daily_investment,
    -- ─── THE OTHER BINDING TERM, AGGREGATED THE ONLY WAY A BOOK CAN CARRY IT ───
    -- A book has no single end date, so it carries the span of them plus a count of the sanctions
    -- with no end date at all. The COLUMN on the total row names none of them — publishing MAX let
    -- the book inherit the more generous of two terms — and the verdict names every one.
    -- EVERY END DATE, NOT THE FIRST AND THE LAST. The header promised "the verdict names every end
    -- date the book actually holds" and the code printed two joined by "and", which reads as a
    -- complete enumeration and is one at exactly two dates and no more. With three sanctions on three
    -- terms it silently dropped the middle one. The distinct dates ride here as an ordered array and
    -- the verdict lists all of them; the claim and the code now say the same thing.
    ARRAY_AGG(DISTINCT IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, stop_date, NULL)
              IGNORE NULLS
              ORDER BY IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, stop_date, NULL))
                                                                        AS stop_dates,
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL AND stop_date IS NULL) AS n_no_end_date,
    -- ─── THE BOOK'S RATE IS COMPUTED OVER THE BOOK, NOT ADDED UP FROM ROUNDED FAMILY RATES ───
    -- Every term in SUM(spend_per_day) has already been rounded to the cent upstream, so that sum is
    -- a sum of roundings rather than a rate, and the error grows with the number of families. This is
    -- the same arithmetic the family rate uses, one level up: the dollars the book spent inside the
    -- window over the days in it.
    -- THE DENOMINATOR IS ONLY LEGITIMATE IF EVERY PRICED FAMILY IS ON THE SAME WINDOW, and the code
    -- comment that used to sit here — "the window is a single span shared by every family, so MAX is
    -- picking a constant" — stopped being true the day a window could be WITHHELD per family. These
    -- stay MAX, and every one of them is renamed to say so; `rate_window_shared` below is the test
    -- that decides whether a pick is a constant, and `tot` publishes NOTHING off these until it
    -- passes. Withhold, never substitute.
    ROUND(SAFE_DIVIDE(
      SUM(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_spend, NULL)),
      NULLIF(MAX(rate_window_days), 0)), 2)                             AS spend_per_day,
    -- The book's short-window rate, same construction, so the total can name both arms too.
    ROUND(SAFE_DIVIDE(
      SUM(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL,
             spend_per_day_7d * short_window_days, NULL)),
      NULLIF(MAX(short_window_days), 0)), 2)                            AS spend_per_day_7d,
    -- ─── EVERY SANCTION COUNT IS TAKEN OVER THE PRICED SET, WHICH IS THE SET THE SENTENCE NAMES ───
    -- These used to count ALL families in the book while n_priced counted only those with both a
    -- sanction and a rate, and the clause compared the two. With one unpriced family in the book the
    -- comparison n_over_28d = n_priced could hold on a set that was never counted, and the sentence
    -- said "all of them" of it. One set now, the priced one, everywhere.
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(spend_breached_28d, FALSE))    AS n_over_28d,
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(spend_breached_7d,  FALSE))    AS n_over_7d,
    -- ─── ORI'S PER-WINDOW RULING AT BOOK LEVEL, FAIL-CLOSED ───
    -- A book may be convicted only where EVERY priced family carries a finding of its own. One
    -- family's finding is not the book's, exactly as one family's sanction is not the book's.
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(sanction_breach_finding, FALSE))               AS n_finding,
    -- AND THE OTHER SIDE OF THE THREE-VALUED ANSWER. A priced family whose finding is FALSE was
    -- MEASURED on every window the sanction covers and is inside its rate on all of them. Counting
    -- only the TRUEs would let "no finding is available" render on a total as "measured, and clean",
    -- which is the substitution Ori's rule forbids. Both counts, so the total can say TRUE, FALSE or
    -- nothing at all.
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND sanction_breach_finding IS FALSE)                       AS n_finding_clear,
    -- The book-level finding, fail-closed and computed ONCE: a book carries a finding only when it
    -- has priced families and EVERY one of them carries a finding of its own. This is the single
    -- expression Rule 5's mood, the total's conviction clause and the published columns all read.
    IF(COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL) = 0, FALSE,
       COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
               AND COALESCE(sanction_breach_finding, FALSE))
         = COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL))
                                                                        AS book_finding_published,
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(sanction_covers_rate_window, FALSE))           AS n_covers_rate_window,
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(sanction_covers_short_window, FALSE))          AS n_covers_short_window,
    MAX(rate_window_basis)                         AS rate_window_basis_max,
    MAX(rate_window_phrase)                        AS rate_window_phrase_max,
    MAX(rate_window_start)                         AS rate_window_start_max,
    MAX(rate_window_end)                           AS rate_window_end_max,
    MAX(rate_window_days)                          AS rate_window_days_max,
    MAX(short_window_days)                         AS short_window_days_max,
    -- ─── IS THAT PICK A CONSTANT? THE TEST, NOT THE ASSUMPTION ───
    -- TRUE only when every priced family carries a rate window and they are all the same span with
    -- the same words. MIN = MAX over a set with no NULLs in it is a unanimity test; the count guard
    -- is there because MIN and MAX both ignore NULLs, so one withheld window beside one published one
    -- would otherwise compare equal to itself and pass.
    IF(COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL) = 0, NULL,
       COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
               AND rate_window_start IS NOT NULL AND rate_window_end IS NOT NULL
               AND rate_window_days IS NOT NULL AND short_window_days IS NOT NULL
               AND rate_window_basis IS NOT NULL AND rate_window_phrase IS NOT NULL)
         = COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL)
       AND MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_start, NULL))
         = MAX(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_start, NULL))
       AND MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_end, NULL))
         = MAX(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_end, NULL))
       AND MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_days, NULL))
         = MAX(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_days, NULL))
       AND MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, short_window_days, NULL))
         = MAX(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, short_window_days, NULL))
       AND MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_basis, NULL))
         = MAX(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_basis, NULL))
       AND MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_phrase, NULL))
         = MAX(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, rate_window_phrase, NULL)))
                                                   AS rate_window_shared,
    -- The honest book-level version of "how much of the window predates the agreement": the SMALLEST
    -- such count over the priced families, spoken as "at least", because the sanctions were not
    -- necessarily agreed on the same day.
    MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL,
           rate_window_days_before_sanction, NULL))                     AS days_before_sanction_min,
    MIN(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL,
           short_window_days_before_sanction, NULL))                    AS short_days_before_sanction_min,
    -- ─── RULE 2 AT BOOK LEVEL, FAIL-CLOSED ───
    -- A book may convict only if EVERY priced family in it is judged. LOGICAL_AND over a
    -- COALESCE(..., FALSE) so an unknown counts as unjudged, and NULL when the book has no priced
    -- family at all — Harvest reads NULL, never TRUE.
    IF(COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL) = 0, NULL,
       LOGICAL_AND(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL,
                      COALESCE(sanction_adherence_judged, FALSE), TRUE)))
                                                   AS sanction_adherence_judged,
    -- Not LOGICAL_OR(COALESCE(..., FALSE)): coalescing first turns "this book has no rate window at
    -- all" into a confident FALSE on the HARVEST total. LOGICAL_OR ignores NULLs and returns NULL
    -- when every input is NULL, which is the honest answer for a book that never had a window.
    LOGICAL_OR(rate_window_is_stale)               AS rate_window_is_stale,
    COUNTIF(real_loss)                             AS n_real_losses,
    -- A THREE-WAY SPLIT, AND THE MIDDLE STATE NOW REACHES FROM BOTH SIDES OF ZERO. Earning by more
    -- than the band, inside the band either way, losing by more than the band. The total used to use
    -- two sides and imply the third ("fix that one and the rest is working", printed above a row
    -- saying it was short of covering its costs); it also called a family inside the band on the
    -- profit side "earning", which is the asymmetry the band exists to prevent. All three are counted
    -- here so the total describes the remainder instead of implying it.
    COUNTIF(real_profit)                           AS n_earning,
    COUNTIF(money_measured AND COALESCE(inside_band, FALSE)) AS n_in_band,
    -- Named, and ordered by family so two consecutive pulls are byte-identical.
    STRING_AGG(IF(money_measured AND COALESCE(inside_band, FALSE), family, NULL),
               ' and ' ORDER BY family)            AS in_band_families,
    -- The sign each band family sits on, counted, so the sentence can say "short of" and "ahead of"
    -- without re-deriving either.
    COUNTIF(money_measured AND COALESCE(inside_band, FALSE) AND net_profit < 0) AS n_in_band_below,
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(spend_breached, FALSE))   AS n_over_rate,
    -- Scoped to the priced set like every other sanction count, so the clause that compares it to
    -- n_priced compares two counts of the same families. Upstream cannot qualify an unpriced family,
    -- so this changes no number today; it removes the way a future change could.
    COUNTIF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL
            AND COALESCE(protection_qualified, FALSE))                      AS n_qualified,
    COUNTIF(COALESCE(protection_enforced,  FALSE))                          AS n_enforced,
    COUNTIF(protection_enforced IS NOT NULL)                                AS n_enforcement_known,
    -- NULL, not 0, when nothing in the book could be checked — SUM ignores NULLs, and a book of
    -- families the coach's budget pass has never seen must not report "holding nothing". Summed per
    -- decision kind, so the book is priced the same way the family rows are.
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
    -- Named, not just counted: "one family is missing" sends nobody anywhere.
    STRING_AGG(IF(money_measured, NULL, family), ' and ' ORDER BY family) AS unmeasured_families,
    STRING_AGG(IF(daily_investment IS NOT NULL AND spend_per_day IS NOT NULL, NULL, family),
               ' and ' ORDER BY family)                                 AS unpriced_families
  FROM trended
  GROUP BY book
),
tot AS (
  SELECT
    s.book,
    'TOTAL'                                          AS row_kind,
    CAST(NULL AS STRING)                             AS family,
    -- Built once in `agg` and read here, so this column and every sentence quoting the window are the
    -- same string.
    a.money_window,
    a.period_start,
    a.period_end,
    -- NOT IFNULL(..., 0). A book with nothing measured has no total, and a zero here would claim it
    -- was measured and found to be nothing.
    a.net_profit,
    a.ad_spend                                       AS ad_spend_in_money_window,
    CAST(NULL AS FLOAT64)                            AS total_net_roas,
    CAST(NULL AS FLOAT64)                            AS ads_net_roas,
    CAST(NULL AS INT64)                              AS share_of_return_with_no_ad_attribution_pct,
    CAST(NULL AS FLOAT64)                            AS organic_share_of_units_pct,
    -- ─── THE BOOK'S WINDOW IS PUBLISHED ONLY IF THE BOOK HAS ONE ───
    -- These were MAX over the families and were published as the book's window and quoted in the
    -- book's verdict. A MAX over families is a PICK, not an aggregate, and the comment that justified
    -- it — the window is one span shared by every family — stopped being true the day a window could
    -- be withheld for one family and not another. Now: unanimous or nothing, on the same priced set
    -- the dollars are summed over. When the priced families are not on one window the book has no
    -- window, no rate and no phrase, and the verdict says so instead of quoting one family's.
    IF(COALESCE(a.rate_window_shared, FALSE), a.rate_window_basis_max, NULL) AS rate_window,
    IF(COALESCE(a.rate_window_shared, FALSE), a.rate_window_start_max, NULL) AS rate_window_start,
    IF(COALESCE(a.rate_window_shared, FALSE), a.rate_window_end_max,   NULL) AS rate_window_end,
    a.rate_window_is_stale,
    CAST(NULL AS INT64)                              AS launch_age_months,
    CAST(NULL AS DATE)                               AS first_sale_date,
    a.daily_investment,
    -- A book has no single agreement date and no single end date. Both are NULL here and the verdict
    -- names every end date the book actually holds. The old column held MAX(stop_date), which let the
    -- book inherit the later of two terms and publish one family's date as the book's.
    CAST(NULL AS DATE)                               AS sanctioned_on,
    CAST(NULL AS DATE)                               AS sanction_end_date,
    -- WITHHELD WITH THE WINDOW THEY ARE MEASURED OVER. A book rate whose denominator was picked from
    -- one family's window is not the book's rate.
    IF(COALESCE(a.rate_window_shared, FALSE), a.spend_per_day,    NULL) AS spend_per_day_in_rate_window,
    IF(COALESCE(a.rate_window_shared, FALSE), a.spend_per_day_7d, NULL) AS spend_per_day_last_7_days,
    CASE WHEN a.n_priced IS NULL OR a.n_priced = 0 THEN NULL
         WHEN a.n_over_28d > 0 AND a.n_over_7d > 0 THEN 'both windows'
         WHEN a.n_over_28d > 0                     THEN 'long window'
         WHEN a.n_over_7d  > 0                     THEN 'short window'
         ELSE 'neither window' END                   AS spend_breach_window,
    a.sanction_adherence_judged,
    -- ─── ORI'S PER-WINDOW RULING AT BOOK LEVEL ───
    -- A book is not one window's worth of standing. These say how many of the PRICED families have
    -- each arm wholly inside their own sanction, expressed as the fail-closed all-or-nothing booleans
    -- the total's verdict is allowed to speak from. NULL when the book has no priced family.
    IF(COALESCE(a.n_priced, 0) = 0, NULL, a.n_covers_rate_window  = a.n_priced) AS sanction_covers_rate_window,
    IF(COALESCE(a.n_priced, 0) = 0, NULL, a.n_covers_short_window = a.n_priced) AS sanction_covers_short_window,
    -- A per-arm finding is a per-family fact; a book carries the aggregate one below and nothing finer.
    CAST(NULL AS BOOL)                               AS sanction_finding_in_rate_window,
    CAST(NULL AS BOOL)                               AS sanction_finding_in_short_window,
    -- THREE-VALUED ON A TOTAL TOO. TRUE only when every priced family carries a finding; FALSE only
    -- when every priced family was measured on its covered windows and none is over; NULL for every
    -- mixture and for every book with no priced family. A withheld state may not render as a pass.
    CASE
      WHEN COALESCE(a.n_priced, 0) = 0        THEN NULL
      WHEN a.n_finding       = a.n_priced     THEN TRUE
      WHEN a.n_finding_clear = a.n_priced     THEN FALSE
      ELSE NULL
    END                                              AS sanction_breach_finding,
    CAST(NULL AS STRING)                             AS sanction_breach_finding_window,
    COALESCE(a.book_finding_published, FALSE)        AS sanction_finding_published,
    IF(s.book <> 'INVEST', NULL, COALESCE(a.n_finding, 0)) AS families_with_a_sanction_finding,
    CASE
      WHEN s.book <> 'INVEST'                          THEN NULL
      WHEN COALESCE(a.book_finding_published, FALSE)   THEN 'ORDER'
      ELSE                                                  'OPTION'
    END                                              AS verdict_action_mood,
    IF(s.book <> 'INVEST', NULL,
       IF(COALESCE(a.book_finding_published, FALSE), k.order_sentence, k.option_sentence))
                                                     AS verdict_action_sentence,
    IF(s.book <> 'INVEST', NULL,
       IF(COALESCE(a.book_finding_published, FALSE), k.option_sentence, k.order_sentence))
                                                     AS verdict_forbidden_sentence,
    -- A BOOK IS NOT IN ONE PROTECTION STATE, so these two stay NULL on a total and the counts behind
    -- them are spoken in the verdict. The two that DO belong on a total are the held decisions and
    -- the budget they cover: those add up honestly, and Harvest sums to NULL rather than 0 because no
    -- family in that book contributes one.
    CAST(NULL AS BOOL)                               AS protection_qualified,
    CAST(NULL AS BOOL)                               AS protection_enforced,
    a.stops_held                                     AS stops_the_coach_is_holding,
    a.trims_held                                     AS trims_the_coach_is_holding,
    a.stops_budget                                   AS daily_budget_the_held_stops_would_free,
    a.trims_budget                                   AS daily_budget_the_held_trims_would_free,
    -- A loss allowance is a per-family sanction; a book has no single one, and no window for one.
    CAST(NULL AS FLOAT64)                            AS loss_allowance_dollars_for_the_month,
    CAST(NULL AS FLOAT64)                            AS loss_so_far_dollars_against_that_allowance,
    CAST(NULL AS STRING)                             AS loss_allowance_window,
    -- A trajectory is a per-family fact; summing organic units across a book would invite exactly the
    -- kind of blended number this object exists to refuse.
    CAST(NULL AS INT64)                              AS organic_units_3rd_last_whole_month,
    CAST(NULL AS INT64)                              AS organic_units_2nd_last_whole_month,
    CAST(NULL AS INT64)                              AS organic_units_last_whole_month,
    CAST(NULL AS STRING)                             AS organic_units_trend,
    -- ACCOUNT-LEVEL, BELONGING TO NEITHER BOOK, AND ON THE HARVEST TOTAL ROW ONLY — the one row that
    -- carries the sentence explaining it. On both totals it read as the same money twice.
    IF(s.book = 'HARVEST', c.unattributed_spend, NULL)  AS account_ad_spend_in_neither_book,
    -- ─── THE FOUR LISTS, COMPLETE, WHATEVER THE VERDICT HAS ROOM TO SAY ───
    -- The verdicts name at most three terms and then switch to a count, so their length is bounded
    -- and Rule 3 is provable. These columns carry the whole list either way, so the bound costs the
    -- reader nothing and the claim in the header is the claim the code keeps.
    -- GATED ON THE BOOK, like every other concept on these rows. A sanction list on a Harvest total
    -- and a break-even list on an Invest total would each answer a question that book does not ask —
    -- and the Invest one would be a profit judgement on the book this design forbids judging on
    -- profit. The mapping list is the one fact both books share, so it alone rides on both.
    IF(s.book = 'INVEST',
       (SELECT STRING_AGG(FORMAT_DATE('%-d %B %Y', d), ', ' ORDER BY d) FROM UNNEST(a.stop_dates) AS d),
       NULL)                                         AS sanction_end_dates,
    IF(s.book = 'HARVEST', a.in_band_families, NULL) AS families_inside_break_even_band,
    a.unmeasured_families                            AS families_with_nothing_measured,
    IF(s.book = 'INVEST',  a.unpriced_families, NULL) AS families_with_no_approved_rate,
    CASE
      WHEN s.book = 'HARVEST' THEN CONCAT(
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'No family is being judged on money right now, which should never happen. Check the book assignments.'
          -- The NULL-money guard belongs here too: with no measured family the sum below is NULL,
          -- IF(NULL >= 0, ...) is NULL, and a CONCAT over a NULL prints as a BLANK LINE on the row
          -- that is hardest to notice is missing.
          WHEN COALESCE(a.n_measured, 0) = 0 OR a.net_profit IS NULL
            THEN CONCAT(
              'The harvest book holds ', CAST(a.n_families AS STRING),
              IF(a.n_families = 1, ' family', ' families'),
              ' with no measured profit at all, which should never happen. ',
              'Fix the product mapping before you read anything else here.')
          ELSE CONCAT(
            'The harvest book ',
            IF(a.net_profit >= 0,
               CONCAT('made ', FORMAT("$%'d", CAST(a.net_profit AS INT64))),
               CONCAT('lost ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)))),
            ' over ', a.money_window, ' across ', CAST(a.n_measured AS STRING),
            IF(a.n_measured = 1, ' family', ' families'), '. ',
            CASE
              -- SCOPED WHENEVER THE SETS DIFFER. "None of them is losing real money" over a set that
              -- excludes an unmeasured family is false comfort in miniature.
              WHEN a.n_real_losses = 0 THEN
                IF(a.n_families = a.n_measured,
                   'None is losing real money.',
                   'None of the measured ones is losing real money.')
              WHEN a.n_real_losses = 1 THEN CONCAT(
                a.worst_family, ' is the only one losing real money, at ',
                FORMAT("$%'d", CAST(-a.worst_net_profit AS INT64)), ' — fix that one first.')
              ELSE CONCAT(
                CAST(a.n_real_losses AS STRING), ' are losing real money, the biggest ',
                a.worst_family, ' at ',
                FORMAT("$%'d", CAST(-a.worst_net_profit AS INT64)), ' — start there.')
            END,
            -- THE REST OF THE BOOK, STATED RATHER THAN LEFT TO BE INFERRED. A family inside the
            -- breakeven band — EITHER SIDE of it — is neither a job nor a success, and it is the
            -- state the total used to swallow on one side and call "earning" on the other. Named
            -- here, in the same words its own row uses, with the sign kept.
            CASE
              WHEN COALESCE(a.n_in_band, 0) > 0 THEN CONCAT(
                ' ', IF(a.n_in_band <= k.list_terms_max, a.in_band_families,
                        CONCAT(CAST(a.n_in_band AS STRING), ' families')),
                IF(a.n_in_band = 1, ' is', ' are'), ' inside the break-even band, too close to ',
                'call either way.',
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
            -- to say so or the total reads complete when it is not.
            IF(a.n_families = a.n_measured, '',
               CONCAT(' ', IF(a.n_families - a.n_measured <= k.list_terms_max, a.unmeasured_families,
                              CONCAT(CAST(a.n_families - a.n_measured AS STRING), ' families')),
                      IF(a.n_families - a.n_measured = 1, ' has', ' have'),
                      ' nothing measured, so none of it is in that number. Check the product mapping.')))
        END,
        -- The one clause that stops this page presenting its spend total as the account's
        -- advertising. It branches on the MEASURED count of advertised keys, so it cannot go stale
        -- into a different lie: one placeholder, one real product, or several, each said plainly.
        IF(c.unattributed_spend > 0,
           CONCAT(' ', FORMAT("$%'d", CAST(c.unattributed_spend AS INT64)),
                  ' of account advertising on that same window — ',
                  FORMAT('%.1f', 100 - c.spend_coverage_pct),
                  '% — reached no family and is in neither book. ',
                  CASE
                    WHEN c.unattributed_products = 1 AND c.unattributed_product_key = 'Unknown' THEN
                      'Those rows carry "Unknown" where the product should be, so that money can only be attributed by campaign.'
                    WHEN c.unattributed_products = 1 THEN
                      'All of it ran against one product carrying no family name. Check the product mapping.'
                    ELSE
                      CONCAT('Those ads ran against ', CAST(c.unattributed_products AS STRING),
                             ' products carrying no family name. Check the product mapping.')
                  END),
           ''))
      ELSE
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'Nothing is on approved launch investment right now, so every family is judged on money.'
          WHEN COALESCE(a.n_priced, 0) = 0
            THEN CONCAT(
              'You have ', CAST(a.n_families AS STRING), IF(a.n_families = 1, ' family', ' families'),
              ' in the investment book and not one approved daily spend on record. ',
              'Nothing is holding them. Write those sanctions down.')
          -- WITHHOLD, NEVER SUBSTITUTE. The book rate divides the book's window spend by ONE window
          -- length. If the priced families are not on one window there is no such length, so there is
          -- no book rate and no book window phrase to quote, and picking one family's would publish
          -- that family's sanction as the book's — the defect this round was called to fix, one column
          -- over from where the last round fixed it.
          WHEN NOT COALESCE(a.rate_window_shared, FALSE)
            THEN CONCAT(
              'The ', CAST(a.n_priced AS STRING),
              IF(a.n_priced = 1, ' family', ' families'),
              ' with approved rates are not all on one rate window, so this book has no rate to ',
              'quote. Read their rows.')
          ELSE CONCAT(
            CAST(a.n_families AS STRING), IF(a.n_families = 1, ' family is', ' families are'),
            ' on approved launch investment',
            IF(a.n_families = a.n_priced, ', spending ',
               IF(a.n_priced = 1, '. The one with an approved rate is spending ',
                  CONCAT('. The ', CAST(a.n_priced AS STRING),
                         ' with approved rates are spending '))),
            FORMAT('$%.2f', a.spend_per_day),
            -- Reachable only past the rate_window_shared gate above, so this phrase is the one window
            -- every priced family is on and not a pick between rival ones.
            ' a day in total ', a.rate_window_phrase_max, ' against ',
            IF(a.daily_investment = TRUNC(a.daily_investment),
               FORMAT("$%'d", CAST(a.daily_investment AS INT64)),
               FORMAT('$%.2f', a.daily_investment)),
            ' a day approved',
            -- ─── AND THE DATES THOSE SANCTIONS RUN TO — ALL OF THEM, OR NONE ───
            -- A book cannot have one end date, so it names the span it actually has, over the same
            -- priced families the dollars are summed over, and says plainly when a sanction has no
            -- end date at all, because an open-ended one is the one that never stops spending.
            -- EVERY DATE, NOT TWO OF THEM. The old two-armed form printed first "and" last, which at
            -- exactly two dates is a complete list and at three or more is a complete-looking list
            -- with the middle terms deleted. The header claimed the verdict names every end date the
            -- book holds; this is the code that makes the claim true. The subquery unnests a local
            -- array, so it costs no scan and cannot correlate to anything outside the row.
            CASE
              WHEN a.stop_dates IS NULL OR ARRAY_LENGTH(a.stop_dates) = 0 THEN ''
              WHEN ARRAY_LENGTH(a.stop_dates) = 1 THEN
                CONCAT(', running to ', FORMAT_DATE('%-d %B %Y', a.stop_dates[SAFE_OFFSET(0)]))
              WHEN ARRAY_LENGTH(a.stop_dates) > k.list_terms_max THEN
                CONCAT(', running to ', CAST(ARRAY_LENGTH(a.stop_dates) AS STRING),
                       ' different end dates, every one of them in sanction_end_dates')
              ELSE CONCAT(', running to ',
                (SELECT STRING_AGG(FORMAT_DATE('%-d %B %Y', d), ', ' ORDER BY d)
                 FROM UNNEST(a.stop_dates) AS d
                 WHERE d < a.stop_dates[SAFE_OFFSET(ARRAY_LENGTH(a.stop_dates) - 1)]),
                ' and ',
                FORMAT_DATE('%-d %B %Y', a.stop_dates[SAFE_OFFSET(ARRAY_LENGTH(a.stop_dates) - 1)]))
            END,
            '. ',
            IF(COALESCE(a.n_no_end_date, 0) = 0, '',
               CONCAT(CAST(a.n_no_end_date AS STRING),
                      IF(a.n_no_end_date = 1,
                         ' of those sanctions has no end date, so nothing says when it stops. ',
                         ' of those sanctions have no end date, so nothing says when they stop. '))),
            IF(a.n_families = a.n_priced, '',
               CONCAT(IF(a.n_families - a.n_priced <= k.list_terms_max, a.unpriced_families,
                         CONCAT(CAST(a.n_families - a.n_priced AS STRING), ' families')),
                      IF(a.n_families - a.n_priced = 1,
                         ' has no approved rate, so none of its spending is in that figure. ',
                         ' have no approved rates, so none of their spending is in that figure. '))),
            -- WHICH ARM OF THE DUAL-WINDOW TEST THE BOOK IS OVER ON.
            -- ONE SET, NAMED AND COUNTED. n_over_28d and n_over_7d used to count every family in the
            -- book while n_priced counted only the families with both a sanction and a rate, and this
            -- clause compared the two — so with an unpriced family present "all of them" was said of
            -- a set that was never counted. Both counts are on the priced set now, and the words say
            -- which set that is whenever it is not the whole book.
            CASE
              WHEN a.n_over_28d = a.n_priced AND a.n_over_7d = a.n_priced THEN
                CONCAT('All ', IF(a.n_families = a.n_priced, 'of them', 'with a rate on record'),
                       ' are over their approved rates on both windows. ')
              WHEN a.n_over_28d = 0 AND a.n_over_7d = 0 THEN
                CONCAT('All ', IF(a.n_families = a.n_priced, 'of them', 'with a rate on record'),
                       ' are inside their approved rates on both windows. ')
              ELSE CONCAT(CAST(a.n_over_28d AS STRING), ' of the ', CAST(a.n_priced AS STRING),
                          ' are over on the long window and ',
                          CAST(a.n_over_7d AS STRING), ' on the last 7 days. ')
            END,
            -- ─── ORI'S PER-WINDOW RULING AT BOOK LEVEL ───
            -- A book convicts only when EVERY priced family carries a finding of its own — a window
            -- lying wholly inside ITS sanction and over ITS rate. Where the excess exists but no
            -- family has a window with standing, the clause states the comparison and convicts
            -- nobody. Where some do and some do not, it says how many, and does not round the mixture
            -- up into a verdict about the book.
            CASE
              -- THE BOOK NAMES THE ARM IT CONVICTS ON, and does not promote a finding won on the
              -- short window into a statement about both. The first draft of this clause said "each
              -- of those windows lies wholly inside its agreement" directly under a sentence saying
              -- both windows were over — which reads as a conviction on the long window too, three
              -- weeks before that window can carry one.
              WHEN COALESCE(a.book_finding_published, FALSE) THEN CONCAT(
                CASE
                  WHEN a.n_covers_rate_window = a.n_priced THEN
                    'Both windows lie wholly inside those agreements, so '
                  WHEN a.n_covers_short_window = a.n_priced THEN
                    CONCAT('The last ', CAST(a.short_window_days_max AS STRING),
                           ' days lie wholly inside those agreements, so ')
                  ELSE 'Each is over a window its own agreement wholly covers, so '
                END,
                IF(a.n_priced = 1, 'that forfeits its launch protection. ',
                   'they forfeit their launch protection. '),
                IF(a.n_covers_rate_window < a.n_priced AND a.n_over_28d > 0,
                   CONCAT('The ', CAST(a.rate_window_days_max AS STRING),
                          '-day figure still reaches back before them, so it stays a comparison. '),
                   ''))
              WHEN COALESCE(a.n_over_rate, 0) > 0 AND COALESCE(a.n_finding, 0) = 0 THEN
                IF(a.days_before_sanction_min IS NULL,
                   'No window yet lies wholly inside its agreement, so this is a comparison and not a finding. ',
                   CONCAT('At least ', CAST(a.days_before_sanction_min AS STRING), ' of those ',
                          CAST(a.rate_window_days_max AS STRING),
                          ' days sit before the rates were agreed, so this is a comparison and not a finding. '))
              WHEN COALESCE(a.n_over_rate, 0) > 0 THEN
                CONCAT(CAST(a.n_finding AS STRING), ' of them ',
                       IF(a.n_finding = 1, 'forfeits its', 'forfeit their'),
                       ' launch protection on a window the agreement wholly covers. ',
                       'The rest is a comparison. ')
              WHEN COALESCE(a.n_priced, 0) > 0 AND a.n_qualified = a.n_priced THEN
                CONCAT('All ', IF(a.n_families = a.n_priced, 'of them', 'with a rate on record'),
                       ' still qualify for launch protection. ')
              ELSE ''
            END,
            -- ─── WHAT THE COACH IS ACTUALLY DOING ABOUT THAT, IN DOLLARS ───
            -- Nothing withdraws protection today: V_LAUNCH_EXEMPTION hardcodes it on and the coach's
            -- gate keys on campaign presence alone. Wiring the sanction to the engine is Task 8b and
            -- Task 8b is not built, so this clause names the gap and hands the job to the only
            -- enforcer there is.
            CASE
              WHEN COALESCE(a.n_enforcement_known, 0) = 0 THEN
                'Whether the coach is protecting them could not be checked today. Check the launch exemption. '
              WHEN COALESCE(a.n_enforced, 0) > 0 AND COALESCE(a.cuts_held, 0) > 0 THEN CONCAT(
                'The coach is still protecting ', CAST(a.n_enforced AS STRING),
                ' of them: it holds ',
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
                ' worth ', FORMAT("$%'d", CAST(ROUND(a.cuts_budget) AS INT64)), ' a day. ',
                IF(COALESCE(a.trims_unsized, 0) > 0,
                   CONCAT(CAST(a.trims_unsized AS STRING),
                          IF(a.trims_unsized = 1,
                             ' of those trims has no target on record, so that figure runs low. ',
                             ' of those trims have no target on record, so that figure runs low. ')),
                   ''),
                -- RULE 5. An ORDER only where the book carries a finding; an OPTION otherwise. Same
                -- expression as verdict_action_mood on this row.
                IF(COALESCE(a.book_finding_published, FALSE), k.order_sentence, k.option_sentence))
              WHEN COALESCE(a.n_enforced, 0) > 0 THEN CONCAT(
                'The coach is still protecting ', CAST(a.n_enforced AS STRING),
                ' of them, and no budget cut is queued today. ',
                IF(COALESCE(a.book_finding_published, FALSE), k.order_sentence, k.option_sentence))
              ELSE
                'The coach is protecting none of them, so they are judged on money like every other family.'
            END,
            -- ...and the families whose money is not in the figures above.
            IF(a.n_families = a.n_measured OR COALESCE(a.n_measured, 0) = 0, '',
               CONCAT(' ', IF(a.n_families - a.n_measured <= k.list_terms_max, a.unmeasured_families,
                              CONCAT(CAST(a.n_families - a.n_measured AS STRING), ' families')),
                      IF(a.n_families - a.n_measured = 1, ' has', ' have'),
                      ' nothing measured, so the money columns leave ',
                      IF(a.n_families - a.n_measured = 1, 'it out.', 'them out.'))),
            -- Same caveat as the family rows carry, failing closed for the same reason.
            CASE
              WHEN a.rate_window_is_stale THEN
                ' That advertising has stopped arriving; nothing can be certified against those rates.'
              WHEN a.rate_window_is_stale IS NULL AND COALESCE(a.n_priced, 0) > 0 THEN
                ' Whether that advertising is still arriving could not be checked; treat those rates as uncertified.'
              ELSE ''
            END)
        END
    END                                              AS verdict
  FROM books s
  LEFT JOIN agg a ON a.book = s.book
  -- A one-row aggregate with no GROUP BY, so it returns exactly one row (all-NULL if there is
  -- nothing to measure) and cannot multiply the two TOTAL rows.
  CROSS JOIN cov c
  -- Rule 5's two moods, the same single row the family rows read them from.
  CROSS JOIN k
)
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE MORNING READ MUST NOT ARRIVE SHUFFLED. A view cannot force row order. It MUST ship the
-- key: read this object with ORDER BY sort_order and it reads top to bottom the way it is meant to —
-- Harvest before Invest, each book's TOTAL above its families, then families by net profit, biggest
-- earner first and the losses last. The tie-break on family is TOTAL, so two families losing the same
-- amount can never swap places between pulls. Unmeasured families sort last within their book: they
-- have no number, and NULLS LAST is the only honest place to put "not measured" on a money ranking.
--
-- verdict_words IS PUBLISHED SO RULE 3 IS CHECKABLE WITHOUT RE-DERIVING THE TOKENISER. A word is a
-- whitespace-separated token containing at least one letter or digit, so a bare em dash is not one.
-- The cap is a DECLARED CONSTANT of 100 (see the header) and it is asserted, not merely intended.
--
-- THE PLANNING CEILING IS REAL AND IT BINDS ON CONSUMERS, NOT ON THIS VIEW.
-- Reading the view once is healthy. WRAPPING it is not: BigQuery inlines a view at every reference
-- and this one fans out over V_UNIFIED_DAILY through three separate views, so a query that touches
-- V_TWO_BOOK_BRIEF more than about twice degrades hard and then stops planning altogether with
-- "Not enough resources for query planning - query is too complex". Measure it yourself before
-- assuming headroom (dry-run command in the header).
--   * WRITE CHECKS AS A SINGLE PASS. COUNTIF/SUM(IF(...)) over one SELECT from the view, never one
--     subquery per check. The natural several-self-reference form takes minutes or fails.
--   * ANY PAGE, CUBE MODEL OR SOP QUERY MUST READ A MATERIALISED COPY, NOT THIS VIEW. One reference
--     plans fine, so the copy is a one-liner and it is the ONLY supported way to consume this:
--       CREATE OR REPLACE TABLE `onyga-482313.OI.T_TWO_BOOK_BRIEF` AS
--       SELECT * FROM `onyga-482313.OI.V_TWO_BOOK_BRIEF`;
--     That table does not exist yet and nothing in the repo builds it. It has to land BEFORE the
--     first consumer, not after the first timeout.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
SELECT
  r.*,
  ARRAY_LENGTH(REGEXP_EXTRACT_ALL(r.verdict, r'[^\s]*[A-Za-z0-9][^\s]*')) AS verdict_words,
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
