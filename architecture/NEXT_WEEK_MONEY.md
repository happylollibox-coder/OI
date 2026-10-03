# Next Week's Money — SOP

**Spec:** `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` (rulings P-1..P-14c; P-15..P-29 ruled 2026-10-02 and built by `docs/superpowers/plans/2026-10-02-money-plan-rulings-piece1.md`)
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
| `DE_PLAN_CONFIG` | `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql` | given a calendar state, how long is the window, what share of the good side does the not-good side get, over how many windows does the allowance ramp, how many orders make a keyword good, which plan is live, and (v27.155) how good the last day must be to earn the P-14b hold (P-14c) |
| `FACT_THRESHOLD_HISTORY` | `scripts/bigquery/tables/FACT_THRESHOLD_HISTORY.sql` | (v27.155) every value this table and `DE_COACH_THRESHOLDS` have held, and when a pass first saw it |
| `FN_PLAN_CALENDAR_STATE(d DATE)` | `scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql` | which calendar state a date is in |
| acceptance | `scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql` | every row must read `PASS` |

### How a reader uses them

Always join, never hardcode. The pattern every plan object follows:

```sql
SELECT c.window_days, c.allowance_share, c.live_plan, c.ramp_steps, c.min_orders,
       c.strong_day_mult, c.strong_day_min_orders
FROM `onyga-482313.OI.DE_PLAN_CONFIG` c
WHERE c.is_active
  AND c.calendar_state = `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'))
QUALIFY ROW_NUMBER() OVER (PARTITION BY c.calendar_state ORDER BY c.updated_at DESC) = 1
```

The calendar is read on **New York** (it is a US retail calendar); the ads facts the window then
selects are read on **Los Angeles**. A plan NIGHT is keyed on New York too (P-24, v27.160):
`FACT_PLAN_NEXT_WEEK.as_of` is the New York date the calendar was read on, so one partition is one
calendar state. Partitions written before v27.160 are keyed on the Los Angeles date (§3, "Which
clock keys a night").

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

**Two more settings, and a column for the reason (v27.155, 2026-10-01).**

| column | what it is | seeded |
|---|---|---|
| `strong_day_mult` | P-14c: the P-14b hold is granted only when the **last complete day** of the window returned, corrected, at least this many times the family bar | 1.5 in every state |
| `strong_day_min_orders` | …and carried at least this many observed orders on that day | 1 in every state |
| `change_reason` | why the row was written, in words (or, once the learning contract's proposer exists, the proposal id) | the seed rows name the rulings they encode |

Until v27.155 the two P-14c numbers were literals in `V_PLAN_WINDOW_JUDGMENT`'s `k` CTE, so the
rule had no history and could only change by a deploy. The judge now reads them from this table
with the other settings of today's calendar state, and the seed carries the values the `k` CTE
carried, so moving them changed no verdict (the before/after comparison is in the view's header).
A NULL in either column is **not a setting**: `C02` fails on it, and the judge raises an error
naming the state rather than judge with no rule — the plan's builder then fails, and
`LOG_PIPELINE_RUNS` records the step as `FAIL`. So every row you insert must carry both.

**Ori changes a setting without a deploy.** **Retire first, insert second** — in that order, and
retire *whatever is active for the state*, not only the seed:

```sql
UPDATE `onyga-482313.OI.DE_PLAN_CONFIG`
SET is_active = FALSE
WHERE calendar_state = 'BOOST' AND is_active;

INSERT INTO `onyga-482313.OI.DE_PLAN_CONFIG`
  (calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   strong_day_mult, strong_day_min_orders,
   is_active, description, change_reason, updated_at, updated_by)
VALUES ('BOOST', 3, 0.35, 'B', 3, 2, 1.5, 1,
        TRUE, 'what this row says, in words', 'why it changed, in words', CURRENT_TIMESTAMP(), 'ori');
```

Copy every setting of the row you retire and change only the one you mean to change — the new row
replaces the old one whole. To move the last-day test, for example from 1.5 to 1.3 in OFF_PEAK,
retire OFF_PEAK and insert its row with `strong_day_mult = 1.3` and the other settings as they
were. The judge reads it on its next read; the builder writes the rule it used onto every plan row
(`FACT_PLAN_NEXT_WEEK.strong_day_mult / strong_day_min_orders`), so `V_PLAN_SCORECARD` grades each
night against the rule that night was judged under.

Written that way the recipe is **idempotent**: run it ten times and the state still holds exactly
one active row, with every superseded row kept for the audit trail. The v27.130 recipe retired
only `updated_by = 'plan_seed'`, so the *second* change to a state found no seed row left to
retire, left the first hand row active alongside the new one, and turned `C01` permanently red.

Never edit the DDL file to change a live setting.

**THE DEPLOY GUARANTEE, STATED EXACTLY (v27.132; v27.155).** Re-running `DE_PLAN_CONFIG.sql` can
never change a **setting that holds a value**, in any state, *however* you changed it — a new
active row, or an `UPDATE` in place — and can never re-activate a state you retired. All it can do
is refresh the **description** and `change_reason` of a seed row whose settings still equal the
declared seed to the value, and fill `strong_day_mult` / `strong_day_min_orders` on a seed row where
they are still NULL. That last clause is how v27.155 converts the three seed rows written before the
columns existed: the guard reads NULL in the two new columns as "not set yet", deletes the row (its
six older settings must still equal the seed), and the INSERT writes it back with 1.5 / 1, the same
sentinel `updated_at` and the seed's `change_reason`. The DELETE and the INSERT run in one
transaction. One consequence: setting one of those two columns back to NULL by an `UPDATE` in place
on an otherwise untouched seed row makes it look untouched, and the next deploy writes 1.5 / 1 there
— NULL is not a setting, so that is the one in-place edit a deploy still reverts. A row someone else
wrote is never touched, NULL or not. Every case was replayed on `TMP_` copies (the DDL header lists
them).

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

### The history of every setting (v27.155)

A learning system changes its rules from graded evidence, and a change can only be graded later if
the record says which value was in force on which day. Two records keep it:

1. **This table.** Retire-then-insert keeps every superseded row, `is_active = FALSE`, with the
   `updated_at` it was written with. **No row is ever deleted** except by the seed guard above, and
   the guard deletes only the untouched seed, which the INSERT writes straight back.
2. **`FACT_THRESHOLD_HISTORY`.** `SP_SNAPSHOT_THRESHOLDS` (orchestrator Refresh Task 10.1, right
   after `SP_DATA_ENTRY_UPDATES`, every pass) appends one row for every row of `DE_PLAN_CONFIG` and
   of `DE_COACH_THRESHOLDS` that differs from its last snapshot: `SEEDED` on the first run, then
   `ADDED`, `CHANGED` or `REMOVED`. A pass with nothing changed writes nothing. It also records the
   two shapes the table's own trail cannot date: an `UPDATE` in place, and a retirement (the flip
   of `is_active` moves no `updated_at`). In `DE_PLAN_CONFIG` the key is the row itself (state ×
   `updated_by` × `updated_at`), so a retire-then-insert reads as the old row `CHANGED` to
   `is_active = FALSE` and the new row `ADDED`, both in the same pass.

What was in force on a day, for a state — read it, never a number from this page:

```sql
-- every setting of the plan's active row for PEAK as the history saw it on 2026-10-15
SELECT h.*
FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY` h
WHERE h.source_table = 'DE_PLAN_CONFIG' AND h.calendar_state = 'PEAK'
  AND h.snapshot_at < TIMESTAMP '2026-10-16'
QUALIFY ROW_NUMBER() OVER (PARTITION BY h.row_key, h.key_ordinal ORDER BY h.snapshot_at DESC) = 1
    AND h.change_kind != 'REMOVED' AND h.is_active;
```

Limits, stated: the history holds what each pass **saw**. A value that lived between two passes
is not recorded, and `snapshot_at` is when a pass saw the change (`source_updated_at` is when the
writer stamped it, where it stamps one). The acceptance is
`scripts/bigquery/tests/THRESHOLD_HISTORY_acceptance.sql`; it runs the nightly procedure on
`TMP_` copies (one changed value writes exactly one row, a second run writes none, a
retire-then-insert writes two) and holds the live history to "every current row covered, nothing
changed since the last pass".

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

**v27.155, in this order** (each step needs the one before it; the view names columns the
v27.154 table does not have, and the snapshot procedure reads them):

**Deployed 2026-10-02 (about 04:20 UTC), on Ori's yes**, in exactly this order. The three seed rows
kept every setting and gained 1.5 / 1; the first snapshot wrote 185 SEEDED rows (182 coach
thresholds + 3 plan states); the judge carries no literal; the orchestrator gained Task 10.1 and
nothing else (diffed against the deployed body first). PLAN_CONFIG_acceptance 24 of 24 PASS,
THRESHOLD_HISTORY_acceptance 17 of 17 PASS. The pre-conversion rows are kept in
`TMP_TASKD_DE_PLAN_CONFIG_BEFORE` until the plan has run cleanly on the new config.

```bash
Q='bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache'
$Q "$(grep -v '^--' scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql)"                 # columns + seed conversion
$Q "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"             # reads the two settings
$Q "$(grep -v '^--' scripts/bigquery/tables/FACT_THRESHOLD_HISTORY.sql)"
$Q "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_THRESHOLDS_INTO.sql)"
$Q "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_THRESHOLDS.sql)"
$Q 'CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS`()'                                # first run: SEEDED
$Q "$(grep -v '^--' scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql)"  # Refresh Task 10.1
$Q "$(grep -v '^--' scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql)"
$Q "$(grep -v '^--' scripts/bigquery/tests/THRESHOLD_HISTORY_acceptance.sql)"
```

BigQuery allows five metadata updates per table in ten seconds; the DDL makes four (SET OPTIONS and
three `ADD COLUMN`). Do not run it twice inside ten seconds.

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
       c.window_days, c.allowance_share, c.live_plan, c.ramp_steps, c.min_orders,
       c.strong_day_mult, c.strong_day_min_orders, c.description, c.change_reason
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

**That divergence was closed (v27.137, corrected here in v27.138) and is OPEN again since
v27.156.** The book read P-5's one-window limit from `FACT_PLAN_NEXT_WEEK` with the expression
`V_PLAN_WINDOW_JUDGMENT` used until v27.155 (the most recent `GRACE` later than the most recent
`GOOD`). `tools/build_reprice_bulksheet.py` still carries that expression and none of P-14c, P-17,
P-18 or P-29, so on 2026-10-02 it calls grace SPENT on 41 keywords the judge does not (31 of them
GRACE that night: the v27.155 view's `prior_grace`, which is that expression, against the v27.156
view's, same history). Read `prior_grace`, `verdict` and `hold_kept_by` from the judge rather than
from the book until the book reads them too. Task 2 shipped and writes that table nightly, so `grace_limit_armed` reads FALSE only
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
  permanently quiet window kept the good side forever. **Ruled 2026-10-02 (P-17), built v27.156
  (2026-10-02):** grace lasts `window_days` nightly judgments, anchored to the night it was granted
  and to the window length in force that night (a grace granted under a 7-day window keeps 7 nights
  after a switch to 3), and is spent once that run has lasted its window — then refused until the
  keyword earns a GOOD window back. The run starts at the first `GRACE` after the latest reset (a
  `GOOD` night, or a night whose row records `memory_cleared_by_gap`, P-29 below); its length is
  the `window_days` of that first night's row; nights are counted on the date `as_of` is keyed on
  (the New York date since v27.160, P-24; the Los Angeles date before). Every row publishes `grace_since`, `grace_window_days` and
  `grace_ends_on`, and the GRACE sentence states the anchored rule of the row's own run: "grace lasts
  N nightly judgments (the window length in force when it was granted, <date>) through <date>"
  (v27.165, follow-up F3; until then it opened with "keeps the good side for ONE quiet window (P-5)"
  whatever the run's length — see "The GRACE sentence states the anchored rule" in §3). `C12` asserts the arm and
  that a GRACE row is inside its run; `G1` asserts no run outlasts its window over the whole
  history; `C22` asserts the sentence. (v27.135 to v27.155 granted ONE nightly judgment and
  refused grace while the most recent `GRACE` was later than the most recent `GOOD`.) **The
  builder must write `verdict = 'GRACE'` faithfully** — a builder that collapses GRACE into GOOD
  turns grace back into a permanent exemption.
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
(`strong_day_min_orders`, `strong_day_mult`: in the judge's `k` CTE until v27.155, in
`DE_PLAN_CONFIG` per calendar state since — §1). A losing window whose last day
won a little is judged on the window. So the guard is a **delay, bounded by the clock, granted on
one condition** — neither the veto the first build produced nor an unconditional wait.

Read it on the row: `last_day_sp / last_day_ord / last_day_gp_corrected / last_day_ret`,
`last_day_strong`, and on every NOT-GOOD row that was good, served and unsettled,
`guard_released_by` = `LAST_DAY_NOT_STRONG` or `HOLD_EXPIRED`. The builder asserts that column is
never NULL on such a row and that every HELD row names what keeps it held (`hold_kept_by`, P-18
below; until v27.156 it asserted `last_day_strong` on every HELD row) — it checks the judgement is
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

### The hold lasts while its very good day is in the window (P-18, v27.156)

Ruled 2026-10-02 (R4), built v27.156. P-14c's own reason is "wait until that day's sales land", so
a hold run lasts while **the very good day that started it is still inside the judged window**, and
never past its clock: it lifts when that day leaves the window or when the window that started the
hold settles, whichever is first. The run remembers that day as `hold_strong_day` (the `window_to`
of the run's first night). The HELD arm reads `last_day_strong OR (a run is in force AND
window_from <= hold_strong_day)`, and every HELD row publishes `hold_kept_by` = `LAST_DAY` or
`STRONG_DAY_IN_WINDOW`; `guard_released_by = LAST_DAY_NOT_STRONG` only when neither holds. The
builder's assertion, `V_ENGINE_HEALTH.plan_settle_guard_holds`, plan acceptance C26 and judge
acceptance G2 all READ `hold_kept_by`; none re-derives the guard. The three HELD sentences say "held
since <date> because <date> was very good; that day leaves the judged window after the window
ending <date>, and the hold lifts then or when its window settles on <date>, whichever is first".

**The clock is on the row from the first held night (audit fix #16).** `hold_since`,
`hold_settles_on` and `hold_strong_day` used to be NULL on night one (the 9 hold runs started
09-28 … 10-01 each wrote NULL on night one and night one's `as_of` on night two). The judge now
publishes tonight's date, settle date and last day on a first HELD night. It never reads those
columns back — only `as_of`, `verdict`, `settle_due_on`, `window_to`, `window_days` and
`memory_cleared_by_gap` — so publishing them cannot re-anchor a run: on 2026-10-02 a run of the
judge on a history whose clock columns were all junk equalled a run on the real one, row for row.

```sql
SELECT hold_kept_by, COUNT(*) AS kw, MIN(hold_since) AS oldest, MIN(hold_strong_day) AS strong_day,
       ROUND(SUM(w_sp) / MAX(window_days), 2) AS spend_per_day
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` WHERE verdict = 'HELD_UNSETTLED' GROUP BY 1;
```

### Memory across an unwritten gap is checked first (P-29, v27.156)

