# CPC Strategy → Net Profit — Findings (2026-06)

_Generated from 6,602 regime-segments across 4 parents; 133/192 cells statistically conclusive._

> Observational analysis — associational, not causal. See spec.

> Two orthogonal labels: `cpc_action` (RAISE/LOWER/CONSTANT = what we did to CPC) and
> `duration_class` (TRANSIENT/HELD = how long it persisted). A raise that then holds
> stays a RAISE — duration no longer overwrites the action.

## De-confound: net profit/day by CPC action × hold duration (pooled)

| cpc_action   | TRANSIENT      | HELD          |
|:-------------|:---------------|:--------------|
| RAISE        | -0.62 (n=1684) | +1.12 (n=505) |
| LOWER        | -0.74 (n=1688) | +0.24 (n=816) |
| CONSTANT     | -0.60 (n=1424) | +1.01 (n=485) |

## Net profit/day by CPC action, per parent (pooled, descriptive)

| parent_name   |   RAISE |   LOWER |   CONSTANT |
|:--------------|--------:|--------:|-----------:|
| Bottle        |   -0.4  |   -0.42 |      -0.26 |
| Fresh         |   -0.5  |   -0.46 |      -0.35 |
| LolliME       |    0.16 |   -0.45 |      -0.31 |
| Lollibox      |   -0.69 |   -0.68 |      -0.59 |

## Recommended CPC action per parent × calendar part

| parent_name   | calendar_segment        | recommended_action   |   winner_npd | confidence   | coacher_bias   | agrees_with_coacher   |
|:--------------|:------------------------|:---------------------|-------------:|:-------------|:---------------|:----------------------|
| Bottle        | Christmas_BOOST         | CONSTANT             |    0.480174  | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Christmas_COOLDOWN      | LOWER                |   -0.64      | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Christmas_PEAK          | RAISE                |    2.08656   | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Cyber Monday_COOLDOWN   | CONSTANT             |    3.21055   | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Cyber Monday_PEAK       | CONSTANT             |   -0.195     | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | EVERYDAY_2025-12        | LOWER                |   -0.703333  | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | EVERYDAY_2026-01        | RAISE                |    0.840759  | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | EVERYDAY_2026-04        | RAISE                |    0.101759  | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | EVERYDAY_2026-05        | RAISE                |   -0.08      | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | EVERYDAY_2026-06        | LOWER                |   -1.1325    | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Easter_BOOST            | LOWER                |   -0.3       | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Easter_COOLDOWN         | LOWER                |   -0.22875   | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Easter_PEAK             | LOWER                |    0.94325   | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Valentines Day_BOOST    | LOWER                |    1.73522   | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Valentines Day_COOLDOWN | LOWER                |   -0.396667  | CONCLUSIVE   | nan            | <NA>                  |
| Bottle        | Valentines Day_PEAK     | LOWER                |    0.0207403 | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Christmas_COOLDOWN      | RAISE                |   -1.4       | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Christmas_PEAK          | RAISE                |    4.86977   | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Cyber Monday_COOLDOWN   | RAISE                |    5.38067   | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Cyber Monday_PEAK       | RAISE                |    0.195103  | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | EVERYDAY_2026-01        | LOWER                |    0.407873  | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | EVERYDAY_2026-04        | LOWER                |   -0.48      | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | EVERYDAY_2026-05        | LOWER                |   -0.7       | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | EVERYDAY_2026-06        | RAISE                |   -1.38      | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Easter_BOOST            | RAISE                |   -0.233795  | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Easter_COOLDOWN         | RAISE                |   -0.821858  | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Easter_PEAK             | RAISE                |    4.85997   | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Valentines Day_BOOST    | RAISE                |   -0.650608  | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Valentines Day_COOLDOWN | LOWER                |    5.45209   | CONCLUSIVE   | nan            | <NA>                  |
| Fresh         | Valentines Day_PEAK     | RAISE                |    4.04782   | CONCLUSIVE   | nan            | <NA>                  |
| LolliME       | Christmas_COOLDOWN      | LOWER                |   -0.531667  | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Christmas_PEAK          | RAISE                |    6.57683   | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Cyber Monday_COOLDOWN   | RAISE                |    3.7924    | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Cyber Monday_PEAK       | RAISE                |    0.885315  | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | EVERYDAY_2025-12        | LOWER                |   -0.78      | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | EVERYDAY_2026-01        | LOWER                |   -0.561667  | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | EVERYDAY_2026-04        | RAISE                |   -0.170663  | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | EVERYDAY_2026-05        | RAISE                |    0.76567   | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | EVERYDAY_2026-06        | RAISE                |   -0.68      | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Easter_BOOST            | LOWER                |    1.1062    | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Easter_COOLDOWN         | LOWER                |   -0.552532  | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Easter_PEAK             | LOWER                |    0.0866667 | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Valentines Day_BOOST    | RAISE                |   -0.6068    | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Valentines Day_COOLDOWN | LOWER                |    0.181753  | CONCLUSIVE   | MIXED          | False                 |
| LolliME       | Valentines Day_PEAK     | LOWER                |    1.67303   | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Christmas_BOOST         | RAISE                |    3.49522   | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Christmas_COOLDOWN      | LOWER                |   -0.925     | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Christmas_PEAK          | RAISE                |   -0.2       | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Cyber Monday_COOLDOWN   | LOWER                |   -0.545     | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Cyber Monday_PEAK       | CONSTANT             |   -0.640501  | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | EVERYDAY_2025-12        | LOWER                |   -0.71      | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | EVERYDAY_2026-01        | CONSTANT             |   -0.276667  | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | EVERYDAY_2026-04        | CONSTANT             |   -0.394444  | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | EVERYDAY_2026-05        | CONSTANT             |   -0.505     | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | EVERYDAY_2026-06        | CONSTANT             |   -0.65      | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Easter_BOOST            | RAISE                |   -0.502222  | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Easter_COOLDOWN         | CONSTANT             |   -0.44      | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Easter_PEAK             | LOWER                |   -0.503136  | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Valentines Day_BOOST    | LOWER                |    0.292989  | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Valentines Day_COOLDOWN | LOWER                |   -0.77625   | CONCLUSIVE   | MIXED          | False                 |
| Lollibox      | Valentines Day_PEAK     | LOWER                |    0.522177  | CONCLUSIVE   | MIXED          | False                 |

