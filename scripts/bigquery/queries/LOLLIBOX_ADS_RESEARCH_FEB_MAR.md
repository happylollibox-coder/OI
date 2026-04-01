# Lollibox ads research: Feb–Mar 2024 vs 2025 and “what’s missing”

## Data availability in OI

- **Feb–Mar 2024:** No Lollibox ads data in the database. FACT_AMAZON_ADS for your account starts Sep 2024; Lollibox does not appear in that period.
- **Feb–Mar 2025:** No Lollibox ads data. **Lollibox first appears in ads on 2025-10-28.** So there is no Feb–Mar 2025 Lollibox to compare.
- **What we can compare:** Oct 2025 → Nov → Dec 2025 (peak) vs Jan 2026 and Feb 2026 (recent drop).

So a direct “Feb–Mar 2024 vs Feb–Mar 2025” comparison for Lollibox is **not possible** in OI; those periods are either before Lollibox or before Lollibox campaigns exist in the pipeline.

---

## What the data shows: Dec 2025 vs Jan/Feb 2026

### Lollibox ads by month (all in OI)

| Month     | Spend    | Orders | Clicks  | CVR   | Campaigns |
|----------|----------|--------|---------|-------|-----------|
| Oct 2025 | $1.9k    | 101    | 4.4k    | 2.27% | 19        |
| Nov 2025 | $26.1k   | 1,658  | 75.4k   | 2.20% | 39        |
| **Dec 2025** | **$74.3k** | **4,732** | **137.3k** | **3.45%** | **29** |
| Jan 2026 | $11.6k   | 575    | 27.6k   | 2.08% | 12        |
| Feb 2026 | $6.5k    | 378    | 14.9k   | 2.54% | 12        |

So: **Lollibox is not selling as well lately** because **spend and number of active campaigns dropped a lot after the Dec 2025 peak**, not because conversion collapsed. CVR in Feb 2026 (2.54%) is actually a bit better than Jan (2.08%) and close to Nov (2.2%); Dec was an outlier (3.45%, holiday).

---

## What’s missing in Feb 2026 vs Dec 2025 (campaign level)

These campaigns drove a large share of Lollibox orders in Dec 2025 but have **zero** spend/orders in Feb 2026 (paused, removed, or renamed):

| Campaign (Dec 2025)              | Dec 2025 spend | Dec 2025 orders | Feb 2026 spend | Feb 2026 orders |
|----------------------------------|----------------|-----------------|----------------|-----------------|
| BOX- VIDEO (competitors-white)   | $12,013        | 685             | $0             | 0               |
| BOX- COMPETE (Copycats)         | $7,515         | 470             | $0             | 0               |
| BOX - AUTO (WHITE)              | $4,247         | 251             | $0             | 0               |
| BOX- VIDEO/BROAD (White)        | $2,723         | 168             | $0             | 0               |
| BOX- VIDEO/PHRASE (Blue)        | $1,631         | 89              | $0             | 0               |
| BOX-STORE/PHRASE                | $1,548         | 57              | $0             | 0               |
| BOX- AUTO (white video X8)      | $1,255         | 70              | $0             | 0               |
| BOX - EXACT (white - trendy)    | $1,024         | 57              | $0             | 0               |
| BRAND-SP/BROAD- gift for girl   | $690           | 65              | $0             | 0               |
| + several smaller BOX campaigns | ~$1.6k         | ~50             | $0             | 0               |

**Still running in Feb 2026 but at much lower spend:**

| Campaign                       | Dec 2025 spend | Dec 2025 orders | Feb 2026 spend | Feb 2026 orders |
|--------------------------------|----------------|-----------------|----------------|-----------------|
| BOX- STORE/ BROAD              | $13,796        | 1,075           | $623           | 32              |
| BOX- STORE broad (BY AGE)      | $8,015         | 506             | $1,257         | 79              |
| BOX -AUTO (white)              | $6,251         | 464             | $734           | 66              |
| BOX-VIDEO/BROAD (2 KW)         | $3,985         | 307             | $650           | 34              |
| BOX- COMPETE (Copycats white)  | $5,291 (Jan)   | —               | $529           | 21              |
| BOX - EXACT (white - teen)     | $253 (Jan)     | —               | $481           | 7               |
| BOX-SP/BOX (Excel words)       | $2,244         | 146             | $436           | 29              |
| BRAND-STORE/BROAD (old one)    | $2,531         | 166             | $227           | 29              |

So: **the main thing “missing” lately is budget and active campaigns** (especially Store, Video, and Compete), not a change in year‑over‑year seasonality that we can measure in OI for Feb–Mar 2024 vs 2025.

---

## Recommendations

1. **If the goal is to compare “Feb–Mar 2024 vs 2025”:**  
   That comparison is not in OI. You’d need another data source (e.g. Amazon Ads UI exports, or a different pipeline that had Lollibox in 2024/early 2025).

2. **To improve Lollibox sales now (with current data):**  
   - Consider re‑enabling or re‑budgeting the high‑impact campaigns that were on in Dec 2025 and are off or much lower in Feb 2026 (especially **BOX- VIDEO (competitors-white)**, **BOX- COMPETE (Copycats)**, **BOX - AUTO (WHITE)**, **BOX- STORE/ BROAD**).  
   - Keep fixing underperformers (e.g. Pink Lollibox search terms) so that when you increase spend again, efficiency doesn’t drop.

3. **To monitor going forward:**  
   Use the query in `LOLLIBOX_ADS_DEC_VS_FEB.sql` (or the monthly summary above) to compare last month vs same month prior year / vs Dec peak, and to see which campaigns are active and at what spend.

---

## Query reference

- **Monthly trend:** `LOLLIBOX_ADS_DEC_VS_FEB.sql` (Part 1).  
- **Campaign-level Dec vs Feb:** same file, Part 2.

Run in BigQuery against project `onyga-482313`, dataset `OI`.
