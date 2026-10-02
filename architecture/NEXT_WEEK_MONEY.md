# Next Week's Money — SOP

**Spec:** `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` (rulings P-1..P-14)
**Plan:** `docs/superpowers/plans/2026-08-23-next-week-money.md` (Tasks 0..8)
**Status:** Task 0 shipped (v27.130), repaired (v27.131, v27.132); Task 1, the judgement layer, shipped (v27.133). This SOP grows one section per task; Task 8 completes it.

> One engine plans next week's not-good money for the working families (HARVEST book: Bottle,
> Lollibox, LolliME, Fresh). Good keywords are never cut and never re-priced (P-4). The not-good
> ones compete for numbered, dollar-sized seats inside an allowance that is a declared share of
> what the good side actually spent in the window; the rest queue at zero.

---

## 1. The config layer (Task 0, v27.130 · repaired v27.131 and v27.132)

Two objects, and nothing else in the plan may write a window, a share, a ramp or an order floor
as a literal.

| object | file | what it answers |
|---|---|---|
| `DE_PLAN_CONFIG` | `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql` | given a calendar state, how long is the window, what share of the good side does the not-good side get, over how many windows does the allowance ramp, how many orders make a keyword good, and which plan is live |
| `FN_PLAN_CALENDAR_STATE(d DATE)` | `scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql` | which calendar state a date is in |
| acceptance | `scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql` | every row must read `PASS` |

### How a reader uses them

Always join, never hardcode. The pattern every plan object follows:

```sql
SELECT c.window_days, c.allowance_share, c.live_plan, c.ramp_steps, c.min_orders
FROM `onyga-482313.OI.DE_PLAN_CONFIG` c
WHERE c.is_active
  AND c.calendar_state = `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'))
QUALIFY ROW_NUMBER() OVER (PARTITION BY c.calendar_state ORDER BY c.updated_at DESC) = 1
```

The calendar is read on **New York** (it is a US retail calendar); the ads facts the window then
selects are read on **Los Angeles**.

**THE WINDOW, EXACTLY (P-10 + the P-14a fence).** `window_days` complete days ending at

```
window_to = LEAST(watermark - 1, CURRENT_DATE('America/Los_Angeles') - 2)
watermark = LEAST(MAX(date), FN_ADS_ANCHOR_CAP())   over FACT_AMAZON_ADS
```

The filling day never enters a window (that is `watermark - 1`), and neither does a day younger
than two (that is the fence). The fence exists because `FN_ADS_ANCHOR_CAP()` advances to the
current Los Angeles date once the LA hour reaches 22, so `watermark - 1` alone can still be an
age-1 day — and the published curve puts an age-1 day's SPEND materially short of final, which
understates the pot, the allowance derived from it, and every seat cost quoted at the repaired
price, all in the same direction. Read the curve, never a number from this page:

```sql
SELECT channel, age_days, spend_pct_of_final_median, spend_pct_worst,
       sales_pct_of_final_median, sales_pct_worst
FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE`
WHERE age_days <= 3 ORDER BY channel, age_days
```

Before 22:00 LA the two terms of the `LEAST` are equal and the fence costs nothing; after it, the
fence gives up one day rather than judge money on a day the warehouse has not finished writing.

**v27.132 defect, now fixed.** `tools/build_reprice_bulksheet.py` — the only live producer of
window verdicts — read a bare `MAX(date)` and no fence, so its window ended on an age-1 day *all
day*, not only after 22:00. Measured at 10:15 LA on 2026-08-23: `MAX(date)` was `2026-08-23`
while `FN_ADS_ANCHOR_CAP()` was `2026-08-22`. It now reads the house watermark and the fence, and
its own window ends where this section says it does. Check it any time:

```sql
SELECT (SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`) AS raw_max,
       `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()                     AS anchor_cap,
       CURRENT_DATE('America/Los_Angeles')                       AS la_today
```

### The settings, and who may change them

`window_days`, `allowance_share`, `ramp_steps`, `min_orders` and `live_plan` are **declared
settings**, not measurements. The seeded values are P-13 and P-3: 7 complete days off-peak and 3
in BOOST and PEAK; a 0.20 share off-peak and in PEAK and 0.50 in BOOST; three ramp steps (P-8's
one third of the gap per window — `ramp_steps` and "ramp thirds" are the same setting); two
orders in the window; plan `B` live with plan `A` written nightly in shadow (P-9).

**Ori changes a setting without a deploy.** **Retire first, insert second** — in that order, and
retire *whatever is active for the state*, not only the seed:

```sql
UPDATE `onyga-482313.OI.DE_PLAN_CONFIG`
SET is_active = FALSE
WHERE calendar_state = 'BOOST' AND is_active;

INSERT INTO `onyga-482313.OI.DE_PLAN_CONFIG`
  (calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   is_active, description, updated_at, updated_by)
VALUES ('BOOST', 3, 0.35, 'B', 3, 2, TRUE, 'why this changed, in words', CURRENT_TIMESTAMP(), 'ori');
```

Written that way the recipe is **idempotent**: run it ten times and the state still holds exactly
one active row, with every superseded row kept for the audit trail. The v27.130 recipe retired
only `updated_by = 'plan_seed'`, so the *second* change to a state found no seed row left to
retire, left the first hand row active alongside the new one, and turned `C01` permanently red.

Never edit the DDL file to change a live setting.

**THE DEPLOY GUARANTEE, STATED EXACTLY (v27.132).** Re-running `DE_PLAN_CONFIG.sql` can never
change the **settings** of any state, *however* you changed them — a new active row, or an
`UPDATE` in place — and can never re-activate a state you retired. All it can do is refresh the
**description** of a seed row whose settings still equal the declared seed to the value.

That guarantee took two goes, and the first two shapes both moved money:

* **v27.130** deleted and re-inserted the seed rows **active, with a fresh `CURRENT_TIMESTAMP()`**,
  so a hand-set share survived the delete but stopped being the row anyone read.
* **v27.131** keyed the guard on `updated_by`, which only protects a change that arrives as a NEW
  ROW. An `UPDATE ... SET allowance_share = 0.33 WHERE calendar_state = 'PEAK' AND is_active`
  leaves `updated_by = 'plan_seed'` on the row, so the delete still fired and the seed came back —
  0.33 reverted to 0.20, silently. The same clause also **re-activated a state retired without a
  replacement**. Both replayed end to end on a `TMP_` copy before the repair.
* **v27.132** compares the **values**: the seed is declared once into a temp table, the `DELETE`
  fires only on a row that is still active *and* still equal, setting for setting, to that
  declaration, and the `INSERT` writes only a state with no row at all.

`C06` and `C07` are the alarms for the v27.130 shape. **`C09` is the alarm for the v27.131
shape**: it goes red the moment an active `plan_seed` row's settings stop matching the DDL. An
in-place edit now *survives*, but it leaves the row wearing the seed's label, so C09 asks you to
convert it with the retire-then-insert recipe above. That recipe remains the supported one.

Whether 0.50 is the right BOOST share is an open learning question — the backtest (plan Task 6)
answers it per state on evidence, and until it does the seed stands. `V_PLAN_SCORECARD` (§6) grades
plan A against plan B and the last-day test; it does not grade the share.

### The other authority on `window_days`, and which one wins

`DE_PLAN_CONFIG` is **not** the only place in the house that answers "how many days is the judged
window". `V_PEAK_WINDOW_RULE` over `DE_PEAK_WINDOW_OVERRIDE` carries Ori's own rule — *in a peak
judge on 3 unless last year's same occurrence proved 7 is better, and the burden of proof is on
the slower window* — with a per-occurrence-type evidence record and a **re-measure clock**. Both
resolve the same number today. A re-measure that grants a 7 would put them in disagreement on the
same doctrine on the same day.

P-11 (one engine) settles it: for the plan, **`DE_PLAN_CONFIG` wins**. But the disagreement must
never be silent, so acceptance **`C08`** compares the plan's window for today's state against
`V_PEAK_WINDOW_RULE.w_days` and goes red when they part. Red there is a **ruling to make**, not a
view to patch. Read both, and the override table's clocks, before ruling:

```sql
SELECT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York')) AS plan_state,
       (SELECT window_days FROM `onyga-482313.OI.DE_PLAN_CONFIG`
        WHERE is_active AND calendar_state =
              `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'))
        QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1)
         AS plan_window_days,
       r.occurrence_type, r.w_days AS house_w_days, r.w_days_source
FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE` r;

SELECT occurrence_type, w_days, evidence_verdict, remeasure_after
FROM `onyga-482313.OI.DE_PEAK_WINDOW_OVERRIDE`
WHERE is_active ORDER BY remeasure_after;
```

### The calendar states, and why PEAK wins

`FN_PLAN_CALENDAR_STATE` reads the **live** `DIM_US_HOLIDAYS` (categories `gift_season`,
`prime_event`, `back_to_school`, `seasonal`, rows carrying a `boost_start`) — never a date
literal, and never the repo seed, which is stale.

- **PEAK** — `peak_start` through `COALESCE(cooldown_end, holiday_date + 3)`.
- **BOOST** — `boost_start` through the day before `COALESCE(peak_start, holiday_date)`.
- **OFF_PEAK** — anything else. The function never returns `NULL`.

The seasons on the live calendar **overlap**: a single date routinely sits inside one season's
peak and another season's run-up at the same time. The plan needs one window and one share per
date, so precedence is declared: **a peak anywhere beats a run-up everywhere**, because the
tighter window is the safer read while real money is moving. The acceptance asserts the
precedence on a live overlap date rather than trusting this paragraph.

**A consequence that is bigger than Q4, and no ruling has been made about it.** Under this
precedence PEAK is not the exception — on the live calendar it is the *majority state of the
year*, and OFF-PEAK, the doctrine's normal case (the 7-day window of P-13), applies on a minority
of days. That matters most for P-14: the 3-day window is the one most exposed to the settle
defect, so the correction and the asymmetric guard end up carrying most of the year rather than
a few peak weeks. Whether that is what Ori wants is a **ruling**, not a build detail — see the
open question at the end of this section.

**A THIRD DERIVATION EXISTED AND DISAGREED ON THE BLACK-FRIDAY RUN-UP (v27.132, fixed).**
`tools/build_reprice_bulksheet.py` did not call this function: it derived the state itself from
`V_PEAK_WINDOW_RULE`'s **single owning occurrence** (the house resolver gives the date to the
*earliest `boost_start`*), comparing on the Los Angeles date. That is a different precedence —
"the earliest season owns the date" against "a peak anywhere wins" — and the difference is not
academic. Sweep both across a year and they agree on most days and part on the stretch where
Halloween's peak opens inside Christmas's run-up: the book said **BOOST** (`allowance_share`
0.50) where the plan's authority says **PEAK** (0.20), a 2.5x difference in money handed to the
not-good side. Nothing was visibly wrong only because BOOST and PEAK happen to declare the same
`window_days` today. The book now calls `FN_PLAN_CALENDAR_STATE` (P-11, one engine); the old rule
survives in Python as `legacy_calendar_state()` **only to print a WARNING when the two disagree**,
so the divergence is a line on the build, never a silent switch. Re-derive the sweep rather than
trusting this paragraph:

```sql
WITH d AS (SELECT dt FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2026-01-01', DATE '2026-12-31')) dt),
h AS (SELECT holiday_name, holiday_date, boost_start, peak_start,
             COALESCE(cooldown_end, DATE_ADD(holiday_date, INTERVAL 3 DAY)) AS win_end
      FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
      WHERE category IN ('gift_season','prime_event','back_to_school','seasonal')
        AND boost_start IS NOT NULL),
own AS (SELECT d.dt, ARRAY_AGG(STRUCT(h.boost_start, h.peak_start, h.holiday_name)
                               ORDER BY h.boost_start, h.holiday_date, h.holiday_name
                               LIMIT 1)[SAFE_OFFSET(0)] AS o
        FROM d LEFT JOIN h ON d.dt BETWEEN h.boost_start AND h.win_end GROUP BY 1),
book AS (SELECT dt, CASE WHEN o.holiday_name IS NULL THEN 'OFF_PEAK'
                         WHEN o.peak_start IS NOT NULL AND dt < o.peak_start THEN 'BOOST'
                         ELSE 'PEAK' END AS book_state
         FROM own)
SELECT book_state, `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(dt) AS plan_state,
       COUNT(*) AS days, MIN(dt) AS first_day, MAX(dt) AS last_day
