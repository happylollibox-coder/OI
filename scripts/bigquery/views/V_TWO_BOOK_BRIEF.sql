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
  SELECT family, net_profit, total_net_roas, ads_net_roas, halo_factor, organic_pct, ad_spend
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'          -- settled 90 complete days, same window the bars are set from
),
-- The book spine. Both books are published EVERY day even when one is empty, so the shape of the
-- brief never changes under Ori and total_rows is structurally 2 rather than data-dependent. An
-- empty Invest book is a real and useful sentence ("nothing is on approved launch investment").
books AS (SELECT 'HARVEST' AS book UNION ALL SELECT 'INVEST' AS book),
base AS (
  SELECT
    -- HARVEST IS THE DEFAULT (V_BOOK_ASSIGNMENT header). A family with no book row is Harvest, not a
    -- third book: COALESCE here keeps its money inside the Harvest total instead of letting a NULL
    -- book silently open a third TOTAL group and drop the dollars out of the reconciliation.
    COALESCE(bk.book, 'HARVEST')                                        AS book,
    p.family,
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
    i.exemption_live, i.ceiling_used_pct, i.days_left,
    i.org_m2, i.org_m1, i.org_m0, i.takeover_target_organic_units,
    (p.net_profit < 0 AND -p.net_profit > k.breakeven_band * p.ad_spend) AS real_loss,
    (COALESCE(p.halo_factor, 0) >= k.wide_halo)                         AS wide_halo
  FROM pnl p
  CROSS JOIN k
  LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` bk ON bk.family = p.family
  LEFT JOIN `onyga-482313.OI.V_FAMILY_BAR`      b  ON b.family  = p.family
  LEFT JOIN `onyga-482313.OI.V_INVEST_STATUS`   i  ON i.family  = p.family
),
-- DOLLARS, NOT RATIOS, DECIDE THE QUEUE. Ordering is TOTAL (family breaks the tie) so the "fix this
-- first" sentence can never coin-flip between two families that happen to lose the same amount.
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
    b.net_profit,
    b.ad_spend,
    b.total_net_roas,
    b.ads_net_roas,
    b.halo_factor,
    b.keyword_bar,
    b.organic_pct,
    b.phase,
    -- The BINDING sanction trio leads. ceiling_used_pct trails it as the catastrophe backstop it is
    -- (V_INVEST_STATUS header: a loss ceiling on a product that nearly covers its costs never fires).
    b.daily_investment,
    b.mtd_spend_per_day,
    b.spend_rate_ratio,
    b.exemption_live,
    b.ceiling_used_pct,
    b.days_left,
    CASE
      -- ───────── INVEST: sanction adherence + trajectory. Never a profit verdict. ─────────
      WHEN b.book = 'INVEST' THEN CONCAT(
        CASE
          WHEN b.daily_investment IS NULL THEN CONCAT(
            b.family, ' is in the investment book, but there is no approved daily spend on record for it, ',
            'so nothing is holding it. Write the sanction down or move it back to being judged on money.')
          WHEN b.spend_breached THEN CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month against the ',
            FORMAT('$%.0f', b.daily_investment), ' a day you approved — about ', FORMAT('%.1f', b.spend_rate_ratio),
            ' times the agreed rate, so it has lost its launch protection and is now judged on money like every ',
            'other family. Bring spend back to ', FORMAT('$%.0f', b.daily_investment), ' a day to restore it.')
          WHEN b.exemption_live THEN CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month, inside the ',
            FORMAT('$%.0f', b.daily_investment), ' a day you approved, so its launch protection holds until ',
            FORMAT_DATE('%-d %B %Y', b.stop_date), '.')
          WHEN COALESCE(b.days_left, -1) < 0 THEN CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month, inside the ',
            FORMAT('$%.0f', b.daily_investment), ' a day you approved, but the agreed end date has passed, ',
            'so it is back to being judged on money like every other family.')
          ELSE CONCAT(
            b.family, ' is spending ', FORMAT('$%.2f', b.mtd_spend_per_day), ' a day so far this month, inside the ',
            FORMAT('$%.0f', b.daily_investment), ' a day you approved, but it has already used up the losses you ',
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
        END)

      -- ───────── HARVEST: dollars lead, the ratio explains them. ─────────
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
    SUM(net_profit)                                AS net_profit,
    SUM(ad_spend)                                  AS ad_spend,
    SUM(daily_investment)                          AS daily_investment,
    SUM(mtd_spend_per_day)                         AS mtd_spend_per_day,
    COUNTIF(real_loss)                             AS n_real_losses,
    COUNTIF(COALESCE(spend_breached, FALSE))       AS n_over_rate
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
    IFNULL(a.net_profit, 0)                          AS net_profit,
    IFNULL(a.ad_spend, 0)                            AS ad_spend,
    CAST(NULL AS FLOAT64)                            AS total_net_roas,
    CAST(NULL AS FLOAT64)                            AS ads_net_roas,
    CAST(NULL AS FLOAT64)                            AS halo_factor,
    CAST(NULL AS FLOAT64)                            AS keyword_bar,
    CAST(NULL AS FLOAT64)                            AS organic_pct,
    CAST(NULL AS STRING)                             AS phase,
    a.daily_investment,
    a.mtd_spend_per_day,
    ROUND(SAFE_DIVIDE(a.mtd_spend_per_day, NULLIF(a.daily_investment, 0)), 2) AS spend_rate_ratio,
    CAST(NULL AS BOOL)                               AS exemption_live,
    CAST(NULL AS FLOAT64)                            AS ceiling_used_pct,
    CAST(NULL AS INT64)                              AS days_left,
    CASE
      WHEN s.book = 'HARVEST' THEN
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'No family is being judged on money right now, which should never happen — check the book assignments.'
          ELSE CONCAT(
            'The harvest book ',
            IF(a.net_profit >= 0,
               CONCAT('made ', FORMAT("$%'d", CAST(a.net_profit AS INT64))),
               CONCAT('lost ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)))),
            ' over the last 90 days across ', CAST(a.n_families AS STRING),
            IF(a.n_families = 1, ' family', ' families'), '. ',
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
            END)
        END
      ELSE
        CASE
          WHEN COALESCE(a.n_families, 0) = 0
            THEN 'Nothing is on approved launch investment right now, so every family is being judged on money.'
          ELSE CONCAT(
            'You have ', CAST(a.n_families AS STRING), IF(a.n_families = 1, ' family', ' families'),
            ' on approved launch investment, spending ', FORMAT('$%.2f', a.mtd_spend_per_day),
            ' a day in total so far this month against the ', FORMAT('$%.0f', a.daily_investment),
            ' a day you approved. ',
            CASE
              WHEN a.n_over_rate = 0            THEN 'All of them are inside their agreed rate and still protected. '
              WHEN a.n_over_rate = a.n_families THEN 'Every one of them is over its agreed rate, so none is protected right now. '
              ELSE CONCAT(CAST(a.n_over_rate AS STRING), ' of them are over their agreed rate and no longer protected. ')
            END,
            IF(a.net_profit < 0,
               CONCAT('The ', FORMAT("$%'d", CAST(-a.net_profit AS INT64)),
                      ' they cost over the last 90 days is money you agreed to spend while they build, ',
                      'not a loss to chase.'),
               CONCAT('They also made ', FORMAT("$%'d", CAST(a.net_profit AS INT64)),
                      ' over the last 90 days while building, ahead of what you agreed to spend on them.')))
        END
    END                                              AS verdict
  FROM books s
  LEFT JOIN agg a ON a.book = s.book
  CROSS JOIN worst w
)
SELECT * FROM fam
UNION ALL
SELECT * FROM tot;
