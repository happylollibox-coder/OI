# WEEKLY_RUN_UX — the 5-second / 5-minute contract

**Born:** 2026-08-16 (Phase 6 of the engine-finalization plan; full build plan:
docs/superpowers/plans/2026-08-16-weekly-run-5s-5min.md). **Owner request (verbatim):** "i want
the ui ux be most readable and explainable so i can easily verify the reason of decided logic
and approve it easily. i want to accept an action in 5 seconds and to understand all ppc changes
(and unchanged) in 5 minutes."

## The 5-second accept

Every actionable row, anywhere on the page, has the same anatomy in the same order:
`[item] [now → proposed] [why: TRIGGER — EVIDENCE ⇒ MOVE] [queue toggle]`.

- The `why` is ONE clause (≤ ~12 words), AUTHORED IN THE VIEW (the v27.62 low-stock rule: written
  short in SQL, never truncated in React). Full paragraph = the cell's tooltip.
- Guards that PASSED are silent. Only REVIEW/flags render (one amber chip + reason). "Nothing
  flagged" is communicated by absence — quiet means safe.
- One click queues; ✓ when queued; apply-all counts and clicks derive from ONE memoised list.

## The 5-minute whole-run read

From page open: SUMMARY STRIP (changes · held · UNCHANGED with why-classes) over TODAY'S
DECISIONS (one unified feed from the preflight, grouped by engine in the ownership order, EXCLUDE
rows collapsed and never queueable, REVIEW rows amber + per-item confirm), then the 17 criteria
sections as LAZY drill-downs — a section fetches ONLY on first expand. The feed is the read; the
sections are the microscope. The front page reads ONLY small tables (T_ENGINE_PREFLIGHT,
V_RUN_SUMMARY, V_RUN_UNCHANGED) and must render in seconds.

## Hard rules

1. All strings and all decisions in BigQuery. The feed renders preflight verdicts; it never
   re-derives one. The one permitted React glue: INCREASE vs REDUCE by comparing suggested to
   current (the OobBudgetPhase:241 precedent).
2. $/day impact shown for BUDGET moves only — bid-level $/day would be invented precision.
3. Non-clobber everywhere (the `ourItem`/`claimedElsewhere` idiom); the export-time preflight
   gate remains the final door.
4. Ori's two numbers are ACCEPTANCE TESTS (plan Task 8): feed with data ≤ 15s from hard reload;
   5 arbitrary rows accepted in ≤ 25s; the whole run narratable in 5 minutes. Failures file
   against the reason grammar, never against the reader.

## Interlocks

- UNCHANGED reads `FACT_KEYWORD_STATE` (built 2026-08-16 — the state machine IS the unchanged
  taxonomy; the plan's interim guard-based CASE is superseded before it was built).
- `V_ENGINE_HEALTH` joins the summary strip as its fourth line.
- `why_short` (plan Task 3) lands per-view; the feed falls back to the full reason until then.

## One decision, one ✓ (v27.72, 2026-08-17)

Ori: "if i approve an action in section or snapshot, visual should show both approve."

- Queued state is looked up by CANONICAL KEY, never by which surface queued it. The keys live in
  `useDoQueue.tsx` as the `findQueued*` helpers: BID → `keyword_id` (any bid action), BUDGET →
  `campaign_id` (any budget action), NEGATE → `campaign_id` + lowercased term (returns ALL of a
  term's ad-group split items).
- A key queued at a DIFFERENT value (the sections read live views, the feed reads the frozen
  snapshot — the values drift a cent apart across midnight) still renders ✓, with the queued
  value printed beside it (`$0.41 ✓ at $0.39`). One click removes it; a second click re-queues
  at the clicked row's own value. The old "· other panel" refusal display is gone.
- Bulk apply-all counts key-queued rows as DONE (not skipped). Bulk unapply removes only
  value-exact items — a foreign-valued item is one deliberate decision, removed only on its row.

## Sections open where the work is (v27.72)

Ori: "when there is an open action hierarchy should be Expanded else collapse by default."

- `WeeklyRunPage` fetches the preflight engine counts once (EnginePreflight cube, GO/REVIEW
  only) and passes `defaultOpen` to each criteria section: LOW_STOCK → Low stock, LAUNCH →
  Launch exemption, REVERDICT → Revivals, OOB → both OOB panels, LIFT → the lift panels.
- A user click is FINAL: the panels hold `openState ?? defaultOpen` — an explicit close is never
  reopened by data arriving late. If the preflight cube errors, every section stays collapsed
  (today's behavior, fail-quiet).
- The negate lever rides the same feed: NEGATE rows appear in Today's decisions under their
  owning engine (OOB / Portfolio 80/20 / Coach), toggle text "block" / "✓ blocking".
