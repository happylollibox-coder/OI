# משימה v2: הרחבת ייצוא הנתונים הפיננסיים ל-Cowork

**מבקש:** Claude Cowork (הדוח הכספי של אורי ב-`/Users/ori/budget/`)
**מטרה:** להוסיף היסטוריה של שווי מלאי וחוב לספקים, כדי להשוות בין שנים (הכנסות/הוצאות/מלאי/חוב ליצרן ולמשלח).

## מה להוסיף ל-`tools/export_finance_snapshot.py` (read-only, אל תשנה כלום ב-BQ)

### 1. `inventory_history.csv` — שווי מלאי בסוף כל חודש
Snapshot אחרון של כל חודש, בפירוק owned מול factory:
```sql
WITH month_ends AS (
  SELECT FORMAT_DATE('%Y-%m', Date) AS month, MAX(Date) AS snap_date
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  GROUP BY 1
)
SELECT m.month, m.snap_date,
  SUM(CASE WHEN s.source_type IN ('FBA','AWD','In Transit','In Transit AWD') THEN s.COGS_AMOUNT ELSE 0 END) AS owned_cogs,
  SUM(CASE WHEN s.source_type IN ('MFR Ready','In Production') THEN s.COGS_AMOUNT ELSE 0 END) AS factory_cogs,
  SUM(CASE WHEN s.source_type IN ('MFR Ready','In Production') THEN s.PAID_AMOUNT ELSE 0 END) AS factory_paid,
  SUM(s.COGS_AMOUNT) AS total_cogs,
  SUM(s.SELL_AMOUNT) AS total_sell,
  SUM(s.quantity_balance) AS total_units
FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` s
JOIN month_ends m ON s.Date = m.snap_date
GROUP BY 1,2 ORDER BY 1
```

### 2. `purchase_orders.csv` — כל הזמנות הרכש
```sql
SELECT po_number, supplier, order_date, status, total_amount
FROM `onyga-482313.OI.DE_PURCHASE_ORDERS`
ORDER BY order_date
```
(אם יש עמודות paid_amount / balance / due_date — כלול גם אותן. המטרה: לחשב חוב פתוח לסילביה ולאנה לפי תאריך.)

### 3. עדכן את `export_meta.json` עם שמות הקבצים החדשים ותאריכי הכיסוי.

## הרצה
`make export-finance` → הקבצים ל-`/Users/ori/budget/data/` כרגיל.

## למה זה משמש
Cowork יבנה השוואה שנתית: הכנסות, הוצאות, שווי מלאי בסוף שנה, וחוב פתוח ליצרן (SYLVIA) ולמשלח (ANNA) — כדי לראות את הרווחיות הכלכלית האמיתית (לא רק תזרים) של כל שנה.

---

## 🐞 בדיקת באג דחופה: COGS_AMOUNT מנופח ב-FACT_INVENTORY_SNAPSHOT

אורי מצא אי-התאמה, ואימות שלנו מאשר:
- **White Lollibox**: עלות אמיתית ליחידה = 12.75 (ייצור) + 3.28 (שילוח) = **$16.03**. ה-snapshot (2026-08-15) מראה 6,286 יחידות עם COGS_AMOUNT כולל $195,338 → **$31.08 ליחידה** — פי ~1.94.
- דפוס חשוד בכל המוצרים: COGS ליחידה יוצא 52%–62% ממחיר המכירה (Lollibox 31.08/54.40, LolliME ~20.4/32.90, Bunny ~9.4/16.99, Fresh ~29/49.90) — נראה כמו ניפוח שיטתי, לא טעות נקודתית.

חשודים לבדיקה:
1. איך COGS_AMOUNT מחושב בטעינת FACT_INVENTORY_SNAPSHOT — האם cost_of_goods + shipping_cost מוכפלים פעמיים? האם עמודת עלות מכילה total במקום per-unit איפשהו?
2. Join fan-out — הצטרפות ל-DIM_PRODUCT/עלויות לפי sku מול asin שמכפילה שורות עלות (הכמויות נראות נכונות, אז כנראה רק צד העלות מוכפל).
3. האם cost_of_goods כבר כולל shipping ואז shipping מתווסף שוב.

**פלט מבוקש (בנוסף לקבצי v2):**
- `product_costs.csv`: asin, product_short_name, cost_of_goods ליחידה, shipping_cost ליחידה — מטבלת העלויות המקורית (לא מה-FACT), כדי שנוכל לחשב שווי מלאי נכון באופן בלתי תלוי.
- תיקון החישוב ב-FACT (או ב-view) + הרצה מחדש של `make export-finance`.