FROM book GROUP BY 1, 2 ORDER BY 1, 2;
```

**Read the shape of the year from the function, never from this document** — editing the calendar
moves it. Per stretch:

```sql
WITH d AS (SELECT day, `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(day) AS s
           FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2026-08-20', DATE '2026-12-31')) day),
g AS (SELECT day, s, IF(s = LAG(s) OVER (ORDER BY day), 0, 1) AS brk FROM d),
r AS (SELECT day, s, SUM(brk) OVER (ORDER BY day) AS grp FROM g)
SELECT s AS state, MIN(day) AS from_day, MAX(day) AS to_day, COUNT(*) AS days
FROM r GROUP BY s, grp ORDER BY from_day;
```

And how many days of a year land in each state — the number the ruling below turns on:

```sql
SELECT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(day) AS state, COUNT(*) AS days
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2026-01-01', DATE '2026-12-31')) day
GROUP BY 1 ORDER BY days DESC;
```

**Open question for Ori (nothing here is a code change).** Two ways out if the answer is "that is
too much PEAK":

- *the calendar* — move a `peak_start` on `DIM_US_HOLIDAYS` (Halloween's is what swallows the
  pre-Black-Friday weeks), and every engine that reads the house calendar moves with it;
- *the precedence* — overrule "a peak anywhere beats a run-up everywhere" with "the nearest
  season wins" or "a run-up wins over a peak from another season". That is one `CASE` in
  `FN_PLAN_CALENDAR_STATE`, and `C03` is written on a live overlap date so it fails the moment
  the precedence changes and has to be re-asserted deliberately.

### Deploy and verify

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql)"
```

The DDL is idempotent **and deferential**: `CREATE TABLE IF NOT EXISTS`, then
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` so a re-run converges against a table that already
exists (a bare `CREATE TABLE IF NOT EXISTS` is a silent no-op there), then a seed that writes
only a state with no row at all and deletes only its own row for a state nobody has ruled on.
The acceptance must read `PASS` on every row; `C03` asserts the live calendar, so it is also the
alarm that fires when someone edits `DIM_US_HOLIDAYS`, and `C08` is the alarm that fires when the
plan's window and the house's older window rule part company.

### What today's settings are

Do not write them down here — read them:

```sql
SELECT CURRENT_DATE('America/New_York') AS today_ny,
       `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York')) AS state,
       c.window_days, c.allowance_share, c.live_plan, c.ramp_steps, c.min_orders, c.description
FROM `onyga-482313.OI.DE_PLAN_CONFIG` c
WHERE c.is_active
  AND c.calendar_state = `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'));
```

---

## 1b. P-14 — the settle correction and the asymmetric guard (built, UNRULED, and measured)

Ori raised this on 2026-08-23: the window's sales are still arriving (SP ~D+7, SB ~D+14), so a
3-day window read today has seen a fraction of its orders and the **not-good** side is overstated
— the plan would park keywords for the crime of being recent. He was offered three fixes and has
**not ruled**. P-14 is the build-as-specified answer and it is now live on the only path that
judges keywords today, `tools/build_reprice_bulksheet.py --rule-b`:

- **(a) the correction** — each day's gross profit is divided by the published completion factor
  for its channel and its age, read from `V_ADS_SETTLE_CURVE` as a **table**, never a factor
  typed into a file. Every factor is at most 1, so the correction can only ever raise a return:
  it **promotes, never demotes**. Order counts are never corrected — a count cannot be
  fractional, so the P-3 floor always reads observed orders.
- **(b) the asymmetric guard** — a keyword whose settled 90-day record clears its family bar is
  **never demoted** until its window has settled (SP 7 / SB 14 complete days after `window_to`).
  Those rows read `HELD_UNSETTLED` and carry the date they settle.
- **(c)** every row publishes `settle_arm` and `decided_by`, in the audit CSV
  (`rule_b_settle_arm`, `rule_b_decided_by`, `rule_b_settle_due`, and `rule_b_gp` beside
  `rule_b_gp_corrected`) and in the plain-English reason the README prints.

**To overrule:** one sentence — *"judge the window as it reads"* — and both halves come out of
`rule_b()` and out of `V_PLAN_WINDOW_JUDGMENT` (§2, shipped v27.133). Nothing else changes.

**Since v27.133 there is a second, sharper question underneath it:** under a rolling window the
guard never lifts, so it does not delay a demotion, it prevents one. §2 states the consequence,
publishes the query that measures it, and gives the one-line ruling that would turn the veto
back into a delay.

### What the correction is actually worth — measure it, do not take a number from this page

This matters to the ruling, so it is written as a query rather than an answer. Arm (a) lifts the
window's gross profit for the whole book, and yet it can carry a keyword across its bar only if
that keyword **already has the two orders the floor demands and sits just under the bar**. The
overstatement Ori described lives almost entirely *behind the order floor* — keywords with one
observed order, or none — and the ruling's own wording forbids correcting a count. So arm (a) can
be real and still promote nobody, while arm (b) can only hold keywords that were already good.
Run this before ruling:

```sql
DECLARE wm DATE DEFAULT (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`())
                         FROM `onyga-482313.OI.FACT_AMAZON_ADS`);
DECLARE window_to DATE DEFAULT LEAST(DATE_SUB(wm, INTERVAL 1 DAY),
                                     DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY));
