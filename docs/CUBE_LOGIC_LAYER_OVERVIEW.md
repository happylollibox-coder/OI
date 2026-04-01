# Cube Logic Layer — Full Overview

## Logic Layer Cubes (Single Source of Truth)

These cubes use **BigQuery UDFs** and **V_PRODUCT_FAMILY_MAP** — no duplicated formula logic.

### 1. WeeklyTrends
- **Source**: FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS
- **Grain**: family × week
- **UDFs**: FN_COGS, FN_NET_ROAS, FN_ORGANIC_PCT, FN_NET_PROFIT
- **View**: V_PRODUCT_FAMILY_MAP
- **Measures**: sales, adCost, cogs, netProfit, orders, clicks, sessions, netRoas, organicPct

### 2. MonthlyTrends
- **Source**: FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS
- **Grain**: family × month
- **UDFs**: FN_COGS, FN_NET_ROAS, FN_ORGANIC_PCT, FN_NET_PROFIT
- **View**: V_PRODUCT_FAMILY_MAP
- **Measures**: sales, adCost, cogs, netProfit, orders, clicks, sessions, netRoas, organicPct

### 3. WeeklyTrendsByAsin
- **Source**: FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS
- **Grain**: family × ASIN × week
- **UDFs**: FN_COGS, FN_NET_ROAS, FN_ORGANIC_PCT, FN_NET_PROFIT
- **View**: V_PRODUCT_FAMILY_MAP
- **Measures**: sales, adCost, cogs, netProfit, orders, clicks, sessions, netRoas, organicPct

### 4. MonthlyTrendsByAsin
- **Source**: FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS
- **Grain**: family × ASIN × month
- **UDFs**: FN_COGS, FN_NET_ROAS, FN_ORGANIC_PCT, FN_NET_PROFIT
- **View**: V_PRODUCT_FAMILY_MAP
- **Measures**: sales, adCost, cogs, netProfit, orders, clicks, sessions, netRoas, organicPct

### 5. Summary
- **Source**: FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS
- **Grain**: family (7d + prev 7d)
- **UDFs**: FN_COGS, FN_NET_ROAS, FN_ORGANIC_PCT, FN_NET_PROFIT
- **View**: V_PRODUCT_FAMILY_MAP
- **Dimensions**: productType, sales7d, adCost7d, cogs7d, netProfit7d, orders7d, etc.

### 6. Ads
- **Source**: FACT_AMAZON_ADS (raw table)
- **UDFs**: FN_COGS (for cogs measure)
- **Table columns**: cost, impressions, clicks, orders, sales, units, TOTAL_COST_PER_UNIT, GROSS_PROFIT
- **Measures**: spend, orders, clicks, impressions, sales, cogs, grossProfit

---

## Duplication Check

| Formula / Logic        | WeeklyTrends | MonthlyTrends | WeeklyByAsin | MonthlyByAsin | Summary | Ads |
|------------------------|-------------|---------------|--------------|--------------|---------|-----|
| COGS                   | FN_COGS     | FN_COGS       | FN_COGS      | FN_COGS      | FN_COGS | FN_COGS |
| Net ROAS               | FN_NET_ROAS | FN_NET_ROAS   | FN_NET_ROAS  | FN_NET_ROAS  | FN_NET_ROAS | — (client calc) |
| Organic %              | FN_ORGANIC_PCT | FN_ORGANIC_PCT | FN_ORGANIC_PCT | FN_ORGANIC_PCT | FN_ORGANIC_PCT | — |
| Net Profit             | FN_NET_PROFIT | FN_NET_PROFIT | FN_NET_PROFIT | FN_NET_PROFIT | FN_NET_PROFIT | — |
| Family mapping         | V_PRODUCT_FAMILY_MAP | V_PRODUCT_FAMILY_MAP | V_PRODUCT_FAMILY_MAP | V_PRODUCT_FAMILY_MAP | V_PRODUCT_FAMILY_MAP | — |
| FACT_AMAZON_ADS cols   | cost, clicks, orders | cost, clicks, orders | cost, clicks, orders | cost, clicks, orders | cost, clicks, impressions, orders | cost, impressions, clicks, orders, sales, units |

**No duplication** — all formulas come from BigQuery UDFs and the shared view.

---

## Other Cubes (Not Logic Layer)

These do **not** use the shared UDFs/view:

| Cube | Uses Logic Layer? | Notes |
|------|-------------------|-------|
| ExperimentTemplates | No | Uses raw `a.cost`, `a.orders`, etc. from FACT_AMAZON_ADS; net_roas = (sales - cost)/cost (gross, not Net ROAS) |
| DataFreshness | No | Simple MAX(date) |
| Product, Sqp, etc. | No | Raw tables |

---

## FACT_AMAZON_ADS Column Names

**Actual table** uses: `cost`, `impressions`, `clicks`, `orders`, `sales`, `units` (no `Ads_` prefix).

The DDL file `FACT_AMAZON_ADS.sql` shows `Ads_cost` etc. — that is **out of sync** with the live table.

---

## Ads Page Empty — Troubleshooting

If the Ads page is empty:

1. **Restart Cube** — Kill the Cube process and run `cd cube && npm run dev` again. Schema is loaded at startup.
2. **Check VITE_CUBE_API_URL** — In `dashboard-react/.env` ensure `VITE_CUBE_API_URL=http://localhost:4000` (or your Cube URL).
3. **Check browser console** — Look for `[cubeLoad]` or `[useCubeData]` warnings. Failed requests return `[]` silently.
4. **Check Network tab** — Find the POST to `/cubejs-api/v1/load`. If it fails (404, 500), Cube may be down or the proxy misconfigured.
5. **Verify Cube directly** — `curl -X POST http://localhost:4000/cubejs-api/v1/load -H "Content-Type: application/json" -d '{"query":{"measures":["Ads.spend"],"limit":1}}'` should return data.
