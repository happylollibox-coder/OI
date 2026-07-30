# Intent campaign grid + date-precise coacher workflow

Date: 2026-07-25
Status: Draft for review
Owner: Ori

## Objective

Restructure ads around **campaigns per product × intent × rung**, with a **monthly, date-precise
coacher workflow** that moves bids instead of creating/deleting campaigns at season boundaries.

The objective function is NOT "maximize ROAS" and NOT "maximize sales":

> **Maximize monthly net profit, subject to a per-product velocity floor, an inventory gate,
> and a bleed floor.**

Why velocity is a constraint, not a preference (measured 2026-07-25):

- White Lollibox units fell 442 (Apr) → ~160 (Jul pace) and **organic share collapsed with
  them, 68% → 42%** — the badge/rank flywheel unwinding. A strict ROAS pause on its biggest
  intent in Jun–Jul (expected net ROAS 0.93/0.88) would have accelerated exactly this.
- The Home tiles the same week: BOX $9.28 NP/unit on 107 units (profit engine, velocity dying)
  vs ME $3.18 NP/unit on 277 units (velocity engine, margin being eaten). One global rule gets
  one of them wrong; the objective must trade them off explicitly.
- CVR alone mis-ranks products: BOX 1.9% CVR out-earns ME 5.3% CVR because GP/order is ~$21
  vs ~$13. All pricing is `CVR × GP/order`, never CVR.

## 1. The grid

