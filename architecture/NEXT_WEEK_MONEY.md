# Next Week's Money — SOP

**Spec:** `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` (rulings P-1..P-14)
**Plan:** `docs/superpowers/plans/2026-08-23-next-week-money.md` (Tasks 0..8)
**Status:** Task 0 shipped (v27.130), repaired (v27.131). This SOP grows one section per task; Task 8 completes it.

> One engine plans next week's not-good money for the working families (HARVEST book: Bottle,
> Lollibox, LolliME, Fresh). Good keywords are never cut and never re-priced (P-4). The not-good
> ones compete for numbered, dollar-sized seats inside an allowance that is a declared share of
> what the good side actually spent in the window; the rest queue at zero.

---

## 1. The config layer (Task 0, v27.130 · repaired v27.131)

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
selects are read on **Los Angeles**, and the window is complete days only — `window_days` days
ending at the ads watermark minus one, where the watermark is
`LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` (P-10). The filling day never
enters a window.

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

Never edit the DDL file to change a live setting. The DDL defers to you: it seeds **only a state
that has no row at all**, deletes only its own row for a state nobody has ruled on, and stamps
its rows with a declared sentinel `updated_at` so a re-deploy can never out-rank your row by
recency. `C06` and `C07` are the alarms. (v27.130 got this wrong in a way that reverted money
silently: it deleted and re-inserted the seed rows **active, with a fresh `CURRENT_TIMESTAMP()`**,
so a hand-set share survived the delete but stopped being the row anyone read.)

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

## 2. The judgement layer (Task 1) — to be written

## 3. The nightly builder (Task 2) — to be written

## 4. Ownership and the preflight (Task 3) — to be written

## 5. The plan book (Task 4) — to be written

## 6. Grading, health and the surfaces (Tasks 5–7) — to be written
