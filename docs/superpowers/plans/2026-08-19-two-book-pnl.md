# Two-Book P&L Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Judge advertising on net profit including the organic halo, split into a Harvest book (established families, judged on money) and an Invest book (declared launches, judged on improvement inside a bounded budget).

**Architecture:** Six new BigQuery objects plus two modifications, layered so nothing hot ever inlines a planner-ceiling view. `V_FAMILY_PNL` is the measurement spine (family × period: net profit, total net ROAS, ads net ROAS, measured halo factor). `V_FAMILY_BAR` turns the measured halo into a per-family keyword bar that the bid engines read from a materialized table. `DE_LAUNCH_INVESTMENT` + `V_BOOK_ASSIGNMENT` + `V_INVEST_STATUS` bound the launch investment and judge it on trajectory. Everything is family-grain because organic sales are not attributable to a keyword.

**Tech Stack:** BigQuery Standard SQL (project `onyga-482313`, dataset `OI`), stored procedures for materialization, `config.yaml` as the object registry, `architecture/` for SOPs.

**Spec:** `docs/superpowers/specs/2026-08-19-two-book-pnl-design.md`

---

## Non-negotiable house rules (read before Task 1)

These are not style preferences. Each one exists because breaking it broke production in the last week.

1. **Never inline a planner-ceiling view.** `V_LOW_STOCK_ADS`, `V_KEYWORD_LIFT`, `V_OOB_KEYWORD`, `V_CHANGE_SCORECARD` are individually at BigQuery's planning ceiling. On 2026-08-17 `V_PANEL_OWNERSHIP` stopped planning entirely because it inlined one of them. If a consumer needs ceiling-view data, materialize a slice into a `T_` table inside a procedure and join the TABLE.
2. **Complete-days windows.** `wm` = newest loaded day. The last day stands alone; every multi-day window ends at `wm − 1`. See `feedback_window_convention_complete_days`.
3. **THE BINDING CONSTRAINT IS THE SPEND RATE** (Ori 2026-08-19: *"spend rate binds"*).
   `DE_LAUNCH_INVESTMENT.daily_investment` is the number Ori actually sanctioned ($30/day Bunny,
   $55/day LolliBall) and it is what the exemption must enforce. `monthly_loss_ceiling` is a
   CATASTROPHE BACKSTOP behind it, nothing more. WHY: measured 2026-08-19, both families run at
   1.53x and 1.84x their sanctioned spend while their month-to-date LOSS is only $259 and $74
   against ceilings of $913 and $1,674 — a net-profit ceiling on a product that nearly covers its
   costs never fires. The loss ceiling was the wrong denominator; the spend rate is the decision.
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
something to re-execute.** Every object below was changed after its task was written — by review, by
the orders-watermark ruling, or by a later fix. The authority for what an object contains is the file
in `scripts/bigquery/`, never this document. If a task is marked SHIPPED, read the file; do not
re-deploy the block. Re-running a shipped block silently reverts production, **and the task's own
acceptance assertion will usually still pass**, because those assertions test the shape of the answer
rather than which version produced it. Task 7's assertion is the clearest example: with today's
six-for-six family coverage the original fourteen-column spine reconciles perfectly, so it would
report success while having thrown away three commits of fixes.

| task | object | status | shipped in | the block below is |
|---|---|---|---|---|
| 1 | `V_FAMILY_PNL` | SHIPPED | `92bf0a2`, refined in `a8cb5aa` | **SUPERSEDED** — written before the complete-days ruling |
| 2 | `DE_LAUNCH_INVESTMENT` | SHIPPED | `a8cb5aa` | carries its own correction banner; still accurate |
| 3 | `V_BOOK_ASSIGNMENT` | SHIPPED | `2d54ebb`, refined in `a8cb5aa` | **SUPERSEDED** — read the file |
| 4 | `V_FAMILY_BAR` | SHIPPED | `95265bd`, `097d8d7`, `72acbdf` | **SUPERSEDED** — read the file |
| 5 | `SP_SNAPSHOT_FAMILY_BAR` | SHIPPED | `35b9fa6` | current; only Step 7's ordering check was wrong (fixed) |
| 6 | `V_INVEST_STATUS` | SHIPPED | `7e32ee2`, `72acbdf`, `0e4e568`, `acbf7be` | **SUPERSEDED** — read the file |
| 7 | `V_TWO_BOOK_BRIEF` | SHIPPED | `fa840df`, `9fd1318`, `971751f`, `0a65589`, `a1d27aa`, `acbf7be` | **SUPERSEDED** — read the file |
| 8 | bid engines read the family bar | **ON HOLD** | — | repaired below, deliberately not released |
| 8b | `V_LAUNCH_EXEMPTION` | **ON HOLD** | — | repaired below, deliberately not released |
| 9 | `architecture/TWO_BOOK_PNL.md` | **BLOCKED** | — | one standing rule needs Ori's decision first |

