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
3. **Blended (sales + ads) measures cut at the ORDERS watermark, never the ads watermark** — ads rows run ~1 day ahead of the business report. Copy the `wm` CTE from `V_FAMILY_NET_PROFIT_7D.sql` verbatim (shown in Task 1).
4. **Deploy battery, every object, every time:** back up → deploy → before/after flip report → pull-twice determinism.
5. **`config.yaml` parses today. NEVER append entries to the end of the file** — the tail is inside the `monitoring:` mapping and appending there broke the parse on 2026-08-17. Insert into the `views:` or `tables:` list, then verify with PyYAML.
6. **Deploy command:** `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"`. Header lines starting `--` at column 0 are stripped at deploy, so header comments are repo-only.
7. **Never pipe SQL through plain `cat`.** Any file beginning with `--` makes bq abort with
   *"FATAL Flags parsing error: Unknown command line flag"* — it reads the comment as a flag. Every
   assertion file in this plan starts with a `--` comment, so **always** use `grep -v '^--' FILE`,
   exactly as the deploy command does. (Found the hard way in Task 1.)

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
  COUNT(*)                                                        AS families
FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`;
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t3_assert.sql)"
```
Expected: `Not found: Table onyga-482313:OI.V_BOOK_ASSIGNMENT`

- [ ] **Step 3: Write the view**

Create `scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql`:

```sql
-- =============================================
-- V_BOOK_ASSIGNMENT — which book each family is in (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §2.
--
-- HARVEST IS THE DEFAULT AND THAT IS THE POINT. A family becomes INVEST only through a complete,
-- in-window declaration in DE_LAUNCH_INVESTMENT. Undeclared spend is Harvest spend and is judged on
-- money like everything else — which is what makes an undeclared launch immediately visible instead
-- of quietly exempt.
--
-- A declaration is VALID only while today is inside [start_date, end_date]. Expiry needs no code
-- change and no cleanup: the family simply reverts to Harvest the day after end_date.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BOOK_ASSIGNMENT` AS
WITH fam AS (
  SELECT DISTINCT parent_name AS family
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`
  WHERE parent_name IS NOT NULL
),
decl AS (
  SELECT family, monthly_loss_ceiling, start_date, end_date, takeover_target_organic_units,
         (CURRENT_DATE('America/Los_Angeles') BETWEEN start_date AND end_date) AS in_window
  FROM `onyga-482313.OI.DE_LAUNCH_INVESTMENT`
  -- one live declaration per family; the newest start_date wins if two overlap
  QUALIFY ROW_NUMBER() OVER (PARTITION BY family ORDER BY start_date DESC) = 1
)
SELECT
  f.family,
  IF(COALESCE(d.in_window, FALSE), 'INVEST', 'HARVEST')                       AS book,
  COALESCE(d.in_window, FALSE)                                               AS declaration_valid,
  d.monthly_loss_ceiling,
  d.start_date,
  d.end_date,
  d.takeover_target_organic_units,
  -- months since the launch started, which selects the RAMP vs PROOF test in V_INVEST_STATUS
  IF(d.start_date IS NULL, NULL,
     DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), d.start_date, MONTH))    AS launch_age_months
FROM fam f
LEFT JOIN decl d ON d.family = f.family;
```

- [ ] **Step 4: Deploy and assert**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t3_assert.sql)"
```
Expected deploy: `Created onyga-482313.OI.V_BOOK_ASSIGNMENT`
Expected assert: `bad_book_values 0, invest_without_declaration 0, null_families 0, families 6`

All six families read HARVEST at this point — nothing is declared yet. That is correct.

- [ ] **Step 5: Register in config.yaml (views: list, same insertion helper as Task 1 Step 7) and commit**

```bash
git add scripts/bigquery/views/V_BOOK_ASSIGNMENT.sql config.yaml
git commit -m "feat: V_BOOK_ASSIGNMENT — Harvest by default, Invest only by live declaration"
```

---

## Task 4: `V_FAMILY_BAR` — the engine bridge

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
bq query --project_id=onyga-482313 --use_legacy_sql=false --format=csv \
"SELECT STRPOS(ddl,'SP_SNAPSHOT_FAMILY_BAR') AS bar_pos,
        STRPOS(ddl,'SP_SNAPSHOT_PANEL_OWNERSHIP') AS ownership_pos
 FROM \`onyga-482313.OI\`.INFORMATION_SCHEMA.ROUTINES
 WHERE routine_name='SP_ORCHESTRATE_DAILY_REFRESH'"
```
Expected: `bar_pos` less than `ownership_pos`, and both non-zero.

- [ ] **Step 8: Register T_FAMILY_BAR in config.yaml (tables:) and commit**

```bash
git add scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql \
        scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql config.yaml
git commit -m "feat: SP_SNAPSHOT_FAMILY_BAR — materialize the bars so engines never inline the view"
```

---

