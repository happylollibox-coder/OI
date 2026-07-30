# Intent Campaign Grid — Operating Manual (SOP)

**Status:** ACTIVE · 2026-07-25 · Supersedes the *campaign* portion of
`INTENT_CAMPAIGN_MODEL.md` (that doc's facet/terminology sections remain useful history).
Spec: `docs/superpowers/specs/2026-07-25-intent-campaign-grid-design.md` (APPROVED by Ori
2026-07-25). Plan: `docs/superpowers/plans/2026-07-25-intent-campaign-grid-plan.md`.

## The model in one paragraph

A **cell** is `product × intent × rung`. Campaigns are **permanent** — all seasonal movement
is dated **bid/state changes** driven by the model (`T_INTENT_BID_BASE`), never
create/delete churn. The registry `DE_INTENT_CAMPAIGN` is the single source of grid
membership; everything joins through it on `campaign_id`. **Names are display-only**
(renamed-campaign trap: ME-AUTO ≡ "ME-SP/AUTO (discovery,Mint)" = id 527422818407259).

**Objective (Ori's ruling):** maximize monthly net profit **subject to a per-product
velocity floor** — on Amazon, velocity is an asset (badge tiers 50/100/500/1K, rank,
organic flywheel). Sell even if marginal. CVR alone mis-ranks: BOX $9.28 NP/unit @ 1.9% CVR
out-earns ME $3.18 @ 5.3%; margin is priced via `value_per_click = cvr_hat × gp_per_order`.

## Rungs

`BROAD_SP | EXACT | PHRASE | BROAD_VIDEO | BROAD_SPOTLIGHT` — values match CoveragePage
`STRAT_LABEL` keys exactly. Extended 2026-07-25: `AUTO` (per-product discovery unit,
intent_key='discovery') and `PT_ASIN` (competitor product-targeting, intent_key='competitor',
cell grain = product × targeted ASIN keyed on the `targeting` expression). Auto is never an
intent cell; its ASIN-page traffic stays out of the intent model; the exact-term
negativeExact fence extends into auto. Competitor cells price with the parent's pooled
comp-PT CVR as prior and borrow the keyword season curve (r=0.82).
**BROAD_SPOTLIGHT = Store Spotlight format (Ori 2026-07-26)**: the ad shows **3 Store
subpages** (cross-family showcase — e.g. Lollibox + Lolli Ball + Lolli Bunny), each subpage
with its own display name/selling text; the CAMPAIGN keeps single-intent keywords and
headline. Cross-family by design (the "≥2 products converge" earn rule is its natural
trigger). Console-first: the ad is built in Campaign Manager (subpage picker); bulksheets
then attach keywords/negatives to the campaign shell — do NOT try to create the ad via
bulk (Product Collection ≠ Store Spotlight; 3 rejection rounds proved it).
**Spotlights are INTENT-owned, not product-owned (Ori 2026-07-26)**: the ad shows all 3
configured families, so the campaign belongs to its intent. Naming =
`STORE-SPOTLIGHT (<intent-key>)`; registry rows carry product_short_name='STORE'.
One spotlight per intent; spotlights never share a keyword. **Earned, not granted**: Tier A starts SP Broad + Exact;
Video/Spotlight/Phrase are earned by performance; Tier B earns entry from Hunter
(clears 1k clicks AND profitable). Demotion = `PAUSED_DEMOTED` (90d net ROAS < floor at
conclusive clicks) — **pause, never delete**.

## Tiers

| Tier | 12m intent-attributed clicks | Entry |
|---|---|---|
| A | ≥ 5,000 | built directly (SP Broad + Exact) |
| B | 1,000–5,000 | earns entry from Hunter |
| LAUNCH | n/a | launch admission: ≥100 clicks AND CVR ≥ family prior |

## Bands (from DE_COACH_THRESHOLDS, strategy_id='INTENT')

| Band | expected net ROAS at market CPC | Behavior |
|---|---|---|
| RUN | ≥ 1.1 (`PROFITABLE_ROAS`) | run at `target_bid`, cap `max_cpc_run` |
| VELOCITY | 0.7–1.1 (`VELOCITY_ROAS`) | runs **only while product below velocity pace**; cheapest marginal sales first; cap `max_cpc_velocity` |
| MARGINAL | 0.5–0.7 (`INTENT_HOPELESS_ROAS`) | OFF unless PROBE |
| OFF | < 0.5 | paused, unconditional |

Hysteresis (**stateful — lives in the plan generator/checkpoint, not the view**): flip only
past floor ± 0.1, resume also on two consecutive checkpoints above the floor.
Velocity floor: `units_floor = GREATEST(badge_tier_defense(prev month), plan_units ×
VELOCITY_PACE_PCT)`; launch products substitute the `V_LAUNCH_RAMP` donor curve.

## Registry lifecycle (`DE_INTENT_CAMPAIGN`)

`PENDING_UPLOAD` (campaign_id = name placeholder) → reconciliation matches the name in
`FACT_AMAZON_ADS` first-sight and **locks the numeric id** → `ACTIVE` → `PAUSED_BAND` /
`PAUSED_DEMOTED` / `RETIRED`. `admitted_reason ∈ TIER_A_BUILD | ABSORBED | LAUNCH_ADMISSION
| TIER_B_GRADUATION | RUNG_EARNED`.

**Write discipline** (BigQuery has no PK enforcement; a bq CLI retry double-ran an INSERT on
2026-07-25): every insert path must carry an existence guard; prefer MERGE-by-key for
Phase 2+ writers.

## Naming

`{PREFIX}-SP/{BROAD|EXACT|PHRASE} ({intent_key}, {Variant})`, video
`{PREFIX}-VIDEO/EXACT (...)`. Prefixes: BOX (Lollibox), ME (LolliME), FRESH (Fresh),
BOTTLE (Bottle), MINT/BLUE/PINK variants keep their token. Collisions get a numeric suffix
**re-checked until unique** (" 2)", " 3)") — Amazon rejects in-file duplicate names.
Brand Defense campaigns are **never renamed** into the grid format.
Bidding Strategy on grid campaigns = **Dynamic bids - down only** (Ori 2026-07-25) —
the model prices the click; Amazon may lower, never raise past it.
Build-time state for TIME_BASED (holiday-facet) cells = **PAUSED regardless of band** —
they wake on `DIM_US_HOLIDAYS.boost_start` via the month plan's dated STATE row (Ori
2026-07-25: off-season christmas traffic ran 1,377 clicks / 6 orders in Jul-Aug).

## Keyword rules (build + ongoing)

- Exact: top-10 by SQP volume, **research rank > 75 gate**, CVR posterior
  (k=200 shrink to the cell's `base_cvr`).
- Broad: 3–5 diverse phrasings (token-Jaccard ≤ 0.6); a cell's Exact terms (new or
  absorbed) may **not** seed its Broad — they ship as negativeExact there (graduation).
- Self-competition: one owner per `(intent, term)` across Exacts — best value-per-click
  posterior wins; losers carry negativeExact.
- Family junk list (`V_PRODUCT_PHRASE_NEGATIVES`) ships campaign-level negativePhrase,
  with two carve-outs: (1) **facet protection** — a cell never negates its own intent
  tokens (`stuff/things` for `implied_low-*`, `toys` for `*-toys`); (2) **converter
  override** — a term with ≥3 orders/12m beats the colliding negative in that campaign
  only. **Brand tokens are never overridden** (brand negated everywhere except defense).
- Term-level bleed control is **search-term negativeExact** via the checkpoint — never
  loss-driven bid cuts in launch windows (2026-07-21 doctrine).

## Tools

| Tool | Does |
|---|---|
| `tools/intent_grid/absorb_existing.py` | proposes registry rows for existing campaigns (clicks-weighted majority intent, purity ≥ 0.60); `--apply` inserts confirm=y rows, guarded |
| `scripts/bigquery/views/V_LAUNCH_OPTIMIZER.sql` | launch-phase tracker (SETUP/RANK/EXIT/POST, verdicts, taper bids, budget recs) — cockpit launch module; coacher LAUNCH_TAPER gates on it |
| `tools/intent_grid/build_tier_a.py` | builds missing BROAD_SP/EXACT rungs for Tier-A cells → `exports/*_tier_a_build_bulksheet.xlsx` + PENDING_UPLOAD registry rows + `.tmp/tier_a_build_audit.csv` |

Both key on `campaign_id`, never name. Bulksheets are uploaded **manually by Ori**
(trust ladder VERIFY→APPLY; no Ads API writes).

## Monthly rhythm (Phase 2+, see plan)

`SP_GENERATE_INTENT_MONTH_PLAN` → `T_INTENT_MONTH_PLAN` rows
`(campaign_id, trigger_date, row_type, payload_key)`; DRAFT → APPROVED once monthly;
checkpoint appends PENDING_REVIEW rows through the existing coach-action flow; `/due`
emits APPROVED|ACCEPTED as dated bulksheets. Trigger dates: month starts (GENERIC),
`DIM_US_HOLIDAYS` boost/peak/holiday−2/cooldown (TIME_BASED). Attribution lag: any
order-bearing window ends at today−4.

## Known gaps (accepted at build time, 2026-07-25)

- 12 Tier-A EXACT cells shipped Broad-only (rank>75 gate starved them); graduation adds
  Exacts with checkpoint evidence. Bottle cells are structurally starved —
  `V_RESEARCH_RANKED` mis-segments Bottle/Bunny (see memory/family identities).
- Duplicate cells exist from absorption (3× Purple LolliME tween-girl-birthday-gift
  PHRASE; 2× White Lollibox teen-girl-gift EXACT) — consolidation is a Phase 2 decision.
- CVR curve pools history unweighted — lags recent improvement; checkpoint corrects.