Ruled 2026-10-02 (R16), built v27.156. A grace run whose last `GRACE` night, or a hold run whose
last night, is older than `today − window_days − 1` is honoured only after the judge reads the
**gap** — the nights after it that wrote no live row for the keyword (the builder refused 08-29 …
09-27; or the keyword was outside the universe). Each gap night *n* would have judged the window
ending *n* − 2 (the P-14a fence) of the length its own calendar state carries
(`FN_PLAN_CALENDAR_STATE(n)` → `DE_PLAN_CONFIG`); the windows ending after the memory's own window
and before tonight's `window_from` are read from `FACT_AMAZON_ADS`, and if one is GOOD — orders at
that state's floor and raw gross profit per ad dollar at tonight's family bar — the memory is
cleared: no grace run, no hold run. The row publishes `memory_cleared_by_gap` (`GRACE` / `HOLD` /
`GRACE_AND_HOLD`) and `memory_gap_good_window_to`. **`memory_cleared_by_gap` is memory, not a
report:** `SP_BUILD_NEXT_WEEK_PLAN` stores it and the judge reads it back as a reset, because
otherwise the next night's history would rebuild the same old run from the August `GRACE` (measured
2026-10-02: with the stored reset the six fresh graces stay GRACE the next day; on a copy of the
history with it nulled, all six read NO_SALE with their August grace spent). On 2026-10-02 it
cleared 9 grace memories, all written 08-23 … 08-28; judge acceptance G4 re-computes the gap from
the history and the ads record and found no honoured memory with a GOOD gap window (45 honoured
memories, 18 with gap windows, 540 windows read).

```sql
SELECT memory_cleared_by_gap, verdict, COUNT(*) AS kw, MIN(memory_gap_good_window_to) AS first_good
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
WHERE memory_cleared_by_gap IS NOT NULL GROUP BY 1, 2;
```

### What v27.156 moved, measured at deploy (2026-10-02, Los Angeles)

Same data both sides — window 09-28 … 09-30 (BOOST, 3 days), 361 rows, `w_sp` equal on every row:
the deployed v27.155 judge snapshotted at 12:10 UTC against the deployed v27.156 judge at 12:46 UTC.
Sides moved only NOT_GOOD → GOOD (0 the other way). The plan columns are the builder's body run
with the partition write removed: HEAD's builder on the v27.155 snapshot, then v27.156's on the
v27.156 view (live plan B; the pot leaves holdout spend out, as the builder did until Task 4).

| family | GRACE | HELD | released LAST_DAY_NOT_STRONG | moved by P-17 (kw, $/day) | moved by P-29 (kw, $/day) | of which holdout $/day | pot $/day | allowance target → ramped $/day | not-good today $/day | seats |
|---|---|---|---|---|---|---|---|---|---|---|
| Bottle | 0 → 1 | 0 → 0 | 0 → 0 | 1, 8.08 | 0 | 8.08 | 0.00 → 0.00 | 0.00 → 0.49 before and after | 0.74 → 0.74 | 1 → 1 |
| Fresh | 2 → 8 | 0 → 0 | 2 → 1 | 3, 27.15 | 3, 7.95 | 7.75 | 57.41 → 84.77 | 28.71 → 68.99 before; 42.38 → 55.31 after | 89.13 → 61.78 | 11 → 14 |
| LolliME | 2 → 20 | 0 → 0 | 2 → 1 | 15, 45.33 | 3, 11.23 | 0.00 | 260.69 → 317.25 | 130.34 → 171.84 before; 158.62 → 158.62 after | 192.58 → 136.03 | 32 → 58 |
| Lollibox | 0 → 6 | 0 → 0 | 6 → 4 | 6, 22.19 | 0 | 6.82 | 80.20 → 95.57 | 40.10 → 48.41 before; 47.78 → 47.78 after | 52.57 → 37.19 | 10 → 9 |
| all | 4 → 35 | 0 → 0 | 10 → 6 | 25, 102.75 | 6, 19.18 | 22.65 | | | | 54 → 82 |