**Cell = product × intent × rung.** Rungs (the Coverage cockpit's five): `SP Broad`, `Exact`,
`Phrase`, `Broad Video`, `Broad Spotlight`.

**Campaigns are permanent.** Month/season NEVER creates or deletes campaigns — all seasonal
movement is bids/budget/TOS/state on trigger dates. This is what makes date precision possible:
bid changes are instant, campaign creation takes 1–4 days (SP 1–2, SB video 3–4).

Sizing (measured, trailing 365d, excluding brand/competitor/placement traffic):

| Tier | Threshold | Pairs | Rungs at creation |
|---|---|---|---|
| A | ≥5,000 clicks | 24 | SP Broad + Exact (48 campaigns) |
| B | 1,000–5,000 | 80 | none — **earns entry** from Hunter (clears 1k AND profitable) |
| Tail | <1,000 | — | stays in existing Hunter/AUTO discovery campaigns |

Tier A+B spans 7 products and 76% of intent-attributed GP ($365k/$477k). Existing EXACT_BOOST
campaigns that already match a (product, intent) are absorbed into the registry, not duplicated.
Hunter/AUTO campaigns are NOT retired — they are the tail's discovery layer and the source of
graduation.

### Registry: `DE_SEARCH_TERM_INTENT`-style physical table `DE_INTENT_CAMPAIGN`

`campaign_id ↔ (product_short_name, intent_key, rung, state, created_at, …)`.
Campaign NAMES carry the intent slug for humans (`MINT-SP/EXACT (tween-girl-gift)`) but are
display-only. **All joins run on campaign_id** — 2026-07-24 we found `ME-AUTO` and
`ME-SP/AUTO (discovery,Mint)` are one renamed campaign; names are not keys.

### Earned rungs

| Rung | Earned when | Demoted when |
|---|---|---|
| Phrase | Broad finds ≥3 distinct converting phrasings | 90d net ROAS < floor at conclusive clicks |
| Broad Video | intent GP/mo ≥ threshold AND video asset in `DIM_PRODUCT_CREATIVES` | same |
| Broad Spotlight | ≥2 family products converge on the intent | same |

Demotion = **pause, not delete**. New Video/Spotlight rungs earned mid-month are created ≥4 days
before their first trigger date (SB moderation lead). Thresholds in `DE_COACH_THRESHOLDS`
(`strategy_id='INTENT'`).

## 2. Keywords (≤10 per campaign)

**Two sources, both feeding every cell:**
- **Proactive — the Research page.** `V_RESEARCH_RANKED` (rank, overall_fit, SQP demand) and
  `FACT_RESEARCH_RECOMMENDATIONS` (status NEW = recommended-but-not-advertised, the Coverage
  cockpit's "missing" rung). This is the only source that exists BEFORE ads run — it seeds
  launches and keeps proposing terms the account has never bought.
- **Reactive — the harvest.** Converting terms from the cell's own Broad/AUTO traffic
  (graduation candidates).

Selection score, in order:
1. **SQP presence + volume** (terms in `FACT_SEARCH_QUERY` with real volume beat ads-only
   tail; Exact promote respects `PROMOTE_MIN_SQP_VOLUME` = 500)
2. Term CVR posterior (shrunk toward the intent — term grain alone is noise, measured 0.5pp
   stddev at ≥1k clicks)
3. GP/click
4. Exact additionally gates on **research rank > 75** (standing rule)

Broad rungs: 3–5 seed phrasings. Exact: top-10 proven terms. **The ≤10 cap makes adds into
swaps**: a new keyword entering a full Exact campaign pairs with pausing the worst incumbent
(lowest GP/click posterior) in the same dated bulksheet.

**Negatives routing = the graduation mechanism:**
- Every Exact keyword → `negativeExact` in the same product's Broad rungs of that intent
  (broad keeps hunting new phrasings, never re-buys proven ones)
- Standard package on every campaign: `V_PRODUCT_PHRASE_NEGATIVES` (family + `_ALL`) + the
  proven-dead school-supplies-style negatives. Always `negativeExact` for term-level negatives
  — a phrase negative on "school supplies" would have blocked "school supplies gift sets"
  ($19.83 GP/click).
- **Self-competition guard**: a term may be live in only ONE product's Exact per intent — the
  facet router's best-ASIN pick owns it; others negate it.
- Holiday intents (`tween-girl-christmas-gift`) ARE the dedicated seasonal campaigns; no
  separate seasonal structure.

## 3. Bid engine (per cell per date)

```
cvr_hat(product, intent, month) = base_cvr(product,intent) × season_index(intent,month)
value_per_click = cvr_hat × gp_per_order            -- gp from FACT_AMAZON_ADS, same grain as CVR
target_bid      = value_per_click × INTENT_BID_PROFIT_SHARE (0.70)
max_cpc(band)   = value_per_click ÷ roas_floor(band)
```

The bid IS a target CPC (Amazon's bid field caps CPC). With UP_AND_DOWN, bid = willingness to
pay; checkpoints also watch actual CPC paid vs the band's max.

### Bands (replaces the hard OFF)

| Expected net ROAS at market | Band | Behavior |
|---|---|---|
| ≥ `PROFITABLE_ROAS` (1.1) | RUN | bid at target |
| `VELOCITY_ROAS` (0.7) – 1.1 | VELOCITY | runs **only while the product is below velocity pace**; max CPC = value ÷ 0.7 |
| `INTENT_HOPELESS_ROAS` (0.5) – 0.7 | MARGINAL | OFF unless the cell is in a PROBE window (launch traverses this zone) |
| < `INTENT_HOPELESS_ROAS` (0.5) | OFF | unconditional — velocity never justifies dead traffic |

Every band boundary comes from a `DE_COACH_THRESHOLDS` row (`PROFITABLE_ROAS`, `VELOCITY_ROAS`, `INTENT_HOPELESS_ROAS`; `strategy_id='INTENT'`) — none hard-coded.

- **Hysteresis**: pause below floor−0.1, resume above floor+0.1 **or after two consecutive
  checkpoints above the floor** — Jun Lollibox at 0.93–0.98 must not flap.
- Validated against actuals: White Lollibox × tween-girl-gift ran net ROAS <1.0 in Jun–Aug
  **two consecutive years** (0.98/0.78/0.79 in 2025; 0.93/0.80 in 2026) and 1.11–1.65 the rest
  of the year. The model's calendar is real; the bands decide what to do about it.

### Velocity floor (per product per month)

`units_floor = GREATEST(badge_tier_defense, plan_units × pace_pct)` — plan units from
`V_PLAN_FORECAST` adjusted monthly units (which already folds `DE_PLAN_STRATEGY` multipliers
and growth — the demand plan IS the velocity target); `badge_tier_defense` = the lower bound
of the badge tier the product held last calendar month (tiers 50/100/500/1K
bought-in-past-month), i.e. defend the badge you currently show. **Launch-population products
use the `V_LAUNCH_RAMP` donor curve as plan_units instead** (no badge to defend yet). Checkpoint compares month-to-date
units vs pro-rata floor. Below pace → open VELOCITY cells **in descending GP/click order**
(cheapest marginal sales first) until projected pace closes. On pace → marginal cells pause.
`VELOCITY_DEFEND` spend is tagged in the change log so `V_PPC_ACTION_OUTCOMES` can score
whether defended months hold organic share — the badge thesis becomes measurable.

### Budget allocation

Monthly plan allocates budget to **equalize marginal net profit per dollar across the grid**
(subject to floors), not to a uniform ROAS bar. Budget may shift between rungs of one intent
(winner funds itself). Integration with the Weekly Run waterfall is out of scope here.

### Inventory gate (overrides everything, including velocity)

No boost/velocity spend when `days_until_oos` < transit-safe runway for the trigger's horizon
(e.g., Mint OOS 2026-10-27 must veto a Christmas ramp). Reads `V_PLAN_FORECAST`.

## 4. The monthly decision: `T_INTENT_MONTH_PLAN` (+ `SP_GENERATE_INTENT_MONTH_PLAN`)

A physical table written by an SP, not a view — the plan is stateful (approval, checkpoint
appends, expiries). Generated M−3. **One row per campaign per TRIGGER DATE** (not per month):

- TIME_BASED intents: dates from `DIM_US_HOLIDAYS` windows — boost_start, peak_start,
  holiday−2, cooldown_end. (BTS bids move Aug 1 / Aug 10 / Sep 28, Christmas at ITS dates.)
- GENERIC intents: month-boundary row from the bid engine.
- Weekly checkpoint rows added reactively during the month.

The plan is not bids-only — **row types**:

| row_type | Content | Source |
|---|---|---|
| `BID` | target_bid, max_cpc, tos_pct, budget | bid engine (month/window) |
| `STATE` | pause / resume (band change) | bands + velocity pace |
| `ADD_KEYWORD` | keyword + match + bid, paired pause of worst incumbent when the cell is full | **Research page** (rank>75, SQP vol ≥500, not yet advertised) + harvest graduation |
| `NEGATE_TERM` | negativeExact | checkpoint (≥15clk/0ord) + rejected launch intents |

Row key: `(campaign_id, trigger_date, row_type, payload_key)` — `payload_key` is the
keyword/term for ADD_KEYWORD / PAUSE_KEYWORD / NEGATE_TERM rows and NULL for BID/STATE, so
multiple keyword rows per campaign per date cannot collide. Other fields: `payload, band,
reason_trace, expiry_date, row_status, pair_id`.

**Row lifecycle** (`row_status`): model rows are `DRAFT` → `APPROVED` in bulk by the monthly
approval. Checkpoint rows appended after approval enter as `PENDING_REVIEW` and are accepted
or rejected individually through the existing coach-action flow (Actions/Weekly Run) —
`/due` emits only `APPROVED` or `ACCEPTED` rows, never `PENDING_REVIEW`. Terminal states:
`APPLIED | REJECTED | EXPIRED`. An ADD_KEYWORD and its paired PAUSE_KEYWORD share a
`pair_id`; **rejecting either cancels both**.

Ori approves the month once in the cockpit; DoPage emits a dated bulksheet per trigger date
(keyword Create rows use the format already validated on the back-to-school upload; **rows
belonging to SB campaigns are written to the Sponsored Brands sheet** — the isSB routing rule).
Every applied change lands in `FACT_PPC_CHANGE_LOG` with a reason from the SINGLE canonical
enum, used identically by the generator, the checkpoint, and the applied endpoint:
`MODEL_MONTH | MODEL_WINDOW | CHECKPOINT_RAISE | CHECKPOINT_BRAKE | VELOCITY_DEFEND | PROBE |
RESEARCH_ADD | HARVEST_ADD | NEGATE`. `OOS_VETO` is a **generation-time plan reason only** —
a vetoed row is never applied, so it appears in `reason_trace`, never in the change log.
`HARVEST_ADD`'s producer: converting broad/auto terms that clear the harvest evidence gate
(≥15 clicks AND CVR ≥ the cell's posterior AND SQP volume ≥ `PROMOTE_MIN_SQP_VOLUME`) become
ADD_KEYWORD rows — monthly in the plan generator and mid-month from the checkpoint. Research
adds keep the rank>75 gate; harvest adds substitute their own click evidence for rank.

## 5. Two-layer coacher

**Layer 1 — model (predictive, dated):** knows the calendar; moves the December bid to $1.11
before any December data exists.

**Layer 2 — weekly checkpoint (reactive):** surfaces where coach actions surface today
(coach cards → Weekly Run/Actions → DoPage). Twice-weekly inside peak windows. Reads actuals
through **orders watermark −2d** (ads lag) and keys freshness on `__TABLES__.last_modified_time`
(restatement). Overrides between model dates:

| Observed | Action |
|---|---|
| actual CVR ≥ model, profitable | raise toward band max (never past) |
| collapse at conclusive clicks | GUARDIAN pull-down / dark-brake |
| term ≥15 clk / 0 ord | negate the term, not the bid |
| below velocity pace | open VELOCITY cells by GP/click |

**Precedence:** checkpoint overrides EXPIRE at the next model date — the model re-baselines,
and a persisting problem re-fires with a fresh logged reason. No stale overrides. The 3-day
re-suggest cooldown applies to all changes.

Known model gap (accepted): the curve pools full history unweighted, so it lags recent
improvement (White Lollibox actual 2026 CVR 3.2–4.2% vs cvr_hat 2.4–2.7%) and over-trusts
stale months (model said Aug RUN_THIN 1.24; actual Aug 2025 was 0.79). The checkpoint corrects
in-month; **recency weighting is a listed future refinement**, not in scope.

## 6. Launch products (insufficient data)

### New variation in an existing family

- Campaigns created day 0 (SP Broad + Exact), keywords = family's proven top-10 for the
  intent, **bid = family prior** (e.g., new Lollibox: 2.43% × gp × 0.70 ≈ $0.35). Flag PROBE.
- 20-day launch window: **no OFF, no loss-driven cuts** — <4 clicks → probe +5%; selling →
  raise; bleed via term negation only. Launch controller owns budget (≤$20/$30) until
  promotion; intent coacher takes over after.
- Posterior walks from family prior to own rate automatically (k=200: 200 own clicks = 50/50).

### Brand-new family (LolliBall case, validated on its real first 6 weeks)

A new family does NOT enter the grid on day 0 — three stages:

1. **Launch controller owns it** (day 0 → ~week 4): existing `NEW_LAUNCH` template (Exact
   launch + AUTO discovery + broad video/store) under launch doctrine. **Day-0 Exact keywords
   come from the Research page** — `V_RESEARCH_RANKED` top terms for the family by rank ×
   SQP volume (research exists pre-launch; the sensor does not). The AUTO/BROAD campaigns are
   the *intent sensors*: every term they buy gets facet-tagged.
2. **Admission** (~week 4–8): the grid admits a (product, intent) pair when launch evidence
   clears `>=100 clicks AND CVR >= intent-level prior`. Bid at admission uses the pair's own
   posterior (LolliBall tween-girl-gift: 345 clicks → 63% own data at k=200 → ~6.7% × gp ×
   0.70), gp_per_order from planned price − landed COGS (BOM) until ads GP stabilizes.
   Keywords = **research candidates ∩ sensor evidence** — research proposes, the sensor's
   converting terms confirm; both SQP-volume-preferred. Band = PROBE until the window closes.
   Launch cells appear in every monthly decision with their `ADD_KEYWORD` suggestions flagged
   PROBE, so new research terms keep flowing to launches through the same monthly review as
   everything else.
3. **Rejection is automatic**: intents that fail the bar never get campaigns and their terms
   route to negatives. LolliBall's real data: gift intents 5.7–7.0% CVR (admitted) vs
   `toys` 0.00% on 74 clicks and `teen-girl-gift` 0.67% (rejected) — the "gifts NOT toys"
   lesson discovered by the sensor, not remembered by a human.

Velocity floor for a new family = the launch ramp plan (`V_LAUNCH_RAMP` donor curve); there is
no badge to defend yet.

### Season quarantine (required, learned from the 11× artifact)

`season_index` pools across products, so a new family's launch ramp would inflate the launch
months' index for its intents **account-wide** — the same mechanism that produced the false
"LolliBall 11× back-to-school" signal in `V_FAMILY_OCCASION_MAP`. Rule: **products <90 days
from first sale are excluded from season_index pooling** (they still receive base_cvr and the
pooled index). Mirrors `V_PEAK_RELEVANCE`'s 90-day pre-peak maturity gate.

### Attribution note

LolliBall is invisible to the `ASIN_BY_CAMPAIGN_NAME` join today (its campaigns don't
resolve) — a second reason the registry keys on campaign_id: new-family campaigns register at
creation and attribution never depends on name parsing.

## 7. Surfaces

- **Intent Month panel** (new, cockpit/Plan area): approve the month, see per-cell dated rows.
- **Weekly Run / Actions / DoPage**: unchanged home of reactive suggestions + bulksheet apply.
- Trust ladder: this ships at VERIFY→APPLY (dated bulksheets, human uploads). AUTOMATE (Ads
  API) is explicitly out of scope.

## 8. Phasing

1. **Registry + Tier A build** — `DE_INTENT_CAMPAIGN`, 48 campaigns via bulksheet, absorb
   matching EXACT_BOOST, standard negatives on all.
2. **`T_INTENT_MONTH_PLAN` + Intent Month approval panel** (bands, velocity floor, inventory
   gate, hysteresis).
3. **Dated bulksheet emission + change-log reasons.**
4. **Weekly checkpoint integration** into the coacher flow; earned-rung automation; Tier B
   graduation from Hunter.
5. **Outcome scoring** — `V_PPC_ACTION_OUTCOMES` per reason code (does VELOCITY_DEFEND hold
   organic share? does MODEL_WINDOW beat CHECKPOINT timing?) → tune `DE_COACH_THRESHOLDS`.

## Out of scope

Ads API auto-apply; recency-weighted CVR curve; Weekly Run budget-waterfall integration;
placement/TOS conditioning of CVR (placement_type spread measured at 22% — Phase 2 refinement
via `V_KEYWORD_DAILY` TOS); forecast integration (BTS proved a targeting window, not a demand
event — do NOT feed intent seasonality into `V_FORECAST_DEMAND`).

## Dependencies (all live as of 2026-07-24)

`V_ADS_SEARCH_TERM_FACETS` (composed intents), `DE_SEARCH_TERM_INTENT` (supervised mapping),
`V_INTENT_CVR_CURVE` (product × intent × month), `V_INTENT_BID_BASE` (bands input),
`DE_COACH_THRESHOLDS` INTENT knobs, `DIM_US_HOLIDAYS` (BTS re-dated), `DIM_PRODUCT_CREATIVES`,
`V_PRODUCT_PHRASE_NEGATIVES`, `V_PLAN_FORECAST`, `FACT_PPC_CHANGE_LOG`.
Note: `V_INTENT_BID_BASE` currently hard-codes the 1.0 breakeven check — Phase 2 replaces it
with the three-band logic reading `PROFITABLE_ROAS`/`VELOCITY_ROAS`/HOPELESS from thresholds.
