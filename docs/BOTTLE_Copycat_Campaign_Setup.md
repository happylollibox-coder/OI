# Bottle Copycat Campaign Setup (Truth Or Dare – Category Conquest)

Use this to create or scale a **copycat (Category Conquest)** campaign for **Truth Or Dare** (Bottle, ASIN **B0F4KCCSWN**), mirroring how **BOX- COMPETE (Copycats white)** works for Lollibox.

---

## Current state

- **BOTTLE-COMPETE** already exists and is linked to experiment `TRUTH_OR_DARE_CATEGORY_CONQUEST_GIFT_GENERAL` (strategy: CATEGORY_CONQUEST).
- In the last 30 days it had very low activity (~$2.69 spend, 1 order) and may be paused or underfunded.
- **BOX- COMPETE (Copycats white)** runs with **product targeting** on 6+ competitor ASINs, ~$400 spend and 14 orders in 30 days.

---

## How BOX copycat is set up (mirror this for Bottle)

| Setting | BOX- COMPETE (Copycats white) | Apply to Bottle |
|--------|-------------------------------|------------------|
| **Advertised product** | White Lollibox (B0C1VLXYBP) | Truth Or Dare (B0F4KCCSWN) |
| **Targeting type** | **Product targeting** (competitor ASINs) | Same |
| **Campaign type** | Sponsored Products | Same (SP) |
| **Targets** | Multiple competitor ASINs (e.g. B0DJS922KB, B0CLV7WYFP, B0DJS97SGG, B0DJS9JYLR, B0FY34F5V1, B0FG2LM9V8) | Add 5–10 competitor ASINs in same category (party games, truth or dare, teen girl games) |
| **Bidding** | DOWN_ONLY (per README) | Start $0.25–$0.75, DOWN_ONLY |
| **Budget** | See V_EXPERIMENT_CAMPAIGN_SETTINGS | Start **$15–25/day** for test |

---

## Step-by-step: Create or fix the bottle copycat campaign

### Option A: Revive and scale existing BOTTLE-COMPETE

1. **In Amazon Advertising (Seller Central)**  
   - Go to **Campaign Manager** → **Sponsored Products**.
   - Find campaign **BOTTLE-COMPETE**. If paused, enable it.

2. **Set budget and bids**  
   - **Daily budget:** e.g. **$20–25** (match BOX copycat level).  
   - **Default bid (product targeting):** **$0.35–0.50** (DOWN_ONLY in Amazon = “Dynamic bids – down only”).

3. **Add more competitor ASINs (product targets)**  
   - In the campaign, open the **Product targeting** ad group(s).  
   - Add **product targets** (Individual product / ASIN) for competitors in the same space:
     - **Past targets that had orders (from your data):** B00VJ664AO, B0CXNXZCZ2, B089G2MTRX (sleepover / party games).
     - **New ideas:** Search Amazon for “truth or dare game”, “party games for teen girls”, “sleepover games” and add 5–10 competitor ASINs from the first 1–2 pages.

4. **Negate your own brand**  
   - Add **negative keywords** (if the campaign has keyword targeting) or ensure you’re not bidding on “happy lolli”, “truth or dare” (your product name) in this campaign so you don’t compete with yourself.

5. **Optional: second campaign (SB Video)**  
   - Per README, CATEGORY_CONQUEST can have Campaign 2: **SB Video Broad**, budget ~$20/day, bid ~$0.30–0.80, same competitor theme. Create only if you have video creative and want to test.

---

### Option B: Create a new campaign from scratch

1. **Create campaign**  
   - **Campaign type:** Sponsored Products.  
   - **Name:** e.g. **BOTTLE- COMPETE (Copycats)** or **BOTTLE- COMPETE (Truth Or Dare)**.  
   - **Daily budget:** $20–25.  
   - **Bidding:** Dynamic bids – down only.

2. **Create ad group**  
   - **Advertised product:** Truth Or Dare (**B0F4KCCSWN**).  
   - **Targeting:** **Product targeting** → “Individual product” → add competitor ASINs (see list below).

3. **Add competitor ASINs**  
   - Start with 5–10 ASINs from:
     - Your best-performing past targets: **B00VJ664AO**, **B0CXNXZCZ2**, **B089G2MTRX**.  
     - Manual search on Amazon: “truth or dare game”, “party games for girls”, “sleepover party games” — pick top organic results that are close competitors.

4. **Link to OI (optional)**  
   - In `DIM_EXPERIMENT_CAMPAIGN` add a row linking the new campaign_id to experiment **TRUTH_OR_DARE_CATEGORY_CONQUEST_GIFT_GENERAL** (or create a new experiment with strategy_id **CATEGORY_CONQUEST** and then link the campaign).  
   - This keeps reporting and daily protocol aligned.

---

## Competitor ASINs to consider (Bottle / party games space)

From your historical BOTTLE-COMPETE data, these had impressions/orders:

| ASIN | Note (from your data) |
|------|------------------------|
| **B00VJ664AO** | High spend, 50 orders historically – strong candidate |
| **B0CXNXZCZ2** | 6 orders – good |
| **B089G2MTRX** | 5 orders – good |
| **B0G1G5343H** | Currently in BOTTLE-COMPETE (low recent spend) |
| **B0DQ5KX6W6** | Tested |

Add others by searching “truth or dare”, “party games for teens”, “sleepover games” on Amazon and copying ASINs from competitor listings.

---

## Checklist

- [ ] Campaign name includes “BOTTLE” and “COMPETE” (or “Copycat”) so reporting is clear.  
- [ ] Only **B0F4KCCSWN** (Truth Or Dare) is advertised in this campaign.  
- [ ] Targeting is **product targeting** (competitor ASINs), not broad keywords.  
- [ ] Daily budget $15–25; default bid $0.35–0.50; Dynamic bids – down only.  
- [ ] 5–10 competitor ASINs added.  
- [ ] Own brand terms negated if there is keyword targeting.  
- [ ] Campaign linked to experiment in OI if you use the experiment system.

---

## Success criteria (from README)

- **Weeks 1–2:** Ads show on competitor pages; low CVR is normal.  
- **Week 3:** Search terms report shows which competitor audiences click. Negate your brand.  
- **Week 4+:** ROAS > 0.8 and 3+ new converting terms = success. ROAS < 0.5 and no converting terms = consider pausing or changing targets.

---

## Reference

- **Strategy:** CATEGORY_CONQUEST (see `scripts/bigquery/README_EXPERIMENTS.md`, Section 6 – Strategy Playbooks).  
- **BOX copycat targets:** B0DJS922KB, B0CLV7WYFP, B0DJS97SGG, B0DJS9JYLR, B0FY34F5V1, B0FG2LM9V8 (Lollibox-style gift box competitors).  
- **Bottle product:** Truth Or Dare, ASIN **B0F4KCCSWN**.
