# Orders Watermark — Last Complete Sales Day

> The single rule that decides which date blended/sales windows anchor on.
> If Yesterday/7d/30d numbers look ~half-size during the morning, start here.

## Definition (canonical, 2026-08-05)

```sql
-- Last date with COMPLETE Seller-Central business-report data
SELECT MAX(date) AS latest_date
FROM (
  SELECT date
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE Performance_TYPE = 'Organic'
  GROUP BY date
  HAVING SUM(ASIN_SESSIONS) > 0
)
```

(The nested subquery matters: `MAX(date)` with a bare `GROUP BY date` would return one
row per day and fan out the consumer. All four consumers must use this exact rule —
see Consumers.)

## Why the sessions gate

The old rule was bare `MAX(date) WHERE Performance_TYPE = 'Organic'`. On 2026-08-05,
during the Fivetran sync window, the first partial order rows for 2026-08-03 landed
(sales $1,697 of an eventual $3,689, sessions 0). The bare watermark advanced to Aug 3
mid-sync, so the Home brief anchored Yesterday/7d/30d on a partial day and under-reported
sales by ~54% until the sync finished.

**Sync ordering:** within a Fivetran load, order/sales rows land before traffic
(sessions) rows. A day whose Organic rows have orders but `SUM(ASIN_SESSIONS) = 0`
is mid-sync, not complete.

**Signal verification (2026-08-05):** across all 857 loaded days
(2024-03-27 → 2026-08-03), no settled day has `SUM(ASIN_SESSIONS) = 0`;
the minimum daily Organic sessions is 1,157. US-only marketplace, so a genuine
zero-traffic day is not a realistic false-negative risk.

## Consumers (must stay identical)

| View | Where |
|---|---|
| `V_SUMMARY_7D` | `date_ranges` CTE — anchors Home 7d/prev-7d windows |
| `V_DATA_FRESHNESS` | `FACT_AMAZON_PERFORMANCE_DAILY` source row — "Data as of" header |
| `V_PLAN_FORECAST` | `last_loaded_date` CTE — anchors last-30d actuals |
| `V_FAMILY_NET_PROFIT_7D` | `wm` CTE — anchors budget-waterfall family weights |

SQL files: `scripts/bigquery/views/{V_SUMMARY_7D,V_DATA_FRESHNESS,V_PLAN_FORECAST,V_FAMILY_NET_PROFIT_7D}.sql`

## Related rules

- **Never anchor blended/sales windows on the ads watermark** — ads rows run ~1 day
  ahead of the business report (see comment in `V_SUMMARY_7D.sql`).
- Cube reads `T_` tables: after redeploying any consumer view, the fix is not live on
  the dashboard until the `T_` rebuild + cache stamp runs (`LOG_PIPELINE_RUNS`).
