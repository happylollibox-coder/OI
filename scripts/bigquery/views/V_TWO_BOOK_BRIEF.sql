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
-- like the same problem by ratio but cost $8 and $1,776 over the M3 window — ranked by ratio you fix
-- Bottle, ranked by dollars you fix Fresh, and Fresh is the right answer. So the Harvest losers are
-- RANKED BY DOLLARS and the worst one is named in its own verdict and in the book total; and a loss
-- smaller than the breakeven band is called noise in words, so an $8 loss can never read as a job.
--
-- THE INVEST ROWS DO NOT CARRY A PROFIT VERDICT. Months 0-3 are judged on improvement, never on
-- profitability (Ori 2026-08-19: "the question of launch products is are they improving — not are
-- they profitable — in the first 3 months"). So an Invest verdict says three things and no fourth:
-- the spend rate against what was sanctioned, whether the launch protection is still live, and the
-- organic trajectory in absolute units. Its net_profit column is still published — it is the cost of
-- the investment, and the verdict frames it as money agreed to, not as a loss to chase.
--
-- WINDOW HONESTY: the P&L columns are the settled 90-day window (period_label = 'M3'); the spend
-- rate is MONTH-TO-DATE, because a rate must be current to bind. The two are deliberately different
-- windows, so every verdict string says which one it is quoting ("over the last 90 days" vs "so far
-- this month"). Do not silently align them — a 90-day average spend rate would not bind on anything.
--
-- VERDICTS ARE PLAIN SENTENCES ON PURPOSE. No rule names, no engine internals, no bare metric codes:
-- ROAS is written as "$1.41 back for every ad dollar", the halo as "the organic sales those ads pull
-- in", the exemption as "launch protection". Ori has repeatedly filed unreadable output as a defect
-- against the page, and he is right to. If you add a branch here, read it aloud before you deploy.
--
-- ---------------------------------------------------------------------------------------------
-- 2026-08-20 — SEVEN REVIEW FINDINGS CLOSED. What changed and why, in the order they matter.
--
-- 1. A FAMILY COULD VANISH SILENTLY, AND THE TOTAL STILL READ COMPLETE (critical). The spine was
--    V_FAMILY_PNL alone, so a family present in V_BOOK_ASSIGNMENT but absent from the M3 P&L was
--    joined away — and the book total went on printing a fluent, confident sentence with no sign
--    anything was missing. The two universes are keyed differently and DO diverge: the P&L is
--    ASIN-keyed through DIM_PRODUCT, the book is campaign-keyed through V_CAMPAIGN_FAMILY_MAP, so a
--    newly declared launch whose ASINs do not yet carry a parent_name has no P&L row at all. That is
--    how every launch begins, and it is exactly the family this design exists to keep visible. The
--    spine is now a FULL OUTER JOIN of the two universes. Such a family gets a row, its money stays
--    NULL (never zero — zero would claim it was measured and found to be nothing), and its verdict
--    names what to check. SUM ignores NULLs, so it cannot move a total or open a reconciliation gap.
--
-- 2. THE MORNING READ ARRIVED SHUFFLED. No sort key at all: two consecutive pulls came back in
--    different orders with the books interleaved. A view cannot force order, but it must ship the
--    key — sort_order is now projected (Harvest before Invest, TOTAL above its families, then net
--    profit descending, unmeasured last, total tie-break on family). loss_rank is published too: it
--    was computed and thrown away, so the "fix this first" queue that the entire net-profit-leads
--    argument rests on could not be reproduced by any reader.
--
-- 3. THE PERIOD WAS NOWHERE ON THE OUTPUT. Two windows sat side by side with the window named only
--    inside the prose, so anyone scanning the grid — which is what a grid is for — compared a 90-day
--    profit against a 17-day rate with nothing on screen to stop them. period_label / period_start /
--    period_end now describe the money columns and rate_window describes the rate columns.
--
-- 4. THE COVERAGE GAP WAS INVISIBLE. On the M3 window the account spent $94,579 on advertising;
--    $85,814 reached a family; $8,765 — 9.3% — reached none, and this object said nothing about it
--    while presenting its spend total as the account's advertising. The founding complaint behind
--    this whole design is a number that lied by omission. It now rides as two columns on the TOTAL
--    rows and one clause in the harvest verdict — NEVER as a third row, because a third row_kind
--    would break the structural total_rows = 2 guarantee, this design's single best property.
--
-- 5. ONE UNCOVERED NULL PATH. A harvest family with NULL net_profit or ad_spend fell through both
--    leading branches (NULL >= 0 is NULL, NOT NULL is NULL) into a CONCAT over NULLs, which prints
--    as a BLANK LINE. Finding 1 made that path reachable for real, so it now leads the harvest CASE.
--
-- 6. TWO FORMAT DEFECTS. `phase` published the raw token 'RAMP' — the one internal code in a grid of
--    plain English — and is now launch_stage, in words. And the sanctioned rate printed through
--    FORMAT('$%.0f') inside the ONE actionable instruction on the object ("Bring spend back to $55 a
--    day to restore it"); at $27.50 that would have ordered a spend-back to $28, a wrong number in
--    the only sentence that tells Ori to do something. Whole dollars still print whole; cents survive.
--
-- 7. THE TRAJECTORY IS PROJECTED, AND THE INVEST TOTAL IS HONEST ABOUT NULLS. org_m2/org_m1/org_m0
--    and takeover_target_organic_units were read into the verdict and discarded, though they are the
--    PRIMARY evidence an Invest family is judged on. And the total counted every family in
--    n_families while SUM skipped the NULLs, so it could say "3 families spending $X against $Y"
--    where X and Y covered 2. Both sanction sums are now taken over the same priced subset, that
--    subset is counted in the sentence, and the families outside it are named.
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
  -- period_label / period_start / period_end are carried THROUGH TO THE OUTPUT on purpose. This view
  -- publishes two different windows side by side and used to name them only inside the prose, so a
  -- reader scanning the grid — which is what a grid is for — compared a 90-day profit against a
  -- 17-day rate with nothing on screen to stop them. The window is now a column.
  SELECT family, period_label, period_start, period_end,
         net_profit, total_net_roas, ads_net_roas, halo_factor, organic_pct, ad_spend
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'          -- settled 90 complete days, same window the bars are set from
),
-- The book spine. Both books are published EVERY day even when one is empty, so the shape of the
-- brief never changes under Ori and total_rows is structurally 2 rather than data-dependent. An
-- empty Invest book is a real and useful sentence ("nothing is on approved launch investment").
books AS (SELECT 'HARVEST' AS book UNION ALL SELECT 'INVEST' AS book),
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE SPEND THAT REACHES NEITHER BOOK (fix 2026-08-20). Measured on the M3 window: the account spent
-- $94,579 on advertising; $85,814 of it reached a family; $8,765 — 9.3% — reached none, all of it on
-- advertised ASINs that carry no family name. It reconciles exactly (94,579 - 8,765 = 85,814 = the
-- two book ad_spend totals summed). That money was in NEITHER book and this object said nothing
-- about it, while presenting its spend total as though it were the account's advertising. The
-- founding complaint behind this whole design is a number that lied by omission; a silent 9.3% is
-- the same defect wearing a smaller coat.
-- IT IS NOT A THIRD ROW. A third row_kind would break the structural total_rows = 2 guarantee, which
-- is this design's single best property. It rides as two COLUMNS on the TOTAL rows plus one clause
-- in the harvest verdict. Those two columns are ACCOUNT-LEVEL and IDENTICAL on both TOTAL rows —
-- this money belongs to neither book, so it cannot be apportioned to one, and it must NEVER be
-- summed across the two rows (that would double it). The acceptance assertion pins them equal.
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
-- THE SPINE IS THE UNION OF BOTH UNIVERSES, NOT THE P&L ALONE (defect fix 2026-08-20).
-- The two upstream universes are keyed differently and CAN disagree: V_FAMILY_PNL's families come
-- from V_UNIFIED_DAILY, which is ASIN-keyed through DIM_PRODUCT; V_BOOK_ASSIGNMENT's come from
-- V_CAMPAIGN_FAMILY_MAP, which is campaign-keyed. A family that has a book but no measured P&L used
-- to be joined away by the inner spine — and the book total still printed a fluent, confident,
-- complete sentence with no sign that anything was missing. That is not theoretical: a newly
-- declared INVEST family whose ASINs do not yet carry a parent_name has no M3 row at all, so the one
-- family this whole design exists to keep visible would have been invisible while spending real
-- money every day.
-- FULL OUTER JOIN fixes it. Such a family gets a row; its money columns stay NULL and are NEVER
-- filled with zero (a zero claims "measured, and it was nothing", which is a different and false
-- statement); its verdict says in words what to go and check. SUM ignores NULLs, so an unmeasured
-- family can neither move a book total nor open a gap in the reconciliation — it can only be seen.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
base AS (
  SELECT
    -- HARVEST IS THE DEFAULT (V_BOOK_ASSIGNMENT header). A family with no book row is Harvest, not a
    -- third book: COALESCE here keeps its money inside the Harvest total instead of letting a NULL
    -- book silently open a third TOTAL group and drop the dollars out of the reconciliation.
    COALESCE(bk.book, 'HARVEST')                                        AS book,
    COALESCE(p.family, bk.family)                                       AS family,
    -- FALSE = this family has a book but no measured P&L on this window. Every money column on the
    -- row is NULL, and the verdict says so rather than reading like a family that earned nothing.
    (p.family IS NOT NULL)                                              AS measured,
    -- The window behind every money column on this row. NULL on a family with no measured P&L,
    -- which is itself the correct statement: no window was measured for it.
    p.period_label, p.period_start, p.period_end,
    ROUND(p.net_profit, 0)                                              AS net_profit,
    ROUND(p.ad_spend, 0)                                                AS ad_spend,
    ROUND(p.total_net_roas, 2)                                          AS total_net_roas,
    ROUND(p.ads_net_roas, 2)                                            AS ads_net_roas,
    ROUND(p.halo_factor, 2)                                             AS halo_factor,
    -- INVEST families are bar-exempt (V_FAMILY_BAR.bar_exempt): they are governed by budget and
    -- trajectory, not by a keyword bar. Printing their computed bar on the brief would imply a test
    -- that is not being applied, so it is blanked here rather than shown and explained away.
    IF(COALESCE(bk.book, 'HARVEST') = 'INVEST', NULL, ROUND(b.keyword_bar, 2)) AS keyword_bar,
    p.organic_pct,
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
    i.exemption_live, i.ceiling_used_pct, i.days_left,
    i.org_m2, i.org_m1, i.org_m0, i.takeover_target_organic_units,
    (p.net_profit < 0 AND -p.net_profit > k.breakeven_band * p.ad_spend) AS real_loss,
    (COALESCE(p.halo_factor, 0) >= k.wide_halo)                         AS wide_halo
  FROM pnl p
  FULL OUTER JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` bk ON bk.family = p.family
  LEFT JOIN `onyga-482313.OI.V_FAMILY_BAR`    b ON b.family = COALESCE(p.family, bk.family)
  LEFT JOIN `onyga-482313.OI.V_INVEST_STATUS` i ON i.family = COALESCE(p.family, bk.family)
  -- k LAST, and never before the FULL OUTER JOIN: cross-joined earlier, the outer join would null
  -- out the tunables on exactly the book-only rows this fix exists to create.
  CROSS JOIN k
),
-- DOLLARS, NOT RATIOS, DECIDE THE QUEUE. Ordering is TOTAL (family breaks the tie) so the "fix this
-- first" sentence can never coin-flip between two families that happen to lose the same amount.
-- loss_rank IS PUBLISHED (fix 2026-08-20). It was computed here and thrown away, so the "fix this
-- first" queue that the whole net-profit-leads argument rests on could not be reproduced by any
-- reader of the output — only re-derived. It ranks the HARVEST families losing REAL money (a loss
-- past the breakeven band), 1 = worst, NULL for everyone else, and it is the same total ordering the
-- verdict quotes, so the column and the sentence can never disagree.
lr AS (
  SELECT
    family,
    ROW_NUMBER()  OVER (ORDER BY net_profit ASC, family ASC) AS loss_rank,
    FIRST_VALUE(family)     OVER (ORDER BY net_profit ASC, family ASC) AS worst_family,
    FIRST_VALUE(net_profit) OVER (ORDER BY net_profit ASC, family ASC) AS worst_net_profit
  FROM base
  WHERE book = 'HARVEST' AND real_loss
),
fam AS (
  SELECT
    b.book,
    'FAMILY'                AS row_kind,
    b.family,
    -- WHICH WINDOW THE MONEY COLUMNS BELONG TO — on the row, not only in the prose.
    b.period_label,
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
    lr.loss_rank,
    -- WHICH WINDOW THE RATE COLUMNS BELOW BELONG TO. Deliberately a different, shorter window from
    -- the one above: a spend rate has to be current to bind on anything. Both are now on the row, so
    -- the mismatch is visible to someone reading the grid rather than the sentences.
    IF(b.mtd_spend_per_day IS NULL, NULL,
       CONCAT('month to date, from ',
              FORMAT_DATE('%-d %B %Y', DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)))) AS rate_window,
    -- 'RAMP' used to be published raw here — the one bare internal token in a grid of plain English.
    -- Same meaning, said the way the verdict already says it.
    CASE b.phase WHEN 'RAMP'  THEN 'in the early stretch'
                 WHEN 'PROOF' THEN 'past the early stretch'
                 ELSE NULL END AS launch_stage,
    b.launch_age_months,
    -- The BINDING sanction trio leads. ceiling_used_pct trails it as the catastrophe backstop it is
    -- (V_INVEST_STATUS header: a loss ceiling on a product that nearly covers its costs never fires).
    b.daily_investment,
    b.mtd_spend_per_day,
    b.spend_rate_ratio,
    b.exemption_live,
    b.ceiling_used_pct,
    b.days_left,
    -- THE TRAJECTORY, PUBLISHED. Absolute organic units over the last three complete months, oldest
    -- first, plus the level that would mean the family can stand on its own. This is the PRIMARY
    -- evidence an Invest family is judged on; it was read into the verdict and then discarded, so
    -- anyone charting the ramp or sorting on it had to re-derive it from upstream.
    b.org_m2,
    b.org_m1,
    b.org_m0,
    b.takeover_target_organic_units,
    -- Account-level coverage lives on the TOTAL rows only; a family row has no share of it.
    CAST(NULL AS FLOAT64)   AS unattributed_spend,
    CAST(NULL AS FLOAT64)   AS spend_coverage_pct,
    CASE
      -- ───────── INVEST: sanction adherence + trajectory. Never a profit verdict. ─────────
      WHEN b.book = 'INVEST' THEN CONCAT(
        CASE
          WHEN b.daily_investment IS NULL THEN CONCAT(
            b.family, ' is in the investment book, but there is no approved daily spend on record for it, ',
            'so nothing is holding it. Write the sanction down or move it back to being judged on money.')
          WHEN b.spend_breached THEN CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month against the ',
            b.daily_investment_text, ' a day you approved — about ', FORMAT('%.1f', b.spend_rate_ratio),
            ' times the agreed rate, so it has lost its launch protection and is now judged on money like every ',
            'other family. Bring spend back to ', b.daily_investment_text, ' a day to restore it.')
          WHEN b.exemption_live THEN CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month, inside the ',
            b.daily_investment_text, ' a day you approved, so its launch protection holds until ',
            FORMAT_DATE('%-d %B %Y', b.stop_date), '.')
          WHEN COALESCE(b.days_left, -1) < 0 THEN CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month, inside the ',
            b.daily_investment_text, ' a day you approved, but the agreed end date has passed, ',
            'so it is back to being judged on money like every other family.')
          ELSE CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month, inside the ',
            b.daily_investment_text, ' a day you approved, but it has already used up the losses you ',
            'allowed it this month, so its launch protection has stopped.')
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
        CASE
          WHEN b.launch_age_months IS NULL THEN ''
          WHEN b.phase = 'RAMP' THEN CONCAT(
            ' It is ', CAST(b.launch_age_months AS STRING), IF(b.launch_age_months = 1, ' month', ' months'),
            ' old, so what matters is whether it is improving, not whether it is profitable yet.')
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
        IF(b.measured, '',
           CONCAT(' None of the money columns are filled in for it, because nothing it sells is being ',
                  'counted under this family yet — check that its products carry the family name.')))

      -- ───────── HARVEST: dollars lead, the ratio explains them. ─────────
      -- NULL FIRST. A harvest family with no measured profit fell through every branch below (NULL >= 0
      -- is NULL, NOT NULL is NULL) into a CONCAT over NULLs, which prints as a BLANK LINE on the
      -- morning read — the one place in this file a NULL had no written fallback.
      WHEN b.net_profit IS NULL OR b.ad_spend IS NULL THEN CONCAT(
        b.family, ' is being judged on money, but there is nothing measured for it over the last 90 days — ',
        'no sales, no ad spend, no profit. That is a mapping gap, not a quiet quarter: nothing it sells ',
        'is being counted under this family name, so it is missing from the harvest total above. ',
        'Check its products before you trust that total.')

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
        IF(lr.loss_rank = 1,
           ' — the biggest loss in the harvest book, so this is the one to fix first. ',
           CONCAT(' — a smaller loss than ', lr.worst_family, "'s ",
                  FORMAT("$%'d", CAST(-lr.worst_net_profit AS INT64)), ', so it waits behind that one. ')),
        'It brings back ', FORMAT('$%.2f', b.total_net_roas),
        ' for every ad dollar even after counting the organic sales those ads pull in, against ',
        FORMAT('$%.2f', b.ads_net_roas), ' counting ads alone.')
    END                     AS verdict
  FROM base b
  LEFT JOIN lr ON lr.family = b.family
),
-- One aggregate per book. NOTHING here groups across books, and there is no second aggregation
-- above this: that absence IS the no-grand-total guarantee.
agg AS (
  SELECT
    book,
    COUNT(*)                                       AS n_families,
    COUNTIF(measured)                              AS n_measured,
    -- Every measured family shares one window, so MIN/MAX are the window itself; NULL when the book
    -- measured nothing, which is the honest answer rather than a borrowed date.
    MAX(period_label)                              AS period_label,
    MIN(period_start)                              AS period_start,
    MAX(period_end)                                AS period_end,
    SUM(net_profit)                                AS net_profit,
    SUM(ad_spend)                                  AS ad_spend,
    -- THE SANCTION SUMS COVER EXACTLY THE FAMILIES THEY CAN COVER (defect fix 2026-08-20). An INVEST
    -- family with no V_INVEST_STATUS row, or no approved rate written down, contributes NULL to both
    -- sums — so the old sentence said "3 families spending $X against $Y" while X and Y described 2.
    -- Both sides are now taken over the SAME priced subset, the count of that subset is published,
    -- and the families outside it are named in words instead of silently thinned out of the money.
    COUNTIF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL) AS n_priced,
    SUM(IF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL, daily_investment,   NULL)) AS daily_investment,
    SUM(IF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL, mtd_spend_per_day, NULL)) AS mtd_spend_per_day,
    COUNTIF(real_loss)                             AS n_real_losses,
    COUNTIF(COALESCE(spend_breached, FALSE))       AS n_over_rate,
    -- Named, not just counted: "one family is missing" sends nobody anywhere. Ordered by family so
    -- the sentence is byte-identical on two consecutive pulls.
    STRING_AGG(IF(measured, NULL, family), ' and ' ORDER BY family)     AS unmeasured_families,
    STRING_AGG(IF(daily_investment IS NOT NULL AND mtd_spend_per_day IS NOT NULL, NULL, family),
               ' and ' ORDER BY family)                                 AS unpriced_families
  FROM base
  GROUP BY book
),
-- The worst Harvest loser, as a ONE-ROW aggregate rather than a scalar subquery. An aggregate with
-- no GROUP BY always returns exactly one row (all-NULL when no family is losing real money), so it
-- can be CROSS JOINed safely. Written this way because BigQuery refused to plan the scalar-subquery
-- form inside the totals CASE ("Correlated subqueries that reference other tables are not
-- supported unless they can be de-correlated") — same tie-break as lr, so the two always agree.
worst AS (
  SELECT
    ARRAY_AGG(family     ORDER BY net_profit ASC, family ASC LIMIT 1)[SAFE_OFFSET(0)] AS worst_family,
    ARRAY_AGG(net_profit ORDER BY net_profit ASC, family ASC LIMIT 1)[SAFE_OFFSET(0)] AS worst_net_profit
  FROM base
  WHERE book = 'HARVEST' AND real_loss
),
tot AS (
  SELECT
    s.book,
    'TOTAL'                                          AS row_kind,
    CAST(NULL AS STRING)                             AS family,
    a.period_label,
    a.period_start,
    a.period_end,
    IFNULL(a.net_profit, 0)                          AS net_profit,
    IFNULL(a.ad_spend, 0)                            AS ad_spend,
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
    ROUND(SAFE_DIVIDE(a.mtd_spend_per_day, NULLIF(a.daily_investment, 0)), 2) AS spend_rate_ratio,
    CAST(NULL AS BOOL)                               AS exemption_live,
    CAST(NULL AS FLOAT64)                            AS ceiling_used_pct,
    CAST(NULL AS INT64)                              AS days_left,
    -- A trajectory is a per-family fact; summing organic units across a book would invite exactly the
    -- kind of blended number this object exists to refuse.
    CAST(NULL AS INT64)                              AS org_m2,
    CAST(NULL AS INT64)                              AS org_m1,
    CAST(NULL AS INT64)                              AS org_m0,
    CAST(NULL AS INT64)                              AS takeover_target_organic_units,
    -- ACCOUNT-LEVEL, IDENTICAL ON BOTH TOTAL ROWS, BELONGING TO NEITHER BOOK. Never add them up.
    c.unattributed_spend,
    c.spend_coverage_pct,
    CASE
      WHEN s.book = 'HARVEST' THEN CONCAT(
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'No family is being judged on money right now, which should never happen — check the book assignments.'
          WHEN COALESCE(a.n_measured, 0) = 0
            THEN CONCAT(
              'The harvest book holds ', CAST(a.n_families AS STRING),
              IF(a.n_families = 1, ' family', ' families'),
              ', and not one of them has anything measured over the last 90 days, which should never ',
              'happen — nothing they sell is being counted under their family names. Fix the product ',
              'mapping before you read anything else on this page.')
          ELSE CONCAT(
            'The harvest book ',
            IF(a.net_profit >= 0,
               CONCAT('made ', FORMAT("$%'d", CAST(a.net_profit AS INT64))),
               CONCAT('lost ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)))),
            ' over the last 90 days across ', CAST(a.n_measured AS STRING),
            IF(a.n_measured = 1, ' family', ' families'), '. ',
            CASE
              WHEN a.n_real_losses = 0 THEN 'None of them is losing real money.'
              WHEN a.n_real_losses = 1 THEN CONCAT(
                w.worst_family, ' is the only one losing real money, at ',
                FORMAT("$%'d", CAST(-w.worst_net_profit AS INT64)),
                ' — fix that one and the rest is working.')
              ELSE CONCAT(
                CAST(a.n_real_losses AS STRING), ' of them are losing real money, and the biggest is ',
                w.worst_family, ' at ',
                FORMAT("$%'d", CAST(-w.worst_net_profit AS INT64)),
                ' — start there, because that is where the dollars are.')
            END,
            -- A family in this book with nothing measured is not in that total, and the sentence has
            -- to say so out loud or the total reads complete when it is not.
            IF(a.n_families = a.n_measured, '',
               CONCAT(' ', a.unmeasured_families,
                      IF(a.n_families - a.n_measured = 1, ' is also in this book but has', ' are also in this book but have'),
                      ' nothing measured at all, so none of it is in that number — check the product mapping.')))
        END,
        -- The one clause that stops this page presenting its spend total as the account's advertising.
        IF(c.unattributed_spend > 0,
           CONCAT(' Separately, ', FORMAT("$%'d", CAST(c.unattributed_spend AS INT64)),
                  ' of advertising over the same 90 days — ', FORMAT('%.1f', 100 - c.spend_coverage_pct),
                  '% of everything the account spent — reached no family at all and is in neither book. ',
                  'Those ads ran against products that are not carrying a family name, so none of the ',
                  'money on this page accounts for it.'),
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
            CASE
              WHEN a.n_over_rate = 0          THEN CONCAT('All ', IF(a.n_families = a.n_priced, 'of them', 'of those with a rate on record'),
                                                          ' are inside their agreed rate and still protected. ')
              WHEN a.n_over_rate = a.n_priced THEN CONCAT('Every one ', IF(a.n_families = a.n_priced, 'of them', 'of those with a rate on record'),
                                                          ' is over its agreed rate, so none is protected right now. ')
              ELSE CONCAT(CAST(a.n_over_rate AS STRING), ' ', IF(a.n_families = a.n_priced, 'of them', 'of those with a rate on record'),
                          ' are over their agreed rate and no longer protected. ')
            END,
            CASE
              WHEN a.n_measured = 0 THEN CONCAT(
                'Nothing they sell is being counted under their family names yet, so there is no ',
                'measured cost for them over the last 90 days — check the product mapping.')
              WHEN a.net_profit < 0 THEN CONCAT(
                'The ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)),
                ' they cost over the last 90 days is money you agreed to spend while they build, ',
                'not a loss to chase.')
              ELSE CONCAT(
                'They also made ', FORMAT("$%'d", CAST(a.net_profit AS INT64)),
                ' over the last 90 days while building, ahead of what you agreed to spend on them.')
            END,
            IF(a.n_families = a.n_measured, '',
               CONCAT(' ', a.unmeasured_families,
                      IF(a.n_families - a.n_measured = 1, ' has', ' have'),
                      ' nothing measured at all, so none of that cost includes ',
                      IF(a.n_families - a.n_measured = 1, 'it.', 'them.'))))
        END
    END                                              AS verdict
  FROM books s
  LEFT JOIN agg a ON a.book = s.book
  -- Both are one-row aggregates with no GROUP BY, so each returns exactly one row (all-NULL if there
  -- is nothing to measure) and neither can multiply the two TOTAL rows.
  CROSS JOIN worst w
  CROSS JOIN cov   c
)
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- THE MORNING READ MUST NOT ARRIVE SHUFFLED (fix 2026-08-20). A view cannot guarantee row order and
-- this one shipped no sort key at all, so two consecutive pulls came back in different orders with
-- the two books interleaved. It cannot force the order, but it MUST ship the key: read this object
-- with ORDER BY sort_order and it reads top to bottom the way it is meant to — Harvest before
-- Invest, each book's TOTAL above its families, then families by net profit, biggest earner first
-- and the losses last. The tie-break on family is TOTAL, so two families losing the same amount can
-- never swap places between pulls. Unmeasured families sort last within their book: they have no
-- number, and NULLS LAST is the only honest place to put "not measured" on a money ranking.
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
