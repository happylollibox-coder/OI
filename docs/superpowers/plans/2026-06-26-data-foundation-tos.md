# Data Foundation + TOS-Aware Bidding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the coacher keyword-level true-impression / top-of-search signals from `targeting_keyword_report`, seed a per-product TOS target, and add a TOS-aware INCREASE_BID for profitable-but-buried keywords (closing the audit-#5 TOS-blind gap).

**Architecture:** A new `V_KEYWORD_DAILY` view exposes the real keyword-day report (impressions incl no-traffic, top-of-search share, set bid, match_type, parent). An 8-week per-keyword aggregate is joined into `V_ADS_COACH_DATA` (`target_tos_share`, `target_impressions_8w`, `no_traffic_rate`). A SQL step seeds `DE_PRODUCT_STRATEGY_PROFILE.tos_target_pct` per cell from winners' achieved TOS. `V_ADS_COACH` gains a TOS bid-up branch, mirroring the existing `BRAND_DEFENSE` TOS raise, capped at the band/ceiling.

**Tech Stack:** BigQuery Standard SQL (`bq` CLI). No new Python (TOS target is a SQL derivation).

**Spec:** `docs/superpowers/specs/2026-06-26-data-foundation-tos-design.md`

---

## File Structure
```
scripts/bigquery/views/V_KEYWORD_DAILY.sql              # new: keyword×day from targeting_keyword_report
scripts/bigquery/queries/derive_tos_targets.sql        # new: seed tos_target_pct per cell (UPDATE DERIVED rows)
scripts/bigquery/views/V_ADS_COACH_DATA.sql            # MODIFY: join 8wk TOS aggregate
scripts/bigquery/views/V_ADS_COACH.sql                 # MODIFY: TOS-aware bid-up branch
config.yaml                                            # register V_KEYWORD_DAILY
```
`bq --project_id=onyga-482313`. Branch `feat/owned-negatives-coacher`. Commit `--no-verify`. Deploy a view: `bq ... query --use_legacy_sql=false < file.sql`.

---

### Task 1: `V_KEYWORD_DAILY` view

**Files:** Create `scripts/bigquery/views/V_KEYWORD_DAILY.sql`; Modify `config.yaml`.

- [ ] **Step 1: Write the view**

```sql
-- V_KEYWORD_DAILY — keyword×day from the true keyword report (impressions incl no-traffic, TOS share, set bid).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_DAILY` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
kh AS (
  SELECT CAST(id AS STRING) AS keyword_id,
         ANY_VALUE(keyword_text) AS keyword_text, ANY_VALUE(match_type) AS match_type
  FROM `fivetran-hl.amazon_ads.keyword_history` GROUP BY 1
)
SELECT
  r.date,
  CAST(r.campaign_id AS STRING) AS campaign_id,
  CAST(r.ad_group_id AS STRING) AS ad_group_id,
  CAST(r.keyword_id  AS STRING) AS keyword_id,
  cp.parent_name,
  kh.keyword_text,
  UPPER(kh.match_type) AS match_type,
  r.keyword_bid,
  r.impressions, r.clicks, r.cost, r.cost_per_click,
  r.click_through_rate                AS ctr,
  r.top_of_search_impression_share    AS tos_share,
  r.units_sold_clicks_14_d            AS units_14d,
  r.sales_14_d                        AS sales_14d,
  r.ad_keyword_status,
  (r.sales_14_d - r.cost)             AS net_proxy,
  (r.impressions = 0)                 AS no_traffic
FROM `fivetran-hl.amazon_ads.targeting_keyword_report` r
LEFT JOIN camp_parent cp ON cp.campaign_id = CAST(r.campaign_id AS STRING)
LEFT JOIN kh            ON kh.keyword_id   = CAST(r.keyword_id AS STRING)
WHERE r.date >= DATE('2025-09-23');
```

- [ ] **Step 2: Deploy + validate**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_KEYWORD_DAILY.sql && echo OK
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_KEYWORD_DAILY`) AS rows_view,
  (SELECT COUNT(*) FROM `fivetran-hl.amazon_ads.targeting_keyword_report` WHERE date>=DATE("2025-09-23")) AS rows_raw,
  (SELECT COUNTIF(no_traffic) FROM `onyga-482313.OI.V_KEYWORD_DAILY`) AS no_traffic_rows,
  (SELECT COUNTIF(parent_name IS NOT NULL) FROM `onyga-482313.OI.V_KEYWORD_DAILY`) AS rows_with_parent'
