# Campaign Launch Ramp + Weekly Run Strategy Row — Design

**Date:** 2026-07-16
**Owner:** Ori

**Status:**
- Sub-project 1 (launch ramp) — `V_TARGET_DAILY` + `V_CAMPAIGN_LAUNCH_RAMP` **built, deployed, verified**.
- Waterfall exclusion — **superseded**, see "Budget is bottom-up" below.
- Sub-project 2 (Strategy row) — not started.
- Sub-project 3 (bottom-up budget) — **new, needs its own spec before any code**.

## Decision 2026-07-16 — budget is bottom-up; the global pool goes away

Ori: *"the total budget is not relevant — remove it."* Confirmed as the full reading: kill
`total_daily_budget` and the family split by profit. Every campaign's budget is set on its own merits —
the ramp while it is new, ROI once it is mature — and the "total" becomes a reported sum, not a dial to
divide.

This **dissolves the waterfall-exclusion problem**: with no pool, the ramp and the waterfall cannot
fight over a campaign's budget, because there is no waterfall. The exclusion described below is moot.

**`V_CAMPAIGN_DAILY_MOVE` already is this engine, and is currently dormant** (referenced only by
`V_CAMPAIGN_BID_CUT` — not by Cube, the frontend, or `app.py`). It gates on out-of-budget and lets net
ROAS decide: < 0.8 → bid cut, 0.8–2.5 → budget +10%, ≥ 2.5 → budget +30% — the same shape as the launch
ramp with different constants. It is clamped by exactly the thing being removed: *"Within-cap
reallocation (Ori 2026-07-05): targets are normalized to the family budget, so SUM(proposed_daily) per
family == the family cap."*

So the redesign is mostly: drop that normalization, wire the view up, and let the ramp hand off to it at
day 21 — which is Ori's "after 20 days coacher should handle it like a regular campaign".

Blast radius to work through in that spec: `V_FAMILY_BUDGET_ALLOCATION`, `V_CAMPAIGN_BUDGET_BASE`,
`V_BUDGET_STEP1_CAMPAIGN`, `V_BUDGET_ROLE_FAMILY`, `V_BUDGET_TOTAL_SUGGESTION`,
`V_EXPERIMENT_BUDGET_HEALTH`, `V_EXPERIMENT_SUGGESTED_CAMPAIGNS`,
`scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql`, `data-entry-app/app.py`, and frontend
`BudgetStep1.tsx`, `PeakPage.tsx`, `PlanPage.tsx`, `StepAdsPath.tsx`. Open question: what Step 1
becomes once there is nothing to divide.

Ori also chose: ramping campaigns get their **own RAMP tier** in the Step-1 table, showing the ramp
budget and day-of-ramp (e.g. "day 2 of 20") alongside WINNING/MARGIN/LOSING.

### Verified on deploy (2026-07-16)

`V_TARGET_DAILY` surfaces what `V_KEYWORD_DAILY` could not: AUTO = 32 campaigns / 116 targets / 32,378
clicks / fresh to 2026-07-16, `campaign_budget` never null. Auto targets carry a **null `keyword_bid`**
(they inherit the ad-group default), so the ramp can state a target bid but not a "from" bid.

Ladder hand-traced on BALL-SP/AUTO (Blue):
- 07-15: spend $10.14 >= budget $10.00 → maxed. `close-match` (10 clicks) and `loose-match` (4) both
  over the trigger → cut once each → $0.93. `substitutes` (0 clicks) → no cut → $1.00.
- 07-16: spend $0.42 < budget $10.00 → not maxed. `substitutes` took 5 clicks — over the trigger — and
  correctly did **not** cut. The self-arresting property, confirmed on live data.
- Gross profit $0 both days → no budget raise → target_budget holds at $10.00.

## Why

Ori is adopting the Coverage role model (`architecture/INTENT_CAMPAIGN_MODEL.md` §F) one role at a
time. Step one is **Auto**: on 2026-07-15 he launched 14 `*-SP/AUTO` campaigns, one per product, each
at a $10/day budget. Every one of them spent its full budget on day 1.

Those campaigns need a launch protocol of their own, and Weekly Run needs a way to work one strategy
role at a time. This document specifies both.

Two sub-projects, built in this order:

1. **Launch ramp** — replaces the existing launch track in `V_ADS_COACH`. Applies to every new
   campaign, not only Auto.
2. **Strategy row** — a role filter in Weekly Run, sharing one role definition with the Coverage page.

## Decision 2026-07-24 — the population is LOW BUDGET, not age (supersedes "first 20 days" below)

The launch controller no longer governs "a campaign's first 20 days". It governs **low-budget** campaigns:
daily budget **≤ $30 in peak** (inside any gift_season / prime_event boost→cooldown window) or **≤ $20
off-season**. Age is an arbitrary clock; budget states how much you are willing to risk while a campaign
is unproven — and unlike age it self-promotes.

