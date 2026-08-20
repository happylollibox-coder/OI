# Two-Book P&L Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Judge advertising on net profit including the organic halo, split into a Harvest book (established families, judged on money) and an Invest book (declared launches, judged on improvement inside a bounded budget).

**Architecture:** Six new BigQuery objects plus two modifications, layered so nothing hot ever inlines a planner-ceiling view. `V_FAMILY_PNL` is the measurement spine (family × period: net profit, total net ROAS, ads net ROAS, measured halo factor). `V_FAMILY_BAR` turns the measured halo into a per-family keyword bar that the bid engines read from a materialized table. `DE_LAUNCH_INVESTMENT` + `V_BOOK_ASSIGNMENT` + `V_INVEST_STATUS` bound the launch investment and judge it on trajectory. Everything is family-grain because organic sales are not attributable to a keyword.

**Tech Stack:** BigQuery Standard SQL (project `onyga-482313`, dataset `OI`), stored procedures for materialization, `config.yaml` as the object registry, `architecture/` for SOPs.

**Spec:** `docs/superpowers/specs/2026-08-19-two-book-pnl-design.md`

---

## STANDING RULE 0 — describe the MECHANISM, publish the QUERY, never pin a MEASUREMENT

*Ori's ruling, 2026-08-20, fourth repair round. It REPLACES the round-3 version of this rule, which
allowed a measured number to stay if it was stamped with an as-of date. Stamping was tried for a
whole round and it failed: round 3 itself shipped `config.yaml`'s `V_BOOK_ASSIGNMENT` entry saying
"As of 2026-08-20 that read 1.61x and 1.94x over rate" while the live view that same day read
otherwise.* **A wrong number under today's date is worse than an undated one: it looks verified.**

**There are two kinds of number, and only one of them is banned.**

**A DECLARED CONSTANT is true because a person decided it.** A sanctioned $30/day, a $913 monthly
backstop, a stop date of 2026-10-31, a `credit = 0.5`, a `bar_floor = 0.60`, a 28-day rate window, a
183-day age boundary, a 3-day staleness threshold, a 5e-5 tolerance, a 5% breakeven band, a
structural invariant such as "exactly two total rows". It does not go stale when data moves; it
changes only when someone changes it. **Declared constants MAY be written down, and they MAY gate an
assertion.** Task 8b Step 4's post-restore check — `daily_investment = 30.0 AND monthly_loss_ceiling
= 913.0 AND stop_date = DATE '2026-10-31'` — is exactly what a declared constant is for: it is the
only thing standing between a test that inflates Bunny's sanction and a permanently overwritten
number Ori signed. It stays. Always say WHERE the constant is declared (`DE_LAUNCH_INVESTMENT`, the
`k` CTE) so a reader checks the source rather than the sentence, and never RESTORE a sanctioned value
from a number typed into a document — read the live row and write back what you read.

**A MEASUREMENT is true only because something was computed from data on some day.** A spend rate, a
ratio, a ROAS, a halo, a net profit, a row count, a column count, a percentage of a ceiling, a
dry-run byte count, an assertion result, and every "today there are N of these" clause.
**A measurement does not go in prose.** A view header, a `config.yaml` entry, a step in this plan and
a paragraph of the spec state **what is computed, from what, and why** — the mechanism. If a number
is needed, **publish the QUERY that produces it** and let the reader run it.

**Run the query before you publish it, and read its output against the sentence beside it.** A
published query whose result contradicts its own sentence is worse than no query at all — that
defect shipped twice, in `V_FAMILY_BAR.sql`'s floor re-check and in Task 9's SOP heredoc. **Check the
COLUMN NAMES too:** several queries published in this design named columns that had been renamed
away, and they did not fail quietly, they failed to compile.

**A MEASUREMENT may never gate anything** — not an acceptance item, not a step's pass condition, not
a monitor. Gate the PROPERTY, not the population; see Task 8 Step 6, where a pinned count was refuted
by re-running the same query the same day with no code change in between. **A DECLARED CONSTANT may.**

**One more case, named so it is not argued again: a GOLDEN EXPECTATION inside a regression test.**
Task 1's assertion compares `V_FAMILY_PNL` against four frozen May–Jul rows under stated tolerances.
Those values are measurements, and they stay — because inside a test the number IS the subject and
its whole purpose is to detect drift, whereas the same number in a sentence is a claim about today.
The two rules that keep it honest: the frozen set must be labelled as frozen with its date and
tolerances, and **you never "refresh" it when it moves.** If it drifts past tolerance, that is the
test working; explain the drift, do not rewrite the expectation.

**When you find a pinned measurement, DELETE it.** Do not update it and do not stamp it.

---

## Non-negotiable house rules (read before Task 1)

These are not style preferences. Each one exists because breaking it broke production in the last week.

1. **Never inline a planner-ceiling view.** `V_LOW_STOCK_ADS`, `V_KEYWORD_LIFT`, `V_OOB_KEYWORD`, `V_CHANGE_SCORECARD` are individually at BigQuery's planning ceiling. On 2026-08-17 `V_PANEL_OWNERSHIP` stopped planning entirely because it inlined one of them. If a consumer needs ceiling-view data, materialize a slice into a `T_` table inside a procedure and join the TABLE.
2. **Complete-days windows.** `wm` = newest loaded day. The last day stands alone; every multi-day window ends at `wm − 1`. See `feedback_window_convention_complete_days`.
3. **THE BINDING CONSTRAINT IS THE SPEND RATE** (Ori 2026-08-19: *"spend rate binds"*).
   `DE_LAUNCH_INVESTMENT.daily_investment` is the number Ori actually sanctioned — Bunny $30/day,
   LolliBall $55/day, both DECLARED CONSTANTS on that table — and it is what the exemption must
   enforce. `monthly_loss_ceiling` is a CATASTROPHE BACKSTOP behind it, nothing more. WHY, as a
   property of how it was built rather than as a reading of a particular day: the ceiling was
   backfilled as the sanctioned SPEND rate monthised, and a launch family with real sales loses far
   less than it spends, so a ceiling denominated in net profit is a loose bound by construction and a
   family can sit deep inside it while running well over its rate. The loss ceiling was the wrong
   denominator; the spend rate is the decision. *(No rate, ratio or ceiling percentage is written on
   this line — Standing Rule 0. Read them:
   `SELECT family, daily_investment, spend_per_day, spend_rate_ratio, ceiling_used_pct,
   rate_window_basis, protection_qualified FROM onyga-482313.OI.V_INVEST_STATUS`.)*
4. **Blended (sales + ads) measures cut at the ORDERS watermark, never the ads watermark** — ads rows run ~1 day ahead of the business report. Copy the `wm` CTE from `V_FAMILY_NET_PROFIT_7D.sql` verbatim (shown in Task 1).
5. **Deploy battery, every object, every time:** back up → deploy → before/after flip report → pull-twice determinism.
6. **`config.yaml` parses today. NEVER append entries to the end of the file** — the tail is inside the `monitoring:` mapping and appending there broke the parse on 2026-08-17. Insert into the `views:` or `tables:` list, then verify with PyYAML.
7. **Deploy command:** `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"`. Header lines starting `--` at column 0 are stripped at deploy, so header comments are repo-only.
8. **Never pipe SQL through plain `cat`.** Any file beginning with `--` makes bq abort with
   *"FATAL Flags parsing error: Unknown command line flag"* — it reads the comment as a flag. Every
   assertion file in this plan starts with a `--` comment, so **always** use `grep -v '^--' FILE`,
   exactly as the deploy command does. (Found the hard way in Task 1.)

---

## STATUS — read this before you execute a single step

**Standing rule: the code block inside a shipped task is a RECORD of what was written that day, not
something to re-execute.** *(One exception, applied 2026-08-20 under Standing Rule 0: MEASURED
NUMBERS have been stripped out of those blocks and replaced with the mechanism or a query. A block
that ships its comments into a live view carries any stale figure in it into production, and a reader
who copies a figure out of a "record" is quoting last week either way. The code is otherwise as
written.)* Every object below was changed after its task was written — by review, by
the orders-watermark ruling, or by a later fix. The authority for what an object contains is the file
in `scripts/bigquery/`, never this document. If a task is marked SHIPPED, read the file; do not
re-deploy the block. Re-running a shipped block silently reverts production, **and the task's own
acceptance assertion will usually still pass**, because those assertions test the shape of the answer
rather than which version produced it. Task 7's assertion is the clearest example: while every
family happens to appear on both sides of its spine, the ORIGINAL narrower spine reconciles
perfectly too, so it would report success while having thrown away several commits of fixes.

| task | object | status | shipped in | the block below is |
|---|---|---|---|---|
| 1 | `V_FAMILY_PNL` | SHIPPED | `92bf0a2`, refined in `a8cb5aa` | **SUPERSEDED** — written before the complete-days ruling |
| 2 | `DE_LAUNCH_INVESTMENT` | SHIPPED | `a8cb5aa` | carries its own correction banner; still accurate |
| 3 | `V_BOOK_ASSIGNMENT` | SHIPPED | `2d54ebb`, refined in `a8cb5aa` | **SUPERSEDED** — read the file |
| 4 | `V_FAMILY_BAR` | SHIPPED | `95265bd`, `097d8d7`, `72acbdf` | **SUPERSEDED** — read the file |
| 5 | `SP_SNAPSHOT_FAMILY_BAR` | SHIPPED | `35b9fa6`, `d0377be` | **SUPERSEDED** — read the file (corrected 2026-08-20: this row said "current") |
| 6 | `V_INVEST_STATUS` | SHIPPED | `7e32ee2`, `72acbdf`, `0e4e568`, `acbf7be`, `ee193ca` | **SUPERSEDED** — read the file |
| 7 | `V_TWO_BOOK_BRIEF` | SHIPPED | `fa840df`, `9fd1318`, `971751f`, `0a65589`, `a1d27aa`, `acbf7be`, `ee193ca`, `cc9425d` | **SUPERSEDED** — read the file |
| 8 | bid engines read the family bar | **ON HOLD** | — | repaired below, deliberately not released |
| 8b | `V_LAUNCH_EXEMPTION` | **ON HOLD** | — | repaired below, deliberately not released |
| 9 | `architecture/TWO_BOOK_PNL.md` | **BLOCKED** | — | one standing rule needs Ori's decision first |

**COLUMNS WERE RENAMED ACROSS 2026-08-20 AND THE SUPERSEDED BLOCKS BELOW STILL SHOW THE OLD NAMES.**
Two matter to the tasks that are meant to be RUN, so they are named here and nowhere else:
`V_INVEST_STATUS.exemption_live` is now **`protection_qualified`** (one word could not carry both
"what the sanction rules say" and "what the machine is doing"), and `mtd_spend_per_day` is now
**`spend_per_day`** — the rate window stopped being month-to-date and became a trailing span of
complete days, so "mtd" named a window that no longer exists. Tasks 8 and 8b carry the new names.

**Everything else that was renamed is deliberately NOT listed** (Standing Rule 0). `V_TWO_BOOK_BRIEF`
in particular has been recolumned twice more since, and any list written here would be a fourth
generation of stale prose. Tasks 6 and 7's code blocks are records of what was written on 2026-08-19
and are not updated. **Before you write ANY column name of `V_INVEST_STATUS` or `V_TWO_BOOK_BRIEF`,
read it off the live object:**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT table_name, ordinal_position, column_name
 FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
 WHERE table_name IN ('V_INVEST_STATUS','V_TWO_BOOK_BRIEF')
 ORDER BY table_name, ordinal_position"
```

### Tasks 8, 8b and 9 are on hold

Ori's ruling, 2026-08-20: *"Tell the truth now, release nothing."* The brief stops claiming an
enforcement that is not happening and shows the gap between sanctioned and actual spend as a number.
**Nothing in the engine changes.** `V_LAUNCH_EXEMPTION`, `V_ADS_COACH` and
`V_COACH_CAMPAIGN_BUDGET` are not to be edited, and no held decision may be released.

The repairs in Tasks 8 and 8b below exist so that **if** the hold is ever lifted the steps can be run
without destroying something. They are a repair, not a permission. Task 9 must not run at all until
Ori answers the open question recorded inside it.

---

## File structure

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_FAMILY_PNL.sql` | the measurement spine — family × period economics including organic |
| `scripts/bigquery/tables/DE_LAUNCH_INVESTMENT.sql` | the launch declaration (ceiling, dates, target) |
| `scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql` | family → HARVEST/INVEST, default HARVEST |
| `scripts/bigquery/views/V_FAMILY_BAR.sql` | measured halo factor → keyword bar |
| `scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql` | materializes the bar into `T_FAMILY_BAR` for the engines |
| `scripts/bigquery/views/V_INVEST_STATUS.sql` | budget consumed, ramp trajectory, exemption live/lifted |
| `scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql` | the morning brief, two books, never blended |
| `architecture/TWO_BOOK_PNL.md` | the SOP |