```
Expected: `rows_view = rows_raw` (the LEFT JOINs must not fan out — `kh` is grouped by id, `camp_parent` is one-per-campaign; if rows_view > rows_raw, a join multiplied — stop and fix). `no_traffic_rows > 0` (the report has zero-impression days). `rows_with_parent` is most of the rows.

- [ ] **Step 3: Register + commit**

Add to `config.yaml` (views): `- name: "V_KEYWORD_DAILY"` / `    description: "Keyword×day from targeting_keyword_report — true impressions incl no-traffic, top-of-search share, set bid; feeds coacher TOS signals"`.
```bash
git add scripts/bigquery/views/V_KEYWORD_DAILY.sql config.yaml
git commit --no-verify -m "feat(coach): V_KEYWORD_DAILY — true keyword-day report (impressions, TOS, set bid)"
```

---

### Task 2: Seed `tos_target_pct` per cell

**Files:** Create `scripts/bigquery/queries/derive_tos_targets.sql`.

- [ ] **Step 1: Write the derivation (UPDATE DERIVED profile rows)**

```sql
-- derive_tos_targets.sql — per (parent×season×match_type×intent) cell, the 75th-pct top-of-search share
-- among net-profitable keyword-days, written to DE_PRODUCT_STRATEGY_PROFILE.tos_target_pct (DERIVED rows only).
UPDATE `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` p
SET p.tos_target_pct = s.tos_p75, p.updated_at = CURRENT_TIMESTAMP()
FROM (
  WITH cal AS (
    SELECT d AS date,
      IF(MAX(CASE WHEN d BETWEEN h.boost_start AND h.cooldown_start THEN 1 END)=1,'PEAK','OFF') AS season
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE('2025-09-23'), CURRENT_DATE('America/Los_Angeles'))) d
    LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON d BETWEEN h.boost_start AND h.cooldown_start
    GROUP BY d
  ),
  cells AS (
    SELECT kd.parent_name, cal.season, kd.match_type,
           COALESCE(ic.intent_class,'GENERIC') AS intent_class,
           kd.tos_share, kd.impressions
    FROM `onyga-482313.OI.V_KEYWORD_DAILY` kd
    JOIN cal ON cal.date = kd.date
    LEFT JOIN `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` ic
      ON ic.parent_name = kd.parent_name AND ic.keyword_text = LOWER(kd.keyword_text)
    WHERE kd.net_proxy > 0 AND kd.impressions > 0 AND kd.match_type IN ('BROAD','EXACT','PHRASE')
  )
  SELECT parent_name AS parent, season, match_type, intent_class,
         ROUND(APPROX_QUANTILES(tos_share, 100)[OFFSET(75)], 1) AS tos_p75
  FROM cells GROUP BY 1,2,3,4
) s
WHERE p.parent_name = s.parent AND p.season = s.season
  AND p.match_type = s.match_type AND p.intent_class = s.intent_class
  AND COALESCE(p.source,'DERIVED') != 'MANUAL';
```

- [ ] **Step 2: Run it + validate**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/queries/derive_tos_targets.sql && echo "tos targets seeded"
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT parent_name, match_type, intent_class, season, ROUND(tos_target_pct,1) AS tos_target
FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
WHERE tos_target_pct IS NOT NULL AND match_type IN ("BROAD","EXACT","PHRASE")
ORDER BY parent_name, match_type, intent_class, season LIMIT 25'
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv '
SELECT COUNTIF(tos_target_pct < 0 OR tos_target_pct > 100) AS out_of_range
FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`'
```
Expected: tos_target rows populated for keyword cells (BROAD/EXACT/PHRASE) with values in 0–100; `out_of_range = 0`. (AUTO/PRODUCT cells stay NULL — the keyword report doesn't cover them.) Report a few rows.

- [ ] **Step 3: Commit**

```bash
git add scripts/bigquery/queries/derive_tos_targets.sql
git commit --no-verify -m "feat(coach): seed per-cell tos_target_pct from winners' achieved top-of-search share"
```

---

### Task 3: Join the 8-week TOS signals into `V_ADS_COACH_DATA`

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH_DATA.sql`.