**`V_LAUNCH_POPULATION` is the single definition.** Before this, "new" existed in three independent places
(`V_LAUNCH_PHASE1.camp`, `V_ADS_COACH.is_new_campaign`, `V_WEEKLY_RUN_CAMPAIGN.age_bucket`) which agreed
only because all three used the same age rule. Under a budget rule they drift, and a campaign then appears
in BOTH the launch cards and the mature table. All three now read this view.

- **Hysteresis:** membership requires budget ≤ cap for the last 3 complete days. Promotion is immediate;
  demotion needs 3 consecutive low days, so a campaign cannot oscillate between two engines whose cadences
  differ (launch = daily, working = weekly / 3-day).
- **The budget test reads the SETTING, not delivery (fix 2026-07-30).** The original test read
  `V_TARGET_DAILY.campaign_budget`, which only exists on days a campaign *delivered* — and only for SP.
  That silently dropped three whole groups from the launch population: every SB campaign older than 20
  days (no `V_TARGET_DAILY` rows ever — 10 campaigns incl. aged Brand Defense), dormant low-budget SP
  (no delivery in 3 days → invisible), and campaigns 100% dark from midnight (out of budget before the
  first impression, so the darkest campaigns were the ones the controller couldn't see). The test now
  reads `DIM_CAMPAIGN` SCD2: `budget_max_3d` = max `daily_budget` across rows whose effective window
  overlaps the last 3 complete days. The setting exists for every enabled campaign on both channels, so
  the old "no data ≠ low budget" guard is no longer needed — its job (don't default missing budgets to
  0) is done by the DIM row itself. Brand-new campaigns not yet in `DIM_CAMPAIGN` (SCD2 loads 3×/day)
  keep the explicit `age < 20d` fallback so they are coached from day 1.

**Budget-constrained probing in CAPPED campaigns (Ori 2026-07-30)** — supersedes "probe +5% even
if dark": in a campaign that is out of budget, under-4-clicks is a **budget artifact, not a bid
problem** ("we have 10 keywords, we want 4 clicks each = 40 clicks; at ~$1 CPC that is $40 of
probing demand on a $10 budget"). While `pct_dark > 10%`, the non-converting branch becomes:
tested ≥ 15 clicks/90d → **PARK at $0.25** (it had its test; free the budget for untested probes,
even if the parked bid goes quiet) · bid above the affordable CPC (`budget ÷ targets×4`, floor
$0.20 — Ori: "should not stop at $1.00") with clicks → **TRIM −15%/day toward it** ·
≥ 6 clicks yesterday → SLOW −5% · else HOLD (never probe up while capped). Probe +5% survives only
when the campaign is NOT capped. A found winner automatically becomes **main**: others park/trim,
the freed budget flows to him, ROAS ladder raises him, profitability triggers the budget promotion.
Applied identically in `V_LAUNCH_PHASE1`, `V_SB_LAUNCH_TARGET` and `V_OOB_KEYWORD` so the launch
cards and the Out-of-budget phase can never disagree.

**Budget promotion is the graduation mechanism** (in `V_LAUNCH_PHASE1`) — there is no separate "graduate"
rule. The controller raises budget while the campaign performs, and once budget clears the cap the campaign
drops out of `V_LAUNCH_POPULATION` and the coacher takes over:

| condition | new budget |
|---|---|
| using its budget AND prev-2d net ROAS ≥ 1.5× | `GREATEST(budget × 1.50, $20)` |
| using its budget AND today net ROAS ≥ 1.2×   | `GREATEST(budget × 1.25, $15)` |

The floors stop a proven campaign crawling up in percentage steps. Note off-season the strong floor ($20)
lands exactly ON the cap, so a strong performer graduates on its **second** good day ($20 → $30).

**The coacher's 14-day warm-up guard is retired.** It blocked `INCREASE_BID` under 14 days old; with a
budget population a campaign can graduate on day 5 and would then sit unable to raise bids for 9 days —
penalising exactly the campaigns that earned their way out. ⚠️ The guard is mirrored in **six** sites in
`V_ADS_COACH` (target_action, trace node, trace text, `recommended_bid`, `bid_change_pct`, summary action);
they must change together or the action, the bid and the explanation disagree. Left as dead `FALSE`
branches so it can be switched back on.

**`age_bucket`'s first bucket is now `LOW_BUDGET`** (was `NEW`), sourced from the population. The other
buckets stay genuinely age-based — "how old is it" and "which engine runs it" are now separate questions.

---

## Phase 1 — stabilize to profitable (shipped 2026-07-17, `V_LAUNCH_PHASE1`)

The ramp below (`V_CAMPAIGN_LAUNCH_RAMP`) was the first cut. Working through it on live day-1/2 data
(Ori, 2026-07-17) replaced its single compounding ladder with a two-lever controller. **Purpose of the
first 20 days: get the campaign STABLE — spending its budget across the whole day, not exhausted by
lunchtime — and PROFITABLE, then hand to the normal coacher on day 21.** It does **not** negate inside
20 days: a keyword with no sale yet idles cheaply ($6–$10/day) and either converts or is negated by
phase 2 on day 21. Live in `scripts/bigquery/views/V_LAUNCH_PHASE1.sql`; bulksheet via
`tools/build_launch_phase1_bulksheet.py`.

### Status source (decision 2026-07-30 — prefer consolidated sources)

Ori's standing rule: **prefer `DIM_`/`FACT_` (and the `V_SRC_` interface layer) over raw
`fivetran-hl` reads** — the consolidated sources carry both channels and the enrichment.

- **Serving-status events (dark %):** every dark computation reads
  `V_SRC_AmazonAds_campaign_history` — the unified SP∪SB event log (`date` = the status-change
  timestamp). Never the raw `campaign_history` / `sb_campaign_history` tables directly: a raw
  SP-only read silently missed all 9 out-of-budget SB campaigns on 2026-07-29.
- **Why not `DIM_CAMPAIGN` for dark %:** it is SCD2 *sampled at load time* (3 loads/day). A status
  flip that reverts between loads never becomes a version — VIDEO- BALL served 00:20–06:33 on
  07-28/29 but DIM shows one unbroken OUT_OF_BUDGET version since 07-27, so DIM-derived dark %
  reads 100% where the truth is 74%. Minute-grain replay requires the event log.
- **Identity / current state / names:** `V_DIM_CAMPAIGN_CURRENT` (rename-proof, both channels).
  `V_LAUNCH_POPULATION` keeps reading `V_SRC_` latest-per-campaign rather than the DIM because a
  brand-new campaign must enter the population the same day it is created ("coached from day 1"),
  and the DIM's 3×/day load can lag that by up to ~8h.

### Signals

- `roas_1d` — today's net ROAS (`GROSS_PROFIT/Ads_cost`, 1.0 = breakeven). Reactive.
- `eq3` — **equal-weight** mean of the last 3 daily net ROAS, ignoring days under 3 clicks, with a
  spend-pooled fallback when no day qualifies. Equal weight (not spend-pooled) so one bad day counts at
  full weight — "strong" means *consistently* good, which catches a volatile campaign (e.g. days
  2.06 / 0.13 / 1.79 → eq3 1.33, correctly not strong) that a pooled ratio would pass.
- `pct_dark` — the GATE for budget: Amazon's `CAMPAIGN_OUT_OF_BUDGET` share of the day (LA). No cap hit
  → no unmet demand → a budget raise is a no-op. `%active = 1 − pct_dark`.
- **"Today" is the last FULLY-ELAPSED day** (`LEAST(MAX(date), yesterday)`), never the current one — at
  09:00 the current LA day has ~10% of its spend and ~0 out-of-budget time, so every signal would read
  as a false zero.

### Bid (per target, clamp $0.20–$1.50)

| Condition | Action | Why |
|---|---|---|
| starving: `pct_dark ≤ 10% AND spend ≤ 60% budget` | ×1.10 | buy traffic even if losing — the campaign can't even spend its floor; more clicks/dollar = more shots at the first sale |
| **CUT: `eq3 < 0.9 AND roas_1d < 0.9`** | ×0.80 | **both** must be bad. A proven keyword (high eq3) on one dead day, or a recovering one (fine today), is spared — a launch controller needs two reasons to cut |
| strong: `eq3 > 1.5` | ×1.30 | consistently profitable |
| weak: `roas_1d > 1.2` | ×1.15 | reactive nudge on a good day |
| else | hold | deadband — fewer whipsaw moves |

The bid does **not** limit loss (a dark campaign spends its full budget at any bid); the budget floor
does. A losing non-converter therefore oscillates cheaply in the $6–$10/day band until it either
converts (ROAS tiers react instantly) or hands to phase-2 negate on day 21 — intended, not a bug.

### Budget (per campaign)

| Gate | Condition | Action |
|---|---|---|
| `pct_dark ≤ 10%` (not maxing → no unmet demand; bids do the work) | `spend ≤ 60% budget` | hold (starving; bids act) |
| | `eq3 < 0.6` | `GREATEST(budget×0.6, floor)` — cut losses |
| | `eq3 < 0.9` | `GREATEST(budget×0.9, floor)` — trim |
| | else | hold |
| `pct_dark > 10%` (maxing → real unmet demand, fund it) | `eq3 > 1.5` | `LEAST(budget/%active, budget×3)` — strong |
| | `roas_1d > 1.2` | `LEAST(budget/%active, budget×2)` — weak |
| | else | hold (maxing but mid ROAS → bids fix it) |

`%dark` is the natural budget cap: as budget grows to meet demand, the campaign stops going dark, the
gate closes, and raises halt on their own — no artificial ceiling needed. The ×3 cap only binds above
67% dark.

### Open items

- **Tuning constants live inline** in the view's `k` CTE (bid factors, caps, thresholds). Migrate to
  `DE_BUDGET_CONFIG` (`launch_dark_target`, `launch_spend_target`, `launch_bid_*`, `launch_bud_*`).
- **No-current-bid auto groups** (auto expressions inheriting the ad-group default) emit `bid_action =
  'NO_BID'` and are not in the bulksheet — they need a seed-bid policy first.
- **Low-volume raises** fire on thin evidence (e.g. a weak raise on one order / a few clicks). Optional
  guard: require `clk3 ≥ N` for raises.
- **Phase-2 handoff** at day 21 (`day_of_ramp > launch_ramp_days`) — the coacher and the day-21 negate
  are not yet wired to read `V_LAUNCH_PHASE1`.

## Sub-project 1 — Launch ramp (superseded by Phase 1 above)

### The rule

A campaign in its first 20 days starts at **$10.00/day budget** and a **$1.00 bid**. For each day `d`
in that window, **only if Amazon reported the campaign out of budget that day** (see "Out of budget is
Amazon's verdict" below — this was `spend(d) >= budget(d)` until 2026-07-17):

- every target with `clicks(d) > 3` → `bid × 0.93`
- if trailing-3-day net ROAS ending `d` > 1.5 → `budget × 1.10`

On day 21 the campaign leaves the ramp and the normal coacher takes over.

Compounded over the window:

```
target_bid    = 1.00 × 0.93 ^ (qualifying days for that target)
target_budget = 10.00 × 1.10 ^ (qualifying days for the campaign)
```

### Out of budget is Amazon's verdict, not ours (fixed 2026-07-17)

The ladder originally gated on `spend(d) >= budget(d)`. **That proxy was wrong three ways at once, and
every one of them made the ladder under-fire.** Ori spotted it: BUNNY-SP/AUTO (Proud) read "not maxed"
at $9.41 of $10.00 while Amazon's console showed it out of budget.

1. **The last few percent of a budget are unspendable.** Amazon stops serving when the remaining
   budget will not cover another click, so a $10.00 campaign at a ~$0.90 CPC goes out of budget at
   ~$9.40. On 2026-07-16, **every campaign between 91% and 100% was out of budget per Amazon and
   "not maxed" per the proxy — 8 of 14 out-of-budget days missed, a 57% false-negative rate.**
2. **`campaign_budget` is restated, not historical.** `targeting_report.campaign_budget_amount`
   carries the campaign's *current* budget on every historical row. ME-SP/AUTO (Pink) really ran a $10
   budget on 07-15 and spent $10.55 — genuinely maxed — but the report stamps 07-15 with the $26 it
   was raised to at 11:39 on 07-16, so the ladder computes `$10.55 >= $26` → not maxed. Because the
   ladder is a replay of history, **a single budget change silently rewrites the whole 20-day past.**
3. **Daily spend is not capped at the daily budget.** Amazon borrows against underspent days, so spend
   legitimately reaches ~2× budget (BOTTLE-SP/AUTO: $29.90 on $15). The proxy's `>=` is not a
   meaningful line — it is crossed trivially on catch-up days and missed entirely on tight ones.

**The fix:** `fivetran-hl.amazon_ads.campaign_history.serving_status` carries Amazon's own
`CAMPAIGN_OUT_OF_BUDGET`, recorded at the time with transitions through the day:

```
BUNNY-SP/AUTO (Proud), times in America/Los_Angeles
  07-15 07:00  CAMPAIGN_STATUS_ENABLED
  07-15 21:34  CAMPAIGN_OUT_OF_BUDGET     ← day 1: out of budget
  07-16 00:03  CAMPAIGN_STATUS_ENABLED    ← midnight reset
  07-16 16:50  CAMPAIGN_OUT_OF_BUDGET     ← day 2: out at $9.41 of $10.00
```

A campaign-day is out of budget if **any** row that day reads `CAMPAIGN_OUT_OF_BUDGET`. This needs no
budget number at all, so it dissolves bugs 2 and 3 along with 1.

**`last_updated_date` is Fivetran UTC and must be converted to `America/Los_Angeles`** before grouping
by day, or evening rows land on the following day — Proud's first out-of-budget (UTC 07-16 04:34) is
really LA 07-15 21:34, which is a different rung of the ladder.

Coverage is 93%: over the ramp cohort, 4 of 56 campaign-days have no status row (Fivetran writes on
change). Those fall back to the old `spend >= budget` proxy, which is the pre-fix behaviour — never
worse than today, and only on days Amazon told us nothing.

### The ladder must never raise a bid (fixed 2026-07-17)

`target_bid = 1.00 × 0.93^n` is anchored at a **constant** $1.00 and only steps down *from there*. That
is a prescription for a campaign you launch at $1.00 — but it was being applied as a retroactive
*assumption* about campaigns that launched at whatever bid they were given. None of them started at
$1.00: real bids average **$0.75**, and even the 2026-07-15 Auto cohort launched around $0.80–$0.90.

The result inverted the ladder's entire purpose. Measured 2026-07-17 across the 78 live ramp targets:

| Direction | Targets | Avg current | Avg ramp bid | Avg move |
|---|---|---|---|---|
| **RAISE — ramp bid above current** | **52** | $0.75 | $0.97 | **+33%** |
| cut — ramp bid below current | 3 | $0.88 | $0.79 | −12% |
| no current bid (auto inherits ad-group default) | 23 | — | $0.98 | — |

**52 of the 55 targets with a known bid would go up.** Wiring `target_bid` to the bulksheet as-is would
have raised 52 bids by an average of 33%, concentrated on BUNNY- BROAD and BALLS- BROAD — which had
together burned $607 at 0.25–0.45× net ROAS. Worst case: `bunny plush` $0.36 → $1.00, **+178%**.

**The fix:** `target_bid = LEAST(1.00 × 0.93^n, current_bid)`. The ramp may only ever cut. Where
`current_bid` is NULL (auto groups inherit the ad-group default) the cap falls back to `launch_start_bid`,
preserving the original behaviour for the only case where it was correct.

**Known consequence — the ladder goes inert below $1.00.** A keyword already at $0.36 sits under every
rung, so it never moves. That is right for a ramp whose premise is "start at $1.00 and walk down," but
it means pre-existing campaigns get budget management and nothing else. The alternative — anchoring each
target on its own *first observed* bid (`first_bid × 0.93^n`) — would give a faithful ladder from any
starting point. **That is a design decision for Ori, deliberately not taken here**; this fix is the
minimal one that makes the ramp safe.

### Why there is no bid floor

The ladder is self-arresting. It only steps down on a day the campaign spent its entire budget, so if
bids fall far enough to starve delivery, the campaign stops filling its budget, the condition stops
firing, and the ladder halts on its own. A floor would be redundant.

### Why no scheduled job

Every condition is evaluated against **observed history** — that day's spend, that day's clicks, that
day's ROAS. Nothing is counterfactual, so the ramp is a pure view over history: it recomputes on read
and is always current. No daily SP, no state table.

Execution model: the engine computes the ramp daily; Ori uploads the bulksheet when he sits down, and
it carries wherever the ladder has reached. Fewer, larger steps than 20 literal daily uploads — the
ladder is the model, not the upload cadence.

### The workflow

Per-day evaluation. Every branch reads observed history, so the whole ladder is a replay:

```
for each day d from campaign_created, while day_of_ramp <= 20 and d <= ads watermark:

  spend(d) >= budget(d) ?            budget(d) = the ACTUAL Amazon budget that day
    │
    ├── no  → nothing fires this day. Starved delivery arrests the ladder by itself.
    │
    └── yes → the campaign maxed out
          ├── per target:  clicks(d) > 3          → n_cut_days   += 1
          └── per campaign: trailing-3d net ROAS ending d > 1.5 → n_raise_days += 1

  target_bid    = $1.00  × 0.93 ^ n_cut_days      (per target)
  target_budget = $10.00 × 1.10 ^ n_raise_days    (per campaign)
```

Pipeline. Nothing here is materialized — Cube reads `V_BUDGET_STEP1_CAMPAIGN` directly, so a ramp
edit is live on the next read with no SP and no `T_*` rebuild:

```
DE_BUDGET_CONFIG ─────────────────┐  8 launch_* knobs
V_SRC_AmazonAds_campaign_history ─┤  creation_date, state='ENABLED'
FACT_AMAZON_ADS ──────────────────┤  spend(d), GROSS_PROFIT(d), watermark
V_TARGET_DAILY ───────────────────┘  clicks(d), keyword_bid, campaign_budget(d)
  ├── targeting_keyword_report (keywords)
  └── targeting_report         (auto groups)
                ↓
      V_CAMPAIGN_LAUNCH_RAMP  (grain: campaign × target)
        ├── budget ladder → target_budget, day_of_ramp
        │     └── V_BUDGET_STEP1_CAMPAIGN  (tier='NEW', new_budget ← ramp not waterfall)
        │           └── Cube: CampaignBudgetStep1
        │                 └── BudgetStep1.tsx — Weekly Run Step 1, "day N of 20"
        └── bid ladder → target_bid, n_cut_days
              └── ⚠ NO CONSUMER — computed on every read, never surfaced or uploaded
```

The bid ladder is the half that has not landed. `target_bid` is correct and live in the view, but no
Cube schema, page, or bulksheet reads it, so the $1.00 × 0.93^n step-down reaches Amazon only if it is
typed by hand. **The launch track it was meant to replace is still the one moving bids in production:**

```
V_ADS_COACH  (LAUNCH_* branch, DE_COACH_THRESHOLDS — old defaults, 30d/15-click/−20%)
  └── SP_REFRESH_ADS_COACH_ACTIONS → FACT_ADS_COACH_ACTIONS
        └── Cube: AdsCoachActions
              └── ActionsPage.tsx "New campaigns" → DoPage bulksheet → Amazon
```

So the two systems have split the campaign, not replaced each other: the ramp owns its **budget**, the
old track owns its **bids**, and they disagree on the window (20d vs 30d) about which campaigns are new.

### Data sources (verified 2026-07-16)

| Input | Source | Notes |
|---|---|---|
| **out of budget(d)** | **`campaign_history.serving_status = 'CAMPAIGN_OUT_OF_BUDGET'`** | **Amazon's own verdict, per LA day. The ladder's gate since 2026-07-17.** Convert `last_updated_date` from UTC. |
| `budget(d)` | `targeting_report.campaign_budget_amount` | ⚠️ **RESTATED, not historical** — carries the *current* budget on every past row. No longer gates the ladder; used only for the 7% of campaign-days with no status row, and for reporting `current_budget`. |
| `spend(d)` | `FACT_AMAZON_ADS.Ads_cost` | Campaign grain, per date. |
| `clicks(d)` per target | `targeting_report.clicks` | See blocker below. |
| current bid | `targeting_report.keyword_bid` | |
| net ROAS | `FACT_AMAZON_ADS.GROSS_PROFIT / Ads_cost` | Same formula as `V_CAMPAIGN_BUDGET_BASE.perf7`. |
| creation date | `V_SRC_AmazonAds_campaign_history.creation_date` | Ramp counts 20 days from here. |

### BLOCKER — auto targets are invisible today

`V_KEYWORD_DAILY` sources `fivetran-hl.amazon_ads.targeting_keyword_report`, which contains **keywords
only**. A 90-day scan returns rows for `BROAD`/`EXACT`/`PHRASE` and **zero** rows for `Automatic`.
The bid ladder therefore cannot see a single target on the 14 new Auto campaigns.

Fix: `fivetran-hl.amazon_ads.targeting_report` carries all four predefined auto groups
(`close-match`, `loose-match`, `substitutes`, `complements`, `keyword_type =
TARGETING_EXPRESSION_PREDEFINED`) with `keyword_bid`, `clicks`, `cost`, per date, fresh through
today — 32 campaigns, ~11.8k clicks on `substitutes` alone over 90 days.

**New view `V_TARGET_DAILY`** — `V_KEYWORD_DAILY`'s shape, unioned across both reports, so every
targetable entity (keyword *and* auto group) appears at one grain. The ramp reads `V_TARGET_DAILY`.
Whether the coacher's other keyword surfaces migrate onto it is out of scope here.

### Replaces the existing launch track

`V_ADS_COACH.sql:139-206` reads nine `LAUNCH_*` keys from `DE_COACH_THRESHOLDS`. The new rule supersedes it:

| Threshold | Current default | New |
|---|---|---|
| `LAUNCH_WINDOW_DAYS` | 30 | **20** |
| `LAUNCH_COLD_BID` | 1.2 × CPC band | **flat $1.00** |
| `LAUNCH_STEP_DOWN_PCT` | 0.2 | **0.07** |
| `LAUNCH_CHECKPOINT_CLICKS` | 15 (lifetime) | **> 3 clicks in the previous day** |
| `campaign_launch_floor_daily` | $10 | $10 — unchanged |
| budget raise | *none* | **× 1.10 when trailing-3d net ROAS > 1.5** |

New keys needed: `LAUNCH_START_BID` ($1.00), `LAUNCH_BUDGET_RAISE_PCT` (0.10), `LAUNCH_RAISE_ROAS`
(1.5), `LAUNCH_RAISE_ROAS_DAYS` (3), `LAUNCH_DAILY_CLICK_TRIGGER` (3). Retire `LAUNCH_BID_MULT`,
`LAUNCH_BID_CEILING`, `LAUNCH_STEP_DOWN_PCT`'s old semantics.

### Required interactions

- **`V_CAMPAIGN_BUDGET_BASE` must exclude ramping campaigns.** The ramp owns their budget; the $750
  offense waterfall splits across mature campaigns only. Otherwise the ramp raises to $15 and the
  waterfall's LOSING $10 floor pulls it back the same week.
- **The ramp must be exempt from the cooldowns.** GUARDIAN's one-bid-change-per-keyword-per-7-days and
  the 3-day re-suggest cooldown would each swallow the ladder.

### Assumptions

1. ~~`budget(d)` is the **actual** budget on Amazon that day — that is what really capped spend.~~
   **FALSIFIED 2026-07-17.** `targeting_report.campaign_budget_amount` restates every historical row
   with the campaign's *current* budget, so `budget(d)` was never the budget on day `d`. The ladder no
   longer asks the question — Amazon's `serving_status` answers it directly. See "Out of budget is
   Amazon's verdict" above.
2. The 20 days count from **campaign creation date**, not from first spend or from adoption date.
3. "each keyword" means **each target** — auto groups ramp exactly like keywords.
4. **The $1.00 start bid is a prescription, not an observation.** Campaigns launched before the ramp
   existed started wherever Ori put them (avg $0.75). The ladder is capped at `current_bid` so it can
   only cut — see "The ladder must never raise a bid" above.

## Sub-project 2 — Weekly Run Strategy row

### `V_CAMPAIGN_ROLE`

One row per campaign, carrying the 8-role classification (`AUTO`, `BRAND_DEFENSE`, `PRODUCT_DEFENSE`,
`EXACT`, `BROAD`, `PHRASE`, `COMPETITOR`, `SB_VIDEO`), lifted out of the `camp_role` CTE currently
inlined in `/api/coverage` (`data-entry-app/app.py:9038`). Coverage and Weekly Run then share one
definition instead of forking it, and the rule lives in BigQuery per the all-logic-in-backend rule.

Normalize case while lifting: `FACT_AMAZON_ADS.targeting_type` holds both `broad` (56.6k clicks) and
`BROAD` (16.1k), `exact`/`EXACT`, `phrase`/`phrase`. The current CASE survives via `UPPER()` on some
branches but matches `'Automatic'`, `'Category'`, `'ASIN'` case-sensitively.

Once the view exists, `/api/coverage` should read it rather than keep its inline copy.

### Surface

- Exposed as `CoachRunCampaign.strategyRole` (add the column to `V_WEEKLY_RUN_CAMPAIGN`, then
  `SP_REFRESH_CUBE_TABLES` to rebuild `T_WEEKLY_RUN_CAMPAIGN` — Cube reads `T_*`, not `V_*`).
- A Strategy toggle row in `WeeklyRunPage.tsx`, directly below the PPC toggle. **Offense mode only** —
  Brand Defense and Product Defense are already their own PPC modes. All roles clickable.
- Picking a role filters the campaign list and keyword work below it (extends `campVisible`).
- **Step 1 stays whole.** It keeps totalling the $750 across mature campaigns. This resolves itself:
  ramping campaigns are outside the waterfall anyway, so Auto campaigns show their *ramp* budget while
  Step 1 continues to mean "the total budget".

## Registration

Per the project constitution, every new BigQuery object goes in `config.yaml`: `V_TARGET_DAILY`,
`V_CAMPAIGN_LAUNCH_RAMP`, `V_CAMPAIGN_ROLE`.

## Money-bleeder guard (bid CASE, before STARVE)

The campaign-level **STARVE** raise (campaign spent <60% of budget → buy traffic) must not be applied to a
target that is itself a heavy-spending **non-converter** — a campaign can under-spend in total while one
target hogs the budget and converts nothing (Ori, on VIDEO- BALL "gift for girls": $11.03 of $14.64, 10
clicks, 0 sales, yet the controller said "raise"). So a **money-bleeder ladder** sits at the TOP of the bid
CASE, **before STARVE and CUT**, keyed on `sales3 <= 0` (0 conversions over the window):

| clicks (clk3), 0 sales | action | bid |
| --- | --- | --- |
| < 4 | (falls through to) PROBE | ×1.15 — still raised (unproven, buy traffic to judge) |
| 4–7 | `BLEED_WATCH` | hold (gather; not raised, not cut yet) |
| ≥ 8 | `BLEED_TRIM` | ×0.80 (−20%, stop the bleed) |
| ≥ 15 | `BLEED_CUT` | ×0.60 (−40%, Ori's decision point) |

Keyed on 0 conversions, NOT net ROAS — a converting-but-unprofitable target still takes the normal
STARVE/CUT path. Identical in `V_LAUNCH_PHASE1` (SP) and `V_SB_LAUNCH_TARGET` (SB). Constants in each `k` CTE.

## Risks

- **The ramp is live now.** 19 enabled campaigns sit inside a 20-day window (14 Auto from 2026-07-15,
  2 BROAD from 07-03, plus 3 with no spend yet). Whatever ships will act on real money immediately.
- **Day-1 maxing.** All 14 Auto campaigns spent their full $10 on day 1, so both branches fire from the
  first evaluated day. The ladder will move fast; check the first computed output before uploading.
- **Replacing the launch track changes behaviour for non-Auto new campaigns too** (the 2 BROAD
  campaigns from 07-03). That is intended — one launch track — but it is a behaviour change beyond Auto.
- **`V_TARGET_DAILY` is a new grain.** Auto groups have no `keyword_text`; anything joining on text
  rather than `keyword_id` will not match them.

## Sponsored Brands (incl. video) — campaign-level card

SB launch campaigns (e.g. `VIDEO- BALL`, `VIDEO- COMP/BALL`) appear in the launch universe
(`V_LAUNCH_PHASE1`) because `campaign_history` includes them while <20 days ENABLED. `FACT_AMAZON_ADS`
undercounts SB at every grain (search-term rows only — e.g. `VIDEO- BALL` 2026-07-18: FACT 8 clk / 60 impr
vs the true **14 clk / 388 impr**, real CTR **3.61%**), so SB is served from the native Fivetran SB tables.

### SB table map (which is current, and what each can give)

| table | freshness | grain | usable for |
| --- | --- | --- | --- |
| `sb_campaign_report` | **current** | campaign×day | true impressions / CTR / spend / clicks / sales (campaign header) |
| `sb_search_term_report` | **current** | keyword_id×day | correct **clicks / spend / sales** per keyword (⚠️ impressions undercount) |
| `sb_keyword` | **current** | keyword (config) | keyword text · match · **bid** · state (no performance) |
| `sb_keyword_report` | **dead 2025-12-29** | keyword×day | *would* give true per-keyword impressions/CTR — unavailable |
| `sb_target_report` | current | product-target×day | product-targeting SB (not keyword-targeted video) |

**Two-level card, both from current data:**

**(1) Campaign header** — from `V_SB_LAUNCH_CAMPAIGN` (cube `SbLaunchCampaign`):

- **r2 = anchor day** (`FN_ADS_ANCHOR_CAP`), **r3 = the prior 2 days** — same windows as the SP card.
- Measures: spend · CPC · clicks · **CTR** · ACoS, all from the campaign report.
- **TOS is deliberately blank ("—")** — the only SB top-of-search field, `top_of_search_impression_share`, is
  the **placement mix** (% of impressions rendered at top, ~0.86 for these video campaigns), NOT the
  competitive "Top-of-search IS" Amazon's UI shows (<5% for a new advertiser). An impression *share* can't be
  86% when every keyword is <5% — they are different metrics. The real SB top-of-search IS is per-keyword and
  lives only in the dead `sb_keyword_report` → unavailable. **units are not reported** by SB → also "—".
- Verified 2026-07-19 against the Amazon UI (VIDEO- BALL, Jul 18): spend $14.64 · CPC $1.05 · 14 clicks ·
  388 impr · CTR 3.61% · $0 sales all tie out exactly.
- **net ROAS is an estimate** — the SB report has sales (`attributed_sales_14_d`) but no units/COGS, so
  gross profit ≈ `sales × (1 − cost_per_unit/list_price)` via the campaign's mapped ASIN
  (`ASIN_BY_CAMPAIGN_NAME` → `DIM_PRODUCT.listing_price_amount` + latest `DIM_COSTS_HISTORY` cost).
- **BUDGET suggestion** runs the **same CASE + `k` constants as `V_LAUNCH_PHASE1`**, but on SB-native signals
  (`V_LAUNCH_PHASE1` gives SB a NULL budget and undercounted FACT spend — $8.67 vs true $14.64): budget +
  `%dark` from `sb_campaign_history` (its `serving_status` uses the same `CAMPAIGN_OUT_OF_BUDGET` string),
  spend + campaign net ROAS from `sb_campaign_report`. ⚠️ SB history is sparse (a non-capping campaign has few
  rows → `%dark` reads 0, which is correct when it isn't capping, but could under-detect a real cap).
- The card (`NewCampaignCards.tsx`) marks these `isSb`: an amber "SB" badge; the header table + an amber note;
  the budget row + per-target drill behave like SP (suggestion pre-filled, apply-all). SB rows are detected by
  joining `V_LAUNCH_PHASE1` to `FACT_AMAZON_ADS.campaign_type = 'SB'`.

**(2) Per-target drill + BID suggestion** (expandable) — from `V_SB_LAUNCH_TARGET` (cube `SbLaunchTarget`),
covering **keyword-targeted AND product-targeted** SB (one row per target, like SP's `RunTarget`):

- **Keyword arm**: list + **bid** + match from `sb_keyword`; clicks/spend/sales from `sb_search_term_report`
  (keyword_id grain). **Product arm**: list + **bid** from `sb_product_target`; perf + label (`asin="…"`) from
  `sb_target_report` (target_id grain). Bids match the Amazon UI; clicks/spend **reconcile exactly** to the
  campaign totals (VIDEO- BALL: 10+3+1 = 14 clicks, $14.64).
- **BID suggestion** runs the **identical CASE + order as `V_LAUNCH_PHASE1`** (NO_BID → STARVE → PROBE → CUT →
  dark HOLD → BRAKE → RAISE_STRONG → RAISE_WEAK → HOLD), on SB-native target signals (per-day net-ROAS est)
  + the campaign signals above. Verified: VIDEO- BALL keywords STARVE (campaign at 49% budget → buy traffic);
  VIDEO- COMP/BALL product targets PROBE (<4 clicks) or HOLD (deadband). Bids editable, queue as
  `SPONSORED_BRANDS`, included in apply-all.
- **No per-target impressions/CTR in the drill.** Keyword impressions only survive at search-term grain
  (undercount — report 70 vs true 276 for "gift for girls"); product impressions ARE true in
  `sb_target_report` but the drill stays uniform (clicks/spend/sales/net-ROAS only). The header keeps true CTR.
- net ROAS per target = same estimate as the header (`sales × (1 − cost_ratio)`).
- Registration: `V_SB_LAUNCH_CAMPAIGN` + `V_SB_LAUNCH_TARGET` in `config.yaml`; both read directly as views
  (small; not `T_` tables).
- **Deferred:** SB `%dark` reliability under sparse history; extending the price-tier corrected COGS (SP uses
  `T_PRICE_COST_TIER`) to SB net ROAS instead of the list-price estimate.
