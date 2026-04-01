# 🧠 Strategy-Specific Tracking — What Should Each Template Actually Measure?

*The core insight: each strategy answers a different business question, so tracking them with the same metrics is misleading.*

---

## Current System Assessment

The STRAT page already has **per-strategy metadata** (different `keyMetrics`, `learningQuestions`, `kpiColumns`, `chartMeasureIds`) in the frontend. But the **backend evaluation** (`V_EXPERIMENT_EVALUATION`) applies the same checks to all strategies: ROAS, CPC, waste %, and conversion rate — with only minor thresholds (e.g., Brand Defense needs ROAS ≥ 5x vs default 1.5x).

**What's missing:** SQP data is not connected to strategy evaluation at all. The system can't tell you "are we winning our brand words?" because it never joins experiment keywords → SQP impression data.

---

## Per-Strategy: Business Question → Primary KPI → Data Source

### 🛡️ BRAND DEFENSE

> **Business question:** "Am I winning my own brand search words?"

| What to track | Why | Data source | Currently tracked? |
|---|---|---|:---:|
| **SQP impression share on brand terms** | If I invest in brand defense, am I commanding more of the search results page for "happy lolli"? | SQP weekly | ❌ |
| SQP click share on brand terms | Are shoppers clicking MY listing vs competitor ads on my brand words? | SQP weekly | ❌ |
| SQP organic orders trend on brand terms | Is organic growing because ads block competitors? (halo effect) | SQP weekly | ❌ |
| CPC on brand terms (should be very low) | Brand defense shouldn't cost much — if CPC is rising, competitors are fighting back | Ads | ✅ |
| **CPC deterrence level** | Are we bidding high enough that competitors see brand conquest as unprofitable? Track our CPC vs market avg | Ads | ❌ |
| Conversion rate (should be very high) | Brand searchers intend to buy from us — CVR should be >15% | Ads | ✅ |

**CPC deterrence strategy:** The goal is not just to win — it's to make it *expensive for competitors to try*. By maintaining strong brand presence + high CVR, competitors' ROAS on our brand terms should be terrible. Track our CPC to ensure we're spending enough to dominate but not overpaying.

**How to connect:** Filter SQP data to queries containing brand names ("happy lolli", "lollime", "lollibox", product names — including misspellings like "lolly", "lolli me"). Show weekly trend of our impression share + click share alongside ads spend. The question becomes: *"When I spend $X on brand defense, does my SQP share go up?"*

**Brand keyword extraction:** We don't maintain a manual list of brand keywords today. Instead, extract them automatically from SQP data by matching search queries against: product family names, brand name variations, product-specific names. Include fuzzy matches for common misspellings ("lolly", "lolli me", "happylolli").

**Primary chart:** SQP Share % (line) vs Ads Spend (bar) over time

---

### 🎯 EXACT BOOST

> **Business question:** "Which product should I push on this keyword, and is it working?"

| What to track | Why | Data source | Currently tracked? |
|---|---|---|:---:|
| **Organic rank per keyword × ASIN** | The goal of Exact Boost is to improve organic rank by accelerating sales velocity | SQP (position) | ❌ |
| SQP impression share per keyword | Are we gaining visibility on the boosted terms? | SQP weekly | ❌ |
| **Which ASIN converges best per keyword** | Different variations convert differently — this may change by peak/season | Ads + KWDS Hero match | ⚠️ Partial (KWDS has it, not linked to STRAT) |
| Ads Conv% per keyword × ASIN | The product × keyword combo that converts best should get the budget | Ads | ✅ |
| Net ROAS per keyword | Is the investment returning profit? | Ads | ✅ |

**How to connect:** For each keyword in an Exact Boost experiment, join to SQP weekly data to show organic position trending. Per-keyword view: "Keyword X — pushed ASIN A for 4 weeks — organic rank improved from #12 → #5 — can now reduce bid."

**Primary chart:** Organic Rank (line, inverted Y-axis) + Ads Spend (bar) per keyword, over time

**Season/Peak awareness:** During peak, shoppers are more willing to pay premium prices, so for general keywords (e.g., "10 year old girl birthday gifts") it may be better to advertise a premium gift product during holidays vs a value product off-season.

> [!IMPORTANT]
> **Campaign planning consideration:** If you change the ASIN within an existing campaign, Amazon may reset the campaign's quality/relevance history. This means for seasonal product rotation, it's better to create **separate campaigns ahead of time** (e.g., `Lollibox-SP/EXACT (Easter)` vs `Lollibox-SP/EXACT (Evergreen)`), each targeting the same keywords but different products, and pause/activate them by season rather than swapping ASINs.

---

### 🔍 HUNTER (Broad Discovery)

> **Business question:** "What new keywords am I finding? Which ones graduate to Exact Boost?"

| What to track | Why | Data source | Currently tracked? |
|---|---|---|:---:|
| **New search terms discovered per week** | The primary output of Hunter is keyword discovery | Ads | ⚠️ Counted, not trended |
| Terms graduated to Exact Boost | Did the discovered terms actually get promoted? | Ads + Experiment links | ✅ (`terms_graduated_to_exact`) |
| SQP market volume of discovered terms | Is the keyword worth investing in? (big market or tiny niche?) | SQP | ❌ |
| Discovery ROAS (expected to be low) | Hunter accepts lower ROAS in exchange for finding new terms | Ads | ✅ |
| Keyword overlap with existing Exact Boosts | Are we paying twice for the same keyword in Hunter + Exact? | Ads | ✅ (`V_EXPERIMENT_KEYWORD_COLLISIONS`) |