- [ ] **Step 1: Capture the current row count + locate the keyword_id grain**

Run: `cd /Users/ori/Develop/OI && bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM \`onyga-482313.OI.V_ADS_COACH_DATA\`'` (record it). Then `rg -n "keyword_id" scripts/bigquery/views/V_ADS_COACH_DATA.sql` to find where `keyword_id` is available in `active_term_data` (the same CTE the B `psp`/`kic` joins live in).

- [ ] **Step 2: Add the TOS aggregate CTE + join**

Add a CTE (lag-trimmed 8-week per-keyword aggregate) near the other CTEs:
```sql
  tos_8w AS (
    SELECT keyword_id,
      SAFE_DIVIDE(SUM(tos_share * impressions), NULLIF(SUM(impressions),0)) AS target_tos_share,
      SUM(impressions) AS target_impressions_8w,
      SAFE_DIVIDE(COUNTIF(no_traffic), COUNT(*)) AS no_traffic_rate
    FROM `onyga-482313.OI.V_KEYWORD_DAILY`
    WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 58 DAY)
      AND date <  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)
    GROUP BY keyword_id
  )
```
LEFT JOIN it in `active_term_data` on the keyword id (cast to match): `LEFT JOIN tos_8w ON tos_8w.keyword_id = CAST(<keyword_id col> AS STRING)`, and expose `tos_8w.target_tos_share`, `tos_8w.target_impressions_8w`, `tos_8w.no_traffic_rate`, propagating them to the final view output (typed NULLs for the opportunity-rows SELECT, same pattern as the B columns).

ALSO surface the profile's TOS target: the B `psp` join already brings in `DE_PRODUCT_STRATEGY_PROFILE` — add `psp.tos_target_pct AS tos_target_pct` to the exposed columns (and propagate it through), so Task 4 can read `d.tos_target_pct`. (It was NULL in B; Task 2 populated it.)

- [ ] **Step 3: Deploy + row parity**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH_DATA.sql && echo OK
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM `onyga-482313.OI.V_ADS_COACH_DATA`'
```
Expected: `OK`; count identical to Step 1 (tos_8w is one row per keyword_id → many-to-one, no fan-out). Spot-check a populated row: `SELECT keyword_id, ROUND(target_tos_share,1), target_impressions_8w, ROUND(no_traffic_rate,2) FROM \`onyga-482313.OI.V_ADS_COACH_DATA\` WHERE target_tos_share IS NOT NULL LIMIT 5`.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git commit --no-verify -m "feat(coach): expose 8wk top-of-search share + impressions + no-traffic to V_ADS_COACH_DATA"
```

---

### Task 4: TOS-aware bid-up in `V_ADS_COACH`

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH.sql`.

- [ ] **Step 1: Study the existing defense-TOS raise (the pattern to mirror)**

Run: `cd /Users/ori/Develop/OI && rg -n "th_defense_dominate_is|impression_share_pct|INCREASE_BID|target_action|profitable|scale_up" scripts/bigquery/views/V_ADS_COACH.sql | head -30`. Read the `BRAND_DEFENSE` branch (~line 754): it does `INCREASE_BID` toward the ceiling when `COALESCE(d.impression_share_pct,0) < d.th_defense_dominate_is`, with a trace chip. Note where `recommended_bid`, `target_action`, the profit gate (`profitable`/net-ROAS), the `strategy_bid_max`/`th_bid_cap`, the suppression branch, and `d.intent_class` are.

- [ ] **Step 2: Add a TOS bid-up branch**

