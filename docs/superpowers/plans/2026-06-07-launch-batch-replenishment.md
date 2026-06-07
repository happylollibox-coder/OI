# Mechanism B — Launch Batch Replenishment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `V_PLAN_FORECAST` feed the replenishment engine a *launch-aware* demand for just-launched products — their own early run-rate over a widening window, capped to lead + 1 month — so the engine orders small gradual batches off early sales instead of committing a full-year/Q4 plan to an unproven SKU.

**Architecture:** One change to the BigQuery view `V_PLAN_FORECAST` only. Add a `launch_signal` CTE (first-sale date, `is_launching`, own run-rate) and, for `is_launching` rows in the final SELECT, override the demand columns the downstream `SP_GENERATE_SHIPMENT_PLAN` reads. The SP, the 4 batch types, the daily refresh, and all React are unchanged — they consume the corrected demand and stage batches as today.

**Tech Stack:** BigQuery Standard SQL. Validation via `bq query` (read-only ad-hoc runs of the modified SQL — the production view is NOT replaced until the final gated task). `bq` CLI authenticated to project `onyga-482313`.

**PRODUCTION-SAFETY RULES (read before starting):**
- The actual `CREATE OR REPLACE VIEW` + `CALL SP_GENERATE_SHIPMENT_PLAN()` change real PO suggestions. **Tasks 1–4 do NOT touch the production view** (they edit the `.sql` file and validate by running the SQL as an ad-hoc read-only `SELECT`). **Task 5 (deploy + SP re-run) is GATED — do it only after explicit user confirmation.**
- Per CLAUDE.md: register the view change in `config.yaml`; never run destructive SQL without confirmation.
- Use `bq query --use_legacy_sql=false --project_id=onyga-482313 --dry_run` for syntax and a non-dry-run `SELECT … LIMIT` for sample rows.

---

## File Structure

- `scripts/bigquery/views/V_PLAN_FORECAST.sql` — **modify**: add the `launch_signal` CTE; wrap the launch-affected output columns in `CASE WHEN ls.is_launching …`. Single file.
- `config.yaml` — **touch**: confirm/refresh the `V_PLAN_FORECAST` registration (it already exists; note the definition change).

There is no automated SQL test harness in this repo, so "tests" are **read-only ad-hoc `bq` runs of the modified view SQL** comparing a launching product (Bunny) against an established one (LolliME/Lollibox), plus a `--dry_run` syntax gate. This is the established pattern for view changes here.

---