**How to connect:** For each newly discovered converting term, auto-lookup its SQP market volume. Show: *"Hunter found 'teen girl gifts trendy stuff' — 210K SQP volume, 5 orders in 2 weeks — PROMOTE to Exact Boost?"*

**Primary chart:** New converting terms discovered (bar) + graduation rate (line) over time

---

### 💰 LOW COST DISCOVERY

> **Business question:** "What cheap long-tail keywords are hiding in the auto traffic?"

| What to track | Why | Data source | Currently tracked? |
|---|---|---|:---:|
| **CPC distribution** (goal: <$0.50) | The entire point is cheap clicks | Ads | ✅ |
| Terms per dollar spent | Efficiency of discovery | Ads | ❌ |
| Long-tail gradient rate | Did these auto terms make it to known Exact campaigns? | Ads | ✅ |
| Aggregate ROAS despite small per-term volume | Individual terms may look insignificant but the aggregate matters | Ads | ✅ |

**Primary chart:** CPC distribution histogram + terms found per week

---

### 🏰 PRODUCT DEFENSE

> **Business question:** "Are competitors stealing sales from my product pages?"

| What to track | Why | Data source | Currently tracked? |
|---|---|---|:---:|
| **Product page placement win rate** | Are we appearing in the "Sponsored products related to this item" on our own pages? | Ads (placement report) | ❌ |
| SQP conversion rate on ASIN-specific terms | If competitors are on our pages, our conversion drops | SQP | ❌ |
| Product page CPC | Should be cheap — our own shoppers, our own pages | Ads | ✅ |
| **CPC deterrence level** | Are we bidding high enough on product pages that competitors lose money trying to advertise on our listings? | Ads | ❌ |

**CPC deterrence strategy (same as Brand Defense):** By holding product page placement and maintaining high bids, competitors advertising on our pages will face low CTR + high CPC = unprofitable ROAS. Track whether our defensive spend makes competitor conquest unviable.

**Primary chart:** Placement win rate + conversion rate + CPC over time

---

### ⚔️ CATEGORY CONQUEST

> **Business question:** "Can we win market share on category terms we don't own today?"

| What to track | Why | Data source | Currently tracked? |
|---|---|---|:---:|
| **SQP impression share on category terms** | Are we appearing more often on "gifts for girls" type searches? | SQP | ❌ |
| New-to-brand orders | Are these truly new customers or are we cannibalizing? | Ads | ❌ |
| Market volume of conquered terms | Is the share gain meaningful in absolute orders? | SQP | ❌ |
| Category ROAS (expected lower than brand) | Category terms are harder — lower ROAS is acceptable if gaining share | Ads | ✅ |

**Primary chart:** SQP Share % (line) on target category terms vs Ads Spend (bar) over time

---

## Architecture Gap Summary

```
Current flow:
  Experiment → Campaigns → FACT_AMAZON_ADS → V_EXPERIMENT_EVALUATION
                                      ↑
                              (Ads metrics only: spend, clicks, orders, ROAS)

Needed flow:
  Experiment → Campaigns → FACT_AMAZON_ADS → V_EXPERIMENT_EVALUATION
                    ↓                                    ↓
              search_terms ────→ JOIN ←──── SQP weekly data
                                    ↓
                         Strategy-specific SQP KPIs
                         (impression share, position, click share)
```

**The join key:** Search term from the ads campaign → search query from SQP. These already exist in both datasets. The SQP data has 10-day lag but that's fine for weekly strategy evaluation.

---

## What Needs to Happen

| # | Change | Layer | Effort |
|:---:|---|---|---|
| 1 | **Classify search terms by strategy intent** — brand terms vs category terms vs competitor terms. Could use `DIM_PRODUCT.product_family` names + brand names as tags | BigQuery | Medium |
| 2 | **New view: `V_EXPERIMENT_SQP_OVERLAP`** — join experiment search terms to SQP weekly data. Per keyword: SQP impression share, click share, position, orders — trended weekly | BigQuery | Medium |
| 3 | **Extend `V_EXPERIMENT_EVALUATION`** — add strategy-specific checks using SQP data (e.g., Brand Defense: check if impression share on brand terms ≥ 80%) | BigQuery | Medium |
| 4 | **Dashboard: per-strategy chart type** — Brand Defense shows share trend, Exact Boost shows rank trend, Hunter shows discovery funnel | React | Medium |
| 5 | **KWDS page Hero ASIN: add seasonality awareness** — flag when the best product to boost changes during peak vs normal periods | BigQuery + React | High |

> [!NOTE]
> **Decisions confirmed:**
> - All 7 strategy types are active and should be tracked
> - Brand keywords: auto-extract from SQP data by matching against brand/product names + fuzzy variations
> - Seasonal Hero ASIN: premium products may perform better during peak. Use separate campaigns per season rather than swapping ASINs in existing campaigns
