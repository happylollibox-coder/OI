# Weekly Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guided one-screen "Weekly Run" page that walks Ori family-by-family through approve → queue actions → export bulksheet → mark done, with durable per-(family×week) status and opportunity-ordered sequencing.

**Architecture:** Backend state machine (`DE_WEEKLY_RUN` table + `V_WEEKLY_RUN` view + 3 Flask endpoints, copying the existing escalation-ack pattern). Frontend `WeeklyRunPage` composes the existing plan rollup, benchmark, DecisionCards, and bulksheet export — scoped to one family — with a left run-queue and a 4-step stepper.

**Tech Stack:** BigQuery Standard SQL; Flask (data-entry-app) + BigQuery client; React 19 + TS + Tailwind (dashboard-react); Cube.js (read path); deploy via `bq query`, `gcloud builds submit` (Flask), `gcloud run deploy` (dashboard/cube).

**Validation note:** This codebase validates SQL by deploying + `bq query` checks, Flask by `py_compile` + endpoint probe, frontend by `npm run build` + preview eval (no pytest-per-view / no Amazon write). Steps follow that established pattern.

---

### Task 1: `DE_WEEKLY_RUN` table

**Files:**
- Create: `scripts/bigquery/tables/DE/DE_WEEKLY_RUN.sql`

- [ ] **Step 1: Write the DDL**

```sql
-- DE_WEEKLY_RUN — per-(family × week) status for the Weekly Run workflow (Coacher D surface).
-- One row per Ori action (APPROVE / DONE); V_WEEKLY_RUN reads the latest per (family, week).
-- All-logic-in-backend: workflow status lives here, not in the frontend.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_WEEKLY_RUN` (
  parent_name    STRING NOT NULL,   -- family
  week_start     DATE   NOT NULL,   -- Sunday week start (matches DE_WEEKLY_PLAN)
  status         STRING,            -- 'APPROVED' | 'DONE'
  approved_at    TIMESTAMP,
  done_at        TIMESTAMP,
  note           STRING,
  actions_queued INT64,
  updated_at     TIMESTAMP,
  updated_by     STRING
);
```

- [ ] **Step 2: Deploy + verify it exists**

Run: `bq query --use_legacy_sql=false < scripts/bigquery/tables/DE/DE_WEEKLY_RUN.sql`
Then: `bq query --use_legacy_sql=false 'SELECT COUNT(*) AS n FROM \`onyga-482313.OI.DE_WEEKLY_RUN\`'`
Expected: returns `n = 0` (table exists, empty).

- [ ] **Step 3: Register in config.yaml**

Add `DE_WEEKLY_RUN` under the data-entry tables section of `config.yaml` (match the format of the neighbouring `DE_` entries).

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/tables/DE/DE_WEEKLY_RUN.sql config.yaml
git commit -m "feat(weekly-run): DE_WEEKLY_RUN status table"
```

---

### Task 2: `V_WEEKLY_RUN` view

**Files:**
- Create: `scripts/bigquery/views/V_WEEKLY_RUN.sql`

- [ ] **Step 1: Write the view**

