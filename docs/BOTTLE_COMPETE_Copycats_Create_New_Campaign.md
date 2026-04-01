# Create New Campaign: BOTTLE- COMPETE (Copycats)

Follow these steps in **Amazon Advertising (Seller Central)** to create the new campaign, then register it in OI.

---

## Part 1: Create campaign in Amazon

### 1. Open Campaign Manager

- Go to **Seller Central** → **Advertising** → **Campaign Manager** (or **Ads** → **Campaigns**).
- Choose **Sponsored Products**.

### 2. Create campaign

- Click **Create campaign**.
- Set:

| Field | Value |
|-------|--------|
| **Campaign name** | **BOTTLE- COMPETE (Copycats)** |
| **Campaign type** | Sponsored Products |
| **Daily budget** | **$25** (or $20 if you prefer to start lower) |
| **Start and end date** | No end date (run indefinitely) |
| **Targeting type** | **Product targeting** (not keyword) |
| **Bidding strategy** | **Dynamic bids – down only** |

- Save / Continue.

### 3. Create ad group and add product target

- **Ad group name:** e.g. **BOTTLE- Copycats – Product targets**.
- **Advertised product:** select **Truth Or Dare** (ASIN **B0F4KCCSWN**). Only this ASIN in this campaign.
- **Product targeting:** add **Individual products** (ASINs). Add these first (proven from your data):

| ASIN | Use |
|------|-----|
| **B00VJ664AO** | Strong historical performer |
| **B0CXNXZCZ2** | Good orders |
| **B089G2MTRX** | Good orders |
| **B0G1G5343H** | Already in bottle conquest |
| **B0DQ5KX6W6** | Tested |

- Add **5–10** more if needed: search Amazon for “truth or dare game”, “party games for teen girls”, “sleepover games” and add ASINs from top competitor listings.
- **Default bid:** **$0.40** (or $0.35–0.50 range).

### 4. Create ad

- Use your standard **Truth Or Dare** product ad (no extra creative needed for product targeting).
- Launch the campaign.

### 5. Get the campaign ID (for OI)

- After the campaign is created, open it and check the **URL** in your browser, or use **Advertising** → **Bulk operations** / **Reports** and export a campaign list. The **campaign_id** is the numeric ID (e.g. `446012015657681`). Copy it for Part 2.

---

## Part 2: Register campaign in OI (BigQuery)

After the campaign exists in Amazon, link it to the existing Bottle Category Conquest experiment so it appears in OI reports and the daily protocol.

1. Replace **`YOUR_CAMPAIGN_ID`** below with the actual campaign ID from Amazon (e.g. `446012015657681`).
2. Run this in **BigQuery** (project `onyga-482313`, dataset `OI`):

```sql
-- Link new campaign BOTTLE- COMPETE (Copycats) to TRUTH_OR_DARE CATEGORY_CONQUEST experiment
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` (
  experiment_id,
  campaign_id,
  campaign_name,
  notes
)
VALUES (
  'TRUTH_OR_DARE_CATEGORY_CONQUEST_GIFT_GENERAL',
  'YOUR_CAMPAIGN_ID',   -- Replace with actual campaign ID from Amazon
  'BOTTLE- COMPETE (Copycats)',
  'Created [today date]. SP product targeting on competitor ASINs (party games / truth or dare). Advertised ASIN: B0F4KCCSWN.'
);
```

3. After Fivetran syncs, the new campaign will appear in **V_EXPERIMENT_CAMPAIGN_SETTINGS**, **V_EXPERIMENT_BUDGET_HEALTH**, and daily protocol queries.

---

## Quick reference

| Item | Value |
|------|--------|
| **Campaign name** | BOTTLE- COMPETE (Copycats) |
| **Advertised ASIN** | B0F4KCCSWN (Truth Or Dare) |
| **Targeting** | Product targeting (competitor ASINs only) |
| **Daily budget** | $25 (or $20) |
| **Bid** | $0.40 (dynamic down only) |
| **Experiment (OI)** | TRUTH_OR_DARE_CATEGORY_CONQUEST_GIFT_GENERAL |
| **Strategy** | CATEGORY_CONQUEST |

---

## Optional: negative keywords

If this campaign ever has **keyword** targeting (e.g. from auto-targeting), add **negative phrase** for your brand so you don’t compete with Brand Defense:

- **happy lolli**
- **truth or dare** (if that’s your product name and you defend it elsewhere)

For a **product-targeting-only** campaign, no keyword negatives are required.