DECLARE wd INT64 DEFAULT (SELECT window_days FROM `onyga-482313.OI.DE_PLAN_CONFIG`
                          WHERE is_active AND calendar_state =
                            `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'))
                          QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state
                                                     ORDER BY updated_at DESC) = 1);
WITH ks AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         family, family_bar, channel
  FROM `onyga-482313.OI.V_KEYWORD_STATE`
  WHERE family IN ('Bottle','Lollibox','LolliME','Fresh')
    AND NOT COALESCE(is_brand_defense, FALSE)),
k AS (
  SELECT ks.cid, ks.kid, ANY_VALUE(ks.family_bar) bar,
         SUM(f.Ads_cost) sp, SUM(f.Ads_orders) ord, SUM(f.GROSS_PROFIT) gp,
         SUM(f.GROSS_PROFIT
             / (COALESCE(NULLIF(sc.sales_pct_of_final_median, 0), 100.0) / 100.0)) gp_corr
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN ks ON ks.cid = CAST(f.campaign_id AS STRING) AND ks.kid = CAST(f.keyword_id AS STRING)
  LEFT JOIN `onyga-482313.OI.V_ADS_SETTLE_CURVE` sc
    ON sc.channel = ks.channel
   AND sc.age_days = DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), f.date, DAY)
  WHERE f.date BETWEEN DATE_SUB(window_to, INTERVAL wd - 1 DAY) AND window_to
    AND f.keyword_id IS NOT NULL
  GROUP BY 1, 2)
SELECT window_to, wd,
       SUM(gp) AS gp_observed, SUM(gp_corr) AS gp_corrected,
       SUM(gp_corr) / NULLIF(SUM(gp), 0) AS uplift,
       COUNTIF(ord >= 2 AND sp > 0 AND gp_corr / sp >= bar
               AND gp / sp < bar)                       AS promoted_by_the_correction,
       SUM(IF(ord >= 2 AND sp > 0 AND gp / sp >= bar, sp, 0)) / wd     AS pot_observed_per_day,
       SUM(IF(ord >= 2 AND sp > 0 AND gp_corr / sp >= bar, sp, 0)) / wd AS pot_corrected_per_day,
       COUNTIF(ord = 1)                                 AS behind_the_floor_one_order,
       SUM(IF(ord = 1, sp, 0)) / wd                     AS one_order_spend_per_day,
       COUNTIF(ord = 0 AND sp > 0)                      AS behind_the_floor_no_sale,
       SUM(IF(ord = 0 AND sp > 0, sp, 0)) / wd          AS no_sale_spend_per_day
FROM k;
```

If `promoted_by_the_correction` comes back at zero while `behind_the_floor_*` carries most of the
not-good spend, then P-14 as written answers the defect only through arm (b) — and the ruling in
front of Ori is whether the order floor itself should bend for a keyword whose window has not
settled. That is a change to P-3, not to P-14, and nobody has made it.

### What the order floor costs, and how big the ramp's gap is (P-3, P-5, P-8)

The spec used to pin these as numbers in its "why" cells. They are measurements and they move, so
they are queries now (Standing Rule 0). Same window definition as above — `wm`, `window_to` and
`wd` declared exactly as in the block above, then:

```sql
WITH ks AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         family, family_bar, state
  FROM `onyga-482313.OI.V_KEYWORD_STATE`
  WHERE family IN ('Bottle','Lollibox','LolliME','Fresh')
    AND NOT COALESCE(is_brand_defense, FALSE)),
k AS (
  SELECT ks.family, ks.state, ANY_VALUE(ks.family_bar) bar, ks.cid, ks.kid,
         SUM(f.Ads_cost) sp, SUM(f.Ads_orders) ord, SUM(f.GROSS_PROFIT) gp
  FROM ks
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON CAST(f.campaign_id AS STRING) = ks.cid AND CAST(f.keyword_id AS STRING) = ks.kid
   AND f.date BETWEEN DATE_SUB(window_to, INTERVAL wd - 1 DAY) AND window_to
  GROUP BY 1, 2, 4, 5)
SELECT family,
  -- P-3: how much of the family's window spend the good side actually holds, and how much of the
  -- bar-passing spend the 2-order floor keeps rather than pushing to the not-good side
  SAFE_DIVIDE(SUM(IF(ord >= 2 AND sp > 0 AND gp / sp >= bar, sp, 0)), SUM(sp))  AS good_share_of_family_spend,
  SAFE_DIVIDE(SUM(IF(ord >= 2 AND sp > 0 AND gp / sp >= bar, sp, 0)),
              SUM(IF(sp > 0 AND gp / sp >= bar, sp, 0)))                        AS bar_passing_spend_kept_by_the_floor,
  -- P-5: settled winners whose window is quiet, i.e. the population grace covers
  COUNTIF(state IN ('WINNER','PACED_WINNER') AND COALESCE(ord, 0) < 2)          AS quiet_settled_winners,
  -- P-8: the gap the ramp exists to close, per day
  SUM(IF(NOT (COALESCE(ord,0) >= 2 AND COALESCE(sp,0) > 0 AND gp / sp >= bar),
         COALESCE(sp, 0), 0)) / wd                                              AS not_good_per_day,
  0.20 * SUM(IF(COALESCE(ord,0) >= 2 AND COALESCE(sp,0) > 0 AND gp / sp >= bar, sp, 0)) / wd
                                                                                AS allowance_per_day_at_020
FROM k GROUP BY family ORDER BY family;
```

Two honest warnings about reading it. **The counts move with the window length** — the same
question asked over 3 days and over 7 gives different populations, which is one more reason not
to write either down. And **`allowance_per_day_at_020` hardcodes the share for illustration**;
the live share is whatever `DE_PLAN_CONFIG` declares for today's state, which may be 0.50.

---

## 2. The judgement layer (Task 1, v27.133 · repaired v27.134, v27.135 and v27.138)

Three objects, deployed in this order:

| object | one responsibility |
|---|---|
| `V_PLAN_SETTLE_COMPLETION` | per (channel, age in days), how much of that day's ads sales had arrived when we read it (P-14a) |
| `FACT_PLAN_NEXT_WEEK` | the nightly plan table — **created empty here**, filled by the builder in Task 2 |
| `V_PLAN_WINDOW_JUDGMENT` | one row per working-family keyword: the window, its record raw and corrected, the side both plans give it, the arm that decided it, the repaired price, the seat cost and the rank |

Nothing in this layer moves money. It judges, and it says out loud who judged. The potting,
seating, queueing and the budgets are Task 2 (`SP_BUILD_NEXT_WEEK_PLAN`).

### The window, and why it is fenced

`window_days` complete days ending at

```
window_to = LEAST(watermark - 1, CURRENT_DATE('America/Los_Angeles') - 2)
watermark = LEAST(MAX(date), FN_ADS_ANCHOR_CAP())   over FACT_AMAZON_ADS
```

The first term is P-10: the filling day never enters a window. The second is the P-14a fence:
`FN_ADS_ANCHOR_CAP()` advances to the current Los Angeles date at 22:00 LA, so a late-evening run
would otherwise judge a day that is only one day old — and the published curve puts an age-1 day's
**spend** materially short of final, which would understate the pot, the allowance and every seat
cost in the same direction, silently. Before 22:00 LA the two terms are equal and the fence costs
nothing. `window_days` and the order floor come from `DE_PLAN_CONFIG` for the state
`FN_PLAN_CALENDAR_STATE` reads today; no setting is a literal in the SQL.

Read today's window, never copy one from this page:

```sql
SELECT DISTINCT calendar_state, window_days, min_orders, watermark, window_from, window_to
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

### The correction (P-14a), and the one number a reader can check

Each window day has a completion factor for its channel and age, read from `V_ADS_SETTLE_CURVE`
through `V_PLAN_SETTLE_COMPLETION` (forward-filled over unmeasured ages, made monotone in age,
capped at 1.0, floored at a declared 0.50, and honest — `curve_available = FALSE` means the curve
could not answer and the factor is 1.0). The window's gross profit is then corrected by **one
reversible division**:

```
settle_factor_eff = SUM(|gp_day|) / SUM(|gp_day| / factor_day)      -- in (0, 1]
w_gp_corrected    = w_gp / settle_factor_eff
```

When every day of a window has the same sign — the normal case — this is algebraically the same as
dividing each day by its own factor, which is how the ruling describes it. Writing it as one
division is what makes the §9 guarantee true *by construction* rather than by luck: gross profit
can be negative on a day, and a mixed-sign window corrected day-by-day can come out **smaller** in
magnitude than the raw window, which is the opposite of what the correction is for. The acceptance
(C10) checks that `w_gp_corrected × settle_factor_eff` reconstructs `w_gp`, so the correction stays
a single audited step. **Spend is never corrected** — the same curve publishes spend at its final
value from age 2, and the fence guarantees age 2. Check that claim against the curve, not this
page:

```sql
SELECT channel, age_days, sales_completion, spend_completion, curve_available, factor_source
FROM `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION` WHERE age_days <= 4 ORDER BY channel, age_days;
```

**Order counts are never corrected.** A count cannot be fractional, so the P-3 floor always reads
observed orders — which is also why the correction can promote only a keyword that already clears
the floor and sits just under its bar (§1b).

### Who decided each row

`decided_by` is the ruling (`P-3`, `P-5`, `P-14b`) and `settle_arm` is what the correction did
(`SETTLED`, `CORRECTED`, `PROMOTED_ON_FRESH`, `HELD_UNSETTLED`, `NOT_CORRECTABLE_NO_GP`,
`UNCORRECTED_NO_CURVE`). The order of the arms is: GOOD on the corrected window → **GRACE (P-5)**
→ **HELD_UNSETTLED (the guard)** → LOSING / ONE_ORDER / NO_SALE / NOT_SERVING.

**Grace is tested BEFORE the guard (v27.135), and the order was doing real damage the other way
round.** Both arms put the row on the good side, so no money moves with the order — but every
ladder-settled winner is by definition "was good", so the guard reached them first and answered for
36 of the 39 winners with a quiet window. Three things followed. P-5's "one quiet window" was
replaced on those rows by a ruling that buys *every* window and has no expiry, so the limit could
never bite for a keyword that carries spend. The shipped reprice book, which has always tested
grace first, named a **different ruling than the view on the same money**. And the `unguarded`
counterfactual below — the one Ori is told to read before he rules — was wrong by that money,
because dropping the guard drops those rows into grace, not into the queue. Re-derive the three
counts on the live view before trusting this paragraph:

```sql
SELECT COUNTIF(ladder_state IN ('WINNER','PACED_WINNER') AND w_ord < min_orders)  AS quiet_winners,
       COUNTIF(verdict = 'GRACE')                                                AS graced,
       COUNTIF(verdict = 'HELD_UNSETTLED')                                        AS held,
       ROUND(SUM(IF(verdict = 'GRACE', w_sp, 0)) / MAX(window_days), 2)           AS graced_per_day
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

**The book and the view now agree row for row.** `tools/build_reprice_bulksheet.py --rule-b` was
the only live judge and it had drifted from the view on more than the arm's name: it held keywords
that never served (a *side* divergence the v27.134 service repair created), it labelled every audit
row `CORRECTED` including rows nothing corrected, and it divided by the RAW `V_ADS_SETTLE_CURVE`
with none of `V_PLAN_SETTLE_COMPLETION`'s cap, floor, monotone smoothing or thin-curve gate. All
four are aligned in v27.135, and the alignment changed **no move**: the same eight rows, the same
dispositions, the same corrected margins. Check the agreement by joining the audit CSV to the view
on `campaign_id, keyword_id` and comparing `rule_b_verdict` / `rule_b_decided_by` /
`rule_b_settle_arm` with `verdict` / `decided_by` / `settle_arm` — it must be exact.

**That divergence is closed (v27.137, corrected here in v27.138).** The book now reads P-5's
one-window limit from `FACT_PLAN_NEXT_WEEK` with the SAME expression `V_PLAN_WINDOW_JUDGMENT` uses
(the most recent `GRACE` later than the most recent `GOOD`), so the two cannot grant and refuse the
same grace. Task 2 shipped and writes that table nightly, so `grace_limit_armed` reads FALSE only
for a keyword the plan has no partition EARLIER THAN TODAY for; both artifacts say which condition
is unmet and when it lifts, rather than the sentence they carried after the builder had already
shipped ("no builder writes it until Task 2").

Four properties of those arms were repaired in **v27.134** and each is now asserted:

- **The guard requires service.** P-14b exists because sales are still *arriving*. A keyword that
  took no spend and no clicks in the window has nothing in flight, so the guard has no basis and
  no longer fires: `served` is a precondition, and `C17` asserts no `HELD_UNSETTLED` row has an
  empty window. Before the repair such rows were held on the good side — where P-4 then forbade
  re-pricing them — while their own `settle_arm_sentence` said, correctly, that the settle question
  did not arise for them. Two published sentences contradicted each other on the same row.
- **An arm never claims work it did not do.** The correction *scales gross profit*. A window with
  money spent, clicks taken and nothing sold has none, and zero divided by any factor is zero — so
  no correction is possible, and those rows no longer print "the window record was corrected". They
  carry `NOT_CORRECTABLE_NO_GP` and say that only the order floor (P-3) or the guard (P-14b) can
  change their side. **These are exactly the keywords Ori's defect was about**, and the plan used
  to tell him on each one that the settle correction had already handled it.
- **Grace is one window, not a standing exemption.** P-5 reads "two quiet windows in a row and rule
  B stands". The view implemented the grant and not the limit, so a settled winner with a
  permanently quiet window kept the good side forever. Grace is now refused when last night's live
  plan already granted it (`prior_grace`, read back from `FACT_PLAN_NEXT_WEEK.verdict`), and `C12`
  asserts both halves. **Task 2 must write `verdict = 'GRACE'` faithfully** — a builder that
  collapses GRACE into GOOD turns grace back into a permanent exemption.
- **"Was good" prefers last night's plan.** It is `IF(prior_seen, prior_good, ladder_settled_good)`,
  which is what this SOP and the ruling always described. It used to be an unconditional `OR`:
  invisible while the plan table is empty, and decisive once Task 2 fills it, because a keyword the
  live plan demoted last night would have been re-held every night for as long as its 90-day ladder
  record cleared the bar — a demotion could never stick and the guard could never be worked off.

Every row also carries two plain sentences: `sentence` (what the keyword did and what happens to
it) and `settle_arm_sentence` (which arm decided it). A keyword that took no spend and no clicks
in the window is `SETTLED` with "nothing to correct and nothing arriving" — `UNCORRECTED_NO_CURVE`
is reserved for rows the curve genuinely could not answer, because that label is the one that tells
Ori the plan is resting on the guard alone.

```sql
SELECT family, verdict, decided_by, settle_arm, sentence, settle_arm_sentence
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` ORDER BY w_sp DESC LIMIT 20;
```

### The guard's clock (P-14b, v27.138) — read it before reading the open question below

`was_good` is last night's live-plan SIDE, and a held row's side is GOOD. `settled` reads the window
being judged, and that window rolls forward every night (`window_to` = the watermark − 1), so it is
never settled on a healthy night. Put together, one night on the protected side wrote the evidence
that re-armed the guard the next night, forever: the protected side was a one-way door, the ladder
gate the spec attributes the guard to stopped applying after night one, and a keyword whose P-5
grace was spent fell straight through into a permanent hold instead of into the queue. The hold is
now ANCHORED to the window that triggered it — `hold_since` and `hold_settles_on`, read from the
plan's own history — and lifts once that window has settled and the sales it was waiting for have
landed. Promotion on fresh evidence is untouched every night. Read the clock:

```sql
SELECT verdict, COUNT(*) AS kw,
       ROUND(SUM(w_sp) / MAX(window_days), 2) AS spend_per_day,
       MIN(hold_since) AS oldest_hold, MIN(hold_settles_on) AS next_lift,
       COUNTIF(hold_expired) AS clock_run_out
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1 ORDER BY 3 DESC;
```

**Ori rules** whether the guard is this delay, or the unlimited veto it was: one line either way
(§3 of this SOP, item 4).

### The last-day test (P-14c, v27.147) — Ori ruled, and it closes the open question below

Ruled 2026-09-17, built 2026-09-28. The hold is granted **only when the last complete day of the
window was very good** — at least one order and a corrected return of at least 1.5× the family bar
(`strong_day_min_orders`, `strong_day_mult` in the judge's `k` CTE). A losing window whose last day
won a little is judged on the window. So the guard is a **delay, bounded by the clock, granted on
one condition** — neither the veto the first build produced nor an unconditional wait.

Read it on the row: `last_day_sp / last_day_ord / last_day_gp_corrected / last_day_ret`,
`last_day_strong`, and on every NOT-GOOD row that was good, served and unsettled,
`guard_released_by` = `LAST_DAY_NOT_STRONG` or `HOLD_EXPIRED`. The builder asserts that column is
never NULL on such a row and that every HELD row has `last_day_strong` — it checks the judgement is
complete and does not re-derive it (P-11). Acceptance C09 (restated) and C26.

**Why this repair was urgent, and what it says about the two workers.** From 2026-08-29 to
2026-09-28 `SP_BUILD_NEXT_WEEK_PLAN` failed every night on its own P-14b assertion. The builder's
v27.136 line copied the guard's preconditions (`was_good AND served AND NOT settled`) and read them
as a veto; the judge's v27.138 clock lets a hold expire. They agreed until the first clock ran out.
From that night the judge demoted a keyword its rule allowed, the builder refused the partition, and
because no partition was written the judge's memory (`hold_since`, `was_good`) froze, so the same
rows failed forever. Nothing on Amazon moved — bids go up by bulksheet — but every surface read the
08-28 plan for a month. A guard that re-judges is the second engine P-11 forbids.

`held_with_no_sale` is FALSE by construction from v27.147 (no order in the window ⇒ no very good
last day); the column stays for the scorecard and this page's history.

**Every row records the rule it was judged under (v27.154 follow-up, 2026-10-01).** The judge
publishes its two `k` settings, `strong_day_mult` and `strong_day_min_orders`, on every row, and the
builder copies them into `FACT_PLAN_NEXT_WEEK` (migration
`scripts/bigquery/migrations/2026-10-01_plan_strong_day_rule_columns.sql`; the builder's assertions
are unchanged). Why: the scorecard grades each hold and release against the multiplier that decision
was made under. A threshold change is exactly what the scorecard's hint exists to propose, and a
grade that compared old decisions with today's constant would grade them against a rule that was
not in force. Rows written before the columns existed (the 2026-09-28 … 10-01 partitions) are not
updated; the scorecard reads them as 1.5 and 1, the values the judge's `k` CTE has carried since
v27.147 (commit 41d2318: `git log -S` on either `k` line lists that commit alone, and the deployed
view's definition read 1.5 / 1 on 2026-10-01).

### THE OPEN QUESTION THIS LAYER PUT ON ORI'S DESK (answered by P-14c above; kept as the record)

P-14b says a keyword that was good is not demoted **until its window has settled**. Under a rolling
window that always ends two days ago, a window is never settled at the moment it is judged: the
"judged again with no guard" date in §3a never arrives, because the next night judges a **new**
unsettled window. So as built the guard is not a delay — it is a **veto**: a keyword whose ladder
record clears its family bar cannot be moved to the not-good side by rule B at all, whatever the
window says. That pulls rule B (P-1: the window decides the side) back towards plan A (the ladder
decides), and it moves real money to the good side, where P-4 says it is never cut and never
re-priced. It is built exactly as the ruling is written.

**The guard moves money in BOTH directions, and every earlier account of it on this page named only
one.** Money held on the good side leaves the seat queue — that half was always disclosed. But P-2
defines the **pot** as what the GOOD side actually spent, and the **allowance** is a share of the
pot, so the very same held keywords *enlarge the loss budget the shrunken queue is rationing*. The
guard therefore removes candidates and raises the allowance at the same time, from the same rows.
Ori is entitled to see both halves before he rules, so the measurement query prints both — and it
prints them per family, because a family's allowance can exceed its entire not-good side, at which
point every candidate is seated with money to spare and the seat queue rations nothing at all:

```sql
WITH j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
d AS (SELECT MAX(window_days) AS wd, MAX(allowance_share) AS share FROM j)
SELECT family,
       ROUND(SUM(IF(side_b = 'GOOD', w_sp, 0)) / (SELECT wd FROM d), 2)             AS pot_guarded,
       ROUND(SUM(IF(side_b = 'GOOD', w_sp, 0)) / (SELECT wd FROM d)
             * (SELECT share FROM d), 2)                                           AS allowance_guarded,
       ROUND(SUM(IF(verdict IN ('GOOD','GRACE'), w_sp, 0)) / (SELECT wd FROM d), 2) AS pot_unguarded,
       ROUND(SUM(IF(verdict IN ('GOOD','GRACE'), w_sp, 0)) / (SELECT wd FROM d)
             * (SELECT share FROM d), 2)                                           AS allowance_unguarded,
       ROUND(SUM(IF(side_b = 'NOT_GOOD', w_sp, 0)) / (SELECT wd FROM d), 2)        AS queue_guarded,
       ROUND(SUM(IF(verdict NOT IN ('GOOD','GRACE'), w_sp, 0)) / (SELECT wd FROM d), 2) AS queue_unguarded,
       COUNTIF(settle_arm = 'HELD_UNSETTLED')                                      AS held,
       COUNTIF(held_despite_evidence)                                              AS held_though_losing,
       ROUND(SUM(IF(held_despite_evidence, w_sp, 0)) / (SELECT wd FROM d), 2)      AS held_though_losing_per_day
FROM j GROUP BY ROLLUP(family) ORDER BY family NULLS FIRST;   -- the NULL family row is the book
```

Compare `allowance_guarded` with `queue_guarded` per family: wherever the allowance is the larger
number, the seats are not scarce and P-7's ranking is decorative for that family.

**Why the `unguarded` columns are now arithmetically right, and were not before.** They read
`verdict IN ('GOOD','GRACE')` — the side the book would take if the `HELD_UNSETTLED` branch were
deleted. That is only true if the branch UNDER the guard catches what the guard was catching. Until
v27.135 the guard was tested *before* grace, so 36 held rows would have fallen into P-5 grace and
not into the queue, and the published `pot_unguarded` was short by their spend — a quarter of the
pot, erring in the direction that made the guard look more expensive than it is, directly under the
one ruling this layer put on Ori's desk. Grace is now tested first, so the rows the guard still
holds are exactly the rows that would be demoted without it and the counterfactual is a real
one-step read. Verify it rather than trusting it — the two must be equal:

```sql
SELECT ROUND(SUM(IF(verdict IN ('GOOD','GRACE'), w_sp, 0)) / MAX(window_days), 2) AS pot_unguarded,
       ROUND(SUM(IF(verdict != 'HELD_UNSETTLED' AND side_b = 'GOOD', w_sp, 0))
             / MAX(window_days), 2)                                              AS pot_minus_the_guard
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

**Not every held row is waiting for evidence, and there are TWO kinds, not one.** Some held
keywords already MET the order floor in the window and still read *under* their family bar on
CORRECTED numbers: they are not quiet, they are losing with the evidence in hand, and the guard
holds them anyway on the side P-4 protects (`held_despite_evidence`, counted by the
`held_though_losing` columns above). **The larger population by money is the other one:** keywords
that took clicks, spent real money and **sold nothing**. Their arm sentence used to read "promotion
is allowed on fresh evidence" — a promise the correction cannot keep, because it scales gross
profit and their window has none. That is the identical fact pattern the NOT-GOOD side gets a
dedicated arm and an explicit sentence for (`NOT_CORRECTABLE_NO_GP`); the only difference is that
these keywords' 90-day ladder records clear the bar, so until v27.135 the disclosure ran the
*opposite* way on the side carrying more money. `held_with_no_sale` marks them, `good_side_no_sale`
marks the same fact wherever it sits on the protected side (grace included, since v27.135's reorder
moves some of them there), and `C20` asserts the sentence. Price both populations:

```sql
SELECT family,
       COUNTIF(held_despite_evidence)                                        AS held_though_losing,
       ROUND(SUM(IF(held_despite_evidence, w_sp, 0)) / MAX(window_days), 2)  AS losing_per_day,
       COUNTIF(good_side_no_sale)                                            AS protected_no_sale,
       ROUND(SUM(IF(good_side_no_sale, w_sp, 0)) / MAX(window_days), 2)      AS no_sale_per_day
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
GROUP BY ROLLUP(family) ORDER BY family NULLS FIRST;
```

Neither population can be read as "we do not know yet": the first has its evidence and it says
losing, and the second has spent money the correction is arithmetically incapable of redeeming.

The per-arm breakdown is still worth reading alongside it:

```sql
SELECT family, side_b, settle_arm, COUNT(*) AS keywords,
       ROUND(SUM(w_sp) / MAX(window_days), 2) AS spend_per_day,
       COUNTIF(is_candidate) AS candidates
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
GROUP BY 1, 2, 3 ORDER BY family, side_b, spend_per_day DESC;
```

**To overrule, one line each.** *"Judge the window as it reads"* — drop the correction and the
`HELD_UNSETTLED` arm (§1b); the pot, the allowance and the queue all revert to the `unguarded`
columns above in one step. *"The guard is a delay, not a veto"* — demote on the last window that
**has** settled (a second window ending `settle_days` before `window_to`) while promotion keeps
reading the fresh one; that is a change to P-14b's evidence, and nobody has made it. Either line
changes the allowance as well as the queue, so read both columns before choosing. Both are now
priced honestly: the `unguarded` columns are a true one-step read since grace moved ahead of the
guard (above).

### A SECOND OPEN QUESTION: P-5's limit, and the day it arms

The grace limit is real code and it is read from the live plan's own history — grace is spent until
the keyword earns a GOOD window back. **Task 2 shipped and `SP_BUILD_NEXT_WEEK_PLAN` writes
`FACT_PLAN_NEXT_WEEK` every night (orchestrator 20.8c), so `grace_limit_armed` reads FALSE only for
a keyword the plan has no partition EARLIER THAN TODAY for — the day the first partition is written,
and never again after it** (v27.138 correction: the view, its OPTIONS description and `config.yaml`
all still said "no builder writes that table until Task 2 ships" after the builder had shipped and
written a partition, which is the opposite of what happens on the next run). Two consequences worth
Ori's eye. First, the population is not small — grace now answers for the ladder winners the guard used to swallow, so
read what it is protecting:

```sql
SELECT COUNTIF(verdict = 'GRACE')                                      AS graced,
       COUNTIF(verdict = 'GRACE' AND good_side_no_sale)                AS graced_and_sold_nothing,
       ROUND(SUM(IF(verdict = 'GRACE' AND good_side_no_sale, w_sp, 0))
             / MAX(window_days), 2)                                    AS no_sale_per_day,
       LOGICAL_OR(grace_limit_armed)                                   AS limit_armed
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

Second, "quiet" is P-5's own word and the view reads it as *under the order floor* — which includes
a keyword that took dozens of clicks and real money and sold nothing. Those rows say so on their
face now (`good_side_no_sale`), because P-4 then forbids cutting or re-pricing them. **Ori rules:**
is a window that spent money and returned no sale a *quiet* window for the purposes of P-5, or is
grace only for a winner that genuinely was not shown?

### Candidacy, price, seat cost and rank

- **Candidate** = a not-good keyword, not in the holdout, with something to repair (losing, one
  order, or spend with no sale). A keyword that took no spend and no clicks has no repair to buy
  and is a candidate only if LIFT's probe list nominates it (P-11 keeps that list as a candidate
  *source*) — otherwise every dormant keyword would queue for a zero-cost seat and bury the
  ranking the seats exist for.
- **The seat SENTENCE and the candidacy COLUMN come from the same expression** (v27.135, `C18`,
  `C19`). They did not. The clause branched on holdout membership before it branched on service, so
  dormant keywords in holdout campaigns were told in words that they "compete for a seat at the
  repaired price today" while their own `is_candidate` refused them one — and `C15` could not catch
  it, because it only asked whether the word *holdout* appeared, never whether the row actually
  competes. A further set read "only if the probe list nominates it", which it does not. Between
  them that left most of the not-good side with **neither a seat nor a queue position named
  anywhere**, against §9's promise that every not-good keyword has exactly one of them. **§9's
  guarantee is about CANDIDATES.** A keyword with no spend, no clicks and no nomination has nothing
  to repair, so it takes no seat *and* no queue position — parking a keyword that spends nothing
  saves nothing — and its row now says exactly that. Count the three populations:

```sql
SELECT side_b, is_candidate, COUNT(*) AS keywords,
       COUNTIF(REGEXP_CONTAINS(sentence, r'competes for a seat at the repaired price')) AS promised_a_seat,
       COUNTIF(REGEXP_CONTAINS(sentence, r'does not compete for a seat'))               AS told_it_has_no_move
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1, 2 ORDER BY 1, 2;
```
- **Repaired price** (P-6) = the ladder's `affordable_bid`, capped at three 5 % steps either way
  from the live bid, floored at the row's own `bid_floor`, ceilinged at the house $2.00 on a
  raise. The cap constants are mirrored from the reprice book so the book and the plan cannot
  price the same keyword differently.
- **Seat cost** (P-6) = spend at *that* price, per day — the window's spend per day scaled by the
  price change; a candidate with no window spend is costed from `T_OOB_SEAT_ECONOMICS`.
- **The good side carries no price and no seat cost** (P-4, v27.134). `planned_bid` and
  `seat_cost_per_day` are **NULL** whenever `side_b = 'GOOD'`. They used to be published on every
  row, so an executable price — sometimes a *cut* — sat one column away from a sentence reading
  "the good side is never cut and is not re-priced", with only `is_candidate` between that column
  and a move and no check standing over it. `C14` asserts it here, at the layer that publishes the
  number, rather than trusting each consumer to re-derive the side.
- **Park price** (§4 step 5, v27.134). `T_OOB_SEAT_ECONOMICS` only knows keywords that entered OOB
  seat economics, so the park price used to be NULL on most of the queue — a gap Task 2 would have
  met as a NULL, with no honesty column. `bid_park` now falls back to the row's own `bid_floor`
  (the one house floor definition, already on every row) and is never below it; `bid_park_source`
  declares which source answered (`SEAT_ECONOMICS` / `BID_FLOOR_FALLBACK` / `NONE`) exactly as
  `V_PLAN_SETTLE_COMPLETION.curve_available` does for the curve, and `bid_park_seat_econ` keeps the
  raw value so the coverage gap stays measurable. **Which** park price the plan *should* use is
  still one of Ori's open rulings (spec §8); this makes the queue answerable, not the ruling made.

```sql
SELECT bid_park_source, COUNT(*) AS keywords, COUNTIF(is_candidate) AS candidates
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1 ORDER BY 2 DESC;
```

- **Rank** (P-7) is written "dollars at stake × closeness to the bar", ties by clicks then by the
  keyword key (a total ordering, so two reads never disagree).
- **THE TWO FACTORS ARE NOT TWO FACTORS: THE SPEND CANCELS, IDENTICALLY, ON EVERY ROW.** Return is
  gross profit *divided by* spend, so
  `(w_sp / days) × (w_gp_corrected / w_sp) / bar` = `w_gp_corrected / (days × bar)`.
  Window spend contributes **nothing** to the ordering: the seat queue is ordered by corrected
  gross profit alone, rescaled by a constant per family. That is the exact inversion P-7's own
  rationale exists to prevent — "closest first alone seats a $0.50/day keyword before a $50/day
  one" — because a keyword returning $3 of gross profit on $0.50/day now outranks one returning $2
  on $50/day. Every published sentence about the rank, here and in the spec, described a product of
  two independent terms until v27.135, and disclosed only the *special case* (rank = 0 when a
  keyword sold nothing), which narrows a total collapse into an edge case. Both factors are now
  published separately — `rank_dollars_at_stake` and `rank_closeness` — so the multiplication can be
  read rather than trusted, and `C21` asserts the identity. **The formula is Ori's ruling and is
  untouched.** Prove the collapse and see the inversion on today's queue:

```sql
SELECT COUNTIF(ABS(rank_score - SAFE_DIVIDE(w_gp_corrected, window_days * family_bar)) > 1e-9)
         AS rows_where_spend_matters          -- must be 0: the spend cancels everywhere
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;

SELECT family, target_text, ROUND(rank_dollars_at_stake, 2) AS at_stake_per_day,
       ROUND(rank_closeness, 3) AS closeness, ROUND(rank_score, 3) AS rank_score
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
WHERE is_candidate ORDER BY rank_score DESC, w_clk DESC LIMIT 10;
```

- **P-7 scores ZERO wherever there is no gross profit — which is most of the queue.** That is the
  same collapse seen at its endpoint: closeness to the bar is zero when a keyword sold nothing, so
  a keyword burning real money with no order ranks *below every losing keyword* and can never be
  seated for a repair; the ordering falls through to clicks and the keyword key, which is a total
  ordering but is not P-7's ordering. It is not absorbed silently: `rank_is_degenerate` is TRUE on
  every candidate whose rank is zero. Read how much of the queue that is, and what it carries,
  before Task 2 hands out seats:

```sql
SELECT COUNTIF(is_candidate) AS candidates,
       COUNTIF(rank_is_degenerate) AS ranked_zero,
       ROUND(SUM(IF(rank_is_degenerate, w_sp, 0)) / MAX(window_days), 2) AS ranked_zero_spend_per_day,
       ROUND(SUM(IF(is_candidate, seat_cost_per_day, 0)), 2) AS candidate_seat_cost_per_day
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

  **Ori's ruling, and it is now two questions, not one.** (1) Park the no-sale keywords (the rank
  is right — a keyword with no sale should queue, and its repair is a cut that saves money by
  parking), or give the rank a term for money burned with no return. (2) Should "dollars at stake"
  be real at all? As written it cannot be, because the second factor already divides by the first.
  If Ori wants money weighted, the second factor has to be an absolute gap rather than a ratio —
  ranking on the gross-profit **shortfall** per day, `spend/day × (bar − return)/bar`, which does
  not cancel and which scores a no-sale keyword at its full spend instead of at zero, answering
  both questions in one line. Nobody has ruled, and Task 2 hands out seats in the order above.