**One deliberate deviation from spec §7:** the spec lists "`V_DAILY_BRIEF` (extend)". This plan
creates a separate `V_TWO_BOOK_BRIEF` instead. `V_DAILY_BRIEF` answers a different question
(PLANNED / HAPPENED / VERDICT_NEW / ACTION_ITEM for the engine's daily instructions) and folding a
family-grain P&L into it would give one view two responsibilities. The two-book brief is its own
object and `V_DAILY_BRIEF` is left alone.

**Deliberately NOT in this plan** (spec §8): no automatic cutting of Harvest families, no per-keyword organic attribution, no change to settle discipline / ownership ladder / preflight gates.

---

## Task 1: `V_FAMILY_PNL` — the measurement spine

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. DO NOT RE-DEPLOY IT.**
> Live in `92bf0a2`, then rewritten in `a8cb5aa`. The block below was written before the
> complete-days ruling and would undo it: it publishes the running month as an ordinary `%Y-%m` row
> whose `period_end` is `LAST_DAY(month)`, so August would claim to end 2026-08-31 while holding
> twenty days of data — and every month-over-month trend built on it would read the current month as
> a collapse. The deployed file emits a `%Y-%m` row only when that month has fully closed, publishes
> the running month as a single row labelled `MTD`, and carries `is_complete_period` on every row so
> a consumer cannot get it wrong by accident. Read
> `scripts/bigquery/views/V_FAMILY_PNL.sql`; treat the block below as history.

Everything else reads this. It must be right before anything is built on it.

**Files:**
- Create: `scripts/bigquery/views/V_FAMILY_PNL.sql`
- Modify: `config.yaml` (insert into the `views:` list)

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t1_assert.sql`. It must FAIL now (view does not exist) and PASS after Step 3.

**A note on the four rows of `want` below, because Standing Rule 0 forbids a measured number in
prose and this is not prose.** They are a **GOLDEN EXPECTATION inside a regression test**: a
measurement deliberately frozen on 2026-08-19, whose entire purpose is to detect drift, compared
under stated tolerances (`np` ±25, `tnr`/`halo` ±0.02). Inside a test the number IS the subject; in
prose it is a claim about today, which is what the rule bans. Do not copy these values into a
sentence anywhere, and do not "refresh" them when they move — if they move past tolerance, that is
the test doing its job and the reason must be explained, not the expectation rewritten. *(They have
already drifted inside tolerance: ads money restates, so even a closed May–Jul window does not hold
still.)*

```sql
-- ASSERT: V_FAMILY_PNL reproduces the hand-verified May-Jul 2026 baseline from the spec.
-- The `want` rows are a FROZEN GOLDEN SET (2026-08-19) with tolerances, not a description of today.
WITH got AS (
  SELECT family,
         ROUND(net_profit, 0)     AS np,
         ROUND(total_net_roas, 2) AS tnr,
         ROUND(halo_factor, 2)    AS halo
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_start = DATE '2026-05-01' AND period_end = DATE '2026-07-31'
),
want AS (
  SELECT 'LolliME'  AS family,  15406 AS np, 1.49 AS tnr, 1.26 AS halo UNION ALL
  SELECT 'Lollibox',            13537,       1.59,        1.37        UNION ALL
  SELECT 'Bottle',               -203,       0.95,        1.59        UNION ALL
  SELECT 'Fresh',               -1497,       0.88,        1.07
)
SELECT
  COUNTIF(g.family IS NULL)                          AS missing_families,
  COUNTIF(ABS(g.np  - w.np)  > 25)                   AS np_mismatches,
  COUNTIF(ABS(g.tnr - w.tnr) > 0.02)                 AS roas_mismatches,
  COUNTIF(ABS(g.halo - w.halo) > 0.02)               AS halo_mismatches
FROM want w LEFT JOIN got g USING (family);
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t1_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.V_FAMILY_PNL`

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_FAMILY_PNL.sql`:

```sql
-- =============================================
-- V_FAMILY_PNL — family economics INCLUDING THE ORGANIC HALO (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md. SOP: architecture/TWO_BOOK_PNL.md.
--
-- WHY THIS EXISTS: every bid decision was judged on ads-ATTRIBUTED profit, which cannot see the
-- organic units a keyword builds. A family can read as a disaster on ads net ROAS and be fine on
-- TOTAL net ROAS; the gap between them IS its halo, and cutting such a family's keywords on the ads
-- number destroys the organic demand carrying it. No family or ratio is named here (Standing Rule
-- 0); read them off the view.
--
-- NET PROFIT IS A TRUE NET, NOT A GROSS MARGIN. V_UNIFIED_DAILY.cogs is all-in — landed product
-- cost, inbound shipping, FBA pick/pack AND the Amazon referral fee — so sales - cogs - ad_cost is
-- after Amazon's fees.
--
-- HALO FACTOR IS MEASURED, NEVER ASSUMED: total_net_roas / ads_net_roas, read straight from dollars.
-- An earlier draft inferred it from unit ratios plus an equal-margin assumption, which flattens the
-- spread BETWEEN families — and that spread is the only thing the bar reads.
--
-- WATERMARK: blended sales+ads measures cut at the ORDERS watermark, never the ads watermark (ads
-- rows run ~1 day ahead of the business report). The wm CTE is copied verbatim from
-- V_FAMILY_NET_PROFIT_7D / V_SUMMARY_7D — see architecture/ORDERS_WATERMARK.md. Do not "simplify" it:
-- the sessions gate is what skips mid-sync partial days, where orders land before sessions.
--
-- GRAIN: one row per (family, period). Organic sales are measurable at family grain and NOT
-- attributable to a keyword — that limit is the whole reason the engine bridge (V_FAMILY_BAR) exists
-- instead of a per-keyword organic number.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_PNL` AS
WITH wm AS (
  -- Sessions gate skips mid-sync partial days (orders land before sessions).
  -- Same rule as V_SUMMARY_7D / V_DATA_FRESHNESS / V_PLAN_FORECAST — architecture/ORDERS_WATERMARK.md.
  SELECT MAX(date) AS d
  FROM (
    SELECT date
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Organic'
    GROUP BY date
    HAVING SUM(ASIN_SESSIONS) > 0
  )
),
-- The reporting periods this view publishes. Every window ENDS AT THE WATERMARK (a complete day by
-- construction of wm), so no partial day enters a blended number.
periods AS (
  SELECT 'M3'  AS period_label, DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AS period_start, (SELECT d FROM wm) AS period_end UNION ALL
  SELECT 'M1',                  DATE_SUB((SELECT d FROM wm), INTERVAL 29 DAY),                 (SELECT d FROM wm)              UNION ALL
  SELECT 'W2',                  DATE_SUB((SELECT d FROM wm), INTERVAL 13 DAY),                 (SELECT d FROM wm)
),
-- Fixed calendar periods for month-over-month trajectory (the Invest ramp test) and for the
-- reproducible baseline the acceptance assertion checks.
cal AS (
  SELECT FORMAT_DATE('%Y-%m', m) AS period_label, m AS period_start, LAST_DAY(m) AS period_end
  FROM UNNEST(GENERATE_DATE_ARRAY(
         DATE_TRUNC(DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY), MONTH),
         DATE_TRUNC((SELECT d FROM wm), MONTH), INTERVAL 1 MONTH)) m
  UNION ALL
  SELECT 'BASELINE_MAY_JUL', DATE '2026-05-01', DATE '2026-07-31'
),
all_periods AS (SELECT * FROM periods UNION ALL SELECT * FROM cal),
u AS (
  SELECT family, date, sales, cogs, ad_cost, ads_gross_profit, units, organic_units, ads_units
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE family IS NOT NULL
)
SELECT
  p.period_label, p.period_start, p.period_end,
  u.family,
  -- THE GOAL: dollars. Net of COGS (all-in, incl. Amazon fees) and of ad spend.
  ROUND(SUM(u.sales - u.cogs) - SUM(u.ad_cost), 2)                                        AS net_profit,
  -- THE EFFICIENCY READ: breakeven is exactly 1.0, no parameters.
  ROUND(SAFE_DIVIDE(SUM(u.sales - u.cogs), NULLIF(SUM(u.ad_cost), 0)), 4)                 AS total_net_roas,
  -- WHAT THE ENGINE CURRENTLY SEES — published so the GAP is visible, not as a verdict.
  ROUND(SAFE_DIVIDE(SUM(u.ads_gross_profit), NULLIF(SUM(u.ad_cost), 0)), 4)               AS ads_net_roas,
  -- THE BRIDGE INPUT: measured, not assumed. NULL when there is no ads profit to divide by.
  ROUND(SAFE_DIVIDE(SUM(u.sales - u.cogs), NULLIF(SUM(u.ads_gross_profit), 0)), 4)        AS halo_factor,
  CAST(SUM(u.units) AS INT64)                                                             AS units,
  CAST(SUM(u.organic_units) AS INT64)                                                     AS organic_units,
  ROUND(100 * SAFE_DIVIDE(SUM(u.organic_units), NULLIF(SUM(u.units), 0)), 2)              AS organic_pct,
  ROUND(SUM(u.sales), 2)                                                                  AS total_sales,
  ROUND(SUM(u.ad_cost), 2)                                                                AS ad_spend,
  (SELECT d FROM wm)                                                                      AS orders_watermark
FROM all_periods p
JOIN u ON u.date BETWEEN p.period_start AND p.period_end
GROUP BY p.period_label, p.period_start, p.period_end, u.family;
```

- [ ] **Step 4: Deploy**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_FAMILY_PNL.sql)"
```
Expected: `Created onyga-482313.OI.V_FAMILY_PNL`

- [ ] **Step 5: Run the assertion — it must now pass**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t1_assert.sql)"
```
Expected: `missing_families 0, np_mismatches 0, roas_mismatches 0, halo_mismatches 0`

If any mismatch is non-zero, STOP and diff against the spec §3 baseline table before continuing — every later task trusts these numbers.

- [ ] **Step 6: Pull-twice determinism**

```bash
Q="SELECT TO_HEX(MD5(STRING_AGG(TO_JSON_STRING(t), '' ORDER BY TO_JSON_STRING(t)))) h, COUNT(*) n
   FROM \`onyga-482313.OI.V_FAMILY_PNL\` t WHERE period_label = 'BASELINE_MAY_JUL'"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv "$Q" | tail -2
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv "$Q" | tail -2
```
Expected: identical hash both times.

- [ ] **Step 7: Register in config.yaml**

Insert into the `views:` list (NOT at the end of the file). Verify the anchor first:

```bash
python3 - << 'PY'
import re
p='config.yaml'; lines=open(p).read().split('\n')
t=next(i for i,l in enumerate(lines) if l.strip()=='tables:')
end=next(i for i in range(t-1,0,-1) if lines[i].strip() and not lines[i].startswith('#'))+1
entry = '''  - name: "V_FAMILY_PNL"
    type: "view"
    source_files: ["scripts/bigquery/views/V_FAMILY_PNL.sql"]
    description: "Family economics INCLUDING the organic halo (2026-08-19). One row per (family, period): net_profit (total sales - all-in COGS - ad spend, a true net after Amazon fees), total_net_roas (breakeven exactly 1.0), ads_net_roas (what the engine currently sees), and halo_factor = total/ads MEASURED not assumed. NO HALO OR BASELINE FIGURE IS WRITTEN HERE - publish the query (Standing Rule 0). Cuts at the ORDERS watermark with the sessions gate, never the ads watermark. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md."
    dependencies:
      - V_UNIFIED_DAILY
      - FACT_AMAZON_PERFORMANCE_DAILY'''.split('\n')
lines[end:end] = ['']+entry
open(p,'w').write('\n'.join(lines))
PY
python3 -c "import yaml;d=yaml.safe_load(open('config.yaml'));print('PARSES OK, views:',len(d['views']))"
```
Expected: `PARSES OK` and the view count **one higher than before your edit**. Do not match an absolute number — the working tree carries other uncommitted registrations, so the total drifts.

- [ ] **Step 8: Commit**

```bash
git add scripts/bigquery/views/V_FAMILY_PNL.sql config.yaml
git commit -m "feat: V_FAMILY_PNL — family economics including the organic halo"
```

---

## Task 2: `DE_LAUNCH_INVESTMENT` — EXTEND the existing declaration

> **⚠ THIS TASK WAS REWRITTEN AFTER TASK 1's REVIEW.** The original version created this table.
> **It already exists, holds real sanctioned data, and `V_LAUNCH_EXEMPTION` reads it today.**
> `CREATE TABLE IF NOT EXISTS` against it is a **silent no-op**, after which Tasks 3, 6 and 8b would
> query columns that do not exist and fail only once three more objects had been built on top.

**What is already there** (Ori sanctioned these on 2026-08-13):

| parent_name | daily_investment | stop_date |
|---|---|---|
| Bunny | $30.00/day | 2026-10-31 |
| LolliBall | $55.00/day | 2026-11-30 |

Schema: `parent_name, daily_investment, stop_date, sanctioned_on, note, updated_at, updated_by`.
`V_LAUNCH_EXEMPTION` computes `exempt_until = LEAST(first sale + 183d, stop_date)` from it.

**The decision: EXTEND, never duplicate.** One declaration, one place. A second declaration table
would be two sources of truth about the same thing — precisely the defect class this design exists
to fix. The existing `stop_date` IS the design's end date and `parent_name` IS its family; only two
fields are genuinely missing.

**Files:**
- Modify: `scripts/bigquery/tables/DE_LAUNCH_INVESTMENT.sql` (record the ALTER; do not rewrite the CREATE)
- Modify: `config.yaml` (update the existing entry's description — do NOT add a second entry)

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t2_assert.sql`:

```sql
-- ASSERT: the two new fields exist, and every pre-existing column and value is untouched.
SELECT
  (SELECT COUNTIF(column_name = 'monthly_loss_ceiling')
     FROM `onyga-482313.OI`.INFORMATION_SCHEMA.COLUMNS
    WHERE table_name = 'DE_LAUNCH_INVESTMENT')                              AS has_ceiling,
  (SELECT COUNTIF(column_name = 'takeover_target_organic_units')
     FROM `onyga-482313.OI`.INFORMATION_SCHEMA.COLUMNS
    WHERE table_name = 'DE_LAUNCH_INVESTMENT')                              AS has_target,
  (SELECT COUNT(*) FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`)             AS rows_kept,
  (SELECT COUNTIF(parent_name = 'Bunny'     AND daily_investment = 30.0
                  AND stop_date = DATE '2026-10-31')
     FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`)                           AS bunny_intact,
  (SELECT COUNTIF(parent_name = 'LolliBall' AND daily_investment = 55.0
                  AND stop_date = DATE '2026-11-30')
     FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`)                           AS lolliball_intact;
```

- [ ] **Step 2: Run it and confirm the new fields are missing**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t2_assert.sql)"
```
Expected: `has_ceiling 0, has_target 0, rows_kept 2, bunny_intact 1, lolliball_intact 1`

- [ ] **Step 3: Extend the table, additively**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\`
  ADD COLUMN IF NOT EXISTS monthly_loss_ceiling FLOAT64,
  ADD COLUMN IF NOT EXISTS takeover_target_organic_units INT64"
```

**ADDITIVE ONLY. Never rename, drop or retype an existing column** — `V_LAUNCH_EXEMPTION` reads this
table live and a rename breaks the launch exemption for both families.

- [ ] **Step 4: Backfill the ceiling from what Ori already sanctioned**

Do not invent a ceiling. The sanctioned daily spend IS the natural loss bound — you cannot lose
materially more than you spend:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
UPDATE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\`
SET monthly_loss_ceiling = ROUND(daily_investment * 30.44, 0)
WHERE monthly_loss_ceiling IS NULL"
```
Expected: Bunny → ~913, LolliBall → ~1674.

**Leave `takeover_target_organic_units` NULL.** A take-over target is a business judgement, not
arithmetic, and it is the one field Ori must still supply. Task 6 must therefore treat a NULL target
as "PROOF phase cannot be judged yet" rather than as zero.

- [ ] **Step 5: Run the assertion — must pass**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t2_assert.sql)"
```
Expected: `has_ceiling 1, has_target 1, rows_kept 2, bunny_intact 1, lolliball_intact 1`

- [ ] **Step 6: Prove nothing downstream broke**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --dry_run \
  "SELECT COUNT(*) FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
  "SELECT COUNT(*) AS exemption_rows FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\`"
```
Expected: dry-run validates and the row count is unchanged from before the ALTER. If the exemption
view breaks, the ALTER was not additive — investigate before going further.

- [ ] **Step 7: Record the ALTER in the repo file and update config.yaml**

Append the ALTER to `scripts/bigquery/tables/DE_LAUNCH_INVESTMENT.sql` under a dated comment
explaining that the two-book design extended it and why the fields mean what they mean. Update the
EXISTING `config.yaml` entry's description to name both new columns. **Do not add a second entry** —
verify with `grep -c 'DE_LAUNCH_INVESTMENT"' config.yaml`, which must return 1.

- [ ] **Step 8: Commit**

```bash
git add scripts/bigquery/tables/DE_LAUNCH_INVESTMENT.sql config.yaml
git commit -m "feat: extend DE_LAUNCH_INVESTMENT with a net-profit ceiling and take-over target"
```

---

## Task 3: `V_BOOK_ASSIGNMENT` — which book each family is in

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. DO NOT RE-DEPLOY IT.**
> Live in `2d54ebb`, then corrected in `a8cb5aa` on two points the block below still gets wrong.
> First, it admits the literal string `Unknown` as a family — that is the fallback
> `V_CAMPAIGN_FAMILY_MAP` emits for a campaign whose family it cannot resolve, and it has no row in
> the measurement spine, so it would arrive as a seventh "family" with a book and no P&L. Second, its
> tie-break for "which declaration is live" orders by `sanctioned_on`, while `V_LAUNCH_EXEMPTION`
> orders by `updated_at`; the two would name different declarations live the moment Ori inserts a
> correction. Read `scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql`.

