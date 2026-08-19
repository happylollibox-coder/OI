# ENGINE_HEALTH — the standing self-check

**Born:** 2026-08-16 (engine-finalization Task 3.3). `V_ENGINE_HEALTH`: one row per check —
GREEN / AMBER / RED / INFO, the measurement AND its threshold printed together. Reads small
tables only, except the single scorecard arm. A quiet board is the goal state.

Checks: contradiction_rate (EXCLUDE share; amber>5 red>15) · ownership_overlaps (red>0) ·
state_duplicate / missing_appointment (the V_KEYWORD_STATE invariants; red>0) ·
overdue_appointments (amber>50) · scorecard_reversed_share (trailing 42d judged; amber>35) ·
manual_better_unresolved (the MANUAL_DIVERGENCE closing rule) · snapshot_freshness (red>2d) ·
noop_leakage (amber>10).

First board 2026-08-16: RED contradiction_rate 31.8 (57/179 — the gate WORKS; the signal is that
the engines structurally overlap a third of their instructions, mostly LAUNCH proposing on
LOW_STOCK-owned keys — a future refinement is to stop GENERATING those, not just silencing them)
· AMBER overdue_appointments 78 (oldest 2025-11-16) · AMBER scorecard_reversed_share 41.1 ·
six GREEN. Surfaces on the Weekly Run summary strip when Phase 6 builds it.
