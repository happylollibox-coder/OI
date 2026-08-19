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
              └─> V_PPC_CHANGE_LOG_APPLIED  (minus FAILED_UPLOAD — the read surface)
                    ├─> V_PPC_ACTION_OUTCOMES  (FAST/EARLY: 7d pre vs 7d post at T+2 cutoff)
                    │     └─> Cube: PpcActionOutcomes
                    │           └─> Decision Scorecard (DO page)
                    └─> V_CHANGE_SCORECARD     (SETTLED: [T+1,T+7] graded no earlier than T+14)
                          └─> Cube: ChangeScorecard
                                └─> Weekly Run page — the OUTCOME half of the loop
                                      └─> (future) tune DE_COACH_THRESHOLDS via SP_SUGGEST_THRESHOLD*
```

**Two outcome views, on purpose.** `V_PPC_ACTION_OUTCOMES` is the fast read (verdict at ~T+9,
data cut at `today-2`) and answers *"did the coach's premise look right?"*.
`V_CHANGE_SCORECARD` is the **settled** read (verdict no earlier than T+14) and answers
*"did the change actually pay?"*. They will disagree on young changes — that is by design, and
the settled view is the one that gets to overrule an entity's bid. See the section below for
why the extra week is not optional.

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
| `upload_status` | STRING | `NULL` = assumed landed in Amazon (default). `'FAILED_UPLOAD'` = verified never landed (bulksheet exported + logged, but the Amazon upload silently failed). Set **only** by audited migrations after comparing the log against the live Fivetran mirrors — never by the writer. |

## Upload verification & FAILED_UPLOAD marking (2026-08-08)

A change-log row records what was **attempted**, not what Amazon accepted. On 2026-08-06 three
whole batches (38 rows: `batch_20260806_162211_d1b142`, `batch_20260806_183247_990c97`,
`batch_20260806_184036_3853e9`, plus 2 unverifiable negates in `batch_20260806_160801_c2e9ae`)
were logged as applied but never landed — poisoning outcome verdicts, APPLIED_HOLD windows,
cooldowns, and the v27.14 negate retirement.

Doctrine:

- **`V_PPC_CHANGE_LOG_APPLIED`** (`scripts/bigquery/views/V_PPC_CHANGE_LOG_APPLIED.sql`) =
  `FACT_PPC_CHANGE_LOG` minus `upload_status='FAILED_UPLOAD'` rows. **Every analytical consumer
  reads this view** — outcome scoring (`V_PPC_ACTION_OUTCOMES`), cooldowns
  (`V_ADS_COACH_DATA`, `V_RUN_TARGET`, `V_SB_LAUNCH_TARGET`, `V_WEEKLY_RUN_*`), APPLIED_HOLD +
  probe episodes (`V_OOB_KEYWORD`, `V_KEYWORD_LIFT`, `V_OOB_BUDGET_PHASE`), negate retirement
  (`V_OOB_SEARCH_TERM`), negative sync (`SP_SYNC_NEGATIVES`), and the live
  `/api/applied-recent` endpoint. Only the Flask writer (`POST /api/ppc-change-log`), the
  debug `GET /api/ppc-change-log`, and audits read the raw table.
- **Marking** is an `UPDATE … WHERE batch_id IN (…)` in a dated migration
  (`scripts/bigquery/migrations/`), keyed by batch_id with a partition filter on
  `DATE(applied_at)`. Never delete rows — the attempt is part of the audit trail.
- **Verification method** (see migration 2026-08-08): compare each row's `new_bid`/`new_budget`
  to the latest live row per entity in `fivetran-hl.amazon_ads`
  (`keyword_history`/`sb_keyword`/`targeting_clause_history`/`sb_product_target`/
  `campaign_history`/`sb_campaign_history`), ±$0.005, at T+2 days (Fivetran lag), accounting
  for supersession by later log rows on the same entity. `NEGATE_TERM` rows are unverifiable
  (negative mirrors frozen since 2026-01-03) — mark them when their sibling batches provably failed.
- **Re-upload**: after a corrected bulksheet is confirmed uploaded, POST fresh rows
  (new batch, `source='REUPLOAD'`) so APPLIED_HOLD re-arms with the correct timestamp.
  Do **not** un-mark the failed rows.

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
| Pre | `[change_date − 7d, change_date − 1d]` |
| Post | `[change_date + 1d, change_date + 7d]`, additionally capped at `data_cutoff` |
| `data_cutoff` | `CURRENT_DATE('America/Los_Angeles') − 2d` — excludes the ads attribution lag (1–2 days per Ori 2026-05-17; the Coach's "4-day lag" doc note is a conservative buffer, see `ADS_COACH_DECISION_MATRIX.md`) |

`post_days_elapsed = DATE_DIFF(LEAST(change_date + 7, data_cutoff), change_date, DAY)` (≥ 0).
Pre/post metrics are compared as **per-day rates** so a partial post window is still comparable.
The pre window is a full 7 days, so its 7-day total equals the weekly rate (`weekly_savings = pre_spend`).
The view also emits per-day averages (`pre/post_net_profit_per_day`, `pre/post_units_per_day`) and
window-level CPC (`pre/post_cpc = spend / clicks`) for the scorecard detail panel.

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

- `TOO_EARLY` — `post_days_elapsed < 7` (verdict final once all 7 post-days settle, ~9 cal days post-change).
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

## V_CHANGE_SCORECARD — the settled OUTCOME half (2026-08-12)

> Ori's doctrine, 2026-08-11: **"1 day for opportunity, 7 days for OUTCOME."** The opportunity
> half was tested and rejected (a standout day marks the stretch you were already in — see
> `project_one_day_signal_verdict`). The outcome half is this view, and it measured as the best
> instrument in the system: settled 7-day verdicts separate the following fortnight by
> **+0.598 GP-ROAS** (FAIL 0.342 → next-14d 0.993; STRONG 2.129 → next-14d 1.591).

- **SQL**: `scripts/bigquery/views/V_CHANGE_SCORECARD.sql`
- **Source**: `V_PPC_CHANGE_LOG_APPLIED` (**never** the raw `FACT_PPC_CHANGE_LOG` — the applied
  view already drops the 40 `FAILED_UPLOAD` rows from the 2026-08-06 silent upload failure;
  grading a change that never landed in Amazon is grading noise).
- **Grain**: one row per graded change (deduped to one row per logical change per LA day).
- **Money metric**: **GP-ROAS** on the doctrine tier-COGS formula —
  `Ads_sales − COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) × Ads_units`, over
  `Ads_cost`. Identical to `V_OOB_KEYWORD` / `V_PARK_REVERDICT`, so a revive bar and a scorecard
  verdict are stated in the same currency. (This differs from `V_PPC_ACTION_OUTCOMES`, which uses
  the coach's `listing_price − TOTAL_COST_PER_UNIT` margin — that view grades the *coach threshold*,
  this one grades the *money*.)

### Grading windows — the entire point of the view

| Channel | Graded window | Read no earlier than | Extended window (thin evidence) | Extended read gate |
|---|---|---|---|---|
| SP | `[T+1, T+7]` | `T+14` | `[T+1, T+21]` | `T+28` |
| SB | `[T+1, T+14]` | `T+21` | `[T+1, T+21]` | `T+28` |

`T` = `DATE(applied_at, 'America/Los_Angeles')` and is **excluded from every window** — the change
lands mid-day, so day T is neither pre nor post.

The load-bearing predicate is the freshness guard:

```sql
WHERE DATE_ADD(window_end, INTERVAL 7 DAY) <= CURRENT_DATE('America/Los_Angeles')
```

i.e. `T+14 <= today` for SP and `T+21 <= today` for SB. **A change that is not old enough does not
appear in the view at all** — there is no `TOO_EARLY` row to be misread as a signal. Rows only ever
enter, never change verdict retroactively once settled.

### Why grading early is worse than not grading (do not "optimise" this away)

A trailing 7-day window ending yesterday reads roughly **89.5% of its final sales** — and the
shortfall is worst on the **newest day**, which is exactly the day your change affected most.
Measured on `V_ADS_SETTLE_CURVE` (sales `pct_of_final`, median): age 1 = **67.0%**, age 2 = 87.4%,
age 4 = 93.0%, age 7 = 95.0%, age 11 = **100%**. Spend closes fast (99.9% by age 2); the entire
distortion lives in sales, therefore in ROAS.

The failure mode is not "a bit noisy". It is **systematic and self-reinforcing**:

1. You grade a raise at T+8. The last days of the window are 67–87% settled, so GP-ROAS reads low.
2. The verdict says REVERSED. You put the bid back.
3. The sales accrue. The window you already acted on settles above the bar.
4. Next week the engine re-raises the same keyword, and you reverse the reversal.

That is churn manufactured by the instrument, and it costs money in both directions (a false cut
kills a winner permanently; a false restore just delays). Hence: **no verdict before settle.**
Same rule, same reason, as `V_PARK_REVERDICT` (`SEASON_CONTEXT_LEDGER.md` §7) and the
`SETTLE_HOLD` veto (§7.6).

Residual, documented and accepted: at the read gate the newest window day is age 7 (≈95% of final
sales), not age 11 (100%). For **SB** the last window day is read at age 7 of a 14-day attribution
tail, so SB GP is understated. The error direction is safe — an understated window can only produce
a *false REVERSED*, whose remedy is "restore the pre-change bid", never a cut. It self-heals on a
later run because the view re-reads today's restatement each time.

### Prior record — `[T-28, T-1]`, settled by construction

Each entity is graded against **its own** settled record over `[T-28, T-1]`. Because the freshness
guard already requires `T+14 <= today`, day `T-1` is at least 15 days old, so the prior window needs
no separate settle guard.

⚠️ **Known bias, stated plainly.** The engines select entities on their *two worst days*, so a bounce
back toward the mean is the null hypothesis, not the treatment effect. Grading against the entity's
own prior therefore **flatters** every change — `NEUTRAL` in particular. The 28-day prior is much
wider than the selection window, which damps but does not remove it. The honest version of this
instrument is a **matched untouched control cohort**; that is a separate build. Until then, read
`CONFIRMED`/`REVERSED` as directional and never treat `NEUTRAL` as proof a change helped.

### Verdicts

Precedence: `INSUFFICIENT` → `CONFIRMED` → `NEUTRAL` → `REVERSED`.

| Verdict | Rule | What Ori does |
|---|---|---|
| `CONFIRMED` | window GP-ROAS **≥ 1.0** | hold; **one** more step in the same direction allowed |
| `NEUTRAL` | window GP-ROAS ≥ its own prior, but **< 1.0** absolute | hold, **no further step** |
| `REVERSED` | window GP-ROAS **< 1.0 AND below its own prior** | **restore the pre-change value**, never lower |
| `INSUFFICIENT` | **< 10 settled clicks** in the window | extend to `T+21`; never verdict on thin evidence |

`INSUFFICIENT` is a *retry*, not a conclusion: when the primary window is thin **and** `T+28 <= today`,
the view re-grades on `[T+1, T+21]` and stamps `window_used = 'EXTENDED'`. Only if the extended
window is still under 10 clicks does the row stay `INSUFFICIENT`.

**`REVERSED` is not a disaster verdict.** Measured, REVERSED rows land near **0.993 GP-ROAS** —
breakeven, not catastrophe. The remedy is therefore *"put it back"* (`remedy_value` = the logged
`old_bid` / `old_budget`), never *"punish it further"*. The view emits the restore value on the row;
it never emits a lower one.

**No comparable prior** (< 10 settled clicks in `[T-28, T-1]`, e.g. a newly added target): the
relative test is undefined, so the row is judged **absolute only** — `CONFIRMED` at ≥ 1.0, else
`REVERSED` — and `prior_available = FALSE` says so.

### How each action type is scored

| `action_group` | Actions | Scope grain | Scored on |
|---|---|---|---|
| `BID_DOWN` | `REDUCE_BID` | target: `campaign_id` + `keyword_id` (falls back to `LOWER(targeting)` when the keyword_id has never appeared in FACT) | GP-ROAS ladder |
| `BID_UP` | `INCREASE_BID`, `BOOST`, `SCALE_UP` | same | GP-ROAS ladder |
| `PAUSE_TARGET` | `STOP_TARGET` | same | GP-ROAS ladder (window is ~0 by construction → usually `INSUFFICIENT`; the prior columns carry the premise) |
| `BUDGET_UP` / `BUDGET_DOWN` | `BUDGET_CHANGE`, `GUARDIAN_BUDGET_*`, `DEFENSE_BUDGET_FLOOR` — direction from `new_budget` vs `old_budget` | **campaign** (`campaign_id` only) | GP-ROAS ladder **at campaign grain** — a budget change moves the whole campaign, so the campaign's own settled GP-ROAS is the only honest measure. `budget_utilization` (= window spend/day ÷ `new_budget`) is exposed so a human can see whether the budget ever bound. |
| `NEGATE` | `NEGATE_TERM`, `NEGATE_*`, `STOP_TERM` | term: `campaign_id` + `LOWER(search_term)` | **the term disappearing, not ROAS.** `CONFIRMED` = the term's window spend fell to ≤ 15% of its prior daily rate, **or** the residual is under 3 clicks (negatives propagate with a lag and the change is marked uploaded mid-day, so a click or two on T+1 is expected — without this floor a $0.58 / 1-click tail reads 19% and false-alarms). `REVERSED` = the term is still spending (the negative did **not** land — wrong match type, wrong level, or a failed upload) → remedy is *re-apply*, not restore a bid. `INSUFFICIENT` = prior term clicks < 10, so disappearance proves nothing. The prior GP-ROAS is carried on the row so the **premise** ("was it losing money?") is auditable next to the **execution**. |
| `UNNEGATE` | `REMOVE_NEGATIVE`, `REMOVE_CONFLICTING_NEGATIVE` | term | GP-ROAS ladder, absolute-only (prior is ~0 by construction) |
| `ADD_TARGET` | `ADD_COMPETITOR_TARGET(_SB)`, `ADD_CROSS_SELL_TARGET`, `ADD_PRODUCT_AD`, `PROMOTE_*`, `START*` | target, within the campaign it was added to | GP-ROAS ladder, absolute-only |
| `OTHER` | anything else (`CAMPAIGN_PAUSE`, `CAMPAIGN_RENAME`, …) | campaign | GP-ROAS ladder; listed for completeness, not decision-grade |

**Deliberate scope limitation**: `PROMOTE_*` is scored inside its logged campaign, not across all
campaigns the way `V_PPC_ACTION_OUTCOMES` does it. There are currently zero `PROMOTE_*` rows in the
log; when promotes resume, revisit this.

### Contamination flags (audit, not verdict)

- `superseded_in_window` / `next_change_date` — a **later** change hit the same entity inside the
  graded window, so the window measures both. The row is **flagged, not dropped** (dropping would
  silently hide the most-worked-on entities). Any threshold-tuning pass must filter these out.
- `match_mode` (`KID` / `TEXT`) — how the target was resolved against FACT.
- `window_used` (`PRIMARY` / `EXTENDED`).

### Self-validation columns

`next14_gp_roas` over `[window_end+1, window_end+14]` (populated only when that window is itself
settled, `next14_readable`) exists so the **+0.598 spread can be re-measured from the view itself**,
not taken on faith. Restrict any such check to `window_used = 'PRIMARY'` — the extended window
overlaps `next14` and would be circular.

### Determinism

Plain `SUM`s over fixed date windows; no `ANY_VALUE` pairs (v27.46 lesson — never divide two
`ANY_VALUE`s from one `GROUP BY`); the dedup `QUALIFY` is fully tie-broken on
`(applied_at, change_id)`. Two consecutive pulls are byte-identical within a day
(2026-08-12: md5 `8b38cae65cc86bddc85176ed910e5206`, 411 rows).

### Known gaps (2026-08-12)

1. **126 change-log rows can never be graded — they were logged without a `campaign_id`.**
   All of them are `ADD_COMPETITOR_TARGET` (116, 2026-07-23/24), `ADD_COMPETITOR_TARGET_SB` (7)
   and `ADD_CROSS_SELL_TARGET` (3). Every scope in this view starts from `campaign_id`, so the
   entire competitor-targeting push of 23–24 July is invisible to the loop. **Fix at the writer**:
   the DO-queue items for `ADD_*` actions must carry `campaign_id` (and ideally `ad_group_id`)
   before the next competitor-target batch.
2. **Own-prior comparison, not a matched control** — see the bias note above. This is the single
   biggest thing standing between this view and a trustworthy accuracy number.
3. **SB is inference.** `sb_keyword_report` died 2025-12-29; SB rows are graded off
   `FACT_AMAZON_ADS` SB rows with a 14-day window read at age 7. Treat SB verdicts as weaker
   evidence than SP ones.
4. ⚠️ **`RESTORE_BUDGET` on a `BUDGET_DOWN` row can point the wrong way — do not automate it.**
   A budget cut is graded at campaign grain, so any campaign sitting under 1.0 GP-ROAS reads
   `REVERSED` whether or not the cut was the cause, and the mechanical remedy ("restore the
   pre-change value") then says *raise the budget on a losing campaign*. That is backwards.
   The four largest `REVERSED` rows today are all `BUDGET_DOWN`/`BID_DOWN` on FRESH SB campaigns
   that were **already** below breakeven before the cut. Treat `RESTORE_BUDGET` as "this cut did
   not fix the campaign — look at the campaign", never as an instruction. Ori decides, as with the
   rest of the page. If this is ever wired to an action, gate it on `prior_gp_roas >= 1.0`.
5. **`PAUSE_TARGET` cannot really be graded** — the entity is paused, so its window is 0 clicks and
   the verdict is `INSUFFICIENT` by construction. The prior columns carry the premise; that is all
   this view can honestly say about a pause.

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

### V_CHANGE_SCORECARD surface (2026-08-12)

The settled half needed its own surface, on the page where the changes are actually initiated:

| piece | where |
|---|---|
| cube | `cube/schema/ChangeScorecard.js` over `V_CHANGE_SCORECARD` (live read, 15-min TTL — the `KeywordLift` / `OobBudget` / `PausedHistory` convention) |
| panel | `dashboard-react/src/pages/ChangeScorecardPanel.tsx`, mounted as its own top-level section on **Weekly Run**, above the total-budget panel — the retrospective frames the run |

The panel is titled **"How did last week's changes do?"**, collapsed by default with the verdict
counts visible in the header (`N confirmed · N neutral · N reversed · N insufficient`). Inside,
rows are grouped CONFIRMED → NEUTRAL → REVERSED → INSUFFICIENT and sorted newest-change-first
within each group. Each row carries: change date · `source` (COACH / MANUAL) · `action` ·
campaign ▸ target/term · `old_value` → `new_value` (`value_kind` picks the $ label) · the settled
window result (`win_clicks` · `win_spend` · `win_gp_roas` · `win_net_profit` over
`[window_start, window_end]`) · the prior record (`prior_gp_roas` on `prior_clicks`, greyed when
`prior_available = FALSE`) · `verdict_reason` verbatim · and the contamination flag
(`superseded_in_window`, `n_later_changes`).

**REVERSED rows show the restore explicitly** — `remedy` + `remedy_value` (which is the
pre-change `old_value`), rendered as "put it back → $X". Per the measurement note, REVERSED lands
near breakeven, so the copy says *restore*, never *punish further*.

Rows that are not old enough to grade never reach the view (the `read_gate_date` guard), so the
panel's empty state is honest: "nothing settled yet" means exactly that, not "no changes made".

**Advisory + display-only.** No verdict logic, threshold or bid math lives in the TypeScript —
`verdict`, `verdict_reason`, `remedy` and `remedy_value` are all read from the view. The panel
does not write to the DO queue.

Both this panel and the Revivals panel degrade gracefully: a failed cube load (e.g. a stale cube
schema missing a dimension) is caught and the header reads "— unavailable" instead of throwing,
so Weekly Run always renders.

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
| 2026-08-12 | **`V_CHANGE_SCORECARD`** — the settled OUTCOME half of Ori's "1 day for opportunity, 7 days for outcome" doctrine, finally built. Graded `[T+1,T+7]` (SB `[T+1,T+14]`) read no earlier than T+14 (SB T+21), against the entity's own settled `[T-28,T-1]` record. Verdicts CONFIRMED / NEUTRAL / REVERSED / INSUFFICIENT; REVERSED restores the pre-change value and never goes lower. Tier-COGS GP-ROAS, same currency as the revival bar. |
| 2026-08-12 | **Weekly Run surfaces**: `ChangeScorecard` cube + "How did last week's changes do?" panel (this doc, §Cube + Dashboard), and `ParkReverdict` cube + Revivals panel (`SEASON_CONTEXT_LEDGER.md` §7.11). Both display-only, both on the page where Ori initiates changes. Not deployed — needs a cube restart + cache stamp. |
| 2026-08-08 | **`upload_status` + `V_PPC_CHANGE_LOG_APPLIED`**: three whole 2026-08-06 batches (38 rows + 2 negates) silently never landed in Amazon; column added, rows marked `FAILED_UPLOAD` (migration `2026-08-08_upload_status_failed_batches.sql`), all analytical consumers switched to the filtered view. Audit artifacts in `.tmp/` (re-upload XLSX + 582-row classification). |


## Launch-negatives backfill (tools/backfill_campaign_negatives.py)

New campaigns ship with no negative keywords. `tools/backfill_campaign_negatives.py` regenerates a catch-up bulksheet (ENABLED SP campaigns created after 2026-01-03; defense campaigns and SB excluded) from the curated family lists in `V_PRODUCT_PHRASE_NEGATIVES`. Two guards run before a row is emitted:

1. **Already-negated exclusion** — "already negated" = the frozen Fivetran snapshot `V_SRC_AmazonAds_negative_keyword` (sync frozen 2026-01-03, last update 2025-12-31) UNION the warehouse-owned `DE_NEGATIVE_KEYWORDS` registry (the authority since the freeze). Any enabled (campaign, term) pair in that union — either level, any match type — is skipped, so the sheet neither re-adds existing negatives nor misses ones added since the freeze.
2. **Own-keyword conflict guard** — a negative phrase contained as a contiguous word sequence inside one of the campaign's own ENABLED bidded keywords (`DIM_KEYWORD`, `is_current`) is dropped and printed under "Own-keyword conflicts dropped", since uploading it would block the campaign's own targeting.

Output goes to `.tmp/` and is prepare-only — never auto-uploaded. Regenerate fresh immediately before any upload (the sheet goes stale as campaigns and negations change), and review the conflict list plus any negative that blocks a term with historical orders before uploading.