## Power coverage (where we can vs cannot conclude)

| parent_name   |   CONCLUSIVE |   WEAK |
|:--------------|-------------:|-------:|
| Bottle        |           25 |     25 |
| Fresh         |           29 |     15 |
| LolliME       |           36 |     14 |
| Lollibox      |           43 |      5 |

## Charts

- `.tmp/cpc_strategy/charts/cpc_vs_profit_Bottle.png`
- `.tmp/cpc_strategy/charts/cpc_vs_profit_Fresh.png`
- `.tmp/cpc_strategy/charts/cpc_vs_profit_LolliME.png`
- `.tmp/cpc_strategy/charts/cpc_vs_profit_Lollibox.png`
- `.tmp/cpc_strategy/charts/npd_by_strategy_Bottle.png`
- `.tmp/cpc_strategy/charts/npd_by_strategy_Fresh.png`
- `.tmp/cpc_strategy/charts/npd_by_strategy_LolliME.png`
- `.tmp/cpc_strategy/charts/npd_by_strategy_Lollibox.png`

---

## Addendum 2026-07-04 — band grain split by campaign_type + ad_format

**Finding.** The pooled CPC band hid a systematic bias: **Sponsored Brands VIDEO ads convert profitably at a higher CPC than PRODUCT_COLLECTION**, across every family. Because collection carries far more click volume, the pooled band was dragged toward collection and **under-bid video**.

