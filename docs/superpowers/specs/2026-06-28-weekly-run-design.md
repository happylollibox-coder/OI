# Weekly Run — Family-by-Family Weekly Operating Loop

**Date:** 2026-06-28
**Status:** Design approved (pending spec review)
**Owner:** Ori

## Goal
A single guided page that lets Ori work his weekly coacher cycle **one family at a time**, with explicit gates and durable status: choose a family → review & **approve** its week plan → review & **queue** its actions → **export** the bulksheet (upload to Amazon manually) → **acknowledge done** → family flips to ✓✓ → auto-advance to the next family. Family is the correct business unit (own products, seasonality, P&L).

## Context (what already exists this session)
- **Plan (D):** `DE_WEEKLY_PLAN` → `V_WEEKLY_PLAN_PRODUCT` → `CoachWeeklyPlanProduct` cube (per-family forward SCALE net, purposes, planned spend). Weeks are **Sun–Sat** (`WEEK(SUNDAY)`), aligned to SQP/Home.
- **Benchmarks:** `V_WEEKLY_PRODUCT_BENCHMARK` → `CoachWeeklyBenchmark` (peak/off ads net + business net + halo).
- **Escalations (E):** `V_PLAN_ESCALATION_SURFACE` + `DE_COACH_ESCALATION_ACTION` + Flask `/api/coach/escalations` + `/api/coach/escalation-action` (ack/snooze). **This is the exact pattern to copy for run status.**
- **Actions:** `ActionsPage` / `DecisionCard` (coach decisions, Queue button, the `wk:` chip linking an action to its family's week target via `weekTargets.ts`).
- **Upload:** Do page bulksheet export from `V_COACH_APPLY` (prepare-only; manual upload — F-scope, no Amazon write API).
- **Family selector:** `FiltersProvider` (`filters.family`).

## Architecture (all logic in backend)
A per-**(family × week)** state machine:

```
PENDING ──(Approve)──▶ APPROVED ──(Mark done)──▶ DONE
```

Status is per Sun–Sat week. New week → plan regenerates → every family is `PENDING` again (a `DONE` row only exists for the week it was set).

### Data model — `DE_WEEKLY_RUN` (new DE table)
```
parent_name   STRING NOT NULL          -- family
week_start    DATE   NOT NULL          -- Sunday week start (matches DE_WEEKLY_PLAN)
status        STRING                   -- 'APPROVED' | 'DONE'
approved_at   TIMESTAMP
done_at       TIMESTAMP
note          STRING
actions_queued INT64                   -- count captured at done (audit; optional)
updated_at    TIMESTAMP
updated_by    STRING
```
One row per (family, week), upserted (load_table_from_json append; latest-by-`updated_at` wins in the view). PENDING = no row for that (family, week).

### View — `V_WEEKLY_RUN` (one row per family, current week)
For each family in the current-week plan (`V_WEEKLY_PLAN_PRODUCT` where `horizon='CURRENT'`), join:
- latest `DE_WEEKLY_RUN` row → `status` (default `'PENDING'`), `approved_at`, `done_at`, `note`
- `V_PLAN_ESCALATION` → `has_escalation`, max `severity`, `escalation_net` (the escalated actual_net)
- plan summary → `forward_ads_net`, `planned_spend`, `purposes`, `cells`, `scale_cells`

**opportunity_score** (orders the run, desc):
```
opportunity_score = COALESCE(forward_ads_net, 0)                 -- upside to capture
                  + GREATEST(-COALESCE(escalation_net, 0), 0)    -- downside to stop (abs loss)
```
"Net-profit dollars in play this week." Tunable — documented as the v1 definition.

### Flask endpoints (mirror the escalation pattern, `@login_required`)
- `GET  /api/coach/weekly-run` → `V_WEEKLY_RUN` rows (fresh, 60s cache cleared on write) — so an Approve/Done reflects on the next fetch.
- `POST /api/coach/weekly-run/approve` `{parent_name, week_start, note?}` → upsert `status='APPROVED'`, `approved_at=now`.
- `POST /api/coach/weekly-run/done` `{parent_name, week_start, note?, actions_queued?}` → upsert `status='DONE'`, `done_at=now`.

### Frontend — `WeeklyRunPage` (new page, sidebar nav "WEEKLY RUN")
Reads `GET /api/coach/weekly-run`.

**Left rail — run queue:** families ordered by `opportunity_score` desc. Each: status chip (`○ Pending` / `✓ Approved` / `✓✓ Done`), opportunity $, escalation dot if any. Header: *"Weekly Run · {weekRange} · {done}/{total} done"*. Clicking a family selects it.

**Main panel — selected family, 4-step stepper:**
1. **Plan** — family's plan rollup (`CoachWeeklyPlanProduct` filtered to `parentName`) + benchmark (`CoachWeeklyBenchmark` filtered). Button **[Approve plan]** → `approve` endpoint → status `APPROVED`.
2. **Actions** *(soft-gated: shown always, highlighted after Approve)* — the family's coach `DecisionCard`s (reuse the Actions data path filtered to `family`). **[Queue all]** adds them to the existing Do queue; per-card Queue still works.
3. **Upload** — **[Export bulksheet]** for the family's queued rows (reuse the Do/`V_COACH_APPLY` export, scoped to the family). Manual upload to Amazon.
4. **Done** — **[Mark done — uploaded to Amazon]** + optional note → `done` endpoint → status `DONE`.

On `DONE`: re-fetch; family flips to ✓✓; auto-select the next `PENDING` family with the highest opportunity. When all `DONE`: show "Week complete 🎉".

### Reuse (compose, don't rebuild)
| Step | Reuses |
|---|---|
| Plan + benchmark | This Week's plan table + `BenchCell` (extract to shared components, family-filtered) |
| Actions | `ActionsPage` decision data + `DecisionCard` (family-scoped) |
| Upload | Do page bulksheet export (`V_COACH_APPLY`, family-scoped) |
| Status writes | escalation-ack pattern (`DE_COACH_ESCALATION_ACTION` → `DE_WEEKLY_RUN`) |

## Gates & semantics (approved defaults)
- **Soft gates:** Approve guides to Actions but nothing is hard-locked; the stepper highlights the next step.
- **Weekly reset:** status is per-week; a new Sunday week starts everyone at `PENDING`.
- **"Actions relevant to this plan"** = all of that family's current coach actions (Actions filtered to the family).
- **Done = acknowledge only:** records "I uploaded"; does **not** call the Amazon write API (stays prepare-only / F-scope).
- **Re-open:** clicking Approve/Done again can re-set state (idempotent upsert); a family can be re-approved if the plan changes.

## Edge cases
- Family in plan but no actions → Actions step shows "No actions this week"; can still Approve + Done.
- Bunny/LolliBall (cut-only / tiny) → appear in the run with low opportunity; still workable.
- Escalated family not yet approved → escalation dot in the rail flags it; opportunity score lifts it up.
- Stale week: `V_WEEKLY_RUN` only surfaces the current week; old `DONE` rows are history.

## Out of scope (v1)
- No Amazon write-API push (manual upload stays).
- No multi-user concurrency (single operator).
- No per-action "uploaded" tracking beyond the `actions_queued` count.
- Generator-consumes-learnings, scheduling — unchanged.

## Testing
- View: `V_WEEKLY_RUN` returns one row per current-week family, correct `opportunity_score` ordering, status defaults to PENDING, reflects an inserted APPROVED/DONE row.
- Endpoints: approve then done transitions; GET reflects after each (cache cleared).
- Frontend: rail ordering, status chips, stepper gating, Queue-all wires to Do queue, auto-advance on Done, "week complete" state.
