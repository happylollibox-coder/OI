# Coach — BLITZ Peak Re-Increase (design)

**Date:** 2026-06-24 · **Status:** approved, pre-implementation · **Owner:** Ori
**Engine:** `V_ADS_COACH.sql` (feeds `FACT_ADS_COACH_ACTIONS` via `SP_REFRESH_ADS_COACH_ACTIONS` → cube → Actions page)

## Problem
The `recommended_bid` math in `V_ADS_COACH.sql` (~L1090–1148) decides purely on the
keyword's **recent (4w/8w) target performance** (`target_roas`, `target_orders_8w`,
`eff_orders_for_bid`). A keyword that is **dormant off-peak** (0 recent orders) but did
strongly at last peak (e.g. *teen girl gifts* for Fresh: **1.65× ROAS / 17 orders / $219
spend** at last peak) hits a reduce/bleeder branch → bid **cut** ($0.37 → $0.33). Peak
performance never enters the bid formula, so the coacher bids *down* a proven peak winner
during the very peak it should capture.

Task #7 (2026-06-23) only flips the **action label** to `MONITOR` and only when
`target_orders_8w > 0` — so a **dormant** proven-peak keyword isn't covered and the bid is
still cut.

## Goal
In BLITZ, a keyword on the peak plan (`peak_rec = 'INCREASE'`) is bid **up** toward its
proven peak level instead of cut — capturing the high volume + buying intent at peak.

## Trigger & scope
A peak-plan keyword (`coach_mode='BLITZ'` AND `peak_rec='INCREASE'`) that current
performance would otherwise **cut/stop/hold** (i.e. NOT already healthy-increasing — those
keep the normal scale ladder) resolves to one of two outcomes:
- **RE-INCREASE** (bid up) when **all** hold: keyword `ENABLED`; **profitable AT peak**
  (`GREATEST(ly_net_roas, q4_peak_net_roas) >= 1.0`); past warmup (campaign ≥ 14d); off the
  3-day re-suggest cooldown.
- **HOLD** (MONITOR, bid unchanged) otherwise — never cut a peak winner.

Placed **above `STOP_TARGET`** in `target_action` so a proven peak winner is never stopped.
Supersedes/generalises the task-#7 hold (which only covered active `orders>0` terms) to
dormant terms too. **Out of scope:** `BRAND_DEFENSE`/`PRODUCT_DEFENSE` keywords keep the
existing defense bid logic (they bid up to dominate own listings regardless of ROAS — handled
before this branch). OOS gating stays **client-side** (`clearCase`) — the engine has no stock
column and existing increase tiers don't gate on stock either.

### Profitable-at-peak gate (refinement found in verification)
A keyword can be on the peak plan for **volume/trending** while having had a net ROAS < 1.0
at last peak (it lost money). Those are **held, not scaled** — the re-increase ladder starts
at peak ROAS ≥ 1.0, matching the approved tier table.

## Bid formula (tiered by peak ROAS + CPC floor)
```
peak_roas      = GREATEST(COALESCE(ly_net_roas,0), COALESCE(q4_peak_net_roas,0))
peak_cpc_floor = COALESCE(ly_cpc, ads_cpc_8w)          -- the CPC that won clicks at peak
base           = GREATEST(current_bid, peak_cpc_floor) -- restore the decayed bid
mult           = 1.50 if peak_roas≥5 · 1.40 ≥3 · 1.30 ≥2 · 1.20 ≥1.5 · 1.10 ≥1.0   (BLITZ ladder)
recommended_bid = LEAST( base × mult,
                         GREATEST(margin_per_unit × 0.5, 0.30),   -- margin cap
                         th_bid_cap )                              -- absolute cap
```
All peak columns exist in `V_ADS_COACH_DATA` (`ly_net_roas` L1403, `ly_cpc` L1398,
`q4_peak_net_roas` L1345, etc.) and reach `coach_data d`.

**Worked example:** peak 1.65× → ×1.20; base = max($0.37, ~$0.74 recent CPC) = $0.74 →
**$0.37 → ~$0.89** (within margin & bid cap), vs the current cut to $0.33.

## Action label & trace
- `target_action` → `INCREASE_BID` (card title becomes "Bid up keyword…" with a real up move)
- `target_decision_trace` peak chip: *"Peak plan re-increase · peak ROAS 1.65× (17 orders)
  · restoring to peak-competitive bid."*
- Consistent with the client-side peak opportunity line (`~$X net profit at last peak`)
  already shipped in `DecisionCard`/`opportunityPerWeek`.

## Guardrails
- **Margin cap** (`margin_per_unit × 0.5`, floor $0.30) and **`th_bid_cap`** still bound the
  bid — never bids into a loss.
- **3-day re-suggest cooldown** still applies → suggests once per peak, no daily churn.
  (Open option: bypass during the active event if it feels too quiet — not taken in v1.)
- BLITZ-only → cannot fire outside a peak.

## Placement (implementation)
New branch **before** the reduce/bleeder tiers in BOTH:
1. `recommended_bid` CASE (~L1106 onward) — the bid value
2. `target_action` CASE (~L814, the task-#7 PEAK PROTECTION block) — flip to `INCREASE_BID`
   for qualifying dormant/lagging peak keywords (currently only `MONITOR_TARGET`)
3. `target_decision_trace` — add the peak re-increase chip
4. `bid_change_pct` CASE (~L1151) — mirror the increase %

Keep the four in sync (the engine pattern: action / bid / pct / trace fire on one condition).

## Rollout & verification (real-money path)
1. Edit `V_ADS_COACH.sql` — DONE. Five edits, kept in sync:
   - `coach_data`: new `peak_reincrease_bid` column (single source of truth for value + %).
   - `target_action`: RE-INCREASE / HOLD branches above `STOP_TARGET`; old task-#7 branch replaced
     with a pointer note.
   - `recommended_bid`, `bid_change_pct`: RE-INCREASE (→ `peak_reincrease_bid`) / HOLD (→ NULL).
   - summary narrative: matching "📈 Peak plan winner" reason.
2. **Pre-prod diff** (scratch view `V_ADS_COACH_PEAKTMP`, since dropped) — VERIFIED 2026-06-24:
   - Compiles (dry-run clean).
   - BLITZ peak_rec=INCREASE subset (168 rows, unchanged → no fan-out):
     **bid direction old → new: cut 40 → 0**, raised 95 → 121, held 33 → 47.
     `target_action`: STOP_TARGET 3 → 0, MONITOR 42 → 17, INCREASE_BID 48 → 76.
   - Consistency: 0 rows with a CUT action but a raised bid.
   - Profitable-at-peak gate holds: 0 non-defense sub-1.0 keywords raised by the peak branch.
   - Whole-view row count identical: 40939 = 40939 (no fan-out).
   - Example: LolliME "girls birthday gifts" $0.42 → $0.89 (peak 10.9×); the dormant Fresh
     "teen girl gifts" case flips from the $0.37 → $0.33 cut to a peak-competitive raise.
3. **PENDING USER GO-LIVE**: deploy view to prod `V_ADS_COACH` → `CALL SP_REFRESH_ADS_COACH_ACTIONS`
   → let cube cache cycle.
4. Update `architecture/ADS_COACH_DECISION_MATRIX.md` with the new branch.
5. No new BQ object — edits an existing view (config.yaml unchanged).

## Not in scope (v1 / YAGNI)
- `peak_rec = 'INCREASE_CAUTIOUS'` (gentler tier) — future.
- Live-SQP-momentum trigger — the peak plan already encodes volume/trending.
- DoPage bulksheet handling for ADD-type peak terms — separate task #8.
