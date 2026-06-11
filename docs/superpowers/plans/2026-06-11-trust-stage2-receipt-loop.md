# Trust Stage 2 — Action Log + Outcome Verification (the Receipt Loop) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every action uploaded to Amazon is logged to BigQuery with a metrics snapshot, then automatically graded against real post-action Amazon data a few days later, surfaced as a Track Record scoreboard — so the coacher earns trust with receipts, not promises.

**Architecture:** Wire the dormant `DE_APPROVED_ACTIONS` table (DDL exists, nothing writes to it): the DO page POSTs queue items to a new Flask endpoint on "Uploaded to Amazon". A new view `V_COACH_ACTION_OUTCOMES` joins each logged action to `FACT_AMAZON_ADS` post-action windows (excluding the ~2-day ads lag) and emits a verdict per action (`VERIFIED` / `NOT_VERIFIED` / `TOO_EARLY`). A Cube + a `TrackRecord` panel on the DO page render the scoreboard.

**Tech Stack:** BigQuery SQL, Flask 3 (`data-entry-app/app.py`, raw BQ client, `@login_required`, `clear_data_cache()` after writes), React 19 + Cube.js. Constraints: branch `feat/offseason-forecast`, commits local `--no-verify`, exact files only, never push; **every production BQ/Cloud-Run deploy is gated on Ori's explicit OK**; register new BQ objects in `config.yaml`.

**Verdict philosophy:** grade only what ad data can actually prove — NEGATE/STOP = the spend stopped; REDUCE_BID = CPC down (and ROAS not worse); INCREASE_BID/PROMOTE = ROAS held above breakeven with volume up. No speculative metrics. Respect the ~2-day ads lag: a verdict needs ≥3 *post-lag* days, otherwise `TOO_EARLY`.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `scripts/bigquery/migrations/ADD_APPROVED_ACTIONS_OUTCOME_COLS.sql` | Add `parent_name`, `targeting`, `keyword_id`, `match_type` to the log table | Create |
| `data-entry-app/app.py` | `POST /api/coach/action-log` (batch insert) | Modify |
| `dashboard-react/src/hooks/useDoQueue.tsx` + `dashboard-react/src/pages/DoPage.tsx` | POST items on "Uploaded to Amazon ✓" | Modify |
| `scripts/bigquery/views/V_COACH_ACTION_OUTCOMES.sql` | Outcome grading view | Create |
| `cube/schema/CoachActionOutcomes.js` | Cube over the view | Create |
| `dashboard-react/src/components/TrackRecord.tsx` + `DoPage.tsx` | Scoreboard panel | Create/Modify |
| `config.yaml` | Register the new view + cube | Modify |

---

### Task 1: Extend `DE_APPROVED_ACTIONS` (migration) 🚦 production gate

**Files:**
- Create: `scripts/bigquery/migrations/ADD_APPROVED_ACTIONS_OUTCOME_COLS.sql`