**Files:**
- Create: `scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t3_assert.sql`:

```sql
-- ASSERT: default is HARVEST; only a live declaration produces INVEST.
SELECT
  COUNTIF(book NOT IN ('HARVEST','INVEST'))                       AS bad_book_values,
  COUNTIF(book = 'INVEST' AND declaration_valid IS NOT TRUE)      AS invest_without_declaration,
  COUNTIF(family IS NULL)                                         AS null_families,
  COUNTIF(book = 'INVEST' AND daily_investment IS NULL)            AS invest_without_spend_sanction,
  COUNTIF(book = 'INVEST' AND launch_age_months IS NULL)           AS invest_without_age,
  COUNT(*)                                                        AS families
FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t3_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.V_BOOK_ASSIGNMENT`

- [ ] **Step 3: Write the view**

> **⚠ COLUMN NAMES CORRECTED 2026-08-19.** `DE_LAUNCH_INVESTMENT` is a pre-existing table, not one
> this plan created. Its real schema is `parent_name` / `daily_investment` / `stop_date` /
> `sanctioned_on` / `note` / `updated_at` / `updated_by`, plus the two columns Task 2 added
> (`monthly_loss_ceiling`, `takeover_target_organic_units`). There is **no** `family`, `start_date`
> or `end_date` column — an earlier draft of this task invented all three.
> Launch AGE comes from the family's first sale, not from the declaration: `sanctioned_on` records
> when Ori signed it off (2026-08-13 for both — a declared date on `DE_LAUNCH_INVESTMENT`), which is
> months after either launch began. Use the same first-sale ANCHOR `V_LAUNCH_EXEMPTION` uses, so
> neither object can invent a different launch date. **They will still disagree about the AGE and
> that is not a defect** — this view counts calendar-month boundaries crossed, `V_LAUNCH_EXEMPTION`
> divides elapsed days by 30.44. Expect a gap of up to about a month, either way. (Corrected
> 2026-08-20; this line used to say the two "can never disagree", which is false.)

Create `scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql`:

```sql
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
-- because monthly_loss_ceiling was backfilled as the sanctioned SPEND rate monthised, and a launch
-- family with real sales loses far less than it spends — so it is a loose bound BY CONSTRUCTION and
-- a family can sit deep inside it while running well over its rate. No rate, ratio or ceiling
-- percentage is written here (Standing Rule 0); read them off V_INVEST_STATUS.
--
-- AGE COMES FROM FIRST SALE, NOT FROM THE DECLARATION. sanctioned_on is when Ori signed the
-- investment off (2026-08-13 for both families), months after either launch actually began. Same
-- first-sale ANCHOR as V_LAUNCH_EXEMPTION / V_PRODUCT_LAUNCH_MODEL, so neither can invent a
-- different launch date — but the UNITS differ (calendar months crossed here, elapsed days / 30.44
-- there), so the two AGES will differ by up to about a month and that is not a defect.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BOOK_ASSIGNMENT` AS
WITH fam AS (
  SELECT DISTINCT parent_name AS family
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`
  WHERE parent_name IS NOT NULL
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
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY sanctioned_on DESC) = 1
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
```

- [ ] **Step 4: Deploy and assert**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t3_assert.sql)"
```
Expected deploy: `Created onyga-482313.OI.V_BOOK_ASSIGNMENT`
Expected assert: every counter `0`, `families 6`.

**Two families read INVEST, not zero** — Bunny and LolliBall were declared on 2026-08-13 and both
stop_dates are still in the future (2026-10-31, 2026-11-30). An earlier draft of this task expected
all six to read HARVEST because it assumed the declaration table was empty. Confirm the split:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, book, daily_investment, stop_date, launch_age_months
 FROM \`onyga-482313.OI.V_BOOK_ASSIGNMENT\` ORDER BY book, family"
```
Expected: Bunny and LolliBall INVEST with their sanctioned rates; the other four HARVEST with NULLs.

- [ ] **Step 5: Register in config.yaml (views: list, same insertion helper as Task 1 Step 7) and commit**

```bash
git add scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql config.yaml
git commit -m "feat: V_BOOK_ASSIGNMENT — Harvest by default, Invest only by live declaration"
```

---

## Task 4: `V_FAMILY_BAR` — the engine bridge

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. DO NOT RE-DEPLOY IT.**
> Live in `95265bd`, then corrected in `097d8d7` (the calibration test compares the MEAN of the two
> ROAS numbers, which the original wrote up wrongly) and `72acbdf` (the bars are rebuilt every day by
> the orchestrator, not monthly as the original comment claimed). Read
> `scripts/bigquery/views/V_FAMILY_BAR.sql`.

The one place the halo becomes a bid decision. Read spec §4 before writing this.

**Files:**
- Create: `scripts/bigquery/views/V_FAMILY_BAR.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t4_assert.sql`. These encode the spec's safety properties AND the validation property — that the bar reproduces the total-net-ROAS verdicts.

```sql
-- ASSERT: safety properties + the calibration property.
WITH b AS (SELECT * FROM `onyga-482313.OI.V_FAMILY_BAR`)
SELECT
  COUNTIF(keyword_bar > 1.0)                                        AS bars_above_one,      -- credit may only LOWER a bar
  COUNTIF(keyword_bar < 0.60)                                       AS bars_below_floor,    -- floor 0.60
  COUNTIF(halo_factor < 1.0 AND keyword_bar <> 1.0)                 AS credited_below_one,  -- no credit when halo < 1
  COUNTIF(keyword_bar IS NULL)                                      AS null_bars,
  -- CALIBRATION: a family clearing its bar must also clear total net ROAS 1.0, and vice versa.
  COUNTIF((ads_net_roas >= keyword_bar) <> (total_net_roas >= 1.0)) AS calibration_breaks
FROM b;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t4_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.V_FAMILY_BAR`

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_FAMILY_BAR.sql`:

```sql
-- =============================================
-- V_FAMILY_BAR — the engine bridge: measured halo -> per-family keyword bar (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
--
-- ADJUST THE BAR, NEVER THE MEASUREMENT. Organic sales are measurable at family grain and NOT
-- attributable to a keyword. So the engine keeps measuring ads-attributed GP-ROAS at keyword grain —
-- the only honest measure available there — and what changes is the BAR it is judged against, set
-- once per family from that family's MEASURED halo. Mathematically this is the same as inflating
-- every keyword's ROAS, but it keeps the measured number true, puts the adjustment in exactly one
-- auditable place per family, and never invents a per-keyword organic figure that does not exist.
--
--   keyword_bar = 1 / (1 + credit * (halo_factor - 1)),  credit = 0.5
--
-- WHY 0.5: crediting ALL organic to ads is wrong (brand search and repeat buyers would happen
-- anyway); crediting NONE is the pre-2026-08-19 behaviour and is why the engine undervalued
-- rank-building. Half is the conservative middle. It is a declared tunable in the k CTE, not a
-- buried constant.
--
-- SAFETY PROPERTIES, each asserted in the acceptance test:
--   · the credit can only LOWER a bar, never raise one above 1.0 — it can never justify a cut
--   · the bar is FLOORED at 0.60 — no halo excuses a catastrophic keyword. With credit 0.5 the
--     floor can only bite above halo 7/3; whether any row is near it is a measurement, not a
--     constant, so read it off the view rather than from a number written here.
--   · where halo_factor <= 1.0 NO credit is given and the bar stays 1.0. Sub-1.0 halos are a
--     COGS-imputation artifact, not a real negative halo (spec §9.1). WHICH families sit there
--     depends on the WINDOW and is deliberately not named here.
--   · INVEST families are exempt entirely; they are governed by budget + trajectory, not by a bar
--
-- WINDOW AND CADENCE: the halo is read from V_FAMILY_PNL's settled 90-day period (M3) and this view
-- is materialised DAILY by SP_SNAPSHOT_FAMILY_BAR (corrected 2026-08-19 — this line said MONTHLY and
-- the deployment has always been daily; the deployment is right). A settled 90-day window moves by
-- roughly one day in ninety per rebuild, so daily cannot make the bar chase noise.
--
-- CALIBRATION IS A STANDING TEST, NOT A ONE-OFF: a family passing its keyword bar must also clear
-- total net ROAS 1.0. If that ever breaks, the bridge is miscalibrated and the credit is wrong.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_BAR` AS
WITH k AS (
  SELECT
    0.5  AS halo_credit,   -- fraction of the measured halo we credit to ads (Ori tunable)
    0.60 AS bar_floor,     -- no halo excuses a keyword below this
    1.0  AS bar_ceiling    -- the credit may only ever lower a bar
),
p AS (
  SELECT family, total_net_roas, ads_net_roas, halo_factor, net_profit, organic_pct
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'          -- settled 90 complete days
)
SELECT
  p.family,
  b.book,
  p.halo_factor,
  p.total_net_roas,
  p.ads_net_roas,
  p.net_profit,
  p.organic_pct,
  -- the bar itself: no credit when the measured factor is <= 1.0, floored, never above 1.0
  ROUND(
    GREATEST(
      LEAST(
        IF(COALESCE(p.halo_factor, 0) > 1.0,
           SAFE_DIVIDE(1.0, 1.0 + k.halo_credit * (p.halo_factor - 1.0)),
           k.bar_ceiling),
        k.bar_ceiling),
      k.bar_floor)
  , 4)                                                                        AS keyword_bar,
  k.halo_credit,
  (b.book = 'INVEST')                                                         AS bar_exempt,
  CURRENT_DATE('America/Los_Angeles')                                         AS computed_on
FROM p
CROSS JOIN k
LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b ON b.family = p.family;
```

- [ ] **Step 4: Deploy and assert**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_FAMILY_BAR.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t4_assert.sql)"
```
Expected: all five counters `0`.

If `calibration_breaks > 0`, STOP. Print the offending rows and reconcile against spec §4 before continuing — a miscalibrated bridge silently changes every bid decision:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, halo_factor, keyword_bar, ads_net_roas, total_net_roas,
        (ads_net_roas >= keyword_bar) AS passes_bar, (total_net_roas >= 1.0) AS passes_truth
 FROM \`onyga-482313.OI.V_FAMILY_BAR\`
 WHERE (ads_net_roas >= keyword_bar) <> (total_net_roas >= 1.0)"
```

- [ ] **Step 5: Eyeball the bars against the spec table**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, ROUND(halo_factor,2) halo, ROUND(keyword_bar,2) bar, ROUND(ads_net_roas,2) running,
        ROUND(total_net_roas,2) truth, ROUND(net_profit,0) np
 FROM \`onyga-482313.OI.V_FAMILY_BAR\` ORDER BY np DESC"
```
**Expected SHAPE, not values** (Standing Rule 0 — this line used to name four bars, and bars move
with the halo on every rebuild): read the output ordered by `bar` and check three properties. (1)
**Monotone** — the higher a family's `halo`, the LOWER its `bar`; that is algebra
(`1/(1+0.5*(halo−1))`) and any exception is a defect. (2) **Bounded** — no bar above 1.00, none below
the declared 0.60 floor. (3) **The gap is the point** — `running` (ads-attributed) sits below `truth`
(total) wherever the halo exceeds 1.0, and it is that gap the bar exists to price. Whether a
particular family clears its bar today is a reading; do not write one down.

- [ ] **Step 6: Register in config.yaml and commit**

```bash
git add scripts/bigquery/views/V_FAMILY_BAR.sql config.yaml
git commit -m "feat: V_FAMILY_BAR — measured halo becomes a per-family keyword bar"
```

---

## Task 5: `SP_SNAPSHOT_FAMILY_BAR` — materialize for the engines

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. DO NOT RE-DEPLOY IT.**
> Live in `35b9fa6`, then corrected in `d0377be`. Banner added 2026-08-20: until then this was the
> only shipped task with no banner, and the STATUS table affirmatively called this block "current",
> which it is not. **The executable SQL is identical to the deployed procedure — it is the prose that
> differs, and the prose is the part that would revert.** Diffed against
> `INFORMATION_SCHEMA.ROUTINES` on 2026-08-20; three material differences, all in comments and in the
> `OPTIONS(description)`:
> 1. **The block below has no "not yet wired" clause.** Its description reads as though the engines
>    already join `T_FAMILY_BAR`. They do not — that is Task 8, Task 8 is unbuilt and on hold, and the
>    deployed description says so in three sentences. Re-deploying this block would put back the exact
>    claim `d0377be` was raised to remove: a reader would conclude the halo is already priced into
>    bids when no bid has moved.
> 2. **The block below has no `'Unknown'` paragraph.** The deployed version explains that campaigns in
>    `V_CAMPAIGN_FAMILY_MAP`'s literal `'Unknown'` bucket are deliberately ABSENT from the table, and
>    that the engines' `LEFT JOIN` + `COALESCE(keyword_bar, 1.0)` therefore leaves them at today's
>    behaviour. Without it, the missing rows read as a bug.
> 3. **The orchestrator task number below is wrong.** It says task `20.4`; the deployed description
>    says `20.5g-1, ahead of task 20.5g SP_SNAPSHOT_PANEL_OWNERSHIP`, which is where the call actually
>    sits (Step 7 verifies the ordering).
>
> Re-take the diff yourself rather than trusting this list:
> ```bash
> bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
>   "SELECT ddl FROM \`onyga-482313.OI\`.INFORMATION_SCHEMA.ROUTINES
>     WHERE routine_name='SP_SNAPSHOT_FAMILY_BAR'" | tail -n +2 \
>   > /tmp/sp_deployed.sql
> diff /tmp/sp_deployed.sql <(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql)
> ```
> Run 2026-08-20 that diff came back with **only** two cosmetic hunks — BigQuery echoes the DDL as
> `CREATE PROCEDURE` (never `CREATE OR REPLACE`) and `--format=csv` wraps the whole DDL in quotes and
> doubles the inner ones. Nothing substantive: **the repo file IS the deployment.** The three
> differences listed above are between the deployment and the CODE BLOCK BELOW, which is a record of
> what was written on 2026-08-19 and has not been maintained since. Read
> `scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql`. It is the authority.

The engines are at the planner ceiling. They must join a TABLE, never this view.

**Files:**
- Create: `scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql`
- Modify: `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t5_assert.sql`:

```sql
SELECT COUNT(*)                                  AS rows_in_table,
       COUNTIF(keyword_bar IS NULL)              AS null_bars,
       COUNTIF(campaign_id IS NULL)              AS null_campaign_ids,
       COUNT(DISTINCT family)                    AS families,
       COUNT(*) - COUNT(DISTINCT campaign_id)    AS duplicate_campaigns
FROM `onyga-482313.OI.T_FAMILY_BAR`;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t5_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.T_FAMILY_BAR`

- [ ] **Step 3: Write the procedure**

Create `scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql`:

