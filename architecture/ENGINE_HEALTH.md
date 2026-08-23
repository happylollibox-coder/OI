# ENGINE_HEALTH — the standing self-check

**Born:** 2026-08-16 (engine-finalization Task 3.3). `V_ENGINE_HEALTH`: one row per check —
GREEN / AMBER / RED / INFO, the measurement AND its threshold printed together. Reads small
tables only, except the single scorecard arm. A quiet board is the goal state.

Checks: contradiction_rate (EXCLUDE share; amber>5 red>15) · ownership_overlaps (red>0) ·
state_duplicate / missing_appointment (the V_KEYWORD_STATE invariants; red>0) ·
overdue_appointments (amber>50) · scorecard_reversed_share (trailing 42d judged; amber>35) ·
manual_better_unresolved (the MANUAL_DIVERGENCE closing rule) · snapshot_freshness (red>2d) ·
noop_leakage (amber>10) · view_body_headroom (v27.101; amber>70% red>85% of the view ceiling) ·
plan_price_ambiguity (v27.102; red>0) · loser_kill_clause / state_floor_resolution (v27.104;
red>0).

**The family seat register's checks (v27.127, 2026-08-23; `seat_*`, spec
`FAMILY_SEAT_REGISTER.md` "Health").** They read the register's once-per-pass IMAGE
(`T_FAMILY_SEAT_REGISTER` — the table the brief, the Weekly Run and the cube read), the seat
ledger, the keyword-state snapshot, the change log, the holdout table and `LOG_PIPELINE_RUNS`;
never the live register view and never a ceiling view. seat_reconciliation_gap (categories = the
family's spend on every horizon, seats + leaks + gaps = the bad side today, within $0.01 — the
acceptance suite's own tolerance; red>0) · seat_ledger_idempotence (the invariants a second
admission or a re-insert on one snapshot would break; the proof proper is two runs, one
fingerprint — red>0) · seat_every_occupant_numbered (red for an unnumbered or twice-held number
on the image; amber when the image and the ledger disagree, which is the transient between
orchestrator step 20.8b and cube step 0c of one pass) · seat_no_launch_seat (red>0) ·
seat_holdout_row_on_sheet (a seat book row naming a HOLDOUT-arm campaign built on or after its
`eligible_from`, at any upload status; red>0) · seat_raise_at_or_below_live_bid (ruling R-f;
red>0) · seat_past_due_in_future_tense (ruling R-i; red>0) · seat_overdue_vs_snapshot (INFO —
reports the appointments the ladder owes, measured on the snapshot's own date; the cause is the
park-era `settle_due`, diagnosed and not applied, a ruling for Ori) · seat_step_days_since_pass
(days since `SP_MAINTAIN_FAMILY_SEATS` last logged OK inside a pass, New York clock — the
orchestrator's clock; `started_at` is UTC and is converted; amber>1, red>2, red when never
logged). Every one was proven to fire on doctored `TMP_` copies before deploy and read
GREEN / INFO on the live objects after it; the numbers are the board's, never this file's.

First board 2026-08-16: RED contradiction_rate 31.8 (57/179 — the gate WORKS; the signal is that
the engines structurally overlap a third of their instructions, mostly LAUNCH proposing on
LOW_STOCK-owned keys — a future refinement is to stop GENERATING those, not just silencing them)
· AMBER overdue_appointments 78 (oldest 2025-11-16) · AMBER scorecard_reversed_share 41.1 ·
six GREEN. Surfaces on the Weekly Run summary strip when Phase 6 builds it.

Read the board:

```sql
SELECT check_name, measured, status, threshold, detail
FROM `onyga-482313.OI.V_ENGINE_HEALTH` ORDER BY status = 'GREEN', check_name;
```