**TWO COLUMNS WERE RENAMED ON 2026-08-20 AND THE SUPERSEDED BLOCKS BELOW STILL SHOW THE OLD NAMES.**
`V_INVEST_STATUS.exemption_live` is now **`protection_qualified`** (one word could not carry both
"what the sanction rules say" and "what the machine is doing") and `mtd_spend_per_day` is now
**`spend_per_day`** ("month to date" is false for the ten days of each month when the window falls
back to the last complete month). Tasks 6 and 7's code blocks are records of what was written on
2026-08-19 and are not updated; Tasks 8 and 8b, which are meant to be RUN, carry the new names.
Confirm against `INFORMATION_SCHEMA.COLUMNS` before writing either name.

### Tasks 8, 8b and 9 are on hold

Ori's ruling, 2026-08-20: *"Tell the truth now, release nothing."* The brief stops claiming an
enforcement that is not happening and shows the gap between sanctioned and actual spend as a number.
**Nothing in the engine changes.** `V_LAUNCH_EXEMPTION`, `V_ADS_COACH` and
`V_COACH_CAMPAIGN_BUDGET` are not to be edited, and none of the ten held decisions may be released.

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

```sql
-- ASSERT: V_FAMILY_PNL reproduces the hand-verified May-Jul 2026 baseline from the spec.
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
-- WHY THIS EXISTS: every bid decision was judged on ads-ATTRIBUTED profit, which excludes 30-40% of
-- units. Measured 2026-08-19: Bottle reads 0.60 on ads net ROAS (a disaster the engine would cut)
-- but 0.95 on TOTAL net ROAS, because its halo factor is 1.59 — the strongest in the account.
-- Cutting Bottle's keywords on the ads number destroys the organic demand carrying it.
--
-- NET PROFIT IS A TRUE NET, NOT A GROSS MARGIN. Verified 2026-08-19: V_UNIFIED_DAILY.cogs is all-in
-- (product $54,155 + inbound shipping $14,337 + FBA pick/pack $45,044 + Amazon referral $38,498
-- over May-Jul), so sales - cogs - ad_cost is after Amazon's fees.
--
-- HALO FACTOR IS MEASURED, NEVER ASSUMED: total_net_roas / ads_net_roas, read straight from dollars.
-- An earlier draft inferred it from unit ratios plus an equal-margin assumption; the measured values
-- range 1.07 (Fresh) to 1.59 (Bottle), which that assumption would have flattened.
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
    description: "Family economics INCLUDING the organic halo (2026-08-19). One row per (family, period): net_profit (total sales - all-in COGS - ad spend, a true net after Amazon fees), total_net_roas (breakeven exactly 1.0), ads_net_roas (what the engine currently sees), and halo_factor = total/ads MEASURED not assumed (range 1.07 Fresh to 1.59 Bottle). Cuts at the ORDERS watermark with the sessions gate, never the ads watermark. Baseline May-Jul 2026: LolliME +$15,406/1.49, Lollibox +$13,537/1.59, Bottle -$203/0.95, Fresh -$1,497/0.88. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md."
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
> when Ori signed it off (2026-08-13 for both), which is months after either launch began. Use the
> same first-sale definition `V_LAUNCH_EXEMPTION` uses, so the two objects can never disagree about
> how old a family is.

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
-- because a net-profit ceiling on a product that nearly covers its costs almost never fires —
-- measured 2026-08-19, both families ran 1.5-1.8x over sanctioned spend while losing only $259 and
-- $74 against ceilings of $913 and $1,674.
--
-- AGE COMES FROM FIRST SALE, NOT FROM THE DECLARATION. sanctioned_on is when Ori signed the
-- investment off (2026-08-13 for both families), months after either launch actually began. Same
-- first-sale definition as V_LAUNCH_EXEMPTION / V_PRODUCT_LAUNCH_MODEL so nothing can disagree.
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
--   · the bar is FLOORED at 0.60 — no halo excuses a catastrophic keyword
--   · where halo_factor < 1.0 NO credit is given and the bar stays 1.0 (LolliBall reads 0.87 today,
--     which is a COGS-imputation artifact, not a real negative halo — see spec §9.1)
--   · INVEST families are exempt entirely; they are governed by budget + trajectory, not by a bar
--
-- WINDOW: the halo is read from V_FAMILY_PNL's settled 90-day period (M3) and this view is
-- materialised MONTHLY by SP_SNAPSHOT_FAMILY_BAR — bids must not chase organic noise day to day.
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
Expected shape (90d window, so values differ slightly from the spec's May–Jul baseline): Lollibox and LolliME bars near 0.84/0.88 with running above them; Fresh bar near 0.97 with running below; Bottle bar near 0.77 with running below.

- [ ] **Step 6: Register in config.yaml and commit**

```bash
git add scripts/bigquery/views/V_FAMILY_BAR.sql config.yaml
git commit -m "feat: V_FAMILY_BAR — measured halo becomes a per-family keyword bar"
```

---

## Task 5: `SP_SNAPSHOT_FAMILY_BAR` — materialize for the engines

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
-- TABLE — six rows — and never the view.
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
Expected: `rows_in_table` = one row per mapped campaign (~106), `null_bars 0`, `null_campaign_ids 0`, `families 6`, `duplicate_campaigns 0`

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
Expected: both non-zero, and `bar_call_pos` less than `ownership_call_pos`.
Measured 2026-08-20 on the deployed procedure: `92024` and `94784` — correctly ordered.

**Search for the CALL, never the bare procedure name.** An earlier version of this check searched the
DDL for `SP_SNAPSHOT_FAMILY_BAR` and `SP_SNAPSHOT_PANEL_OWNERSHIP` on their own. Both names also
appear inside comments elsewhere in the procedure, and `STRPOS` returns the FIRST occurrence, so the
check compared a comment against a comment and reported `91889` against `83540` — a mis-ordering that
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
> Live in `7e32ee2`, then corrected in `72acbdf` and `0e4e568`. The block below breaks house rule 2
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
-- looks like success and is not. Bunny and LolliBall already sit at ~31% organic, comparable to
-- Lollibox's 29.7%, so by share alone they would read "finished" while still losing $2,892/month.
--
-- A USEFUL CONSEQUENCE: trajectory is robust to a level bias. A constant COGS misallocation cancels
-- out of a month-over-month trend, which is why LolliBall's implausible 0.87 halo (spec §9.1) does
-- not block the ramp test — though it must be fixed before LolliBall reaches PROOF.
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
-- daily_investment is the number Ori actually sanctioned ($30/day Bunny, $55/day LolliBall). The
-- net-profit ceiling is computed too, but only as a catastrophe backstop: measured 2026-08-19 both
-- families ran 1.5-1.8x over sanctioned SPEND while their month-to-date LOSS was just $259 and $74
-- against ceilings of $913 and $1,674 — a loss ceiling on a product that nearly covers its costs
-- never fires. Enforcing on it would have been enforcement in name only.
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
Expected: Bunny in `PROOF` (first sale 2026-05-24, so ~3 months) with a verdict naming organic units against the 400 target. If `launch_age_months` reads 3 it will be RAMP — either is correct depending on the run date; what must not happen is a RAMP verdict mentioning profitability.

- [ ] **Step 6: Register in config.yaml and commit**

```bash
git add scripts/bigquery/views/V_INVEST_STATUS.sql config.yaml
git commit -m "feat: V_INVEST_STATUS — bounded budget, ramp trajectory, proof against target"
```

---

## Task 7: `V_TWO_BOOK_BRIEF` — the morning read

> **⚠ SHIPPED — THE CODE BLOCK BELOW IS SUPERSEDED. RE-DEPLOYING IT WOULD LOSE THREE COMMITS OF
> FIXES, AND STEP 4'S ASSERTION WOULD STILL SAY IT PASSED.**
> Live in `fa840df`, then `9fd1318`, `971751f` and `0a65589`. The block below publishes fourteen
> columns off a LEFT JOIN spine; the deployed view publishes thirty-five off a FULL OUTER JOIN of the
> two family universes, so a declared family with no measured P&L still appears instead of vanishing
> from the brief. It also carries the enforcement-gap dollars that the 2026-08-20 ruling required.
> The Step 4 assertion cannot protect you here: it checks that the Harvest total reconciles to the
> Harvest family rows, and with today's six-for-six family coverage the old spine reconciles
> perfectly, so it would report a clean pass over a reverted view. Read
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
-- THE POINT OF THE WHOLE DESIGN IS THIS ONE SENTENCE. July 2026 read as "the account lost $5,612",
-- which was never true: it was Harvest earning money while a deliberate, undeclared launch
-- investment spent it, and an ads-attributed lens that excluded 30-40% of units. The brief reports
-- "Harvest earned X; Invest spent Y of its declared budget" and never adds those two together.
--
-- NET PROFIT LEADS, THE RATIO EXPLAINS IT (Ori's framing is total dollars). Bottle at 0.95 and Fresh
-- at 0.88 look like the same problem by ratio, but cost $203 and $1,497 — ranked by ratio you fix
-- Bottle, ranked by dollars you fix Fresh, and Fresh is the right answer.
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
> lifted; every statement written into them was dry-run against live BigQuery on 2026-08-20. They
> are a repair, not a permission.

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
-- drives organic sales. The worked example, MEASURED ON THE SETTLED 90 DAYS TO 2026-08-17 AND
-- RE-READ 2026-08-20: Bottle reads 0.6339 on ads-attributed net ROAS and 0.9980 on total net ROAS,
-- a halo of 1.5744, which sets its bar at 0.7769 — under the old flat 1.0 bar the engine would cut
-- the very keywords carrying it. THESE FOUR NUMBERS ARE A DATED READING, NOT CONSTANTS: they move
-- with every rebuild of the settled window, Bottle's total sits 0.2% under 1.000 and will cross it
-- on a routine restatement, and this comment must not be read as a threshold. Pull
-- V_FAMILY_PNL WHERE period_label = 'M3' and V_FAMILY_BAR for today's. Reads the TABLE, never
-- V_FAMILY_BAR:
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

Expected direction: **fewer cuts**, concentrated in high-halo families (Bottle, halo 1.59, bar 0.77). Zero new raises — the bar can only lower a cut threshold, never manufacture a raise. Any new raise means the predicate was inverted somewhere; find it before proceeding.

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

> **⚠ THE OLD GATE WAS A PINNED COUNT AND COULD NOT HOLD. DO NOT PUT ONE BACK.** It read: *"Baseline
> measured 2026-08-20: four rows — `AUTO_DAY_TRIM` LolliBall 2, `AUTO_DAY_TRIM` Bunny 1, `PARK`
> Bunny 1. This task must leave that count at four."* Re-running that exact query later **the same
> day**, with no code change of any kind in between, returned **one row — `AUTO_DAY_TRIM` LolliBall
> 2.** `V_KEYWORD_LIFT` recomputes from ads data that is 88-90% loaded at age 1 and restates for
> about D+3 (`fact_oi_ads_restatement_settle`), and the daily-trim and seat-queue arms judge on
> pacing and capacity, both of which move through the day. So the count is INTRADAY-VOLATILE and no
> fixed value can gate anything: pinned at four it fails on a morning when nothing is wrong, and a
> gate that cries wolf gets waved through — which is worse than no gate, because the next person
> reads a red check as normal. **Gate the PROPERTY, not the population.** The property is "Step 3
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
> **The "safe to execute" claim above is now backed, and it was not before (2026-08-20).** The
> previous round wrote that sentence while the task still contained a statement BigQuery refuses to
> compile, a join that silently produces a cartesian product, and four references to two columns
> that had been renamed upstream the same day — so the banner was itself a false claim. **Every SQL
> statement in this task has now been dry-run or executed against live BigQuery on 2026-08-20**, and
> the two renames are carried through: `V_INVEST_STATUS.exemption_live` is **`protection_qualified`**
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

Measured 2026-08-20: it **validates**, 72.3 MB upper bound. That is a query-time check on the joined
SELECT, not proof that the same join survives inside the view definition, so run it again against the
edited file before you deploy.

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

Expected today: a **non-zero** count. **Re-measured 2026-08-20 with the renamed column it returns
`14` over 14 joined rows.** Bunny runs at $48.35/day against a sanctioned $30 (1.61x) and LolliBall
at $106.90 against $55 (1.94x), so `protection_qualified` is
already `false` for both — while `exempt_active` is hardcoded `TRUE`, so all fourteen of their
campaigns (Bunny 6, LolliBall 8) hold an exemption that has outlived its sanction. That is the
defect, stated as a number. When this task runs, that 14 must become 0.

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
  -- clock. The pre-2026-08-19 exemption was open-ended, which is how ~$5,400/month reached Bunny and
  -- LolliBall undeclared and unbounded. A family with a live declaration keeps its exemption only
  -- while it is inside its declared window AND spending at or under the daily rate Ori sanctioned
  -- ($30/day Bunny, $55/day LolliBall). THE SPEND RATE IS THE BINDING CLAUSE, not the monthly loss
  -- ceiling: measured 2026-08-19 both families ran 1.5-1.8x over sanctioned spend while their
  -- month-to-date loss was only $259 and $74 against ceilings of $913 and $1,674 — a net-profit
  -- ceiling on a product that nearly covers its costs never fires, so enforcing on it would have
  -- been enforcement in name only. The ceiling stays as a catastrophe backstop behind the rate.
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
> cross join. Re-derived 2026-08-20 on a two-row stand-in for `rolled`: `ON inv.family = family`
> returned **4 rows**, `ON inv.family = rolled.parent_name` returned **2**. At full size that is
> every launch campaign duplicated once per declared family, each copy taking an arbitrary family's
> protection state — a wrong answer that compiles, deploys and looks healthy. Confirm both names
> before you type either:

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
the cartesian form validates too. Also run the row-count check in Step 4 item 2 and confirm the view
still returns 14 launch-campaign rows, not 28.

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
> so breaching it proves nothing: measured 2026-08-20 Bunny sits at $203.78 of loss against $913 and
> is nowhere near it, while it is 1.61x over its sanctioned spend rate. The rate is what to test.

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql)"

# ── 1. RECORD the live sanction. This value, and nothing else, is what the restore writes back.
BUNNY_RATE=$(bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT FORMAT('%.4f', daily_investment) FROM \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` WHERE parent_name='Bunny'" | tail -1)
echo "Bunny's live sanctioned daily investment is $BUNNY_RATE — the restore writes back exactly this."
case "$BUNNY_RATE" in ''|*[!0-9.]*) echo "ABORT: could not read the live sanction. Do not touch the row."; exit 1;; esac

