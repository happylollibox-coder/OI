# Lollibox: Add High-Spend, 0-Order Terms as Negatives

Use this to stop wasted spend on search terms that had **≥$1 spend** and **0 orders** in the last 30 days across all Lollibox campaigns.

**Total terms in CSV:** ~600 rows across all campaigns.

## Phase 1 – Quick wins (add these first)

Add these **phrase** negatives in the corresponding campaign to cut the biggest waste quickly:

| Campaign | Add these as negative phrase (top 5 by spend) |
|----------|-----------------------------------------------|
| **BOX -AUTO (white)** | gifts for teenage girls, tween girls gifts, gifts for 10 year old girl, valentines day gifts for teen girls, valentine gifts for teen girls |
| **BOX- COMPETE (Copycats white)** | b0clv7wyfp, cute stuff, valentines gift for teen girl, teen gifts for girls, gift box for teen girls |
| **BOX- STORE broad (BY AGE)** | 11 year old girl gifts, stuff for girls 10-12, girl stuff, 12 year old girl gifts, gifts for teen girls |
| **BOX- STORE/ BROAD** (Pink) | easter basket stuffers for teens, 10 year old girl gifts, 9 year old girl birthday gifts, 8 year old girl birthday gift, 10 year old girl birthday gifts |
| **BOX - EXACT (white - teen)** | teen girls gifts, teen girl gift, gifts for teens girls 12-14, gift for teen girls 12-14, gift for teens girls 12-14 |
| **BOX -EXACT/VIDEO (teen girl gifts trendy stuff)** | teens girls trendy stuff, teen girls trendy stuff, tween girl gifts trendy stuff |
| **BOX- COMPETE (Copycats)** | b0djs922kb, b0djs9jylr, cute things for teen girls |

Then use the full CSV for the rest.

## Files

| File | Use |
|------|-----|
| `LOLLIBOX_negative_keywords_by_campaign.csv` | Full list: **Campaign name** → **Negative keyword** → **Spend (30d)**. Use this as your source when adding negatives in Amazon Ads. |

## How to add in Amazon Ads

### Option A: Manual (campaign by campaign)

1. In **Amazon Advertising** → **Campaign Manager** → **Sponsored Products** (or **Stores** if any campaign is there), open the **Campaign** named in the CSV.
2. Go to the **Negative keywords** tab (campaign-level) or add at **ad group** level if you prefer.
3. **Add negative keyword** → choose **Phrase match** (recommended so close variants are blocked).
4. Copy each **negative_keyword** from the CSV for that campaign and add it. Skip the header row and any term that is your brand (e.g. “happy lolli” only if you want to block it in that campaign).

**Suggested order (by impact):**  
Add campaigns in this order to save the most spend first:

1. **BOX -AUTO (white)** – many terms, high total waste  
2. **BOX- COMPETE (Copycats white)** – ASINs and generic terms  
3. **BOX- STORE broad (BY AGE)** – Purple Lollibox; broad terms  
4. **BOX- STORE/ BROAD** – Pink Lollibox  
5. **BOX - EXACT (white - teen)**  
6. **BOX -EXACT/VIDEO (teen girl gifts trendy stuff)**  
7. **BOX- COMPETE (Copycats)**  
8. **BOX-SP/BROAD-(white- gift for girl)**  
9. **BOX-VIDEO/BROAD (2 KW)**  
10. **BOX-SP/PT (Product Defense)** – only if you want to block your own ASIN (b0c1vlxybp) here  
11. **BOX-SP/AUTO (White, Discovery)**  
12. **BRAND-STORE/BROAD (old one)**, **BOX-SP/EXACT (Teen Girl Gifts, Boost)** – if present in the CSV  

### Option B: Bulk upload (if your account supports it)

1. In Amazon Ads, go to **Bulk operations** (or **Portfolio** → **Bulk uploads**).
2. Download the **Negative keywords** template for Sponsored Products.
3. Fill:
   - **Campaign Name** = exact name from the CSV (e.g. `BOX -AUTO (white)`).
   - **Ad Group** = leave blank for campaign-level negatives, or set if you use ad-group negatives.
   - **Keyword** = the `negative_keyword` from the CSV.
   - **Match Type** = **Negative phrase** (recommended).
4. Upload the file.

**Note:** Do not add a term in the CSV that is longer than Amazon’s keyword limit (~100 chars). One term in the list is a very long “mayicivo…” phrase; you can skip it or truncate if the template rejects it.

## Important notes

- **Match type:** Use **Phrase** so variants (e.g. “gifts for teenage girls”) are blocked. Use **Exact** only if you want to block that exact phrase only.
- **Your brand:** The list may include “happy lolli” or “happy lolli gift box” in some campaigns. Add those as negatives only in campaigns where you do **not** want to show for brand (e.g. Product Defense / Compete). Do **not** add them in Brand Defense.
- **Own ASIN (b0c1vlxybp):** Appears under BOX-SP/PT (Product Defense). Add as negative only if that campaign should not show on searches for your own ASIN.
- **Re-run the query** periodically (e.g. every 2–4 weeks) to refresh the CSV; the file was generated from the last 30 days of data.

## Query used (BigQuery)

The list is generated from `onyga-482313.OI` with:

- **FACT_AMAZON_ADS** last 30 days  
- **Lollibox** = `DIM_PRODUCT.product_short_name` LIKE '%lollibox%'  
- **Include:** `search_term` with **sum(cost) ≥ 1** and **sum(orders) = 0**  
- Grouped by **campaign_name** and **search_term**, ordered by **campaign_name**, **spend** descending  

To regenerate the CSV, run the same query and export to `docs/LOLLIBOX_negative_keywords_by_campaign.csv`.
