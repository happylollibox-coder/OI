# Business-Unit Coacher — Design Spec

**Date:** 2026-06-09
**Status:** 🟢 Approved (design) — pending spec review → implementation plan
**Owner:** Ori
**Context:** Reshapes the Ads Coacher so each product **family is treated as an independent business unit**. Builds on the just-landed per-family-mode refactor (`coachActuals.ts`, `famModes`, injectable `adRoasSignal`).

---

## 1. Goal

Make the coacher judge every search term **independently per family**, so the same customer search term can be **profitable for one family and wasteful for another at the same time** — and the coacher reacts correctly for each, instead of crowning a single global winner and treating every other family as a loser.

## 2. Trust strategy (why this scope)

The owner does **not yet trust** the coacher's recommendations. Trust is earned by the coacher being **demonstrably correct before it is aggressive**. Therefore the first version:

- Keeps **all** action types (negate, reduce-bid, promote, remove-asin, etc.).
- Gates every action behind a **confidence/clarity threshold** so only *unambiguous* cases surface. The action list gets **short because each item is obviously right**.
- Parks marginal cases in a visible **"needs judgment" review bucket**, not acted on.
- Puts the gate's knobs in **`CoachThresholds`** (already per-mode/per-season) so "upgrade later" = **loosen the gate**, no redeploy.

**Deferred to later phases (explicitly out of scope now):**
- Cross-family **opportunity surfacing** (actively suggesting a *new* family bid on a proven term).
- Aggressive automation: auto-`STOP` of whole keywords, bulk restructure.
- Ad-group-scoped negatives.

## 3. The model

| Concept | Rule |
|---|---|
| **Business unit** | **Family** (`parent_name`). Owns the P&L verdict on a term. |
| **Judgment** | Per **(family × term)**, using **only that family's attributed metrics**. Never a cross-family aggregate. |
| **Actions** | Land on the Amazon object: **bids → keyword/target**; **negate → search term as a campaign-scoped negative keyword**. (Owner: "actions are per keyword; a term matters when it needs negating.") |
| **Campaign** | The lever for **population & placement**, decided within the family. |
| **Verdict** | `family_net_roas = Σ(attributed sales − cogs) / Σ(attributed spend)` on the term → judged vs **that family's own coach-mode bar** (same bar the dashboard uses) → **CUT / HOLD / SCALE**. |

A single term-row set can read: *Lollibox → SCALE (1.4×), Fresh → CUT (0.6×)* — each true, each independent.

## 4. The two blur sources being fixed

Confirmed in `scripts/bigquery/views/V_ADS_COACH_DATA.sql`:

1. **Global hero per term** (`term_hero` CTE): `ROW_NUMBER() OVER (PARTITION BY search_term ORDER BY hero_score DESC) ... WHERE global_rank = 1`. Crowns one winner per term **across all families**; `is_hero_match` then judges every other family as "not the hero." → **Replaced** with a per-family hero.
2. **Cross-family verdict**: decisions partly read keyword performance pooled across campaigns rather than per the owning family. → **Replaced** with per-family attributed metrics.

## 5. Engine changes (Approach A — server-side, BigQuery)

All decisions live in SQL so **every** consumer (dashboard, `oi-coach` MCP, DoQueue) is correct, not just one screen.

### 5a. Per-family hero — fully replaces global hero
In `V_ADS_COACH_DATA.term_hero`: change `PARTITION BY search_term` → `PARTITION BY search_term, parent_name`. Each family gets its own best ASIN for a term; `is_hero_match` becomes "best product **within its own family**." The global hero is removed (not kept as a side signal).

### 5b. Campaign territory classifier — new view `V_ADS_COACH_CAMPAIGN_TERRITORY`
From the campaign × asin grain, derive each campaign's distinct served families (`parent_name`) → tag:
- **`DEDICATED`** — all the campaign's ASINs map to **one** family.
- **`SHARED`** — ASINs span **≥2** families (e.g. a brand-defense campaign).