## Task 1: Add the `launch_signal` CTE

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_FORECAST.sql`

- [ ] **Step 1: Insert the CTE.** Add this CTE immediately AFTER the existing `daily_rates AS ( … ),` block (it ends at the line `),` right before `-- 8. Inventory snapshot (latest date)`). Paste the new CTE there:

```sql
-- 7b. Launch signal: first-sale date, is_launching (<= 60d), and own early run-rate.
-- For just-launched products the engine should order off their OWN trailing sales (widening
-- window MIN(days_since_launch, 30)), not the model forecast. >=3 selling days required before a
-- rate is trusted (else 0 — the manual seed PO covers days 0-N).
launch_signal AS (
  SELECT
    dp.product_short_name AS product,
    fs.first_sale_date,
    DATE_DIFF(lld.last_date, fs.first_sale_date, DAY) AS days_since_launch,
    LEAST(GREATEST(DATE_DIFF(lld.last_date, fs.first_sale_date, DAY), 1), 30) AS launch_window_days,
    COALESCE(lw.launch_selling_days, 0) AS launch_selling_days,
    CASE
      WHEN COALESCE(lw.launch_selling_days, 0) >= 3
      THEN COALESCE(lw.launch_units, 0)
           / LEAST(GREATEST(DATE_DIFF(lld.last_date, fs.first_sale_date, DAY), 1), 30)
      ELSE 0
    END AS launch_daily_rate,
    (fs.first_sale_date IS NOT NULL
      AND DATE_DIFF(lld.last_date, fs.first_sale_date, DAY) BETWEEN 0 AND 60) AS is_launching
  FROM `onyga-482313.OI.DIM_PRODUCT` dp
  CROSS JOIN last_loaded_date lld
  -- first sale = earliest day with PURCHASED_UNITS > 0; fall back to estimated_start_selling_date
  LEFT JOIN (
    SELECT dp2.product_short_name AS product, MIN(f.DATE) AS first_sale_date
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp2 ON dp2.asin = f.ASIN
    WHERE f.PURCHASED_UNITS > 0
    GROUP BY 1
  ) fs0 ON fs0.product = dp.product_short_name
  LEFT JOIN UNNEST([STRUCT(
    COALESCE((SELECT MIN(f.DATE) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
              JOIN `onyga-482313.OI.DIM_PRODUCT` dpx ON dpx.asin = f.ASIN
              WHERE dpx.product_short_name = dp.product_short_name AND f.PURCHASED_UNITS > 0),
             dp.estimated_start_selling_date) AS first_sale_date
  )]) AS fs
  -- trailing-window units + distinct selling days (last 30 calendar days up to last loaded date)
  LEFT JOIN (
    SELECT dp3.product_short_name AS product,
      SUM(f.PURCHASED_UNITS) AS launch_units,
      COUNT(DISTINCT f.DATE) AS launch_selling_days
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp3 ON dp3.asin = f.ASIN
    CROSS JOIN last_loaded_date lld2
    WHERE f.DATE BETWEEN DATE_SUB(lld2.last_date, INTERVAL 29 DAY) AND lld2.last_date
      AND f.PURCHASED_UNITS > 0
    GROUP BY 1
  ) lw ON lw.product = dp.product_short_name
),
```

Note: the inline `fs` STRUCT computes `first_sale_date` with the `estimated_start_selling_date` fallback (the separate `fs0` join is not needed — remove it; use only the `fs` UNNEST). If the UNNEST correlated-subquery form errors in your BigQuery dialect, replace `fs` with a plain `LEFT JOIN` to a CTE that does `COALESCE(MIN(sale), estimated_start_selling_date)` per product — same result. The widening window is `MIN(days_since_launch, 30)`; the 30-day units sum naturally equals the since-launch sum for a product younger than 30 days.

- [ ] **Step 2: Join `launch_signal` in the final query.** Find the join list near the end (it contains `LEFT JOIN daily_rates dr ON inv.product = dr.product`, ~L730). Add directly below it:

```sql
LEFT JOIN launch_signal ls ON inv.product = ls.product
```

- [ ] **Step 3: Syntax-validate (read-only, does NOT deploy).** Run the whole modified file as a dry-run by wrapping its body. Simplest: copy the file's `SELECT … ;` (everything after `CREATE OR REPLACE VIEW … AS`) into a dry-run:

```bash
cd /Users/ori/Develop/OI
# strip the CREATE OR REPLACE VIEW header, dry-run the SELECT body:
sed '0,/AS$/d' scripts/bigquery/views/V_PLAN_FORECAST.sql \
 | bq query --use_legacy_sql=false --project_id=onyga-482313 --dry_run 2>&1 | tail -5
```
Expected: `Query successfully validated. Assuming the tables are not modified, …` (a byte estimate). If it errors, fix the CTE syntax (commonly the `fs` UNNEST — fall back to the plain-join form noted above) and re-run.

- [ ] **Step 4: Commit.**

```bash
cd /Users/ori/Develop/OI && git add scripts/bigquery/views/V_PLAN_FORECAST.sql
git commit --no-verify -m "feat(plan): V_PLAN_FORECAST launch_signal CTE (first-sale, is_launching, run-rate)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Override the demand columns for launching rows

For `ls.is_launching` rows the engine must size off the launch run-rate and cap to lead + 1 month. Wrap each affected output expression. `available_stock = inv.fba_stock + inv.in_transit + inv.awd_stock`; `launch_cover = ls.launch_daily_rate * (inv.full_lead_days + 30)`.

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_FORECAST.sql`

- [ ] **Step 1: `daily_rate`.** Replace line 618:
```sql
  COALESCE(dr.daily_rate, 0) AS daily_rate,