LolliME's allowance target ($158.62/day) now exceeds its whole not-good side ($136.03/day), so its
walk is rationed by nothing and its planned spend delta turned from −$20.82 to +$14.46 a day (raises
at P-6's repaired prices). That is the case R5 (plan Task 3, built v27.157) and R7 (plan Task 4)
close; it is not a Task 2 rule.

### No raise below the bar, the zero-score rank, the probe price (P-19, P-20, P-25; v27.157)

Ruled 2026-10-02 (R5, R6, R12), built in the judge v27.157 (piece-1 plan Task 3). The window, the
sides, the memory and the guard are untouched; only the price, the seat cost, the rank order and
the seat sentences moved.

- **P-19 — no raise below the bar.** A not-good row that is not a probe and whose corrected return
  is under the family bar is priced at `LEAST(P-6's price, current bid)`. The gate is the return
  against the bar, not the verdict label (below-bar `ONE_ORDER` rows would survive a label gate).
  A NULL return (no spend) reads as under the bar. **P-19 wins over P-6's floor:** a current bid
  already under the row's `bid_floor` is held where it is rather than raised to the floor — holding
  it uploads nothing (the builder's `HOLD_AT_PRICE` / `HOLD_AT_PARK` carry the current bid), and C08
  accepts exactly that case. The seat cost follows the gated price, so such a seat costs its window
  spend per day and never more. The candidate's sentence says "competes for a seat at its current
  price $X — the ladder's repaired price $Y would RAISE it … (P-19, Ori 2026-10-02)".
- **P-20 — the zero-score rank.** `rank_money_burned` = window spend per day × `GREATEST(0, 1 −
  return ÷ bar)` on every row. The view orders `GREATEST(rank_score, 0) DESC, rank_money_burned
  DESC, w_clk DESC, campaign_id, keyword_id`: P-7's score for every candidate it scores above zero,
  then every candidate with **no positive score** — zero, or the rare negative one (2 of 978 live
  candidate-nights 08-23 … 10-02) — by money burned. `GREATEST(…, 0)` is Ori's "among candidates
  with no positive score": ordering on `rank_score` itself would put a keyword that sold at a loss
  below every zero-sale one whatever it burned. **Since v27.159 (piece-1 Task 5) the builder's
  `ranked` CTE orders on the same key** (acceptance `T5` recounts it from the row's columns).
- **P-25 — the probe price (the judge's half).** `probe_start_bid` = LIFT's latest single
  `PROBE_START` `suggested_bid` (`FACT_ENGINE_PROPOSALS`, latest snapshot, one distinct price per
  keyword or none). A probe with one is priced at it, capped at `GREATEST(2.00, current bid)`, and
  costed at `click_goal_day` × that price — the seat funds the clicks it asks for. A probe without
  one keeps P-6's price and its sentence says LIFT holds no single `PROBE_START` bid. P-19 does not
  apply to a probe. **The builder's half, v27.159 (Task 5):** a seated probe's move is
  `OPEN_PROBE`; an unseated probe gets move `NONE` and nothing is uploaded — its sentence says
  "PROBE NOT OPENED TONIGHT; NOTHING UPLOADED" and that the park price this view's queue clause names
  is not applied (the judge's clause itself is unchanged; §3, "Probes").

**Measured before deploy, 2026-10-02 (Los Angeles), same data both sides** (window 09-28 … 09-30,
BOOST, 361 rows): the deployed v27.156 judge snapshotted against the v27.157 body run as a query (the
deployed v27.157 view then equalled that run on every column). Keyed on campaign × keyword, every
published column equal except `planned_bid` (85 rows), `seat_cost_per_day` (57) and `sentence` (49).
The plan columns are the builder's body with the partition write removed (every ASSERT run), on each
judge snapshot, live plan B.

| family | P-19 rows (candidates) | candidates' raise removed $/day | candidate seat cost $/day | probes repriced | probe seat cost $/day | no-positive candidates reordered | plan seats | plan seats that raise spend |
|---|---|---|---|---|---|---|---|---|
| Bottle | 6 (2) | 0.08 | 0.78 → 0.70 | 0 | 0 → 0 | 0 of 3 | 1 → 1 | 1 → 0 |
| Fresh | 16 (4) | 2.11 | 59.88 → 61.25 | 2 | 1.80 → 5.28 | 15 of 21 | 14 → 18 | 3 → 1 |
| LolliME | 34 (27) | 10.94 | 150.49 → 177.51 | 9 | 7.20 → 45.16 | 32 of 45 | 58 → 54 | 39 → 9 |
| Lollibox | 17 (4) | 5.07 | 42.63 → 41.84 | 1 | 0.80 → 5.08 | 2 of 7 | 9 → 9 | 6 → 2 |
| all | 73 (37) | 18.20 | 253.79 → 281.31 | 12 | 9.80 → 55.52 | 49 of 76 | 82 → 82 | 49 → 12 |

The 49 seats that raised spend before ($27.01 a day): 33 that P-19 now holds ($18.10), 10 probe
seats costed at the floor ($8.00), 6 at or above the bar ($0.91). After, 12 ($30.83): the same 6
($0.91) and 6 probe seats at LIFT's bid ($29.92). Every probe was `NOT_SERVING` with a LIFT price:
10 moved from $0.21 / $0.25 to $1.27 / $1.13, one SB probe $0.25 → $1.05, and one Fresh probe
$0.29 → $0.27 (LIFT's own nomination, whose preflight verdict was EXCLUDE). At about $5 a day a
probe fits less: LolliME's probe seats fell 9 → 5. The first no-positive candidate of each family is
the same under both orders. Plan acceptance on the dry-run plan (history plus the would-be
partition): 26 of 26 PASS. Slot-seconds as queries, three runs: v27.156 833 / 985 / 1,270, v27.157
964 / 1,012 / 1,023; bytes 127,101,013 → 127,661,417 (the `FACT_ENGINE_PROPOSALS` read, 0.5
slot-seconds alone); no new read of `FACT_AMAZON_ADS`.

```sql
-- what set each price tonight, and what P-19 took off (priced at repair_bid_p6, P-6's price
-- rounded to the cent, so it reads within cents of the table: 2026-10-02 0.09 / 2.10 / 11.00 / 4.83)
SELECT family, planned_bid_basis, COUNT(*) AS kw, COUNTIF(is_candidate) AS candidates,
       ROUND(SUM(IF(planned_bid_basis = 'P19_HELD_AT_CURRENT' AND is_candidate,
                    (w_sp / window_days) * (repair_bid_p6 / current_bid - 1), 0)), 2) AS raise_removed_per_day
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
WHERE side_b = 'NOT_GOOD' GROUP BY 1, 2 ORDER BY 1, 2;

-- the probes: LIFT's bid, the price, the seat cost
SELECT family, target_text, current_bid, probe_start_bid, planned_bid, planned_bid_basis,
       seat_cost_per_day
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` WHERE is_probe ORDER BY family, planned_bid DESC;
```

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
       COUNTIF(REGEXP_CONTAINS(sentence, r'competes for a seat'))                       AS promised_a_seat,
       COUNTIF(REGEXP_CONTAINS(sentence, r'does not compete for a seat'))               AS told_it_has_no_move
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1, 2 ORDER BY 1, 2;
```
- **Repaired price** (P-6) = the ladder's `affordable_bid`, capped at three 5 % steps either way
  from the live bid, floored at the row's own `bid_floor`, ceilinged at the house $2.00 on a
  raise — published since v27.157 as `repair_bid_p6`. The cap constants are mirrored from the
  reprice book, so the book and the plan price a keyword the same way only where P-6's price
  stands (`planned_bid_basis = 'P6_REPAIR'`): the book has no P-19 or P-25.
- **The price** (`planned_bid`, v27.157) is P-6's price **gated by P-19** — never above the current
  bid where the corrected return is under the bar, even where the current bid is under the floor —
  or **replaced by P-25** on a probe with a LIFT `PROBE_START` bid. `planned_bid_basis` names which:
  `P6_REPAIR` · `P19_HELD_AT_CURRENT` · `P25_LIFT_PROBE_START` · `P6_PROBE_NO_LIFT_PRICE`. See
  "No raise below the bar, the zero-score rank, the probe price" above.
- **Seat cost** (P-6) = spend at *that* price, per day — the window's spend per day scaled by the
  price change; a probe with a LIFT price is costed at `click_goal_day` × its opening price (P-25);
  any other candidate with no window spend is costed from `T_OOB_SEAT_ECONOMICS`.
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

- **Rank** (P-7) is written "dollars at stake × closeness to the bar". Since v27.157 (P-20) the
  candidates P-7 scores above zero come first by that score, every candidate with no positive
  score follows by `rank_money_burned`, and clicks then the keyword key break what ties remain (a
  total ordering, so two reads never disagree).
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
WHERE is_candidate
ORDER BY GREATEST(rank_score, 0) DESC, rank_money_burned DESC, w_clk DESC, campaign_id, keyword_id
LIMIT 10;
```

- **P-7 scores ZERO wherever there is no gross profit — which is most of the queue.** That is the
  same collapse seen at its endpoint: closeness to the bar is zero when a keyword sold nothing, so
  a keyword burning real money with no order ranks *below every losing keyword*. It is **not**
  thereby kept out of the seats: until v27.157 the ordering fell through to clicks and the keyword
  key, and the fit test seated zero-score candidates in click order whenever allowance remained
  (audit, 2026-10-01: 21 of the 102 zero-score candidates held seats, $69.54 a day). It is not absorbed silently: `rank_is_degenerate` is TRUE on
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
  both questions in one line. **Ruled 2026-10-02 (R6, spec P-20):** that shortfall, floored at 0,
  is `rank_money_burned`, and it orders every candidate with no positive score — built in the judge
  v27.157; `SP_BUILD_NEXT_WEEK_PLAN`'s walk orders the same way from v27.159 (piece-1 Task 5).
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
# v27.156 reads FACT_PLAN_NEXT_WEEK.memory_cleared_by_gap: the column migration goes first
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/migrations/2026-10-02_plan_judge_memory_columns.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
# the acceptance AND its negative controls, never the file directly (follow-up F7, see below): the
# script's LIVE copy is the acceptance on the live judgement (every check 0 = PASS); exit 0 = LIVE all 0
# and every doctored copy as expected
python3 scripts/bigquery/tests/check_judge_memory_controls.py --submit      # prints JOB=...
bq wait <JOB> 60                                                           # repeat until DONE
python3 scripts/bigquery/tests/check_judge_memory_controls.py --collect <JOB>
```

**The Run line is the controls script (follow-up F7, 2026-10-03).** The acceptance file's header
gave a direct `bq query` Run line, and this block ran it. Run that way in the Task 10 proof (job
`t10_acc_v_plan_window_judgment_1791012391`, the file before F3), it was cancelled after 995.9 s at
1,786,614.5 slot-seconds with 2,573 stages in its plan: the file reads `j` in 31 places, and
`T_LIFT_PROBES`, which the view reads once, was read by 32 of those stages (`FACT_AMAZON_ADS` by 224).
BigQuery's documentation: a view or a non-recursive WITH clause is evaluated again at each reference.
The controls script
reads the view once into a temp table and runs the file's text on it (the proof's run: 207.6 s, 9,315.5
slot-seconds, exit 0). The header and this block now give the script's three commands; the header
records why, F7's run and its controls.

**v27.157: 30 checks** — C08 restated (a price under the floor only where P-19 held a current bid
already under it), C18 restated (the seat promise matched on "competes for a seat"), and P1 (P-19:
no non-probe row under the bar priced above its current bid or costed above its spend, and the
label and the sentence honest), P2 (P-20: `rank_money_burned` exact on every candidate, and the
view's deployed `ORDER BY` ranks by it after the positive scores — read from
`INFORMATION_SCHEMA.VIEWS`), P3 (P-25: recomputed from `FACT_ENGINE_PROPOSALS`, every not-good probe
with a LIFT bid priced and costed at it, capped; one without says so). Run 2026-10-02 on the
deployed view: 30 rows, every one PASS. **Run it through the controls script, not directly:** run
directly it cost 1,180,821 slot-seconds over 624 s (every CTE that reads the view re-evaluates it;
75,686 – 234,068 for the v27.156 file earlier the same day), while the controls script reads the
view once and ran LIVE plus 34 doctored copies for 14,145 slot-seconds, exit 0 (each control and
its measured value is in the acceptance file's header).

**v27.156: 27 checks** — the 23 below with C12 and C22 restated for P-17, plus G1 (no grace run
outlasts its window, over the whole history), G2 (every HELD row names `hold_kept_by` and the reason
stands on the row), G3 (the clock on every HELD row) and G4 (no memory honoured across a gap whose
windows read GOOD, recomputed from the history and the ads record). Run 2026-10-02 on the deployed
view: 27 rows, every one PASS, and the controls script exited 0 with all 17 controls as expected
(each is listed with its measured value in the acceptance file's header).

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
| 1 POT | the **GOOD side's** window spend per day, per family — **every GOOD keyword of the family, holdout included** (P-15, built v27.158). Not the family total, and not a budget anyone set — it is what the good keywords actually bought. | P-2, P-15 |
| 2 ALLOWANCE | `allowance_share × pot`. The share and the window come from `DE_PLAN_CONFIG` for today's calendar state; neither is a literal anywhere in the procedure. | P-2, P-13 |
| 3 RAMP | close **one third of the gap** between today's not-good spend and the allowance this window. As built (the builder's own comment in `fam2`): the ramp term alone closes one third of the gap in whichever direction it runs, and the `GREATEST` removes the downward half for a family already inside its allowance — instead of being ramped up one third at a time, it is handed **the whole allowance target on night one**, so a family whose target exceeds its not-good side gets a bigger loss budget immediately (audit 2026-10-02: Lollibox on 09-30, $3.43 a day above its not-good spend; 13 of 24 August family-nights). **Ruled 2026-10-02 (P-21), built v27.158:** the ramped allowance is capped at today's not-good spend, `LEAST(notgood_today, GREATEST(target, notgood_today − (notgood_today − target) / ramp_steps))`, so it never raises a family's loser spend above what it spends tonight (acceptance `M1`, `C04`). The ramp is re-anchored on tonight's actual not-good spend, so it descends only as uploads cut that spend: with no upload, each night re-takes the same one-third step from a base that drifts with the window. `ramp_step` counts the plan uploads that **landed** for the family since its first plan night (`plan_uploads_landed`, capped at `ramp_steps`; 0 prints "no step taken yet") — until v27.157 it was a calendar count of windows and read 3 of 3 on every live row although no plan batch had landed since 2026-08-25 (audit fix #15). | P-8, P-21 |
| 4 SEATS | **incumbents first** (v27.159, P-16): last partition's seats written under P-16, before their verdict date and still candidates, keep their seat, number, price, verdict date and question, walked in the order they took their seats, each costing **its kept price on tonight's window** (v27.164, follow-up F2 — until v27.160 the cost its seat was granted at); when tonight's allowance cannot carry them all they **leave latest-seated first until the rest fit** — the incumbents' walk is a prefix, not a fit test (v27.167, follow-up F8). Then candidates ranked (P-7's score, then money burned with no return, P-20), each costing its spend **at the repaired price**, walked in rank order into what the incumbents left: a candidate takes the lowest free seat **whenever its own cost fits the allowance still unspent**, and one it cannot afford is skipped rather than closing the queue behind it. Each walk is a recursive walk over a total order, so it is exactly as reproducible as a prefix sum and does not park candidates the allowance can pay for. | P-6, P-7, P-16, P-20, §4.4 |
| 5 QUEUE | everything that did not fit: parked at the engine park price, **held** at the price it already has when that is at or below the park price (nothing to upload), or **paused only when the ladder has already closed the keyword** (`ladder_state = 'DEAD'`); an **unseated probe gets no move** and nothing is uploaded (v27.159, P-25). Since v27.158 the family's **expected spend after the upload** (seats + the queue at the price the plan leaves it at) and the **share of the gap it closes** are published beside the allowance (P-22). | §4.5, P-22, P-25 |
| 6 MOVES | exactly one executable instruction per **candidate**; none on the good side. A seated probe is `OPEN_PROBE` (v27.159). Every seat names its question over its settle horizon (P-26). | P-4, §4.6, P-25, P-26 |
| 7 BUDGETS | `GREATEST(current + (need − current) / ramp_steps, need, good side, $1.00)` — **need** being the good side + the seats + the queue at today's rate — snapped out of the forbidden $20.01–$31.99 band. No move on a brand-defense, an unmeasured or (v27.158) a **holdout** campaign. `campaign_budget_basis` names what bound the cap (v27.158): `RAMPED` (the one-third number), `FLOORED_AT_NEED`, `BAND_SNAPPED_UP` / `_DOWN`, `FLOORED_AT_MINIMUM`, `NO_MOVE_*`. | §4.7, P-27 |

**Seat numbers are the ledger's, not the plan's — and a number is FREE only when the ledger has
freed it.** On the live plan, a keyword `DE_FAMILY_SEAT_LEDGER` holds open keeps the register's
number; any other seated keyword keeps **the number it held most recently in any earlier partition**
(P-28, v27.159 — until v27.158 only last night's, so a one-night absence reissued it), unless the
register holds that number open for another keyword; a new occupant takes the family's lowest number
**no open ledger row is holding** (`closed_on IS NULL` means occupied, whether or not tonight's plan
seats that occupant). If two seated keywords claim one number, the register's claimant keeps it,
then the more recent claim, then the better rank, and the other is numbered as new — so "numbered
exactly once" cannot be broken by a ledger inconsistency. **The register is the live plan's**
(v27.159): the shadow plan numbers its own seats from its own history. `C17` compares the live plan's
numbering with the register's, `C23` (last night) and `T2` (across an absence) check stickiness, and
the builder asserts both before it writes; read the two side by side with:

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
in words. **Since v27.157 (P-19) a raise is possible only on a row at or above its family bar, or on
a probe opening at LIFT's bid (P-25)** — measured on the dry-run plan of 2026-10-02: 12 seats raise
spend, 6 of each. Read the direction per family before any upload — a family reading positive is
one the plan is spending MORE on, not less:

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
restated to the identity that holds (`C19`). **Ruled 2026-10-02 (P-22, option (b)), built v27.158:**
the arithmetic stays and the residual is published beside the allowance, per family on every row:

- `expected_after_upload_per_day` = the seats' cost + each queued candidate's window spend per day
  × (the price the plan leaves it at ÷ its current bid): the park price on a `PARK` row, its current
  bid on a `HOLD_AT_PARK` row (nothing uploads), **zero** on a `PAUSE` row. Linear in price, the same
  model as a seat's cost; the queue's true park spend is re-decided once an upload has been scored.
- `share_closed` = (not-good today − expected after upload) ÷ (not-good today − allowance target).
  **NULL** when the family's not-good spend is already at or under its target (a gap of $0.005 a day
  or less): there is no gap to close, and the ratio's sign would read backwards. The formula in the
  plan's Task 4 divides by `NULLIF(gap, 0)` only; a negative gap is the case that guard did not name.

Both are printed in the **FAMILY clause** every row's sentence now ends with ("Expected after the
upload: $X a day — the seats $S plus the queue at the price the plan leaves it at $Q — N% of the gap
to the allowance target closes", or "…so there is no gap to close"), and acceptance `M3` recounts
both from the row columns. Read them per family:

```sql
SELECT family, ROUND(MAX(notgood_today_per_day), 2) AS notgood_today,
       ROUND(MAX(allowance_target_per_day), 2) AS target, ROUND(MAX(allowance_ramped_per_day), 2) AS allowed,
       ROUND(MAX(expected_after_upload_per_day), 2) AS expected_after_upload,
       ROUND(MAX(share_closed), 3) AS share_closed, MAX(ramp_step) AS ramp_step,
       MAX(plan_uploads_landed) AS plan_uploads_landed
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan
GROUP BY 1 ORDER BY 1;
```

**The ramp is geometric, not linear, and three windows is not the whole gap.** One third of the
*remaining* gap closes each window **in which an upload cuts the spend**, exactly like the
three-step bid cap, so after three such windows about seventy per cent of the original gap is
closed and the rest follows. The allowance is re-anchored on tonight's actual not-good spend, so
without an upload it does not descend: each night re-takes the same one-third step from a base that
drifts with the window. `ramp_step` says which (v27.158): the plan uploads that have landed for the
family since its first plan night, capped at `ramp_steps` — a plan batch is a `batch_id` of the
book's `BRAIN:*` / `PACING:*` / `CATALOG:*` rows that is in `V_PPC_CHANGE_LOG_APPLIED` or that an
observed change confirms (`CONFIRMS <change_id>`), on a campaign of the family. On 2026-10-02 it is
0 for every family: the last plan batches (2026-08-25) are `PENDING_UPLOAD` or
`SUPERSEDED_NEVER_UPLOADED`. And P-8's third is the *allowance*, not the realised cut —
`share_closed` above is the realised one. Anybody who reads "ramped over three windows" as "arrives
at the allowance on the third upload" will be wrong by the last third. Read where a family actually is:

```sql
SELECT family, MAX(notgood_today_per_day) AS notgood_day, MAX(allowance_target_per_day) AS allowance_day,
       MAX(allowance_ramped_per_day) AS this_window_day, MAX(ramp_step) AS step_of, MAX(ramp_steps) AS steps,
       MAX(plan_uploads_landed) AS uploads_landed
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
is the check that stands over this. Since v27.156 the judge also reads back
`memory_cleared_by_gap` (P-29): a grace or hold memory a GOOD gap window cleared stays cleared the
next night only because the builder stored that column, so it is copied faithfully too, with
`hold_strong_day`, `hold_kept_by` and `grace_since` (migration
`scripts/bigquery/migrations/2026-10-02_plan_judge_memory_columns.sql`). Confirm the limit is armed
the morning after a first run:

```sql
SELECT DISTINCT grace_limit_armed FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;
```

### What Ori still rules — four readings this builder had to make

1. **The holdout is outside the money, not only outside the sheet.** A holdout campaign's spend is
   excluded from the pot, from the not-good side and from the ramp base: a measurement control's
   money is not the plan's to allocate. It still gets a row, a side and a sentence — the
   counterfactual — and no move. *To overrule:* drop `AND NOT holdout` from the `fam` aggregation.
   **Ruled 2026-10-02 (P-15), built v27.158:** the pot counts every GOOD keyword of the family,
   holdout included; the not-good base and every move keep excluding the holdout (acceptance `C03`,
   `C15`, `V_ENGINE_HEALTH.plan_pot_reconciliation`). And the holdout's **campaign cap** is no
   longer moved (`NO_MOVE_HOLDOUT`, audit fix #11; acceptance `C08`): on every live partition
   2026-09-28 … 10-02 the plan had moved the caps of 7 of the 8 holdout campaigns ($57.53–$82.35 a
   day of raises a night; query in "What v27.158 moved" below). Its GOOD keywords keep move `NONE`
   (P-4) and their sentence now says they are a measurement control.
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
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = CURRENT_DATE('America/New_York');
```

(Both runs must land in the same New York day — the date `as_of` is keyed on since v27.160 — and
behind the same ads watermark; if the watermark moved between them, re-run both.)

**v27.156 (2026-10-02, piece-1 Task 2).** The builder copies `hold_strong_day`, `hold_kept_by`,
`grace_since` and `memory_cleared_by_gap` (deploy the column migration
`scripts/bigquery/migrations/2026-10-02_plan_judge_memory_columns.sql` before the judge and the
builder), and its HELD assertion reads `hold_kept_by` (P-18) instead of requiring a very good last
day on every hold. Measured at deploy: the builder body with the partition write removed passed every
assertion on the deployed v27.156 judge, then one CALL wrote the 2026-10-02 partition (722 rows, no
refusal). Plan acceptance 26 rows PASS, C26 restated with its controls in the file.

**v27.158 (2026-10-02, piece-1 Task 4 — P-15, P-21, P-22, audit fixes #11 #12 #15 #24).** Deploy
the column migration first, then the builder, then `V_ENGINE_HEALTH`; run the acceptance and the
negative controls:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/migrations/2026-10-02_plan_money_columns.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
# the negative controls: the acceptance's own text on doctored copies (exit 0 = every control as expected)
python3 scripts/bigquery/tests/check_plan_money_controls.py
```

Measured at deploy: the builder body with the partition write removed passed every assertion on a
snapshot of the judgement (`OI._tmp_t4_judge`, 14:50 UTC), then one CALL wrote the 2026-10-02
partition (722 rows, no refusal; job `t4_call_1790953757`, 2,141.5 slot-seconds including the
judgement view). The deployed bodies of the procedure and the view equal their files
(`INFORMATION_SCHEMA.ROUTINES` / `VIEWS`, whitespace and comments aside). Plan acceptance 29 rows
PASS on the live partition; the controls script exit 0 (its results are in the acceptance file's
header); `PLAN_HEALTH_acceptance.sql` 22 rows PASS on the redeployed board. The builder's new read is
`FACT_PPC_CHANGE_LOG` + `V_PPC_CHANGE_LOG_APPLIED` (52.5 slot-seconds alone); nothing new reads
`FACT_AMAZON_ADS`. The uploads count was proved on a doctored log: one observed confirmation of a
row of the pending batch `weekly_book_20260825_214435` (a LolliME campaign) reads LolliME 1 and the
other families 0; the live log reads 0 for every family (3–4 plan batches logged per family since
2026-08-23, none applied or confirmed).

### What v27.158 moved, measured at deploy (2026-10-02)

Same judgement on both sides (the snapshot, window 09-28 … 09-30, BOOST, share 0.50): the v27.156
builder body (dry run) against the v27.158 partition, live plan B, $ a day. "Expected after" on the
v27.156 side is the P-22 formula applied to its rows (that builder did not publish it).

| family | pot | target | not-good today | allowance | seats (probes) | seat cost | queued | expected after | share closed |
|---|---|---|---|---|---|---|---|---|---|
| Bottle v27.156 | 0.00 | 0.00 | 0.74 | 0.49 | 1 (0) | 0.39 | 2 | 0.55 | — |
| Bottle v27.158 | 12.54 | 6.27 | 0.74 | 0.74 | 3 (0) | 0.70 | 0 | 0.70 | no gap |
| Fresh v27.156 | 84.77 | 42.38 | 61.78 | 55.31 | 18 (0) | 55.30 | 5 | 55.94 | — |
| Fresh v27.158 | 104.40 | 52.20 | 61.78 | 58.58 | 22 (1) | 57.05 | 1 | 57.05 | 49 % |
| LolliME v27.156 | 317.25 | 158.62 | 136.03 | 158.62 | 54 (5) | 157.19 | 4 | 157.19 | — |
| LolliME v27.158 | 337.69 | 168.84 | 136.03 | 136.03 | 49 (0) | 132.35 | 9 | 132.35 | no gap |
| Lollibox v27.156 | 95.57 | 47.78 | 37.19 | 47.78 | 9 (1) | 41.84 | 0 | 41.84 | — |
| Lollibox v27.158 | 147.25 | 73.62 | 37.19 | 37.19 | 8 (0) | 36.76 | 1 | 36.76 | no gap |

- **P-15** raised every pot by its holdout GOOD spend: Bottle $0.00 → $12.54 (all of its GOOD
  keywords sit in the holdout campaign BOTTLE-SP/AUTO), Lollibox +$51.68, Fresh +$19.63, LolliME
  +$20.44. Three of the four targets now sit above the family's not-good side (LolliME's and
  Lollibox's already did, and v27.156's `GREATEST` handed them the whole target).
- **P-21** then holds those three families at today's not-good spend: LolliME's allowance fell
  $158.62 → $136.03 and Lollibox's $47.78 → $37.19; Bottle rose $0.49 → $0.74 (its own not-good
  side). Fresh is the one family above its target and ramps by a third ($55.31 → $58.58, because
  its target rose with P-15). Seat cost per family: LolliME −$24.84, Lollibox −$5.08, Fresh
  +$1.75, Bottle +$0.31 a day (−$27.86 in all). The 6 probe seats of v27.156 (5 LolliME,
  1 Lollibox; P-25 prices them at LIFT's `PROBE_START` bid) no longer fit: they rank last (LolliME
  ranks 50–58), and after the candidates ahead of them LolliME has $3.68 a day of allowance left and
  Lollibox $0.43, against probe seat costs of $4.52–$5.08. Every queued candidate tonight is such a
  probe (window spend $0), so the queue adds $0.00 to the expected figure. Fresh seated 4 more (its
  probe among them).
- **P-22**: Fresh is expected to close 49 % of its gap to the target after the upload (P-8 asks a
  third of the allowance); the other three have no gap to close.
- **Fix #11**: the 7 holdout caps v27.156 moved ($76.28 a day of raises, $17.51 of cuts) are left
  where they are (`NO_MOVE_HOLDOUT`, 8 campaigns); 5 of them show need above today's budget, which
  the floor assertion now leaves to the control.
- **Fix #12**: of the 35 caps moved outside the holdout, 21 are the ramp's number (`RAMPED`, all
  cuts, $128.66 a day), 9 landed on need (`FLOORED_AT_NEED`, raises $90.29), 4 were moved up to
  $32.00 by the band (`BAND_SNAPPED_UP`: raises $18.00, cuts $14.75 — a snap up can shorten a cut)
  and 1 down to $20.00 (`BAND_SNAPPED_DOWN`, a cut of $12.00). v27.156 called all 42 `RAMPED`.
  5 caps outside the holdout changed their number because their seats changed (by $17.47 a day in
  all).
- **Fix #15**: `ramp_step` 3 → 0 on every row ("no step taken yet").

```sql
-- the caps by the rule that set them, and the holdout's caps v27.157 and earlier moved
SELECT as_of, COUNTIF(h) AS holdout_campaigns, COUNTIF(h AND ABS(d) > 0.005) AS holdout_moved,
       ROUND(SUM(IF(h AND d > 0, d, 0)), 2) AS holdout_raises, ROUND(SUM(IF(h AND d < 0, -d, 0)), 2) AS holdout_cuts
FROM (SELECT as_of, campaign_id, LOGICAL_OR(holdout) h, MAX(campaign_planned_budget_delta_per_day) d
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of >= '2026-09-28' AND is_live_plan GROUP BY 1, 2)
GROUP BY 1 ORDER BY 1;
```

### Tenure, probes, the question and the numbers (v27.159, piece-1 Task 5 — P-16, P-20, P-25, P-26, P-28)

**A seat is held until its verdict date (P-16, Ori 2026-10-02, R2).** An *incumbent* is a keyword
seated in the previous partition whose seat was written under P-16 (`seat_since` is set), whose
`verdict_date` is after tonight, and that is still a candidate tonight (not GOOD, not holdout, ladder
not `DEAD`). It keeps its seat, its number, its planned price, its verdict date, the night it took
the seat (`seat_since`) and its question; its cost — since v27.164 its kept price on tonight's window,
not the cost it was seated at (see "An incumbent's cost is tonight's money" below) — comes off the
allowance first. The
builder walks the incumbents in the order they took their seats (earliest first, tonight's rank
breaking a tie) — since v27.167 as a prefix: when the allowance cannot carry them all, they leave
latest-seated first until the rest fit (see "Incumbents leave latest-seated first" below; v27.159 ..
v27.164 used the newcomers' fit test) — then walks every other candidate in rank order into what is
left. `seat_tenure` says which: `INCUMBENT`, `NEW`, or `LEFT_ALLOWANCE_SHRANK` on an
incumbent tonight's allowance could not carry; each sentence says it in words ("TENURE: …",
"TENURE ENDS EARLY: …"). The previous partition is the latest one **before** tonight's `as_of`, so a
rewrite of the same night derives the same incumbents from the same rows.

Three readings the builder had to make, recorded for Ori:

1. **The cutover.** Only a seat written with `seat_since` (every seat from v27.159) is an incumbent.
   The seats of the 2026-10-01 partition were priced before P-19 / P-25 and asked before P-26: 11 of
   the 28 live seats that were still candidates on the 2026-10-02 judgement carried a price above
   their current bid on a keyword whose corrected return was under the bar (P-19 forbids that raise),
   and no plan batch has landed since 2026-08-25, so no such contract was in force on Amazon. Tenure
   therefore starts with the 2026-10-02 partition and is first honoured by the 2026-10-03 one.
   *To overrule:* drop `AND seat_since IS NOT NULL` from `prior_seat` (and re-price the old seats
   under P-19 first, or the raises come back).
2. **"Those seated latest leave first" — read as a fit test in seat order until v27.164; a prefix
   since v27.167 (follow-up F8, which restores R2's words).** v27.159 kept each incumbent whose cost
   fitted what the incumbents seated before it left, so a senior seat whose cost alone exceeded the
   room left went out and a cheaper junior one that fitted stayed. On a doctored judgement with
   LolliME's allowance share halved (allowance $136.03 → $118.83 a day), the simulated 2026-10-03
   night kept 25 incumbents of 49 ($118.82 a day) and released 24 ($13.57 a day); all 49 took their
   seats the same night, so tonight's rank decided the order. The proof (2026-10-03) listed this as
   R2 not built as worded; v27.167 builds the words.
3. **An incumbent keeps its price** even when tonight's window would price it differently: settle
   discipline at the new price is the point of the verdict date. P-19 was applied the night the
   price was set; the sentence prints tonight's price beside the kept one when they differ.

**Probes (P-25, audit fix #19).** A probe that wins a seat gets move `OPEN_PROBE` at the price the
judge set (LIFT's `PROBE_START` bid, capped; P-6's where LIFT holds none) with its own sentence ("OPEN
PROBE at $X for about N clicks a day (about $Y a day) …, judged after <clicks> clicks or on <date>").
An unseated probe gets move `NONE`, no price, and "PROBE NOT OPENED TONIGHT; NOTHING UPLOADED" — no
PARK on a keyword that bought no clicks (the v27.158 builder parked 9 LolliME and 1 Lollibox probes and
held a Fresh one at park on the 2026-10-02 partition). The PARK and HOLD_AT_PARK sentences branch on
service: an unserved row reads "not serving: … the park price is a floor it already does not reach, and
it adds nothing to the family's not-good spend". Since every unserved candidate is a probe, that branch
is unreachable by construction tonight; acceptance `T4` checks that no queued candidate that bought
nothing says it "keeps buying clicks". `is_probe` is copied onto the row.

**The question spans the settle horizon (P-26).** On a seat taken tonight `clicks_requested` =
`ROUND(w_clk × settle_days / window_days)` (probes `click_goal_day × settle_days`), due on the verdict
date (`as_of + settle_days`); `implied_daily_spend` = the seat's cost per day; `expected_cpc` = that
cost × the horizon ÷ the clicks, so clicks × CPC ÷ horizon = implied spend to the rounding of the CPC
(`T3`). Integer clicks move `expected_cpc` off the window's own CPC at the new price by at most half a
click's share of the horizon (one BOOST seat with 1 window click asks 2 clicks: $0.43 a click against
$0.37). `request_basis` is `HORIZON_WINDOW_RATE` or `HORIZON_PROBE_GOAL`. An incumbent repeats its own
question, so `FACT_SEAT_REQUEST` holds one promise per seat and `V_SEAT_REQUEST_OUTCOME` grades the
clicks delivered since the night it was asked. `PLAN_SEAT_REQUEST_acceptance.sql` S03 / S06 / S07 /
S11 and `SEAT_REQUEST_acceptance.sql` R04 / R11 read the new bases; rows written before keep theirs.
`SEAT_REQUEST_acceptance.sql` R02 (follow-up F6, 2026-10-03) compares the `(plan, campaign_id,
keyword_id)` keys of the plan's latest seats with the ledger's partition for that `as_of` both ways
(seats missing from the ledger plus ledger rows the plan no longer seats); until then it subtracted
row counts, so equal counts over different keywords read 0 and a longer ledger read negative. On
2026-10-03 at 10:29 UTC it read 9 (the 08:58 UTC plan build after the 08:12 UTC append: 5 seats
missing, 4 rows no longer seated) where the counts form read 1; its controls on copies are in the
file's header.

**Seat numbers (P-28).** See "Seat numbers are the ledger's" above. Two defects made the builder's
continuity assertion refuse 4 passes from 2026-09-29 16:53 to 2026-10-02 05:34 UTC. Replayed with
BigQuery time travel (the ledger as of each refused pass, against the partition the same night's
first pass wrote): **(a)** the register's numbers bound the shadow plan — every refusal names plan-A
seats renumbered by the register (09-29: Fresh 340057616788625 16 → 5, LolliME 123153583900193 7 → 6
and 546572942561610 13 → 18; 10-01: LolliME 23713700698206 24 → 30); **(b)** `SP_MAINTAIN_FAMILY_SEATS`
re-opened a row closed earlier the same `run_day` at its OLD number — the 2026-10-01 05:47 UTC pass
re-opened LolliME 420345733116531 at 24 and 417323360351451 at 28 (the plan of 09-30 had them at 25 and
30), so the plan's numbers of two other keywords were taken and the admission walk fell back to 18 and
20 for 485639729786108 and 359460728874259 (the plan had them at 24 and 28). Fixes: the shadow plan
numbers its own seats; the register re-opens a row only at the plan's number (v27.159), else admits a
new row at it. Replaying that 05:47 pass on a time-travel copy of the ledger: the old body leaves 4 open
rows off the plan's number (exactly the live ledger's 4), the new body 0 (98 open rows, 98 distinct
numbers, no repeated occupancy key). The builder's assertion now reads the precedence itself: a key the
register holds keeps the register's number, any other its most recent claim — on the first v27.159 dry
run 24 live seats returning after an absence held a register number the v27.158 partition of 10-02 had
given them, not their older claim.

```sql
-- seat tenure on the latest partition, per plan and family
SELECT plan, family, COUNTIF(seat_tenure = 'INCUMBENT') AS kept, COUNTIF(seat_tenure = 'NEW') AS new_seats,
       COUNTIF(seat_tenure = 'LEFT_ALLOWANCE_SHRANK') AS left_allowance_shrank,
       COUNTIF(move = 'OPEN_PROBE') AS probes_opened, COUNTIF(is_candidate AND move = 'NONE') AS probes_not_opened
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
GROUP BY 1, 2 ORDER BY 1, 2;
-- the 11 of 28: the 2026-10-01 seats still candidates on a judgement, priced above their current bid
-- under the bar (run against the judgement of the night after)
WITH j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
prev AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = '2026-10-01' AND is_live_plan AND seat_no IS NOT NULL)
SELECT COUNT(*) AS still_candidates,
       COUNTIF(NOT j.is_probe AND p.planned_bid > j.current_bid + 0.005 AND COALESCE(j.ret_corrected, 0) < j.family_bar) AS p19_raise
FROM prev p JOIN j USING (campaign_id, keyword_id)
WHERE p.verdict_date > DATE '2026-10-02' AND j.is_candidate AND j.ladder_state != 'DEAD';
```

### Deploy and verify v27.159 (2026-10-02, piece-1 Task 5)

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/migrations/2026-10-02_plan_seat_tenure_columns.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_MAINTAIN_FAMILY_SEATS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"          # a long job: submit with --nosync and poll
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
# the negative controls of C06 C12 C14 C17 C19 C23 T1..T5, S03 S06 S07 S11 and V_ENGINE_HEALTH
# plan_one_move_per_notgood (exit 0 = every control exercised and as expected; 1 = a mismatch, or a
# control NOT EXERCISED because the partition has no row for it to doctor). A long job (one script,
# 121 statements): submit, then collect, which polls with bq wait.
python3 scripts/bigquery/tests/check_plan_seat_controls.py --submit --judge-table <a snapshot of the judgement>
python3 scripts/bigquery/tests/check_plan_seat_controls.py --collect <the JOB it printed>
```

The negative controls, run 2026-10-03 02:01–02:10 UTC on every partition with the 2026-10-02
v27.159 partition as the latest and the judgement read from `OI._tmp_t5_judge` (job
`bqjob_r4ed37cefafebd407_000001a0ff7ee55d_1`, 5,789.9 slot-seconds): exit 0. LIVE read 0 on all 47
readings (34 plan checks, 11 `PLAN_SEAT_REQUEST` checks, the board's `plan_one_move_per_notgood`
measured value and RED status); all 28 doctored copies were exercised and each read its expected
value. The per-copy results are in `FACT_PLAN_NEXT_WEEK_acceptance.sql`'s header. The commit before
this run claimed controls for C12 and C19 that the script did not contain, and it had no control for
the C14 `is_probe IS NULL` term, the T1 "TENURE ENDS EARLY" sentence term, the T4 unseated-probe
term, S07, S11, or the board's two v27.159 terms. Its four conditional expectations expected 0 when
the row they doctor was absent, so a control that tested nothing passed.

Measured at deploy (2026-10-02 Los Angeles, 01:14–01:22 UTC 10-03): the migration added three columns
and restated two `FACT_SEAT_REQUEST` column descriptions; the deployed bodies of both procedures and
the view equal their files. Three CALLs (jobs `t5_call1_1790990069`, `t5_call2_1790990207`,
`t5_call3_1790990324`; 1,820.8 / 1,323.3 / 1,755.5 slot-seconds) each wrote the 2026-10-02 partition
(722 rows, 118 seats) with no refusal, and the three partitions have one fingerprint; the first equals
the dry run on the judgement snapshot `OI._tmp_t5_judge` row for row. Plan acceptance 34 rows PASS
(job `t5_acc_live_1790990459`, 1,513.2 slot-seconds); `PLAN_SEAT_REQUEST` 11 PASS; `SEAT_REQUEST` 11
PASS and R12 1 (it read 1 before this change: `V_SEAT_REQUEST_OUTCOME` reads the table);
`PLAN_HEALTH_acceptance.sql` 22 PASS (41,189.7 slot-seconds). Nothing new reads `FACT_AMAZON_ADS`.
On the v27.158 partition of the same night the new checks read C14 140, T1 118, T2 1, T3 118, T4 22,
T5 61 (red before; C14 and T1 count, among others, the `is_probe` and `seat_tenure` columns that
builder did not write).

### What v27.159 moved, measured at deploy (2026-10-02)

Same judgement on both sides (window 09-28 … 09-30, BOOST): the v27.158 partition written at 17:03 UTC
against the v27.159 partition, live plan B. Seats and seat cost did not move (every not-good candidate
that fitted before fits now; 0 incumbents tonight, by the cutover).

| family | seats | seat cost $/day | probes opened | probe moves PARK / HOLD_AT_PARK → NONE | ranks changed | clicks requested | implied $ to the due date / clicks × CPC |
|---|---|---|---|---|---|---|---|
| Bottle | 3 → 3 | 0.70 | 0 | 0 | 0 | 4 → 9 | 4.93 / 2.11 → 4.93 / 4.93 |
| Fresh | 22 → 22 | 57.06 | 0 → 1 (REPRICE → OPEN_PROBE) | 1 | 15 | 351 → 1,464 | 628.31 / 171.17 → 628.31 / 628.31 |
| LolliME | 49 → 49 | 132.39 | 0 | 9 | 34 | 620 → 2,220 | 1,327.00 / 397.18 → 1,327.00 / 1,327.00 |
| Lollibox | 8 → 8 | 36.76 | 0 | 1 | 2 | 292 → 1,193 | 472.49 / 110.30 → 472.49 / 472.53 |

- **P-26**: the question now prices the clicks it asks for: implied spend to the due date equals clicks
  × expected CPC (to $0.04 on 1,193 Lollibox clicks, the rounding of the CPC); v27.158 overstated the
  clicks' cost 2.3–4.3× per family.
- **P-25 / fix #19**: 11 unserved probes no longer get a PARK or a park hold; Fresh's seated probe opens
  at LIFT's $0.27 for 28 clicks by 10-09.
- **P-20**: 51 live candidates changed rank; none changed seat.
- **P-28**: the shadow plan renumbered 3 seats (Fresh 1, LolliME 2) it had taken from the register's
  numbering; the live plan renumbered none.
- **P-16** (simulated: the builder body with `as_of` 2026-10-03 on a history whose 10-02 partition is
  the v27.159 one, same judgement): all 118 seats were incumbents and kept their contracts unchanged
  (0 renumbered, 0 changed price, date or question), 0 newcomers seated (the allowance was full). With
  LolliME's allowance share halved: 25 kept and 24 released in plan B (above), 12 kept and 4 released
  in plan A; every builder assertion passed in both.

```sql
-- after, per family, on the latest partition. The v27.158 side was read before the first v27.159
-- CALL rewrote 2026-10-02; within seven days it is readable again by time travel: replace the FROM
-- with FACT_PLAN_NEXT_WEEK FOR SYSTEM_TIME AS OF TIMESTAMP('2026-10-03 01:10:00+00') and as_of = '2026-10-02'.
SELECT plan, family, COUNTIF(seat_no IS NOT NULL) AS seats,
       ROUND(SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)), 2) AS seat_cost,
       COUNTIF(move = 'OPEN_PROBE') AS opened, COUNTIF(is_candidate AND move = 'NONE') AS probes_none,
       SUM(IF(seat_no IS NOT NULL, clicks_requested, 0)) AS clicks,
       ROUND(SUM(IF(seat_no IS NOT NULL, implied_daily_spend * DATE_DIFF(clicks_due_date, as_of, DAY), 0)), 2) AS implied_to_due,
       ROUND(SUM(IF(seat_no IS NOT NULL, clicks_requested * expected_cpc, 0)), 2) AS clicks_x_cpc
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
GROUP BY 1, 2 ORDER BY 1, 2;
```

### Which clock keys a night, and the shadow plan's sentences (v27.160, piece-1 Task 6 — P-24, fix #25)

**P-24 (Ori 2026-10-02, R11 option (a) with option (c)'s guard).** A plan night is keyed on the
**New York date**: `SP_BUILD_NEXT_WEEK_PLAN` writes `as_of = CURRENT_DATE('America/New_York')`, the
date `V_PLAN_WINDOW_JUDGMENT` reads the calendar state on. The judge's `today_plan` moved with it, so
the plan's history is read before the New York date (`plan_hist`, `armed`), P-17's grace nights and
P-29's gap nights are counted on it, and a first HELD or GRACE night publishes it. **The ads clock
stays on Los Angeles** — the window fence `window_to = LEAST(watermark − 1, today_la − 2)`, the
settle ages, `settled`, the hold's settle clock (`today_la > hold_settles_on`, an ads date) and the
holdout date — because ads days are Los Angeles days. So within one New York night the window can
move a day between the 01:35 and 04:10 New York passes: fresher evidence for the same night, under
the same calendar state.

**Partitions before v27.160 are keyed on the Los Angeles date.** The eight built after 22:00 Los
Angeles — 2026-08-23 … 08-28, 09-28 and 09-30 — carry an `as_of` one day before the New York date of
their build, and the 09-30 partition carries BOOST while `FN_PLAN_CALENDAR_STATE('2026-09-30')` is
OFF_PEAK (the audit's rewrite: the 01:22 and 09:42 Los Angeles builds were OFF_PEAK, 7-day window,
share 0.20; the 22:44 Los Angeles build, already 10-01 in New York, replaced them with BOOST, 3-day
window, 0.50). Read it:

```sql
SELECT as_of, ANY_VALUE(calendar_state) AS state, COUNT(DISTINCT calendar_state) AS n_states,
       `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(as_of) AS state_of_its_date,
       DATETIME(MAX(built_at), 'America/Los_Angeles') AS built_la,
       DATE(MAX(built_at), 'America/New_York') AS built_ny_date
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` GROUP BY 1 ORDER BY 1;
```

**R11's guard.** Before the `DELETE`, the builder reads the calendar state the partition for tonight's
date was written under; if it differs from tonight's, the build raises `partition <date> was written
under <state>; tonight reads <state>; refusing to rewrite` and the written partition stands (the
orchestrator's Task 20.8c logs a FAIL). Keyed on New York, the calendar is read on the key's own date,
so the guard does not fire in normal operation; it is the net under any later change of either clock
(or an edit to `DIM_US_HOLIDAYS` that moves tonight's state after a pass has written it — then the
night keeps the state it was first written under, and K2 reads 1 until the next night). A new
assertion also requires one calendar state on every row of a night.

**Fix #25: a shadow row speaks for plan A's side.** The judgement's sentence and its settle-arm
sentence are written for rule B's verdict. Until v27.159 every plan-A row opened with them, so where the
ladder and rule B disagree the row named the live plan's side and then plan A's move. A shadow row
whose side differs from the live plan's now reads "SHADOW PLAN A, recorded for grading and never
uploaded (P-9): the ladder calls this <ladder state>, so plan A puts it on the <good | not-good> side;
rule B says <verdict> for the window … so the live plan puts it on the <side> side. What follows is
plan A's own move, never uploaded." followed by plan A's own seat or queue clause; the P-4 "carries no
planned price" clause leaves with the rule-B sentence. A shadow row on the live plan's side keeps the
judgement's sentence. On the v27.159 partition of 2026-10-02 (built 01:20 UTC): 118 of 361 shadow rows
sided differently from the live plan, 110 plan-A GOOD rows carried the not-good side's words (54 of them
"competes for a seat at" beside "No move: the good side is never cut"), 8 plan-A NOT_GOOD rows the
good side's, and 8 priced rows said "carries no planned price" (audit counts for 09-28 … 10-01: sides
differ on 120 / 135 / 141 / 152; 59 / 75 / 77 / 89; 6 / 4 / 2 / 4). The query, on any partition:

```sql
SELECT a.as_of, COUNT(*) AS keys, COUNTIF(a.side != b.side) AS sides_differ,
       COUNTIF(a.side != b.side AND STRPOS(a.sentence, 'so plan A puts it on the') = 0) AS side_unnamed,
       COUNTIF(a.side = 'GOOD' AND a.side != b.side AND a.sentence LIKE '%competes for a seat at%'
               AND a.sentence LIKE '%No move: the good side is never cut%') AS good_row_promised_a_seat,
       COUNTIF(a.planned_bid IS NOT NULL AND a.sentence LIKE '%carries no planned price%') AS priced_says_none
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` a
JOIN `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` b
  ON b.as_of = a.as_of AND b.campaign_id = a.campaign_id AND b.keyword_id = a.keyword_id AND b.plan = 'B'
WHERE a.plan = 'A' AND a.as_of >= '2026-09-28'
GROUP BY 1 ORDER BY 1;
```

**What else had to follow the key, and what did not.**
- `FACT_PLAN_NEXT_WEEK_acceptance.sql` C01 and `V_ENGINE_HEALTH` `plan_window_complete_days` asserted
  `window_to = LEAST(watermark − 1, as_of − 2)`. On a partition the ~22:35 Los Angeles pass writes,
  `as_of` is the next New York date and the watermark has already advanced to the Los Angeles date
  (watermark = the build's Los Angeles date on all eight late partitions above), so that form fails
  every row. Both now fence on `DATE(built_at, 'America/Los_Angeles') − 2`, which equals `as_of − 2` on
  every Los Angeles-keyed partition.
- `V_PLAN_WINDOW_JUDGMENT_acceptance.sql`: the night clocks (C12's grace run, G1's history and
  tonight, G3, G4's memory and gap nights) moved to New York with the view; C01's fence and C06's
  settle date stay on Los Angeles.
- `plan_partition_fresh` keeps its clock (the later of yesterday and the Los Angeles day the plan step
  last ran): a New York `as_of` is never earlier than the Los Angeles day of its build, so every pass
  that saved its partition meets it. Only its comment changed.
- `FN_PLAN_SCORECARD`: Task 6 recorded "needed no change"; the Task 10 proof found that wrong, and
  follow-up F4 (2026-10-03) fixed it. `V_PLAN_SCORECARD` called the function on the Los Angeles date
  while `as_of` is a New York date, so from the 01:35 New York pass until Los Angeles midnight the
  scorecard left out the night that pass had just written (its decisions and its rule), and dated a
  night's 14-day age on a clock the key is not on. The function now takes **both clocks**:
  `grade_date`, the New York date nights are dated on (a graded night's 14-day age, and the nights
  the rule in force and the written decisions are read up to), and `ads_date`, the Los Angeles date
  ads days are on (`settle_due_on` = `window_to` + 7 / + 14, and the `FACT_AMAZON_ADS` fence). The view
  passes `CURRENT_DATE('America/New_York')` and `CURRENT_DATE('America/Los_Angeles')`, the judge's own
  two clocks, so a decision is graded when the judge would call its window `settled`
  (`today_la >= settle_due_on`), not up to three hours earlier. The graded days still start on the
  plan night. Measured 2026-10-03 at the clock of 22:40 Los Angeles 10-02 = 01:40 New York 10-03:
  the pre-F4 form read 123 guard decisions written, the two-clock function 136 (the 13 of the 10-03
  night), both 0 graded; the New York date alone would have graded 20 there. With one date passed
  twice the function equals the pre-F4 one row for row (2026-10-02, 10-03, 11-02).
  `PLAN_SCORECARD_acceptance.sql` holds both clocks at two boundaries built from the plan history
  (F4a: the pre-F4 view misses a night 14 days old on the New York date; F4b: the New York date alone
  grades before the settle date; F4c: the pre-F4 view misses the decisions of the night the 01:35
  pass wrote) — 46 of 46 PASS on 2026-10-03, controls in its header.
- The ramp step's upload count reads `applied_at` on the New York date, the clock `as_of` is on.
- `SEAT_REQUEST_acceptance.sql` R09 (added after review, 2026-10-03): `SP_APPEND_SEAT_REQUEST` copies
  the plan's `as_of` into `requested_on`, so `requested_on` is a New York date too. R09 counted a
  partition dated after `CURRENT_DATE('America/Los_Angeles')` as a future one, which the 01:35 New York
  pass (about 22:35 Los Angeles) writes every night; it now compares with
  `CURRENT_DATE('America/New_York')`. Controls on copies of the ledger with the clock pinned to 22:40
  Los Angeles 10-02 = 01:40 New York 10-03 (recorded in the file): the 10-02 partition copied to 10-03
  reads R09 118 under the old form and 0 under the new; copied to 10-04 it reads 118 under the new.
- `PLAN_HEALTH_acceptance.sql` C02b (added after the second review, 2026-10-03): the negative control
  of `plan_partition_fresh`, NC_DROP_LATEST, dropped only `MAX(as_of)`. After the 01:35 New York pass
  (about 22:35 Los Angeles, day D) that is the D+1 partition; D was left, equal to `due` (the Los
  Angeles day the step last ran), the control did not fire, and C02b read FAIL until the 04:10 New
  York pass. It now drops every partition dated on or after the Los Angeles day the plan step last
  ran, which is never later than `due`. Pinned-clock controls on the file's own text (recorded in
  its header, jobs `t6r3_c02b_*_035333`): at 22:40 Los Angeles 10-02 after a simulated 01:35 New York
  pass the old form reads 1 and the new 0; at 00:30 Los Angeles 10-03, before the 04:10 pass, 1 and
  0; at 10:30 Los Angeles 10-02, at 22:40 with the pass rewriting 10-02 as under v27.159, and at
  01:20 Los Angeles 10-03 after the 04:10 pass, 0 and 0. The live alarm was right throughout; only
  the control's premise moved.
- **Every test re-read for the key (2026-10-03).** A grep of `scripts/bigquery/tests/` (not `.bak`,
  not `archive/`) for files naming `as_of` or `requested_on` together with a Los Angeles or UTC clock
  found, besides the two above: `FACT_PLAN_NEXT_WEEK_acceptance.sql` (the C01 fence, already on the
  build's Los Angeles date); `PLAN_SCORECARD_acceptance.sql` (C10 and the gradable-night twins bound
  `as_of` by the same Los Angeles date `FN_PLAN_SCORECARD` is called with, so a New York partition
  dated tomorrow is left out of both — consistent with each other, and both wrong; since F4 they bound
  `as_of` by the New York date and `settle_due_on` by the Los Angeles date, as the view does); `V_PLAN_WINDOW_JUDGMENT_acceptance.sql` (C01's fence and C06's
  settle date compare ads dates, Los Angeles by design); `V_FAMILY_SEAT_REGISTER_acceptance.sql` (a
  change's Los Angeles date against ads dates, no `as_of`); `check_judge_memory_controls.py` (doctored
  `hold_settles_on`, an ads date, and `grace_ends_on` set to Los Angeles yesterday, which is before the
  New York date C12 compares it with at every hour); `check_plan_clock_controls.py` (NC_K1 stamps a
  22:40 Los Angeles build on purpose); `PLAN_OWNERSHIP_acceptance.sql` (holdout `eligible_from`, no
  `as_of`). No other test compares `as_of` or `requested_on` with a clock.
- **Not changed, recorded:** `tools/build_reprice_bulksheet.py` still reads the plan's history with
  `as_of < CURRENT_DATE('America/Los_Angeles')` (and still carries v27.135's grace reading); between
  21:00 and 24:00 Los Angeles its history stops a night short of the judge's. The judge's `holdout`
  flag compares `eligible_from` with the Los Angeles date; every eligible date is in the past, so no
  row moves today.

### Deploy and verify v27.160 (2026-10-02, piece-1 Task 6)

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"          # a long job: submit with --nosync and poll
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
# the negative controls of C01, K1, K2, K3 and V_ENGINE_HEALTH plan_window_complete_days (exit 0 =
# every control exercised and as expected). One script job: submit, then collect.
python3 scripts/bigquery/tests/check_plan_clock_controls.py --submit
python3 scripts/bigquery/tests/check_plan_clock_controls.py --collect <the JOB it printed>
```

Measured at deploy (2026-10-02 Los Angeles; 02:36–03:07 UTC 10-03). Before deploy, with both dates
10-02: the v27.160 judge body run as a query equalled the deployed v27.157 view on all 98 columns of
361 rows (floats to 1e-9 relative; 639.0 against 527.6 slot-seconds, 127,819,989 bytes each); the
builder body on that snapshot, writing to a copy of the table (`OI._tmp_t6_plan`), passed every
assertion and differed from the v27.159 partition of 10-02 only in `sentence` on the 118 shadow rows
whose side differs from the live plan's, `rank_no` on one tied pair (LolliME ranks 10 / 11, scores
equal to the last bit) and `built_at`; the plan acceptance read 37 of 37 PASS on it. Deployed at
02:45:20 UTC (`INFORMATION_SCHEMA.ROUTINES.last_altered`; each deployed body equals its file). One
CALL (job `t6_call1_1790995726`, 2,048.7 slot-seconds) rewrote the 2026-10-02 partition — the New
York date at 19:50 Los Angeles — with the same 722 rows, money, seats and moves (the same three
column differences as the dry run); the plan acceptance read 37 of 37 PASS (job
`t6_acc_live1_1790995837`, 1,383.0 slot-seconds) and the board's `plan_window_complete_days` GREEN.
On the v27.159 partition K3 read 244 (118 / 110 / 8 / 8 on its four terms).

The guard was controlled on the builder's own body against a copy of the table: over the copy's
BOOST partition of the same date it wrote (627.4 slot-seconds); with that partition set to OFF_PEAK it
raised `partition 2026-10-02 was written under OFF_PEAK; tonight reads BOOST; refusing to rewrite …`
and the OFF_PEAK partition stood, 722 rows, `built_at` unchanged (1,070.2 slot-seconds). The negative
controls (`check_plan_clock_controls.py`, job `bqjob_r28d04f5d6d9da7e1_000001a0ffabd93a_1`, 2,642.4
slot-seconds) exited 0: LIVE 39 readings 0, all 11 copies exercised as expected (per-copy values in
the acceptance file's header).

**The late pass, simulated.** No orchestrator pass had yet run under v27.160, and the case R11 is
about — the ~22:35 Los Angeles pass, already the next New York date, after `FN_ADS_ANCHOR_CAP` has
advanced — cannot be produced by a CALL before 22:00 Los Angeles. So both v27.160 bodies were run
with the Los Angeles date 10-02, the New York date 10-03, `FN_ADS_ANCHOR_CAP` 10-02 and `built_at`
05:40 UTC (22:40 Los Angeles) written in, on a copy of the table holding the CALL's 10-02 partition
(`OI._tmp_t6_sim_judge`, `OI._tmp_t6_sim_plan`; 401.6 and 1,006.1 slot-seconds). It wrote as_of
2026-10-03, BOOST, window 09-28 … 09-30 behind watermark 10-02; every assertion passed. On that
partition the v27.159 fence form (`as_of − 2`) reads 722 of 722 rows wrong and the v27.160 form 0;
the controls script on the copy exited 0 (job `bqjob_r3b355b0a9c44aefd_000001a0ffb852de_1`, 2,407.5
slot-seconds; LIVE 39 readings 0, including T1 and C23 over 82 real incumbents). The judge acceptance
with the same dates written in read 30 of 30 PASS; the v27.159 judge acceptance (every clock Los
Angeles) read G1 6 and G3 2 on the same tables. Live plan B, the CALL's 10-02 partition against the
simulated 10-03 one (the first night P-16 meets seats written with `seat_since`):

| family | seats 10-02 → 10-03 | incumbents kept / new / left | pot $/day | allowance $/day | expected after upload $/day | GRACE | HELD | releases |
|---|---|---|---|---|---|---|---|---|
| Bottle | 3 → 3 | 3 / 0 / 0 | 12.54 → 4.46 | 0.74 → 0.74 | 0.70 → 0.70 | 1 → 0 | 0 → 0 | 0 → 1 |
| Fresh | 22 → 22 | 22 / 0 / 0 | 104.40 → 104.40 | 58.58 → 58.58 | 57.06 → 57.06 | 8 → 8 | 0 → 0 | 1 → 0 |
| LolliME | 49 → 53 | 49 / 4 / 0 | 337.69 → 318.30 | 136.03 → 155.42 | 132.39 → 152.26 | 20 → 14 | 0 → 2 | 1 → 4 |
| Lollibox | 8 → 9 | 8 / 1 / 0 | 147.25 → 147.04 | 37.19 → 37.40 | 36.76 → 36.97 | 6 → 5 | 0 → 0 | 4 → 1 |

What moved is the ruling, not the data: the window (09-28 … 09-30) and the calendar state are the
same on both sides (the watermark moved 10-01 → 10-02 when `FN_ADS_ANCHOR_CAP` advanced at 22:00 Los
Angeles, and the fence held the window where it was). The night is one later, so the judge's memory reads 10-02 as last night: the v27.157
judge at the same simulated clock (history before 10-02) against v27.160's (history through 10-02)
— 8 grace runs counted one more night and spent, 6 of them to the not-good side ($27.68 a day of
window spend: Bottle 1, LolliME 4, Lollibox 1) and 2 LolliME held instead; `prior_good` differs on 53
rows. Under v27.159 that pass would have rewritten 10-02 itself.

```sql
-- the late-pass fence, on any partition: the v27.159 form and the v27.160 form
SELECT as_of, DATETIME(MAX(built_at), 'America/Los_Angeles') AS built_la, COUNT(*) AS n,
       COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY), DATE_SUB(as_of, INTERVAL 2 DAY))) AS v27159_form_wrong,
       COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY),
                                  DATE_SUB(DATE(built_at, 'America/Los_Angeles'), INTERVAL 2 DAY))) AS v27160_form_wrong
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` GROUP BY 1 ORDER BY 1;
```

Nothing new reads `FACT_AMAZON_ADS`; the judge's one scan is unchanged in bytes. A direct run of
`V_PLAN_WINDOW_JUDGMENT_acceptance.sql` on the deployed view was cancelled at 354,660 slot-seconds
(its header records 1,180,821 for one run: every CTE that reads `j` re-evaluates the view) — use
`check_judge_memory_controls.py`, which reads the view once.

`check_judge_memory_controls.py` on the deployed v27.160 view and the live history, after the CALL
(both dates 10-02; job `bqjob_r50cef6748812af44_000001a0ffbb3ea6_1`, 7,661.3 slot-seconds): exit 0,
LIVE 30 checks 0, all 34 copies as expected — the restated night clocks keep their controls.

### Brand defense is read from the campaign (v27.161, piece-1 Task 7 — audit fix #18)

§8 keeps brand defense out of the plan: it is never judged on profit. The judgement view enforces
that with the ladder's flag (`V_PLAN_WINDOW_JUDGMENT`'s `ks` CTE: `NOT COALESCE(s.is_brand_defense,
FALSE)`), and until v27.161 `SP_SNAPSHOT_KEYWORD_STATE` took that flag from `V_BID_CPC_TRANSFER`
alone — a view that keeps only campaigns with clicks in its placement window. BOTTLE-VIDEO/PHRASE
(Brand Defense) `92805659761140` had none, so its five keywords (the house's own "happy lolli truth
or dare" terms) read "not defense" and sat in the universe: 5 rows a night in each plan, 2026-09-28 …
10-02, side NOT_GOOD on plan B, verdict NOT_SERVING, no candidate, move NONE, cap basis
`NO_MOVE_BRAND_DEFENSE` (the builder's name gate; item 5 of "What Ori rules from this pass" below).
The audit (2026-10-02) read that its first served window would have made it a candidate: the keyword
path has no defense test, and the move CASE then yields PARK, HOLD_AT_PARK, REPRICE or HOLD_AT_PRICE.

**The rule (v27.161).** `is_brand_defense` = "BRAND DEFENSE" in the campaign's name (the name
`FACT_PANEL_OWNERSHIP` gives it, or `V_DIM_CAMPAIGN_CURRENT`'s) **or** the campaign sits in a
`DIM_EXPERIMENT` whose `strategy_id` is `BRAND_DEFENSE` (through `DIM_EXPERIMENT_CAMPAIGN`) **or**
`V_BID_CPC_TRANSFER`'s flag, last. `PRODUCT_DEFENSE` is not brand defense — extending the exclusion to
it is a ruling (§8 says brand defense; 3 PT product-defense campaigns sit in the 10-02 ladder
snapshot, one row each, family NULL, so none reaches the plan).
SOP of the ladder: `architecture/KEYWORD_STATE.md`.

**C02 restated** (`V_PLAN_WINDOW_JUDGMENT_acceptance.sql`). It read the flag — the column the
universe filter reads — so it passed by construction. It now counts universe rows whose campaign is
brand defense by name (the row's own name, or the dimension's) or by experiment strategy, each read
from its own source, plus two emptiness terms: no judgement row, or no defense keyword in the latest
ladder snapshot (HARVEST family the judgement covers, ENABLED campaign, not LAUNCH_CONTAINED) for the
exclusion to act on.

### Deploy and verify v27.161 (2026-10-02, piece-1 Task 7)

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"       # ~20 s; the orchestrator's 20.8 runs it nightly
# the judge's checks and their negative controls: one script job, submitted and collected
python3 scripts/bigquery/tests/check_judge_memory_controls.py --submit
python3 scripts/bigquery/tests/check_judge_memory_controls.py --collect <the JOB it printed>
```

```sql
-- the flag against the campaign, on the live snapshot: every defense campaign's keyword flagged
WITH d AS (
  SELECT CAST(campaign_id AS STRING) AS cid FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE REGEXP_CONTAINS(UPPER(campaign_name), r'BRAND DEFENSE')
  UNION DISTINCT
  SELECT CAST(ec.campaign_id AS STRING) FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING (experiment_id) WHERE e.strategy_id = 'BRAND_DEFENSE')
SELECT COUNTIF(campaign_id IN (SELECT cid FROM d)) AS defense_rows,
       COUNTIF(campaign_id IN (SELECT cid FROM d) AND is_brand_defense) AS flagged,
       COUNTIF(campaign_id NOT IN (SELECT cid FROM d) AND is_brand_defense) AS flagged_elsewhere
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;
```

Measured at deploy (2026-10-02 Los Angeles, 04:05–04:40 UTC 10-03):

- **Before deploy, on the same inputs.** The v27.105 body and the v27.161 body, each run as a query
  into a scratch table with the 16:55 UTC snapshot as the prior row (`OI._tmp_t7_ks_old` /
  `_tmp_t7_ks_new`, prior = `OI._tmp_t7_ks_before`; all expire 2026-10-10): 818 rows each, every
  column equal except `is_brand_defense` on the five keywords of `92805659761140` (FALSE → TRUE).
  The query above: 28 defense rows, 23 flagged before, 28 after, 0 flagged elsewhere. Three paired
  runs, slot-seconds new / old: 2,140.3 / 162.7, 245.3 / 155.1, 264.6 / 202.8; bytes 130,905,146 /
  130,856,111 (the two experiment tables and `DIM_CAMPAIGN`; no new read of `FACT_AMAZON_ADS`).
- **The restated C02 on the deployed v27.160 judge over the v27.105 snapshot** (C02's CTEs with `j` =
  the view, job `bqjob_r14efa745090b29e6_000001a0fff6862f_1`, 913.9 slot-seconds): **5** — the five
  rows of `92805659761140`, out of 361; the population term read 28.
- **Deployed** 04:13:01 UTC (`INFORMATION_SCHEMA.ROUTINES.last_altered`; the deployed body equals
  the file with comment lines stripped). **One CALL** (job
  `bqjob_r51a275a2a3c5e62c_000001a0fff76ba5_1`, 216.0 slot-seconds, 151,910,622 bytes, ~21 s)
  rewrote the 10-02 snapshot: against the 16:55 UTC snapshot `is_brand_defense` changed on exactly
  those five rows (FALSE → TRUE), no `state` changed; `m_effective` (115 rows), `affordable_bid` /
  `clean_affordable_bid` (92) and `prior_state` (1) moved with the data — the v27.105 body reproduces
  all three on the same inputs.
- **After:** the same C02 query on the deployed judge (job
  `bqjob_r459e37318be25532_000001a1000027cc_1`, 968.6 slot-seconds): **0**; the universe 361 → 356
  rows, none of `92805659761140`; population 28. The plan table keeps those five rows until the next
  builder pass writes a partition without them; nothing else in the plan moves (they had no spend, no
  candidacy and no move). Both C02 queries read the population term through `V_BOOK_ASSIGNMENT`;
  the file now reads it over the judgement's own HARVEST families (below).
- **The negative controls** (`check_judge_memory_controls.py`, now one script job: every copy
  INSERTs into a temp table and the last statement reads it, so `--submit` / `--collect` poll it with
  `bq wait` like `check_plan_clock_controls.py`; two more sources are swapped per copy,
  `DIM_EXPERIMENT_CAMPAIGN` and `FACT_KEYWORD_STATE`). Job
  `bqjob_rfd55d4d6239c64c_000001a1000386e3_1`, 13,281.6 slot-seconds: exit 0, LIVE 30 checks 0, all
  37 doctored copies as expected — the 32 earlier ones unchanged, and a universe row's name given
  " (Brand Defense)" 1, " (Product Defense)" 0, its campaign (`104973644967484`) put in a
  `BRAND_DEFENSE` experiment 9 (its 9 universe rows — the first run expected 1 and read 9), in a
  `PRODUCT_DEFENSE` one 0, an empty ladder snapshot 1, an empty judgement 2. Per-copy values are in
  the acceptance file's header.
- **What the restated C02 costs.** Its first form read `V_BOOK_ASSIGNMENT` for the HARVEST families,
  77,330,550 bytes a read (bq dry run), once per copy: the first two control runs cost 19,084.8 and
  22,462.4 slot-seconds (104.3 MB a copy) against 7,661.3 for the v27.160 run (65.5 MB a copy).
  Reading the families from the judgement's own `book` column brought it to 64.9 MB a copy and
  13,281.6 slot-seconds. Run the file through the script, never directly (§2's deploy notes).

### An incumbent's cost is tonight's money (v27.164, piece-1 follow-up F2 — P-16)

**The defect.** P-16 keeps an incumbent's seat, number, planned price, verdict date and question.
v27.159–v27.160 also kept the **cost** its seat was granted at — the window of the night it was
seated, at that price — and charged it to the allowance. When tonight's window spent less, or the
price sat at tonight's bid, the seat sentence still said "A RAISE", and the family's
`expected_after_upload_per_day` and `share_closed` read the seating night's money. On the 2026-10-03
partition built 08:12 UTC by v27.160: **30 live incumbent rows** (Bottle 1, Fresh 7, LolliME 20,
Lollibox 2) said "That is A RAISE of about $X" with their planned bid at or under their current bid,
**$15.24 a day** in total (29 ordinary seats, $15.14, and the probe below); plan A had 13 more
ordinary seats ($11.84).

**The rule (v27.164).** An incumbent costs its **kept price on tonight's window**:
`w_sp / window_days × kept planned bid / current bid` (0 with no spend or no current bid, P-6), and on
a keyword that is a probe tonight `click_goal_day × kept price` (P-25's costing of a probe opened at a
price; the judge costs a probe without a LIFT price by its window or its seat CPC, but an incumbent
probe's price is the one it opened at). The incumbents' walk charges
it to the allowance, and `planned_spend_per_day`, the direction clause, the campaign need,
`expected_after_upload_per_day` and `share_closed` read it. The question is unchanged — clicks, due
date, expected CPC, implied spend and basis are the ones the seat was given — so on an incumbent
`implied_daily_spend` is the money of the night it was asked and `seat_cost_per_day` is tonight's
(on the v27.164 partition of 10-03 they differ by more than a cent on 96 of 113 incumbents).

*A reading recorded for Ori:* "probe" is tonight's `is_probe`, the flag the move reads
(`OPEN_PROBE`). On 10-03 one live incumbent, Fresh `388620934464557`, was seated on 10-02 as an
ordinary seat (`HOLD_AT_PRICE` at $0.25, 1 click in its window, $0.1067 a day) and is a LIFT probe
nominee tonight with no window spend: it opens as a probe at its kept $0.25 and costs 4 × $0.25 =
$1.00 a day, while its question still asks the 5 clicks by 2026-10-16 it was given. *To overrule:*
test the seat's own basis (`request_basis = 'HORIZON_PROBE_GOAL'`) instead of `is_probe` in
`ranked`.inc_cost, the P-16 assertion and acceptance `T1`.

**Checks.** `T1` (acceptance) and the builder's P-16 assertion recount an incumbent's cost from its
row — the kept price is the previous partition's `planned_bid`, `click_goal_day` is read from the
judgement — and test an eviction against the same recount (both compared the cost with the
contract's until v27.160). `T3` and `PLAN_SEAT_REQUEST` `S04` compare implied spend with seat cost on
seats taken tonight only; `S04` gains an emptiness term.

### Deploy and verify v27.164 (2026-10-03, piece-1 follow-up F2)

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"          # then bq wait <job> 60 until DONE
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/tests/PLAN_SEAT_REQUEST_acceptance.sql)"
python3 scripts/bigquery/tests/check_plan_seat_controls.py --submit --judge-table <a snapshot of the judgement>
python3 scripts/bigquery/tests/check_plan_seat_controls.py --collect <the JOB it printed>
```

```sql
-- incumbents that say "A RAISE" while their price is held or cut (0 from v27.164; probes apart:
-- an opening probe raises spend from nothing to the clicks it asks for, P-25)
SELECT plan, family, COUNTIF(seat_tenure = 'INCUMBENT') AS incumbents,
       COUNTIF(seat_tenure = 'INCUMBENT' AND NOT is_probe AND sentence LIKE '%That is A RAISE of about%'
               AND planned_bid <= current_bid + 0.005) AS raise_said_at_held_or_cut_price,
       ROUND(SUM(IF(seat_tenure = 'INCUMBENT', seat_cost_per_day, 0)), 2) AS incumbent_cost,
       ROUND(MAX(expected_after_upload_per_day), 2) AS expected_after_upload, MAX(share_closed) AS share_closed
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
GROUP BY 1, 2 ORDER BY 1, 2;
```

Measured 2026-10-03 (08:48–09:10 UTC). Both bodies were run on one judgement snapshot,
`OI._tmp_f2_judge` (taken 08:48 UTC, window 09-29 … 10-01, BOOST, 356 rows; 417.0 slot-seconds), as
dry runs writing scratch tables (`OI._tmp_f2_old` / `_tmp_f2_new`, 508.5 / 604.6 slot-seconds); every
builder assertion passed on both. The v27.160 dry run carries the same 43 "A RAISE at a held or cut
price" incumbent rows as the 08:12 partition (30 plan B, 13 plan A; equal key sets).

| family (plan B) | incumbents | incumbent cost $/day | seats | seat cost $/day | expected after upload $/day | share closed | ordinary incumbents saying "A RAISE" at a held or cut price |
|---|---|---|---|---|---|---|---|
| Bottle | 3 → 3 | 0.70 → 0.46 | 3 → 4 | 0.70 → 1.63 | 1.04 → 1.63 | — (under target) | 1 → 0 |
| Fresh | 22 → 22 | 57.06 → 61.43 | 24 → 24 | 68.08 → 72.46 | 75.18 → 79.55 | 0.438 → 0.373 | 6 → 0 |
| LolliME | 47 → 47 | 124.65 → 115.93 | 51 → 53 | 160.03 → 161.15 | 166.55 → 163.07 | 0.188 → 0.292 | 20 → 0 |
| Lollibox | 5 → 5 | 6.33 → 6.99 | 7 → 7 | 6.58 → 7.24 | 6.58 → 7.24 | — (under target) | 2 → 0 |

Plan A's 13 such rows read 0 too. The two Fresh probe incumbents (`271226499623994` at $0.27,
`388620934464557` at $0.25) say "A RAISE … in spend" on both sides: an opening probe's spend rises from
nothing to the clicks it asks for (P-25); `388620934464557` went from $0.1067 to $1.00 a day.

- The money freed or taken by the restated cost moved seats on 7 rows: plan B seats three newcomers
  (Bottle `460474443550039`, re-priced $1.00 → $0.86; LolliME `288339178183774` and `174400329814141`,
  held at their price) that were parked; plan A keeps two Lollibox incumbents its stale costs had
  sent out as `LEFT_ALLOWANCE_SHRANK` (`518360001113420`, `491299818636882`) and no longer opens two
  newcomer probes (Fresh `321619237632774`, LolliME `207390974307873`). No other row changed seat,
  move, rank, price or question; 38 of 114 plan × campaign caps changed (334 rows).
- After deploy (08:56:59 UTC, `INFORMATION_SCHEMA.ROUTINES.last_altered`; the deployed body equals the
  file with comment lines stripped), one CALL (job `f2_call_1791017831`, 700.8 slot-seconds, 94.6 s)
  rewrote the 10-03 partition: every non-float column equal to the v27.164 dry run on all 712 rows,
  floats within 2.9e-14.
- Acceptance on the live partition and the deployed view: 37 rows PASS (job
  `f2_acc_live_1791017982`, 617.4 slot-seconds, 140,894,039 bytes); `PLAN_SEAT_REQUEST` 11 PASS. The
  new `T1` reads 99 on the v27.160 partition (same snapshot); the v27.160 forms read `T1` 101, `T3` 96
  (job `f2_accH_live_1791018032`) and `S04` 96 on the v27.164 partition. The file now reads the
  judgement twice (C13 and T1's click goal); the bytes are the same for both forms (140,894,039, bq dry
  run), and the old form's run right after took 5,414.7 slot-seconds, so the slot cost of one run
  says little.
- **The negative controls** (`check_plan_seat_controls.py --judge-table onyga-482313.OI._tmp_f2_judge`,
  job `bqjob_r78febaf76288764f_000001a100fdebd9_1`, 8,715.2 slot-seconds): exit 0, LIVE 50 readings 0,
  all 32 copies exercised and as expected. New: an incumbent carrying its contract's cost (v27.160's
  rule) T1 1; the incumbent made a probe and costed 4 × its kept price T1 0, costed by its window T1 1;
  a NEW seat's cost $0.50 off its implied spend S04 1 and T3 1; the empty partition S04 1. The eviction
  copies now price the dropped contract (it is the price, not the cost, that the recount reads): $0.00
  → T1 1, $1,000,000 → T1 0. Per-copy values are in `FACT_PLAN_NEXT_WEEK_acceptance.sql`'s header.
- **The builder's own assertion, controlled:** the v27.164 body with v27.160's cost restored (the walk
  and the written cost read the previous partition's `seat_cost_per_day`) was refused by the P-16
  assertion alone on the same snapshot ("an incumbent before its verdict date that is still a
  candidate keeps its seat and its contract, … (P-16)", job `f2_dry__tmp_f2_nc_1791017706`, 381.5
  slot-seconds); every assertion before it passed.

### The GRACE sentence states the anchored rule (v27.165, piece-1 follow-up F3 — P-17)

**The defect.** P-17 anchors a grace run to the night it was granted: it lasts the `window_days` in
force that night. The judge's GRACE sentence still opened with P-5's words, "A proven winner keeps
the good side for ONE quiet window (P-5)", and then granted the run's own length. On 2026-10-03
(window 09-29 … 10-01, BOOST, 3-day window) all 33 GRACE rows said it, 13 of them on a run of 7
nights granted 2026-09-28 under a 7-day window, through 2026-10-04.

**The rule (V_PLAN_WINDOW_JUDGMENT v27.165).** The sentence states the anchored rule with the row's
own run: "A proven winner keeps the good side, held, not cut (P-5): grace lasts N nightly judgments
(the window length in force when it was granted, `grace_since`) through `grace_ends_on` (P-17, Ori
2026-10-02)." The unarmed branch says "THE GRACE LIMIT IS NOT ARMED TONIGHT" (it said "THE
ONE-WINDOW LIMIT"). No verdict, side, price or date changes. `SP_BUILD_NEXT_WEEK_PLAN` copies the
sentence into the plan's rows, so a partition carries the new words from the first build after the
deploy. The 2026-10-03 partition (built 08:58:26 UTC, before the 09:27 deploy) carries the old words
on its 33 GRACE rows of each plan; no CALL was run for this fix, so the next orchestrator build is the
first to write the new ones.

**Check.** Acceptance `C22` is restated: every GRACE sentence carries
`FORMAT('grace lasts %d nightly judgments (the window length in force when it was granted, %t) through %t', grace_window_days, grace_since, grace_ends_on)`
and says SPENT-from or NOT ARMED; no sentence says "ONE quiet window" or "ONE-WINDOW LIMIT"; a NULL
sentence on a GRACE row counts; a judgement with no GRACE row reads 1 (emptiness).

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
python3 scripts/bigquery/tests/check_judge_memory_controls.py --submit      # prints JOB=...
bq wait <JOB> 60                                                           # repeat until DONE
python3 scripts/bigquery/tests/check_judge_memory_controls.py --collect <JOB>
```

```sql
-- GRACE rows, the runs that outlast tonight's window, and any sentence still in P-5's words
SELECT family, COUNTIF(verdict = 'GRACE') AS grace,
       COUNTIF(verdict = 'GRACE' AND grace_window_days != window_days) AS run_length_not_tonights_window,
       COUNTIF(REGEXP_CONTAINS(sentence, r'ONE quiet window|ONE-WINDOW LIMIT')) AS old_words
FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1 ORDER BY 1;
```

Measured 2026-10-03 (Los Angeles and New York both 10-03). The deployed v27.160 view was
snapshotted at 09:26 UTC (`OI._tmp_f3_judge_old`, 747.8 slot-seconds), the v27.165 view deployed at
09:27 and snapshotted at 09:28 (`OI._tmp_f3_judge_new`, 666.4 slot-seconds; 128,069,145 bytes each).
Keyed on campaign × keyword: 356 rows each side; of the 98 columns besides the key, 97 equal on every
row (floats to 1e-9 relative); `sentence` differs on the 33 GRACE rows only, each the old sentence
with the rule phrase replaced. The restated `C22` reads 66 on the old snapshot (33 without the
anchored rule, 33 saying "ONE quiet window") and 0 on the new one; the v27.156 form read 0 on both.
`check_judge_memory_controls.py` on the deployed view (job
`bqjob_r4f85b3c63fa8c3e1_000001a101194d2f_1`, 15,213.5 slot-seconds): exit 0, LIVE 30 checks 0, all
40 doctored copies as expected. The new ones: the rule put back to the v27.160 words `C22` 2; a
7-night run's sentence saying 3 `C22` 1; every GRACE verdict made GOOD `C22` 1; the empty judgement
`C22` 1. A GRACE row with a NULL sentence (C22's CTE alone on a copy of the new snapshot) reads 1; the
v27.156 form read 0 on it.

### Incumbents leave latest-seated first (v27.167, piece-1 follow-up F8 — P-16)

**The defect.** R2 (P-16): if tonight's allowance cannot carry every incumbent, those seated latest
leave first. v27.159–v27.164 walked the incumbents in seat order with the newcomers' fit test (skip
and continue), so an earlier, costlier incumbent could leave while a later, cheaper one kept its seat
(reading 2 of "Tenure, probes, the question and the numbers"; the Task 10 proof listed it as R2 not
built as worded). The live 2026-10-03 partition (v27.164, built 08:58 UTC) carries 0
`LEFT_ALLOWANCE_SHRANK` rows in either plan; the proof counted 0 plan-B rows and 2 plan-A Lollibox
rows on the v27.160 build of that night, sent out by the stale costs F2 retired.

**The rule (v27.167).** The incumbents' walk (`walk_inc`) is a **prefix** of the incumbents in seat
order (`seat_since`, then tonight's rank): it keeps them while the running cost fits the ramped
allowance, and the first one that does not fit leaves together with every incumbent seated after it,
however cheap. No incumbent's cost is negative (each branch of `inc_cost` multiplies a bid, a click
goal or a window spend), so this is exactly the set left by dropping the latest seated one at a time
until the rest fit. An incumbent that leaves is then a candidate like any other in the newcomers'
walk, at tonight's price and in rank order (unchanged). The TENURE ENDS EARLY sentence states R2's
rule and what the kept incumbents cost: "… cannot carry every incumbent, so incumbents leave
latest-seated first until the rest fit (P-16): the 9 that keep their seats were all seated before it
(tonight's rank breaking a tie of seat dates) and cost $69.00 a day, so it gives the seat up before
its date." (v27.164: "incumbents keep their seats in the order they took them, and this one no longer
fits behind those seated before it" — the fit test's words.)

*A reading recorded for Ori:* the newcomers' walk still re-seats an incumbent the prefix sent out when
its rank comes up and its cost at tonight's price fits (as since v27.159). It then holds a NEW seat —
a new verdict date and question — not its old contract. On the doctored copy below, 20 of the 84
incumbents v27.167 sends out are re-seated that way, so a later-seated keyword can end the night in a
seat while an earlier one queues. *To overrule:* leave walk 1's leavers out of `new_order`.

**Checks.** The builder's P-16 assertion and acceptance `T1` read walk 1's order (`inc_pos`: the
previous partition's `seat_since`, then tonight's rank): no incumbent that left (a re-seat as NEW
included) comes before one that kept its seat, and the **first** one that left costs more than the
allowance leaves after the kept ones. Until v27.164 both asked that of **every** incumbent that left
— the fit test's own invariant, which passes the skip and refuses the prefix (a later leaver can be
cheap enough to fit). `T1`'s sentence term asks a `LEFT_ALLOWANCE_SHRANK` row for R2's words.

### Deploy and verify v27.167 (2026-10-03, piece-1 follow-up F8)

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync \
  "$(grep -v '^[[:space:]]*--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"   # bq wait <job> 60
python3 scripts/bigquery/tests/check_plan_seat_controls.py --submit --judge-table <a snapshot of the judgement>
python3 scripts/bigquery/tests/check_plan_seat_controls.py --collect <the JOB it printed>
```

```sql
-- incumbents on the latest partition, in walk 1's order: first_left_pos < last_kept_pos is a leaver
-- seated before a kept incumbent, the skip v27.167 retires
WITH h AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
           WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                          WHERE as_of < (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`))),
p AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
      WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)),