Also expose the served-family list and served-ASIN list per campaign. Registered in `config.yaml`.

### 5c. Per-family attribution & verdict — in `V_ADS_COACH_DATA` / `V_ADS_COACH_DECISION`
Metrics are already at **campaign × asin × search_term** grain, so the family's slice of a SHARED campaign comes out **natively at the ASIN level — no proration, no double-count** (the trap the Phase-2B brief flagged). For each (family × term): aggregate spend/sales/orders/cogs across that family's ASINs and campaigns → `family_net_roas` → verdict vs the family's mode bar. **ASIN-level metrics are retained** alongside the family rollup (the shared-conflict action must name a specific ASIN).

### 5d. Confidence gate — the trust mechanism
An action surfaces as **actionable** only when **all three** hold (knobs from `CoachThresholds`, per-mode/per-season):
1. **Enough data** — `spend ≥ min_spend` AND `clicks/orders ≥ min_signal` AND `days ≥ min_days`. Never acts on thin noise.
2. **Decisively past the bar** — the family verdict sits **outside a gray band** around the threshold (e.g. not 0.90–1.10×); clearly CUT or clearly SCALE.
3. **No conflicting signal** — don't negate a term a sibling family is clearly winning on in the same SHARED campaign (that triggers `REMOVE_ASIN_FROM_CAMPAIGN` instead, and only on a stark split).

Cases that fail the gate are **parked** (not emitted as actions) with a reason, surfaced in the review bucket.

### 5e. Action mapping (each row is per campaign × asin × search_term)

**DEDICATED campaign (one family):**
- Verdict **CUT** (gated) → `NEGATE_TERM`, scoped to that campaign (negative-exact); bid keyword → `REDUCE_BID`.
- Verdict **SCALE** (gated) → `PROMOTE_TO_EXACT` / `SCALE_UP` on the keyword. **HOLD** → `KEEP`.

**SHARED campaign (cross-family):**
- Term **CUT for *all* served families** (gated) → `NEGATE_TERM` at campaign level (safe — no collateral).
- Term **SCALE/HOLD for ≥1 family but CUT for another**, both sides clear (stark split) → **new action `REMOVE_ASIN_FROM_CAMPAIGN`** naming the wasteful ASIN ("remove/replace this product from this campaign"). **Not** a negate.
- Term good for all → keep/promote per family.

`STOP` (auto-pause a whole keyword) and aggressive promote stay **gated to only the most egregious cases** in this phase, effectively rare; broader automation is a later upgrade. (The one routine `STOP` is the launch 15-click zero-order case — see 5f.)

### 5f. New-keyword launch ramp (per keyword/target)
A keyword is in **LAUNCH** state until it reaches **15 clicks** (lifetime). Two things the ramp owns; then it hands off to the normal coach.

1. **Launch bid = `cpc_target × 1.35`.** The 35% premium buys clicks fast to gather data. `cpc_target` is the family's plan CPC for the relevant channel (branded/non-branded — via the Phase-2B brand classifier, `DIM_BRAND_PHRASES`). The `1.35` premium is a tunable `launch_cpc_premium` in `CoachThresholds`.
2. **15-click decision gate:**
   - **0 orders → `STOP`** (pause). The cleanest possible stop — 15 clicks with no conversion, and no halo at risk (see [[fact-oi-net-roas-no-halo]]). This is the one routine auto-`STOP`.
   - **≥ 1 order → graduate** out of LAUNCH. From there the **normal per-family net-ROAS coach manages the bid** — **net ROAS is king**: it scales (`PROMOTE_TO_EXACT` / `SCALE_UP`) when net ROAS clears the scale gate (GUARDIAN ~1.30× / BLITZ ~1.15×) and reduces (`REDUCE_BID`) when below the family's good bar. **No bespoke launch bid-down loop** — it's the same engine and the same gates as every other keyword.

