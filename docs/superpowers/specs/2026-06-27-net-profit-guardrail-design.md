# Net-Profit Guardrail + Escalation (Coacher sub-project E)

- **Date:** 2026-06-27
- **Owner:** Ori
- **Status:** Design (autonomous, per "continue — don't stop unless you have questions") — spec → plan → build
- **Parent vision:** the per-product coacher. **E** is the "check that the plan gains net profit — if so continue, if not raise it to me" step after D (the plan).
- **Builds on:** D ([[project_coacher_weekly_plan]] — `V_WEEKLY_PLAN_REVIEW`, `DE_WEEKLY_PLAN`, `V_WEEKLY_CELL_NET`), C ([[project_coacher_gaps_borrow_probe]] — `DE_PROBE_LOG`), `DE_COACH_THRESHOLDS`. Backend only ([[feedback_all_logic_in_backend]]); advisory (execution = F).

---

## 1. Problem

D produces a weekly plan and an on/off-plan verdict, but nothing **acts as a guardrail**: nothing watches whether a product is actually making net profit week-over-week, distinguishes a one-off miss from a real failure, or **raises it to Ori** when the coacher can't self-correct. E is that guardrail + escalation: detect persistent/acute net-profit failure per product (and cell), classify severity, and emit an escalation with the evidence and a recommended intervention. It does not execute — it raises.

## 2. Decisions (locked from established patterns + Ori's standing preferences)

| Axis | Decision |
|---|---|
| Output | **Backend** `V_PLAN_ESCALATION` view (+ tunable thresholds in `DE_COACH_THRESHOLDS`). The "raise it to me" queue. |
| Posture | **Advisory** — recommends an intervention, never executes (that's F). Consistent with D being advisory. |
| Grain | Per **product** (the escalation unit), with the offending **cell** named in the evidence. |
| Severity | `WATCH` (mild / first week) vs `ESCALATE` (persistent or acute loss). |
| Boundary | D self-corrects a single OFF_PLAN at the next weekly boundary; **E fires when it's persistent or acute** (the D/E line from the D flowchart). |
| Scope | The 4 advertised parents. Surface / notification = **v1.1** (or feed `DE_ALERTS` later); ack/snooze = v1.1. |

## 3. Component 1 — `V_PLAN_ESCALATION` (the guardrail view)

One row per active escalation. Evaluates these triggers (each gated by a tunable `DE_COACH_THRESHOLDS` key), reading `DE_WEEKLY_PLAN` (status history), `V_WEEKLY_PLAN_REVIEW` (last week), `V_WEEKLY_CELL_NET` (net trend), `DE_PROBE_LOG`:

| Trigger | Fires when | Severity | Recommended action |
|---|---|---|---|
| `PERSISTENT_OFF_PLAN` | a SCALE product is OFF_PLAN ≥ `ESCALATE_OFF_PLAN_WEEKS` (2) consecutive completed weeks | ESCALATE | re-derive `cpc_target` / cut SCALE budget / review strategy |
| `ACUTE_NET_LOSS` | product (or a SCALE cell) net profit < 0 in the last completed week | ESCALATE | pause/cut the loss-making cell |
| `NET_COLLAPSE` | last week's net ≤ `NET_COLLAPSE_FRAC` (0.5) × trailing-`TREND_WEEKS` average, for a profitable product | WATCH→ESCALATE if 2× | investigate; hold bids (no chase) |
| `CAP_OVERSPEND` | a CAP cell's actual spend exceeded its cap (`V_WEEKLY_PLAN_REVIEW.overspend`) | WATCH | lower the configured Amazon daily budget |
| `PROBE_WASTE` | a probe is `EXHAUSTED` (14 days, < 15 clicks, no conversion) in `DE_PROBE_LOG` | WATCH | kill the probe; mark the cell un-winnable |

**Columns:** `parent_name, scope (PRODUCT|CELL), season, match_type, intent_class, trigger, severity, since_week, weeks_off, actual_net, expected_net, trend_net, spend_vs_cap, recommended_action, evidence` (a short string). Pure logic; no persistence in v1 (the live view *is* the queue).

## 4. Component 2 — thresholds (`DE_COACH_THRESHOLDS`)

New keys (seeded, tunable): `ESCALATE_OFF_PLAN_WEEKS=2`, `NET_COLLAPSE_FRAC=0.5`, `ACUTE_LOSS_NET=0` (net below this = loss), `ESCALATION_TREND_WEEKS=8`. All read with `COALESCE(..., default)` so the view works before they're inserted.

## 5. Data flow

```
DE_WEEKLY_PLAN (status history) ─┐
V_WEEKLY_PLAN_REVIEW (last week) ─┼─► V_PLAN_ESCALATION  (per-product guardrail + severity + recommended action)
V_WEEKLY_CELL_NET (net trend) ───┤        └─► (v1.1) surface / DE_ALERTS feed / ack
DE_PROBE_LOG (exhausted probes) ─┘
DE_COACH_THRESHOLDS (tunable triggers)
```

## 6. Scope

**In:** `V_PLAN_ESCALATION`; the 4 new `DE_COACH_THRESHOLDS` keys (seeded); `config.yaml`.
**Deferred:** auto-execution of interventions (**F**); a surface / push notification / `DE_ALERTS` feed (**v1.1**); acknowledge/snooze so a raised escalation can be dismissed (**v1.1**); a persisted escalation history/log (**v1.1**); the TOS-brake-on-defense bid behavior (engine v2, not escalation).

## 7. Risks & limits

- **Thin history at cold start** — `PERSISTENT_OFF_PLAN` needs ≥2 completed planned weeks; fires nothing until D has run a couple of weeks (like the rest of the loop). The acute triggers (`ACUTE_NET_LOSS`, `CAP_OVERSPEND`, `PROBE_WASTE`) can fire sooner.
- **Net profit = ads-attributed** (`GROSS_PROFIT − Ads_cost`), consistent with the coacher.
- **Advisory only** — E raises; a human (or F) acts. No mid-week auto-brake in v1.
- **No de-dup/ack in v1** — the same escalation re-appears each run until the underlying issue clears; acceptable for a live queue, ack is v1.1.
- Observational, US-only, completed weeks only.

## 8. Testing

- `V_PLAN_ESCALATION` deploys; one row per (product, trigger); `severity ∈ {WATCH, ESCALATE}`; every row has a non-empty `recommended_action`.
- `ACUTE_NET_LOSS` fires for a product whose last-week `V_WEEKLY_CELL_NET` net < 0; does not fire for a profitable one.
- `PROBE_WASTE` fires for an `EXHAUSTED` `DE_PROBE_LOG` row, not for ACTIVE/GRADUATED.
- `CAP_OVERSPEND` mirrors `V_WEEKLY_PLAN_REVIEW.overspend` (CAP cells only).
- Thresholds: changing a `DE_COACH_THRESHOLDS` key (e.g. `ESCALATE_OFF_PLAN_WEEKS`) changes which rows fire; the view defaults sanely when the key is absent.
- Cold start: with no completed planned week, persistent/off-plan triggers are empty and the view still deploys + runs clean.
