# KEYWORD_STATE — the roadmap of each keyword

**Born:** 2026-08-16 (engine-finalization plan Task 2.1). **Owner request:** "the roadmap of each
keyword" — every keyword in exactly ONE state, with exactly ONE owner, and always ONE NEXT
APPOINTMENT (a date on which something will re-judge it).

## Objects

| object | role |
|---|---|
| `SP_SNAPSHOT_KEYWORD_STATE` | Assembles the state row from the OTHER snapshots (guard, reverdict, panel ownership, today's preflight, the change log). Computes NOTHING new — it only assembles verdicts other objects already made. Orchestrator Task 20.8, after the preflight (20.7). |
| `FACT_KEYWORD_STATE` | One row per (campaign, keyword): state, owner, next appointment, settled record, season context, view-authored reason. |
| `V_KEYWORD_STATE` | Thin read surface. No logic. |

## The states (first match wins — the derivation order IS the doctrine)

| state | predicate (all inputs are existing snapshot columns) | next appointment |
|---|---|---|
| `DEAD` | settled_clk90 ≥ 15 AND settled_ord90 = 0 (tested loser — thesis falsified) | none (the one exempt state; sibling evidence is its only door, Task 2.4) |
| `PENDING_SETTLE` | reverdict = PENDING_SETTLE | reverdict settle_due |
| `REVIVED_SETTLING` | revive_settling | its settle_due |
| `PARKED` | reverdict ∈ (REVIVE, CONFIRM_PARK, INSUFFICIENT) | REVIVE → today (it is in the plan); CONFIRM_PARK → +14d (the revival sweep); INSUFFICIENT → its settle_due |
| `PACED_WINNER` | winner + a GO bid-lowering instruction in today's preflight | tomorrow (the pace re-fires daily) |
| `WINNER` | settled_roas90 ≥ 1.0 at ≥ 10 settled clicks | last change + 14d (its scorecard read) else +7d rolling |
| `LOSER_BLEED` | settled_roas90 < 0.6 at ≥ 10 settled clicks | same |
| `TRIAL` | everything else | guard settle_due else +7d |

**Owner:** `FACT_PANEL_OWNERSHIP.owner` (LOW_STOCK > LAUNCH > OOB > LIFT, the single-home ladder),
with one keyword-grain overlay: a LIFT-owned keyword carrying reverdict = REVIVE is
`REVERDICT`-owned (the preflight ladder's REVERDICT-above-LIFT rule, applied at rest).

## The two invariants (standing self-checks; V_ENGINE_HEALTH reads them)

1. **One state:** `SELECT campaign_id, keyword_id … HAVING COUNT(*) > 1` returns 0 rows.
2. **No keyword without a next appointment:** `COUNTIF(next_check_date IS NULL AND state != 'DEAD') = 0`.

## v1 honesty notes

- `SEASONAL_HOLD` is NOT yet a state: the season gate's ENTRY_BLOCK verdict is computed inside the
  engines and not snapshotted. Rows it would claim appear as PARKED/TRIAL carrying
  `season_context` (from `season_win_prior`). Upgrades when the gate gets a snapshot.
- `state_since` is best-effort (park_date where parked, last bid change elsewhere, NULL when no
  event is logged) — full event-sourcing arrives with proposal history depth.
- The 360° SIGNAL PANEL (windows {1d,3d,7d,14d,90d,LY} × scopes {keyword, campaign, family},
  settle-labeled) is the task's SECOND HALF — this file gains its column spec when it lands.
  The state core ships first so the invariants start guarding immediately.