Output: a `lifecycle` tag (`LAUNCH` | `ACTIVE`) on the keyword's rows + the launch-bid recommendation while in LAUNCH; the 15-click `STOP` reuses the existing `STOP` action.

### 5g. NEW launch-candidate sourcing — from `V_RESEARCH_RANKED`, per family
Where new keywords *come from*. `V_RESEARCH_RANKED` is already at grain **`parent_name × query_text`** (one row per family per search term — exactly the business-unit grain) and scores every family×term with `seg_fit`, `overall_fit`, `purchase_rank`, and a final **`rank` (0–100)**; it also carries `ads_family_orders`. Already in `config.yaml`.

- **Candidate** = a (family × term) row where the family is **not already advertising** the term (exclude terms in the family's active keyword/target set — not merely "no orders") **AND `rank ≥ launch_rank_min`**.
- **Selectivity (trust-first):** take the **top `launch_batch_per_family` terms by `rank` per family per cycle** — *few, high-fit* launches you can watch.
- Each selected candidate → a **`NEW` action** that starts the launch ramp (5f): bid `cpc_target × 1.35` → 15-click gate.
- The **`rank` / `overall_fit` score IS the confidence gate for NEW** (high fit = clear case) — consistent with §5d.
- Knobs in `CoachThresholds`: **`launch_rank_min` (default ~70)**, **`launch_batch_per_family` (default ~3–5)**. "Upgrade later" = lower the bar / raise the cap to discover more.

(Note: `V_ADS_COACH_DATA` already emits SQP-only `OPPORTUNITY` rows — NULL campaign × asin × search_term. The plan reconciles whether `NEW` reuses/ranks those via `V_RESEARCH_RANKED` or is a parallel source; either way the per-family rank from `V_RESEARCH_RANKED` is the selector.)

## 6. Output & consumers

- **`FACT_ADS_COACH_ACTIONS`** (already carries `parent_name`, `asin`, `campaign_id`, `hero_asin`, `is_hero_match`) gains columns:
  - `campaign_territory` (`DEDICATED` | `SHARED`)
  - `family_net_roas` (the business-unit verdict metric)
  - `family_verdict` (`CUT` | `HOLD` | `SCALE`)
  - `confidence_clear` (BOOL — passed the gate) + `gate_reason` (why parked, when not)
- **Action enum** gains `REMOVE_ASIN_FROM_CAMPAIGN`; `utils.ts` gets its label / criteria / priority-group.
- **`SP_REFRESH_ADS_COACH_ACTIONS`** updated to materialize the new columns/logic.
- **Dashboard Actions page** already groups by family — clear cases show per family; **parked cases go to a collapsed "Needs judgment" review bucket** (default-collapsed; flip-to-hidden later).
- **`oi-coach` MCP** and **DoQueue** consume the corrected rows unchanged.

## 7. Confidence-gate defaults (starting point — tune in `CoachThresholds`)

**Important — the ROAS is `family_net_roas` = direct ad-attributed (sales − COGS) / ad spend, with NO organic/repeat halo.** Two consequences baked into the gate below:
- The metric **understates** true value (it can't see rank lift / repeat customers). So promote bars are kept conservative-but-not-inflated — demanding too much would suppress genuine winners.
- Negating on direct ROAS alone can kill a term that was actually driving halo. So the **cleanest negate is a zero-conversion term** (real spend, **0 orders**) — no direct value *and* no halo to lose. Terms that *have* orders but low ROAS are treated more conservatively (higher cut bar, or parked).

**Data-sufficiency knobs (don't act on noise):**

| Knob | Starting default | Rationale |
|---|---|---|
| `min_spend` (negate) | $5 over the window | Don't negate on pennies. |
| `min_signal` | ≥ 10 clicks **or** the term's own orders ≥ a floor | Enough to read intent. |
| `min_days` | term active ≥ 7 days | Avoid one-day spikes. |

**Clarity knobs (don't act on a coin-flip):**

| Knob | Starting default | Rationale |
|---|---|---|
| `gray_band` (ROAS) | 0.90–1.10× → HOLD / park | Only act outside the band. |
| `negate_clearest` | **0 orders** + `min_spend`/`min_signal`/`min_days` met | The highest-trust negate — no halo at risk. Terms with orders but ROAS < `gray_band` low edge are negated more cautiously or parked. |
| `scale_clear` — **GUARDIAN** | net ROAS ≥ **~1.30×** | Margin above the 1.1× display bar — headroom for the marginal-ROAS decline as spend rises. |
| `scale_clear` — **BLITZ** | net ROAS ≥ **~1.15×** | Grows more eagerly than GUARDIAN, but still clearly positive to auto-act. |
| `scale_clear` — **COOLDOWN** | **N/A — never promotes** (`scale: false`) | Wind-down mode only holds (≥ 0.8×) or cuts; the promote gate does not apply. |
| `remove_asin_split` | winner ≥ 1.3× **and** loser ≤ 0.7×, both gated | Stark split only. |

Note the split between the **display reaction bar** (`MODE_ROAS.up` = GUARDIAN 1.1 / BLITZ 1.0 — drives the dashboard "↑ scale budget" hint) and the **auto-promote gate** (the stricter ~1.30 / ~1.15 above). Display = "lean toward scaling"; gate = "confident enough to spend more."

(Values illustrative; finalized in the plan, owner-tunable thereafter.)

## 7b. Trust roadmap — staged rollout, each stage verified with real Amazon results

The owner's requirement (2026-06-11): *make the coacher explainable in a simple, clear way; end state = the action list is generated automatically for bulk upload on the DO page; build trust in stages, each verified with real data and real results from Amazon a few days later.*

UI review findings that shape this:
- Good raw material exists: per-action plain-English `reason` with real numbers (`V_ADS_COACH_DECISION.sql` ~505), a `confidence` field (HIGH/MEDIUM/LOW), and a working Amazon Bulksheet v2.0 exporter (`DoPage.tsx`).
- Blockers: 200+ surfaced actions (volume kills trust); explanations buried in expanded rows; **no outcome-verification loop at all** (uploaded actions go to localStorage and are forgotten — the system never shows whether its calls were right); localStorage-only action state can't power verification.
- Dormant asset: `DE_APPROVED_ACTIONS` table (DDL exists, status flow PENDING→EXPORTED→APPLIED, nothing writes to it) — becomes the action log.

**Stage 1 — short, explainable list (decision cards).**
Per-family hero (✅ deployed 2026-06-11) + a client-side **clear-case selector** over engine-provided fields (confidence, spend, clicks, orders, net ROAS — the §7 knob defaults) + each surfaced action rendered as a **decision card**: the claim ("Stop X for Fresh") → the evidence (3 numbers, from `reason`) → real past impact in dollars (facts, not forecasts) → exactly what changes in Amazon (campaign, negative type). Everything else collapses into the "needs judgment" bucket. *No wizard* — trust comes from repeated small verifications, not a one-time walkthrough. (The selector migrates into `V_ADS_COACH_DECISION` at Stage 3, per Approach A; client-side first so the knobs can be iterated daily.)
**Success test:** Ori reads the short list daily and agrees with ~all of it.

**Stage 2 — the receipt loop (action log + scoreboard).**
Wire `DE_APPROVED_ACTIONS`: on "Uploaded to Amazon" the DO page POSTs each item with a **metric snapshot at action time** (spend/orders/ROAS/bid). New view `V_COACH_ACTION_OUTCOMES` compares post-action actuals from `FACT_AMAZON_ADS` at **+3/+7/+14 days** (excluding the ~2-day ads lag): NEGATE/STOP verified when spend stops; REDUCE_BID when CPC/ROAS improves; PROMOTE when ROAS holds with more volume; TOO_EARLY before enough post-lag days. A **Track Record panel** renders the scoreboard: *"N calls in the last 2 weeks — K verified correct, $X saved, M wrong (with reasons)."*
**Success test:** after ~2 weeks the scoreboard shows a hit rate Ori believes, computed from real Amazon data.

**Stage 3 — widen the gate.** Once hit-rate holds (≥85–90%), loosen `CoachThresholds` knobs to admit more cases; move the clear-case selector into the engine (`V_ADS_COACH_DECISION`); auto-build the DO queue (human still clicks upload). Includes roadmap plans 2–6 (territory, attribution, engine gate, launch ramp, action mapping).

**Stage 4 — end state.** Bulk list generated automatically on the DO page; Ori reviews-and-uploads; the scoreboard grades the coacher continuously.

## 8. Testing strategy

- **Per-family hero:** SQL spot-check — a known term that converts best on Family A but is run by Family B now yields a Family-B hero row (B's own best ASIN), not A's.
- **Territory classifier:** assert a known brand campaign tags `SHARED`; a colour-line campaign tags `DEDICATED`.
- **Attribution no-double-count:** Σ family-attributed spend on a SHARED campaign term = the campaign's actual term spend (reconciliation query).
- **Verdict independence:** a seeded conflicting term shows `CUT` for one family and `SCALE` for another in the same output.
- **Gate:** a thin-data term and a gray-band term are both `confidence_clear = FALSE` with a `gate_reason`; a stark case is `TRUE`.
- All new BQ objects: `bq query --dry_run` validates before any deploy.

## 9. Constraints (carry over)

- Branch `feat/offseason-forecast`; commits local, **not pushed**.
- New views/columns **registered in `config.yaml`**; build additively.
- **Production SQL deploy needs explicit owner OK.** No destructive SQL without confirmation.
- Reuse the existing per-family mode bar / `CoachThresholds`; engine and dashboard must agree.

## 10. Decisions locked this session

1. Intent = **independent per-family judgment** (not cross-family opportunity surfacing — deferred).
2. Decision grain = **family × term**; actions on keyword (bid) / search-term-as-negative (negate); campaign owns population/placement.
3. Brand campaigns can be single-family **or** cross-family → engine must **detect** (territory classifier).
4. Shared cross-family conflict → **`REMOVE_ASIN_FROM_CAMPAIGN`** (remove/replace the wasteful product), not a negate.
5. Per-family hero **fully replaces** global hero.
6. Verdict bar = **same per-family coach mode** as the dashboard.
7. Trust via a **confidence gate** — all action types kept, only clear cases surface; gate tunable in `CoachThresholds`; "upgrade later" = loosen it.
8. Marginal cases → **collapsed "needs judgment" review bucket** (not hidden).
9. `family_net_roas` is **direct ad-attributed, no organic/repeat halo**. ⇒ promote bars kept conservative-not-inflated; the **cleanest negate is a zero-conversion term** (0 orders), and orders-but-low-ROAS terms are cut cautiously / parked.
10. **Display reaction bar ≠ auto-promote gate.** Reaction bar stays `MODE_ROAS.up` (GUARDIAN 1.1 / BLITZ 1.0) for the dashboard hint; the auto-promote gate is stricter — **GUARDIAN ~1.30×, BLITZ ~1.15×, COOLDOWN never promotes**.
11. **New-keyword launch ramp** (per keyword/target): launch bid = `cpc_target × 1.35`; at **15 clicks** → **0 orders = `STOP`**, **≥1 order = graduate** to the normal net-ROAS coach. **No separate bid-down loop** — net ROAS governs (scale ≥ gate, reduce below good). `1.35` premium tunable as `launch_cpc_premium` in `CoachThresholds`.
12. **NEW candidates sourced from `V_RESEARCH_RANKED`** (grain `parent_name × query_text`): per cycle, top **`launch_batch_per_family` (~3–5)** unadvertised terms with **`rank ≥ launch_rank_min` (~70)** per family → `NEW` action → launch ramp. Trust-first (few, high-fit); both knobs tunable in `CoachThresholds`.