- **The holdout is named in words, not only in a column** (v27.134). `holdout` is TRUE only from the
  campaign's `eligible_from`, so a holdout campaign judged *before* that date is a candidate today
  and silent tomorrow. The sentence used to promise those rows a seat with no mention of the
  holdout, and `C13` ("the holdout is never a candidate") passed only because no campaign had
  reached its date — a vacuous check on exactly the arm that would break. `holdout_member` is TRUE
  for membership at any date, the sentence names the holdout and its date wherever it names a seat,
  and `C15` asserts that on live rows today.

### Deploy and verify

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql)"
```

The acceptance is **twenty-two** checks and **every row must read PASS**: the fenced complete-days
window (C01), the universe (C02), the keyword grain (C03), both plans' sides (C04), the
correction's honesty (C05, C09, C10), the asymmetric guard including its service precondition
(C06), the order floor read on observed orders and `decided_by` always named (C07), a usable price
/ seat cost / rank on every not-good row (C08), a plain sentence, a declared arm and a declared
park source on every row (C11), P-5 as written — one quiet window held and grace never granted
twice in a row (C12), the holdout never a candidate (C13), **no executable price or seat cost on
the good side (C14)**, **the holdout named in words wherever a seat is named (C15)**, **a park
price at or above its floor with a declared source on every candidate (C16)**, **no arm
claiming work it did not do (C17)**, and the five added in v27.135: **a seat promised in words only
to a row that competes for one (C18)**, **a not-good keyword with no seat and no queue position
saying so (C19)**, **a protected window that sold nothing saying it sold nothing, whichever ruling
protects it (C20)**, **P-7's two named factors published with the score as their product (C21)**,
and **the GRACE sentence stating whether the one-window limit is armed (C22)**.

C13 is vacuous until a holdout campaign reaches its `eligible_from`; C15 is the one that bites
today, and the two are read together. C14, C15, C16 and C17 were each run against the v27.133 view
before the v27.134 repair and each read FAIL. C12-restated, C18, C19, C20 and C22 were each run
against the v27.134 view before the v27.135 repair and each read FAIL (36 / 41 / 195 / 45 / 3
violations); C21 could not run at all, because the columns it asserts did not exist.

**C12 was a tautology and is not any more.** It used to assert that a ladder-settled winner with a
quiet window sits on the good side — which the branch order guaranteed by putting the guard first,
so the check read 0 for the wrong reason, exactly the structural vacuity this SOP condemns in C13.
It now asserts the ARM THAT ANSWERS: such a row must read `verdict = 'GRACE'`, so if anything takes
P-5's population back, C12 goes red.

`FACT_PLAN_NEXT_WEEK` is `CREATE TABLE IF NOT EXISTS` — re-running the file can never drop a
written plan. It is created in this task because the guard reads last night's side from it; until
the builder runs it is empty and the guard falls back to the declared bootstrap (the ladder's own
settled record clearing the bar with the window's order floor met).


## 3. The nightly builder (Task 2, v27.136 · repaired v27.137 and v27.138)

`SP_BUILD_NEXT_WEEK_PLAN` reads `V_PLAN_WINDOW_JUDGMENT` once and turns the judgement into money.
It writes one partition of `FACT_PLAN_NEXT_WEEK` per night — **both plans**, `B` live and `A` in
shadow (P-9) — and nothing else. It is idempotent (it rewrites only today's `as_of`) and
deterministic (every ordering reaches the keyword key). Orchestrator step **20.8c**, after the seat
ledger at 20.8b, because a continuing occupant's seat number comes from the ledger that step
maintains and the judgement reads the snapshot 20.8 writes.

### The seven steps, and where each ruling lives

| step | what it does | ruling |
|---|---|---|
| 1 POT | the **GOOD side's** window spend per day, per family. Not the family total, and not a budget anyone set — it is what the good keywords actually bought. | P-2 |
| 2 ALLOWANCE | `allowance_share × pot`. The share and the window come from `DE_PLAN_CONFIG` for today's calendar state; neither is a literal anywhere in the procedure. | P-2, P-13 |
| 3 RAMP | close **one third of the gap** between today's not-good spend and the allowance this window. A family already inside its allowance gets the full allowance and is never ramped *upwards* into a bigger loss budget. Recomputed from actual spend every night, so the sequence converges whether or not anyone uploads on schedule. | P-8 |
| 4 SEATS | candidates ranked, each costing its spend **at the repaired price**, walked in rank order: a candidate takes the lowest free seat **whenever its own cost fits the allowance still unspent**, and one it cannot afford is skipped rather than closing the queue behind it. The walk is a recursive rank walk over a total order, so it is exactly as reproducible as a prefix sum and does not park candidates the allowance can pay for. | P-6, P-7, §4.4 |
| 5 QUEUE | everything that did not fit: parked at the engine park price, **held** at the price it already has when that is at or below the park price (nothing to upload), or **paused only when the ladder has already closed the keyword** (`ladder_state = 'DEAD'`). | §4.5 |
| 6 MOVES | exactly one executable instruction per **candidate**; none on the good side. | P-4, §4.6 |
| 7 BUDGETS | the sum of the campaign's planned spend, ramped one step, floored at **that same sum** — the campaign's good side plus the seats the plan seated inside it — snapped out of the forbidden $20.01–$31.99 band, floored at $1.00. | §4.7 |

**Seat numbers are the ledger's, not the plan's — and a number is FREE only when the ledger has
freed it.** A continuing occupant keeps the number `DE_FAMILY_SEAT_LEDGER` holds for it; a new
occupant takes the family's lowest number **no open ledger row is holding** (`closed_on IS NULL`
means occupied, whether or not tonight's plan seats that occupant). If two open ledger rows ever
claim one number, the better-ranked keyword keeps it and the other is admitted as new — so "numbered
exactly once" cannot be broken by a ledger inconsistency. `C17` compares the plan's numbering with
the register's, and the builder asserts it before it writes; read the two side by side with:

```sql
SELECT p.family, p.seat_no, p.target_text AS plan_occupant, l.keyword_id AS ledger_occupant
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
LEFT JOIN (SELECT family, CAST(keyword_id AS STRING) keyword_id, MIN(seat_no) seat_no
           FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL GROUP BY 1, 2) l
  ON l.family = p.family AND l.seat_no = p.seat_no