| family | BRAND_VIDEO avg target | PRODUCT_COLLECTION avg target |
|---|---:|---:|
| Fresh | $0.55 | $0.35 |
| LolliME | $0.57 | $0.43 |
| Lollibox | $0.75 | $0.45 |

Focus cell — **LolliME · OFF · BROAD · generic** (net profit by $0.10 CPC bin): PRODUCT_COLLECTION peaks at **$0.35** (+$266), BRAND_VIDEO peaks at **$0.45** (+$107) and stays profitable to $0.75. Sponsored Products BROAD·generic is negligible for LolliME (11 kw-days, 0 orders). STORE_SPOTLIGHT is absent from Happy Lolli's data — only BRAND_VIDEO + PRODUCT_COLLECTION carry volume.

**Change.** `DE_PRODUCT_STRATEGY_PROFILE` grain extended from `parent × season × match × intent` to **`… × campaign_type × ad_format`**, emitted as two layers:
- **Coarse** rows tagged `campaign_type = ad_format = 'ALL'` — the pooled band, unchanged. Guaranteed fallback; the unit `borrow.py` + `V_STRATEGY_GAPS` operate on.
- **Fine** rows split by SP/SB and SB creative type (`BRAND_VIDEO` / `PRODUCT_COLLECTION` / `NA`).

`V_ADS_COACH_DATA` joins both (`psp` coarse pinned to `ALL/ALL` to avoid fan-out; `pspf` fine on all six keys via `V_SRC_AmazonAds_sb_ad_report` → `ad_group_id` → `creative_type`) and uses the **fine band only where its own evidence is CONCLUSIVE**, else the coarse fallback (`profile_ad_format` records which). No keyword loses its band; ~99% resolve to a fine band, ~310 fall back to coarse.

## Manual band-cell fills (2026-08-01, claude-do-all)

Three missing band cells were filled directly in `DE_PRODUCT_STRATEGY_PROFILE` from realized CPC history (Ori-approved), with `source='derived-from-realized-cpc 2026-08-01'`: Lollibox OFF PRODUCT ALL/ALL (0.65 / 0.30-0.70, CONCLUSIVE, 4,835 clk), Fresh OFF PRODUCT ALL/ALL (0.55 / 0.40-0.60, WEAK, 148 clk), Fresh PEAK PRODUCT ALL/ALL (0.45 / 0.40-0.60, WEAK, 93 clk), plus the first SB STORE_SPOTLIGHT fine cell Lollibox OFF BROAD (0.35 / 0.20-0.50, WEAK, 32 clk). Method: converting-target-day spend-weighted median CPC, snapped down to the nearest net-profit-positive $0.10 bin midpoint; min/max = contiguous net-positive bin run (derive.py `best_cpc_band` convention).

**Rules for any future manual/agent band fill:**
1. **Never plain-INSERT a cell that already has a row.** `V_ADS_COACH_DATA` joins the profile on the 6-part key (parent, season, match, intent, campaign_type, ad_format) assuming at most one row per key; a duplicate key fans out every matching keyword row in the coach. Use MERGE (update-when-matched) and re-check `GROUP BY key HAVING COUNT(*)>1` = 0 after writing.
2. **Custom-source rows survive the refresh tool but the tool re-emits the same cells.** `tools/strategy_profile/load.py` deletes only `source IN ('DERIVED','BORROWED')` before reloading, and `derive_profile` emits every cell with data - so the next `tools/strategy_profile/run.py` will recreate DERIVED/BORROWED rows on top of any custom-source (or MANUAL) key, reintroducing the fan-out. After each refresh, dedupe those keys (keep the reviewed row) until the tool learns to skip keys held by non-DERIVED sources.
3. WEAK rows are invisible to `V_KEYWORD_LIFT`/`V_OOB_KEYWORD` band joins (CONCLUSIVE-only, enabled-only). A WEAK fill positions the cell for review in Admin but does not steer until confidence is raised or volume accrues.
