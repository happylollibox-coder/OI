# PPC Close The Loop — Change Log & Outcome Scoring

> **Goal**: Every applied PPC change (negate, bid change, promote, budget) is persisted to BigQuery,
> scored against actual post-change performance, and surfaced as a Decision Scorecard — so the
> Coach's calls become explainable, auditable, and usable to tune `DE_COACH_THRESHOLDS`.

---

## Problem

Applied changes from the DO page lived only in browser `localStorage`
(`dashboard-react/src/hooks/useDoQueue.tsx` — keys `oi_do_queue` / `oi_do_done` / `oi_do_uploaded`).
The system never learned whether a change was right.

A previous half-built attempt exists: `DE_BULKSHEET_UPLOADS` + `/api/bulksheet-uploads`
(Flask endpoint present, **never called by the dashboard**). That table is a thin generic log
(string old/new values, no coach snapshot, no keyword_id / ad_group_id / match_type).
**`FACT_PPC_CHANGE_LOG` supersedes it for outcome scoring.** `DE_BULKSHEET_UPLOADS` is left
in place untouched (legacy; candidate for retirement once this loop is proven).

## Object Graph

```
DO page "Uploaded to Amazon ✓"
  └─> POST /api/ppc-change-log  (Flask data-entry app; localStorage fallback + retry queue)
        └─> FACT_PPC_CHANGE_LOG          (append-only change log + coach metric snapshot)
              └─> V_PPC_ACTION_OUTCOMES  (pre/post window comparison vs FACT_AMAZON_ADS)
                    └─> Cube: PpcActionOutcomes
                          └─> Decision Scorecard (DO page)
                                └─> (future) tune DE_COACH_THRESHOLDS via SP_SUGGEST_THRESHOLD*
```

## FACT_PPC_CHANGE_LOG

- **DDL**: `scripts/bigquery/tables/FACT_PPC_CHANGE_LOG.sql` — `CREATE TABLE IF NOT EXISTS`
  (append-only log; never `CREATE OR REPLACE`).
- **Partitioning**: by `DATE(applied_at)`.
- **Writer**: Flask `POST /api/ppc-change-log` only (`load_table_from_json`, `WRITE_APPEND`,
  check `job.errors`, then `clear_data_cache()`).
- **Grain**: one row per applied change item (a "Mark all uploaded" batch produces N rows
  sharing one `batch_id`).

| Column | Type | Notes |
|---|---|---|
| `change_id` | STRING NOT NULL | `chg_<sha1-12>` — **deterministic** hash of (campaign_id, action, object, new_bid, new_budget, applied-day). Same logical change → same id, so a re-POST collapses via idempotent MERGE (no more duplicate rows) |
| `batch_id` | STRING NOT NULL | groups one upload batch |
| `applied_at` | TIMESTAMP NOT NULL | UTC instant the user marked uploaded; views derive LA date |
| `action` | STRING NOT NULL | DO-queue action (`NEGATE_TERM`, `REDUCE_BID`, `PROMOTE_TO_EXACT`, …) |
| `search_term` | STRING | shopper search term (term-level actions) |
| `targeting` | STRING | keyword/target text (target-level actions) |
| `keyword_id` | STRING | Amazon keyword / product-targeting ID |
| `match_type` | STRING | EXACT / PHRASE / BROAD / PRODUCT_TARGETING |
| `campaign_id` | STRING | |
| `campaign_name` | STRING | display |
| `campaign_type` | STRING | SP / SB / SBV |
| `ad_group_id` | STRING | |
| `product` | STRING | ASIN or product short name (as carried by the DO queue) |
| `old_bid` / `new_bid` | FLOAT64 | bid actions (`current_bid` → `recommended_bid`) |
| `old_budget` / `new_budget` | FLOAT64 | budget actions |
| `target_spend_8w` | FLOAT64 | **coach snapshot at decision time** |
| `target_orders_8w` | INT64 | coach snapshot |
| `target_net_roas_8w` | FLOAT64 | coach snapshot |
| `coach_mode` | STRING | GUARDIAN / COOLDOWN / BLITZ / DEFAULT at decision time |
| `source` | STRING NOT NULL | `'COACH'` (queued from a coach recommendation) or `'MANUAL'` |

