# משימה: ייצוא נתונים פיננסיים ל-Cowork (דוח כספי משפחתי)

**מבקש:** Claude Cowork (הדוח הכספי של אורי בתיקיית `/Users/ori/budget/`)
**מטרה:** ליצור כלי דטרמיניסטי שמייצא snapshot פיננסי מ-BigQuery לתיקיית budget, כדי שהדשבורד הכספי יתעדכן עם שווי מלאי ומכירות עדכניים.

## מה לבנות

צור `tools/export_finance_snapshot.py` (read-only, לפי כללי CLAUDE.md — כלי דטרמיניסטי, בלי אובייקטים חדשים ב-BQ) שכותב את הקבצים הבאים אל `/Users/ori/budget/data/` (צור את התיקייה אם אין):

### 1. `inventory_snapshot.csv`
```sql
SELECT Date, source_type,
       SUM(quantity_balance) AS units,
       SUM(COGS_AMOUNT)      AS cogs_value,
       SUM(SELL_AMOUNT)      AS sell_value,
       SUM(PAID_AMOUNT)      AS paid_amount
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
WHERE Date = (SELECT MAX(Date) FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`)
GROUP BY Date, source_type
ORDER BY source_type
```

### 2. `inventory_by_product.csv`
אותו snapshot אחרון, בפירוק לפי מוצר:
```sql
SELECT agg.Date, p.parent_name AS product_family, p.product_short_name,
       SUM(agg.quantity_balance) AS units,
       SUM(agg.COGS_AMOUNT) AS cogs_value,
       SUM(agg.SELL_AMOUNT) AS sell_value
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` agg
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p
  ON p.asin = agg.ASIN AND p.marketplace = 'ATVPDKIKX0DER'
WHERE agg.Date = (SELECT MAX(Date) FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`)
GROUP BY 1,2,3 ORDER BY cogs_value DESC
```

### 3. `ads_sales_monthly.csv`
```sql
SELECT FORMAT_DATE('%Y-%m', date) AS month,
       SUM(sales) AS ads_sales, SUM(ad_spend) AS ad_spend,
       SUM(orders) AS orders
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
GROUP BY 1 ORDER BY 1
```

### 4. `export_meta.json`
`{"exported_at": "<ISO timestamp>", "inventory_snapshot_date": "<Date>", "files": [...]}`

## דרישות
- הרצה: `python tools/export_finance_snapshot.py` (להשתמש ב-google-cloud-bigquery עם ה-ADC הקיים)
- להוסיף target ל-Makefile: `make export-finance`
- אידיאלי: להוסיף גם ל-cron מקומי / launchd הרצה יומית (אם אורי מאשר)
- אין לשנות שום דבר ב-BigQuery — קריאה בלבד

## אחרי שזה רץ
Cowork יקרא את הקבצים מ-`/Users/ori/budget/data/` בכל עדכון של הדוח הכספי, יוסיף את שווי המלאי לנכסים בתמונת המצב, ויבדוק מוכנות מלאי ל-Q4 מול תחזית המכירות.