e AS (SELECT p.plan, p.family, p.seat_tenure,
             ROW_NUMBER() OVER (PARTITION BY p.plan, p.family ORDER BY h.seat_since, p.rank_no, p.campaign_id, p.keyword_id) AS pos
      FROM h JOIN p USING (plan, family, campaign_id, keyword_id)
      WHERE h.seat_no IS NOT NULL AND h.seat_since IS NOT NULL AND h.verdict_date > p.as_of
        AND p.is_candidate AND COALESCE(p.ladder_state, '') != 'DEAD')
SELECT plan, family, COUNT(*) AS incumbents, COUNTIF(seat_tenure = 'INCUMBENT') AS kept,
       COUNTIF(seat_tenure = 'LEFT_ALLOWANCE_SHRANK') AS left_allowance_shrank,
       COUNTIF(seat_tenure = 'NEW') AS left_and_reseated_new,
       MAX(IF(seat_tenure = 'INCUMBENT', pos, 0)) AS last_kept_pos,
       MIN(IF(COALESCE(seat_tenure, '') != 'INCUMBENT', pos, NULL)) AS first_left_pos
FROM e GROUP BY 1, 2 ORDER BY 1, 2;
```

Measured 2026-10-03 (11:00–11:22 UTC, Los Angeles and New York both 10-03).

- **No change on tonight's data.** One judgement snapshot, `OI._tmp_f8_judge` (taken 11:00 UTC, window
  09-29 … 10-01, BOOST, 356 rows; 610.0 slot-seconds). Both bodies dry-run on it (the partition write
  swapped for a scratch table; v27.164 812.9, v27.167 884.1 slot-seconds): every builder assertion
  passed, and the two would-be 10-03 partitions are equal on all 712 rows, every column but
  `built_at`, floats exactly. Against the live 10-03 partition (built 08:58 UTC by v27.164) the v27.167 dry run differs
  only in `sentence` on 66 rows — the 33 GRACE rows of each plan, which carry F3's words (deployed after
  that build) — and by at most 2.9e-14 on floats. No incumbent leaves on that night.
- **A night that shrinks.** A copy of the snapshot with LolliME's and Fresh's `allowance_share` 0.25 and
  `ramp_steps` 1 (`OI._tmp_f8_judge_shrunk`, so their allowance is a quarter of the pot) shrinks four
  plan × family walks; the other four carry every incumbent under both bodies. Every incumbent took
  its seat on 10-02, so tonight's rank decides the order. Costs are each incumbent's kept price on
  tonight's window.

  | plan · family | allowance $/day | incumbents ($/day) | v27.164 kept ($/day) · left · kept after one that left ($/day) | v27.167 kept ($/day) · left · re-seated as NEW |
  |---|---|---|---|---|
  | A · Fresh | 38.86 | 14 (53.31) | 10 (38.80) · 4 · 6 (5.85) | 4 (32.94) · 10 · 6 |
  | A · LolliME | 83.73 | 16 (130.52) | 7 (83.70) · 9 · 6 (29.54) | 1 (54.16) · 15 · 8 |
  | B · Fresh | 18.69 | 22 (61.43) | 7 (18.64) · 15 · 6 (15.23) | 1 (3.42) · 21 · 5 |
  | B · LolliME | 69.68 | 47 (115.93) | 10 (69.67) · 37 · 1 (0.67) | 9 (69.00) · 38 · 1 |

  v27.164: 19 incumbents kept a seat after an earlier one left ($51.29 a day), and 45 that left were
  seated before one that kept its seat. v27.167: 0 and 0; 84 leave, 64 as `LEFT_ALLOWANCE_SHRANK` and
  20 re-seated by the newcomers' walk as NEW.
- **The builder's assertion, controlled on that copy.** The v27.167 body with walk 1 put back to the fit
  test was refused by the P-16 assertion (job `f8_dry__tmp_f8_ncwalk_shrunk_1791025762`, 1,094.3
  slot-seconds); the prefix walk under v27.164's eviction test was refused by the same assertion (job
  `f8_dry__tmp_f8_oldassert_shrunk_1791025765`, 1,142.1 slot-seconds); the v27.164 body (job
  `f8_dry__tmp_f8_old_shrunk_1791025558`, 1,457.5) and the v27.167 body (job
  `f8_dry__tmp_f8_new_shrunk_1791025760`, 1,803.6) passed every assertion.
- **Acceptance.** On the live partition and the deployed view: 37 rows PASS (job
  `f8_acc167_live_1791025929`, 2,365.3 slot-seconds). On the shrunk copy (history = the live table
  before 10-03 + the dry run's 10-03 partition): this form reads 37 PASS on the v27.167 partition and
  `T1` 110 on the v27.164 one (45 leavers before a kept incumbent + 65 TENURE ENDS EARLY sentences in
  the fit test's words); v27.164's form reads `T1` 59 on the v27.167 partition (later leavers cheap
  enough to fit the room the kept ones leave) and 37 PASS on the v27.164 one.
- **The negative controls** (`check_plan_seat_controls.py --judge-table onyga-482313.OI._tmp_f8_judge`,
  job `bqjob_r7aa7d0f7442a1a18_000001a10177bacd_1`, 10,719.1 slot-seconds): exit 0, LIVE 50 readings 0,
  all 35 copies exercised and as expected. New: two contracts behind every kept incumbent, the earlier
  priced out and the later at $0.00, both leaving → `T1` 0; an eviction dated before every kept
  incumbent of its family → `T1` 1; an eviction in v27.164's words → `T1` 1. The same three copies
  under v27.164's acceptance form (job `bqjob_r3e728f553dd863_000001a1017a55a5_1`, 1,357.7
  slot-seconds) read 1, 0 and 0, so each tells the two forms apart. The eviction copies now doctor a
  queued row ranked after every kept incumbent of its family (LolliME `207390974307873`, rank 56; the
  second, LolliME `273302151474906`, rank 57).
- **Deployed** 11:16:17 UTC (`INFORMATION_SCHEMA.ROUTINES.last_altered`); the deployed body equals the
  file with comment lines stripped (50,034 characters, whitespace collapsed). No CALL was run: on the
  11:00 UTC judgement snapshot the v27.167 partition equals v27.164's on every column but `built_at`,
  so the next orchestrator pass is the first v27.167 write.

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
-- what the caps did tonight, by the reason the plan gives (v27.158: the basis names what bound
-- the cap — RAMPED, FLOORED_AT_NEED, BAND_SNAPPED_UP / _DOWN, FLOORED_AT_MINIMUM — and NO_MOVE_HOLDOUT
-- is the holdout's row, never moved; before v27.158 every moved cap read RAMPED)
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
   §9's reconciliation is restated (`C19`) rather than left as a claim nothing checked. **Ruled
   2026-10-02 (P-22, option (b)), built v27.158:** the arithmetic stays, and
   `expected_after_upload_per_day` / `share_closed` are published beside the allowance (§3, "The
   queue's residual is not zero money").
2. **A seat that raises.** P-6 costs a seat at the repaired price, and the ladder's repaired price
   can be above today's bid; regardless of allowance headroom, nothing stops the plan spending more
   there: the fit test has no direction term (audit 2026-10-02: seats raised spend in 16 of 16 live
   family-nights 09-28 … 10-01; the allowance exceeded the whole not-good side in 1 of them). It is
   published per row and per family (`planned_spend_delta_per_day`). **Ruled 2026-10-02 (P-19):** a
   not-good seat whose corrected return is under the family bar is never priced above its current
   bid; built in the judge v27.157 (§2, "No raise below the bar…"). Raises that remain: rows at or
   above the bar (P-6's price) and probes opening at LIFT's bid (P-25).
3. **P-7's degenerate rank** — **ruled 2026-10-02 (P-20):** candidates with no positive score rank
   by money burned with no return (`rank_money_burned`), not by clicks. Built in the judge v27.157
   and in this builder's `ranked` CTE in v27.159 (`GREATEST(rank_score, 0) DESC, rank_money_burned
   DESC, w_clk DESC`, keys; acceptance `T5`).
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
   because widening candidacy inside the builder would break `C13`. **Finished 2026-10-02 (v27.161,
   piece-1 Task 7, audit fix #18):** the ladder now reads the flag from the campaign (its name, or
   its experiment's `BRAND_DEFENSE` strategy, with `V_BID_CPC_TRANSFER`'s flag last), and the five
   keywords left the universe — see "Brand defense is read from the campaign" below.
6. **The book and the plan read one grace memory from v27.137 to v27.155, and not since v27.156.**
   `tools/build_reprice_bulksheet.py --rule-b` reads `FACT_PLAN_NEXT_WEEK` for P-5's limit with the
   v27.135 expression (the most recent GRACE later than the most recent GOOD); the judge now reads
   P-17 / P-29 (§2), and on 2026-10-02 the two disagreed on 41 keywords' `prior_grace`. The book
   also has no P-14c or P-18. Nothing to rule unless Ori wants the book to stop judging at all and
   read the plan's `side` directly — which is Task 4's design question; until then the judge is the
   authority.

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
| `plan_window_complete_days` | the fence: `window_to = LEAST(watermark − 1, the Los Angeles date of built_at − 2)` and `window_days` long (the Task 5 draft's `watermark − 1` fails after 22:00 Los Angeles — §2 "why it is fenced"; v27.152–v27.159 read `as_of − 2`, which is a day past the fence on a partition keyed on the New York date by the ~22:35 Los Angeles pass, P-24, v27.160) | red > 0 |
| `plan_pot_reconciliation` | pot = every GOOD keyword's window spend, holdout included (P-15, v27.158), allowance = share × pot, to the cent (the acceptance's C03/C04 form; v27.152–v27.157 excluded the holdout under a "(P-2)" label, audit fix #24); the detail prints each family's not-good side, expected spend after the upload and share of the gap closed (P-22) | red > 0 |
| `plan_one_move_per_notgood` | one move per CANDIDATE, NONE on the good side and on rows with nothing to repair (§9 v27.135, the acceptance's C06 form; the draft read 152 violations on a healthy partition) | red > 0 |
| `plan_ownership_no_foreign_go` | foreign GO rows on money levers inside live-plan campaigns — **a REPORT until Task 3 ships**, because no engine `PLAN` writes proposals and the plan owns nothing at the gate yet | INFO, then red > 0 |
| `plan_both_plans_written` | exactly plans A and B in the latest partition | red otherwise |
| `plan_settle_guard_holds` | **P-14b is a clock and P-14c a last-day test, not a veto.** A live-plan row demoted under the guard's preconditions (not-good, was good, served, unsettled) is legitimate iff the judge published `guard_released_by` as `HOLD_EXPIRED` or `LAST_DAY_NOT_STRONG`; a `HELD_UNSETTLED` row must have earned the hold with a very good last day, or (P-18, v27.156) carry `hold_kept_by = STRONG_DAY_IN_WINDOW` with `window_from <= hold_strong_day`. The check READS `hold_kept_by` as well, and `guard_released_by` and never re-derives the guard — re-deriving it is what vetoed every partition for a month | red > 0 |
| `plan_settle_curve_coverage` | share of live-plan rows the curve could correct | INFO |
| `plan_proposal_lag_days` | the proposal snapshot's date against the live plan's | INFO, amber > 2 |
| `plan_partition_fresh` | **ALARM.** The latest plan is older than the later of yesterday and the Los Angeles day the plan step last ran, OK or FAIL. Not "older than today": the pass runs three times a day, so "today" alone would be red between midnight and the first pass every day. Since v27.160 the first pass of a New York night (01:35 New York) writes that night's partition (as_of is the New York date, never earlier than the Los Angeles day of the same build), so every pass that saved its partition meets the Los Angeles due date; the clock itself is unchanged. The detail says the last plan date and the nights missing | red > 0 |
| `pipeline_step_failing` | **ALARM, GENERIC.** Any procedure whose three most recent runs in the last 30 days all logged FAIL, with the first 120 characters of its latest error and the length of the streak. This is the check that would have named the builder on day 1 of the outage, and the next outage needs no new check | red > 0 |
| `plan_pass_failed` | **ALARM (v27.163, piece-1 Task 9).** The plan step's latest run (last 30 days) logged FAIL, or any of its runs in the last 24 hours did; RED as well when it logged no run in the last 24 hours. The detail leads with the failure's New York time and the first 160 characters of its error. 3 of 9 passes refused 09-29 → 10-01 with never more than two FAILs in a row and a partition saved every night, so the two alarms above could not name one | red > 0 |

**The surface.** `V_DAILY_BRIEF` carries one SYSTEM line (section_rank 7, appended) that reads
the board LIVE — never an image, which goes stale exactly when the pipeline that builds it stops —
and folds its RED rows into one sentence, the two alarms first and quoted with the board's own
detail. The action says A NIGHT WAS NOT SAVED when either alarm is RED. `DAILY_BRIEF.md` has the
row shape and the reasons.

**v27.163 (2026-10-03, piece-1 Task 9): the line tells a new RED from an old one.** The board now
has a memory, `FACT_ENGINE_HEALTH_HISTORY`, written once per pass by `SP_SNAPSHOT_ENGINE_HEALTH`
(Refresh Task 23, the pass's last step). The SYSTEM line lists the NEW REDs first
(`NEW since <time>: …`) and the standing ones after (`standing: contradiction_rate since <date>, …`),
quotes `plan_pass_failed`'s error beside the two alarms, and says A PLAN PASS FAILED when it is RED
and no night alarm is. Rules and reasons: `DAILY_BRIEF.md` SYSTEM, `ENGINE_HEALTH.md`.

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

**Deploy and verify v27.163 (2026-10-03, piece-1 Task 9)**, in this order: the table, the board (the
first snapshot must carry plan_pass_failed), the procedure, one hand CALL (the memory's first
snapshot), the orchestrator (after diffing its deployed body against the file: the only code
difference must be Refresh Task 23), the brief, then the acceptance. The acceptance reads the brief
in full (two `V_CHANGE_SCORECARD` arms beside the board's), so it runs longer than a bq call should
wait: submit it with `--nosync` and poll.

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/tables/FACT_ENGINE_HEALTH_HISTORY.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache 'CALL `onyga-482313.OI.SP_SNAPSHOT_ENGINE_HEALTH`()'
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/views/V_DAILY_BRIEF.sql)"
JOB=$(bq query --nosync --format=none --use_legacy_sql=false --project_id=onyga-482313 --nouse_cache "$(grep -v '^[[:space:]]*--' scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql)" 2>&1 | grep -o 'bqjob_[A-Za-z0-9_]*')
bq wait "$JOB" 60   # repeat until DONE; then read the last child job: bq ls -j --parent_job_id="$JOB"
```