WHERE p.as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
  AND p.is_live_plan AND p.seat_no IS NOT NULL AND l.keyword_id != p.keyword_id;
```

**A repair can be a RAISE, and the plan says which on the row.** A seat costs its spend *at the
repaired price* (P-6), and the repaired price is the ladder's affordable price — which is sometimes
above today's bid. So the plan can add money to a family's not-good side while staying inside the
allowance, and a family whose allowance exceeds its whole not-good side has no ranking pressure to
stop it. `planned_spend_delta_per_day` is that number on every row and the seat sentence prints it
in words. Read the direction per family before any upload — a family reading positive is one the
plan is spending MORE on, not less:

```sql
SELECT family,
       ROUND(SUM(IF(seat_no IS NOT NULL, planned_spend_delta_per_day, 0)), 2) AS seats_delta_per_day,
       COUNTIF(seat_no IS NOT NULL AND planned_spend_delta_per_day > 0.005)   AS seats_that_raise,
       ROUND(MAX(notgood_today_per_day), 2)                                   AS notgood_today,
       ROUND(MAX(allowance_ramped_per_day), 2)                                AS allowance_this_window
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan
GROUP BY 1 ORDER BY 2 DESC;
```

**The queue's residual is not zero money.** A queued row's PLANNED spend is zero because parking
lowers a price and does not stop a spend; what the family actually keeps paying until the park price
bites is the difference between its real not-good spend and the seats' cost. §9's reconciliation is
restated to the identity that holds (`C19`), and whether the arithmetic should carry the residual
instead is one of Ori's open rulings below.

**The ramp is geometric, not linear, and three windows is not the whole gap.** One third of the
*remaining* gap closes each window, exactly like the three-step bid cap, so after three windows
about seventy per cent of the original gap is closed and the rest follows. Anybody who reads
"ramped over three windows" as "arrives at the allowance on the third upload" will be wrong by the
last third. Read where a family actually is:

```sql
SELECT family, MAX(notgood_today_per_day) AS notgood_day, MAX(allowance_target_per_day) AS allowance_day,
       MAX(allowance_ramped_per_day) AS this_window_day, MAX(ramp_step) AS step_of, MAX(ramp_steps) AS steps
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan
GROUP BY 1 ORDER BY 2 DESC;
```

### Writing this table ARMS two rulings

`V_PLAN_WINDOW_JUDGMENT` reads `FACT_PLAN_NEXT_WEEK` back as the plan's **memory**. From the night
after the first write, the live rows' `side` is the P-14b guard's "was good" (the ladder is only the
bootstrap for a keyword the plan has never seen), and `verdict = 'GRACE'` **spends** P-5's one quiet
window. So the builder writes `GRACE` as `GRACE` and never collapses it into `GOOD`: a builder that
collapsed it would silently restore the permanent exemption §2 describes. `C13` of the acceptance
asserts the live plan reproduces the view row for row on `side`, `verdict` and `is_candidate`, which
is the check that stands over this. Confirm the limit is armed the morning after a first run:

```sql
SELECT DISTINCT grace_limit_armed FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

