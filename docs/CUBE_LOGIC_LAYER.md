# Cube Logic Layer — Single Source of Truth

Measures logic is centralized to avoid duplication and ensure consistency.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ BigQuery (single source of truth)                                 │
├─────────────────────────────────────────────────────────────────┤
│ V_PRODUCT_FAMILY_MAP  │ asin → family mapping                     │
│ FN_COGS               │ units × cost_per_unit                     │
│ FN_NET_ROAS           │ (sales − cogs) ÷ ad_cost                  │
│ FN_ORGANIC_PCT        │ organic_orders ÷ total_orders × 100       │
│ FN_NET_PROFIT         │ sales − ad_cost − cogs                    │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ Cube schema (cube/schema/)                                        │
├─────────────────────────────────────────────────────────────────┤
│ WeeklyTrends              │ Uses view + UDFs                      │
│ MonthlyTrends             │ Uses view + UDFs                      │
│ WeeklyTrendsByAsin        │ Uses view + UDFs                      │
│ MonthlyTrendsByAsin       │ Uses view + UDFs                      │
│ Summary                   │ Uses view + UDFs                      │
│ Ads                       │ Uses FN_COGS for cogs measure         │
└─────────────────────────────────────────────────────────────────┘
```

## Deploy Order

1. **Deploy BigQuery objects** (UDFs + view):
   ```bash
   ./deployment/deploy_cube_logic_layer.sh
   ```

2. **Start Cube** — schema will use the deployed objects.

## ROAS Definitions

| Name       | Formula                    | Used in                    |
|------------|----------------------------|----------------------------|
| **Net ROAS**  | (Sales − COGS) ÷ Ad Spend | Trends, Summary, Ads       |
| **Gross ROAS**| Sales ÷ Ad Spend          | Ads (grossProfit measure)  |

## Files

| File | Purpose |
|------|---------|
| `scripts/bigquery/views/V_PRODUCT_FAMILY_MAP.sql` | Family mapping (Lollibox, LolliME, etc.) |
| `scripts/bigquery/functions/FN_COGS.sql` | COGS = units × cost_per_unit |
| `scripts/bigquery/functions/FN_NET_ROAS.sql` | Net ROAS formula |
| `scripts/bigquery/functions/FN_ORGANIC_PCT.sql` | Organic % formula |
| `scripts/bigquery/functions/FN_NET_PROFIT.sql` | Net profit formula |