Timezone note (per the layered model): `applied_at` is a UTC `TIMESTAMP`;
**all window math happens in `V_PPC_ACTION_OUTCOMES` using
`DATE(applied_at, 'America/Los_Angeles')`** so it aligns with `FACT_AMAZON_ADS.date`.

## V_PPC_ACTION_OUTCOMES

- **SQL**: `scripts/bigquery/views/V_PPC_ACTION_OUTCOMES.sql`
- **Grain**: one row per `change_id` (changes from the **last 180 days**; FACT scan statically
  bounded to 200 days for partition pruning).

### Windows

| Window | Range (LA dates) |
|---|---|
| `change_date` | `DATE(applied_at, 'America/Los_Angeles')` — excluded from both windows |
| Pre | `[change_date − 14d, change_date − 1d]` |
| Post | `[change_date + 1d, change_date + 14d]`, additionally capped at `data_cutoff` |
| `data_cutoff` | `CURRENT_DATE('America/Los_Angeles') − 2d` — excludes the ads attribution lag (1–2 days per Ori 2026-05-17; the Coach's "4-day lag" doc note is a conservative buffer, see `ADS_COACH_DECISION_MATRIX.md`) |

`post_days_elapsed = DATE_DIFF(LEAST(change_date + 14, data_cutoff), change_date, DAY)` (≥ 0).
Pre/post metrics are compared as **per-day rates** so a partial post window is still comparable.

### Scope — which FACT_AMAZON_ADS rows count

| `action_group` | Actions | Scope predicate |
|---|---|---|
| `NEGATE` | `NEGATE_*`, `STOP_TERM`, `STOP`, `NEGATE`, `SWITCH_HERO` | `campaign_id` + `LOWER(search_term)` |
| `UNNEGATE` | `REMOVE_NEGATIVE`, `REMOVE_CONFLICTING_NEGATIVE` | `campaign_id` + `LOWER(search_term)` — the inverse of `NEGATE`: a previously-blocked term is re-allowed, so it's judged term-scoped on whether it now converts (not the generic campaign-level `OTHER` check it used to fall into) |
| `PAUSE_TARGET` | `STOP_TARGET` | `campaign_id` + `keyword_id` (exact Amazon ID; falls back to `LOWER(targeting)` when no keyword_id was logged — `FACT_AMAZON_ADS` has no `match_type` column) |
| `BID_DOWN` | `REDUCE_BID` | same as `PAUSE_TARGET` |
| `BID_UP` | `INCREASE_BID`, `BOOST`, `SCALE_UP` | same as `PAUSE_TARGET` |
| `PROMOTE` | `PROMOTE_TO_*`, `START_TERM`, `START` | `LOWER(search_term)` across **all** campaigns (promotion creates a new campaign) |
| `BUDGET` | `*BUDGET*` | `campaign_id` only |
| `OTHER` | anything else | `campaign_id` only |

### Net ROAS — same semantics as the Coach (direct ad-attributed, **no halo**)

Mirrors `V_ADS_COACH_DATA`'s `ads_net_roas_8w`:

```
margin_per_unit = DIM_PRODUCT.listing_price_amount − latest(DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT)
fallback margin = SAFE_DIVIDE(sales, orders) − total_cost_per_unit
net_roas        = SAFE_DIVIDE(margin_per_unit × units, spend)
```

Do **not** swap in Cube's `UnifiedPerformance` Net ROAS here — the verdict must use the same
metric that fired the threshold (gotchas #1 and #5 in the oi-data-analyst skill).

### Verdicts

`TOO_EARLY` and `NO_DATA` always take precedence:

- `TOO_EARLY` — `post_days_elapsed < 7` (full confidence at 14).
- `NO_DATA` — no FACT rows matched in either window (or, for `PROMOTE`/`UNNEGATE`, no post spend:
  the promoted/re-allowed keyword never went live).

Otherwise, per action group:

| Group | `IMPROVED` when | rationale |
|---|---|---|
| `NEGATE` / `PAUSE_TARGET` | pre `net_roas < 1.0` OR pre orders = 0 | we cut spend that was losing money; `weekly_savings = pre_spend_per_day × 7` |
| | `WORSE` otherwise (pre `net_roas ≥ 1.0`) | we cut profitable traffic |
| `BID_DOWN` | post `net_roas ≥` pre `net_roas` | bid cuts are an efficiency play |
| `BID_UP` | post orders/day ≥ pre orders/day AND post `net_roas ≥ 0.8 ×` pre | scaling allows modest efficiency dip |
| `PROMOTE` | post orders/day > pre orders/day AND post `net_roas ≥ 1.0` | promotion must produce profitable volume |
| `UNNEGATE` | post orders > 0 AND post `net_roas ≥ 1.0` | re-allowing a blocked term must prove it now converts profitably (pre window is ~0 by construction — it was negated); `NO_DATA` when no post spend |
| `BUDGET` (increase) | as `BID_UP`, campaign scope | |
| `BUDGET` (decrease) / `OTHER` | as `BID_DOWN` scope rules | |

Output columns include per-window `spend/orders/units/sales/net_profit/net_roas`,
per-day rates, deltas, `weekly_savings`, `verdict`, `action_group`, plus the decision-time
coach snapshot passed through for display.

**Known limitation (documented, accepted)**: negate verdicts are judged on pre-window
profitability (the negated term has no post data by construction) — i.e. "was the coach's
premise right", not a counterfactual. Bid/budget/promote verdicts are true pre/post comparisons.

## Ingestion — Flask + DO page

- `POST /api/ppc-change-log` — body: JSON array of change items (camel-ish keys identical to
  `DoQueueItem` fields plus `source`). Server mints a **deterministic** `change_id` (see table
  above) plus `batch_id`/`applied_at`. **Idempotent**: rows are loaded to an ephemeral staging
  table and `MERGE … WHEN NOT MATCHED`-ed into `FACT_PPC_CHANGE_LOG` on `change_id`, so any
  re-POST (double-click, multi-tab, offline-flush race, dev StrictMode) is a no-op rather than
  a duplicate row. BigQuery serialises DML on the target, so concurrent re-POSTs are race-safe.
  `clear_data_cache()` after write. Returns `{success, batch_id, items_received, items_logged}`
  (`items_logged` = rows actually inserted by the MERGE).
- **Client dedup (defence in depth)**: `useDoQueue.tsx` keeps `oi_ppc_log_sent` keys
  (`ppcLogDedup.changeLogKey`) and dedups both the upload batch and the on-mount re-flush of
  `oi_ppc_log_pending` before POSTing. The server MERGE is the authoritative backstop.
- `GET /api/ppc-change-log?limit=N` — recent rows, for verification/debug.
- **DO page**: `markAllUploaded()` in `useDoQueue.tsx` now also POSTs the batch.
  localStorage remains the source for the UI (offline fallback). Failed POSTs are queued in
  localStorage key `oi_ppc_log_pending` and re-flushed on next app load / next upload.
  `coach_mode` and `source` were added to `DoQueueItem` and populated where items are queued
  (Actions page). Items queued before this change log `coach_mode=''`, `source='COACH'`.

## Cube + Dashboard

- **Cube**: `cube/schema/PpcActionOutcomes.js` over `V_PPC_ACTION_OUTCOMES`.
  Measures: `count`, `improvedCount`, `worseCount`, `scoreableCount`, `accuracyPct`
  (= improved / (improved + worse)), `totalWeeklySavings`.
- **UI**: `DecisionScorecard` section on the **DO page** (where uploads happen): aggregate
  coach accuracy %, verdict counts, and per-change verdict sentences, e.g.
  "negated 'X' — saving $Y/wk" / "bid cut on 'Z' — orders dropped, likely wrong call".

## Future (out of scope here)

- Feed `V_PPC_ACTION_OUTCOMES` verdict rates into `SP_SUGGEST_THRESHOLD*` to tune
  `DE_COACH_THRESHOLDS` (e.g. negate_roas too aggressive if NEGATE WORSE-rate is high).
- Backfill from `DE_BULKSHEET_UPLOADS` / retire that table.
- Business-unit coacher confidence gate can consume per-family accuracy %.

## Maintenance Log

| Date | Change |
|---|---|
| 2026-06-11 | Initial design + implementation (table, view, endpoint, DO-page wiring, Cube, scorecard). |
| 2026-06-16 | **Idempotent ingestion**: deterministic `change_id` + staging-table `MERGE` (no more duplicate-logged rows); client mount-flush now dedups. **`UNNEGATE` action_group**: `REMOVE_NEGATIVE`/`REMOVE_CONFLICTING_NEGATIVE` now scored term-scoped (did the re-allowed term convert?) instead of falling into campaign-level `OTHER`. |
