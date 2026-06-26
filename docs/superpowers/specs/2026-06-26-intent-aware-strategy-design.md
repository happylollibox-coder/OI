# Intent-Aware Strategy (Coacher sub-project B.2)

- **Date:** 2026-06-26
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Builds on:** [[project_coacher_product_strategy_profile]] (sub-project B) and the CPC/match-type analysis [[project_cpc_strategy_net_profit_analysis]].
- **Motivating finding:** within a single match type, performance splits hard by *keyword intent*. LolliME exact: journal/product-intent terms net **+$4,641**, generic-gift terms breakeven. Fresh/Lollibox exact: the profitable part is **brand defense** (+8.99 / +4.84 net/$), while **generic-gift exact bleeds** (−$666 / −$3,766). The current per-match-type suppression is too blunt — it over-suppresses profitable product/brand terms and under-distinguishes the generic losers.

---

## 1. Goal

Make the strategy and its suppression **intent-aware**: classify every keyword as BRAND / PRODUCT / GENERIC and decide per intent, instead of per match type. Defend brand, protect & grow non-brand product-intent terms, suppress only the generic losers.

## 2. Decisions locked (from brainstorming)

| Axis | Decision |
|---|---|
| **Grain** | Intent is a real dimension: `DE_PRODUCT_STRATEGY_PROFILE` grain becomes **parent × season × match_type × intent_class**. |
| **Intent classes** | **BRAND** / **PRODUCT** / **GENERIC**. |
| **Brand source** | Reuse `V_BRAND_KEYWORD_CLASSIFICATION.is_brand_keyword` + `DIM_BRAND_PHRASES` (existing). |
| **Product vs generic** | Non-brand AND (research fit ≥ threshold OR is an anchor) → PRODUCT; else GENERIC. Fit from `V_RESEARCH_RANKED`/`FACT_RESEARCH_RANKED`. |
| **Classification** | **Derived + manually overridable** (fit mis-segments some families — Ori can fix a term's class). |
| **Steering rule** | BRAND → never suppress; PRODUCT → protect (keep bid-ups); GENERIC → suppress when its own intent cell is a CONCLUSIVE loser. |

## 3. Intent classification — `V_KEYWORD_INTENT_CLASS` (new view)

One canonical place to classify a keyword/term, reused by derivation and steering. Grain: `parent_name × keyword_text` (and `keyword_id` where present).

Resolution order:
1. **BRAND** — `is_brand_keyword = TRUE` (join `V_BRAND_KEYWORD_CLASSIFICATION` by term; fallback: term matches a `DIM_BRAND_PHRASES.phrase_type='BRAND'` phrase).
2. **PRODUCT** — not brand AND (`research_rank ≥ INTENT_FIT_MIN` from `FACT_RESEARCH_RANKED` joined by family×term, OR the term is an anchor in `DE_PRODUCT_MAIN_KEYWORDS`).
3. **GENERIC** — everything else (incl. non-brand terms with no research-fit match).
4. **MANUAL override** — a row in `DE_KEYWORD_INTENT_OVERRIDE (parent_name, keyword_text, intent_class, updated_by, updated_at)` wins over the derived class (COALESCE pattern).

`INTENT_FIT_MIN` default **50** (tunable in `DE_COACH_THRESHOLDS`); anchors are PRODUCT regardless of fit (they're the proven product winners).

## 4. Table changes

### `DE_PRODUCT_STRATEGY_PROFILE`
- Add `intent_class STRING NOT NULL` to the grain. New key: `(parent_name, season, match_type, intent_class)`.
- Re-derive: the ~50 rows become up to ~150 (4 parents × 2 seasons × 5 match types × 3 intents; empties skipped).
- `enabled`, `cpc_target/min/max`, `net_per_dollar`, `confidence` are now computed **per intent class**.
- BRAND cells seed `enabled = TRUE` (defense) regardless of measured net/$.

### `DE_PRODUCT_MAIN_KEYWORDS`
- Add `is_brand BOOL` and `intent_class STRING`, stamped from `V_KEYWORD_INTENT_CLASS`.

### `DE_KEYWORD_INTENT_OVERRIDE` (new, editable)
- `parent_name, keyword_text, intent_class, updated_by, updated_at` — MANUAL corrections to classification.

## 5. Derivation (`tools/strategy_profile`)
- Join `V_KEYWORD_INTENT_CLASS` onto the keyword-day base; add `intent_class`.
- Group by `parent × season × match_type × intent_class`; compute `net_per_dollar`, best CPC band, `confidence` (same gates as B), `enabled = net_per_dollar > 0` (override to TRUE for BRAND).
- Preserve `source='MANUAL'` profile rows (unchanged MERGE discipline).
- Tag main keywords with `is_brand`/`intent_class`.

## 6. Steering (`V_ADS_COACH_DATA` / `V_ADS_COACH`)
1. `V_ADS_COACH_DATA`: join `V_KEYWORD_INTENT_CLASS` → each row carries `intent_class`; join `DE_PRODUCT_STRATEGY_PROFILE` on **(parent, season, match_type, intent_class)** instead of three keys.
2. `V_ADS_COACH` suppression CASE:
   - `intent_class = 'BRAND'` → **never suppress** (defense).
   - `intent_class = 'PRODUCT'` → **never suppress** bid-ups (protect/grow).
   - `intent_class = 'GENERIC'` AND `profile_enabled = FALSE` AND `profile_steers` AND not a defense strategy → cap bid-up at `MONITOR_TARGET` (suppress).
   - Decision-trace chip records the intent class + reason.
3. Band-clamp stays **MANUAL-only** (the I1 de-risk from B holds); this change is about suppression scope, not turning the broad band-clamp on.

## 7. What changes live
- Fresh/Lollibox **generic** exact → suppressed (the real −$666 / −$3,766 bleed).
- Fresh/Lollibox/LolliME **brand** exact → protected (defense).
- LolliME **product** (journal) exact → protected and free to scale — no longer caught by a blanket exact suppression.
- Generalizes to broad/auto (same intent split applies).

## 8. Migration
- `DE_PRODUCT_STRATEGY_PROFILE`: add the `intent_class` column (`ALTER TABLE`), then a full re-derive of DERIVED rows at the new grain. Existing `source='MANUAL'` rows (none yet) would be re-keyed by hand if present.
- Deploy `V_KEYWORD_INTENT_CLASS`, then the two coacher views; register all new objects in `config.yaml`.

## 9. Risks & limits
- **Research-fit mis-segmentation** (known for some families, e.g. Bottle/Bunny→Toys) → wrong PRODUCT/GENERIC calls; mitigated by anchors-are-PRODUCT and `DE_KEYWORD_INTENT_OVERRIDE`. Start by spot-checking the classification per family before relying on suppression.
- **Term-grain join**: research fit is per search_term; coacher keyword grain is `targeting`. Join misses default to GENERIC — acceptable (conservative; generic suppression only fires on CONCLUSIVE losers).
- **Cell thinning**: splitting by intent makes some cells thin → WEAK; suppression already fires only on CONCLUSIVE cells, so thin intent cells simply don't act.
- Same clicks-only-data caveat as B (foundation A still pending).

## 10. Testing
- `V_KEYWORD_INTENT_CLASS`: known terms classify correctly — "happy lolli gift box"→BRAND, "girls diary"/"journal for girls"→PRODUCT, "gift for 9 year old girl"→GENERIC; a `DE_KEYWORD_INTENT_OVERRIDE` row wins.
- Derivation: profile has per-intent rows; LolliME EXACT PRODUCT `enabled=TRUE` (net>0), Lollibox EXACT GENERIC `enabled=FALSE` (net<0), any BRAND cell `enabled=TRUE`.
- Steering (live validation): generic-exact INCREASE_BID suppressed for Fresh/Lollibox; LolliME product-exact and all brand-exact still able to bid up; row-count parity preserved; defense still exempt; `reduce_inversions=0` unchanged.
