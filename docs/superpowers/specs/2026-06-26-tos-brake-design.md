# TOS-Brake (Coacher sub-project A.1)

- **Date:** 2026-06-26
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Parent vision:** the per-product coacher. This is **A.1**, the follow-on to [[project_coacher_data_foundation_tos]] (sub-project A) that makes the top-of-search signal actually steer a decision.
- **Builds on:** A (which exposed `target_tos_share` / `tos_target_pct` and floored the targets at 3%). Relates to [[feedback_coacher_rules_in_engine]] (all decision rules live in `V_ADS_COACH.sql`).

---

## 1. Problem

Sub-project A unlocked the real top-of-search (TOS) signal, seeded a per-cell `tos_target_pct`, and added a TOS bid-up branch — but that branch is **inert**: it sits below the profitable-tier catch-all in `V_ADS_COACH.target_action`, which already raises **every** profitable keyword (`target_roas ≥ th_profitable_roas AND eff_orders_for_bid ≥ 2`) regardless of position. So "bid up profitable-but-buried keywords" was redundant and never fired (verified: 163 gate-eligible rows, 0 decided by the TOS branch).

The engine's real blind spot is the **opposite**: it keeps raising bids on keywords that have **already reached** their TOS target. Once a term is dominant, more bid buys CPC, not position. The fix is a **brake**, not another bid-up.

## 2. Decision

When a **profitable, non-defense** keyword has **already reached its TOS target** (`target_tos_share ≥ tos_target_pct`), **hold the bid** (`MONITOR_TARGET`) instead of raising it. Buried terms (below target) are untouched — the existing profitable/scale tiers raise them exactly as today. It is a HOLD, never a cut.

**Locked choices (from brainstorming):**

| Axis | Decision |
|---|---|
| **Brake scope** | **Pure brake** — hold dominant; no special size-up of buried terms (they keep the existing `raise_pace`). |
| **Defense** | **Exempt** — `BRAND_DEFENSE` / `PRODUCT_DEFENSE` never braked (the brand moat always defends). Consistent with B.2 suppression exemption. |
| **Near-term footprint** | Accepted as **0 rows today** — no non-defense profitable term is at its (floored-high) target yet. The brake is a forward-looking guardrail that activates as terms climb. The only currently-dominant profitable terms are 11 Lollibox **brand-defense** rows (66.6% TOS vs 65.3% target), which the exemption deliberately leaves alone. |

## 3. The change (`V_ADS_COACH.sql`)

### 3.1 Add the brake branch to `target_action`

Insert a new `WHEN` **immediately before the scale-up frequency-gate tier** (currently line ~849), after the peak re-increase and bleeder blocks:

```sql
-- ═══ TOS BRAKE: already-dominant profitable keyword → hold the bid ═══
-- Once target_tos_share ≥ tos_target_pct the term owns its top-of-search position;
-- raising further buys CPC, not impressions. Hold (no change). Defense exempt.
-- Self-correcting: if TOS later erodes below target, this fails and the normal
-- scale-up/profitable raise resumes.
WHEN d.target_tos_share IS NOT NULL
     AND d.tos_target_pct IS NOT NULL
     AND d.target_tos_share >= d.tos_target_pct
     AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
     AND d.strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
  THEN 'MONITOR_TARGET'
```

**Placement rationale:**
- **After** peak re-increase (BLITZ peak winners stay aggressive) and the bleeder cut (0-order bleeders still cut) → the brake never interferes with those.
- **Before** the scale-up (849) and profitable (859) INCREASE tiers → it intercepts the raise for dominant non-defense terms before it fires.
- Buried terms fail `target_tos_share >= tos_target_pct`, fall through, and are raised by the existing tiers — no behavior change for them.

### 3.2 Remove the inert TOS bid-up action branch

Delete the dead `WHEN d.target_tos_share ... THEN 'INCREASE_BID'` branch (currently ~line 894). Verified 0 firings; fully superseded by the brake.

### 3.3 Remove the `recommended_bid` TOS size-up branch

Delete the TOS block in the `recommended_bid` CASE (currently ~line 1256) that steps buried terms +15%/+$0.10 toward the cap. This is the "size-up" path explicitly declined in favor of a pure brake. Removing it reverts the affected rows to the normal bid computation:
- ~90 rows today: mostly brand-defense (which raise toward the ceiling via the defense bid-raise logic anyway) + 5 LolliME PRODUCT (revert to profitable-tier `raise_pace`).

### 3.4 Decision trace

Keep the existing `tos` chip but make it reflect the brake state:
- Dominant (braked): `pass:true`, label "dominant — holding bid (TOS x% ≥ target y%)".
- Buried / below target: `pass:false`, label "TOS x% < target y%" (position read only — no action implied now).

The chip renders whenever TOS data is present (unchanged); only the wording/`pass` semantics align to the brake.

## 4. Scope

**In:** the brake branch (3.1); removal of the two declined/dead TOS bid-up paths (3.2, 3.3); the trace-chip wording (3.4).
**Out / unchanged:** the exposed signals (`target_tos_share`, `target_impressions_8w`, `no_traffic_rate`, `tos_target_pct`) all stay — the brake and trace consume them. `V_KEYWORD_DAILY`, `derive_tos_targets.sql` (incl. the 3% floor), `V_ADS_COACH_DATA` unchanged. No new tables/columns. Defense bid logic untouched.

## 5. Risks & limits

- **Dormant today.** Fires on 0 rows now (accepted). If it never fires for a long time because non-defense terms can't climb to their targets, that's a signal the targets are too high or the position is structurally un-winnable — a `tos_target_pct` re-tune, not a code change.
- **Brand defense still over-climbs.** The 11 dominant Lollibox brand terms keep being raised (exempt). Revisiting whether to brake brand-defense-at-target is a possible v2 (deliberately deferred).
- **HOLD only.** The brake never cuts; a dominant term that becomes unprofitable is still handled by the existing reduce/bleeder tiers (above the brake or via ROAS), not by this branch.
- Observational, US-only. Rules live in SQL per [[feedback_coacher_rules_in_engine]].

## 6. Testing

- **Row parity:** `V_ADS_COACH` row count unchanged (41,257).
- **Brake fires 0 today** (expected): `COUNTIF(target_action changed to MONITOR_TARGET due to brake) = 0` on live data; **and** a synthetic/forced dominant non-defense row (`target_tos_share ≥ tos_target_pct`, profitable, non-defense) flips `INCREASE_BID → MONITOR_TARGET`.
- **Defense unchanged:** the 11 dominant `BRAND_DEFENSE` rows keep their pre-change action (still raising).
- **Buried unchanged:** rows with `target_tos_share < tos_target_pct` keep the same `target_action` and `recommended_bid` they'd get from the existing tiers after 3.3's removal (spot-check the 5 LolliME PRODUCT terms now use `raise_pace`, not the +15% TOS step).
- **No regressions:** `reduce_inversions = 0` unchanged; no orphaned references to the removed branches (grep `V_ADS_COACH.sql` for the deleted predicates); decision-trace JSON still valid.