### What Ori still rules — four readings this builder had to make

1. **The holdout is outside the money, not only outside the sheet.** A holdout campaign's spend is
   excluded from the pot, from the not-good side and from the ramp base: a measurement control's
   money is not the plan's to allocate. It still gets a row, a side and a sentence — the
   counterfactual — and no move. No campaign is eligible before 2026-09-01, so this costs nothing
   today and everything afterwards. *To overrule:* drop `AND NOT holdout` from the `fam` aggregation.
2. **A not-good keyword with nothing to repair gets no move** (spec §9, v27.135): no spend, no
   clicks, no probe nomination means no seat, no queue position and `move = 'NONE'`. Parking a
   keyword that spends nothing saves nothing.
3. **The shadow cannot always be priced.** P-4 makes the judgement view withhold `planned_bid` and
   `seat_cost_per_day` wherever *rule B* calls the row GOOD. Some of those rows are not good to the
   *ladder*, so plan A wants to price a keyword the live plan protects. Rather than compute the
   repaired price a second time — the "one keyword, two prices" defect — the shadow holds such a row
   at its current price, costs its seat at its current spend, and says so on the row. Plan A is never
   uploaded. *To fix properly:* publish the unmasked price under a second name in the judgement view,
   never a second formula here.
4. **The implied budget sees only the plan's own keywords.** Brand defense, launch-contained keywords
   and non-keyword targets are outside the universe (§8), so a mixed campaign's implied budget is
   below its real need. That is why the budget is **ramped** from today's budget rather than set to
   the implied figure, and floored at **the plan's own spend inside that campaign** — its good side
   plus the seats the plan seated there. A cap under the good side is a cut and P-4 forbids cuts; a
   cap under the seats is a promise the move cannot keep, which is what v27.136 published on six
   campaigns before the repair. Read the campaigns where the two disagree most before any upload:

```sql
SELECT campaign_name, MAX(campaign_current_budget) AS today_budget,
       MAX(campaign_planned_budget) AS planned, ROUND(SUM(planned_spend_per_day), 2) AS implied_from_plan_keywords
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan
GROUP BY 1 ORDER BY ABS(MAX(campaign_planned_budget) - MAX(campaign_current_budget)) DESC LIMIT 20;
```

### The question this layer answers, and the query that answers it

"Will this take the not-good side down to the allowance?" cannot be answered from the plan alone,
because **the side the plan judges is not the side the doctrine's arithmetic was quoted on**. P-5
grace and the P-14b guard move real money onto the GOOD side, which both shrinks the queue and — since
the pot is the good side's spend — *enlarges* the allowance rationing it. Both halves must be read
together or the plan looks either far too tight or far too loose:

```sql
SELECT ROUND(SUM(w_sp) / MAX(window_days), 2)                                AS universe_per_day,
       ROUND(SUM(IF(verdict = 'GOOD', w_sp, 0)) / MAX(window_days), 2)       AS good_p3_alone,
       ROUND(SUM(IF(verdict != 'GOOD', w_sp, 0)) / MAX(window_days), 2)      AS notgood_p3_alone,
       ROUND(SUM(IF(side_b = 'GOOD', w_sp, 0)) / MAX(window_days), 2)        AS good_as_the_plan_judges_it,
       ROUND(SUM(IF(verdict = 'GRACE', w_sp, 0)) / MAX(window_days), 2)      AS moved_by_grace,
       ROUND(SUM(IF(verdict = 'HELD_UNSETTLED', w_sp, 0)) / MAX(window_days), 2) AS moved_by_the_guard,
       COUNTIF(settle_arm = 'PROMOTED_ON_FRESH')                             AS promoted_by_the_correction
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

`promoted_by_the_correction` is the one to look at before ruling on P-14: arm (a) lifts the whole
book's gross profit, but it can only carry a keyword across a bar that keyword already has the orders
to reach, and the overstatement Ori described lives *behind* the order floor. If that column reads
zero, every dollar the guard protects was protected by arm (b) alone, and the open ruling is whether
the ORDER FLOOR should bend for an unsettled window — a change to P-3, not to P-14.

### Deploy and verify

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
```

Twenty-one checks, every row `PASS`. Ten assertions fire inside the procedure and name the
guarantee they protect — **fix the arithmetic, never the assertion.** They run **before the
partition is touched**: the rows are built into a temp table carrying the fact table's own schema,
the assertions read that, and only a clean build reaches the `DELETE`/`INSERT`. A failing build
therefore leaves *yesterday's* plan standing, which is the safe state — stale and correct beats
fresh and wrong. (v27.136 deleted, inserted and only then asserted, inside the orchestrator's
`BEGIN … EXCEPTION WHEN ERROR THEN` wrapper, so a broken guarantee left the violating partition
committed and the pass carried on.) Idempotence is proved by
running the CALL twice and comparing a fingerprint of the partition, not its row count alone:

```sql
SELECT COUNT(*) AS n, ROUND(SUM(planned_spend_per_day), 4) AS spend,
       FARM_FINGERPRINT(STRING_AGG(CONCAT(plan, campaign_id, keyword_id, move,
              CAST(COALESCE(seat_no, -1) AS STRING), CAST(ROUND(planned_spend_per_day, 4) AS STRING))
              ORDER BY plan, campaign_id, keyword_id)) AS fingerprint
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = CURRENT_DATE('America/Los_Angeles');
```

(Both runs must land in the same Los Angeles day and behind the same ads watermark; if the watermark
moved between them, re-run both.)

### Four checks that depart from the plan's draft, and why

- **C01** asserts the P-14a **fence** (`window_to = LEAST(watermark − 1, as_of − 2)`), not
  `watermark − 1`. The draft's form fails by construction after 22:00 Los Angeles, when
  `FN_ADS_ANCHOR_CAP()` advances and the fence gives up a day on purpose.
- **C06** reads **candidacy**. The draft required one of four moves on every not-good row; §9
  (v27.135) says the guarantee is about candidates, and a keyword with nothing to repair takes no
  seat, no queue position and no move.
- **C09** carries the guard's **service clause** (v27.134, T1's C17): a keyword that took no spend and
  no clicks has no sales in flight, so P-14b has no basis and does not fire — and the draft's form
  failed on exactly those rows on the live view before a line of the builder was written.
- **C11** adds the half that protects P-4: a campaign's planned budget may never sit under the
  good-side spend inside it — nor, from v27.137, under the plan's *own* spend inside it. A cap below
  the good side is a cut; a cap below the seats is a move the budget cannot pay for.

### Checks added or restated in the repair passes

Each went red on the deployed v27.136 partition before the repair and green after it; the violation
counts live in the task report, never on this page.

- **C10** was written as "every *repriced* seat carries a verdict date". P-12 says **every seat**,
  and a seat held at its current price — allowance spent, nothing uploaded — is exactly the parking
  lot the ruling exists to prevent. The narrowing was in the check, the procedure, the header and
  the registry entry; all four now say what P-12 says.
- **C17** compares the plan's seat numbers with `DE_FAMILY_SEAT_LEDGER`'s **open** rows. `C05` tests
  uniqueness inside the plan's own partition and can never see a number the register is still
  holding for someone else.
- **C18** asserts the seat walk is §4.4's **fit test**: after the walk, no queued candidate's cost
  fits the allowance the family has left. Greedy skip-and-continue makes that invariant true by
  construction, because the remaining allowance only falls as the walk proceeds.
- **C19** is §9's reconciliation restated to the identity the arithmetic can hold — the not-good
  side's PLANNED spend equals the seats' cost, and every candidate has exactly one of a seat or a
  queue position. The original wording ("seats + queued = the not-good side") was asserted by none
  of the sixteen v27.136 checks and does not hold with a queue planned at zero.
- **C20** asserts `planned_spend_delta_per_day` is exactly planned minus current, so a plan that
  RAISES a family's not-good spend says so in a column.
