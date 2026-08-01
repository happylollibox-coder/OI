# Out-of-budget phase — Weekly Run

**Date:** 2026-07-30 · **Owner:** Ori · **Status:** v2 — campaign → keyword → search-term hierarchy + apply-all (v1: campaign-level advisory)

## Goal (Ori, verbatim intent)

> "Main goal is that campaigns won't be out of budget but use almost all their budget.
> If campaign is out of budget and performs good — raise budget."

A **technical phase**, deliberately straightforward: one screen listing every enabled campaign
(SP **and** SB, launch **and** working) that Amazon reported `CAMPAIGN_OUT_OF_BUDGET` on the
anchor day, with the dark %, utilization, performance and ONE budget suggestion each.

## Where

Weekly Run page, its own collapsible section directly **below the Coach-logic flowchart** and above
the launch cards. Component: `dashboard-react/src/pages/OobBudgetPhase.tsx` · cube `OobBudget`
(live read) · view `scripts/bigquery/views/V_OOB_BUDGET_PHASE.sql`.

## Rules (same definitions as the launch controller's budget ladder — applied uniformly)

Signals: `pct_dark` = share of the anchor day Amazon reported out-of-budget (from the unified
`V_SRC_AmazonAds_campaign_history` event log — see CAMPAIGN_LAUNCH_RAMP.md §"Status source");
net ROAS = corrected gross profit ÷ spend, 1.0 = breakeven (SP from FACT + price-tier COGS; SB
estimated via the campaign's mapped ASIN cost ratio, same as `V_SB_LAUNCH_CAMPAIGN`).

**Tier split (Ori 2026-07-30 v3):** evidence windows scale with the budget tier — small campaigns
are judged daily, working campaigns on their working cadence. STRONG needs BOTH windows; CUT needs
BOTH windows bad (symmetric evidence, no one-day verdicts).

| tier | condition (first match wins) | action | suggested budget |
|---|---|---|---|
| all | dark ≤ 10% | WATCH | — |
| ≤ low-budget cap ($20 off / $30 peak) | last-day ≥ 1.2× AND prev-2d ≥ 1.5× | RAISE_STRONG | `LEAST(budget ÷ %active, ×3)` |
| | last-day ≥ 1.2× | RAISE_WEAK | `LEAST(budget ÷ %active, ×2)` |
| | last-day < 0.9× AND prev-2d < 0.9× | CUT | −10%/day toward $10 |
| | else | HOLD | — |
| > cap, off-season (7d/28d windows) | 7d ≥ 1.2× AND 28d ≥ 1.5× | RAISE_STRONG | same formulas |
| | 7d ≥ 1.2× | RAISE_WEAK | |
| | 7d < 0.9× | CUT | −10%/day toward $10 |
| | else | HOLD | — |
| > cap, peak (3d/7d windows) | 3d ≥ 1.2× AND 7d ≥ 1.5× | RAISE_STRONG | |
| | 3d ≥ 1.2× | RAISE_WEAK | |
| | 7d < 0.9× | CUT | |
| | else | HOLD | — |

> cap cadence throttle: re-suggest only when the last budget change is ≥ 7 days old (off-season) /
≥ 3 days (peak) — the working-campaign rhythm.

`budget ÷ %active` is the projection of what a full serving day would cost — the raise that makes
the campaign *stop* being dark, which is the phase's goal state: **dark 0%, utilization ~85–100%**.

## v2 — keyword and search-term layers (Ori 2026-07-30)

Hierarchy on the panel: **campaign → keywords → search terms**, with one **apply-all** button that
queues every suggestion (budget updates + bid updates + term negations) into the DO queue /
bulksheet flow. Mechanism note (validated in data 2026-07-30): bid cuts do NOT reduce spend — the
budget caps spend either way; they lower CPC so the same budget serves more of the day. 69% of
dark-campaign spend sat on 6+-click keywords, so the −5% lever touches most of the money.

**Keyword layer** (`V_OOB_KEYWORD` — SP keywords/auto/PT **and SB keywords/product targets**;
v2.1, Ori: "i cant see sb keywords as a hierarchy". SB signals from the SB reports with the
est.-net-ROAS cost-ratio method; SB bids from the live sb_keyword / sb_product_target config
mirrors. **Target CPC column** (Ori: "based on time last year if data exists"): precedence =
(1) same 28 days one year back (364-day offset keeps weekday alignment; needs ≥10 LY clicks),
(2) else the coacher band `cpc_target` (product × season × match, conclusive ALL/ALL cells
averaged), (3) else — . Auto clauses/PT skip LY — the clause text is not product-specific.):
same constants as the launch controller, applied to every OOB campaign regardless of engine —
- CONVERTING (net ROAS ≥ 1.0 on last day OR prior-2d) while CAPPED (Ori 2026-07-30, BOX-VIDEO/PT
  case): **never raise the bid** — with clicks ≥ the 4-click goal and bid above the realized 3-day
  CPC, **FIT the bid down to that CPC** (−15%/day, floored at real CPC): "increase budget to $15
  offers ~5 more clicks, but reducing the bid gets more clicks from the same budget." Both levers
  fire together: budget raise buys volume, cheaper clicks buy more of it. Otherwise hold. The ROAS
  ladder raises (+15%/+30% toward $2) survive only in the launch controller's NOT-capped branch.
- NOT converting → **budget-constrained probing economics** (Ori 2026-07-30: "the under-4-clicks
  is due to low budget not low bid" — 10 keywords × 4 clicks at ~$1 CPC = $40 of probing demand on
  a $10 budget; the purpose is to find a winner who then funds the others). In a dark campaign,
  first match wins:

  **SEAT MODEL (Ori 2026-08-01, "lets do it" — supersedes spreading the budget over every target):**
  a capped campaign can only afford to TEST `slots = max(1, round(budget ÷ $4))` keywords at once
  ($10 → 3 seats, $20 → 5, $30 → 8; ~$4/day buys one keyword its 4-click trial). Seats are ranked:
  **(1) converting keywords by recent net ROAS** (winner is always main), **(2) mid-test keywords by
  clicks-so-far** (finish what you started), **(3) untested candidates** by target-CPC-anchored /
  LY-volume rank. Tested losers (≥15 clk/90d, 0 orders) are never seated. Everything beyond the
  seats **PARK_WAITs at $0.25 in a queue** — its test pauses, not dies. When a seat frees (a test
  reaches its 15-click verdict) the next candidate **ACTIVATEs** at `min(1.5 × target CPC, $1.50)`
  (fallback: the per-seat affordable CPC). Growth is paced by the 20% rule: at most
  `max(1, floor(0.20 × budget ÷ $4))` activations per day — 80% of any budget raise keeps feeding
  the winners. The per-seat affordable CPC = `budget ÷ (slots × 4)` (≈$0.83 on $10/3 seats)
  replaces the old all-targets affordable as the TRIM target: real trial economics, not a number
  diluted by ten idle bids. Real example (ME-SP/PT Competitors Mint C1, $10, 10 targets): 90d spend
  $115 — $72 went to two tested losers while the two converters took $32; the seat model gives the
  3 seats to the 1.23× winner, the 1.03× marginal and the 7/15 mid-test, queues 5, parks the rest.
  1. **tested ≥ 15 clicks over 90d, no sale → PARK at $0.25** — it had its test; free the budget
     for the untested keywords, even if the parked bid gets no clicks.
  2. **bid above the affordable CPC with REAL evidence (≥ 4 clicks yesterday) → TRIM toward it** —
     the affordable CPC = `budget ÷ (targets × 4-click goal)`, floored $0.20 (Ori: "TRIM floor
     should not stop at $1.00"). Step = `max(15%, 30% × dark)` per day. Evidence gate added
     2026-08-01 (Ori: "cheap gift for girl has only 1 click but action is reduce bid due to bid
     eats the budget") — 1–2 clicks is NOT proof the keyword eats the budget; those rows fall to
     the campaign-wide brake below.
  3. **any keyword that clicked YESTERDAY, above the $0.20 floor → DARK_BRAKE** (Ori 2026-08-01:
     never brake a keyword that did not click — its bid did not eat the budget) (2026-08-01, replaces flat SLOW
     −5%): the bid lever against darkness is CAMPAIGN-WIDE and proportional — step =
     `max(5%, 30% × dark)` per day (68% dark → −20%/day; 82% → −25%/day), re-fires every day the
     campaign stays capped, floor $0.20 — Ori: "bid should be reduced with more than 5% and
     continue reducing until dark is 0%" (single-keyword BOX-VIDEO/PT case) and "no keyword is the
     eater — the campaign bleeds from many small bids" (VIDEO- COMP/BALL case). The brake stops
     when the campaign leaves the dark set (dark ≤ 10%, the phase's WATCH tolerance).
  4. zero clicks in both windows → **HOLD, never probe up** — the constraint is budget, not bid.
     (+5% probing survives only in the launch controller's NOT-capped branch.)
  A found winner automatically becomes **main**: the others park/trim, the freed budget flows to
  him, his ROAS ladder raises him, and campaign profitability triggers the budget promotion.
- 1-day cooldown: a keyword changed < 1 day ago (FACT_PPC_CHANGE_LOG) shows HOLD "changed today".

**Search-term layer** (`V_OOB_SEARCH_TERM`, SP + SB, TWO windows — Ori 2026-07-30: "to negate
general big words need to check 3 month data; small volume words 28 days are enough"):
- **big general word** (≥ 30 clicks over 90 complete days **ACCOUNT-WIDE**, all campaigns SP+SB —
  per-slice volume fragments a big word into "small" pieces; caught by Ori on "teen girl gifts
  trendy stuff": 13 clicks in one slice, 1,326 clicks / 11 orders account-wide) → negate only on
  **0 orders anywhere in the full 90d**, AND (Ori 2026-07-30, the 2-week-old campaign case: "too
  early to negate — only after real 90 days with at least 25 clicks I will consider") only in
  campaigns **≥ 90 days old** with **≥ 25 clicks for this word in this campaign** — a young
  campaign hasn't given a big word its own trial yet;
- **small word** → negate at **≥ 10 clicks · 0 orders over 28d**;
plus the structural rules: the term is not the keyword itself (`term ≠ keyword`, normalized —
applies to MANUAL and SB keywords), AUTO targets skip the term≠keyword test (every auto term
differs by construction; the 0-order gate protects harvesting), PT targets excluded entirely
(the "term" is the targeted ASIN). Winners (orders in 90d) are shown, never negated.

`days_since_budget_change` (from `FACT_PPC_CHANGE_LOG`) is displayed so re-suggestions after a
fresh change are visibly "just changed".

## Lever 2B — 80/20 portfolio + probe rotation (Ori 2026-07-30, `V_KEYWORD_LIFT`)

Working campaigns only (budget > low-budget cap), SP **and SB** (v2 2026-07-30), dark or not.
Window W = 7d off-season / 3d peak. Classes over W (corrected net ROAS): WINNER ≥ 1.1 with ≥ 1
order · MARGINAL 0.7–1.1 with orders · LOSER < 0.7 or clicks with 0 orders · IDLE (candidate pool).

**80% of spend to winners:** losers ranked best-first (ROAS desc) keep spending inside a 20%
exploration allowance; everything beyond it PARKs at $0.25. **1–2 probes at a time**: next
candidate (anchored first, then LY volume) lifts to `min(1.5 × target CPC, $2)` (fallback:
winners' avg CPC); the probe episode is STATELESS — measured as FACT activity after the last
INCREASE_BID upload (change log); bid moves daily during the test (6+ clicks/day no sale → −5%);
**verdict at 20 episode clicks**: ≥ 1.0× → WINNER_FOUND (joins the 80% pool), else PARK and the
next 1–2 candidates promote. Goal: every un-parked keyword profitable over W — the best keyword
per intent at the best bid. Probing keywords are exempt from PARK/TRIM and (by design) from the
coacher's pullback; this engine's verdicts take precedence for keywords it touched within W.
Panel: `KeywordLiftPhase.tsx` ("Portfolio 80/20") below the Out-of-budget section; rows route to
the SP/SB bulksheet tab by the view's `channel` column.

**SB arm (v2, 2026-07-30).** Coverage audit 2026-07-30: 9 enabled SB working campaigns
(~$2,525/wk — e.g. ME-VIDEO/EXACT $200, FRESH-VIDEO/BROAD $100, ME-VIDEO/BROAD Hunter $53) had
NO keyword engine — not dark (outside the OOB phase), budget > cap (off the launch controller),
and V_KEYWORD_LIFT was SP-only. Same classes / 20% allowance / probe machinery on SB-native
sources, the way `V_SB_LAUNCH_TARGET` mirrors `V_LAUNCH_PHASE1`:

- **Population:** `V_DIM_CAMPAIGN_CURRENT` `campaign_type='SB'`, ENABLED + serving
  (ENABLED / OUT_OF_BUDGET), budget > cap — same predicate as the SP arm.
- **Targets + live bids:** the minutes-fresh config mirrors `sb_keyword` ∪ `sb_product_target`
  (enabled, not deleted; SB has no auto clauses); ad-group `default_bid` fallback as SP.
- **Performance:** `sb_search_term_report` (keyword_id grain) ∪ `sb_target_report` (target
  grain) — **NOT `sb_keyword_report`** (died 2025-12-29; `sb_product_target_report` does not
  exist). Anchor day = sb_search_term_report watermark (per-channel anchors, same as this phase).
- **Net ROAS:** the SB ESTIMATE `sales × (1 − mapped-ASIN cost_ratio) ÷ spend` — SB reports have
  no per-unit COGS (same method as all SB views). Orders = `attributed_conversions_14_d`.
- **Target CPC precedence:** LY same-28d (keyword text, account-wide, ≥10 LY clicks) → the FINE
  band cell (`campaign_type='SB'` × ad_format via `DIM_AD_GROUP.creative_type` × match,
  CONCLUSIVE) → the coarse ALL/ALL band. Product targets skip LY (band or nothing).
- **Probe episodes:** stateless, same as SP — last INCREASE_BID in `FACT_PPC_CHANGE_LOG`
  (keyword_id holds the SB target id), 14d lookback, episode evidence = SB report activity after
  the upload date, verdict at 20 episode clicks.
- **Capped guard — both arms (v3 2026-07-30; SB-only in v2):** `PROBE_START` requires the
  campaign NOT capping (dark ≤ 10% on the anchor day, from the channel's own event log — SB
  anchored on its report watermark, SP on FACT's `wm`) — in a capped campaign under-clicking is
  the budget dying, not the bid; probing up is a budget artifact (the no-loss-cuts rule). Idle
  keywords there show IDLE "capped — probes held". Running probes still get verdicts and the
  −5% descent. The SP gap was latent when closed: on 2026-07-30 no SP PROBE_START sat in a dark
  campaign (BOX-SP/AUTO (White), 22% dark, had 0 probe starts).

## Known caveats

- SB campaigns overdeliver up to **2× daily budget** while "out of budget" (Amazon SB rule) —
  utilization > 100% on SB rows is real spend, not a bug.
- For LAUNCH campaigns the suggestion matches `V_LAUNCH_PHASE1`'s dark-gated branch by
  construction (same constants); the not-dark branches (starve / promotion) live only in the
  launch controller — this phase only covers campaigns that actually went dark.
- Anchor day per channel: SP anchors on FACT's watermark, SB on `sb_campaign_report`'s — each
  channel is judged on its own last complete day, mirroring the two launch engines.
