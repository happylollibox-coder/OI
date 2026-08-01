# Ads Coach Decision Matrix

> **Source of truth**: `V_ADS_COACH.sql`
> **Data layer**: `V_ADS_COACH_DATA.sql`
> **Actions table**: `FACT_ADS_COACH_ACTIONS` (populated by `SP_REFRESH_ADS_COACH_ACTIONS`)

---

## Term-Level Actions (`action` column)

| Priority | Action | Strategy | Conditions | Guard |
|----------|--------|----------|------------|-------|
| 1 | `MONITOR` | EXACT_BOOST (target=term) | Term matches targeting keyword | — |
| 2 | `MONITOR` | EXACT_BOOST (target≠term, underperforming target) | Target ROAS < reduce threshold, 0 orders | STOP_TARGET fires at target level |
| 3 | `NEGATE_BOOST_SIMILAR_EXACT` | EXACT_BOOST | 0 orders + min clicks + active | — |
| 4 | `MONITOR` | EXACT_BOOST | ROAS < negate threshold + **lag ROAS > 1.3** | ⚡ Lag Safety |
| 5 | `NEGATE_BOOST_SIMILAR_EXACT` | EXACT_BOOST | ROAS < negate threshold + min clicks + active | — |
| 6 | `MONITOR` | EXACT_BOOST | ROAS < reduce threshold + **lag ROAS > 1.3** | ⚡ Lag Safety |
| 7 | `NEGATE_BOOST_SIMILAR_EXACT` | EXACT_BOOST | ROAS < reduce threshold + min clicks + active | — |
| 8 | `MONITOR` | BRAND/PRODUCT_DEFENSE | Always | Never negate (NEGATE_ROAS = -999) |
| 9 | `NEGATE_EXACT` | CONQUEST | 0 orders + min clicks + active | — |
| 10 | `MONITOR` | CONQUEST | ROAS < negate threshold + **lag ROAS > 1.3** | ⚡ Lag Safety |
| 11 | `NEGATE_EXACT` | CONQUEST | ROAS < negate threshold + min clicks + active | — |
| 12 | `MONITOR` | General | Holiday seasonal + off-season mode | Seasonal guard |
| 13 | `PROMOTE_TO_EXACT` | HUNTER/LCD | Orders ≥ promote threshold + ROAS ≥ 1.5 + SQP vol | — |
| 14 | `MONITOR` | General | ROAS < negate threshold + **lag ROAS > 1.3** + orders > 0 | ⚡ Lag Safety |
| 15 | `NEGATE_EXACT` | General | ROAS < negate threshold + min clicks + active | — |
| 16 | `MONITOR` | Fallback | Everything else | — |

---

## Target-Level Actions (`target_action` column)

| Priority | Action | Conditions | Guard |
|----------|--------|------------|-------|
| 1 | `CAMPAIGN_PAUSED` | Campaign state != ENABLED | — |
| 2 | `STOP_TARGET` | 0 orders + min clicks + active 5d | — |
| 3 | `SWITCH_HERO` | Non-hero ASIN + hero has better CVR + min orders | — |
| 4 | `KEEP_TARGET` (seasonal) | GUARDIAN + holiday_seasonal + profitable | Seasonal guard |
| 5 | `TARGET_PAUSED` | Keyword/target state != ENABLED | ⏸️ Paused guard |
| 6 | `INCREASE_BID` | ROAS ≥ scale_up threshold + orders ≥ 2 | — |
| 7 | `INCREASE_BID` | ROAS ≥ profitable threshold + orders ≥ 2 | — |
| 8 | `MONITOR_TARGET` | ROAS < reduce threshold + **lag ROAS > 1.3** | ⚡ Lag Safety |
| 9 | `REDUCE_BID` | ROAS < reduce threshold + orders > 0 | — |
| 10 | `KEEP_TARGET` | Orders > 0 (between thresholds) | — |
| 11 | `MONITOR_TARGET` | Fallback | — |