- **C21** asserts `PAUSE` fires only where the ladder has already closed the keyword (§4.5's "paused
  if already closed"), and that a paused row carries **no** planned bid for a book to upload.

### What the v27.137 pass changed in the money, and what it did not

Nothing in the doctrine moved: the bar, the floors, the ladder, the pot, the share and the ramp are
untouched. What moved is **which candidates get seats inside the allowance that was already
declared** (the fit test seats the cheap candidates a prefix stop was parking), **which seat numbers
they are called by** (the register's, not the plan's), **which queued keywords are paused** (only
those the ladder has closed), **what the campaign cap will pay for** (the seats the plan itself
opened) and **whether a build that breaks a guarantee can reach the table** (it cannot). Re-read the
per-family picture after any run rather than trusting this paragraph:

```sql
SELECT family, ROUND(MAX(allowance_ramped_per_day), 2) AS allowance_this_window,
       COUNTIF(seat_no IS NOT NULL) AS seats,
       ROUND(SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)), 2) AS seat_cost_per_day,
       COUNTIF(is_candidate AND seat_no IS NULL) AS queued,
       ROUND(MAX(notgood_today_per_day), 2) AS notgood_today
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan
GROUP BY 1 ORDER BY 1;
```

### What the v27.138 pass changed, and the queries that read it

Again nothing in the doctrine moved. Five things did, and each is a number a reader can pull:

1. **A keyword the ladder has CLOSED is no longer seatable.** `DEAD` was tested only after the two
   seat branches, so whether a closed keyword was stopped or re-priced depended on whether its cost
   happened to fit — one partition carried both instructions at once. The seat walk now refuses it,
   `PAUSE` is decided first, and `C22` asserts the converse `C21` never tested.
2. **Seat numbers survive the night.** The register only admits ladder occupant states, so the
   plan's `AT_BAR` and `DEAD` seats can never hold an open ledger row and were re-numbered from an
   index into that night's rank order. Precedence is now register > last night's plan > lowest free
   number (`C23`).
3. **The campaign cap stopped cutting what the plan cannot see.** The floor is the good side + the
   seats + the queue's continuing spend, and a campaign the plan measured nothing in — or a brand
   defense campaign — is not moved at all (`C11`, `C24`).
4. **The cap says its own move.** Every row carries `campaign_planned_budget_delta_per_day`,
   `campaign_budget_basis` and `campaign_visible_spend_per_day`, and prints all three.
5. **Every seat sentence names the direction**, not only the repriced ones (`C25`).

```sql
-- what the caps did tonight, by the reason the plan gives
SELECT campaign_budget_basis, COUNT(*) AS campaigns,
       ROUND(SUM(GREATEST(d, 0)), 2) AS raises_per_day,
       ROUND(SUM(GREATEST(-d, 0)), 2) AS cuts_per_day
FROM (SELECT DISTINCT campaign_id, campaign_budget_basis,
             campaign_planned_budget_delta_per_day AS d
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
      WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
        AND is_live_plan)
GROUP BY 1 ORDER BY 1;

-- the guard's clock: who is held, since when, and when the hold lifts (P-14b, v27.138)
SELECT verdict, COUNT(*) AS kw, MIN(hold_since) AS oldest_hold,
       MIN(hold_settles_on) AS next_lift, COUNTIF(hold_expired) AS clock_run_out
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1 ORDER BY 2 DESC;
```

### What Ori rules from this pass

1. **The queue's residual.** A queued keyword's planned spend is zero and its real spend is not.
   §9's reconciliation is restated (`C19`) rather than left as a claim nothing checked. *To
   overrule:* make `planned_spend_per_day` on a queued row the spend it will keep making at the park
   price, and re-derive `C05`, `C07`, `C15` and `C19` — the plan's not-good total would then read as
   the money at risk rather than as the money the plan intends.
2. **A seat that raises.** P-6 costs a seat at the repaired price, and the ladder's repaired price
   can be above today's bid; where a family's allowance exceeds its whole not-good side, nothing in
   the ranking stops the plan spending more there. It is now published per row and per family
   (`planned_spend_delta_per_day`). *To overrule:* forbid a seat whose repair raises the spend, or
   cap the book's total raise — either is one predicate in step 4, and neither is in the spec today.
3. **P-7's degenerate rank still hands out the seats** (§2's open ruling, unchanged): every
   spend-with-no-sale keyword scores exactly zero, so the biggest bleeders rank last. The fit test
   now lets cheap candidates behind them take seats, which *reduces* the damage but does not fix the
   ordering.
4. **P-14b IS NOW A DELAY WITH A CLOCK, AND THAT IS A READING, NOT A RULING ORI MADE.** The guard
   was a permanent veto: `was_good` reads last night's SIDE, a held row's side is GOOD, and the
   window rolls so `settled` is never true — so the protected side was a one-way door, the ladder
   gate the spec attributes the guard to stopped applying after night one, and P-5's one-window
   limit went inert in money. The hold is now anchored to the window that TRIGGERED it and lifts
   when that window settles, which is the literal reading of "not demoted until ITS window has
   settled". *To overrule (either direction):* restore the unlimited veto by dropping `hold_expired`
   from the `HELD_UNSETTLED` branch; or go the other way and demote on the last window that HAS
   settled while promotion keeps reading the fresh one. Both are one line in
   `V_PLAN_WINDOW_JUDGMENT`. **P-14 as a whole is still unruled** and is still the biggest number
   in the plan.
5. **May a brand-defense campaign be judged at all?** The live defense campaign reaches the plan
   because the ladder's `is_brand_defense` reads FALSE on all five of its keywords, so §8's filter
   in the judgement view does not catch it: it is published `NOT_GOOD` and, before this pass, its
   cap was cut. The budget step now detects defense the way the seat register does (the flag OR
   "BRAND DEFENSE" in the campaign name) and refuses to move its cap. *To overrule / to finish:*
   fix the FLAG in the ladder snapshot so the judgement view excludes those keywords from the
   universe entirely — a Task 1 / ladder file, recorded here rather than patched from the builder,
   because widening candidacy inside the builder would break `C13`.
6. **The book and the plan now read one grace memory.** `tools/build_reprice_bulksheet.py --rule-b`
   reads `FACT_PLAN_NEXT_WEEK` for P-5's one-window limit with the same expression
   `V_PLAN_WINDOW_JUDGMENT` uses, so the two cannot grant and refuse the same grace. Nothing to rule
   unless Ori wants the book to stop judging at all and read the plan's `side` directly — which is
   Task 4's design question, not a defect.

## 4. Ownership and the preflight (Task 3) — to be written

## 5. The plan book (Task 4) — to be written

## 6. Grading, health and the surfaces (Tasks 5–7) — health built v27.152; grading built v27.154; the surfaces to be written

### Health (Task 5's second half, v27.152, 2026-10-01)