```sql
-- =============================================
-- SP_SNAPSHOT_FAMILY_BAR — materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
--
-- WHY A SNAPSHOT AND NOT A VIEW READ: the bid engines (V_KEYWORD_LIFT, V_OOB_KEYWORD) are each at
-- BigQuery's planning ceiling. On 2026-08-17 V_PANEL_OWNERSHIP stopped planning outright because it
-- inlined V_LOW_STOCK_ADS, and the repair was exactly this pattern. The engines LEFT JOIN this
-- TABLE and never the view.
--
-- Fully derived and idempotent: CREATE OR REPLACE TABLE from the view. Safe to run repeatedly.
-- Runs EARLY in the orchestrator, before the engine T_ builds, so the engines compile against the
-- bars of the run they are part of.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR`()
OPTIONS (
  description = "Materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19). Six rows, one per family: the measured halo factor and the keyword bar the bid engines judge ads-attributed GP-ROAS against. Exists because the engines are at BigQuery's planning ceiling and must join a table, never inline the view. Idempotent. Orchestrator task 20.4, before the engine T_ builds. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md."
)
BEGIN
  -- CAMPAIGN GRAIN, deliberately. The bid engines publish campaign_id and NOT family (verified
  -- 2026-08-19: neither V_KEYWORD_LIFT nor V_OOB_KEYWORD has a family/parent column). Resolving
  -- family inside those views would mean joining V_CAMPAIGN_FAMILY_MAP inside a planner-ceiling
  -- view — exactly the move that broke V_PANEL_OWNERSHIP on 2026-08-17. So the explosion happens
  -- HERE, once, and the engines do a single LEFT JOIN on a key they already carry.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_FAMILY_BAR` AS
  SELECT
    CAST(m.campaign_id AS STRING) AS campaign_id,
    b.*
  FROM `onyga-482313.OI.V_FAMILY_BAR` b
  JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.parent_name = b.family;
END;
```

- [ ] **Step 4: Deploy, run, assert**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t5_assert.sql)"
```
Expected: `null_bars 0`, `null_campaign_ids 0`, `duplicate_campaigns 0`, and `families` equal to
the number of families `V_FAMILY_BAR` publishes — **read that off the view in the same session; it is
a measurement and no fixed value may gate this step** (Standing Rule 0; this line used to pin it).

`rows_in_table` is **not** pinned here and must not be (Standing Rule 0 — this step used to expect a
row count that the table had never held, and it contradicted `config.yaml`'s own `T_FAMILY_BAR` entry
for a day). The row count is one per ENABLED
campaign that `V_CAMPAIGN_FAMILY_MAP` resolves to a real family, and campaigns are enabled and
paused daily, so the count moves on its own. Check the **property** — that the table holds exactly
the mapped, non-`Unknown` campaigns and nothing else:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT (SELECT COUNT(*) FROM \`onyga-482313.OI.T_FAMILY_BAR\`)                              AS rows_in_table,
        (SELECT COUNT(*) FROM \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\`
          WHERE parent_name <> 'Unknown')                                                    AS mapped_campaigns,
        (SELECT COUNT(*) FROM \`onyga-482313.OI.T_FAMILY_BAR\`)
      - (SELECT COUNT(*) FROM \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\`
          WHERE parent_name <> 'Unknown')                                                    AS gap"
```
Expected: `gap 0`, whatever the two counts happen to be that day.

- [ ] **Step 5: Prove idempotence**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t5_assert.sql)"
```
Expected: identical counts to Step 4.

- [ ] **Step 6: Wire into the orchestrator**

Find the anchor and insert the call BEFORE the engine `T_` builds:

```bash
grep -n "SP_SNAPSHOT_PANEL_OWNERSHIP\|REBUILD_T_CAMPAIGN_PRODUCT_SCOPE" \
  scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql | head -4
```

Insert a task block immediately before the `SP_SNAPSHOT_PANEL_OWNERSHIP` call, following the file's existing OK/FAIL `LOG_PIPELINE_RUNS` wrapper pattern exactly as the neighbouring tasks do (copy the shape from the block around the line the grep reports). The task label is `SP_SNAPSHOT_FAMILY_BAR`.

- [ ] **Step 7: Deploy the orchestrator and verify ordering**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT STRPOS(ddl,'CALL \`onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR\`')     AS bar_call_pos,
        STRPOS(ddl,'CALL \`onyga-482313.OI.SP_SNAPSHOT_PANEL_OWNERSHIP\`') AS ownership_call_pos
 FROM \`onyga-482313.OI\`.INFORMATION_SCHEMA.ROUTINES
 WHERE routine_name='SP_ORCHESTRATE_DAILY_REFRESH'"
```
Expected: both non-zero, and `bar_call_pos` strictly less than `ownership_call_pos`. **That
ordering is the pass condition; the two character offsets themselves are a measurement of a DDL that
changes every time the procedure is edited, so do not write them down and never compare against a
pair recorded here.**

**Search for the CALL, never the bare procedure name.** An earlier version of this check searched the
DDL for `SP_SNAPSHOT_FAMILY_BAR` and `SP_SNAPSHOT_PANEL_OWNERSHIP` on their own. Both names also
appear inside comments elsewhere in the procedure, and `STRPOS` returns the FIRST occurrence, so the
check compared a comment against a comment and reported the two calls in the WRONG ORDER — a
mis-ordering that
does not exist. Anyone acting on that reading would have re-ordered a correct orchestrator.

- [ ] **Step 8: Register T_FAMILY_BAR in config.yaml (tables:) and commit**

```bash
git add scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql \
        scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql config.yaml
git commit -m "feat: SP_SNAPSHOT_FAMILY_BAR — materialize the bars so engines never inline the view"
```

---

## Task 6: `V_INVEST_STATUS` — budget, ramp and proof

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. DO NOT RE-DEPLOY IT.**
> Live in `7e32ee2`, then corrected in `72acbdf`, `0e4e568`, `acbf7be` and `ee193ca` — **and this
> list is exactly the kind of thing that goes stale** (it named two of those five until 2026-08-20).
> Take it from git, not from here: `git log --oneline -- scripts/bigquery/views/V_INVEST_STATUS.sql`.
> The most recent of them, `ee193ca`, replaced the month-to-date spend rate with a trailing window of
> 28 complete days and DELETED the whole fallback apparatus, so anything below about "last complete
> month", `is_fallback` or `rate_window_is_last_complete_month` describes an object that no longer
> exists. The block below breaks house rule 2
> and house rule 4 in the same CTE: its month-to-date window is `WHERE u.date >= DATE_TRUNC(...)`
> with **no upper bound**, so it sweeps in today's part-loaded day, divides the spend by a day count
> that includes it, and reports a spend rate diluted toward compliance — on a view whose entire job
> is to say whether the sanctioned spend rate is being exceeded. The deployed file splits the two
> measures that were tangled here: the spend rate is ads-only and ends at the ads watermark, the
> money number is blended and ends at the orders watermark, and each publishes its own window start
> and end so no reader has to guess which days a column covers. Read
> `scripts/bigquery/views/V_INVEST_STATUS.sql`.

**Files:**
- Create: `scripts/bigquery/views/V_INVEST_STATUS.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t6_assert.sql`:

