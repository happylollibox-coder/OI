# MANUAL_DIVERGENCE — the hand-vs-model ledger

**Born:** 2026-08-16 (engine-finalization Task 3.1). **Doctrine (Ori 2026-08-11, verbatim):**
"i preffer fixing the model then supporting manual — the goal is that the engine will be 100%
auto — if i change something manually you should ask why and if it is the right decision. if so
we need to fix the model."

`V_MANUAL_DIVERGENCE`: every `source='MANUAL'` change × the engine's proposal snapshot for its
applied day × its scorecard verdict at the honest lag.

- **kind:** AGREED (±5% of the engine's value — hand-applied coach, never counted as
  disagreement) · OVERRODE (the divergence that matters) · ENGINE_SILENT (a MODEL GAP — the
  human saw what the engine did not) · LEVER_NOT_SNAPSHOTTED (pauses, hero swaps — negates
  graduated out in v27.72: a manual negate keys on `term|<lowercased term>`, lever NEGATE, and is
  AGREED when the engine proposed the same block that day — a negate has no value to diverge
  from — else ENGINE_SILENT, never OVERRODE) ·
  UNKNOWN (era PRE_SNAPSHOT, applied before 2026-08-15 — no proposal memory exists).
- **judgment:** MANUAL_BETTER (OVERRODE + CONFIRMED → a rule should change) · ENGINE_BETTER
  (OVERRODE + REVERSED → the hold doctrine earned its keep) · TIE · GRADED_* · PENDING.
- **The closing rule:** every MANUAL_BETTER row ends as either a threshold change
  (THRESHOLD_TUNER.md) or a documented disagreement. V_ENGINE_HEALTH check
  `manual_better_unresolved` counts the open ones.
- **1.8 interlock:** the MANUAL_HOLD engine guard is removed only after this ledger has run ≥ 2
  weeks alongside it (engine-finalization Task 1.8, resequenced).

First census 2026-08-16: 89 manual changes — 24 graded (5 CONFIRMED / 2 NEUTRAL / 9 REVERSED /
8 INSUFFICIENT), 65 pending gates; all PRE_SNAPSHOT. Real kind-classification begins with
changes applied 2026-08-15+.