# ── 2. Bunny is ALREADY over its sanctioned rate, so protection_qualified is already false. Confirm
#       the exemption followed it down, which is the whole point of Step 3. The row count is also
#       the guard against the cartesian join Step 3 warns about: 6, never 12.
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
#       literal typed here, and it dry-runs clean (validated 2026-08-20, 72,062,793 bytes).
#       The IS NOT NULL guards matter: V_INVEST_STATUS deliberately publishes NO rate when the
#       window has too few loaded ads days (Ori: "when you do not have full window data, do not
#       show calculate"), and a NULL landing in daily_investment would blank a sanctioned number.
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

# ── 4. RESTORE from the value recorded in step 1. Self-derived, never a literal.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
"UPDATE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` SET daily_investment = $BUNNY_RATE WHERE parent_name='Bunny'"

# ── 5. POST-RESTORE ASSERTION — the sanction must read exactly what Ori signed off on 2026-08-13.
#       This is the guard the old step did not have. It must print sanction_intact = true.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT parent_name, daily_investment, monthly_loss_ceiling, stop_date,
        (daily_investment = 30.0 AND monthly_loss_ceiling = 913.0 AND stop_date = DATE '2026-10-31') AS sanction_intact
 FROM \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` WHERE parent_name='Bunny'"
```