```sql
-- ASSERT: phases are correct, and the ramp verdict never reads "unprofitable".
SELECT
  COUNTIF(phase NOT IN ('RAMP','PROOF'))                                AS bad_phase,
  COUNTIF(launch_age_months <= 3 AND phase <> 'RAMP')                   AS ramp_misassigned,
  COUNTIF(launch_age_months > 3  AND phase <> 'PROOF')                  AS proof_misassigned,
  COUNTIF(phase = 'RAMP' AND LOWER(verdict) LIKE '%unprofitab%')        AS ramp_judged_on_profit,
  COUNTIF(spend_breached AND exemption_live)                            AS spend_breach_still_exempt,
  COUNTIF(takeover_target_organic_units IS NULL
          AND LOWER(verdict) LIKE '%target%'
          AND LOWER(verdict) NOT LIKE '%not set%')                       AS null_target_judged_as_zero
FROM `onyga-482313.OI.V_INVEST_STATUS`;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t6_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.V_INVEST_STATUS`

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_INVEST_STATUS.sql`:

```sql
-- =============================================
-- V_INVEST_STATUS — the Invest book: budget consumed, trajectory, exemption state (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §5.
--
-- THE QUESTION CHANGES WITH AGE (Ori 2026-08-19: "the question of launch products is are they
-- improving — not are they profitable — in the first 3 months").
--
--   RAMP  (months 0-3): judged on TRAJECTORY ONLY. Nothing is required to be positive; everything is
--                       required to be IMPROVING — organic units rising, total net ROAS rising, loss
--                       shrinking. The decision rule is "no improvement across two consecutive
--                       months", NEVER "still unprofitable". A profitable-at-month-2 test would kill
--                       every launch that was working.
--   PROOF (months 3+):  level starts to matter — closing on the declared take-over target by the
--                       end date, with the ceiling and clock enforcing themselves.
--
-- WHY ABSOLUTE ORGANIC UNITS, NOT SHARE: share is a trap — it rises when ads units collapse, which
-- looks like success and is not. A launch can reach an established family's organic SHARE while
-- still losing money every month, and by share alone it would read "finished". No share figures are
-- written here (Standing Rule 0); compare them yourself off V_FAMILY_PNL.organic_pct.
--
-- A USEFUL CONSEQUENCE: trajectory is robust to a level bias. A constant COGS misallocation cancels
-- out of a month-over-month trend, which is why an implausible sub-1.0 halo (spec §9.1) does not
-- block the ramp test — though it must be fixed before that family reaches PROOF, which judges a
-- LEVEL. Always name the WINDOW when you quote a halo: the same family reads differently on
-- BASELINE_MAY_JUL and on the settled M3 window the bar actually uses.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INVEST_STATUS` AS
WITH b AS (
  SELECT * FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'
),
-- the three most recent COMPLETE calendar months, per family, from the measurement spine
m AS (
  SELECT family, period_label, period_start, net_profit, total_net_roas, organic_units
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE REGEXP_CONTAINS(period_label, r'^\d{4}-\d{2}$')
    AND period_end < DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)
),
ranked AS (
  SELECT m.*, ROW_NUMBER() OVER (PARTITION BY family ORDER BY period_start DESC) AS rn
  FROM m JOIN b USING (family)
),
trend AS (
  SELECT family,
    MAX(IF(rn=1, organic_units, NULL))  AS org_m0, MAX(IF(rn=2, organic_units, NULL))  AS org_m1, MAX(IF(rn=3, organic_units, NULL))  AS org_m2,
    MAX(IF(rn=1, total_net_roas, NULL)) AS tnr_m0, MAX(IF(rn=2, total_net_roas, NULL)) AS tnr_m1, MAX(IF(rn=3, total_net_roas, NULL)) AS tnr_m2,
    MAX(IF(rn=1, net_profit, NULL))     AS np_m0,  MAX(IF(rn=2, net_profit, NULL))     AS np_m1,  MAX(IF(rn=3, net_profit, NULL))     AS np_m2
  FROM ranked WHERE rn <= 3 GROUP BY family
),
-- MONTH-TO-DATE SPEND RATE — the binding constraint (Ori 2026-08-19: "spend rate binds").
-- (SUPERSEDED IN THE DEPLOYED FILE: the rate window became a TRAILING span of complete days on
-- 2026-08-20 — read scripts/bigquery/views/V_INVEST_STATUS.sql, not this block.)
-- daily_investment is the number Ori actually sanctioned — a DECLARED CONSTANT on
-- DE_LAUNCH_INVESTMENT. The net-profit ceiling is computed too, but only as a catastrophe backstop:
-- it was backfilled as the sanctioned SPEND rate monthised, and a launch family with real sales
-- loses far less than it spends, so it is a loose bound by construction and a family can sit deep
-- inside it while running well over its rate. Enforcing on it would be enforcement in name only.
mtd AS (
  SELECT u.family,
    ROUND(SUM(u.sales - u.cogs) - SUM(u.ad_cost), 2)                       AS mtd_net_profit,
    ROUND(SUM(u.ad_cost), 2)                                               AS mtd_spend,
    COUNT(DISTINCT u.date)                                                 AS mtd_days,
    ROUND(SAFE_DIVIDE(SUM(u.ad_cost), NULLIF(COUNT(DISTINCT u.date), 0)), 2) AS mtd_spend_per_day
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  WHERE u.date >= DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)
  GROUP BY 1
)
SELECT
  b.family,
  b.launch_age_months,
  IF(b.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  -- THE BINDING SANCTION
  b.daily_investment,
  COALESCE(mtd.mtd_spend_per_day, 0)                                                  AS mtd_spend_per_day,
  ROUND(SAFE_DIVIDE(COALESCE(mtd.mtd_spend_per_day, 0), NULLIF(b.daily_investment, 0)), 2) AS spend_rate_ratio,
  (COALESCE(mtd.mtd_spend_per_day, 0) > b.daily_investment)                           AS spend_breached,
  -- the catastrophe backstop, published but NOT enforcing
  b.monthly_loss_ceiling,
  COALESCE(mtd.mtd_net_profit, 0)                                                     AS mtd_net_profit,
  ROUND(100 * SAFE_DIVIDE(-COALESCE(mtd.mtd_net_profit, 0), NULLIF(b.monthly_loss_ceiling, 0)), 1) AS ceiling_used_pct,
  (-COALESCE(mtd.mtd_net_profit, 0) >= b.monthly_loss_ceiling)                        AS ceiling_breached,
  b.stop_date,
  DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY)                    AS days_left,
  -- THE EXEMPTION: live only while inside the window AND under the SANCTIONED SPEND RATE.
  -- The engine stops, not the human. Spend rate binds; the loss ceiling is a backstop behind it.
  (CURRENT_DATE('America/Los_Angeles') <= b.stop_date
   AND COALESCE(mtd.mtd_spend_per_day, 0) <= b.daily_investment
   AND -COALESCE(mtd.mtd_net_profit, 0) < b.monthly_loss_ceiling)                     AS exemption_live,
  t.org_m2, t.org_m1, t.org_m0,
  t.tnr_m2, t.tnr_m1, t.tnr_m0,
  t.np_m2,  t.np_m1,  t.np_m0,
  -- the three RAMP trends; NULL-safe so a young family with two months of data still reports
  (t.org_m0 > t.org_m1)                                                               AS organic_units_rising,
  (t.tnr_m0 > t.tnr_m1)                                                               AS net_roas_rising,
  (t.np_m0  > t.np_m1)                                                                AS loss_shrinking,
  b.takeover_target_organic_units,
  CASE
    WHEN b.launch_age_months <= 3 THEN
      CASE
        WHEN t.org_m1 IS NULL THEN 'too early to judge — needs two complete months'
        WHEN t.org_m0 > t.org_m1 AND t.np_m0 > t.np_m1
          THEN CONCAT('improving — organic units ', CAST(t.org_m1 AS STRING), ' to ', CAST(t.org_m0 AS STRING), ', loss shrinking')
        WHEN t.org_m2 IS NOT NULL AND t.org_m0 <= t.org_m1 AND t.org_m1 <= t.org_m2
          THEN 'no improvement two months running — the investment is not working'
        ELSE CONCAT('mixed — organic units ', CAST(t.org_m1 AS STRING), ' to ', CAST(t.org_m0 AS STRING), ', watch next month')
      END
    ELSE
      CASE
        WHEN b.takeover_target_organic_units IS NULL
          THEN CONCAT('no take-over target set — ', CAST(t.org_m0 AS STRING),
                      ' organic units last complete month, but nothing to judge it against')
        WHEN t.org_m0 >= b.takeover_target_organic_units
          THEN CONCAT('took over — ', CAST(t.org_m0 AS STRING), ' organic units against a target of ', CAST(b.takeover_target_organic_units AS STRING))
        ELSE CONCAT('short of target — ', CAST(t.org_m0 AS STRING), ' of ', CAST(b.takeover_target_organic_units AS STRING), ' organic units, ',
                    CAST(DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY) AS STRING), ' days left')
      END
  END                                                                                 AS verdict
FROM b
LEFT JOIN trend t ON t.family = b.family
LEFT JOIN mtd    ON mtd.family = b.family;
```

- [ ] **Step 4: Deploy and assert with a real declaration**

**Bunny is already declared** (Task 2 extended the existing row: $30/day sanctioned, stop_date
2026-10-31, ceiling backfilled to ~$913/month). Do NOT insert a new declaration and do NOT invent
numbers — the earlier draft of this task proposed a $2,500 ceiling and a 2026-11-30 end date, both
of which contradict what Ori actually sanctioned on 2026-08-13.

`takeover_target_organic_units` is deliberately NULL until Ori supplies it, so the PROOF branch must
report "target not set" rather than comparing against zero. Verify the view handles that:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_INVEST_STATUS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t6_assert.sql)"
```
Expected: all five counters `0`.

- [ ] **Step 5: Read the verdict in plain words**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, phase, launch_age_months, ROUND(mtd_net_profit,0) mtd, ceiling_used_pct,
        exemption_live, org_m2, org_m1, org_m0, verdict
 FROM \`onyga-482313.OI.V_INVEST_STATUS\`"
```
Expected: `phase` follows the declared rule `IF(launch_age_months <= 3, 'RAMP', 'PROOF')`, so which
phase a family is in depends on the run date and either answer can be correct — check the rule, not a
phase written here. **`takeover_target_organic_units` is NULL on every row until Ori supplies one**,
so a PROOF verdict must report that no take-over target is on record rather than compare against a
number; a version of this line expected a verdict naming units "against the 400 target", and no such
target exists. **What must never happen is a RAMP verdict mentioning profitability** — that is the
assertion, and it is a property, not a count.

- [ ] **Step 6: Register in config.yaml and commit**

```bash
git add scripts/bigquery/views/V_INVEST_STATUS.sql config.yaml
git commit -m "feat: V_INVEST_STATUS — bounded budget, ramp trajectory, proof against target"
```

---

## Task 7: `V_TWO_BOOK_BRIEF` — the morning read

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. RE-DEPLOYING IT WOULD LOSE THREE COMMITS OF
> FIXES, AND STEP 4'S ASSERTION WOULD STILL SAY IT PASSED.**
> Live in `fa840df`, then seven more commits — **take the list from git, not from here**
> (`git log --oneline -- scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql`); this banner used to name a
> fixed few of them. The block below publishes a NARROW column set off a LEFT JOIN spine; the
> deployed view publishes a different set off a FULL OUTER JOIN of the two family universes, so a
> declared family with no measured P&L still appears instead of vanishing from the brief. **The
> column count is deliberately not written here** (Standing Rule 0): this banner has pinned one twice
> and the object has been recolumned three times since. Count it yourself —
> `SELECT COUNT(*) FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\` WHERE table_name='V_TWO_BOOK_BRIEF'`.
> The deployed view also carries the enforcement-gap dollars that the 2026-08-20 ruling required.
> The Step 4 assertion cannot protect you here: it checks that the Harvest total reconciles to the
> Harvest family rows, and while every family appears on both sides of the spine the OLD spine
> reconciles perfectly too, so it would report a clean pass over a reverted view. Read
> `scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql`.

**Files:**
- Create: `scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t7_assert.sql`:

```sql
-- ASSERT: two books, never blended, and the Harvest total reconciles to its own rows.
WITH r AS (SELECT * FROM `onyga-482313.OI.V_TWO_BOOK_BRIEF`)
SELECT
  COUNTIF(book NOT IN ('HARVEST','INVEST'))                                    AS bad_books,
  COUNTIF(row_kind NOT IN ('FAMILY','TOTAL'))                                  AS bad_row_kinds,
  (SELECT COUNT(*) FROM r WHERE row_kind='TOTAL')                              AS total_rows,
  ABS((SELECT SUM(net_profit) FROM r WHERE book='HARVEST' AND row_kind='FAMILY')
    - (SELECT MAX(net_profit) FROM r WHERE book='HARVEST' AND row_kind='TOTAL')) AS harvest_reconcile_gap
FROM r;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t7_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.V_TWO_BOOK_BRIEF`

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql`:

```sql
-- =============================================
-- V_TWO_BOOK_BRIEF — the morning read: two books, never blended (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §6.
--
-- THE POINT OF THE WHOLE DESIGN IS THIS ONE SENTENCE. A month can read as "the account lost money"
-- and be untrue: Harvest earning while a deliberate, undeclared launch investment spends some of it,
-- under an ads-attributed lens that cannot see the organic units. The brief reports "Harvest earned
-- X; Invest spent Y of its declared budget" and never adds those two together. Reproduce the month
-- that showed it rather than quoting a figure:
--   SELECT ROUND(SUM(net_profit),0), ROUND(SUM(ad_spend*(ads_net_roas-1)),0)
--   FROM `onyga-482313.OI.V_FAMILY_PNL` WHERE period_label = '2026-07';   -- opposite signs
--
-- NET PROFIT LEADS, THE RATIO EXPLAINS IT (Ori's framing is total dollars). A ratio has no size in
-- it: two families the same distance under 1.0 can be a rounding error apart in dollars or thousands
-- apart, because the ratio says nothing about how much was spent to get there. Rank on the dollars.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_TWO_BOOK_BRIEF` AS
WITH pnl AS (
  SELECT family, net_profit, total_net_roas, ads_net_roas, halo_factor, organic_pct, ad_spend
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'
),
bar AS (SELECT family, keyword_bar FROM `onyga-482313.OI.V_FAMILY_BAR`),
bk  AS (SELECT family, book FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`),
inv AS (SELECT family, phase, ceiling_used_pct, days_left, exemption_live, verdict FROM `onyga-482313.OI.V_INVEST_STATUS`),
fam AS (
  SELECT
    bk.book, 'FAMILY' AS row_kind, p.family,
    ROUND(p.net_profit, 0)      AS net_profit,
    ROUND(p.total_net_roas, 2)  AS total_net_roas,
    ROUND(p.ads_net_roas, 2)    AS ads_net_roas,
    ROUND(p.halo_factor, 2)     AS halo_factor,
    ROUND(b.keyword_bar, 2)     AS keyword_bar,
    p.organic_pct,
    i.phase, i.ceiling_used_pct, i.days_left, i.exemption_live,
    COALESCE(
      i.verdict,
      CASE
        WHEN p.net_profit >= 0 THEN CONCAT('earning — ', FORMAT('%.2f', p.total_net_roas), 'x on ', FORMAT('$%.0f', p.ad_spend), ' of spend')
        ELSE CONCAT('losing ', FORMAT('$%.0f', -p.net_profit), ' — ', FORMAT('%.2f', p.total_net_roas),
                    'x, halo ', FORMAT('%.2f', p.halo_factor))
      END)                      AS verdict
  FROM pnl p
  LEFT JOIN bk  ON bk.family  = p.family
  LEFT JOIN bar b ON b.family = p.family
  LEFT JOIN inv i ON i.family = p.family
),
tot AS (
  SELECT book, 'TOTAL' AS row_kind, CAST(NULL AS STRING) AS family,
    ROUND(SUM(net_profit), 0) AS net_profit,
    CAST(NULL AS FLOAT64) AS total_net_roas, CAST(NULL AS FLOAT64) AS ads_net_roas,
    CAST(NULL AS FLOAT64) AS halo_factor,    CAST(NULL AS FLOAT64) AS keyword_bar,
    CAST(NULL AS FLOAT64) AS organic_pct,
    CAST(NULL AS STRING)  AS phase, CAST(NULL AS FLOAT64) AS ceiling_used_pct,
    CAST(NULL AS INT64)   AS days_left, CAST(NULL AS BOOL) AS exemption_live,
    CONCAT(book, ' book: ', FORMAT('$%.0f', SUM(net_profit))) AS verdict
  FROM fam GROUP BY book
)
SELECT * FROM fam UNION ALL SELECT * FROM tot;
```

- [ ] **Step 4: Deploy and assert**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t7_assert.sql)"
```
Expected: `bad_books 0, bad_row_kinds 0, total_rows 2, harvest_reconcile_gap 0`

- [ ] **Step 5: Read the brief as Ori would**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT book, row_kind, COALESCE(family,'—') family, net_profit, total_net_roas, halo_factor, keyword_bar, verdict
 FROM \`onyga-482313.OI.V_TWO_BOOK_BRIEF\`
 ORDER BY book, row_kind DESC, net_profit DESC"
```
Read every verdict string aloud. Each must be a plain sentence a person could act on, with no rule names, no jargon and no bare metric codes. If any reads like engine internals, fix the string before committing.

- [ ] **Step 6: Register in config.yaml and commit**

```bash
git add scripts/bigquery/views/V_TWO_BOOK_BRIEF.sql config.yaml
git commit -m "feat: V_TWO_BOOK_BRIEF — Harvest and Invest reported separately, never blended"
```

---

## Task 8: Wire the bar into the bid engines

> **⚠ ON HOLD — DO NOT RUN. `V_KEYWORD_LIFT` and `V_OOB_KEYWORD` are the LIVE bid engines and are
> not to be edited (Ori, 2026-08-20: *"Tell the truth now, release nothing."*).**
> This task is the one that actually moves money: it changes the threshold two live engines cut
> bids against, on every keyword in the account, the next time the daily orchestrator runs. Tasks 8b
> and 9 each carry a banner and this one did not, which left the heaviest task in the plan reading
> as runnable (added 2026-08-20 — Tasks 8b and 9 were banner-checked in the same sweep and this one
> was missed). The steps below have been repaired so they are safe to execute *if* the hold is ever
> lifted. They are a repair, not a permission.
>
> **HOW FAR THE "SAFE TO EXECUTE" CLAIM ACTUALLY REACHES (qualified 2026-08-20 — this banner used to
> say "every statement written into them was dry-run against live BigQuery on 2026-08-20", and Step 6
> says in its own words that one statement was not).** Two things are NOT dry-run and cannot be:
> 1. **Step 6's first query carries an unresolved placeholder** — `<the action labels of the
>    breakeven arm you edited in Step 3>` — so it does not parse as written. Step 6 says so itself.
>    Substitute the real labels and dry-run it yourself; a `0` from a query that never named the arm
>    you edited is not a pass, it is a query that measured nothing.
> 2. **Every statement that reads `V_KEYWORD_LIFT` or `V_OOB_KEYWORD` after Step 3 reads an object
>    that does not exist yet.** Step 3 is a hand edit to two live engine files. Nothing downstream of
>    it can have been validated against the post-edit views, because the post-edit views have never
>    been written. Steps 4-7 are a *procedure* for finding out whether the edit was safe — that is
>    their whole purpose — not evidence that it was.
>
> What IS true: the statements that read only objects existing today (Step 1's capture, Step 4's two
> planner dry runs, Step 7's determinism pulls) run against live BigQuery as written. Do not upgrade
> that into a claim about the task as a whole. **A "safe to execute" sentence with nothing behind it
> is the specific defect the previous round was raised to remove from Task 8b; it must not be written
> back onto either task.**

The behaviour change. Do this last, and prove what moved.

**Files:**
- Modify: `scripts/bigquery/views/V_KEYWORD_LIFT.sql`
- Modify: `scripts/bigquery/views/V_OOB_KEYWORD.sql`

- [ ] **Step 1: Capture the before-state**

```bash
cd /Users/ori/Develop/OI
for f in V_KEYWORD_LIFT V_OOB_KEYWORD; do
  cp scripts/bigquery/views/$f.sql scripts/bigquery/views/$f.sql.bak.twobook.$(date +%H%M)
done
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT 'LIFT' src, action, COUNT(*) n FROM \`onyga-482313.OI.V_KEYWORD_LIFT\` GROUP BY 1,2 ORDER BY 3 DESC" \
  > /tmp/before_lift.csv
cat /tmp/before_lift.csv

# The gate in Step 6 compares against THIS capture, not against a number typed into this document.
# It is the SET of cut arms that reach a bar-exempt campaign — the property Step 3 must not widen.
# Capture it in the same session, minutes before the edit, or the comparison means nothing.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT DISTINCT l.action
 FROM \`onyga-482313.OI.V_KEYWORD_LIFT\` l
 JOIN \`onyga-482313.OI.T_FAMILY_BAR\` b ON b.campaign_id = CAST(l.campaign_id AS STRING)
 WHERE l.suggested_bid < l.current_bid AND b.bar_exempt
 ORDER BY 1" | tail -n +2 > /tmp/before_exempt_arms.csv
cat /tmp/before_exempt_arms.csv
```

- [ ] **Step 2: Find the flat-1.0 breakeven sites**

```bash
grep -n "breakeven_roas\|>= 1.0\|< 1.0" scripts/bigquery/views/V_KEYWORD_LIFT.sql | head -20
```

The LIFT engine's breakeven arm is documented around lines 1275–1290 (SP) and 1849+ (SB): *"Poor 28d net ROAS (< 1.0) with the bid above that breakeven -> cut TO it."* That literal `1.0` is the flat bar this task replaces.

- [ ] **Step 3: Add the bar join and replace the flat 1.0**

Both engines publish `campaign_id` and neither publishes a family column (verified 2026-08-19), which
is why `T_FAMILY_BAR` is campaign-grain. Find the base CTE that carries `campaign_id`:

```bash
grep -n "campaign_id" scripts/bigquery/views/V_KEYWORD_LIFT.sql | head -6
```

Add the join to that CTE:

```sql
-- v27.84 (2026-08-19, two-book P&L): the profit bar is now per-family, set from the family's
-- MEASURED organic halo, because ads-attributed GP-ROAS structurally undervalues any keyword that
-- drives organic sales. THE WORKED EXAMPLE IS A QUERY, NOT FOUR NUMBERS (rewritten 2026-08-20 —
-- this comment ships VERBATIM into a live bid engine, so a stale figure here becomes a stale figure
-- inside the thing that moves money, and an earlier draft of it already had: it named one family's
-- ads ROAS, total ROAS and halo, and every one of the three was wrong against the window this view
-- actually reads. The replacement briefly named the LIVE values instead, which is the same defect
-- one day later. NO FIGURE OF ANY VINTAGE GOES IN THIS COMMENT.) Run this to see the shape:
--   SELECT family, ads_net_roas, total_net_roas, halo_factor, keyword_bar, bar_exempt
--   FROM `onyga-482313.OI.V_FAMILY_BAR` ORDER BY keyword_bar;
-- The shape it shows — and the reason this join exists — is that the family with the account's
-- strongest halo carries the LOWEST bar, i.e. the keywords carrying the organic sales are exactly
-- the ones a flat 1.0 bar would cut hardest. DO NOT COPY A ROW OF THAT OUTPUT INTO THIS COMMENT.
-- The bars move with every rebuild of the settled window, and at least one family's total net ROAS
-- sits within a percent of 1.000 and crosses it on a routine restatement. Nothing here is a
-- threshold. Reads the TABLE, never V_FAMILY_BAR:
-- this view is at BigQuery's planning ceiling and inlining another view is what broke
-- V_PANEL_OWNERSHIP on 2026-08-17. Six rows, LEFT JOIN, COALESCE to 1.0 so a missing family keeps
-- exactly the old behaviour — the bar may only ever LOWER the threshold.
LEFT JOIN `onyga-482313.OI.T_FAMILY_BAR` fb
       ON fb.campaign_id = CAST(<the base CTE's campaign_id column> AS STRING)
```

Then replace each flat breakeven comparison. Every site changes from a bare `1.0` to `COALESCE(fb.keyword_bar, 1.0)`, and `bar_exempt` families are skipped:

```sql
-- was:  <roas expression> < 1.0
-- now:
<roas expression> < COALESCE(fb.keyword_bar, 1.0) AND NOT COALESCE(fb.bar_exempt, FALSE)
```

Apply the identical change to `V_OOB_KEYWORD.sql`. **No-drift rule:** if the file has parallel action/value/reason ladders, every one of them must use the same predicate text — a bar in the action ladder and a flat 1.0 in the reason ladder produces a row whose number and explanation disagree.

- [ ] **Step 4: Deploy and immediately dry-run the planner**

```bash
for f in V_KEYWORD_LIFT V_OOB_KEYWORD; do
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
    "$(grep -v '^--' scripts/bigquery/views/$f.sql)"
done
bq query --project_id=onyga-482313 --use_legacy_sql=false --dry_run \
  "SELECT COUNT(*) FROM \`onyga-482313.OI.V_KEYWORD_LIFT\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --dry_run \
  "SELECT COUNT(*) FROM \`onyga-482313.OI.V_PANEL_OWNERSHIP\`"
```

**If either dry-run fails to plan, restore from the `.bak.twobook.*` file, redeploy, and STOP.** These views have no measured planner headroom; a broken ownership pipeline is far worse than a delayed feature.

- [ ] **Step 5: Flip report — prove what moved and why**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT 'LIFT' src, action, COUNT(*) n FROM \`onyga-482313.OI.V_KEYWORD_LIFT\` GROUP BY 1,2 ORDER BY 3 DESC" \
  > /tmp/after_lift.csv
diff /tmp/before_lift.csv /tmp/after_lift.csv || true
```

Expected direction: **fewer cuts**, concentrated in whichever families carry the highest measured
halo — read that off `V_FAMILY_BAR ORDER BY keyword_bar` on the day you run this, do not take it
from a name written here. Zero new raises — the bar can only lower a cut threshold, never manufacture
a raise. Any new raise means the predicate was inverted somewhere; find it before proceeding.

- [ ] **Step 6: Confirm the breakeven arm never cuts a bar-exempt family**

The gate is on **the arm Step 3 changed** — the breakeven cut, the only place a flat `1.0` was ever
compared. Nothing else in this task touches any other arm, so nothing else may be gated on it:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNT(*) AS breakeven_cuts_on_exempt_families
 FROM \`onyga-482313.OI.V_KEYWORD_LIFT\` l
 JOIN \`onyga-482313.OI.T_FAMILY_BAR\` b ON b.campaign_id = CAST(l.campaign_id AS STRING)
 WHERE l.suggested_bid < l.current_bid
   AND b.bar_exempt
   AND l.action IN (<the action labels of the breakeven arm you edited in Step 3>)"
```
Expected: `0`. This is the one statement in Tasks 8 and 8b that carries an unresolved placeholder,
so it is the one that has NOT been dry-run — substitute the real action labels and dry-run it
yourself before you rely on the answer. A `0` from a query that failed to name the arm you edited is
not a pass; it is a query that measured nothing.

Then confirm this change added no NEW KIND of cut on a bar-exempt family. **Compare the arm SET
against the capture Step 1 took, not against a number written here:**

```bash
BEFORE_ARMS=$(paste -sd, /tmp/before_exempt_arms.csv | sed "s/[^,]*/'&'/g")
# An EMPTY capture is a legitimate before-state (it happens on a quiet morning), but an empty
# BigQuery array literal has no type and will not compile. One empty string keeps the array typed
# STRING and matches no real action, which is exactly the semantics wanted: nothing was there
# before, so anything after is new.
BEFORE_ARMS=${BEFORE_ARMS:-"''"}
echo "arms that reached a bar-exempt campaign before the edit: $BEFORE_ARMS"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"WITH after_arms AS (
   SELECT DISTINCT l.action
   FROM \`onyga-482313.OI.V_KEYWORD_LIFT\` l
   JOIN \`onyga-482313.OI.T_FAMILY_BAR\` b ON b.campaign_id = CAST(l.campaign_id AS STRING)
   WHERE l.suggested_bid < l.current_bid AND b.bar_exempt),
 before_arms AS (SELECT * FROM UNNEST([$BEFORE_ARMS]) AS action)
 SELECT ARRAY_TO_STRING(ARRAY(SELECT action FROM (
          SELECT action FROM after_arms EXCEPT DISTINCT SELECT action FROM before_arms
        ) ORDER BY action), ', ') AS new_cut_classes_on_exempt_families"
```
Expected: an **empty string**. Any arm named here is a class of cut that did not reach a bar-exempt
family before the edit and does now — that is the failure this step exists to catch, and it is the
same failure whether it arrives on one row or a hundred. An arm DISAPPEARING is not a failure; the
test is one-directional on purpose.

> **⚠ THE OLD GATE WAS A PINNED COUNT AND COULD NOT HOLD. DO NOT PUT ONE BACK.** It named a baseline
> number of bar-exempt cut rows and required the task to leave the count at that number. Re-running
> that exact query later **the same day**, with no code change of any kind in between, returned a
> DIFFERENT count. `V_KEYWORD_LIFT` recomputes from ads data that is materially under-loaded at age 1
> and restates for about D+3 (`fact_oi_ads_restatement_settle`), and the daily-trim and seat-queue
> arms judge on pacing and capacity, both of which move through the day. So the count is
> INTRADAY-VOLATILE and no fixed value can gate anything: pinned, it fails on a morning when nothing
> is wrong, and a gate that cries wolf gets waved through — which is worse than no gate, because the
> next person reads a red check as normal. **Gate the PROPERTY, not the population.** The property is
> "Step 3
> must not add a new class of cut on a bar-exempt campaign", the capture in Step 1 is the only valid
> baseline, and it must be taken in the same session as the edit.

**NON-GOAL, stated so nobody removes it later: `AUTO_DAY_TRIM` and `PARK` must keep working on
Invest families**, and the check above is deliberately written so it never asks them to stop. The
original wording of this step asserted zero bid decreases of **any** kind on bar-exempt campaigns,
which has never been achievable: those arms judge on daily pacing and on capacity, not on any profit
bar, and `V_LAUNCH_EXEMPTION.sql:290` (the `allows` list) names exactly those levers as the ones a launch exemption
**allows**, because they are the sanctioned way a launch is contained. Forcing them to zero would
remove the only downward levers left on the two families burning the most money.

The family bar exempts an Invest family from being cut *for missing a profit bar*. It does not exempt
it from pacing, from capacity, or from any other control. An Invest family is judged on sanction
adherence and organic trajectory — a different question from profitability, not a licence to spend
without limit.

- [ ] **Step 7: Pull-twice determinism on both engines**

```bash
for v in V_KEYWORD_LIFT V_OOB_KEYWORD; do
  Q="SELECT TO_HEX(MD5(STRING_AGG(TO_JSON_STRING(t),'' ORDER BY TO_JSON_STRING(t)))) h, COUNT(*) n FROM \`onyga-482313.OI.$v\` t"
  echo "== $v"
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv "$Q" | tail -1
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv "$Q" | tail -1
done
```
Expected: identical hash per view.

- [ ] **Step 8: Commit**

```bash
git add scripts/bigquery/views/V_KEYWORD_LIFT.sql scripts/bigquery/views/V_OOB_KEYWORD.sql
git commit -m "feat: bid engines judge against the per-family halo bar, not a flat 1.0"
```

---

## Task 8b: `V_LAUNCH_EXEMPTION` — the exemption expires on the sanctioned spend rate and the clock

> **⚠ ON HOLD — DO NOT RUN. `V_LAUNCH_EXEMPTION` is not to be edited (Ori, 2026-08-20).**
> The steps below have been repaired so that they are safe to execute *if* the hold is ever lifted.
> Three of them could not run at all as originally written, and the obvious repair to a fourth would
> have silently widened Bunny's sanctioned backstop by 2.74x. Read the whole task before touching
> anything.
>
> **HOW FAR THE "SAFE TO EXECUTE" CLAIM ACTUALLY REACHES (qualified 2026-08-20, fourth round — this
> banner used to say flatly "every SQL statement in this task has now been dry-run or executed
> against live BigQuery", and that sentence reaches further than the evidence does; Task 8's banner
> was qualified in the third round and this one was not).** The round before it wrote an unbacked
> "safe to execute" while the task still contained a statement BigQuery refuses to compile, a join
> that silently produces a cartesian product, and four references to two columns that had been
> renamed upstream — so the flat claim has been false here once already.
>
> **What IS backed:** every statement that reads only objects existing today — Step 1's assertion,
> Step 2's run of it, the planner dry run above, Step 4's `── 0`/`── 1`/`── 2` reads and the Step 4
> `── 3` MERGE's dry run, and Step 5 — has been executed or dry-run against live BigQuery.
>
> **What is NOT backed, and cannot be:** **everything from Step 3 onwards that reads
> `V_LAUNCH_EXEMPTION` reads a view that has never been written.** Step 3 is a hand edit to a live
> engine file; the post-edit view does not exist, so no statement downstream of it can have been
> validated against the object it will actually run against. That includes Step 3's own dry run of
> the edited file, Step 4's `bunny_rows` / `bunny_campaigns_still_exempt` check, the `── 3`
> re-assertion, and Step 5's fail-open check. Steps 3-5 are a *procedure* for finding out whether
> the edit was safe — that is their purpose — not evidence that it was.
>
> The two renames are carried through: `V_INVEST_STATUS.exemption_live` is **`protection_qualified`**
> and `V_INVEST_STATUS.mtd_spend_per_day` is **`spend_per_day`** (confirm against
> `INFORMATION_SCHEMA.COLUMNS` before you run anything — this task has been wrong about column names
> twice). If you change a statement here, dry-run the version you actually wrote; a repaired step
> that nobody ran is a claim, not a repair.

Spec §5 requires the launch exemption to become conditional. Until this task runs, the sanctioned
spend rate and the end date are **reported** by `V_INVEST_STATUS` and **enforced by nobody** — which
is the exact defect the whole design exists to fix. `V_TWO_BOOK_BRIEF` says so in plain words and
publishes the gap in dollars, so the truth is visible while the enforcement waits.

**Files:**
- Modify: `scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql`

### The two column names this task keeps getting wrong

Verified against `INFORMATION_SCHEMA.COLUMNS` on 2026-08-20:

| object | the family key it publishes | it does **not** have |
|---|---|---|
| `V_LAUNCH_EXEMPTION` | `family` | `parent_name` |
| `V_INVEST_STATUS` | `family` | `parent_name` |
| `V_BOOK_ASSIGNMENT` | `family` | `parent_name` |
| `DE_LAUNCH_INVESTMENT` | `parent_name` | `family` |

The declaration TABLE is keyed on `parent_name`; every VIEW above it republishes that key as
`family`. Task 3's own banner at the top of this plan says exactly this, and earlier drafts of this
task still wrote `e.parent_name` on the exemption view and `family` on the declaration table — four
references, all of which fail with `Unrecognized name`. They are corrected below.

### The planner-ceiling question, before you write a line

House rule 1 says never inline a planner-ceiling view. `V_LAUNCH_EXEMPTION` is a large view and
`V_INVEST_STATUS` pulls `V_FAMILY_PNL`, `V_BOOK_ASSIGNMENT` and `V_UNIFIED_DAILY` behind it. Dry-run
the join before committing to it:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --dry_run \
"SELECT COUNT(*) FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\` e
 LEFT JOIN \`onyga-482313.OI.V_INVEST_STATUS\` i ON i.family = e.family"
```

It **validates** at a modest upper bound — well inside the planner. The byte figure is a measurement
and is not written here; the dry run prints it. And a clean validation is a query-time check on the
joined SELECT, not proof that the same join survives inside the view definition, so run it again
against the edited file before you deploy.

If it does not plan, the shape is the same one that fixed `V_PANEL_OWNERSHIP`: snapshot the two or
three columns you need into a `T_` table inside `SP_SNAPSHOT_FAMILY_BAR` and join the TABLE. Decide
this before Step 3, not after a failed deploy.

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t8b_assert.sql`:

```sql
-- ASSERT: no campaign may hold a live exemption once its family has broken the sanction that
-- granted it — spending faster than the sanctioned daily rate, or running past the declared end
-- date. Families with no declaration are unaffected (fail-open).
-- BOTH sides key on `family` HERE, because both are the PUBLISHED output columns of two views in
-- the outer FROM. That is not true inside V_LAUNCH_EXEMPTION's own final SELECT — see Step 3.
-- The flag is protection_qualified (renamed from exemption_live 2026-08-20; the old name would
-- fail to compile).
SELECT COUNTIF(e.exempt_active AND NOT i.protection_qualified) AS exemptions_outliving_their_sanction
FROM `onyga-482313.OI.V_LAUNCH_EXEMPTION` e
JOIN `onyga-482313.OI.V_INVEST_STATUS` i ON i.family = e.family;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t8b_assert.sql)"
```

Expected today: a **non-zero** count, and it should equal the number of joined rows.

That is the defect, stated as a MECHANISM rather than as a count (Standing Rule 0 — this step used
to pin both families' spend rates and ratios here, and ninety-six lines later the same task stated
different figures for the same two families, so one task carried two contradictory readings). The
mechanism: `exempt_active` is hardcoded `TRUE` in `V_LAUNCH_EXEMPTION`, while `protection_qualified`
in `V_INVEST_STATUS` already reflects the sanction. Wherever a declared family is over its
sanctioned rate or past its stop date, every one of its campaigns holds an exemption that has
outlived the sanction that granted it. **When this task runs, this count must become 0 — and 0 is
the pass condition, which is a property, not a pinned population.**

Read today's rates rather than quoting a figure from this page:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, daily_investment, spend_per_day, spend_rate_ratio, spend_breached,
        ceiling_used_pct, protection_qualified, rate_window_basis
 FROM \`onyga-482313.OI.V_INVEST_STATUS\`"
```

- [ ] **Step 3: Add the spend-rate-and-clock condition**

`V_LAUNCH_EXEMPTION.sql` line 235 currently hardcodes the exemption as live:

```sql
  TRUE                              AS exempt_active,   -- camp already filters today <= exempt_until
```

Replace it so a declared family must also be inside its sanctioned spend rate and its declared
window. Undeclared families keep exactly today's behaviour — the condition can only ever REVOKE an
exemption, never grant one:

```sql
  -- v27.84 (2026-08-19, two-book P&L §5): an exemption now expires on the SPEND RATE as well as the
  -- clock. The pre-2026-08-19 exemption was open-ended, which is how a substantial monthly spend
  -- reached two families undeclared and unbounded. A family with a live declaration keeps its
  -- exemption only while it is inside its declared window AND spending at or under the daily rate
  -- Ori sanctioned in DE_LAUNCH_INVESTMENT.daily_investment.
  -- THE SPEND RATE IS THE BINDING CLAUSE, NOT THE MONTHLY LOSS CEILING, AND THAT IS A PROPERTY OF
  -- HOW THE CEILING WAS DERIVED rather than a reading of any particular day: monthly_loss_ceiling
  -- was backfilled as the sanctioned SPEND rate monthised, and a launch family with real sales
  -- loses far less than it spends, so the ceiling is a loose bound by construction. A family can
  -- therefore sit deep inside its ceiling while running well over its rate — enforcing on the
  -- ceiling would be enforcement in name only. The ceiling stays as a catastrophe backstop behind
  -- the rate. NO MEASURED RATE, RATIO OR CEILING PERCENTAGE MAY BE WRITTEN INTO THIS COMMENT: it
  -- ships verbatim into a live engine view and would become a permanent stale measurement inside
  -- it. Read them from `onyga-482313.OI.V_INVEST_STATUS` instead.
  -- FAIL-OPEN: a family with no declaration row is untouched, so this can only revoke, never grant.
  COALESCE(inv.protection_qualified, TRUE) AS exempt_active,
```

(`protection_qualified`, not `exemption_live` — renamed upstream 2026-08-20.)

Then add the join to the final SELECT's FROM chain. **Write `rolled.parent_name`. Not `family`:**

```sql
FROM rolled
LEFT JOIN `onyga-482313.OI.V_INVEST_STATUS` inv ON inv.family = rolled.parent_name
```

> **⚠ `ON inv.family = family` DOES NOT FAIL LOUDLY — IT SILENTLY DOUBLES THE VIEW.** This is the
> one place in the whole task where the column-name confusion actually bites, and the previous
> repair still had it backwards (corrected 2026-08-20). The final SELECT reads `FROM rolled`
> (`V_LAUNCH_EXEMPTION.sql:310`) and only *projects* `parent_name AS family` in its select list
> (`:224`); the line being replaced is `:235`. A select-list alias is not in scope in a JOIN's `ON` clause, so inside the join
> `rolled` offers `parent_name` and nothing called `family`. The obvious guess is that a bare
> `family` therefore raises `Unrecognized name` — **it does not**, and that is the danger.
> `V_INVEST_STATUS` itself publishes a column called `family`, so a bare `family` in the `ON` clause
> resolves to `inv.family` and the predicate becomes `inv.family = inv.family` — a tautology, i.e. a
> cross join. That is algebra, not a reading: on an N-row stand-in for `rolled` against an M-row
> `V_INVEST_STATUS`, `ON inv.family = family` returns N x M rows and
> `ON inv.family = rolled.parent_name` returns N. At full size that is every launch campaign
> duplicated once per declared family, each copy taking an arbitrary family's protection state — a
> wrong answer that compiles, deploys and looks healthy. Confirm both names before you type either:

```bash
grep -n "AS family\|parent_name" scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql | tail -6
bq query --project_id=onyga-482313 --use_legacy_sql=false --format=csv \
"SELECT table_name, column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
 WHERE table_name IN ('V_INVEST_STATUS','V_LAUNCH_EXEMPTION') AND column_name IN ('family','parent_name')"
```

Then dry-run the EDITED FILE before you deploy it — this validates the join without changing
anything, and it is how the two forms above were told apart:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --dry_run \
  "$(grep -v '^--' scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql)"
```
Expected: `Query successfully validated.` **A clean validation is necessary and not sufficient** —
the cartesian form validates too. Also run the row-count check in Step 4 `── 2`: capture the view's
launch-campaign row count BEFORE the edit and confirm it is UNCHANGED after. The count itself is a
measurement and is deliberately not written here; the property — unchanged, never multiplied by the
number of declared families — is what you check.

- [ ] **Step 4: Deploy, then force the real test on the clause that actually binds**

> **⚠ READ THIS BEFORE YOU TOUCH `DE_LAUNCH_INVESTMENT`.** An earlier version of this step breached
> the **ceiling**, then restored it with the literal `monthly_loss_ceiling = 2500.0`. That number
> came from a withdrawn draft this plan repudiates in Task 6 Step 4; Bunny's live sanctioned ceiling
> is **$913.00**. Running it would have written 2500.0 over 913.0 and widened the backstop by 2.74x,
> permanently, with nothing to catch it — the old success check was "confirm `exemption_live` returns
> to true", and *any* ceiling above the current loss produces true. **Never restore a sanctioned
> value from a literal typed into a document.** Read the live row first and write back what you read.
>
> This step no longer touches `monthly_loss_ceiling` at all. The ceiling is not the binding clause,
> so breaching it proves nothing — a launch family can sit a long way inside its ceiling and a long
> way over its sanctioned rate at the same time, because the ceiling was backfilled as the
> sanctioned spend monthised and a family with real sales loses far less than it spends. That is the
> whole reason the RATE is what gets tested. Read the two side by side rather than quoting a figure
> from here (Standing Rule 0 — the figures that used to be written in this banner went stale within a
> day, and again when the rate window itself was redefined):
> ```bash
> bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
> "SELECT family, daily_investment, spend_per_day, spend_rate_ratio, ceiling_used_pct,
>         monthly_loss_ceiling, mtd_net_profit, rate_window_basis
>  FROM \`onyga-482313.OI.V_INVEST_STATUS\`"
> ```
> *(Read against `V_INVEST_STATUS`, not `V_TWO_BOOK_BRIEF`: the brief is at the planner ceiling, and
> the version of this query that used to sit here named `times_over_agreed_rate` and
> `loss_allowance_used_pct_so_far`, columns the brief no longer carries — it did not fail quietly, it
> failed to compile. Verify every column name against `INFORMATION_SCHEMA.COLUMNS` before running.)*

> **⚠ THIS STEP WRITES AN INFLATED SANCTION TO A LIVE ROW AND LEAVES IT THERE UNTIL THE RESTORE.
> THAT IS AN EXPOSURE WINDOW, NOT A SCRATCH EDIT** (added 2026-08-20).
> `DE_LAUNCH_INVESTMENT` is not a fixture. It is read **live** by `V_BOOK_ASSIGNMENT` (which decides
> which book a family is in) and by `V_LAUNCH_EXEMPTION` (which the coach reads), so between the
> MERGE in `── 3` and the UPDATE in `── 4` Bunny's sanction reads roughly `measured rate + $10`
> instead of the $30/day Ori signed off. Anything that runs in that window — the daily orchestrator,
> a coach refresh, a person opening the brief — sees a launch that is **inside** its sanction when it
> is over it, and holds budget cuts it should be releasing. The window is only as short as the three
> `bq` calls between the two writes, and one of them is an assertion.
>
> **Three things make it safe to interrupt. Do not drop any of them.**
> 1. **The restore is written to disk BEFORE the first write**, as a complete standalone statement.
>    A shell variable dies with the shell; a file survives a `Ctrl-C`, a dropped connection, a laptop
>    lid, and the next person.
> 2. **A `trap` fires the restore on any exit path** — normal, error, or interrupt — so the row is
>    put back even if the assertion in `── 3` hangs or you kill it.
> 3. **Nothing runs between the two writes that does not have to.** The assertion is the only thing
>    that genuinely needs the raised value. Read anything else afterwards.
>
> **If you find yourself here after an interrupt and are not sure what state the row is in**, run the
> restore file on its own and then `── 5`. It is idempotent:
> ```bash
> bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(cat /tmp/bunny_sanction_restore.sql)"
> ```

```bash
set -o pipefail
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql)"

# ── 0. DO NOT OPEN THE WINDOW WHILE THE DAILY PASS IS RUNNING. If the orchestrator is mid-flight it
#       will rebuild V_BOOK_ASSIGNMENT and the coach tables off the inflated sanction.
IN_FLIGHT=$(bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNTIF(finished_at IS NULL) AS orchestrator_in_flight
 FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\`
 WHERE started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR)" | tail -1)
echo "pipeline runs still in flight: $IN_FLIGHT"
[ "$IN_FLIGHT" = "0" ] || { echo "ABORT: a pipeline run is in flight. Wait for it to finish."; exit 1; }

# ── 1. RECORD the live sanction. This value, and nothing else, is what the restore writes back.
BUNNY_RATE=$(bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT FORMAT('%.4f', daily_investment) FROM \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` WHERE parent_name='Bunny'" | tail -1)
echo "Bunny's live sanctioned daily investment is $BUNNY_RATE — the restore writes back exactly this."
case "$BUNNY_RATE" in ''|*[!0-9.]*) echo "ABORT: could not read the live sanction. Do not touch the row."; exit 1;; esac