```
with:
```sql
  CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE COALESCE(dr.daily_rate, 0) END AS daily_rate,
```

- [ ] **Step 2: `demand_during_lead`.** Replace line 652:
```sql
  ROUND(COALESCE(ld.demand_during_lead, 0)) AS demand_during_lead,
```
with:
```sql
  CASE WHEN ls.is_launching THEN ROUND(ls.launch_daily_rate * COALESCE(pl.effective_lead_days, inv.full_lead_days))
       ELSE ROUND(COALESCE(ld.demand_during_lead, 0)) END AS demand_during_lead,
```

- [ ] **Step 3: `demand_30d/45d/60d/90d` + `proportional_daily_demand`.** Replace lines 655–659:
```sql
  ROUND(COALESCE(dwin.demand_30d, 0)) AS demand_30d,
  ROUND(COALESCE(dwin.demand_45d, 0)) AS demand_45d,
  ROUND(COALESCE(dwin.demand_60d, 0)) AS demand_60d,
  ROUND(COALESCE(dwin.demand_90d, 0)) AS demand_90d,
  ROUND(COALESCE(dwin.demand_90d, 0) / 90, 2) AS proportional_daily_demand,
```
with (launching rows: linear projection of the launch rate; the 90-day window is capped to lead+30 so the next batch covers exactly lead + 1 month):
```sql
  CASE WHEN ls.is_launching THEN ROUND(ls.launch_daily_rate * 30) ELSE ROUND(COALESCE(dwin.demand_30d, 0)) END AS demand_30d,
  CASE WHEN ls.is_launching THEN ROUND(ls.launch_daily_rate * LEAST(45, inv.full_lead_days + 30)) ELSE ROUND(COALESCE(dwin.demand_45d, 0)) END AS demand_45d,
  CASE WHEN ls.is_launching THEN ROUND(ls.launch_daily_rate * LEAST(60, inv.full_lead_days + 30)) ELSE ROUND(COALESCE(dwin.demand_60d, 0)) END AS demand_60d,
  CASE WHEN ls.is_launching THEN ROUND(ls.launch_daily_rate * (inv.full_lead_days + 30)) ELSE ROUND(COALESCE(dwin.demand_90d, 0)) END AS demand_90d,
  CASE WHEN ls.is_launching THEN ROUND(ls.launch_daily_rate, 2) ELSE ROUND(COALESCE(dwin.demand_90d, 0) / 90, 2) END AS proportional_daily_demand,
```

- [ ] **Step 4: `days_until_oos`.** The existing formula divides stock by `demand_90d/90`; for launching rows `demand_90d` is now capped, so divide by the true launch rate instead. Replace lines 662–665:
```sql
  CASE WHEN COALESCE(dwin.demand_90d, 0) > 0
    THEN CAST(FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / (dwin.demand_90d / 90)) AS INT64)
    ELSE 999
  END AS days_until_oos,
```
with:
```sql
  CASE
    WHEN ls.is_launching THEN
      CASE WHEN ls.launch_daily_rate > 0
        THEN CAST(FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / ls.launch_daily_rate) AS INT64)
        ELSE 999 END
    WHEN COALESCE(dwin.demand_90d, 0) > 0
      THEN CAST(FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / (dwin.demand_90d / 90)) AS INT64)
    ELSE 999
  END AS days_until_oos,
```

- [ ] **Step 5: `emergency_priority`.** Mirror the same denominator switch. Replace lines 668–671:
```sql
  CASE WHEN COALESCE(dwin.demand_90d, 0) > 0
    THEN CAST(CEIL(GREATEST(0, FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / (dwin.demand_90d / 90))) / 7.0) AS INT64) + 1
    ELSE 999
  END AS emergency_priority,