Expected, in order: with the sanction at $30/day and Bunny measured at $48.35,
`protection_qualified` reads `false`, `bunny_rows` reads `6` and `bunny_campaigns_still_exempt` reads
`0` — the exemption followed the spend rate down. `bunny_campaigns_still_exempt` read `6` before this
task, so a `6` here means Step 3's join never took effect; and `bunny_rows` above `6` means the join
went in as a cartesian product (Step 3's warning), which no other check in this task would catch.
With the sanction temporarily raised above the measured rate, `protection_qualified` reads `true` and
the assertion returns `exemptions_outliving_their_sanction 0`. After the restore, `sanction_intact`
must read `true`.

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

Ads were judged on ads-ATTRIBUTED profit, which excludes 30-40% of units. Measured 2026-08-19:
July read -$5,612 on that lens and **+$3,682 including the organic halo**. The lens, not the
business, was the problem.

Two defects followed from it. **The engine optimized the wrong number** — Bottle reads 0.60 on ads
net ROAS but 0.95 on total, halo 1.59, so a flat 1.0 bar would cut the keywords carrying it. And
**deliberate launch investment was invisible and unbounded** — ~$5,400/month to Bunny and LolliBall
with no ceiling, no end date and no success test, its losses blended into the engine's scorecard.

## The books

| book | membership | judged on |
|---|---|---|
| Harvest | default | net profit; total net ROAS vs 1.0 explains it |
| Invest | live declaration only | sticking to the sanctioned spend rate, plus trajectory (RAMP) or target (PROOF) |

## Objects

`V_FAMILY_PNL` (spine) -> `V_FAMILY_BAR` -> `T_FAMILY_BAR` (what the engines join)
`DE_LAUNCH_INVESTMENT` -> `V_BOOK_ASSIGNMENT` -> `V_INVEST_STATUS` -> `V_TWO_BOOK_BRIEF`

## Standing rules

- **Net profit leads, the ratio explains.** Bottle (0.95) and Fresh (0.88) rank identically by
  ratio and 7x apart in dollars. Dollars decide what to work on.
- **The halo factor is MEASURED** (`total_net_roas / ads_net_roas`), never assumed from unit ratios.
- **The bar may only LOWER a threshold**, is floored at 0.60, gives no credit below halo 1.0, and
  reads a settled 90-day window. **It is rebuilt EVERY DAY** by `SP_SNAPSHOT_FAMILY_BAR`,
  orchestrator task 20.5g-1, before the engine `T_` builds. There is no monthly job.
- **The launch exemption binds on the SANCTIONED DAILY SPEND RATE, not on the monthly loss ceiling.**
  `DE_LAUNCH_INVESTMENT.daily_investment` is the number Ori actually sanctioned and it is the clause
  that decides whether an exemption is still live; the end date is the second clause. The monthly
  loss ceiling is a catastrophe backstop sitting behind both, and it almost never fires: measured
  2026-08-19, Bunny and LolliBall ran at 1.6x and 1.9x their sanctioned spend while losing only $204
  and $15 against ceilings of $913 and $1,674. Enforcing on the ceiling is enforcement in name only.
- **Calibration is a standing test:** a family clearing its keyword bar must clear total net ROAS
  1.0. If that breaks, the credit is wrong.
- **Launches in months 0-3 are judged on IMPROVEMENT, never profitability.** The rule is "no
  improvement two months running", not "still unprofitable".
- **Absolute organic units, never share** — share rises when ads units collapse.
- **Blended measures cut at the ORDERS watermark**, never the ads watermark; an ads-only measure such
  as the month-to-date spend rate cuts at the ads watermark. No window may run to today: the newest
  day is only 88-90% loaded, and letting it in dilutes a spend rate toward looking compliant. Every
  column here publishes the window it covers so no reader has to guess.
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
   Verified 2026-08-20: the `CALL` positions in the deployed procedure read 92024 against 94784.
4. An incomplete launch declaration is refused by the table (Task 2 Step 6). ✅ — but see Task 9's
   open question: "incomplete" currently means a missing rate or end date, and a missing take-over
   target is allowed. Ori has not ruled on whether that is right.
5. A RAMP-phase verdict never mentions profitability (Task 6 assertion). ✅
6. The brief's Harvest total reconciles to its own family rows (Task 7 assertion). ✅
7. ⏸ ON HOLD — Both bid engines still plan, `V_PANEL_OWNERSHIP` still plans, and both engines pull
   twice byte-identically (Task 8 Steps 4 and 7).
8. ⏸ ON HOLD — The flip report shows fewer cuts and **zero new raises** (Task 8 Step 5). The
   bar-exempt cut count stays at its measured baseline of four; it is not required to reach zero, and
   forcing it to zero would disable the automatic daily trim and the seat-queue park on the two
   Invest families (Task 8 Step 6).
9. ⏸ ON HOLD — Spending faster than the sanctioned daily rate, or running past the declared end date,
   revokes the launch exemption; an undeclared family is untouched by it (Task 8b Steps 4 and 5). The
   monthly loss ceiling is not the test.
10. `config.yaml` parses and every new object is registered in the correct section. ✅

## Known follow-ons (NOT in this plan)

- **LolliBall's 0.87 halo factor** — a COGS imputation artifact. Harmless to the RAMP test (a
  constant bias cancels out of a trend) but must be fixed before LolliBall reaches PROOF.
- **Fresh** — 24 months old, halo 1.07, losing $1,497. This plan makes it visible; deciding what to
  do about it is Ori's, not the engine's.
- **The randomized holdout** — parked, `architecture/HOLDOUT.md`. If not repaired before its
  2026-09-01 window opens, formally abandon it rather than let it run invalid.
