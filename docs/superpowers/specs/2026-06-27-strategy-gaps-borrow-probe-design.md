# Strategy Gaps: Detect → Borrow → Probe (Coacher sub-project C)

- **Date:** 2026-06-27
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Parent vision:** the per-product coacher. **C** closes the cold-start / low-confidence gap: situations where the coacher has no trusted per-product plan and silently falls back to generic defaults.
- **Builds on:** [[project_coacher_product_strategy_profile]] (B/B.2 — the profile + confidence gate), [[project_coacher_data_foundation_tos]] (A — real impressions/`no_traffic_rate`/cost per keyword), [[project_cpc_strategy_net_profit_analysis]] (per-match-type CPC behavior). Relates to [[feedback_coacher_rules_in_engine]].

---

## 1. Problem

The coacher plans bids per `parent × season × match_type × intent_class` cell. Today **86 cells exist, all DERIVED — 60 CONCLUSIVE, 26 WEAK; 0 BORROWED, 0 MANUAL.** A cell steers only when `source='MANUAL' OR confidence='CONCLUSIVE'`, so the **26 WEAK cells plus every missing cell don't steer** — the coacher runs them on generic thresholds with no per-product plan, invisibly. C makes those gaps **visible**, **fills the fillable ones by borrowing a trusted similar cell**, and **probes the rest** (cells whose keywords sit starved) with a bounded, per-match-type exploratory bid.

## 2. Decisions locked (from brainstorming)

| Axis | Decision |
|---|---|
| **Scope** | All three mechanisms in v1: gap-detector + borrow-similar + probe. |
| **Authority** | **Auto-steer with caps.** BORROW auto-steers (reuses already-trusted params, capped + labeled). PROBE auto-emits as a **capped recommendation** — execution stays manual today (Ori uploads), so a probe is a bounded *suggestion*, not auto-spend. |
| **Probe cost** | **Per match type, data-driven.** Probe `launch_cpc` = a conservative percentile of that `parent × match_type`'s *real* `cost_per_click`; exact/phrase naturally land higher than broad. No flat/hardcoded bid. |
| **Demand signal** | **Per match type** — the opportunity bar that justifies a probe is read at the match-type grain, so a pricier exact/phrase probe only fires when demand justifies its higher per-click cost. |
| **Out of scope** | **Bunny/LolliBall** (unadvertised — standing them up is product launch / new campaigns, not gap-filling). Cells with **no keywords at all** (probing those = keyword creation = F). |

## 3. Component 1 — Gap-detector (`V_STRATEGY_GAPS`, new view)

One row per `parent × season × match_type × intent_class` cell that is **active in ads** (has keyword spend in the last 8w) but **does not steer** (missing profile row, or present but `confidence='WEAK'` and `source NOT IN ('MANUAL','BORROWED')`).