In the `target_action` CASE, add a branch that fires AFTER suppression/defense/stop/reduce branches but with priority over plain KEEP — only for profitable, buried, non-suppressed keyword targets:
```sql
      WHEN d.target_tos_share IS NOT NULL
           AND d.tos_target_pct IS NOT NULL
           AND d.target_tos_share < d.tos_target_pct
           AND <the existing "profitable" / has-orders condition>
           AND NOT (d.intent_class = 'GENERIC' AND d.profile_enabled = FALSE AND d.profile_steers)
           AND d.current_bid < d.th_bid_cap
        THEN 'INCREASE_BID'
```
And ensure `recommended_bid` for this case steps toward the cap: it already passes through the outer `LEAST(GREATEST(<bid>, strategy_bid_min), strategy_bid_max, th_bid_cap)` clamp from B, so set the inner bid expression for a TOS-raise to move up (e.g. `GREATEST(<existing recommended bid>, LEAST(d.current_bid * 1.15, d.th_bid_cap))`) — reuse the same shape the defense branch uses; do not exceed `th_bid_cap`. Add a decision-trace chip `STRUCT('tos' AS id, CONCAT('buried: TOS ', CAST(ROUND(COALESCE(d.target_tos_share,0)) AS STRING), '% < target ', CAST(ROUND(d.tos_target_pct) AS STRING), '%') AS label, 'tos_raise' AS rule)` (match the file's chip struct shape).

- [ ] **Step 3: Deploy + validate behavior**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH.sql && echo OK
bq --project_id=onyga-482313 query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REFRESH_ADS_COACH_ACTIONS`()'
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT
  COUNTIF(target_action="INCREASE_BID" AND target_tos_share < tos_target_pct) AS tos_driven_bidups,
  COUNTIF(target_action="INCREASE_BID" AND target_tos_share >= tos_target_pct) AS bidup_already_dominant,
  COUNTIF(recommended_bid > th_bid_cap + 0.001) AS over_ceiling,
  COUNTIF(target_action="REDUCE_BID" AND current_bid IS NOT NULL AND recommended_bid > current_bid + 0.001) AS reduce_inversions,
  COUNTIF(target_action="INCREASE_BID" AND intent_class="GENERIC" AND profile_enabled=FALSE AND profile_steers
          AND strategy_id NOT IN ("BRAND_DEFENSE","PRODUCT_DEFENSE")) AS suppressed_generic_bidup
FROM `onyga-482313.OI.V_ADS_COACH`'
```
Expected: `tos_driven_bidups > 0` (the new behavior fires); `over_ceiling = 0`; `reduce_inversions = 0` (B fix intact); `suppressed_generic_bidup = 0` (suppression still wins over the TOS raise). Report the row. Also spot-check a LolliME journal head term gets the TOS raise: `SELECT parent_name, targeting, ROUND(target_tos_share,1) tos, ROUND(tos_target_pct,1) tgt, target_action FROM \`onyga-482313.OI.V_ADS_COACH\` WHERE parent_name="LolliME" AND target_tos_share < tos_target_pct AND target_action="INCREASE_BID" LIMIT 8`.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH.sql
git commit --no-verify -m "feat(coach): TOS-aware bid-up for profitable-but-buried keywords (capped at ceiling)"
```

---

## Review checkpoint (human)
After Task 4, review with Ori: do the seeded `tos_target_pct` values look sensible per product, and do the TOS-driven bid-ups land on the right "profitable but buried" keywords (LolliME journal head terms), not on terms that can't win position anyway?

## Notes / gotchas
- `targeting_keyword_report` is keyword-targeting only — AUTO/PRODUCT targets get no TOS signal (NULL `target_tos_share`) and the TOS branch can't fire for them. Intended.
- Type casts: report ids are INT64; `keyword_history.id` / coach `keyword_id` are STRING — cast consistently (`CAST(... AS STRING)`) on every id join.
- `tos_share` and `tos_target_pct` are both percentages (0–100) — compare directly.
- Suppression (B.2) must win over the TOS raise — the branch's `NOT (GENERIC & disabled & steers)` guard plus suppression-branch ordering ensures it; the `suppressed_generic_bidup=0` check is the gate.
- Re-run `SP_REFRESH_ADS_COACH_ACTIONS` after the view edits (it runs >2 min — run it in the background or with a long timeout).
- `bq` authed for `onyga-482313`.