## Task 6: `V_INVEST_STATUS` — budget, ramp and proof

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
  COUNTIF(ceiling_breached AND exemption_live)                          AS breach_still_exempt
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
-- month-to-date net profit against the declared ceiling (ceiling is denominated in NET PROFIT)
mtd AS (
  SELECT u.family, ROUND(SUM(u.sales - u.cogs) - SUM(u.ad_cost), 2) AS mtd_net_profit
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  WHERE u.date >= DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)
  GROUP BY 1
)
SELECT
  b.family,
  b.launch_age_months,
  IF(b.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  b.monthly_loss_ceiling,
  COALESCE(mtd.mtd_net_profit, 0)                                                     AS mtd_net_profit,
  ROUND(100 * SAFE_DIVIDE(-COALESCE(mtd.mtd_net_profit, 0), NULLIF(b.monthly_loss_ceiling, 0)), 1) AS ceiling_used_pct,
  (-COALESCE(mtd.mtd_net_profit, 0) >= b.monthly_loss_ceiling)                        AS ceiling_breached,
  b.end_date,
  DATE_DIFF(b.end_date, CURRENT_DATE('America/Los_Angeles'), DAY)                     AS days_left,
  -- THE EXEMPTION: live only while inside the window AND under the ceiling. The engine stops, not the human.
  (CURRENT_DATE('America/Los_Angeles') <= b.end_date
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
        WHEN t.org_m0 >= b.takeover_target_organic_units
          THEN CONCAT('took over — ', CAST(t.org_m0 AS STRING), ' organic units against a target of ', CAST(b.takeover_target_organic_units AS STRING))
        ELSE CONCAT('short of target — ', CAST(t.org_m0 AS STRING), ' of ', CAST(b.takeover_target_organic_units AS STRING), ' organic units, ',
                    CAST(DATE_DIFF(b.end_date, CURRENT_DATE('America/Los_Angeles'), DAY) AS STRING), ' days left')
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
-- drives organic sales. Bottle reads 0.60 on ads and 0.95 on total (halo 1.59) — under the old flat
-- 1.0 bar the engine would cut the very keywords carrying it. Reads the TABLE, never V_FAMILY_BAR:
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

- [ ] **Step 6: Confirm no cut survives against its own family bar**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNT(*) AS cuts_below_bar
 FROM \`onyga-482313.OI.V_KEYWORD_LIFT\` l
 JOIN \`onyga-482313.OI.T_FAMILY_BAR\` b ON b.campaign_id = CAST(l.campaign_id AS STRING)
 WHERE l.suggested_bid < l.current_bid AND b.bar_exempt"
```
Expected: `0` — Invest families are exempt from the bar and must not be cut by it.

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

## Task 8b: `V_LAUNCH_EXEMPTION` — the exemption expires on money and time

Spec §5 requires the launch exemption to become conditional. Without this task the ceiling and end
date are reported by `V_INVEST_STATUS` and enforced by nobody — which is the exact defect the whole
design exists to fix.

**Files:**
- Modify: `scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql`

- [ ] **Step 1: Write the failing assertion**

Save as `/tmp/t8b_assert.sql`:

```sql
-- ASSERT: no family may hold a live exemption while its declared ceiling is breached or its end
-- date has passed. Families with no declaration are unaffected (fail-open).
SELECT COUNTIF(e.exempt_active AND NOT i.exemption_live) AS exemptions_outliving_their_budget
FROM `onyga-482313.OI.V_LAUNCH_EXEMPTION` e
JOIN `onyga-482313.OI.V_INVEST_STATUS` i ON i.family = e.parent_name;
```

- [ ] **Step 2: Run it and confirm it fails (or returns 0 only because nothing is declared yet)**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t8b_assert.sql)"
```
If Task 6 inserted Bunny's declaration and Bunny is inside its window and under ceiling, this may
already read `0`. That is a weak pass — Step 4 forces the real test.

- [ ] **Step 3: Add the budget-and-clock condition**

`V_LAUNCH_EXEMPTION.sql` line 235 currently hardcodes the exemption as live:

```sql
  TRUE                              AS exempt_active,   -- camp already filters today <= exempt_until
```

Replace it so a declared family must also be inside its budget and its declared window. Undeclared
families keep exactly today's behaviour — the condition can only ever REVOKE an exemption, never
grant one:

```sql
  -- v27.84 (2026-08-19, two-book P&L §5): an exemption now expires on MONEY as well as time. The
  -- pre-2026-08-19 exemption was open-ended, which is how ~$5,400/month reached Bunny and LolliBall
  -- undeclared and unbounded. A family with a live declaration keeps its exemption only while it is
  -- inside its window AND under its monthly NET PROFIT ceiling; when either fails the family reverts
  -- to Harvest rules and its halo-adjusted bar applies. FAIL-OPEN: a family with no declaration row
  -- is untouched, so this can only ever revoke, never grant.
  COALESCE(inv.exemption_live, TRUE) AS exempt_active,
```

and add to the final SELECT's FROM chain:

```sql
LEFT JOIN `onyga-482313.OI.V_INVEST_STATUS` inv ON inv.family = <the outer query's family column>
```

Find that column with:

```bash
grep -n "parent_name\|family" scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql | tail -6
```

- [ ] **Step 4: Deploy, then force the real test by breaching the ceiling**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql)"

# temporarily set Bunny's ceiling to $1 so it is certainly breached
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
"UPDATE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` SET monthly_loss_ceiling = 1.0 WHERE family='Bunny'"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT family, exemption_live, ceiling_used_pct FROM \`onyga-482313.OI.V_INVEST_STATUS\` WHERE family='Bunny'"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' /tmp/t8b_assert.sql)"

# restore
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
"UPDATE \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` SET monthly_loss_ceiling = 2500.0 WHERE family='Bunny'"
```
Expected: with the $1 ceiling, `exemption_live` reads `false` and the assertion still returns
`exemptions_outliving_their_budget 0` — i.e. the exemption followed the budget. Then confirm it
returns to `true` after the restore.

- [ ] **Step 5: Confirm undeclared families are untouched**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNTIF(NOT exempt_active) AS undeclared_families_revoked
 FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\` e
 WHERE NOT EXISTS (SELECT 1 FROM \`onyga-482313.OI.DE_LAUNCH_INVESTMENT\` d WHERE d.family = e.parent_name)"
```
Expected: `0` — fail-open holds.

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/views/V_LAUNCH_EXEMPTION.sql
git commit -m "feat: launch exemption expires on the declared ceiling and end date"
```

---

## Task 9: The SOP

**Files:**
- Create: `architecture/TWO_BOOK_PNL.md`

- [ ] **Step 1: Write the SOP**

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
| Invest | live declaration only | budget adherence + trajectory (RAMP) or target (PROOF) |

## Objects

`V_FAMILY_PNL` (spine) -> `V_FAMILY_BAR` -> `T_FAMILY_BAR` (what the engines join)
`DE_LAUNCH_INVESTMENT` -> `V_BOOK_ASSIGNMENT` -> `V_INVEST_STATUS` -> `V_TWO_BOOK_BRIEF`

## Standing rules

- **Net profit leads, the ratio explains.** Bottle (0.95) and Fresh (0.88) rank identically by
  ratio and 7x apart in dollars. Dollars decide what to work on.
- **The halo factor is MEASURED** (`total_net_roas / ads_net_roas`), never assumed from unit ratios.
- **The bar may only LOWER a threshold**, is floored at 0.60, gives no credit below halo 1.0, and is
  refreshed monthly from a settled 90-day window.
- **Calibration is a standing test:** a family clearing its keyword bar must clear total net ROAS
  1.0. If that breaks, the credit is wrong.
- **Launches in months 0-3 are judged on IMPROVEMENT, never profitability.** The rule is "no
  improvement two months running", not "still unprofitable".
- **Absolute organic units, never share** — share rises when ads units collapse.
- **Blended measures cut at the ORDERS watermark**, never the ads watermark.
- **Engines join `T_FAMILY_BAR`, never `V_FAMILY_BAR`** — they are at the planner ceiling.

## What invalidates this

- Crediting more than 50% of the halo without evidence. The feedback test: if lowering a family's
  bar does not improve its net profit over the following quarter, the credit was too generous.
- Judging a RAMP-phase launch on profitability.
- Adding a family to Invest without all three declaration fields.
DOC
git add architecture/TWO_BOOK_PNL.md
git commit -m "docs: TWO_BOOK_PNL SOP"
```

---

## Acceptance

The feature is done when all of these hold:

1. `V_FAMILY_PNL` reproduces the spec §3 baseline (Task 1 assertion, zero mismatches).
2. `V_FAMILY_BAR` passes all five safety and calibration assertions (Task 4).
3. `T_FAMILY_BAR` is rebuilt by the orchestrator before the engine `T_` builds (Task 5 Step 7).
4. An incomplete launch declaration is refused by the table (Task 2 Step 6).
5. A RAMP-phase verdict never mentions profitability (Task 6 assertion).
6. The brief's Harvest total reconciles to its own family rows (Task 7 assertion).
7. Both bid engines still plan, `V_PANEL_OWNERSHIP` still plans, and both engines pull twice
   byte-identically (Task 8 Steps 4 and 7).
8. The flip report shows fewer cuts and **zero new raises** (Task 8 Step 5).
9. A breached ceiling revokes the launch exemption, and an undeclared family is untouched by it
   (Task 8b Steps 4 and 5).
10. `config.yaml` parses and every new object is registered in the correct section.

## Known follow-ons (NOT in this plan)

- **LolliBall's 0.87 halo factor** — a COGS imputation artifact. Harmless to the RAMP test (a
  constant bias cancels out of a trend) but must be fixed before LolliBall reaches PROOF.
- **Fresh** — 24 months old, halo 1.07, losing $1,497. This plan makes it visible; deciding what to
  do about it is Ori's, not the engine's.
- **The randomized holdout** — parked, `architecture/HOLDOUT.md`. If not repaired before its
  2026-09-01 window opens, formally abandon it rather than let it run invalid.