```sql
-- V_WEEKLY_RUN — one row per current-week family: plan summary + escalation + run status +
-- opportunity_score (orders the Weekly Run). Coacher D surface. Served fresh by Flask.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_RUN` AS
WITH cur AS (
  SELECT DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(SUNDAY)) AS wk
),
plan AS (   -- current-week per-family plan rollup
  SELECT parent_name, week_start, cells, scale_cells, planned_spend, forward_ads_net, purposes
  FROM `onyga-482313.OI.V_WEEKLY_PLAN_PRODUCT`
  WHERE horizon = 'CURRENT'
),
esc AS (    -- escalation per family (worst severity + its net)
  SELECT parent_name,
         MAX(CASE UPPER(severity) WHEN 'ESCALATE' THEN 2 WHEN 'WATCH' THEN 1 ELSE 0 END) AS sev_rank,
         MIN(actual_net) AS escalation_net
  FROM `onyga-482313.OI.V_PLAN_ESCALATION`
  GROUP BY parent_name
),
run AS (    -- latest run status per (family, week)
  SELECT parent_name, week_start, status, approved_at, done_at, note
  FROM `onyga-482313.OI.DE_WEEKLY_RUN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name, week_start ORDER BY updated_at DESC) = 1
)
SELECT
  p.parent_name,
  CAST(p.week_start AS STRING) AS week_start,
  COALESCE(r.status, 'PENDING') AS status,
  CAST(r.approved_at AS STRING) AS approved_at,
  CAST(r.done_at AS STRING)     AS done_at,
  r.note,
  p.cells, p.scale_cells, p.planned_spend, p.forward_ads_net, p.purposes,
  (e.sev_rank IS NOT NULL) AS has_escalation,
  CASE e.sev_rank WHEN 2 THEN 'ESCALATE' WHEN 1 THEN 'WATCH' ELSE NULL END AS escalation_severity,
  e.escalation_net,
  ROUND(COALESCE(p.forward_ads_net, 0) + GREATEST(-COALESCE(e.escalation_net, 0), 0), 2) AS opportunity_score
FROM plan p
LEFT JOIN esc e ON e.parent_name = p.parent_name
LEFT JOIN run r ON r.parent_name = p.parent_name AND r.week_start = p.week_start
ORDER BY opportunity_score DESC
```

- [ ] **Step 2: Deploy + verify**

Run: `bq query --use_legacy_sql=false < scripts/bigquery/views/V_WEEKLY_RUN.sql`
Then: `bq query --use_legacy_sql=false --format=pretty 'SELECT parent_name, status, forward_ads_net, escalation_net, opportunity_score FROM \`onyga-482313.OI.V_WEEKLY_RUN\` ORDER BY opportunity_score DESC'`
Expected: one row per current-week family (6), all `status='PENDING'`, ordered by `opportunity_score` desc.

- [ ] **Step 3: Verify status reflects a row**

Run an insert + recheck, then clean up:
```bash
bq query --use_legacy_sql=false "INSERT INTO \`onyga-482313.OI.DE_WEEKLY_RUN\` (parent_name,week_start,status,approved_at,updated_at,updated_by) VALUES ('LolliME', DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'),WEEK(SUNDAY)), 'APPROVED', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'test')"
bq query --use_legacy_sql=false "SELECT parent_name,status FROM \`onyga-482313.OI.V_WEEKLY_RUN\` WHERE parent_name='LolliME'"   # expect APPROVED
bq query --use_legacy_sql=false "DELETE FROM \`onyga-482313.OI.DE_WEEKLY_RUN\` WHERE updated_by='test'"
```
Expected: LolliME shows `APPROVED`, then cleanup removes it.

- [ ] **Step 4: Register in config.yaml + commit**

```bash
git add scripts/bigquery/views/V_WEEKLY_RUN.sql config.yaml
git commit -m "feat(weekly-run): V_WEEKLY_RUN view (status + opportunity ordering)"
```

---

### Task 3: Flask endpoints (GET run + approve + done)

**Files:**
- Modify: `data-entry-app/app.py` (add after the existing `api_coach_escalation_action` block — search `def api_coach_escalation_action`)

- [ ] **Step 1: Add the three endpoints**

Insert after the escalation-action route:

```python
# ─── Coacher: Weekly Run — per-family×week workflow status (approve / done) ──
WEEKLY_RUN_TABLE = f"{PROJECT_ID}.{DATASET_ID}.DE_WEEKLY_RUN"

@cache_result(ttl_seconds=60)
def _get_weekly_run():
    query = f"""
        SELECT parent_name, week_start, status, approved_at, done_at, note,
               cells, scale_cells, planned_spend, forward_ads_net, purposes,
               has_escalation, escalation_severity, escalation_net, opportunity_score
        FROM `{PROJECT_ID}.{DATASET_ID}.V_WEEKLY_RUN`
        ORDER BY opportunity_score DESC
    """
    return [dict(row) for row in client.query(query).result()]

@app.route('/api/coach/weekly-run', methods=['GET'])
@login_required
def api_coach_weekly_run():
    try:
        return jsonify({'success': True, 'data': _get_weekly_run()})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

def _weekly_run_upsert(data, new_status):
    parent = data.get('parent_name')
    week_start = data.get('week_start')
    if not parent or not week_start:
        return None, 'parent_name and week_start required'
    now = datetime.utcnow().isoformat()
    row = {
        'parent_name': parent, 'week_start': week_start, 'status': new_status,
        'approved_at': now if new_status in ('APPROVED', 'DONE') else None,
        'done_at': now if new_status == 'DONE' else None,
        'note': (data.get('note') or None),
        'actions_queued': int(data.get('actions_queued', 0) or 0),
        'updated_at': now, 'updated_by': session.get('user', {}).get('email', 'dashboard'),
    }
    job_config = bigquery.LoadJobConfig(write_disposition=bigquery.WriteDisposition.WRITE_APPEND)
    job = client.load_table_from_json([row], WEEKLY_RUN_TABLE, job_config=job_config)
    job.result()
    return job.errors, None

@app.route('/api/coach/weekly-run/approve', methods=['POST'])
@login_required
def api_coach_weekly_run_approve():
    try:
        errors, err = _weekly_run_upsert(request.get_json() or {}, 'APPROVED')
        if err: return jsonify({'success': False, 'error': err}), 400
        if errors: return jsonify({'success': False, 'error': str(errors)}), 500
        clear_cache('_get_weekly_run')
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/coach/weekly-run/done', methods=['POST'])
@login_required
def api_coach_weekly_run_done():
    try:
        errors, err = _weekly_run_upsert(request.get_json() or {}, 'DONE')
        if err: return jsonify({'success': False, 'error': err}), 400
        if errors: return jsonify({'success': False, 'error': str(errors)}), 500
        clear_cache('_get_weekly_run')
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
```

- [ ] **Step 2: Compile-check**

Run: `cd data-entry-app && /usr/bin/python3 -m py_compile app.py && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add data-entry-app/app.py
git commit -m "feat(weekly-run): Flask GET/approve/done endpoints"
```

---

### Task 4: dataEntry client methods + types

**Files:**
- Modify: `dashboard-react/src/utils/dataEntry.ts` (add types near `CoachEscalationRow`; add methods near `getCoachEscalations`)

- [ ] **Step 1: Add the types**

```ts
export interface WeeklyRunRow {
  parent_name: string;
  week_start: string;
  status: 'PENDING' | 'APPROVED' | 'DONE';
  approved_at: string | null;
  done_at: string | null;
  note: string | null;
  cells: number; scale_cells: number; planned_spend: number;
  forward_ads_net: number | null; purposes: string;
  has_escalation: boolean; escalation_severity: string | null; escalation_net: number | null;
  opportunity_score: number;
}
export interface WeeklyRunActionInput {
  parent_name: string; week_start: string; note?: string; actions_queued?: number;
}
```

- [ ] **Step 2: Add the client methods (after `postEscalationAction`)**

```ts
  getWeeklyRun: async (): Promise<WeeklyRunRow[]> => {
    const r = await json<{ success?: boolean; data?: WeeklyRunRow[] }>('/api/coach/weekly-run', { method: 'GET' });
    return Array.isArray(r) ? r : (r.data ?? []);
  },
  approveWeeklyRun: (b: WeeklyRunActionInput) =>
    json<{ success: boolean }>('/api/coach/weekly-run/approve', { method: 'POST', body: JSON.stringify(b) }),
  doneWeeklyRun: (b: WeeklyRunActionInput) =>
    json<{ success: boolean }>('/api/coach/weekly-run/done', { method: 'POST', body: JSON.stringify(b) }),
```

- [ ] **Step 3: Build-check**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run build 2>&1 | grep -E "error TS|✓ built"`
Expected: `✓ built` (no errors).

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/utils/dataEntry.ts
git commit -m "feat(weekly-run): dataEntry client methods + types"
```

---

### Task 5: Page scaffold + routing + left run-queue rail

**Files:**
- Create: `dashboard-react/src/pages/WeeklyRunPage.tsx`
- Modify: `dashboard-react/src/types.ts` (PageId union — add `'weeklyrun'`)
- Modify: `dashboard-react/src/App.tsx` (lazy import + `case 'weeklyrun'`)
- Modify: `dashboard-react/src/hooks/useViewMode.tsx` (`USER_VISIBLE_PAGES` += `'weeklyrun'`)
- Modify: `dashboard-react/src/hooks/data/pageDatasets.ts` (`weeklyrun: []`)
- Modify: `dashboard-react/src/components/Sidebar.tsx` (nav item "WEEKLY RUN", icon `ListChecks` from lucide, under OVERVIEW after THIS WEEK)

- [ ] **Step 1: Add routing wiring**

Mirror the existing `'thisweek'` wiring exactly (it's the precedent added this session): add `'weeklyrun'` to the `PageId` union in `types.ts`, to `USER_VISIBLE_PAGES` in `useViewMode.tsx`, `weeklyrun: []` in `pageDatasets.ts`, a lazy import + `case 'weeklyrun': return <WeeklyRunPage />;` in `App.tsx`, and a Sidebar nav button (copy the THIS WEEK item, label "WEEKLY RUN", icon `ListChecks`).

- [ ] **Step 2: Create the page with rail only (selected-family logic stubbed)**

```tsx
import { useCallback, useEffect, useState } from 'react';
import { dataEntry, type WeeklyRunRow } from '../utils/dataEntry';
import { fM } from '../utils';

const fmtDay = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  return (y && m && d) ? new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : ds || '';
};
const weekRange = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return '';
  const end = new Date(y, m - 1, d + 6);
  return `${fmtDay(ds)} – ${end.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
};
const statusChip = (s: string) =>
  s === 'DONE' ? { label: '✓✓ Done', cls: 'text-emerald-400' }
  : s === 'APPROVED' ? { label: '✓ Approved', cls: 'text-blue-400' }
  : { label: '○ Pending', cls: 'text-muted' };

export function WeeklyRunPage() {
  const [rows, setRows] = useState<WeeklyRunRow[]>([]);
  const [sel, setSel] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    try { const r = await dataEntry.getWeeklyRun(); setRows(r); setSel(s => s ?? r[0]?.parent_name ?? null); }
    catch (e) { setErr(String(e)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const week = rows[0]?.week_start ?? '';
  const doneCount = rows.filter(r => r.status === 'DONE').length;
  const current = rows.find(r => r.parent_name === sel) ?? null;

  if (loading) return <div className="p-6 text-muted">Loading…</div>;
  if (err) return <div className="p-6 text-red-400">Couldn't load Weekly Run: {err}</div>;

  return (
    <div className="max-w-5xl mx-auto px-4 py-6 text-text">
      <div className="flex items-baseline justify-between mb-4">
        <h1 className="text-title font-medium">Weekly Run{week ? <span className="text-muted font-normal"> · {weekRange(week)}</span> : ''}</h1>
        <span className="text-label text-muted">{doneCount} of {rows.length} done</span>
      </div>
      <div className="flex gap-6">
        <aside className="w-56 shrink-0 flex flex-col gap-1">
          {rows.map(r => {
            const c = statusChip(r.status);
            return (
              <button key={r.parent_name} onClick={() => setSel(r.parent_name)}
                className={`text-left px-3 py-2 rounded-lg border ${sel === r.parent_name ? 'border-blue-500/50 bg-blue-500/5' : 'border-border hover:bg-white/5'}`}>
                <div className="flex items-center justify-between">
                  <span className="font-medium text-body">{r.parent_name}</span>
                  {r.has_escalation && <span className="text-red-400 text-[9px]">●</span>}
                </div>
                <div className="flex items-center justify-between text-label">
                  <span className={c.cls}>{c.label}</span>
                  <span className="text-faint font-mono">{fM(r.opportunity_score)}</span>
                </div>
              </button>
            );
          })}
        </aside>
        <main className="flex-1 min-w-0">
          {current ? <div className="text-muted">Selected: {current.parent_name} (stepper in next tasks)</div>
                   : <div className="text-muted">Pick a family.</div>}
        </main>
      </div>
    </div>
  );
}
export default WeeklyRunPage;
```

- [ ] **Step 3: Build + preview-verify the rail**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run build 2>&1 | grep -E "error TS|✓ built"`
Then in the preview: navigate to WEEKLY RUN; confirm the rail lists 6 families ordered by opportunity desc, each with a status chip + opportunity $, and the header shows the week range + "0 of 6 done". (Escalations require deployed Flask; locally the GET may 404 → rail empty is acceptable until deploy.)

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/pages/WeeklyRunPage.tsx dashboard-react/src/types.ts dashboard-react/src/App.tsx dashboard-react/src/hooks/useViewMode.tsx dashboard-react/src/hooks/data/pageDatasets.ts dashboard-react/src/components/Sidebar.tsx
git commit -m "feat(weekly-run): page scaffold + routing + run-queue rail"
```

---

### Task 6: Stepper — Plan step + Approve

**Files:**
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx`
- Read first: `dashboard-react/src/pages/ThisWeekPage.tsx` (for the plan rollup + `BenchCell` rendering to mirror, family-filtered via `CoachWeeklyPlanProduct.parentName` / `CoachWeeklyBenchmark.parentName` equals filter)

- [ ] **Step 1: Add a `<FamilyStepper>` section in the main panel**

Render, for `current`, a vertical stepper. Step 1 = **Plan**: load `CoachWeeklyPlanProduct` + `CoachWeeklyBenchmark` filtered to `current.parent_name` (cubeLoad with a `parentName equals` filter), render the same plan summary + `BenchCell` columns This Week uses. Footer button:

```tsx
<button
  disabled={busy}
  onClick={async () => {
    setBusy(true);
    try { await dataEntry.approveWeeklyRun({ parent_name: current.parent_name, week_start: current.week_start }); await load(); }
    finally { setBusy(false); }
  }}
  className="px-3 py-1.5 rounded-md border border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10 disabled:opacity-50">
  {current.status === 'PENDING' ? 'Approve plan' : '✓ Approved'}
</button>
```

Add `const [busy, setBusy] = useState(false);` to the component.

- [ ] **Step 2: Build + preview-verify**

Build, then in preview select a family → confirm the Plan step shows its plan + benchmark; click **Approve plan** → the rail chip flips to `✓ Approved` (after `load()` re-fetch). Requires deployed Flask for the write to persist; locally verify the UI renders + the button calls the endpoint (network tab).

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/WeeklyRunPage.tsx
git commit -m "feat(weekly-run): Plan step + Approve"
```

---

### Task 7: Stepper — Actions step + Queue all

**Files:**
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx`
- Read first: `dashboard-react/src/pages/ActionsPage.tsx` + `dashboard-react/src/components/Actions/DecisionCard.tsx` + `dashboard-react/src/hooks/useDoQueue` — to get the exact data hook that yields a family's decision rows and the queue API (`onQueue` / `addToQueue`).

- [ ] **Step 1: Render the family's DecisionCards**

In Step 2 = **Actions**: reuse the same data source ActionsPage uses, filtered to `current.parent_name`; render each as the existing `<DecisionCard>` (pass the same props ActionsPage passes — `action`, `family`, `why`, `opp`, `inQueue`, `onQueue`, etc.). Add a **[Queue all]** button that calls the queue-add for every shown card, and capture the count into `actions_queued` for the Done step.

- [ ] **Step 2: Build + preview-verify**

Build; in preview, select a family → Actions step lists that family's cards; **Queue all** adds them to the Do queue (verify the queue count rises / cards show "Queued ✓").

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/WeeklyRunPage.tsx
git commit -m "feat(weekly-run): Actions step + Queue all"
```

---

### Task 8: Stepper — Upload + Done + auto-advance

**Files:**
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx`
- Read first: `dashboard-react/src/pages/DoPage.tsx` (the `exportBulksheet` function / `V_COACH_APPLY` path) to reuse the export, scoped to the family's queued rows.

- [ ] **Step 1: Upload + Done steps**

Step 3 = **Upload**: a **[Export bulksheet]** button that calls the existing Do export for the family's queued rows. Step 4 = **Done**: a note input + **[Mark done — uploaded to Amazon]**:

```tsx
<button
  disabled={busy}
  onClick={async () => {
    setBusy(true);
    try {
      await dataEntry.doneWeeklyRun({ parent_name: current.parent_name, week_start: current.week_start, note: note || undefined, actions_queued: queuedCount });
      const fresh = await dataEntry.getWeeklyRun(); setRows(fresh);
      const next = fresh.find(r => r.status !== 'DONE'); setSel(next ? next.parent_name : current.parent_name);
    } finally { setBusy(false); }
  }}
  className="px-3 py-1.5 rounded-md border border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10 disabled:opacity-50">
  Mark done — uploaded to Amazon
</button>
```

Add `const [note, setNote] = useState('');` and track `queuedCount`. When every row is `DONE`, render "Week complete 🎉" in the main panel.

- [ ] **Step 2: Build + preview-verify**

Build; in preview, walk a family Approve → Queue → Export → **Mark done** → confirm the rail chip flips to `✓✓ Done`, the "done" count rises, and selection auto-advances to the next pending family. Mark all → "Week complete 🎉".

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/WeeklyRunPage.tsx
git commit -m "feat(weekly-run): Upload + Done + auto-advance"
```

---

### Task 9: Deploy + end-to-end verification

- [ ] **Step 1: Deploy backend + services**

```bash
cd /Users/ori/Develop/OI/data-entry-app && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" gcloud builds submit --config cloudbuild.yaml --project=onyga-482313 .
cd /Users/ori/Develop/OI/dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" gcloud run deploy oi-dashboard --source . --project=onyga-482313 --region=us-central1 --allow-unauthenticated --clear-base-image --set-build-env-vars "VITE_CUBE_API_URL=https://cube-api-405291422506.us-central1.run.app,VITE_DATA_ENTRY_URL=https://data-entry-forms-405291422506.us-central1.run.app" --memory=256Mi --cpu=1 --timeout=60 --quiet
```
(View + table already deployed in Tasks 1–2; no cube change.)

- [ ] **Step 2: Verify prod endpoints up**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://data-entry-forms-405291422506.us-central1.run.app/api/coach/weekly-run   # 401 = up (auth-gated)
curl -s -o /dev/null -w "%{http_code}\n" https://oi-dashboard-405291422506.us-central1.run.app/                            # 200
```

- [ ] **Step 3: Live walk-through (Ori's authed browser)**

Confirm on prod: WEEKLY RUN nav present; rail ordered by opportunity; Approve → ✓; Queue all; Export bulksheet; Mark done → ✓✓ + auto-advance; status persists across reload.

- [ ] **Step 4: Update memory**

Append to `project_coacher_weekly_plan` memory: Weekly Run page shipped (DE_WEEKLY_RUN + V_WEEKLY_RUN + 3 endpoints + WeeklyRunPage; opportunity = forward SCALE net + |escalated loss|; PENDING→APPROVED→DONE per family×week, weekly reset).

---

## Self-Review

**Spec coverage:** state machine (Task 1/2/3), `DE_WEEKLY_RUN` (T1), `V_WEEKLY_RUN` + opportunity (T2), endpoints (T3), dataEntry (T4), page+rail+routing (T5), Plan+Approve (T6), Actions+Queue (T7), Upload+Done+auto-advance (T8), deploy+verify (T9). All spec sections covered.

**Placeholder scan:** Tasks 6–8 reference reused components by file + the exact props/functions to read first, with concrete wiring code for the new parts (buttons, endpoint calls, auto-advance) — the "read first" steps are real actions, not placeholders, because the reused component APIs (DecisionCard props, DoPage export, useDoQueue) must be read from source to wire exactly. Backend tasks (1–4) and the rail (5) have complete code.

**Type consistency:** `WeeklyRunRow` fields match `V_WEEKLY_RUN` SELECT (status, opportunity_score, forward_ads_net, escalation_*, etc.); `approveWeeklyRun`/`doneWeeklyRun` take `WeeklyRunActionInput` (parent_name, week_start, note?, actions_queued?) matching the Flask `_weekly_run_upsert` body; `'PENDING'|'APPROVED'|'DONE'` consistent across SQL default, TS type, and chip logic.