**What happened, and why this half shipped before the grade.** `SP_BUILD_NEXT_WEEK_PLAN`
failed every pass from 2026-08-29 to 2026-09-28 — first on the P-14b assertion the builder
re-derived from the guard's preconditions (§2, "the guard's clock"), then on §9's seat-number
stability (C23). `LOG_PIPELINE_RUNS` logged every one of those failures. The Admin page's sidebar
dot reflected the latest pass. Nothing on `V_DAILY_BRIEF` — the one query Ori reads every morning
— said a word, and `V_ENGINE_HEALTH` already showed three REDs nobody acted on, so a RED there is
necessary and not sufficient. The grade (`V_PLAN_SCORECARD`, Task 5's first half) is still to be
built; what shipped first is the alarm, because a learning system that does not notice it stopped
saving its decisions is not learning.

**The checks** live on `V_ENGINE_HEALTH` (c23–c32; the board's ritual query is in
`ENGINE_HEALTH.md`, which also carries each check's threshold in words). They read the plan's
latest partition, the proposal snapshot and the gate table — never `V_PLAN_WINDOW_JUDGMENT`,
which re-anchors the moment the ads watermark moves, and never a ceiling view. Every partition
check reads RED on an empty partition rather than vacuously green.

| check | reads | status |
|---|---|---|
| `plan_window_complete_days` | the fence: `window_to = LEAST(watermark − 1, as_of − 2)` and `window_days` long (the Task 5 draft's `watermark − 1` fails after 22:00 Los Angeles — §2 "why it is fenced") | red > 0 |
| `plan_pot_reconciliation` | pot = good-side spend outside the holdout, allowance = share × pot, to the cent (the acceptance's C03/C04 form; the draft counted holdout spend into the pot) | red > 0 |
| `plan_one_move_per_notgood` | one move per CANDIDATE, NONE on the good side and on rows with nothing to repair (§9 v27.135, the acceptance's C06 form; the draft read 152 violations on a healthy partition) | red > 0 |
| `plan_ownership_no_foreign_go` | foreign GO rows on money levers inside live-plan campaigns — **a REPORT until Task 3 ships**, because no engine `PLAN` writes proposals and the plan owns nothing at the gate yet | INFO, then red > 0 |
| `plan_both_plans_written` | exactly plans A and B in the latest partition | red otherwise |
| `plan_settle_guard_holds` | **P-14b is a clock and P-14c a last-day test, not a veto.** A live-plan row demoted under the guard's preconditions (not-good, was good, served, unsettled) is legitimate iff the judge published `guard_released_by` as `HOLD_EXPIRED` or `LAST_DAY_NOT_STRONG`; a `HELD_UNSETTLED` row must have earned the hold with a very good last day. The check READS `guard_released_by` and never re-derives the guard — re-deriving it is what vetoed every partition for a month | red > 0 |
| `plan_settle_curve_coverage` | share of live-plan rows the curve could correct | INFO |
| `plan_proposal_lag_days` | the proposal snapshot's date against the live plan's | INFO, amber > 2 |
| `plan_partition_fresh` | **ALARM.** The latest plan is older than the later of yesterday and the Los Angeles day the plan step last ran, OK or FAIL. Not "older than today": the pass runs three times a day and the first that can write today's partition is the 04:10 New York one, so "today" alone would be red between midnight and that pass every day. The detail says the last plan date and the nights missing | red > 0 |
| `pipeline_step_failing` | **ALARM, GENERIC.** Any procedure whose three most recent runs in the last 30 days all logged FAIL, with the first 120 characters of its latest error and the length of the streak. This is the check that would have named the builder on day 1 of the outage, and the next outage needs no new check | red > 0 |

**The surface.** `V_DAILY_BRIEF` carries one SYSTEM line (section_rank 7, appended) that reads
the board LIVE — never an image, which goes stale exactly when the pipeline that builds it stops —
and folds its RED rows into one sentence, the two alarms first and quoted with the board's own
detail. The action says A NIGHT WAS NOT SAVED when either alarm is RED. `DAILY_BRIEF.md` has the
row shape and the reasons.

**Deploy and verify.**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_DAILY_BRIEF.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql)"
```

The acceptance carries its negative controls as standing checks: a twin of each alarm's
expression run over doctored temp copies (a healthy step's three most recent runs set to FAIL
must be named, two of three must not; the latest partition dropped must read RED; a release
nulled and a hold weakened must each count 1) and tied to the deployed view's live reading so the
twin cannot drift. The measured results of the first run are in the file's header.

**What this half does not do.** It does not grade the plan (`V_PLAN_SCORECARD`), does not record
the rule settings' history (the 1.5× `strong_day_mult` and the 1-order `strong_day_min_orders` in
the judgement view's `k` CTE are still literals; since the v27.154 follow-up each plan row carries
the values it was judged under, see §2 "The last-day test"), and does not re-run a failed step —
nothing does; the line says so.

### Grading (Task 5's first half, v27.154, 2026-10-01)

**What it answers.** Two questions, both read from what the plan WROTE that night and never from the
judgement view (which re-anchors the moment the ads watermark moves):

1. **Which plan puts its dollars where the money turned out to be?** Plans A and B are written every
   night on the same keywords; nobody compared them until now.
2. **Is the 1.5× last-day test (P-14c) holding the right keywords?** Every hold and every release is
   graded once the window it judged has settled.

| object | file | what it is |
|---|---|---|
| `FN_PLAN_SCORECARD(grade_date DATE)` | `scripts/bigquery/functions/FN_PLAN_SCORECARD.sql` | the grade, as a table function so the acceptance can run the SAME arithmetic with the clock moved forward (the guard has nothing old enough to grade until 2026-10-03) |
| `V_PLAN_SCORECARD` | `scripts/bigquery/views/V_PLAN_SCORECARD.sql` | the function at today's Los Angeles date — the one to read |
| acceptance | `scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql` | every row must read `PASS` |

**Five row types.**

| row_type | grain | what it says |
|---|---|---|
| `GRADE` | plan × family × calendar state, pooled over the graded nights | the dollars each plan allocated, what the keywords netted in the days that followed, and **net per allocated dollar** |
| `RECOMMENDATION` | family × calendar state | the declared rule applied: `WAIT`, `KEEP_<live>` or `SWITCH_TO_<shadow>`, with a sentence |
| `FAMILY_WEEK` | family × graded night | A and B side by side for one week, so the trajectory is visible and not only the pooled grade |
| `GUARD` | week × outcome class (always all four classes for a week that has a graded decision) | held right / held wrong / released right / released wrong — counts, settled spend and net, and the last day's return (raw and as a multiple of the bar) at p25/p50/p75 |
| `RULE_HINT` | exactly one row | what the GUARD grades say about the 1.5× threshold, or `WAIT` with the reason |

**How a plan is graded.** One plan night per Sunday-start week (the house week) is graded: the latest
night in that week that is at least 14 days old, the longer attribution window. For every keyword in
that night's plan, the allocation is `planned_spend_per_day × window_days`, and the outcome is what
the keyword netted (`GROSS_PROFIT − Ads_cost` in `FACT_AMAZON_ADS`, read today) over the
`window_days` days starting on the plan night. **How settled that is:** the 14-day rule is on the
plan night, so with a 7-day window the last day read is 8 days old at the earliest grade — past SP's
7-day attribution window, inside SB's 14 — and the newest graded week can still move a little as SB
orders land (the guard grade below waits for each window's own settle date instead). A plan's score is

```
net per allocated dollar = Σ allocation_k × (net_k / spend_k)  /  Σ allocation_k
```

— each allocated dollar is credited with what one ad dollar on that keyword actually netted in the
days that followed (zero where the keyword spent nothing; those dollars are published as
`allocated_unrealized_dollars`). A plan that puts more of its dollars on keywords that went on to make
money scores higher. It assumes a dollar placed on a keyword earns what that keyword's dollars
actually earned; the effect of the plan's own price change is not modelled (that is the learning
contract's response model, piece 2), and neither plan has been uploaded yet, so this grades where
each plan WOULD have put the money.

**Why this is not the plan draft's formula.** The draft divided the keywords' total realized net by
the plan's total allocation. Plans A and B are written on the **same keywords** every night, so that
numerator is identical for both plans and the draft's comparison reduced to which plan allocated
fewer dollars — the larger plan "won" whenever the family lost money and lost whenever it made money,
whatever it did with the dollars. `realized_net` is still published on every GRADE row (it is the
same for A and B by construction); check the identical-keyword premise any time:

```sql
SELECT a.as_of, COUNT(*) AS keyword_pairs,
       COUNTIF(b.keyword_id IS NULL) AS a_only, COUNTIF(a.keyword_id IS NULL) AS b_only
FROM (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'A') a
FULL OUTER JOIN (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B') b
  ON a.as_of = b.as_of AND a.campaign_id = b.campaign_id AND a.keyword_id = b.keyword_id
GROUP BY 1 ORDER BY 1;
```

**The decision rule (P-9), declared in the function's `k` CTE.** With at least **3** graded weeks in
a calendar state, if the shadow plan's net per allocated dollar beats the live plan's by at least
**10% of the live plan's magnitude**, the row says `SWITCH_TO_<shadow>`; otherwise `KEEP_<live>`.
The draft wrote the margin as `shadow ≥ live × 1.10`, which is right only while the live score is
positive: at −0.50 it would switch to a shadow scoring −0.54, a worse plan. The live plan is read
from the graded rows' `is_live_plan`, not assumed to be B. **Ori flips `DE_PLAN_CONFIG.live_plan`;
the code never switches itself.**

**How the guard is graded (P-14b / P-14c).** Every live-plan row written under the last-day test
(it carries `last_day_strong`) that the judge HELD (`verdict = 'HELD_UNSETTLED'`) or LET THROUGH
(`guard_released_by` is `LAST_DAY_NOT_STRONG` or `HOLD_EXPIRED`) is graded once its own
`settle_due_on` has passed — 7 complete days after the window for SP, 14 for SB. The grade re-reads
**the same window** (`window_from … window_to`) from `FACT_AMAZON_ADS` today: settled good = at least
the order floor in force when the plan was built (`DE_PLAN_CONFIG.min_orders`, the row in force at
`built_at`) and gross profit per ad dollar at or above the row's `family_bar`. The grade READS the
judge's published decision; it never re-derives the guard. Each night's decision is graded on its own
window, so a keyword held three nights running is three graded decisions; `keywords` counts the
distinct ones beside them.

**The hint on the 1.5×.** Below **20** graded decisions the RULE_HINT row says `WAIT` and why — with
nothing old enough to grade it says how many decisions have been written and the date the first one
settles. The hint is about **the rule in force**: the `strong_day_mult` and `strong_day_min_orders`
the live plan's latest partition was judged under, read from the plan rows (`rule_value`,
`rule_min_orders`). It reads only decisions made under that rule, in two groups: keywords **held**,
and **the band**: keywords **released** by the last-day test whose last day sat between 1.0× the bar
and that decision's own multiplier, with at least that decision's own order minimum on that day, and
**whose hold clock had not run out** (`hold_expired`, as the judge published it). Those are the ones
a lower threshold would have held. The clock term matters because the judge names a release
`LAST_DAY_NOT_STRONG` before it looks at the clock, so a keyword whose hold had already run out also
carries that name when its last day was not very good; a lower threshold would still have let it
through, this time as `HOLD_EXPIRED`, so it says nothing about the threshold. Before the fix of
2026-10-01 (Los Angeles time) the band counted those releases too. On the plan history to
2026-10-01 that was 2 of the 4 rows the band counted, and 40 of the 104 `LAST_DAY_NOT_STRONG`
releases had a clock that had run out. Count them again any time:

```sql
SELECT COUNT(*) AS last_day_not_strong, COUNTIF(hold_expired) AS clock_had_run_out,
       COUNTIF(SAFE_DIVIDE(last_day_ret, NULLIF(family_bar, 0)) >= 1.0
               AND SAFE_DIVIDE(last_day_ret, NULLIF(family_bar, 0))
                   < COALESCE(strong_day_mult, IF(as_of <= DATE '2026-10-01', 1.5, NULL))
               AND last_day_ord >= COALESCE(strong_day_min_orders, IF(as_of <= DATE '2026-10-01', 1, NULL))
               AND NOT COALESCE(hold_expired, FALSE)) AS in_the_band
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE is_live_plan AND last_day_strong IS NOT NULL AND guard_released_by = 'LAST_DAY_NOT_STRONG';
```

(The 1.5 and 1 read rows written on or before 2026-10-01, before the plan table stored the rule, as
the function does. This counts every night written, graded or not; the hint counts only the graded
ones made under the rule in force.) Graded decisions made under a different or unrecorded rule stay
in the GUARD rows and are counted on the hint row as `other_rule_rows`.

**Each group needs at least 10 graded decisions** (`min_group_rows`, declared in the function's
`k` CTE; **Ori rules on the number**) before the hint says anything but `WAIT`. 20 in total is not
enough: on the real history 108 of the first 117 decisions are releases and 9 are holds, and 2 of
the releases sit in the band (4 did before the clock term above). The review of v27.154 measured
the total-only gate saying KEEP at the 2026-10-03 clock from 0 holds and 1 band row, and RAISE at
10-05 from 2 holds. That one band row was a release whose hold clock had run out, so under the band
as it is now the band at 2026-10-03 is empty.

**What 10 buys, and the ruling it needs.** Take a group whose true wrong-rate is 30%, which is not
"more than half". The chance that it reads "more than half wrong" anyway, by luck, is (binomial,
computed with exact fractions on 2026-10-01, Los Angeles time): 5.8% at 8 rows, 9.9% at 9,
**4.7% at 10**, 7.8% at 11, 3.9% at 12, 6.2% at 13, 3.1% at 14, 5.0% at 15. 10 is the smallest
group size at which the chance is under 5%. It does not fall steadily as the group grows, because
"more than half" of an odd number of rows needs proportionally fewer wrong rows than of the even
number below it: 7.8% at 11, 6.2% at 13, 5.0% at 15. It is under 5% for every size from 16 up (computed for every size to
400). The first verdicts that are not `WAIT` will come from groups just past the minimum, so this
matters for the first rulings. Ori's options, none of which the code takes on its own:
- **keep 10**: for such a group, a false alarm about 1 time in 20 at 10 rows, and up to about 1 in
  13 at 11 rows;
- **16**: under 1 in 20 at 16 rows and at every size above it, and the hint waits longer for its
  first verdict;
- **"at least half" instead of "more than half"**: this makes chance alarms more frequent, not
  less: 15.0% at 10 rows, and under 5% at every size only from 19 up (also computed to 400).

Below the minimum the row says `WAIT`, names the group that is too small and its count. From the
minimum on: if released-wrong is more than half of the band, the threshold looks too high
(`LOWER_STRONG_DAY_MULT`); if held-wrong is more than half of the held, too low (`RAISE_STRONG_DAY_MULT`); both at once is `NO_CLEAN_SIGNAL`; neither is
`KEEP_STRONG_DAY_MULT`. Each sentence leads with the size of the group it argued from, then the
counts and the dollars. On the history to 2026-10-01 no clock reaches 10 holds or 10 band rows, so
every reading is `WAIT` today; the four non-WAIT verdicts have come out of the function only on
doctored copies of the plan table (`scripts/bigquery/tests/check_plan_scorecard_hint_branches.py`;
the acceptance's header records the run). It is a hint: the threshold lives in
`V_PLAN_WINDOW_JUDGMENT`'s `k` CTE and nothing here changes it. The scorecard keeps no copy of it:
it reads the value stored on each plan row, and acceptance C10 checks every row written after the
columns existed carries one, that a night carries one rule, and that `rule_value` is the latest
night's. Acceptance C13 checks the band counts exactly the releases a lower threshold would have
held, never one whose hold clock had run out.

**Read it.**

```sql
-- the recommendations and the guard's grade
SELECT row_type, family, calendar_state, graded_windows, graded_rows, recommendation, sentence
FROM `onyga-482313.OI.V_PLAN_SCORECARD`
WHERE row_type IN ('RECOMMENDATION', 'RULE_HINT') ORDER BY row_type, family, calendar_state;

-- the weekly trajectory, A and B side by side
SELECT family, week_start, graded_night, calendar_state, live_plan,
       allocated_a, npd_a, allocated_b, npd_b, realized_net
FROM `onyga-482313.OI.V_PLAN_SCORECARD`
WHERE row_type = 'FAMILY_WEEK' ORDER BY family, graded_night;

-- the guard, week by week
SELECT week_start, outcome_class, class_rows, graded_rows, settled_spend, settled_net,
       last_day_x_bar_p25, last_day_x_bar_p50, last_day_x_bar_p75
FROM `onyga-482313.OI.V_PLAN_SCORECARD`
WHERE row_type = 'GUARD' ORDER BY week_start, outcome_class;
```

**Young by design, and it says so.** On 2026-10-01 only the six August nights (2026-08-23 … 08-28,
one Sunday week) are 14 days old, so GRADE carries one graded week and every RECOMMENDATION reads
`WAIT`. The guard columns exist only from the 2026-09-28 partition, so GUARD is empty and RULE_HINT
says when the first decision settles. The acceptance does not pass on that emptiness: C04 and C08
compare what the scorecard grades with what the plan history makes gradable, and C06 also runs on
the function with the clock moved 30 days forward, where the guard has real decisions to partition.

**Deploy and verify.**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/functions/FN_PLAN_SCORECARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_PLAN_SCORECARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql)"
# the hint's branches, run on doctored copies of the plan table (exit 0 = every branch as expected)
python3 scripts/bigquery/tests/check_plan_scorecard_hint_branches.py
```

The rule columns ship before the judge and the builder that fill them, in this order:
`scripts/bigquery/migrations/2026-10-01_plan_strong_day_rule_columns.sql`, then
`V_PLAN_WINDOW_JUDGMENT.sql`, then `SP_BUILD_NEXT_WEEK_PLAN.sql` (the builder's temp table copies the
plan table's schema, so it needs the columns first, and it reads the two new columns from the judge).

It is a view over a function, not a table: the FACT_AMAZON_ADS reads are clustered joins on a
handful of plan nights, so nothing is materialised and nothing is added to the orchestrator. The
acceptance reads only the nine `plan_*` checks of `V_ENGINE_HEALTH` by name, because a filter on
`check_name` prunes the board's other arms; read the board whole and it costs the full board.

**What this half does not do.** It does not freeze a grade (a view re-reads `FACT_AMAZON_ADS`, so a
graded week moves slightly as late orders land; the learning contract's grader freezes grades), does
not switch a plan, and does not change the last-day threshold. Those are Ori's, by one row each.

### The surfaces (Tasks 6–7) — to be written