# ── 1a. PERSIST THE RESTORE TO DISK BEFORE ANY WRITE, and arm it on every exit path. This file is
#        the thing that survives an interrupt; the shell variable is not.
printf "UPDATE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` SET daily_investment = %s WHERE parent_name='Bunny'\n" \
  "$BUNNY_RATE" > /tmp/bunny_sanction_restore.sql
cat /tmp/bunny_sanction_restore.sql
restore_bunny() {
  echo ">> restoring Bunny's sanctioned rate to $BUNNY_RATE"
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
    "$(cat /tmp/bunny_sanction_restore.sql)" || \
    echo "!! RESTORE FAILED — run /tmp/bunny_sanction_restore.sql BY HAND NOW. Bunny's sanction is still inflated."
}
trap restore_bunny EXIT INT TERM

# ── 2. Bunny is ALREADY over its sanctioned rate, so protection_qualified is already false. Confirm
#       the exemption followed it down, which is the whole point of Step 3. The row count is also
#       the guard against the cartesian join Step 3 warns about: compare bunny_rows against the SAME
#       count captured BEFORE the Step 3 edit — it must be UNCHANGED, never a multiple of it. Do not
#       expect a number written in this file; capture your own baseline.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, daily_investment, spend_per_day, spend_rate_ratio, spend_breached,
        protection_qualified, rate_window_basis
 FROM \`onyga-482313.OI.V_INVEST_STATUS\` WHERE family='Bunny'"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNT(*) AS bunny_rows, COUNTIF(exempt_active) AS bunny_campaigns_still_exempt
 FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\` WHERE family='Bunny'"

# ── 3. Flip it the OTHER way: raise the sanctioned rate above the measured rate and confirm the
#       exemption comes back. Testing only one direction is how the old step passed while measuring
#       nothing. NOTE the key: parent_name, not family.
#
#       THIS IS A MERGE, NOT AN UPDATE, AND THAT IS NOT A STYLE CHOICE. The previous repair wrote
#         UPDATE DE_LAUNCH_INVESTMENT SET daily_investment = (SELECT ... FROM V_INVEST_STATUS ...)
#       which BigQuery rejects outright: "Correlated subqueries that reference other tables are not
#       supported unless they can be de-correlated, such as by transforming them into an efficient
#       JOIN." (Re-confirmed by dry run 2026-08-20 — it is a hard parse-time refusal, so the step
#       could never have run.) A MERGE is that JOIN, it reads the live measurement rather than a
#       literal typed here, and it dry-runs clean. (Run the dry run yourself; the byte figure is a
#       measurement and is deliberately not written into this comment.)
#       The IS NOT NULL guards matter: V_INVEST_STATUS deliberately publishes NO rate when the
#       window has too few loaded ads days (Ori: "when you do not have full window data, do not
#       show calculate"), and a NULL landing in daily_investment would blank a sanctioned number.
#       ── THE EXPOSURE WINDOW OPENS ON THE NEXT LINE AND CLOSES AT ── 4. Keep it to these three
#          calls. Do not add a read, do not go and look at the brief, do not step away.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
"MERGE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` t
 USING (SELECT 'Bunny' AS parent_name, CEIL(MAX(spend_per_day)) + 10 AS test_rate
        FROM \`onyga-482313.OI.V_INVEST_STATUS\`
        WHERE family = 'Bunny' AND spend_per_day IS NOT NULL) s
    ON t.parent_name = s.parent_name
 WHEN MATCHED AND s.test_rate IS NOT NULL THEN UPDATE SET daily_investment = s.test_rate"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, daily_investment, spend_per_day, protection_qualified
 FROM \`onyga-482313.OI.V_INVEST_STATUS\` WHERE family='Bunny'"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t8b_assert.sql)"

# ── 4. RESTORE from the value recorded in step 1. Self-derived, never a literal — and it is the
#       SAME statement the trap holds, so an interrupt anywhere above lands here too. Running it
#       twice is harmless.
#       ── THE EXPOSURE WINDOW CLOSES ON THE NEXT LINE.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(cat /tmp/bunny_sanction_restore.sql)"
trap - EXIT INT TERM

# ── 5. POST-RESTORE ASSERTION — the sanction must read exactly what Ori signed off on 2026-08-13.
#       This is the guard the old step did not have. It must print sanction_intact = true.
#       THE THREE LITERALS BELOW ARE DECLARED CONSTANTS, NOT MEASUREMENTS, AND STANDING RULE 0
#       DELIBERATELY PERMITS THEM TO GATE THIS CHECK. They are true because Ori decided them on
#       2026-08-13; no query can restate them, and nothing but a person may change them. This is the
#       only thing standing between a test that inflates Bunny's sanction and a permanently
#       overwritten number — a "measurements never gate anything" reading that forbade it would
#       delete the guard and leave the exposure window unwatched. Cross-check the literals against
#       the live row BEFORE you run the test (── 1 already reads daily_investment), and if they ever
#       disagree, STOP: either Ori re-sanctioned and this line needs updating in the same commit as
#       the new sanction, or something already overwrote the row.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT parent_name, daily_investment, monthly_loss_ceiling, stop_date,
        (daily_investment = 30.0 AND monthly_loss_ceiling = 913.0 AND stop_date = DATE '2026-10-31') AS sanction_intact
 FROM \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` WHERE parent_name='Bunny'"
```

Expected, in order, **as properties rather than as pinned counts** — read every figure off the
`── 2` output, not off this page (the spend rate written here went stale three times in two days and
the window under it was redefined once):

1. With the sanction at its live, declared $30/day and Bunny's measured rate above it,
   `protection_qualified` reads `false`.
2. `bunny_rows` equals the count you captured BEFORE the Step 3 edit — **unchanged**. A multiple of
   it means the join went in as a cartesian product (Step 3's warning), which no other check in this
   task would catch.
3. `bunny_campaigns_still_exempt` reads `0` — the exemption followed the spend rate down. It equalled
   `bunny_rows` before this task, so anything other than `0` means Step 3's join never took effect.
4. With the sanction temporarily raised above the measured rate, `protection_qualified` reads `true`
   and the assertion returns `exemptions_outliving_their_sanction 0`.
5. After the restore, `sanction_intact` reads `true`.

**If `sanction_intact` is anything but `true`, you have overwritten a number Ori sanctioned. Stop and
put it back: Bunny is $30.00/day, $913.00 monthly backstop, stop date 2026-10-31.**

- [ ] **Step 5: Confirm undeclared families are untouched**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNTIF(NOT exempt_active) AS undeclared_families_revoked
 FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\` e
 WHERE NOT EXISTS (SELECT 1 FROM \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` d
                   WHERE d.parent_name = e.family)"
