# Ads Coach — Audit Findings (June 2026)

Deep audit of the Actions-page cards vs SQL ground truth, triggered by inflated
clicks/orders on bid cards. Each finding lists **practical impact** (decisions or
$ affected, not theoretical severity) and **fix cost**, because impact ≠ severity
here — the most interesting bug has the smallest footprint.

## Priority summary

| # | Finding | Practical impact | Fix cost | Priority | Status |
|---|---------|------------------|----------|----------|--------|
| 1 | Target/budget rollup fan-out | HIGH — all bid/budget cards 4–7× inflated | Low | — | ✅ SHIPPED 2026-06-17 |
| 2 | Per-action card fragmentation | Med — display/trust, multi-action keywords | Med | P2 | open |
| 3 | Off-season vs displayed 1w ROAS mismatch | Med — display/trust | Low–Med | P2 | open |
| 4 | Margin over-credit (advertised vs purchased SKU) | **LOW — ~1 live decision flips** | High (correct) / Low (proxy) | P3 | open |
| 5 | TOS-/impression-share-blind bidding | Med — decision quality (enhancement) | Med–High | P3 | open |

---

## 1. Target/budget rollup fan-out — ✅ SHIPPED 2026-06-17
Bid/budget cards summed a fanned-out join (campaign→multi-experiment, joined twice;
+ cross-targeting 4w grain). Fixed in `SP_REFRESH_ADS_COACH_ACTIONS` (dedupe
`campaign_experiment`, 4w volume from `ca`, asin in join, net_profit from corrected
volume). girls journal 132/1232→33/173. See `project_coach_target_rollup_fanout_bug`.

## 2. Per-action card fragmentation — P2
**What:** Step 4 groups TARGET rows by `(campaign, targeting, target_action)`, so one
keyword/ASIN splits into several cards (e.g. INCREASE_BID + KEEP_TARGET + SWITCH_HERO),
each summing only the search-terms that got that action.
**Evidence:** "gifts for tween girls" (Pink Lollibox) — 3 weekly orders split as
2 (INCREASE_BID card) + 1 (KEEP_TARGET) + 0 (SWITCH_HERO). The INCREASE_BID card shows
2/3 of the keyword and ROAS 0.86, while the engine decides on the whole keyword.
**Fix:** show whole-keyword evidence on the bid card, or collapse the per-action split.
Also investigate *why* one keyword/ASIN gets three different `target_action`s.

## 3. Off-season vs displayed 1w ROAS mismatch — P2
**What:** the card shows `ads_net_roas_1w` (raw, all days); in GUARDIAN/COOLDOWN the
engine decides on `target_net_roas_1w_os` (boost/peak days excluded —
`V_ADS_COACH_DATA.sql:1199`). They diverge, and the off-season value is **not stored in
FACT**, so the card literally can't show the number that justified the action.
**Evidence:** gifts-for-tween-girls card 1W 0.86 vs engine basis 1.27 (compounded by #2).
Note: June 10–16 had **zero** boost/peak days, so the off-season *exclusion* was a no-op
that week — the 0.86 vs 1.27 gap was actually #2 (per-action fragment), not off-season.
**Fix:** surface the decision ROAS on the card (add `target_net_roas_1w_os` to FACT +
display, or show the trace summary), so green actions stop sitting next to red evidence.

## 4. Margin over-credit: advertised vs purchased SKU — REAL, but LOW impact — P3
**What:** net ROAS uses `margin_per_unit = list_price − all_in_cost` of the **advertised**
product, applied to **every** attributed order. Amazon attributes cross-SKU purchases
(often cheaper products) to the ad, so net ROAS is overstated where clicks convert to
cheaper items. (`all_in_cost` does include FBA+referral+pick/pack+shipping — that part is fine.)
**Evidence:** Pink Lollibox ad (8w) — engine net ROAS 1.23 vs purchased-mix ~0.99
(half the conversions were cheaper LolliMEs/bunnies valued at the Lollibox margin).
**Scope — why it's LOW impact:** realized-revenue/list ratio is ~0.96–1.02 for most
products; only **Pink Lollibox 0.84, Choice Bunny 0.88, Blue Lollibox 0.92** are
materially diluted. Of **39** active bid-up decisions clearing the bar, **only 1 flips**
below it after correction. Most products' ad-clickers buy similar-priced products.
**Fix options:**
- *Correct but HIGH cost:* purchased-mix margin from `V_SRC_AmazonAds_purchased_product`.
  Blocked on reconciliation — that report is **other-SKU/halo only** and on a different
  window (FACT = SP 30d / SB 14d; purchased = 30d default). A uniform **14-day** rebuild
  is feasible (raw `search_term_ad_keyword_report` exposes `purchases_14_d`/`sales_14_d`;
  SB already 14d; purchased has `_14d`). Then layer advertised-SKU margin + halo margin.
- *Pragmatic, recommended:* use **realized ASP** (`Ads_sales/Ads_units` over 4w/8w, min-order
  gated) instead of list price for `margin_per_unit`, falling back to list when sparse.
  FACT-only, no report reconciliation, same window as the decision; slightly conservative
  (applies advertised cost to cheaper cross-buys → Pink Lollibox lands ~0.90 vs true ~0.99).
**Recommendation:** don't build the purchased-mix rebuild for ~1 decision. Do the realized-ASP
proxy (or just exclude the one term). Revisit the full fix if discounting/halo grows (Q4 deals).

## 5. TOS-/impression-share-blind bidding — P3 (enhancement)
**What:** the engine bids purely on ROAS/orders and never reads Top-of-Search IS /
impression share, so it treats a term at <5% TOS (lots of headroom) identically to one
at 60–80% TOS (saturated).
**Evidence:** happy lolli ~60% TOS (brand, near-saturated → a bid raise is mostly
insurance); gifts for tween girls <5% TOS (headroom, but marginal economics + 0.38% CTR).
**Fix:** add impression-share/TOS as a bid input — scale where headroom *and* economics
hold; don't keep raising bids on terms you already dominate.

---

### Cross-cutting theme
Findings 2, 3, 4 are the same pattern: **the card displays one number while the engine
decides on another**, and the deciding number often isn't surfaced. Closing that
display↔decision gap (show what the engine actually used) would resolve most of the
"this recommendation looks wrong" friction.