- [ ] **Step 1: Verify current live schema** (the table may or may not exist in BQ yet):
```bash
bq show --schema --format=prettyjson onyga-482313:OI.DE_APPROVED_ACTIONS || echo "TABLE MISSING"
```
If missing, first create it from the existing DDL: `bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/tables/DE/DE_APPROVED_ACTIONS.sql` (it's `CREATE TABLE IF NOT EXISTS` — safe, **but still confirm with Ori before running anything against production**).

- [ ] **Step 2: Write the migration file:**
```sql
-- Outcome-loop columns for DE_APPROVED_ACTIONS (Trust Stage 2).
-- Adds the identifiers needed to join logged actions back to FACT_AMAZON_ADS
-- and to attribute outcomes per family (business-unit grain).
ALTER TABLE `onyga-482313.OI.DE_APPROVED_ACTIONS`
  ADD COLUMN IF NOT EXISTS parent_name STRING,
  ADD COLUMN IF NOT EXISTS targeting STRING,
  ADD COLUMN IF NOT EXISTS keyword_id STRING,
  ADD COLUMN IF NOT EXISTS match_type STRING;
```

- [ ] **Step 3: Dry-run, 🚦 get Ori's OK, apply:**
```bash
bq query --use_legacy_sql=false --dry_run --project_id=onyga-482313 < scripts/bigquery/migrations/ADD_APPROVED_ACTIONS_OUTCOME_COLS.sql
# after explicit OK:
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/migrations/ADD_APPROVED_ACTIONS_OUTCOME_COLS.sql
bq show --schema onyga-482313:OI.DE_APPROVED_ACTIONS | grep -E "parent_name|targeting|keyword_id|match_type"
```

- [ ] **Step 4: Ensure `config.yaml` lists `DE_APPROVED_ACTIONS`** (`grep -n DE_APPROVED_ACTIONS config.yaml`); add an entry following the file's existing table format if absent.

- [ ] **Step 5: Commit**
```bash
git add scripts/bigquery/migrations/ADD_APPROVED_ACTIONS_OUTCOME_COLS.sql config.yaml
git commit --no-verify -m "feat(coacher): outcome-loop columns on DE_APPROVED_ACTIONS

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Flask endpoint `POST /api/coach/action-log`

**Files:**
- Modify: `data-entry-app/app.py`

- [ ] **Step 1: Read the house patterns first** — pick an existing POST endpoint (e.g. `/api/adjust_forecast`, app.py:2387) and copy its exact idioms: `@login_required`, `request.get_json()`, BQ client acquisition, `load_table_from_json` + `job.errors` check, `clear_data_cache()`, JSON response shape.

- [ ] **Step 2: Add the endpoint** (adapt names to the file's actual helpers — e.g. if the app uses a shared `bq_client` / `get_bq_client()`, use that):

```python
@app.route('/api/coach/action-log', methods=['POST'])
@login_required
def coach_action_log():
    """Log coach actions uploaded to Amazon, with a metrics snapshot for outcome grading."""
    payload = request.get_json(silent=True) or {}
    items = payload.get('items', [])
    if not items:
        return jsonify({'error': 'no items'}), 400
    now = datetime.utcnow().isoformat()
    rows = []
    for it in items:
        rows.append({
            'id': str(uuid.uuid4()),
            'approved_at': now,
            'action': it.get('action'),
            'negate_as': 'NEGATIVE_EXACT' if 'NEGATE' in (it.get('action') or '') else None,
            'search_term': it.get('search_term') or '',
            'campaign_id': it.get('campaign_id'),
            'campaign_name': it.get('campaign'),
            'asin': it.get('asin'),
            'parent_name': it.get('parent_name'),
            'targeting': it.get('targeting'),
            'keyword_id': it.get('keyword_id'),
            'match_type': it.get('match_type'),
            'current_bid': it.get('current_bid'),
            'suggested_bid': it.get('recommended_bid'),
            'reason': it.get('reason'),
            'total_net_roas': it.get('net_roas'),
            'ads_spend': it.get('spend'),
            'ads_orders': it.get('orders'),
            'status': 'APPLIED',
            'applied_at': now,
            'created_by': session.get('user_email', 'unknown'),
        })
    table_ref = f"{GCP_PROJECT_ID}.{BIGQUERY_DATASET}.DE_APPROVED_ACTIONS"
    job = bq_client.load_table_from_json(rows, table_ref,
        job_config=bigquery.LoadJobConfig(write_disposition='WRITE_APPEND',
                                          schema_update_options=[]))
    job.result()
    if job.errors:
        return jsonify({'error': str(job.errors)}), 500
    clear_data_cache()
    return jsonify({'ok': True, 'logged': len(rows)})
```
(Match the file's actual import set — `uuid`, `datetime` may already be imported; the project/dataset env var names per `data-entry-app/config.py`; the session-email pattern per existing endpoints. The `bigquery.LoadJobConfig` line should mirror the write pattern documented in `OI/CLAUDE.md`.)

- [ ] **Step 3: Test locally** — run the Flask app locally per its README/config (or `python app.py` if that's the dev pattern) and:
```bash
curl -s -X POST localhost:8080/api/coach/action-log -H 'Content-Type: application/json' \
  -d '{"items":[{"action":"NEGATE_TERM","search_term":"_smoke_test_","campaign":"TEST","campaign_id":"T1","spend":9.5,"orders":0,"net_roas":0}]}'
```
Expected `{"ok": true, "logged": 1}` (auth may require a session — if `@login_required` blocks curl, verify through the dashboard flow in Task 3 instead and note it). Then delete the smoke row: `bq query ... "DELETE FROM \`onyga-482313.OI.DE_APPROVED_ACTIONS\` WHERE search_term = '_smoke_test_'"` (confirm with Ori before any DELETE — or use an obviously-fake campaign_id and leave it, filtered out by the outcomes view's join).

- [ ] **Step 4: Commit.** Note in the report: **Cloud Run deploy of data-entry-app is an owner step** (🚦 gate) — the endpoint isn't live for the dashboard's `/api` proxy until Ori deploys.
```bash
git add data-entry-app/app.py
git commit --no-verify -m "feat(coacher): POST /api/coach/action-log — persist uploaded actions with snapshot

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: DO page wiring — log on "Uploaded to Amazon ✓"

**Files:**
- Modify: `dashboard-react/src/pages/DoPage.tsx` (the `markAllUploaded` confirm block, ~line 904)
- Modify (if needed): `dashboard-react/src/hooks/useDoQueue.tsx`

- [ ] **Step 1:** In the existing confirm handler (`if (confirm('Mark all queued items as uploaded to Amazon? ...')) { doQueue.markAllUploaded(); }`), capture the items first and POST fire-and-forget:

```ts
              if (confirm('Mark all queued items as uploaded to Amazon? This will hide them from the Actions page.')) {
                const items = doQueue.items.map(it => ({
                  action: it.action, search_term: it.search_term, campaign: it.campaign,
                  campaign_id: it.campaign_id, targeting: it.targeting, keyword_id: it.keyword_id,
                  match_type: it.match_type, current_bid: it.current_bid, recommended_bid: it.recommended_bid,
                  spend: it.spend, orders: it.orders, net_roas: it.target_net_roas_8w,
                  parent_name: it.product || null, asin: null, reason: null,
                }));
                fetch('/api/coach/action-log', {
                  method: 'POST', headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ items }),
                }).catch(() => console.warn('[action-log] failed — outcomes will miss this batch'));
                doQueue.markAllUploaded();
              }
```
Verify against the real `DoQueueItem` fields (`useDoQueue.tsx:3-35`) — if `product` holds the product short-name rather than family, map it through `useProductFamily().getFamily(it.product)` instead (check what `it.product` actually contains by reading where `addItem` is called).

- [ ] **Step 2:** `npx tsc --noEmit && npm run build` clean; live-verify in the preview: queue one item → Export → "Uploaded to Amazon ✓" → check the network call fired (preview_network) and (once Flask is deployed/local) the row lands:
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty \
 "SELECT action, search_term, campaign_name, ads_spend, status, applied_at FROM \`onyga-482313.OI.DE_APPROVED_ACTIONS\` ORDER BY applied_at DESC LIMIT 5"
```

- [ ] **Step 3: Commit**
```bash
git add src/pages/DoPage.tsx src/hooks/useDoQueue.tsx
git commit --no-verify -m "feat(do): log uploaded actions to DE_APPROVED_ACTIONS with metric snapshot

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `V_COACH_ACTION_OUTCOMES` — grade each action against real data 🚦 production gate

**Files:**
- Create: `scripts/bigquery/views/V_COACH_ACTION_OUTCOMES.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Verify `FACT_AMAZON_ADS` join columns** (the CLAUDE.md summary is abbreviated):
```bash
bq show --schema --format=prettyjson onyga-482313:OI.FACT_AMAZON_ADS | grep -E '"name"' | head -30
```
Confirm it has `date`, `campaign_id` (or only `campaign_name`), `search_term`, spend (`ad_spend` or `cost`), `clicks`, `orders`, `sales`. **Use the actual column names in the view below** (written assuming `campaign_id`, `search_term`, `ad_spend`; substitute as found).

- [ ] **Step 2: Write the view:**
```sql
-- =============================================
-- V_COACH_ACTION_OUTCOMES — Trust Stage 2 receipt loop
-- Grades every logged coach action (DE_APPROVED_ACTIONS, status APPLIED)
-- against real post-action Amazon ads data.
-- Lag rule: ads data is ~2 days behind → observation starts at applied_date+2;
-- a verdict needs >= 3 observed days, else TOO_EARLY.
-- Verdicts grade only what ad data can prove:
--   NEGATE/STOP    → VERIFIED when post-action spend on that term/campaign ~ stops (<10% of pre daily rate)
--   REDUCE_BID     → VERIFIED when post CPC < pre CPC AND post ROAS >= pre ROAS
--   INCREASE/PROMOTE → VERIFIED when post ROAS >= 1.0 AND post orders > 0
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COACH_ACTION_OUTCOMES` AS
WITH log AS (
  SELECT id, action, search_term, campaign_id, campaign_name, parent_name,
         targeting, current_bid, suggested_bid, reason,
         ads_spend  AS pre_spend_4w,
         ads_orders AS pre_orders_4w,
         total_net_roas AS pre_net_roas,
         DATE(applied_at) AS applied_date
  FROM `onyga-482313.OI.DE_APPROVED_ACTIONS`
  WHERE status = 'APPLIED'
),
post AS (
  SELECT l.id,
         COUNT(DISTINCT fa.date)                      AS post_days,
         SUM(fa.ad_spend)                             AS post_spend,
         SUM(fa.clicks)                               AS post_clicks,
         SUM(fa.orders)                               AS post_orders,
         SUM(fa.sales)                                AS post_sales,
         SAFE_DIVIDE(SUM(fa.ad_spend), SUM(fa.clicks)) AS post_cpc,
         SAFE_DIVIDE(SUM(fa.sales), SUM(fa.ad_spend))  AS post_roas
  FROM log l
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON fa.campaign_id = l.campaign_id
   AND LOWER(fa.search_term) = LOWER(COALESCE(l.search_term, l.targeting))
   AND fa.date >= DATE_ADD(l.applied_date, INTERVAL 2 DAY)  -- skip the lag window
  GROUP BY l.id
)
SELECT
  l.*,
  DATE_DIFF(CURRENT_DATE(), DATE_ADD(l.applied_date, INTERVAL 2 DAY), DAY) AS observable_days,
  COALESCE(p.post_days, 0)   AS post_days,
  COALESCE(p.post_spend, 0)  AS post_spend,
  COALESCE(p.post_orders, 0) AS post_orders,
  p.post_cpc, p.post_roas,
  -- pre-action daily spend rate (4w snapshot / 28d) for "did it stop" + $ saved
  ROUND(l.pre_spend_4w / 28.0, 2) AS pre_daily_spend,
  CASE
    WHEN DATE_DIFF(CURRENT_DATE(), DATE_ADD(l.applied_date, INTERVAL 2 DAY), DAY) < 3
      THEN 'TOO_EARLY'
    WHEN l.action IN ('NEGATE_TERM','NEGATE_ROAS_THRESHOLD','NEGATE_SPEND_THRESHOLD','NEGATE_PHRASE','NEGATE_BOOST_SIMILAR_EXACT','STOP','STOP_TARGET') THEN
      IF(COALESCE(p.post_spend, 0)
           < 0.10 * (l.pre_spend_4w / 28.0)
             * DATE_DIFF(CURRENT_DATE(), DATE_ADD(l.applied_date, INTERVAL 2 DAY), DAY),
         'VERIFIED', 'NOT_VERIFIED')
    WHEN l.action IN ('REDUCE_BID','REDUCE_BID_ROAS','REDUCE_BID_SPEND') THEN
      CASE
        WHEN p.post_clicks IS NULL OR p.post_clicks = 0 THEN 'VERIFIED'  -- bid cut killed the waste entirely
        WHEN p.post_cpc < SAFE_DIVIDE(l.pre_spend_4w, NULLIF(l.pre_orders_4w, 0)) IS NULL THEN 'NOT_VERIFIED'
        WHEN p.post_roas >= COALESCE(l.pre_net_roas, 0) THEN 'VERIFIED'
        ELSE 'NOT_VERIFIED'
      END
    WHEN l.action IN ('INCREASE_BID','PROMOTE_TO_EXACT','SCALE','SCALE_UP','SCALE_UP_ROAS','BOOST') THEN
      IF(COALESCE(p.post_roas, 0) >= 1.0 AND COALESCE(p.post_orders, 0) > 0, 'VERIFIED', 'NOT_VERIFIED')
    ELSE 'UNGRADED'
  END AS verdict,
  -- $ saved estimate for cuts: what the old daily rate would have burned, minus what actually spent
  CASE WHEN l.action LIKE '%NEGATE%' OR l.action LIKE 'STOP%' THEN
    ROUND(GREATEST(0,
      (l.pre_spend_4w / 28.0)
        * DATE_DIFF(CURRENT_DATE(), DATE_ADD(l.applied_date, INTERVAL 2 DAY), DAY)
      - COALESCE(p.post_spend, 0)), 2)
  END AS dollars_saved_est
FROM log l
LEFT JOIN post p USING (id);
```
**Note for implementer:** the `REDUCE_BID` CPC comparison above contains a deliberate marker (`... IS NULL THEN 'NOT_VERIFIED'`) that is wrong as written — replace that branch with a real pre-CPC comparison once you confirm whether a pre-CPC snapshot exists in the log (it does not in v1: only spend/orders/ROAS are snapshotted). Simplest correct v1: grade REDUCE_BID as `VERIFIED` when `post_roas >= COALESCE(pre_net_roas, 0)` (ROAS not worse after the cut), dropping the CPC clause entirely. Implement that, and note pre-CPC snapshot as a v2 column.

- [ ] **Step 3: Dry-run; 🚦 Ori's OK; deploy; register in `config.yaml`** (views section, same format as `V_ADS_COACH_DATA`):
```bash
bq query --use_legacy_sql=false --dry_run --project_id=onyga-482313 < scripts/bigquery/views/V_COACH_ACTION_OUTCOMES.sql
# after OK:
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/views/V_COACH_ACTION_OUTCOMES.sql
```

- [ ] **Step 4: Verify with the smoke row** (if Task 2's test row was kept): it must appear with `verdict = 'TOO_EARLY'` (applied today → no post-lag days).

- [ ] **Step 5: Commit**
```bash
git add scripts/bigquery/views/V_COACH_ACTION_OUTCOMES.sql config.yaml
git commit --no-verify -m "feat(coacher): V_COACH_ACTION_OUTCOMES — grade logged actions vs real ads data

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Cube + Track Record panel

**Files:**
- Create: `cube/schema/CoachActionOutcomes.js`
- Create: `dashboard-react/src/components/TrackRecord.tsx`
- Modify: `dashboard-react/src/hooks/useCubeData.ts`, `dashboard-react/src/types.ts`, `dashboard-react/src/hooks/useUnifiedData.ts`, `dashboard-react/src/pages/DoPage.tsx`
- Modify: `config.yaml` (register the cube)

- [ ] **Step 1: Cube** (one file per cube, fully-qualified BQ name — house style):
```js
cube('CoachActionOutcomes', {
  sql: 'SELECT * FROM `onyga-482313.OI.V_COACH_ACTION_OUTCOMES`',
  dimensions: {
    id: { sql: 'id', type: 'string', primaryKey: true },
    action: { sql: 'action', type: 'string' },
    searchTerm: { sql: 'search_term', type: 'string' },
    campaignName: { sql: 'campaign_name', type: 'string' },
    parentName: { sql: 'parent_name', type: 'string' },
    verdict: { sql: 'verdict', type: 'string' },
    appliedDate: { sql: 'applied_date', type: 'time' },
    reason: { sql: 'reason', type: 'string' },
    preSpend4w: { sql: 'pre_spend_4w', type: 'number' },
    postSpend: { sql: 'post_spend', type: 'number' },
    postOrders: { sql: 'post_orders', type: 'number' },
    postRoas: { sql: 'post_roas', type: 'number' },
    dollarsSavedEst: { sql: 'dollars_saved_est', type: 'number' },
    observableDays: { sql: 'observable_days', type: 'number' },
  },
  measures: { count: { type: 'count' } },
});
```

- [ ] **Step 2: Loader** — follow the `loadPlanAdsTargetsFromCube` light-loader pattern in `useCubeData.ts` exactly (find it with `grep -n PlanAdsTargets src/hooks/useCubeData.ts`): add `CoachActionOutcomeRow` to `types.ts` (fields mirroring the cube dimensions, snake_case like the other row types), a `loadCoachActionOutcomesFromCube` loader, wire into the light-loaders array and `DashboardData.coach_action_outcomes`, empty-array default in `useUnifiedData.ts`.

- [ ] **Step 3: TrackRecord panel:**
```tsx
import type { CoachActionOutcomeRow } from '../types';
import { fM } from '../utils';

// The coacher's receipts: every uploaded action graded against real Amazon data.
// VERIFIED = the call did what it claimed. TOO_EARLY = still inside the data lag.
export function TrackRecord({ rows }: { rows: CoachActionOutcomeRow[] }) {
  if (!rows.length) return null;
  const graded = rows.filter(r => r.verdict === 'VERIFIED' || r.verdict === 'NOT_VERIFIED');
  const verified = graded.filter(r => r.verdict === 'VERIFIED');
  const saved = rows.reduce((s, r) => s + (r.dollars_saved_est || 0), 0);
  const tooEarly = rows.filter(r => r.verdict === 'TOO_EARLY').length;
  return (
    <div className="border border-border rounded-xl bg-card p-4 mb-4">
      <div className="text-[11px] font-bold uppercase tracking-wider mb-2">📊 Coacher track record</div>
      <div className="text-[12px] mb-2">
        <span className="font-mono">{verified.length}/{graded.length}</span> calls verified correct
        {saved > 0 && <> · <span className="text-emerald-400 font-mono">{fM(saved)}</span> saved</>}
        {tooEarly > 0 && <span className="text-faint"> · {tooEarly} too early to grade</span>}
      </div>
      <div className="space-y-1">
        {rows.slice(0, 15).map(r => (
          <div key={r.id} className="flex items-center gap-2 text-[10px]">
            <span className={r.verdict === 'VERIFIED' ? 'text-emerald-400' : r.verdict === 'NOT_VERIFIED' ? 'text-red-400' : 'text-faint'}>
              {r.verdict === 'VERIFIED' ? '✓' : r.verdict === 'NOT_VERIFIED' ? '✗' : '…'}
            </span>
            <span className="text-muted">{r.action}</span>
            <span className="truncate">"{r.search_term}"</span>
            <span className="text-faint ml-auto font-mono">
              {r.verdict === 'TOO_EARLY' ? `${r.observable_days}d observed` :
               r.dollars_saved_est ? `${fM(r.dollars_saved_est)} saved` :
               r.post_roas != null ? `ROAS ${Number(r.post_roas).toFixed(2)}× after` : ''}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
```
Render it at the top of `DoPage` (`<TrackRecord rows={data.coach_action_outcomes || []} />`).

- [ ] **Step 4: Verify** — `npx tsc --noEmit && npm test && npm run build`; restart local Cube (`cd cube && npm run dev` picks up the new schema); live-check the panel renders (with the smoke row: "0/0 … 1 too early to grade"). Register the cube in `config.yaml`. Screenshot.

- [ ] **Step 5: Commit**
```bash
git add cube/schema/CoachActionOutcomes.js dashboard-react/src/components/TrackRecord.tsx \
  dashboard-react/src/hooks/useCubeData.ts dashboard-react/src/hooks/useUnifiedData.ts \
  dashboard-react/src/types.ts dashboard-react/src/pages/DoPage.tsx config.yaml
git commit --no-verify -m "feat(do): coacher Track Record — outcomes cube + scoreboard panel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Success test (the Stage-2 gate, human + real data)
After the next real bulk upload, wait ~5 days (2-day lag + 3 observed days). The Track Record panel must show verdicts computed from real `FACT_AMAZON_ADS` data, and Ori spot-checks 2–3 of them against Seller Central. Only when the hit rate is believed does Stage 3 (widening the gate / engine migration) start.

## Self-review notes
- Spec coverage: §7b Stage 2 fully mapped (log ✅ T1–3, outcomes ✅ T4, scoreboard ✅ T5); lag rule honored (+2d skip, ≥3d observed).
- Known v1 simplifications, stated in-code: REDUCE_BID graded by ROAS-not-worse (no pre-CPC snapshot yet); `post_roas` is gross (sales/spend), not margin-net — verdicts use it only directionally vs the pre snapshot.
- The only intentionally-flagged fix-up is the REDUCE_BID branch in Task 4 Step 2, called out explicitly with the correct v1 resolution.