```
Expected: `0` — fail-open holds. **Note the join: `d.parent_name = e.family`.** The declaration table
is keyed on `parent_name` and the view publishes `family`; writing either name on both sides fails to
compile.

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql
git commit -m "feat: launch exemption expires on the sanctioned spend rate and the declared end date"
```

---

## Task 9: The SOP

> **⚠ BLOCKED — DO NOT RUN UNTIL ORI RULES ON THE OPEN QUESTION BELOW.**
> This task writes `architecture/TWO_BOOK_PNL.md`, a file that does not exist yet and which
> `V_FAMILY_PNL.sql:3` already cites as its SOP. Whatever it says becomes the standing rule, so it
> has to be right on the day it lands. Three of its rules were wrong; two are corrected below, and
> the third is a question only Ori can answer.

### OPEN QUESTION FOR ORI — how many fields make a declaration?

The spec (§5) and the draft SOP both say a family joins the Invest book only with **three**
declaration fields: the monthly loss ceiling, the end date, and the take-over target. The draft SOP
then lists *"adding a family to Invest without all three declaration fields"* as something that
invalidates the design.

**Live production violates that rule on the day it would be published.** Bunny and LolliBall are both
in the Invest book with `takeover_target_organic_units` set to NULL, because Task 2 Step 4 of this
plan explicitly ordered it left NULL until Ori supplies the numbers, and Task 6 Step 4 repeats the
order. Publishing the rule as drafted would make the SOP condemn the only two families the system
actually manages.

