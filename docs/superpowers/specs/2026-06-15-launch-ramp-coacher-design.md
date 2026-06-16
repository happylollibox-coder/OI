# Launch-Ramp Coacher — Design Spec

- **Date:** 2026-06-15
- **Owner:** Ori
- **Status:** Approved design → ready for implementation plan
- **Architecture choice:** Approach A (new isolated campaign-grain view, advisory on the DO/Actions page)

## 1. Problem

New `EXACT_BOOST` boost campaigns created by the DO-page generator have no lifecycle management in their first weeks. Two failure modes the normal coacher doesn't handle:

- **Not serving:** bid too low to win the entry auction → ~0 impressions (e.g. `BOX-VIDEO/EXACT (Boost, 11 year old girl)` sat at 0 impressions). Nothing escalates the bid.
- **Serving but unproven:** a few clicks, 0 orders. The keyword-level insufficient-data gate (`min_clicks`) correctly holds everything at `MONITOR`, so a clearly-failing launch lingers with no kill signal.

There is no automated *entry-bid ramp* and no automated *kill* for launch campaigns. The owner wants an **advisory** launch lifecycle surfaced on the DO/Actions page (human approves every change).

## 2. Goals / Non-goals

**Goals**
- Per-campaign launch **state** during a launch window, rendered as advisory cards the owner approves.
- Phase A: ramp the bid to win entry; cap it, then recommend close.
- Phase B: after enough clicks, recommend reduce-bid (chase net ROAS) or close.
- Every number lives in `DE_COACH_THRESHOLDS` — no hardcoding.

**Non-goals**
- No fully-automated bid changes or closes — the owner queues + uploads each (Q1 decision).
- No changes to the keyword-level `V_ADS_COACH` decision logic.
- Not a replacement for the normal coacher after graduation.

## 3. Scope

`EXACT_BOOST` campaigns where `campaign_age_days <= LAUNCH_WINDOW_DAYS` (default **21**). After the window the campaign **graduates** — it drops out of this view and the normal coacher governs it.

## 4. Architecture (Approach A)

| Object | Type | Purpose |
|---|---|---|
| `V_CAMPAIGN_LAUNCH_COACH` | View (campaign grain) | Computes launch state + action per in-window campaign |
| `T_CAMPAIGN_LAUNCH_COACH` | Table | Materialized via `SP_REFRESH_CUBE_TABLES` (mirrors `V_CAMPAIGN_LAUNCH_PERF`) |
| `CampaignLaunchCoach` | Cube | Serves the table to the dashboard |
| `data.launch_coach` (`LaunchCoachRow[]`) | Dashboard | Loader in `useCubeData`; new "Launch" section + cards; bulksheet emission |

**View inputs:** `FACT_AMAZON_ADS` (impr/clicks/orders/spend), `V_CAMPAIGN_LAUNCH_PERF` (age, active days), `FACT_PPC_CHANGE_LOG` (days since last bump → enforces hold), `DE_COACH_THRESHOLDS`, current bid.

## 5. State machine (per campaign, each refresh)

Serving signal: `impr_per_active_day = impressions_since_launch / NULLIF(active_days,0)`. "Not serving" = `< LAUNCH_IMPR_FLOOR` (default 10).

**Phase A — not serving**
- `bid < CAP` AND `days_since_last_bump >= HOLD_DAYS` → **`RAMP_BID`** = `round(current_bid * (1 + STEP_PCT/100), 2)`, capped at `CAP`
- `bid >= CAP` (still not serving) → **`CLOSE`**
- otherwise → **`WAIT`** (no card; lag hasn't resolved)

**Phase B — serving**
- `clicks < MIN_CLICKS` → **`WAIT`**
- `clicks >= MIN_CLICKS` AND `orders = 0` → **`CLOSE`**
- `clicks >= MIN_CLICKS` AND `orders > 0` AND `net_roas < BREAKEVEN` → **`REDUCE_BID`**
- `net_roas >= BREAKEVEN` → **`GRADUATE`** (no card)

`launch_action ∈ {RAMP_BID, REDUCE_BID, CLOSE, WAIT, GRADUATE}`. Only the first three render cards. Each row carries a `launch_decision_trace`.

## 6. Advisory flow + bulksheet emission

Launch cards on the DO/Actions page → owner approves → bulksheet export: `RAMP_BID`/`REDUCE_BID` = SP Keyword/Ad-Group **Update** with new Bid; `CLOSE` = SP Campaign **Update** `State=PAUSED`. Every applied change logs to `FACT_PPC_CHANGE_LOG`, which feeds `days_since_last_bump` next cycle.

## 7. Thresholds (`DE_COACH_THRESHOLDS` seed — all tunable)

| Key | Default | Meaning |
|---|---|---|
| `LAUNCH_WINDOW_DAYS` | 21 | Days governed by the launch coach |
| `LAUNCH_IMPR_FLOOR` | 10 | Impressions/active-day below which = "not serving" |
| `LAUNCH_BID_STEP_PCT` | 20 | Phase-A ramp step |
| `LAUNCH_BID_CAP` | 1.30 | Max ramp bid before recommending close |
| `LAUNCH_HOLD_DAYS` | 3 | Min days between ramp bumps (lag-aware) |
| `LAUNCH_MIN_CLICKS` | 10 | Clicks before a Phase-B verdict |
| `LAUNCH_BREAKEVEN_ROAS` | 1.0 | Net-ROAS line: reduce vs graduate |
| `LAUNCH_REDUCE_STEP_PCT` | 15 | Phase-B reduce-bid step |

## 8. Reconciliation with existing logic

The 14-day `INCREASE_BID` block in `V_ADS_COACH` stays (no ROAS-scaling on young campaigns). This view never ROAS-scales — it owns only the entry-ramp and the kill during the window — so no overlap. `CLOSE` reuses the `PAUSE_CAMPAIGN` concept. After the window the campaign exits this view.

## 9. Data lag

Ads data lags 1–2 days; `LAUNCH_HOLD_DAYS = 3` between bumps ensures a bid change's effect is visible before the next escalation.

## 10. Build steps

1. SQL: `V_CAMPAIGN_LAUNCH_COACH` + `T_CAMPAIGN_LAUNCH_COACH`; register in `config.yaml`; add table to `SP_REFRESH_CUBE_TABLES`.
2. Seed the 8 `LAUNCH_*` thresholds in `DE_COACH_THRESHOLDS`.
3. Cube `CampaignLaunchCoach`.
4. Dashboard: `LaunchCoachRow` type + loader + `data.launch_coach` + `EMPTY` default; "Launch" section + cards; bulksheet emission in `DoPage`.
5. SOP first: update `architecture/ADS_COACH_DECISION_MATRIX.md`.
6. Tests: pure state-machine function (TS) table-driven per branch; SQL validation queries.

## 11. Open items to resolve in the implementation plan

- Current-bid source at campaign/keyword grain.
- Net ROAS at campaign grain in SQL (don't reinvent the Cube metric).
- Page placement: DO page vs Actions page "Launch" section.

## 12. Testing

- Pure state-machine function with table-driven tests for every branch (Phase A ramp/cap→close/wait; Phase B wait/close/reduce/graduate).
- SQL: row-count + spot-check against known launch campaigns (e.g. `BOX-SP/EXACT (Boost, 11 year old girl)`).
- Dashboard: card render + bulksheet emission verified in the preview.
