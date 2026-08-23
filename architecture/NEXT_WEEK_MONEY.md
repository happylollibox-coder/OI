# Next Week's Money — SOP

**Spec:** `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` (rulings P-1..P-14)
**Plan:** `docs/superpowers/plans/2026-08-23-next-week-money.md` (Tasks 0..8)
**Status:** Task 0 shipped (v27.130), repaired (v27.131, v27.132). This SOP grows one section per task; Task 8 completes it.

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

Whether 0.50 is the right BOOST share is an open learning question — `V_PLAN_SCORECARD` and the
backtest answer it per state on evidence, and until they do the seed stands.

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
`rule_b()` and, when Task 1 lands, out of `V_PLAN_WINDOW_JUDGMENT`. Nothing else changes.

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

## 2. The judgement layer (Task 1) — to be written

## 3. The nightly builder (Task 2) — to be written

## 4. Ownership and the preflight (Task 3) — to be written

## 5. The plan book (Task 4) — to be written

## 6. Grading, health and the surfaces (Tasks 5–7) — to be written