Two ways out, and they are genuinely different decisions:

**Option A — two binding fields; the target gates PROOF only.** A declaration is complete with the
sanctioned daily rate and the end date. The take-over target may be added later, and until it exists
a PROOF-phase family reports *"no take-over target set"* instead of a pass or a fail.
*Implies:* today's production is correct and needs nothing. It also means a launch can reach month
three with no definition of success, and the system will say so out loud rather than stopping it. The
worst case is a family that sits in PROOF indefinitely, visibly unjudged.

**Option B — three fields, targets supplied first.** A declaration without a take-over target is not
a declaration, and the family stays in Harvest until Ori sets one.
*Implies:* Bunny and LolliBall drop out of the Invest book the moment this rule is enforced, and are
judged on money like every Harvest family — which is the thing the two-book design was built to stop
happening to a deliberate launch. Ori would have to supply both targets before the rule ships.

**Nothing in the engine changes either way** — `V_BOOK_ASSIGNMENT` already treats a NULL target as
acceptable, so Option A is a documentation change and Option B is a code change plus two numbers from
Ori. Do not pick one. Ask.

> **REPORTED AS RULED, NOT YET CONFIRMED IN THIS REPO (2026-08-20).** The round-3 repair brief carries
> Ori's standing rulings, and among them: *"Two binding declaration fields: sanctioned $/day + end
> date. The take-over organic-units target gates PROOF only; a NULL target does not invalidate a
> declaration."* That is **Option A**, and if it holds, this task's block is lifted and the Option A
> line is the one to publish. It is recorded here rather than acted on because the ruling reached this
> plan second-hand and Task 9 writes a STANDING RULE that will outlive everyone who remembers the
> conversation. **Confirm it with Ori in his own words, then delete this box and the `<<< >>>` marker
> in the heredoc in the same commit.** Do not publish the SOP off this paragraph alone.

### Two rules corrected without asking

Both were factually wrong rather than debatable:

1. **The bar is rebuilt DAILY, not monthly.** The draft says the keyword bar is *"refreshed monthly
   from a settled 90-day window"*. `SP_SNAPSHOT_FAMILY_BAR` runs every day as orchestrator task
   20.5g-1, and `V_FAMILY_BAR.sql` was corrected to say so in `72acbdf`. The 90-day window is
   settled; the refresh cadence is daily. Writing "monthly" into the SOP would have had someone
   hunting for a monthly job that does not exist.
2. **The SOP was silent on which exemption clause binds**, which is the single most important fact in
   the design. It is the **sanctioned daily spend rate**, not the monthly loss ceiling. A rule that
   does not say so invites the next reader to enforce on the ceiling, which is what the design
   already tried and abandoned.

Both corrections are in the heredoc below.

**Files:**
- Create: `architecture/TWO_BOOK_PNL.md`

- [ ] **Step 1: Write the SOP** — only after Ori has ruled on the open question above.

```bash
cat > architecture/TWO_BOOK_PNL.md << 'DOC'
# Two-Book P&L — Harvest and Invest

**Born:** 2026-08-19. **Spec:** `docs/superpowers/specs/2026-08-19-two-book-pnl-design.md`

## Why

Ads were judged on ads-ATTRIBUTED profit, which cannot see the organic units a keyword builds. A
closed month can therefore read as a LOSS on that lens and as a PROFIT on total dollars — same money,
two sentences, and only the second one is true. That is why this design exists. July 2026 was the
month that showed it; reproduce it rather than quoting it:

    SELECT ROUND(SUM(net_profit), 0)                   AS net_profit_including_halo,
           ROUND(SUM(ad_spend * (ads_net_roas - 1)), 0) AS ads_attributed_only
    FROM `onyga-482313.OI.V_FAMILY_PNL` WHERE period_label = '2026-07';

The two columns have opposite signs. The lens, not the business, was the problem.

Two defects followed from it. **The engine optimized the wrong number.** The bar is
`1 / (1 + 0.5 * (halo_factor - 1))`, so THE STRONGER A FAMILY'S HALO, THE LOWER ITS BAR — that is
algebra, not a reading. The families that most need the credit are the ones where `ads_net_roas`
sits far below `total_net_roas` — that gap IS the halo — and a flat 1.0 bar judges precisely those
keywords hardest, cutting the ones carrying the organic sales. Read the two columns side by side and
see how far apart they run:
`SELECT family, book, ads_net_roas, total_net_roas, halo_factor, keyword_bar FROM
onyga-482313.OI.V_FAMILY_BAR ORDER BY keyword_bar`. **Do not write a family name or a ratio into this
sentence** — an earlier version claimed the family with the strongest halo also carried the account's
LOWEST ads-attributed ROAS, and the query printed directly beneath it disagreed. And **deliberate
launch investment was invisible and unbounded** — real money each month to two families with no
ceiling, no end date and no success test, its losses blended into the engine's scorecard.

## The books

| book | membership | judged on |
|---|---|---|
| Harvest | default | net profit; total net ROAS vs 1.0 explains it |
| Invest | live declaration only | sticking to the sanctioned spend rate, plus trajectory (RAMP) or target (PROOF) |

## Objects

`V_FAMILY_PNL` (spine) -> `V_FAMILY_BAR` -> `T_FAMILY_BAR` (what the engines join)
`DE_LAUNCH_INVESTMENT` -> `V_BOOK_ASSIGNMENT` -> `V_INVEST_STATUS` -> `V_TWO_BOOK_BRIEF`

## Standing rules

- **Net profit leads, the ratio explains.** A ratio has no size in it: two families the same distance
  under 1.0 can be a rounding error apart in dollars or thousands apart, because the ratio says
  nothing about how much was spent to get there. Ranked by ratio you may fix the cheap one; ranked by
  dollars you fix the expensive one, and dollars is the right answer. Read both columns together and
  rank on the dollars — `SELECT family, net_profit, ad_spend, total_net_roas FROM
  onyga-482313.OI.V_TWO_BOOK_BRIEF WHERE book='HARVEST' AND row_kind='FAMILY' ORDER BY net_profit`.
  Dollars decide what to work on.
- **The halo factor is MEASURED** (`total_net_roas / ads_net_roas`), never assumed from unit ratios.
- **The bar may only LOWER a threshold**, is floored at 0.60, gives no credit below halo 1.0, and
  reads a settled 90-day window. **It is rebuilt EVERY DAY** by `SP_SNAPSHOT_FAMILY_BAR`,
  orchestrator task 20.5g-1, before the engine `T_` builds. There is no monthly job.
- **The launch exemption binds on the SANCTIONED DAILY SPEND RATE, not on the monthly loss ceiling.**
  `DE_LAUNCH_INVESTMENT.daily_investment` is the number Ori actually sanctioned and it is the clause
  that decides whether an exemption is still live; the end date is the second clause. The monthly
  loss ceiling is a catastrophe backstop sitting behind both, and it almost never fires — for a
  structural reason, not because of what any particular day reads: the ceiling was backfilled as the
  sanctioned SPEND rate monthised, and a launch family with real sales loses far less than it spends,
  so a family can sit deep inside its ceiling while running well over its rate and a ceiling-based
  gate would read it as fully compliant. Enforcing on
  the ceiling is enforcement in name only. **Check it, do not quote it** — the figures that used to
  be written into this line went stale twice, once on their own and once when the rate window under
  them was redefined:
  `SELECT family, daily_investment, spend_per_day, spend_rate_ratio, ceiling_used_pct,
  rate_window_basis, protection_qualified FROM onyga-482313.OI.V_INVEST_STATUS`.
  (Verify every column name against `INFORMATION_SCHEMA.COLUMNS` before you run a query written into
  a document. The version of this line that named `times_over_agreed_rate` and
  `loss_allowance_used_pct_so_far` on `V_TWO_BOOK_BRIEF` did not fail quietly — both columns had been
  renamed away and it failed to compile.)
- **Calibration is a standing test:** a family clearing its keyword bar must clear total net ROAS
  1.0. If that breaks, the credit is wrong.
- **Launches in months 0-3 are judged on IMPROVEMENT, never profitability.** The rule is "no
  improvement two months running", not "still unprofitable".
- **Absolute organic units, never share** — share rises when ads units collapse.
- **Blended measures cut at the ORDERS watermark**, never the ads watermark; an ads-only measure such
  as the sanctioned spend rate cuts at the ads watermark. No window may run to today: the newest ads
  day is materially under-loaded (read the loaded share off `V_ADS_SETTLE_CURVE`, never from a
  percentage typed into a document), and letting it in dilutes a spend rate toward looking compliant.
  Every column here publishes the window it covers so no reader has to guess.
- **When the window is not full, WITHHOLD — never substitute** (Ori: *"when you do not have full
  window data, do not show calculate"*). A different window's answer in the same column is the defect,
  not the fix. The sanctioned rate is a trailing span of complete days precisely so that it is always
  full; if the ads feed stops moving under it, the row says so and protection fails closed.
- **Describe the mechanism, publish the query, never pin a measurement.** A DECLARED CONSTANT — a
  sanctioned $/day, a stop date, the 0.5 credit, the 0.60 floor — may be written down and may gate an
  assertion, because a person decided it and only a person can change it; say where it is declared. A
  MEASUREMENT — a rate, a ratio, a ROAS, a count, a percentage of a ceiling — may not be written
  down at all, and may never gate anything. Publish the query instead, RUN it before publishing, and
  check its output against the sentence beside it and its column names against
  `INFORMATION_SCHEMA.COLUMNS`. Stamping a measurement with an as-of date was tried for a whole round
  and shipped a wrong number under the right date, which looks verified and is worse.
- **Engines join `T_FAMILY_BAR`, never `V_FAMILY_BAR`** — they are at the planner ceiling.

## What invalidates this

- Crediting more than 50% of the halo without evidence. The feedback test: if lowering a family's
  bar does not improve its net profit over the following quarter, the credit was too generous.
- Judging a RAMP-phase launch on profitability.
- Enforcing the launch exemption on the monthly loss ceiling instead of the sanctioned spend rate.
- <<< AWAITING ORI'S RULING — do not publish this line until he answers the open question above.
  Option A: "Adding a family to Invest without a sanctioned daily rate and an end date." (two fields;
  a missing take-over target is reported, not disqualifying.)
  Option B: "Adding a family to Invest without all three declaration fields." (three fields; Bunny
  and LolliBall must be given take-over targets or they leave the Invest book.) >>>
DOC
git add architecture/TWO_BOOK_PNL.md
git commit -m "docs: TWO_BOOK_PNL SOP"
```

---

## Acceptance

Items 1-6 and 10 are **met** — Tasks 1-7 shipped, see the STATUS table at the top of this plan. Items
7-9 belong to Tasks 8 and 8b, which are **on hold**, so the feature is deliberately incomplete and
that is the current intent, not a gap to close.

1. `V_FAMILY_PNL` reproduces the spec §3 baseline (Task 1 assertion, zero mismatches). ✅
2. `V_FAMILY_BAR` passes all five safety and calibration assertions (Task 4), and its re-check alarms
   only on PERMISSIVE disagreements, never conservative ones. ✅
3. `T_FAMILY_BAR` is rebuilt by the orchestrator before the engine `T_` builds (Task 5 Step 7). ✅
   The pass condition is the ORDERING of the two `CALL` positions in the deployed DDL, not their
   offsets — those move whenever the procedure is edited and are deliberately not recorded here.
4. An incomplete launch declaration is refused by the table (Task 2 Step 6). ✅ — but see Task 9's
   open question: "incomplete" currently means a missing rate or end date, and a missing take-over
   target is allowed. Ori has not ruled on whether that is right.
5. A RAMP-phase verdict never mentions profitability (Task 6 assertion). ✅
6. The brief's Harvest total reconciles to its own family rows (Task 7 assertion). ✅
7. ⏸ ON HOLD — Both bid engines still plan, `V_PANEL_OWNERSHIP` still plans, and both engines pull
   twice byte-identically (Task 8 Steps 4 and 7).
8. ⏸ ON HOLD — The flip report shows fewer cuts and **zero new raises** (Task 8 Step 5), and Step 3
   **adds no new CLASS of cut that reaches a bar-exempt campaign** — the arm SET after the edit
   contains nothing the Step 1 capture did not already contain (Task 8 Step 6). *No count of
   bar-exempt cuts gates this item, and none may be written back into it (Standing Rule 0).* This
   item used to pin the bar-exempt cut count at a measured baseline; re-running that query the same
   day, with no code change in between, returned a different count. The population is
   intraday-volatile — `V_KEYWORD_LIFT` recomputes from ads data that is materially under-loaded at
   age 1 and its trim and seat-queue arms judge on pacing and capacity, both of which move through
   the day — while the property is not. Reaching zero
   is explicitly **not** required and would be a failure, not a pass: it would disable the automatic
   daily trim and the seat-queue park on the two Invest families, which are the sanctioned way a
   launch is contained. See the boxed warning in Task 8 Step 6.
9. ⏸ ON HOLD — Spending faster than the sanctioned daily rate, or running past the declared end date,
   revokes the launch exemption; an undeclared family is untouched by it (Task 8b Steps 4 and 5). The
   monthly loss ceiling is not the test.
10. `config.yaml` parses and every new object is registered in the correct section. ✅

## Known follow-ons (NOT in this plan)

- **LolliBall's sub-1.0 halo factor on its early windows** — a COGS imputation artifact. Harmless to
  the RAMP test (a constant bias cancels out of a trend) but must be fixed before LolliBall reaches
  PROOF, because PROOF judges a LEVEL. **NEVER QUOTE A HALO WITHOUT NAMING ITS WINDOW**: this bullet
  used to quote a sub-1.0 figure bare, and that figure was the `BASELINE_MAY_JUL` halo, not the
  settled M3 halo the bar actually reads — which sits on the other side of 1.0. A reviewer
  spot-checking it concluded the no-credit guard was broken when it was not. Compare the two:
  `SELECT period_label, halo_factor FROM onyga-482313.OI.V_FAMILY_PNL WHERE family='LolliBall' AND
  period_label IN ('M3','BASELINE_MAY_JUL')`.
- **Fresh** — the long-standing Harvest family that loses real money every window. This plan makes it
  visible; deciding what to do about it is Ori's, not the engine's. Size it on the day you act, and
  do not quote a figure from this bullet, which has already carried three:
  `SELECT family, net_profit, ad_spend, total_net_roas, money_window FROM
  onyga-482313.OI.V_TWO_BOOK_BRIEF WHERE row_kind='FAMILY' ORDER BY net_profit`.
  (`halo_factor` is NOT a column of the brief — the version of this query that named it failed to
  compile. Check column names against `INFORMATION_SCHEMA.COLUMNS` before publishing a query.)
- **The randomized holdout** — parked, `architecture/HOLDOUT.md`. Its declared trial window opens
  2026-09-01; if it is not repaired before then, formally abandon it rather than let it run invalid.