Columns:
- Cell key: `parent_name, season, match_type, intent_class`.
- `gap_type` — `MISSING` (no profile row) | `WEAK` (row exists, doesn't clear the gate).
- `spend_at_risk` — 8w ad spend flowing through the cell on default rules (prioritization).
- `keyword_count`, `starved_keyword_count` — keywords in the cell, and how many sit starved (high `no_traffic_rate` / near-zero impressions, from A).
- `demand_signal` — sum of the **cell's own keywords'** market/SQP search volume (the search demand those keyword queries see). Inherently per-type: exact/phrase/broad keywords address different breadth, so the same cell key carries a different demand figure per match type. This is the bar a probe must clear (`>= floor`).
- `has_borrow_donor` (BOOL) + `donor_key` — whether a CONCLUSIVE donor exists per §4's ladder, and which.
- `is_probeable` (BOOL) — `NOT has_borrow_donor AND starved_keyword_count > 0 AND demand_signal >= floor`.
- `suggested_resolution` — `BORROW` (donor exists) | `PROBE` (no donor, probeable) | `NONE` (neither — leave on defaults, surface for manual attention).

Pure visibility + the driver for Components 2 and 3. Registered in `config.yaml`; a dashboard surface is a later add (not in C).

## 4. Component 2 — Borrow-similar (extends `tools/strategy_profile`)

A new step (e.g. `tools/strategy_profile/borrow.py`) runs **after** derivation. For each non-CONCLUSIVE cell, find the most-similar **CONCLUSIVE** donor by a priority ladder (first hit wins):

1. **Same** parent + match_type + intent, **other season**.
2. Same parent + intent, **nearest match_type** (EXACT↔PHRASE↔BROAD) — **cost-adjusted** (see below).
3. Same intent + match_type, a **sibling parent**.
4. Same parent + intent, **aggregate** across that intent's cells.

Write the donor's steering params into the gap cell with:
- `source='BORROWED'`, `borrowed_from=<donor cell key>`, `confidence` carried from donor.
- **Cap (the "with caps"):** borrowed `cpc_target/cpc_min/cpc_max` clamped to **≤ donor and ≤ 80% of donor's `cpc_target`** (a conservative haircut — never bid a borrowed guess above 80% of what the donor earns), and never above the global $2 ceiling.
- **Cost-adjust on cross-match (ladder step 2):** when the donor is a different match type, scale the borrowed `cpc_*` to the **target** match_type's own observed CPC level (from `V_KEYWORD_DAILY`), since exact/phrase/broad price differently — copy the *shape*, not the raw number.

**Steering:** extend `profile_steers` in `V_ADS_COACH_DATA` to include `source='BORROWED'`, so borrowed cells auto-steer exactly like CONCLUSIVE-derived ones (suppression + enabled flag). The cap is baked into the stored values, so no extra engine gate is needed. The existing MANUAL-preserving `load.py` keeps MANUAL rows; it now also **re-derives BORROWED rows each run** (a cell that earns its own CONCLUSIVE data graduates out of BORROWED automatically).

## 5. Component 3 — Probe (`target_action='PROBE'` in `V_ADS_COACH`)

For a keyword in a **PROBE-resolution cell** (`is_probeable`) that is itself **starved** (high `no_traffic_rate` / near-zero impressions), emit a new `target_action='PROBE'`:
- `recommended_bid` = **per-match-type probe launch CPC** = a conservative percentile (**p50**) of that `parent × match_type`'s real `cost_per_click` from `V_KEYWORD_DAILY`, capped at $2. Fallback when the parent has no cost data for that match type: the **same match type's** CPC level from a sibling parent (never cross match types — that would mis-price).
- A `probe` decision-trace chip: "probe: starved cell, no donor — exploring at $X (p50 of <parent> <match> CPC)".
- **Decision budget — 15 clicks or 14 days** (mirrors the existing new-campaign-launch track). Tracked in a new **`DE_PROBE_LOG`** (`keyword_id`, cell keys, `probe_started_at`, `clicks_accumulated`, `status` ACTIVE/GRADUATED/EXHAUSTED, `decided_at`):
  - **Graduates** when the keyword reaches 15 clicks (now it has real data → next derivation makes the cell DERIVED, probe ends naturally).
  - **Exhausted** after 14 days without 15 clicks → stop probing (not winnable); the cell falls back to `NONE`.
  - A daily step (small SP or the `strategy_profile` run) updates `DE_PROBE_LOG` from `V_KEYWORD_DAILY`.

**Signals to expose** in `V_ADS_COACH_DATA` (LEFT JOIN `V_STRATEGY_GAPS` / `DE_PROBE_LOG` by cell + keyword): `is_probe_cell`, `probe_launch_cpc`, `probe_status`. Placement of the PROBE branch: it acts only on starved keywords with no usable performance signal, so it sits where the launch/no-traffic logic lives (a starved keyword has no ROAS to drive the normal tiers) — it must **not** override an active REDUCE/STOP on a keyword that actually has (bad) data.

## 6. Data flow

```
V_KEYWORD_DAILY (A: cost, impressions, no_traffic) ─┐
DE_PRODUCT_STRATEGY_PROFILE (B: cells, confidence) ─┼─► V_STRATEGY_GAPS  (detect)
market/SQP demand (per match_type) ────────────────┘        │
                                                            ├─► borrow.py → DE_PRODUCT_STRATEGY_PROFILE (source=BORROWED, capped)
                                                            │       └─► V_ADS_COACH_DATA.profile_steers += BORROWED → V_ADS_COACH steers
                                                            └─► V_ADS_COACH (target_action='PROBE', per-type launch_cpc) ──► DE_PROBE_LOG (close the loop)
```

## 7. Scope

**In:** `V_STRATEGY_GAPS`; `tools/strategy_profile/borrow.py` + `profile_steers` extension + load.py re-deriving BORROWED; `target_action='PROBE'` + per-type launch CPC + `is_probe_cell`/probe signals in `V_ADS_COACH_DATA` + trace chip; `DE_PROBE_LOG` + its daily update; `config.yaml` registration.
**Deferred:** dashboard surfaces for gaps/probes; probing cells with **no** keywords (keyword creation = F); launching Bunny/LolliBall (product launch); auto-execution of probes (F).

## 8. Risks & limits

- **Borrowed params are guesses** — mitigated by the 80% haircut, clear `source=BORROWED` labeling, and automatic graduation to DERIVED once the cell earns its own data.
- **Probes spend real money** — bounded by: per-match-type CPC (no overpay), the 15-click/14-day budget, manual upload (Ori still approves), and the `is_probeable` demand floor (never probe no-demand junk). Probes that can't win exhaust and stop.
- **PROBE must not fight real signals** — gated to starved keywords only; a keyword with actual (even bad) performance is handled by the existing tiers, not probed.
- **Demand signal is per-match-type** — requires a market/SQP volume measure at the match-type grain; if unavailable for a cell, that cell is `NONE` (not probed), erring safe.
- Observational, US-only; the 4 advertised parents only.

## 9. Testing

- **`V_STRATEGY_GAPS`:** every WEAK/missing-but-active cell appears exactly once; a CONCLUSIVE-steering cell never appears; `suggested_resolution` is BORROW iff a donor exists, PROBE iff probeable, else NONE; `spend_at_risk` reconciles to 8w ads spend for a sampled cell.
- **Borrow:** a known WEAK cell with a CONCLUSIVE other-season sibling gets `source=BORROWED`, `borrowed_from` set, and `cpc_target ≤ 0.8 × donor`; a MANUAL row is untouched; a cell with no donor stays unborrowed; re-running after a cell earns CONCLUSIVE data flips it back to DERIVED. Row parity of the profile preserved (no fan-out); `V_ADS_COACH` row parity preserved.
- **Probe:** a starved keyword in a probeable cell yields `target_action='PROBE'` with `recommended_bid` = the per-match-type p50 CPC (exact/phrase > broad on the same parent), ≤ $2; a keyword with real performance in the same cell does **not** get PROBE; `DE_PROBE_LOG` rows go ACTIVE→GRADUATED at 15 clicks and ACTIVE→EXHAUSTED at 14 days; `reduce_inversions=0` and ceiling invariants unchanged.