```
with:
```sql
  CASE
    WHEN ls.is_launching THEN
      CASE WHEN ls.launch_daily_rate > 0
        THEN CAST(CEIL(GREATEST(0, FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / ls.launch_daily_rate)) / 7.0) AS INT64) + 1
        ELSE 999 END
    WHEN COALESCE(dwin.demand_90d, 0) > 0
      THEN CAST(CEIL(GREATEST(0, FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / (dwin.demand_90d / 90))) / 7.0) AS INT64) + 1
    ELSE 999
  END AS emergency_priority,
```

- [ ] **Step 6: `is_emergency`.** Reorder when available stock is below the lead+30 cover. Replace lines 674–678:
```sql
  CASE
    WHEN COALESCE(dwin.demand_90d, 0) = 0 THEN FALSE
    WHEN (inv.fba_stock + inv.in_transit + inv.awd_stock) < COALESCE(dwin.demand_90d, 0) THEN TRUE
    ELSE FALSE
  END AS is_emergency,
```
with:
```sql
  CASE
    WHEN ls.is_launching THEN
      (ls.launch_daily_rate > 0
        AND (inv.fba_stock + inv.in_transit + inv.awd_stock) < ROUND(ls.launch_daily_rate * (inv.full_lead_days + 30)))
    WHEN COALESCE(dwin.demand_90d, 0) = 0 THEN FALSE
    WHEN (inv.fba_stock + inv.in_transit + inv.awd_stock) < COALESCE(dwin.demand_90d, 0) THEN TRUE
    ELSE FALSE
  END AS is_emergency,
```

- [ ] **Step 7: Kill the Q4 pre-buy.** Replace lines 681, 684, 687:
```sql
  COALESCE(q4d.q4_demand, 0) AS q4_demand,
```
→
```sql
  CASE WHEN ls.is_launching THEN 0 ELSE COALESCE(q4d.q4_demand, 0) END AS q4_demand,
```
```sql
  COALESCE(pq4d.pre_q4_demand, 0) AS pre_q4_demand,
```
→
```sql
  CASE WHEN ls.is_launching THEN 0 ELSE COALESCE(pq4d.pre_q4_demand, 0) END AS pre_q4_demand,
```
```sql
  GREATEST(0, (inv.fba_stock + inv.awd_stock + inv.in_transit) - COALESCE(pq4d.pre_q4_demand, 0)) AS forecasted_sep1_pipeline,
```
→
```sql
  CASE WHEN ls.is_launching THEN (inv.fba_stock + inv.awd_stock + inv.in_transit)
       ELSE GREATEST(0, (inv.fba_stock + inv.awd_stock + inv.in_transit) - COALESCE(pq4d.pre_q4_demand, 0)) END AS forecasted_sep1_pipeline,
```

- [ ] **Step 8: Legacy DOC columns use the launch rate.** Replace lines 694–702 (the three `dr.daily_rate` DOC cases). For each, swap `dr.daily_rate` for `CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE COALESCE(dr.daily_rate,0) END`. Concretely, replace:
```sql
  CASE WHEN COALESCE(dr.daily_rate, 0) > 0
    THEN ROUND(inv.fba_stock / dr.daily_rate, 1) ELSE 999.0
  END AS fba_doc,
  CASE WHEN COALESCE(dr.daily_rate, 0) > 0
    THEN ROUND((inv.fba_stock + inv.in_transit) / dr.daily_rate, 1) ELSE 999.0
  END AS fba_doc_effective,
  CASE WHEN COALESCE(dr.daily_rate, 0) > 0
    THEN ROUND(inv.total_stock / dr.daily_rate, 1) ELSE 999.0
  END AS system_doc,
```
with:
```sql
  CASE WHEN (CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE COALESCE(dr.daily_rate, 0) END) > 0
    THEN ROUND(inv.fba_stock / (CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE dr.daily_rate END), 1) ELSE 999.0
  END AS fba_doc,
  CASE WHEN (CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE COALESCE(dr.daily_rate, 0) END) > 0
    THEN ROUND((inv.fba_stock + inv.in_transit) / (CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE dr.daily_rate END), 1) ELSE 999.0
  END AS fba_doc_effective,
  CASE WHEN (CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE COALESCE(dr.daily_rate, 0) END) > 0
    THEN ROUND(inv.total_stock / (CASE WHEN ls.is_launching THEN ls.launch_daily_rate ELSE dr.daily_rate END), 1) ELSE 999.0
  END AS system_doc,
