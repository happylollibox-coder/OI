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

---

## Budget Actions (`budget_action` column)

| Action | Conditions |
|--------|------------|
| `INCREASE_BUDGET` | Campaign profitable + high utilization |
| `DECREASE_BUDGET` | Campaign unprofitable + low utilization |
| `RESTORE_BUDGET` | Cooldown: restore to pre-peak budget |
| `KEEP_BUDGET` | Default |

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

---

## Thresholds (from `DE_COACH_THRESHOLDS`)

| Threshold | Key | Default | Used By |
|-----------|-----|---------|---------|
| Min Clicks | `min_clicks` | 15 | Insufficient data gate |
| Negate ROAS | `negate_roas` | 0.5 | NEGATE_EXACT / STOP_TERM |
| Negate Spend | `negate_spend` | $20 | Legacy (clicks preferred) |
| Reduce Bid ROAS | `reduce_bid_roas` | 0.9 | REDUCE_BID |
| Scale Up ROAS | `scale_up_roas` | 2.0 | INCREASE_BID |
| Profitable ROAS | `profitable_roas` | 1.1 | INCREASE_BID (baseline) |
| Promote Min Orders | `promote_min_orders` | 4 | PROMOTE_TO_EXACT |
| Promote Min ROAS | `promote_min_roas` | 1.5 | PROMOTE_TO_EXACT |
| Halo ROAS | `halo_roas` | 0.5 | SQP halo credit |

---

## Mode-Aware ROAS Resolution

The ROAS metric used depends on the coach mode:

| Mode | Term ROAS | Target ROAS |
|------|-----------|-------------|
| **GUARDIAN** | `COALESCE(ads_weighted_net_roas_offseason, ads_weighted_net_roas, ads_net_roas_8w)` | `COALESCE(target_weighted_net_roas_offseason, target_weighted_net_roas, target_net_roas_8w)` |
| **COOLDOWN** | Same as GUARDIAN | Same as GUARDIAN |
| **BLITZ** | `COALESCE(ads_weighted_net_roas_hotseason, ads_weighted_net_roas, ads_net_roas_8w)` | `COALESCE(target_weighted_net_roas_hotseason, target_weighted_net_roas, target_net_roas_8w)` |
| **Default** | `COALESCE(ads_weighted_net_roas, ads_net_roas_8w)` | `COALESCE(target_weighted_net_roas, target_net_roas_8w)` |

---

## Maintenance Log

| Date | Change |
|------|--------|
| 2026-04-13 | Added lag window safety check (3-day look-ahead) for REDUCE_BID and ROAS-based NEGATE_EXACT. |
| 2026-04-13 | Fixed deploy script: V_ADS_COACH was read but never deployed to BigQuery. |
| 2026-04-13 | Added paused target guard: INCREASE_BID/REDUCE_BID only fire for ENABLED keywords. Paused/archived → TARGET_PAUSED. |
