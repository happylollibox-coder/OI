# Ads 1-Week Data Comparison: Dashboard vs Amazon Console

## Reference: Amazon Console (Feb 22–28, 2026)

From the Amazon Ads Portfolios view:
- **Date range**: Feb 22, 2026 – Feb 28, 2026 (Sun–Sat)
- **Total cost**: $4,084.52
- **Total sales**: $16,055.74
- **ROAS**: 3.22
- **Scope**: 5 portfolios (GOX, MEZ, FRFSH, BRAND, BOTFLE)

---

## Our Data (FACT_AMAZON_ADS, same dates)

| Scope | Cost | Sales | ROAS |
|-------|------|-------|------|
| **All rows** (dashboard source) | $5,021.31 | $16,780.75 | 3.34 |
| **Rows with ASIN in DIM_PRODUCT** | $4,996.46 | $16,726.35 | 3.35 |
| **5 portfolios only** (BOX, ME, FRESH, BRAND, BOTTLE) | $4,996.46 | $16,726.35 | 3.35 |

---

## Discrepancy Summary

| Metric | Amazon | OI | Difference |
|--------|--------|-----|------------|
| Cost | $4,085 | $5,021 | +$937 (~23% higher) |
| Sales | $16,056 | $16,781 | +$725 (~4.5% higher) |
| ROAS | 3.22 | 3.34 | +0.12 |

---

## Likely Causes

1. **Scope**
   - Amazon: Portfolio-level view (5 portfolios).
   - OI: All campaigns in `FACT_AMAZON_ADS` (no portfolio filter).
   - Extra spend may come from campaigns not in those 5 portfolios or from different portfolio mapping.

2. **Portfolio mapping**
   - Amazon: GOX, MEZ, FRFSH, BRAND, BOTFLE.
   - OI: BOX, ME, FRESH, BRAND, BOTTLE (from `V_SRC_AmazonAds_portfolio`).
   - Names differ; temporal joins (`OI_start_date`, `OI_end_date`) can change which campaigns belong to which portfolio.

3. **Week definition**
   - Both use Sun–Sat (Feb 22 = Sunday).
   - Dashboard `getWeekStart()` uses Sunday as week start, so Feb 22–28 is consistent.

4. **Data freshness**
   - Amazon: live console.
   - OI: `FACT_AMAZON_ADS` from Fivetran sync; may lag by hours or days.

5. **Product filter**
   - OI Ads cube: LEFT JOIN to `Product` (DIM_PRODUCT).
   - All rows are included; ~$25 cost is from ASINs not in DIM_PRODUCT.

---

## Validation Query

To compare portfolio-level data:

```bash
bq query --use_legacy_sql=false < scripts/bigquery/queries/validation/VALIDATE_ADS_PORTFOLIO_LEVEL.sql
```

(Update date literals in the query to match the desired range.)

---

## Cube vs Dashboard Discrepancy

**Cube Playground** (Feb 22–28): 404 orders, $16,780.75 sales. The dashboard can differ because:

1. **Different period** – Dashboard defaults to the **latest** period. Use **Weekly** mode and select **Feb 22 – Feb 28** to match Cube.
2. **Period mode** – Weekly = 7 days; Monthly = full month (Feb 1–28).
3. **Filters** – Family, Experiment, or Keyword filters reduce totals.

---

## Recommendations

1. **Match period when comparing** – Select Feb 22–28 explicitly on the dashboard.
2. **Add portfolio filter to Ads page** – Allow filtering by portfolio to align with Amazon’s view.
3. **Reconcile portfolio names** – Map OI portfolio names (BOX, ME, etc.) to Amazon (GOX, MEZ, etc.).
4. **Document sync timing** – Note when `FACT_AMAZON_ADS` was last refreshed vs Amazon console.