```

- [ ] **Step 9: Syntax-validate (read-only).** Re-run the dry-run from Task 1 Step 3. Expected: `Query successfully validated…`. Fix any error before continuing.

- [ ] **Step 10: Commit.**
```bash
cd /Users/ori/Develop/OI && git add scripts/bigquery/views/V_PLAN_FORECAST.sql
git commit --no-verify -m "feat(plan): launch-aware demand override in V_PLAN_FORECAST final SELECT

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Validate sample rows (read-only — production view untouched)

Run the MODIFIED view SQL as an ad-hoc `SELECT` (does NOT replace the production view) and inspect a launching product vs an established one.

**Files:** none (validation only).

- [ ] **Step 1: Bunny (launching) — expect launch-rate + no Q4.** Run the view body filtered to Bunny products:
```bash
cd /Users/ori/Develop/OI
( sed '0,/AS$/d' scripts/bigquery/views/V_PLAN_FORECAST.sql | sed 's/;[[:space:]]*$//' ; ) > /tmp/vpf_body.sql
printf 'SELECT product, daily_rate, demand_90d, days_until_oos, is_emergency, q4_demand, available_stock\nFROM (\n' > /tmp/vpf_test.sql
cat /tmp/vpf_body.sql >> /tmp/vpf_test.sql
printf '\n) WHERE LOWER(product) LIKE "%%bunny%%" ORDER BY product LIMIT 20;\n' >> /tmp/vpf_test.sql
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty < /tmp/vpf_test.sql 2>&1 | tail -25
```
Expected for Bunny rows: `daily_rate` ≈ its own small early rate (a few/day, NOT a model-forecast number); `q4_demand = 0`; `demand_90d` ≈ `daily_rate × (full_lead_days + 30)` (small); `days_until_oos` = `available_stock / daily_rate` (sane, not 999 unless rate floored to 0). A Bunny product with < 3 selling days shows `daily_rate = 0` (seed-PO case).

- [ ] **Step 2: LolliME / Lollibox (established) — expect UNCHANGED.** Same harness, `LIKE "%lollime%"` then `"%lollibox%"`. Expected: `q4_demand > 0` (Q4 plan intact), `daily_rate` = the model rate, `demand_90d` = the seasonal 90-day window — i.e. identical to before this change (these are not launching).

- [ ] **Step 3: Spot-check the boundary.** Run a query listing `product, ls.is_launching, days_since_launch` (add those to the SELECT in /tmp/vpf_test.sql) to confirm only products with a first sale within 60 days are flagged. Expected: Bunny = TRUE; LolliME/Lollibox = FALSE.

- [ ] **Step 4: No commit (validation only).** If any expectation fails, return to Task 1/2, fix, re-validate.

---

## Task 4: Register the view change in config.yaml

**Files:**
- Modify: `config.yaml`

- [ ] **Step 1: Confirm the entry.** `grep -n "V_PLAN_FORECAST" config.yaml`. It already exists (the view is registered). If the registry tracks a description/columns hash or `last_modified`, update it to note the `is_launching` launch-demand override. If it's just a name/path entry, no change is needed — record in the commit that the definition changed.