> **Grain: one bid decision per keyword.** A bid is set on the **keyword (target)**, not the search term, but `V_ADS_COACH_DATA` is one row **per search term** (a BROAD keyword matches dozens of queries). Every condition above therefore reads **keyword-grain** metrics (`target_*`), so `target_action` is identical across a keyword's search-term slices and the SP's `GROUP BY campaign, targeting, target_action` collapses to one TARGET row per keyword. See [§2026-06-23 Target Bid Grain](#2026-06-23-target-bid-grain-one-decision-per-keyword). Per-query divergence is handled by **term-level** `NEGATE_TERM` / `SWITCH_HERO` (search-term grain — correct there), never by emitting multiple bid rows.

---

## Budget Actions (`budget_action` column)

| Action | Conditions |
|--------|------------|
| `INCREASE_BUDGET` | Campaign profitable + high utilization |
| `DECREASE_BUDGET` | Campaign unprofitable + low utilization |
| `RESTORE_BUDGET` | Cooldown: restore to pre-peak budget |
| `KEEP_BUDGET` | Default |

---

## Cross-Sell Action (`ADD_CROSS_SELL_TARGET`)

Self-brand cross-sell: advertise product **B** on product **A**'s detail page,
chosen from proven in-brand co-purchase affinity. This is a *separate* engine
from the term/target/budget decisions above — it has its own view and grain.

| Aspect | Detail |
|--------|--------|
| Source | `V_ADS_COACH_CROSSSELL` (grain `target_asin` × `advertise_asin`) → materialized to `T_ADS_COACH_CROSSSELL` → `AdsCoachCrossSell` cube |
| Signal | `V_SRC_AmazonAds_purchased_product` — shoppers who engaged ads for A (`advertised_asin`) then bought B (`purchased_asin`), last 30d, our ASINs only, A ≠ B |
| Gate | `cross_orders_30d ≥ CROSS_SELL_MIN_ORDERS` (default **3**) **and** the pair is not already covered by a live product-target (gaps only, via `FACT_AMAZON_ADS.targeting` `asin=` coverage) |
| Confidence | HIGH ≥ 10 orders · MEDIUM ≥ 5 · LOW ≥ 3 (30d) |
| Surface | Actions page "🔁 Cross-sell" section, grouped by `target_parent`; `+ Queue` enqueues an `ADD_CROSS_SELL_TARGET` item (`product` = B, `targeting` = `asin="A"`, `match_type` = PRODUCT_TARGETING, **no fabricated bids**) |
| Export | Do-page bulksheet emits a Sponsored Products **product-targeting** campaign (Campaign → Ad Group → Product Targeting `asin="A"` → Product Ad for B). Budget, bid floor and product-page placement all come from the **`PRODUCT_DEFENSE`** row of `DIM_STRATEGY_CAMPAIGN_TEMPLATE` (no hardcoding); deduped against live campaigns. |

---

## Safety Guards

### ⚡ Lag Window Safety Check (NEW — 2026-04-13)

**Problem**: The 4-day data lag excludes the most recent 3 days from the weighted ROAS calculation. During this window, sales may already be occurring but are invisible to the decision engine, causing premature REDUCE_BID or NEGATE_EXACT actions.

**Solution**: Before executing any ROAS-based reduction/negation, peek at the lag window:

| Level | Metric | Source CTE | Column |
|-------|--------|------------|--------|
| **Term** | Net ROAS of last 3 days for this search_term | `ads_lag` | `ads_lag_net_roas` |
| **Target** | Net ROAS of last 3 days for this targeting keyword | `target_rollup_lag` | `target_lag_net_roas` |

**Rule**: If lag ROAS > **1.3**, the action is deferred to **MONITOR** (term) or **MONITOR_TARGET** (target). The rationale: those lag-window sales will naturally mature into the 8-week weighted ROAS within days, and a reduction now would be premature.

**Scope**: Only applies to ROAS-based actions. Zero-order negations (0 orders in 8 weeks) are NOT guarded — no amount of recent data justifies 8 weeks of zero conversions.

### ⏸️ Paused Target Guard (NEW — 2026-04-13)

**Problem**: Paused or archived targets (keyword-level) were still receiving INCREASE_BID / REDUCE_BID recommendations, which is misleading and not actionable.

**Solution**: Before evaluating bid thresholds, check `target_keyword_status` (derived from the latest `ad_keyword_status` in `FACT_AMAZON_ADS`). If the status is not `ENABLED`, emit `TARGET_PAUSED` and skip all bid logic.

| Field | Source | Value |
|-------|--------|-------|
| `target_keyword_status` | `V_ADS_COACH_DATA` → `FACT_AMAZON_ADS.ad_keyword_status` | `ENABLED` / `PAUSED` / `ARCHIVED` |

**Scope**: Applies only to target-level bid actions (`INCREASE_BID`, `REDUCE_BID`). Campaign-level `CAMPAIGN_PAUSED` (based on `campaign_state`) is checked separately and takes priority.

### 🧪 Lift-Probe Suppression (NEW — 2026-08-01)

**Problem**: The 80/20 portfolio engine (`V_KEYWORD_LIFT`, spec `OOB_BUDGET_PHASE.md` §Lever 2B) runs
stateless 20-click probe experiments on working-campaign keywords. The coacher, judging the same
keywords on 4w/8w windows, was emitting `REDUCE_BID` / `STOP_TARGET` on keywords **mid-probe**
(verified live 2026-08-01: a REDUCE on a 'mystery box for girls' probe and a STOP on a mid-test
auto clause) — killing a test before its 20-click verdict wastes the entire test spend.

**Solution**: in `V_ADS_COACH.scored` (same masking pattern as the 3-day cooldown), keywords the
lift engine currently owns — `V_KEYWORD_LIFT WHERE probing OR action = 'PROBE_START'` (both
channels) — get `target_action → 'KEEP_TARGET'` and bid-type `action → 'KEEP'`. A boolean
`is_lift_probe` column is exposed for the decision trace / UI.

**Scope**: bid actions only, and **unlike the cooldown, `STOP_TARGET` is also masked** (stopping a
probe mid-episode defeats the test). Term-grain negation (`NEGATE_TERM` / `STOP_TERM`) still passes
— per the no-loss-cuts doctrine, bleed is handled at the SEARCH-TERM level and does not fight the
probe. Suppression ends automatically when the episode reaches its verdict (probing=FALSE and no
PROBE_START row) — `WINNER_FOUND` keywords return to normal coacher governance.

---

## Decision Trace (JSON chips)

Each row includes a `term_decision_trace` and `target_decision_trace` column containing a JSON array of decision chips:

### Term trace chips
| Chip ID | Label | Rule |
|---------|-------|------|
| `clicks` | Clicks 8w | ≥ min_clicks threshold |
| `orders` | Orders 8w | > 0 |
| `roas` | OS WtROAS | ≥ negate threshold |
| `term_lag` | Lag ROAS (3d) | ≤ 1.3 → negate *(only when ROAS < negate threshold + orders > 0)* |

### Target trace chips
| Chip ID | Label | Rule |
|---------|-------|------|
| `tgt_clicks` | Target Clicks 8w | ≥ min_clicks threshold |
| `tgt_orders` | Target Orders 8w | ≥ 2 |
| `tgt_roas` | Target WtROAS | ≥ profitable threshold |
| `tgt_spend` | Target Spend 8w | context |
| `tgt_lag` | Lag ROAS (3d) | ≤ 1.3 → reduce *(only when ROAS < reduce threshold + orders > 0)* |
| `tgt_status` | Target Status | ENABLED *(only when target is paused/archived)* |

### Card display (non-decision)

Search-term DecisionCards also surface two **display-only** signals (no effect on the decision):
- **Fit `NN` badge** — `research_rank` (0–100) from `FACT_RESEARCH_RANKED.rank` (avg of `overall_fit` + `purchase_rank`), joined by family × term. Color: green ≥ 75 (promote-worthy), amber 40–74, faint < 40; hidden when the term has no research match.
- **`via {MATCH}: {term}` line** — `source_keyword`: the top-spend `targeting` the term matched through in the last 4w (+ its match type), suppressed when the term is its own exact targeting.

Both columns live on `V_ADS_COACH_DECISION` (LEFT JOINs, no fanout) → cube `AdsCoachDecision` → `CoachDecisionRow`.

---

## Thresholds (from `DE_COACH_THRESHOLDS`)

| Threshold | Key | Default | Used By |
|-----------|-----|---------|---------|
| Min Clicks | `min_clicks` | 15 | Insufficient data gate |
| Negate ROAS | `negate_roas` | 0.5 | NEGATE_EXACT / STOP_TERM |
| Negate Spend | `negate_spend` | $20 | Legacy (clicks preferred) |
| Reduce Bid ROAS | `reduce_bid_roas` | 0.9 | REDUCE_BID |
| Scale Up ROAS | `scale_up_roas` | 2.0 | INCREASE_BID (STRONG tier) |
| Profitable ROAS | `profitable_roas` | 1.1 | INCREASE_BID (the **bid-up floor** = `min(profitable, scale_up)`) |
| Promote Min Orders | `promote_min_orders` | 4 | PROMOTE_TO_EXACT |
| Promote Min ROAS | `promote_min_roas` | 1.5 | PROMOTE_TO_EXACT |
| Cross-Sell Min Orders | `CROSS_SELL_MIN_ORDERS` | 3 | ADD_CROSS_SELL_TARGET (`V_ADS_COACH_CROSSSELL`) |
| Halo ROAS | `halo_roas` | 0.5 | SQP halo credit |
| Bid Ceiling | `bid_cap_suggestion` | **$2.00** | Hard cap on every recommended bid |
| Defense Dominate IS% | `defense_dominate_is_pct` | **50** | BRAND_DEFENSE bid-up gate |

> **Reminder:** the bar called `profitable_roas` is **not "profitable"** for every strategy — it is the per-strategy **bid-up floor**, and several strategies set it below ad-breakeven on purpose (NEW_LAUNCH 0.5, SEASONAL_PUSH 0.7). The decision trace must explain the *intent* per strategy in plain language, never just "profitable threshold."

### Per-strategy `profitable_roas` (GUARDIAN), post-2026-06-16

| Strategy | Bar | Rationale |
|----------|-----|-----------|
| GLOBAL, HUNTER, EXACT_BOOST, LOW_COST_DISCOVERY, CATEGORY_CONQUEST, TOS_DOMINATION, RETARGETING | **1.1** | must be ad-profitable to scale (net ROAS is ads-only, breakeven = 1.0) |
| SEASONAL_PUSH | 0.7 | keep peak-proven terms warm for the next peak |
| NEW_LAUNCH | 0.5 | first days push for clicks to learn — buy rank at a controlled loss |
| BRAND_DEFENSE / PRODUCT_DEFENSE | 3.0 / 2.0 | vestigial for the ROAS bar — defense never scales on ROAS (see redesign §) |

---

## Mode-Aware ROAS Resolution

The ROAS metric used depends on the coach mode:

| Mode | Term ROAS | Target ROAS |
|------|-----------|-------------|
| **GUARDIAN** | `COALESCE(ads_weighted_net_roas_offseason, ads_weighted_net_roas, ads_net_roas_8w)` | `COALESCE(target_weighted_net_roas_offseason, target_weighted_net_roas, target_net_roas_8w)` |
| **COOLDOWN** | Same as GUARDIAN | Same as GUARDIAN |
| **BLITZ** | `COALESCE(ads_weighted_net_roas_hotseason, ads_weighted_net_roas, ads_net_roas_8w)` | `COALESCE(target_weighted_net_roas_hotseason, target_weighted_net_roas, target_net_roas_8w)` |
| **Default** | `COALESCE(ads_weighted_net_roas, ads_net_roas_8w)` | `COALESCE(target_weighted_net_roas, target_net_roas_8w)` |

**BLITZ PEAK phase** overrides the target ROAS for fast peak reaction with **keyword-grain** `GREATEST(target_lag_net_roas, target_net_roas_1w)` (was per-search-term `ads_net_roas_3d` until 2026-06-23). The freshest 3d (`target_lag`, today-3..today-1) sits inside the attribution lag and understates ROAS, so the lag-complete 1w floors it — a genuinely-hot 3d still scales up, but a lag artifact can't REDUCE a profitable keyword mid-peak. See [§Target Bid Grain](#2026-06-23-target-bid-grain-one-decision-per-keyword).

---

## 2026-06-16 GUARDIAN Redesign

Net ROAS used for all bid decisions is **ads-only** (`margin_per_unit × ad-attributed units ÷ ad spend`); breakeven = 1.0; no organic/SQP halo. Changes:

1. **Bid-up floor = 1.1** across non-discovery strategies (see per-strategy table). The floor is `min(profitable_roas, scale_up_roas)`, so HUNTER also got `scale_up_roas` 1.0→2.0. Stops bidding *up* terms that aren't ad-profitable.
2. **`NEEDS_STRATEGY`** (new target_action): a target on a campaign with no mapped strategy gets no bid action — it is flagged for the user to assign a strategy (name-based suggestion reused from the Campaign Mapping panel). No more silent GLOBAL-bar fallback on unmapped campaigns.
3. **Frequency-gate bypass**: the GUARDIAN 7-day bid-change cadence may be bypassed at **≥3 days** if the **3-day net ROAS ≥ 2.0** (`ads_net_roas_3d`) — strong winners aren't held a full week.
4. **`DEFENDED`** (new `ads_signal`): BRAND/PRODUCT_DEFENSE terms report `DEFENDED` instead of the misleading `WASTED_SPEND`.
5. **Defense bid-raise** (replaces pure `MONITOR_TARGET` for defense — purpose: control the auction and make terms expensive for competitors):
   - **BRAND_DEFENSE** (brand search terms): `INCREASE_BID` toward the $2 ceiling when SQP `impression_share_pct < defense_dominate_is_pct` (50%); else MONITOR (already dominating). Share comes from `FACT_SEARCH_QUERY`.
   - **PRODUCT_DEFENSE** (ASIN targeting on own detail pages): `INCREASE_BID` toward the $2 ceiling **unconditionally** when `current_bid < ceiling` — no SQP signal exists for detail-page slots; intent is to occupy own listings.
6. **Bid ceiling**: every recommended bid is capped at `bid_cap_suggestion` ($2.00, GLOBAL default). When the cap binds, the trace carries a "bid set by BID Ceiling" chip.
7. **Dead config dropped**: `PROMOTE_ROAS_THRESHOLD` (never read — pivot uses `PROMOTE_MIN_ROAS`) and `REDUCE_BID_SPEND` (no logic) removed from `DE_COACH_THRESHOLDS`.
8. **Per-strategy reasoning**: decision-trace explains each strategy's intent in plain language (the `profitable` bar is not self-explanatory).

**Follow-ups:** ~~display research_rank + source keyword on cards~~ (shipped 2026-06-16, display-only — see §Card display); ~~PRODUCT_DEFENSE self-brand cross-sell~~ (shipped 2026-06-16 — see §Cross-Sell Action).

---

## 2026-06-23 Target Bid Grain (one decision per keyword)

**Problem:** one keyword produced multiple contradictory TARGET rows (e.g. `INCREASE_BID` **and** `REDUCE_BID` on the same keyword) → confusing cards + "Duplicate Id" rejection if two bid Updates for one Keyword Id reach a bulksheet. Cause: `V_ADS_COACH_DATA` is **per search term**; the SP already groups TARGET rows by `(campaign, targeting, target_action)`, so the only way to get >1 row per keyword was `target_action` *varying across the keyword's search-term slices*. Three slice-grain fields leaked into the otherwise keyword-grain decision:

| # | Branch | Leaked field (per term) | Fixed to (per keyword) |
|---|--------|-------------------------|------------------------|
| 1 | Money-bleeder `REDUCE_BID` (`target_action` + matching `recommended_bid`) | `ads_orders_4w` / `ads_spend_4w` / `ads_clicks_4w` | `target_orders_4w` / `target_spend_4w` / `target_clicks_4w` |
| 2 | BLITZ **PEAK** `target_roas` | `ads_net_roas_3d` | `GREATEST(target_lag_net_roas, target_net_roas_1w)` — keyword-grain, lag-robust (3d understates inside the attribution lag) |
| 3 | `SWITCH_HERO` trigger | `is_hero_match` | `target_is_hero_match` |

**New fields in `V_ADS_COACH_DATA`:** exposed `target_spend_4w` (= `clause_spend_4w`); added `target_hero_match` CTE → `target_is_hero_match` (TRUE when ≥50% clicks-weighted of a keyword's search-term slices advertise the family hero). Once `target_action` is keyword-invariant, the existing SP `GROUP BY` collapses to one TARGET row per keyword with correctly summed 4w stats.

**Auto-clause guard (SP):** an SP-Auto auto-targeting clause (`loose-match` etc.) serves multiple ASINs but bids **once**, and ROAS metrics are per-ASIN — so one clause can still split into INCREASE(asin A)+REDUCE(asin B). `SP_REFRESH_ADS_COACH_ACTIONS` Step 4 adds a `QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign, targeting, [bid-actions-as-one] ORDER BY priority DESC) = 1` so all bid-exporting actions collapse to the single highest-priority one (≤1 bid Update per keyword); non-bid actions (SWITCH_HERO) keep their own partition and still surface.

**Left at search-term grain (correct):** term-level `NEGATE_TERM` money-bleeder + fit-protection (`action` column), and `SWITCH_HERO` export — DoPage emits it as `Add NEGATIVE_EXACT` + "switch ASIN", a different bulksheet op than a keyword bid Update, so it is **not** a Duplicate-Id even when co-located with a bid action.

**Verified:** `kw_increase_AND_reduce` 5→0; keywords exporting 2 bid Updates 19→0; `gifts for girls` 4 bid actions → 1 (`INCREASE_BID`, BLITZ-correct). Deployed + `SP_REFRESH_ADS_COACH_ACTIONS` run.

---

## Maintenance Log

| Date | Change |
|------|--------|
| 2026-06-23 | **Peak-relevance override**: new `DE_PEAK_OVERRIDES(family, holiday_name, force_relevant)` table UNIONed into `V_ADS_COACH.family_holiday_relevance` — lets a family be forced into BLITZ for a holiday `V_PEAK_RELEVANCE` can't measure (launched into the only completed occurrence → 90d maturity gate drops it). Seeded `LolliME / Prime Day` for Prime 2026 (first sale 2025-06-07; auto-qualifies from Prime 2027, so remove the row after). Judgment override — BLITZ then runs on default aggression with no measured peak anchor. |
| 2026-06-23 | **Target bid grain fix**: TARGET bid decisions now read keyword-grain metrics (`target_orders_4w`/`target_spend_4w`/`target_clicks_4w`, `target_lag_net_roas` for BLITZ PEAK, new `target_is_hero_match`) so one keyword no longer fans into contradictory INCREASE/REDUCE bid rows. See §2026-06-23. |
| 2026-06-16 | DecisionCards now show research **Fit** rank (`FACT_RESEARCH_RANKED.rank`, 0–100; green ≥75 / amber 40–74 / faint <40) + top-spend 4w **source keyword/target** (+ match type). Display-only — added `research_rank`/`source_keyword`/`source_keyword_match_type` to `V_ADS_COACH_DECISION` via LEFT JOINs (row-count parity verified, no decision change). See §Card display. |
| 2026-06-16 | Added self-brand cross-sell: `V_ADS_COACH_CROSSSELL` (target×advertise co-purchase pairs, gaps only), `CROSS_SELL_MIN_ORDERS` threshold (3), `ADD_CROSS_SELL_TARGET` action + Actions card, Do-page bulksheet export into a `PRODUCT_DEFENSE` SP product-targeting campaign. See §Cross-Sell Action. |
| 2026-06-16 | GUARDIAN redesign: per-strategy 1.1 bid-up floor, NEEDS_STRATEGY, 3d freq-gate bypass, DEFENDED signal, defense bid-raise (SQP IS gate / unconditional), $2 bid ceiling, dropped dead keys, per-strategy trace. See §2026-06-16. |
| 2026-04-13 | Added lag window safety check (3-day look-ahead) for REDUCE_BID and ROAS-based NEGATE_EXACT. |
| 2026-04-13 | Fixed deploy script: V_ADS_COACH was read but never deployed to BigQuery. |
| 2026-04-13 | Added paused target guard: INCREASE_BID/REDUCE_BID only fire for ENABLED keywords. Paused/archived → TARGET_PAUSED. |