**Deployed 2026-10-03 (06:29–06:48 UTC)** in that order, with a second hand CALL after the board's
last deploy. The orchestrator's deployed body differed from the file only by Refresh Task 23
(comment lines removed on both sides), and equals the stripped file after the deploy. Board: 34
checks, plan_pass_failed GREEN 0, the same 3 RED. PLAN_HEALTH_acceptance: 42 of 42 PASS (job
`bqjob_r43c4576878d111d2_000001a1008dc061_1`, 29,439.4 slot-s, 26,479.0 of them the brief read);
the controls' readings are in the file's header. Each snapshot reads the board once
(4,535.4 and 3,197.7 slot-s for the two hand CALLs; the board's scorecard arm scans
`FACT_AMAZON_ADS`).

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
| `FN_PLAN_SCORECARD(grade_date DATE, ads_date DATE)` | `scripts/bigquery/functions/FN_PLAN_SCORECARD.sql` | the grade, as a table function so the acceptance can run the SAME arithmetic with the clock moved forward (the guard has nothing old enough to grade until 2026-10-03). Two clocks since follow-up F4 (2026-10-03): `grade_date` is the New York date nights are dated on, `ads_date` the Los Angeles date settle dates and ads days are read on |
| `V_PLAN_SCORECARD` | `scripts/bigquery/views/V_PLAN_SCORECARD.sql` | the function at today's New York date and today's Los Angeles date (the judge's two clocks; until F4 it passed the Los Angeles date as both) — the one to read |
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
judge's published decision; it never re-derives the guard. **Open since v27.156 (P-18):** a hold
kept by `STRONG_DAY_IN_WINDOW` is graded as a HELD decision like any other, though its own last day
was not very good — so the hint's held group, which argues about `strong_day_mult`, can carry holds
that multiplier did not decide. `hold_kept_by` is on the row, so `FN_PLAN_SCORECARD` can separate
them; it does not yet (no such hold had been written as of 2026-10-02). Each night's decision is graded on its own
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

**Each group needs at least 16 graded decisions** (`min_group_rows`, declared in the function's
`k` CTE; **Ori ruled 16 on 2026-10-02**, the second option below; it was 10 from 2026-10-01) before the hint says anything but `WAIT`. 20 in total is not
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
C08's own control (C08a) runs on the function at the day before the first guard decision settles
(read from the plan history), not on today's scorecard: on 2026-10-03, 20 of 136 decisions had become
gradable, so a control built on today's youth sentence could no longer fire (follow-up F1).

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