- [ ] **Step 2: Commit (if config.yaml changed).**
```bash
cd /Users/ori/Develop/OI && git add config.yaml
git commit --no-verify -m "chore(plan): note V_PLAN_FORECAST launch-demand override in config.yaml

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Deploy to production + verify (⚠️ GATED — requires explicit user confirmation)

**Do NOT run this task until the user explicitly approves deploying to production.** It replaces the live view and regenerates real PO suggestions.

**Files:** none (deploy + verify).

- [ ] **Step 1: Get explicit go-ahead.** Confirm with the user: "Deploy the V_PLAN_FORECAST change to production and re-run SP_GENERATE_SHIPMENT_PLAN?" Proceed only on an explicit yes.

- [ ] **Step 2: Deploy the view.**
```bash
cd /Users/ori/Develop/OI
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/views/V_PLAN_FORECAST.sql 2>&1 | tail -3
```
Expected: the `CREATE OR REPLACE VIEW` succeeds (no error).

- [ ] **Step 3: Regenerate the shipment plan.**
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 "CALL \`onyga-482313.OI.SP_GENERATE_SHIPMENT_PLAN\`()" 2>&1 | tail -3
```
Expected: SP completes (it clears old SUGGESTED rows and writes new ones).

- [ ] **Step 4: Verify the SUGGESTED shipments.**
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty "
SELECT product, shipment_type_name, ship_qty, ship_qty_reason
FROM \`onyga-482313.OI.DE_SCHEDULED_SHIPMENTS\`
WHERE status='SUGGESTED' AND LOWER(product) LIKE '%bunny%'
ORDER BY product, shipment_type_name" 2>&1 | tail -30
```
Expected: Bunny suggestions are **small next-batch quantities** sized off its own rate, with **no `Q4_BULK`** rows (the Q4 pre-buy is gone). Cross-check a LolliME/Lollibox product still has its normal batches (including Q4_BULK) unchanged.

- [ ] **Step 5: Live UI check.** Open the Plan page → Shipment Plan; confirm Bunny shows small launch batches and no Q4 pre-buy, and the established families look unchanged. Report the before/after.

---

## Self-Review

**1. Spec coverage:**
- Detection (first sale < 60d) → Task 1 `launch_signal.is_launching`. ✓
- Own early run-rate over widening `MIN(days,30)` window + ≥3-selling-day floor → Task 1 `launch_daily_rate`. ✓
- Horizon cap = lead + 1 month → Task 2 (`demand_90d = rate × (full_lead_days+30)`, OOS/emergency/is_emergency switched to the launch rate so cover = lead+30 with correct OOS timing). ✓
- Kill Q4 pre-buy → Task 2 Step 7 (`q4_demand`/`pre_q4_demand`=0, `forecasted_sep1_pipeline`=stock). ✓
- Seed batch = manual PO (not built) → no task, by design. ✓
- Recalc = daily SP re-run; "additional PO needed" = existing types → unchanged, Task 5 verifies. ✓
- Graduation at 60d → `is_launching` is false past 60d ⇒ falls back to existing columns. ✓
- `V_PRODUCT_LAUNCH_MODEL` not used as multiplier → only `estimated_start_selling_date`/own first-sale used for detection. ✓ (Note: the plan uses `estimated_start_selling_date` as the fallback rather than `V_PRODUCT_LAUNCH_MODEL.first_sale_date`; both are launch-date-only signals — acceptable, the own first PURCHASED_UNITS date is primary.)
- SP + React unchanged → only `V_PLAN_FORECAST.sql` + `config.yaml` touched. ✓

**2. Placeholder scan:** every step has exact SQL + exact `bq` commands + expected output. The one conditional is the `fs` UNNEST fallback (a documented either/or with both forms specified), not a placeholder.

**3. Consistency:** `ls.is_launching`, `ls.launch_daily_rate`, `available_stock = inv.fba_stock+inv.in_transit+inv.awd_stock`, and `launch_cover = ls.launch_daily_rate*(inv.full_lead_days+30)` are used identically across Tasks 2–3. `demand_90d` for launching = the cover; `days_until_oos`/`emergency_priority`/`is_emergency` all switched to the launch rate so OOS timing stays correct while the order cover is lead+30. Consistent.

**4. Ambiguity:** the `demand_45d/60d` use `LEAST(N, lead+30)` so they never exceed the 90-day cover (avoids `demand_60d > demand_90d` inversion for short-lead products). The ≥3-selling-day floor and the `days_since_launch BETWEEN 0 AND 60` bound (excludes future-dated `estimated_start_selling_date`) are explicit.
