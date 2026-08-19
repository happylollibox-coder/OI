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
     **v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3, 2026-08-16):** the dark-scaled step collapses to
     the 5% minimum whenever pct_dark reads low — but a campaign OOB-owned on the 7-day hysteresis
     can sit at 0% dark TODAY while a keyword burns double-digit clicks with zero sales (root case:
     Ori's "22 clicks and no bid trimming — why?"; measured: BALL Mint substitutes 23c at 0.00×
     braked 5%/day, 12+ days to the floor at ~$8/day). Every brake LEAST therefore carries a third
     term: **clk1 ≥ 10 AND roas_1d = 0.00 AND roas90 < 1.0 ⇒ step ≥ 15%**. One shared SQL fragment
     across all 3 bid arms and all 3 reason mirrors, so the step and the displayed % can never
     drift. Proven seats (roas90 ≥ 1.0) are exempt — a winner is paced 5%, never punished for one
     unsettled day (v27.47/v27.63). Deployed 2026-08-16: 4 rows deepened 5%→15%, 234 unchanged.
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

## v4 — the Portfolio absorbs the launch controller (Ori 2026-08-01)

"The launch controller cards should also be part of Out of budget or Portfolio 80/20 with the seat
mechanism. Format of Portfolio 80/20 should be the same as Out of budget (actions on the 3
hierarchies — campaign, keyword, search term/negate)."

- **Two sections only.** Out of budget owns every campaign capping (dark > 10%); the **Portfolio
  80/20 owns every healthy enabled campaign — ANY budget, both channels** (V_KEYWORD_LIFT v4
  dropped the budget > cap population filter). The launch-controller card section is retired from
  the Weekly Run page. Partition verified: 19 OOB + 89 Portfolio = 108 servable campaigns.
- **Seat mechanism everywhere:** slots = max(1, round(budget/$4)) in the Portfolio too — seats
  ranked proven (roas90/class, probes protected) → mid-tests by clicks → anchored candidates;
  tested losers (≥15 clk/90d, 0 orders) permanently park; beyond-seat rows PARK_WAIT $0.25;
  PROBE_START requires a free seat AND the 1–2-probe pace AND not capped.
- **Same grammar:** the Portfolio panel renders the OOB columns (item | dark | now $ | last day |
  prev-2d | CPC/target | action | → $ | apply | why) on three levels — campaign rows carry the
  launch controller's BUDGET engine output (V_LAUNCH_PHASE1 / V_SB_LAUNCH_CAMPAIGN suggestions;
  the launch controller lives on as the budget engine, its bid logic superseded by seats),
  keyword rows carry the seat/probe verdicts with last-day and prev-2d windows, term rows carry
  the two-window negates (V_OOB_SEARCH_TERM engine='LIFT').

## v5 — graduation budget rule + Brand defense section (Ori 2026-08-01)

- **Graduation budget fix (ONE-TIME, 2026-08-01):** campaign 7d net ROAS > 1.0 AND budget < $30
  → $31 (past both season caps). Ori: "this suppose to be one time bulksheet" — executed as a
  10-campaign bulksheet (8 SP + 2 SB, .tmp/budget_graduation_onetime_20260801.xlsx), NOT a
  standing rule. The engines' campaign-grain suggested_budget/budget_reason columns remain as
  NULL hooks for future budget logic; ongoing budgets run on the existing ladders.
- **Brand defense is its own section** (campaigns named '%Brand Defense%'): excluded from
  Out-of-budget and Portfolio displays. The moat doctrine enforced in data: defense keywords get
  action DEFENSE (never parked/probed by ROAS — the coacher defense mode owns bids, raising
  toward the $2 hard cap), and defense campaigns are excluded from V_OOB_SEARCH_TERM entirely
  (never negate brand terms in defense). The only lever on the panel is BUDGET (incl. the
  graduation rule). Partition: OOB (dark, non-defense) + Portfolio (healthy, non-defense) +
  Brand defense (all 8) = 108 servable.
- **2×2 layout (Ori 2026-08-01):** the two engine surfaces render split by budget tier —
  "Low budget — out of budget" (dark, ≤ cap) · "Portfolio 80/20 — out of budget" (dark, > cap) ·
  "Low budget" (healthy, ≤ cap) · "Portfolio 80/20" (healthy, > cap) · "Brand defense".
  Presentational only (tier prop on the panel components); engines unchanged. Partition verified
  15 + 4 + 61 + 20 + 8 = 108.

## v6 — Ori's tuning round (2026-08-01)

| knob | value |
|---|---|
| Loser allowance | **20% off-season / 40% peak** |
| Max probes per campaign | **2 off-season / 4 peak** |
| Dark ladder, working tier | STRONG ×1.5 @ prev-2d ≥ 1.5 AND today ≥ 1.2 · WEAK ×1.25 @ today ≥ 1.2 · CUT @ evidence (7d off / 3d peak) < 0.6 AND today < 0.6 → GREATEST(×0.8, floor) |
| Dark ladder, low tier | STRONG ×2 · WEAK ×1.5 (same conditions) · CUT @ prev-2d < 0.6 AND today < 0.6 → GREATEST(×0.8, floor) |
| Budget floor | **$10 off-season / $15 peak** |
| Healthy campaigns (all tiers) | ONE budget rule: W AND today both < 0.6 → −20% to the floor (raises belong to the dark ladder — a healthy campaign is not hitting its cap). Brand Defense EXCLUDED from the auto-cut (moat doctrine); flag to include. |
| Raise formulas | fixed multipliers (the budget ÷ %active projection retired) |

## v7 — negate bars on SQP market data (Ori 2026-08-01)

> "big word is a search term with more than 1000 sells for amazon in last 90 days [per SQP] and
> sqp have 90 days data on it and this campaign is at least 90 days old, and this campaign gave
> it ≥25 clicks of its own trial and this campaign have no sells then negate. if exist in sqp but
> do not has 90 days of data — wait. Small word — everything else: 15 clicks, 0 sales, 28 days."

- **BIG word** = the MARKET buys it: > **1,000 Amazon purchases in 90 days** per SQP
  (`FACT_SEARCH_QUERY.TOTAL_PURCHASES`, deduped per query-week), **and** SQP history on the term
  spans ≥ 90 days. Negate only when: campaign ≥ 90 days old AND ≥ 25 clicks of its own trial AND
  **this campaign** has no sales on the term (the account-wide-orders test is retired — a term
  converting elsewhere may still be negated here).
- **SQP-WAIT**: term exists in SQP with < 90 days of history → no negate of either kind until the
  market data matures (~1,790 term rows protected on day one).
- **SMALL word** (everything else, incl. terms Amazon never surfaces in SQP): **15 clicks**
  (raised from 10) · 0 sales · 28 days at this slice.
- Unchanged guards: term ≠ keyword · AUTO skips the same-word test · PT excluded · never in
  Brand Defense.
- First run: OOB 25 negates (9 big + 16 small) · Portfolio 29 (6 big + 23 small); sample big
  negate: 'gifts for 10 year old girl' — 5,949 market purchases/90d, 37 clicks here, 0 sales.

## v8 — seasonal revival + target-vs-bid reductions (Ori 2026-08-02)

Ori: "1. implement the seasonal revival rule 2. the out of budget methodology should catch dark
campaigns 3. if target < bid and net ROAS is marginal reduce slowly toward the target bid
4. if target < bid and net ROAS is loosing reduce to the target bid."

**Seasonal revival** (`seasonal_now`, both engines — `V_KEYWORD_LIFT` + `V_OOB_KEYWORD`):
- Signal: the keyword TEXT (account-wide) had **≥ 1 ad order in this same 28-day window last
  year** (364-day offset, the same `ly` CTE that anchors the personal target CPC). Auto clauses
  and product targets excluded. The window slides daily, so "christmas gift for girl" flips
  seasonal in late October automatically and flips back after the season.
- Effect: a `seasonal_now` keyword is **never permanent-parked as a tested loser** (the
  ≥15 clk/90d · 0-order park is gated `AND NOT seasonal_now`) and **jumps the candidate queue** —
  seat_rank and cand_rank order it right after the proven/converting keys, so it takes the next
  freed seat and probe slot. ACTIVATE/probe reasons carry a "SEASONAL REVIVAL" prefix.
- The `ly` CTE gate widened: `HAVING clicks >= 10 OR orders >= 1` — the CPC anchor (`ly_cpc`)
  still requires ≥ 10 LY clicks (quality), but a 4-click 2-order LY seller now revives.
- Current-season evidence still wins: a revived keyword that loses NOW can still hit the loser
  allowance PARK — LY signal opens the door, this year's clicks decide.

**Target-vs-bid reductions** (`V_KEYWORD_LIFT`, both arms — bid > target_cpc + $0.05):
- `MARGINAL` (0.7–1.1×): action **EASE_TO_TARGET** — glide `max(bid × 0.95, tcpc)` per day
  (slow reduction toward the target; the −5%/day grammar shared with OOB EASE).
- `LOSER` (inside the allowance): action **CUT_TO_TARGET** — suggested_bid = `tcpc` in one step.
- `WINNER`: untouched — established doctrine, real results own winning bids; the target
  only governs entries and raise ceilings, never pulls a winner down.
- Ordering: the allowance PARK still fires first for losers beyond the 20/40% pool; only the
  kept tail gets CUT_TO_TARGET. Both actions dedupe against the 1-day cooldown as usual.

**Dark campaigns** (directive 2 — no code change): a Portfolio campaign that goes dark > 10%
is already caught by the single-home rule — it moves to the Out-of-budget section next refresh
and the OOB ladder + seat model own its budget and bids until darkness clears.

## v9 — seasonal campaigns get their own home (Ori 2026-08-02)

Ori: "seasonal campaigns should be also separated (seasonal and seasonal out of budget); in
seasonal also show paused seasonal campaigns; other (paused not seasonal campaigns)."

**`is_seasonal` (campaign grain, both engine views — V_KEYWORD_LIFT + V_OOB_BUDGET_PHASE):**
name-based, mirroring `is_defense`:
`REGEXP_CONTAINS(LOWER(campaign_name), 'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday')`.
'prime'/'season' deliberately NOT matched (too ambiguous — archived 'jewelry prime' etc.).
Current live set: 6 enabled '(Back to School)' campaigns + 2 paused '(Boost, Easter 2026)'.

**Weekly Run sections (single home, priority defense > seasonal > tier):**
1–4. The 2×2 (Low budget / Portfolio 80/20 × out-of-budget / healthy) now EXCLUDES seasonal
   campaigns (`NOT is_seasonal`), as it already excludes defense.
5. Brand defense — unchanged; a campaign that is both defense and seasonal stays here (the moat
   outranks the season).
6. **Seasonal — out of budget** — enabled seasonal campaigns dark > 10%, full OOB grammar
   (budget ladder + seat model + negates), any tier.
7. **Seasonal** — enabled healthy seasonal campaigns, full Portfolio grammar (any tier), PLUS
   **paused seasonal campaigns** as display rows (name + PAUSED badge + budget + season note) so
   e.g. the Easter 2026 boosts stay visible for revival when their season nears. Paused rows are
   display-only — no bid/budget actions (nothing serves).
8. **Other — paused** — replaces the legacy SCALE/MARGIN/CUT coacher list, which by v8 contained
   EXACTLY the 44 paused campaigns (engines own every enabled+serving campaign, so only paused
   ones leaked through). Now explicitly: paused AND NOT seasonal, collapsed by default, keeps the
   manage (map/rename/pause) button and trailing 28d/net-per-day stats, sorted by net/day so
   profitable-when-paused revival candidates surface first.

Paused campaigns come from a new live-view cube `CampaignDim` on V_DIM_CAMPAIGN_CURRENT
(campaign_state / is_seasonal / is_defense flags; ARCHIVED excluded everywhere).
Keyword-grain `seasonal_now` (v8) is unchanged and independent — a seasonal KEYWORD can live in
any campaign; a seasonal CAMPAIGN is a homing/display concept.

## v10 — $1 seat-entry floor (Ori 2026-08-02)

Ori: "when starting a seat minimum bid should be 1 dollar (i wont move if not)."

Every seat-entry bid is floored at **$1.00** — below that the keyword simply doesn't move
(no impressions, the test never produces data):
- `V_KEYWORD_LIFT` PROBE_START: `min(max(coalesce(1.5×target, winners-avg-CPC, $1), $1), $2)`.
  The anchor REQUIREMENT is gone — a keyword with no LY target, no band cell and no winner CPC
  now enters at the $1 floor instead of never starting (this unfroze MINT-SP/EXACT,
  MINT-VIDEO/EXACT and FRESH-VIDEO/EXACT, which had $0 spend in-season because no probe could
  ever fire).
- `V_OOB_KEYWORD` ACTIVATE: `min(max(coalesce(1.5×target, per-seat affordable), $1), $1.50)`.
- The floor applies to ENTRIES only. Once clicks flow, the evidence-based reductions
  (probe -5%/day descent, EASE/CUT_TO_TARGET, TRIM, DARK_BRAKE) may go below $1 — real CPC
  data outranks the no-movement heuristic.

## v11 — 4-click trial gate on loser reductions (Ori 2026-08-02)

Trigger case: FRESH-SP/BROAD (Back to School), day 1 of spend ($3.10, 3 clicks). The 20%
loser allowance is spend-share math — on a newborn campaign the allowance is cents, so the
first 1–2 clicks blew through it and both spending keywords were PARKed while the only
0-click keyword got the probe. That contradicts "1 click do not break", the TRIM evidence
bar (>=4 clicks), and finish-what-you-started.

Rule (`V_KEYWORD_LIFT`, both arms): a LOSER can be **allowance-PARKed or CUT_TO_TARGET only
with >= 4 clicks in the window W** — the same evidence bar as TRIM. Under 4 clicks it is
KEEP_TAIL with reason "still in its 4-click trial (N clicks so far) — 1 click does not
break; keep gathering". The permanent park (15 clk/90d) and the probe verdict (20 clicks)
are unchanged — this gate only stops under-evidence in-window reductions.
Effect at deploy: 22 keywords portfolio-wide moved from PARK/CUT to in-trial KEEP_TAIL;
49 allowance parks and 5 cuts (all >= 4 clicks) stand.

## v12 — paused sections in the Seasonal grammar, historic-only (Ori 2026-08-02)

Ori: "other format should be like Seasonal but only with historic measures (last month, last
3 month, last year); also add Seasonal Paused and show only the performance of the relevant
season last year."

New view **`V_PAUSED_CAMPAIGN_HISTORY`** (cube `PausedHistory`, panel `PausedHistoryPhase`):
paused campaigns at (campaign, target) grain from FACT history + campaign rollup rows.
Display-only — nothing spends while paused, no actions, no apply buttons.

- **Seasonal Paused** (after Seasonal): paused seasonal campaigns, ONE column — the relevant
  season's most recent occurrence (name token → DIM_US_HOLIDAYS holiday; window
  pre_season_start → COALESCE(cooldown_end, holiday_date)). E.g. the Easter 2026 boosts show
  their actual Easter-2026 run (BOX-SP 639c · $574 · 0.71× · 17 ord; the keyword rows expose
  the revival candidates — "easter baskets for teens" 1.85×). Replaces the v9 inline ⏸ rows
  in the Seasonal section.
- **Other** (bottom, replaces the legacy SCALE/MARGIN/CUT list entirely): paused non-seasonal
  campaigns with last month · last 3 months · last year columns (clicks · spend · est. net
  ROAS via mapped-ASIN cost ratio). Population is now the FULL paused set from DIM (68), not
  the coacher table's 44 — campaigns with zero rows in T_WEEKLY_RUN_CAMPAIGN appear too.
  The ⋯ manage button of the legacy list is retired with it (mapping lives in Admin).

## v13 — season ramp: RAISE_TO_TARGET (Ori 2026-08-02)

The gap (Ori's "gift for girl" December example): a keyword ticking along at its June bid
($0.50) keeps that bid straight through December even when the LY-anchored target rises to
$1.20 — the target only caps raises and drives reductions. Strong winners get coacher raises
and parked/idle keywords re-enter via probes at 1.5x target, but the in-between keyword
(running, a few clicks, not strong) quietly starves through its own season.

Rule (`V_KEYWORD_LIFT`, both arms): **RAISE_TO_TARGET** when `seasonal_now` (its season is
arriving — LY same-window orders) AND class WINNER or MARGINAL (orders prove the season)
AND bid < 60% of the current target → glide UP `min(max(bid×1.10, bid+$0.05), target)` per
day. Never above target from this rule (beyond-target raises stay earned via the coacher);
losers excluded (they'd lose faster at higher CPCs — the probe path is their way back).
$0.50 → $1.20 takes ~10 days at this pace. Panel: emerald action, apply button queues the
raise. At deploy: 2 live ramps (both under-bid seasonal converters at $0.20–0.30 bids).

## v14 — probes compete for seats + seat status everywhere (Ori 2026-08-02)

Trigger (the "why are there 4 seats" case, ME-SP/PT B2 + VIDEO- BALL): in-flight Portfolio
probes were blanket-exempt from the OOB seat model ("probe in flight — hold"), so a 3-seat
campaign could carry 5 full bids while 70%+ dark, and the visible queue started at #3
because the probes silently occupied #1–#2.

Rule (`V_OOB_KEYWORD`): **a probe only keeps its bid while it holds a seat.**
- Seated probe (seat_rank ≤ slots): HOLD, untouched — "probe in flight — holds a seat until
  its 20-click verdict" (the Portfolio engine still owns the bid; no TRIM/DARK_BRAKE).
- Beyond-seat probe: **PARK_WAIT $0.25** like any mid-test — "probe pauses — beyond the seats
  while the campaign caps"; it resumes via ACTIVATE when a seat frees or darkness clears.
- A mid-probe keyword still never permanent-parks (tested_loser gated `AND NOT is_lift_probe`
  — the 20-click verdict outranks the 15-click bar).

**Seat status on every keyword row** (Ori: "for all tables add keyword seat status"): the
OOB, Portfolio (all tiers incl. Seasonal) and Brand-defense tables now show `seat i/M` (sky)
or `queue #k` (faint) on each keyword — OobKeyword cube gained slots/seatRank dims.
Paused-history tables excluded (no seats while paused).

## v15 — term winners must earn 1.1x (Ori 2026-08-02)

Trigger: asin="B09V45RH3Q" showed "1 winner" for a term with 3 orders at 0.84x net ROAS —
"winner" meant only "an order exists somewhere in 90d".

Rule (`V_OOB_SEARCH_TERM.is_winner`): a winning search term needs **>= 1.1x net ROAS at
this slice over 90d** — the same bar as the keyword WINNER class. SP terms use real
GROSS_PROFIT; SB terms estimate net via the campaign cost ratio (new prod CTE, same method
as the SB launch views). `net_roas_90d` exposed. The account-wide-orders arm is dropped
(an order elsewhere does not make THIS slice a winner). Negation is untouched — the negate
bars still key on 0 orders, so an ordered-but-under-1.1x term is neither winner nor negate:
it just keeps gathering. At deploy: 167 order-but-under-bar terms demoted.

**Winners hierarchy (same day):** keyword rows in the OOB and Portfolio tables carry a
collapsed "▸ N winners" toggle (emerald) — expanding lists the winning terms under that
keyword: term · kind · 90d clicks · orders · net ROAS, "earns >=1.1x net over 90d — never
negated". OobSearchTerm cube gained netRoas90d; the Portfolio panel fetches engine='LIFT'
is_winner terms alongside its negates. Display-only (winners have no action — they're the
evidence layer; e.g. a 7d-loser keyword showing 5 terms at 6-48x/90d reads very differently
than its class alone).

## v16 — keyword ROLE column (Ori 2026-08-02)

Ori: "add a role column — each keyword role in campaign like Funder, Candidate,…"

Both engine views expose `role` — the keyword's job in the campaign economy, one word,
derived from the same state as the actions (never contradicts them):

| role | meaning |
|---|---|
| FUNDER | winner/converter — pays for everything; never pulled down |
| WATCH | marginal earner (0.7–1.1x) — monitored, EASE/RAISE glides apply |
| PROBE | mid-test under the Portfolio's 20-click episode |
| CANDIDATE | next up — seated with a probe slot (Portfolio) / awaiting ACTIVATE (OOB) |
| TRIAL | gathering its 4-click trial — 1 click does not break |
| PARKED | allowance-parked loser (can return via seat queue) |
| RETIRED | tested loser (>= 15 clk/90d, 0 orders) — permanent, seasonal revival exempts |
| QUEUED | beyond the seats — waiting line |
| IDLE | seated but no probe slot free |
| DEFENSE | the moat (Portfolio arm only) |

Cubes KeywordLift/OobKeyword gained `role`; the OOB and Portfolio tables show it as a column
before `action` (colored: funder emerald · watch amber · probe/candidate sky · parked/retired
red · queued/idle faint). Portfolio mix at deploy: 196 QUEUED · 102 PROBE · 78 PARKED ·
51 FUNDER · 45 TRIAL · 41 IDLE · 30 RETIRED · 28 DEFENSE · 27 CANDIDATE · 21 WATCH.

### v16.1 — per-role logic (the full life of a keyword)

**FUNDER** — enter: net ROAS >= 1.1x with an order in W (Portfolio) / converting >= 1.0x on a
recent window or 90d-proven (OOB). Always seated first (converters ranked by 90d corrected
net ROAS — the winner is main). While healthy: KEEP — the target NEVER pulls it down; raises
are earned via the coacher sweet-spot (>= 2x on 1w, stepping toward $2, ceiling = personal LY
x1.5 else band); seasonal_now + bid < 60% of target -> RAISE_TO_TARGET +10%/day. While the
campaign caps: never raised (the budget raise buys volume) — winner-concentrated campaigns
EASE -5%/day toward real CPC, mixed campaigns FIT_CPC -15%/day (>= 4 clicks evidence).
Exit: stops converting -> WATCH -> TRIAL chain as windows roll.

**WATCH** — enter: MARGINAL, 0.7-1.1x (has orders). Seated by rank; KEEP by default.
Bid > target + $0.05 -> EASE_TO_TARGET (max(bid x0.95, target)/day). seasonal_now + bid
< 60% of target -> RAISE_TO_TARGET. Never parked (orders protect it).
Exit: >= 1.1x -> FUNDER · < 0.7x / orders dry -> TRIAL/PARKED chain.

**PROBE** — enter: PROBE_START applied (episode = last INCREASE_BID in the change log, 14d).
Owns its bid EVERYWHERE (coacher masks to KEEP; OOB defers while it holds a seat). During:
> 6 clicks/day with no sale -> -5%/day descent; verdict at 20 episode clicks: >= 1.0x ->
WINNER_FOUND -> FUNDER, else park $0.25 and the next candidate is promoted. While the
campaign caps it keeps its bid ONLY while seated — beyond the seats the probe pauses
(QUEUED, $0.25) and resumes via ACTIVATE. Never permanent-parked mid-test.

**CANDIDATE** — enter (Portfolio): IDLE + seated + a free probe slot inside the pace
(2 off-season / 4 peak active probes per campaign); cand_rank: seasonal_now first, then
target-anchored, then LY-click history. Enter (OOB): parked bid <= $0.30 holding a seat,
next in the ACTIVATE pace (max(1, floor(20% x budget / 4))/day — 80% of any raise keeps
feeding winners). Action: PROBE_START / ACTIVATE at max($1, min(1.5 x target, $2 / $1.50))
— the $1 floor; no anchor needed. Becomes PROBE the day the lift is applied.

**TRIAL** — enter: LOSER class still inside its evidence trial — under 4 clicks in W, or
within the loser allowance. KEEP_TAIL: keep gathering, 1 click does not break. With >= 4
clicks and bid > target + $0.05 -> CUT_TO_TARGET (straight to target, still seated).
Exit: converts -> WATCH/FUNDER · >= 4 clicks and the allowance burns -> PARKED ·
15 clicks/90d with 0 orders -> RETIRED.

**PARKED** — enter: LOSER with >= 4 clicks in W whose cumulative spend exceeds the loser
allowance (20% off / 40% peak of campaign W spend; best-first cum-sum keeps the best tail).
PARK $0.25 — temporary. Return: the seat queue (-> CANDIDATE -> PROBE when a seat frees);
seasonal_now jumps the queue.

**RETIRED** — enter: >= 15 clicks/90d with 0 orders AND NOT seasonal_now. Permanent park
$0.25; its seat goes to the next candidate. Only two ways back: seasonal revival (an LY
order enters the sliding same-28d window) or the 90d click window decaying under 15.

**QUEUED** — enter: seat_rank > slots (slots = max(1, round(budget / $4))). PARK_WAIT $0.25
— the test pauses, not dies. Includes paused probes while the campaign caps. Exit: a seat
frees (funder retires, budget raise adds slots, probe verdict lands) -> ACTIVATE at the
paced rate -> CANDIDATE.

**IDLE** — seated but the probe pace is exhausted (all 2/4 slots busy). No action; first in
line when a probe verdict lands.

**DEFENSE** — campaign name '%brand defense%'. The moat: never ROAS-parked, never negated,
bids run on the coacher defense mode (to $2); budget is the only Weekly Run lever.

Cross-cutting: dark > 10% moves the whole campaign to OOB ownership (launch/Portfolio views
defer); the negate layer works at TERM grain independent of keyword roles (winners >= 1.1x
never negated); every bid entry respects the $1 seat floor; every reduction needs evidence
(4 clicks) except the probe's own descent.

### v16.2 — role definition fixes + hover tooltips (Ori 2026-08-02)

Ori: "in OOB there is no funders only Winner (winner is net roas >= 1.0 for the last 3 days),
always seated first. FUNDER — the window is 28 days. Add tooltips to roles."

- **OOB role WINNER** (replaces FUNDER there): net ROAS >= 1.0 over the LAST 3 DAYS
  (`converting` = >= 1.0 on the last-day or prev-2d window) — always seated first.
  90d-proven but cold in the last 3 days -> **WATCH** (holds its seat, monitored).
- **Portfolio FUNDER is judged on 28 DAYS**: net ROAS >= 1.1 over the combined 7d + 8-28d
  windows — a stable financier, not a hot week. W-window earners (WINNER/MARGINAL class)
  that are not funder-grade on 28d -> WATCH. Actions stay class-driven (W window) — a role
  FUNDER with action `cut to target` is exactly the tension the column exists to surface.
- Every role cell now carries a hover tooltip with its full logic (per engine — the OOB and
  Portfolio texts differ where the definitions differ).
Mix after the fix: Portfolio 60 FUNDER / 33 WATCH (was 51/21); OOB 22 WINNER / 15 WATCH.

## v17 — cost-aware seats (Ori 2026-08-02)

Trigger (ME-SP/PT B2): $10 budget -> 3 seats by the flat budget/$4 math, but seat 1 is a
WINNER bidding $1.56 whose 4-click day costs $6.24 — the third seat was phantom money
(its keyword sat at $0 spend).

Rule (both engines): **the $4 seat assumes $1 clicks — winners pay for their real seat.**
`slots = max(1, round((budget − winner_premium) / 4))` where winner_premium =
SUM over WINNER/converting keywords of `max(0, 4 × (bid − $1))`. B2: (10 − 2.24)/4 = **2
seats** — the winner + one; everything else queues. "After a few sales the budget will
increase" — that's the existing budget ladder (STRONG/WEAK raises on the ROAS windows):
sales -> budget raise -> the premium is absorbed and the seats come back. seat_cpc uses the
same corrected slot count. At deploy: 5 Portfolio campaigns lost 8 phantom seats.

## v18 — SB negatives carry their Ad Group Id (upload report 29, Ori 2026-08-02)

Amazon rejected 9 of 158 rows: SB Negative Keyword Create requires an **Ad Group Id**
(SB has no campaign-level negatives), and the negate pipeline never carried one.

Fix end-to-end: `V_OOB_SEARCH_TERM` exposes `ad_group_ids` (STRING_AGG of the ad groups the
term actually RAN in under that keyword, both arms — grain unchanged so the negate bars are
untouched); cube dim `adGroupIds`; the panels' queueNeg fans out **one queue item per ad
group** (SP with empty id still falls back to Campaign Negative Keyword). A multi-ad-group
SB campaign (BOX-SBS By Age, 12 ad groups) negates the term in every ad group where it
fired. One-time repair: the 9 rejected terms were re-issued as 17 rows with real ad-group
ids (sb_negatives_reupload.xlsx, delivered for manual upload).

## v19 — in-season campaigns probe every seat (Ori 2026-08-02)

Trigger (MINT-VIDEO/EXACT BTS): a keyword held seat 3/3 but sat IDLE "waiting for a probe
slot" — the off-season probe pace (2) throttled a seasonal campaign in the middle of its own
season. Two compounding causes: (1) `in_peak` only fires for gift_season/prime_event, so
category back_to_school never gets the 4-probe peak pace; (2) budget seats and probe pace
are separate throttles, and for a short seasonal window the pace throttle is pure waste.

Rule (`V_KEYWORD_LIFT`): a campaign gets `season_active` (its OWN holiday's window is
running: pre_season_start -> cooldown_end, name-token -> DIM_US_HOLIDAYS map). When
`is_seasonal AND season_active`, the probe cap becomes **the seat count** — every funded
seat may probe at once (each at the $1 entry floor); the budget already caps the risk.
Evergreen campaigns keep the 2 off / 4 peak pace. At deploy: MINT-VIDEO 3/3, MINT-SP/EXACT
3/3, FRESH-VIDEO 3/3 probing (FRESH-SP arms hold funder/trial seats; MINT-SP/BROAD is
capped -> OOB owns it); zero non-seasonal campaigns exceed pace 2.

(Also this session: the retired coacher list's "Not applied / action" chips removed from
Weekly Run — they counted suggestions with no surface and misread as un-applied uploads.)

### v19.1 — funder needs evidence + one-time $1 seasonal bid floor (Ori 2026-08-02)
- FUNDER requires **>= 4 clicks over the 28d** on top of the 1.1x bar ("only 1 click can't
  be funder") — a 1-click 4.5x keyword is WATCH until it has evidence. 60 -> 57 funders.
- ONE-TIME bulksheet (NOT a standing rule, like the $31 graduation sheet): the 18 seated
  keywords in the 6 in-season BTS campaigns bid $0.75-0.88 — under the $1 won't-move line —
  lifted to $1.00 (12 SP + 6 SB rows, seasonal_bid_floor_1usd.xlsx delivered). Parked/queued
  rows stay at $0.25; probes already enter at the $1 floor.

### v19.2 — manual bid entry (Ori 2026-08-02)

Every keyword row's "→ $" cell in the OOB and Portfolio tables is now clickable: it opens an
inline input (prefilled with the suggestion, else the current bid, else $1), **Enter queues
the bid** (Esc/blur cancels; min $0.02). The queued item carries source='MANUAL' and shows
as "$X.XX ✎" in the cell; re-entering replaces the previous item. Manual items ride the same
DO-queue -> bulksheet -> change-log path as engine suggestions, so cooldowns and the applied
state treat them identically. The ✓ queue-toggle shows on any row with a queued item — engine
OR manual — so a hand-set bid can be reviewed and un-queued like any suggestion. The
section-level "✓ applied N" unapply ALSO clears manual bids scoped to that section's
campaigns (sections are disjoint, so campaign scope is exact).

## v20 — Seasonal split by tier (Ori 2026-08-02)

"Separate seasonal to seasonal low budget and seasonal": the healthy Seasonal section splits
like the evergreen 2x2 — **Seasonal low budget** (budget <= the low cap, $20 off / $30 peak)
and **Seasonal** (working tier above it). Seasonal — out of budget stays one section (any
tier). Layout is now: 2x2 evergreen + Brand defense + Seasonal-OOB + Seasonal low budget +
Seasonal + Seasonal Paused + Other. All six BTS campaigns sit in Seasonal low budget today;
the working tier fills as the budget ladder graduates them. (Also fixed: the "N winners
found" header counter is now scoped to the section's campaigns.)

## v21 — low-budget tiers read at launch cadence (Ori 2026-08-02)

"Seasonal low budget, Low budget should be based on 1 day and prev 2 days like out of budget
format": the two low-budget Portfolio sections now show **last day** and **prev-2d** window
columns (the OOB grammar) instead of 7d / 8-28d — a $10 campaign's story changes daily, not
weekly. The working tiers (Portfolio 80/20, Seasonal) keep 7d / 8-28d. V_KEYWORD_LIFT gained
keyword-grain clicks_1d/roas_1d/clicks_prev2/roas_prev2 + campaign rollups (camp_clicks_1d/
camp_roas_1d/camp_clicks_prev2/camp_roas_prev2), both arms; KeywordLift cube exposes them.
DISPLAY-ONLY: the engine's classes/actions still run on W and 28d — the columns changed, not
the judgment windows.

## v22 — research mode + honest seasonal (Ori 2026-08-02, "build it")

**Seasonal concentration** (replaces v8's one-order bar; both engines): `seasonal_now` now
requires **>= 2 LY same-28d-window orders AND >= 25% of the keyword's LY-YEAR orders in the
window AND first LY activity >= 30 days before the window** (launch-artifact guard — a
keyword born inside the window has 100% share by construction). 74 -> 20 seasonal keywords;
the 1-order badges ("9 year old girl birthday gifts", 1 of 6) are gone; survivors have real
measured concentration. ly CTEs widened to the full LY year (728-364d) with window-scoped
ly_cpc; thresholds (2 / 25% / 421d) are tunable.

**Research mode** (formalizes Ori's manual play: "added new broad keywords based on winners
+ reduce bids of existing"): `is_research` = campaign name matches hunter|discovery|research.
- Losers beyond the allowance -> **RESEARCH_EASE** (glide -15%/day, floor $0.30) instead of
  PARK $0.25 — the antenna stays alive; role **ANTENNA** (violet). Tested-loser permanent
  park (15 clk/90d, 0 orders) unchanged even in research.
- **ADD_KEYWORD suggestions**: V_OOB_SEARCH_TERM.is_add_candidate — a winning term (>= 1.1x
  /90d) in a research campaign with NO enabled keyword of its own (SP DIM_KEYWORD + SB
  sb_keyword anti-join by equality; ASINs excluded). 1,274 candidates at deploy (best 188x).
  Panel: "+ broad" button on orphan winner rows queues ADD_KEYWORD (broad, $1 entry floor,
  the term's own ad group); DoPage exports Keyword Create rows on the matching SP/SB sheet.
- Campaign header shows "· research"; role tooltip explains ANTENNA.

## v23 — auto-campaign doctrine (Ori 2026-08-02)

Ori: "in automatic campaigns no need to park — it is always 4 groups; purpose is to negate
not-good search terms, reduce bid for not-performing keywords and increase bids when
performance is good; targets are less good here because it is general."

Auto clauses (close/loose-match, substitutes, complements) are 4 FIXED antennae — there is
no bench behind them, so parking one just kills a quarter of the discovery surface. Both
engines now treat `is_auto` rows accordingly:
- **Never PARK / PARK_WAIT / RETIRED / QUEUED / probe-started.** Failed probe verdicts on
  autos TRIM instead of park (in-flight legacy probes finish their episodes untouched).
- **AUTO_TRIM** (Portfolio): LOSER clause with >= 4 clicks in W -> -15%/day, floor $0.30 —
  "reduce bid for not performing". Under 4 clicks: KEEP_TAIL (1 click does not break).
- **Raises stay earned**: winners KEEP; the coacher sweet-spot owns increases.
- **Targets advisory**: autos excluded from EASE/CUT/RAISE_TO_TARGET (the clause is general —
  a per-term target does not describe it). While capped, OOB TRIM_BID/DARK_BRAKE still apply
  (evidence-gated reductions ARE the auto lever).
- **Negation is the primary lever** — unchanged: auto terms flow through the negate layer
  (AUTO skips the term!=keyword test) and the winners hierarchy shows harvest material.
- Roles for autos: FUNDER / WATCH / TRIAL / IDLE (+PROBE for legacy in-flight); seat badges
  hidden on auto rows (seat mechanics do not apply to a fixed 4).
23 AUTO_TRIMs live at deploy; 0 auto parks/queues/retires in either engine.

## v24 — the Auto section (Ori 2026-08-02)

"Separate auto campaigns. It should be above Low budget — out of budget, and window should be
last 7 days, 8-28 days (in peak 3 days and 4-14 days)."

- **`is_auto_campaign`** (data-truth, both campaign-grain views): the campaign's current
  config contains an enabled auto clause (close/loose-match, substitutes, complements) —
  no name regex needed; Amazon autos are structurally pure.
- **One home, first on the page**: the Auto section (KeywordLiftPhase tier=AUTO) sits ABOVE
  Low budget — out of budget and holds ALL 19 auto campaigns — dark or healthy (the OOB
  sections exclude autos; the 2x2 and seasonal tiers exclude autos). v23's auto doctrine
  runs inside it: AUTO_TRIM / KEEP / negate, never park.
- **Windows**: off-season last 7d + 8-28d; in peak **last 3d + 4-14d** (new keyword-grain
  clicks_3d/roas_3d/clicks_4_14/roas_4_14 + campaign rollups in V_KEYWORD_LIFT, both arms).
- Partition after: 19 auto + 15 lowOOB + 4 portOOB + 38 low + 18 port + 8 defense +
  1 seasonalOOB + 5 seasonalLow + 0 seasonal = 108.

### v24.1 — no probe semantics on autos at all (Ori 2026-08-02, "why is it probe?")

The probe framework treats ANY logged INCREASE_BID within 14 days as an episode. The old
click-rate controller's +5% PROBE raises (Jul 22/25) had therefore left 33 auto clauses
across 15 campaigns labeled role PROBE — some with phantom "episodes" at 170/20 clicks.
Fix: `probing` / `probe_done` are gated `AND NOT is_auto` in both arms — a bid increase on
an auto clause is just a raise. Auto clauses now always resolve through the v23 doctrine
(AUTO_TRIM / KEEP_TAIL / KEEP / IDLE, roles FUNDER/WATCH/TRIAL/IDLE); 0 probe artifacts
remain. 27 AUTO_TRIMs, 20 keep-tails live.

### v24.2 — auto trim floor $0.20 (Ori 2026-08-02, "make minimum 0.2")

AUTO_TRIM floor lowered $0.30 -> **$0.20** (matching the OOB engine's bid_min), gate
lowered > $0.35 -> **> $0.25** so every step is still genuinely downward (0.85 x $0.26 =
$0.22 >= floor). Research-mode RESEARCH_EASE keeps its $0.30 floor (antennae stay a notch
warmer). 27 -> 32 AUTO_TRIMs; zero upward, zero below-floor.

### v24.3 — honest labels for evidence-complete floored autos (Ori: "why research if there was 19c")

An auto LOSER with >= 4 clicks whose bid already sits at/below the $0.25 trim gate was
falling into the "4-click trial — keep gathering" fall-through — a lie for a clause with 19
clicks of verdict. Now: reason = "evidence in — N clicks this window with no profit and the
bid already at the floor: negate its bad terms, nothing left to trim"; role = **ANTENNA**
(alive cheap, its terms are the information). The ANTENNA tooltip now covers both research
keywords (seed new broads) and floored auto clauses (feed the negate layer). TRIAL is
reserved for genuinely under-4-click clauses.

### v24.4 — AUTO_RAISE: the third auto lever (Ori: "why is this not raised")

The auto doctrine's raise lever is now in the section itself: an auto WINNER clause
(>= 1.1x with an order in W) with **>= 4 clicks of evidence**, in a **not-capped** campaign,
below the $2 cap -> **AUTO_RAISE +15%/day toward $2**. While capped the budget raise stays
the only lever (never bid up into darkness). Trigger row: ME-SP/AUTO (Purple) substitutes,
14.43x on 8 clicks at $0.28 -> $0.32. 5 raises live at deploy; invariants clean (none
capped, none under-evidenced, none above cap, all genuinely upward).

### v24.5 — dark autos must raise or trim (Ori: "if dark% > 0 then must be a raise or trim")

Dark autos lost the OOB ladder + dark-brake when they moved into the Auto section (v24) —
a 49%-dark campaign read "hold — split healthy". Restored inside the Auto section:
- **Dark-auto budget ladder** (campaign grain, in V_KEYWORD_LIFT): capped auto campaigns get
  the OOB ladder — STRONG x2/x1.5 @ today >= 1.2 AND prev-2d >= 1.5 · WEAK x1.5/x1.25 @
  today >= 1.2 · CUT x0.8 (floor $10/$15) @ both windows < 0.6. (No day-throttle here —
  the 1-day change-log cooldown still applies at apply time.)
- **AUTO_BRAKE**: capped + clicked-yesterday non-winner clause -> step max(5%, 30% x dark)/day,
  floor $0.20.
- **AUTO_FIT**: capped WINNER clause with >= 4 clicks yesterday and bid > real CPC + $0.05 ->
  fit -5%/day toward the real CPC (never raise while dark).
- Panel fallback for dark campaigns without a budget move now says "dark N% · mixed windows"
  instead of "split healthy".
Result: 11/12 capped autos act. The honest residue (BOX-SP/AUTO Pink): winner already bid
BELOW its real CPC ($0.58 vs $0.62), second winner at 1 click, losers floored at $0.25 —
every move is evidence-blocked; the market is already braking it.

## v25 — the 30-click weekly decision floor + VOLUME_LIFT (Ori 2026-08-03)

Ori (ME-VIDEO/EXACT tween-girl case, 8 clicks/wk): "8 clicks a week is not enough to decide
something. We need at least 30 clicks a week. In this case we should lift the bid."

- **Decision floor**: the WINDOW-based reductions (allowance PARK, CUT_TO_TARGET,
  EASE_TO_TARGET) require the CAMPAIGN to have **>= 30 clicks in the last 7 days** — under
  that, weekly classes are noise and no window verdict fires. Keyword-grain ACCUMULATED
  evidence still decides regardless of weekly volume: the 15-click/90d permanent park and
  20-click probe verdicts stand (a 46-click/90d tested loser IS a decision).
- **VOLUME_LIFT**: in an under-floor campaign (not capped, not auto, not defense), every
  SEATED non-probing keyword bidding below the entry anchor (max($1, min(1.5x target, $2)))
  lifts TO the anchor — buy decision-grade traffic. The lift starts a normal 20-click
  episode, so the data it buys resolves into real verdicts. Keywords already at/above the
  anchor hold with the honest reason "under the 30-click/week decision floor (Nc/7d)".
- 29 VOLUME_LIFTs at deploy; zero invalid (none capped/auto/downward/above $2).

## v26 — CUT_TO_BREAKEVEN: economics name the bid (Ori 2026-08-03)

Ori (BUNNY-VIDEO case): "those keywords are not [weekly] losers — last 28 days they have
more than 30 clicks and net ROAS is poor. Reduce bids by the rate of clicks per sale: if 30
clicks create one sale and margin is $3, the bid should be 3/30."

margin-per-sale ÷ clicks-per-sale = **28d net profit ÷ 28d clicks** — the realized value of
one click. Rule (`V_KEYWORD_LIFT`, both arms): a non-WINNER keyword (not auto/defense) with
**>= 30 clicks over 28d** and 28d net ROAS < 1.0, bidding above its profit-per-click ->
**CUT_TO_BREAKEVEN** = max(gp28/clk28, $0.02). Keyword-grain 28d evidence outranks the
weekly volume floor (such keywords are EXCLUDED from VOLUME_LIFT — they need their verdict,
not more traffic) and outranks research ease. Zero-sale 30+click keywords compute to the
$0.02 floor — economics' version of a park (the 15clk/90d permanent park still follows).
49 cuts at deploy; invariants clean (all downward, none under $0.02, all >= 30 clicks).

### v26.1 — breakeven cut is the aggressive lever (Ori 2026-08-03)

Ori: "zero-sale cases go to the standard $0.25 queue-park; this should be fired only when
>= 30 clicks over 28 days AND ads net ROAS < 0.4 — this is an aggressive change."

- Bar tightened: CUT_TO_BREAKEVEN requires 28d net ROAS **< 0.4x** (was < 1.0) — reserved
  for clearly-bleeding keywords; 49 -> 12 cuts.
- Zero-profit split: >= 30 clicks/28d with **no net profit** -> standard **PARK $0.25**
  (the seat queue owns any comeback), not a $0.02 economic corpse; keywords WITH profit cut
  to their true profit-per-click (floor $0.02 stays for tiny-margin sellers).

## v27 — Auto splits by tier: Auto low budget / Auto (Ori 2026-08-04)

Ori: "lets split auto to auto low budget, Auto."

Same tier split every other section already has, applied to autos. Display-only —
`KeywordLiftPhase` gains tier `AUTO_LOW`:

- **Auto low budget** = auto campaigns with budget <= the low cap ($20 off-peak / $30 peak).
- **Auto** = auto campaigns above the cap.
- Render order: Auto low budget, then Auto — both above Low budget — out of budget
  (autos keep first position on the page).
- Everything else about the auto doctrine is unchanged and shared by both tiers: 4 fixed
  clauses, never park/probe/queue, 7d/8-28d windows (3d/4-14d in peak), AUTO_TRIM /
  AUTO_RAISE / AUTO_BRAKE / AUTO_FIT + search-term negates, dark-auto budget ladder.
- No view/cube change — the split reads the existing `budget` + `is_auto_campaign`
  dimensions. Partition at deploy: 10 + 9 = the same 19 autos, single-home preserved.

### v27.1 — manual budget override (Ori 2026-08-04)

Ori: "add an option to change budget manually as well."

The manual-bid pattern, applied to campaign budgets — both `KeywordLiftPhase` and
`OobBudgetPhase`:

- The budget $ cell on every campaign row is clickable — input opens, Enter queues a
  BUDGET_CHANGE with `source: 'MANUAL'` (floor $1, Amazon's minimum), Esc/blur cancels.
- Works on **hold** rows too: a manual budget bypasses the suggestion gate, so any
  campaign can take a hand-set budget, not just ones the engine flagged.
- Queued manual budgets display as `$X ✎`; the ✓ button appears whenever a budget item
  is queued (suggested or manual) and unqueues it.
- Re-editing replaces the queued item (one budget row per campaign).
- Section unapply clears MANUAL budgets along with MANUAL bids (campaign-scoped sweep
  now covers BUDGET_CHANGE).

### v27.2 — Auto low budget reads at launch cadence (Ori 2026-08-04)

Ori: "auto low budget time window should be 1 day and 2-3 days."

Same display cadence the other low-budget tiers got in v21: the **Auto low budget**
section shows **last day + prev-2d** (days 2-3) instead of 7d/8-28d — small budgets
move daily, so the table should read at daily grain. Applies in peak too (the 3d/4-14d
peak pair now belongs to the big-budget Auto section only). Display-only — the engine's
AUTO_TRIM/AUTO_RAISE/AUTO_BRAKE/AUTO_FIT decisions still run on the W windows.

### v27.3 — AUTO_NUDGE: feed the starving converter (Ori 2026-08-04)

Ori (BUNNY Brave close-match — 1c 5.93x yesterday, 24c 0.24x/7d, would-be AUTO_TRIM):
"the problem in this scenario: last days' clicks are very low — if you trim it, it will
be stuck. It is better to increase 5% the one that converted."

At starving click rates the trim compounds into silence: a lower bid buys fewer
impressions, the weekly window never accumulates new evidence, the clause trims again —
stuck. So on LOW-VOLUME auto clauses, a recent conversion outranks the weekly loser class:

- **AUTO_NUDGE** (`V_KEYWORD_LIFT`, both arms, before AUTO_TRIM): auto clause, class
  LOSER, **4 <= W clicks < 30** (under the 30-click weekly decision floor — the same bar
  that gates other weekly reductions), **not capped**, **converted in the last 3 days**
  (gp1 > 0 OR gp3 > 0 — the sale must be net-profitable), bid < $2
  -> bid x 1.05/day, cap $2. Reason: "converted in the last 3 days on starving clicks
  (Nc this window, under the 30-click floor) — a trim would freeze it: nudge +5%/day so
  the sale can prove itself".
- AUTO_TRIM still owns: starving clauses that did NOT convert recently, and >=30-click
  clauses whose week is decided (enough volume for the trim verdict to be honest).
- Capped campaigns keep AUTO_BRAKE priority — never nudge into dark.
- At deploy: 2 nudges (BUNNY Brave close-match $0.71->$0.75, BUNNY Birthday close-match
  $0.52->$0.55), invariants clean (all 4-29 clicks, uncapped, upward, <= $2).

### v27.4 — APPLIED_HOLD: one ladder step per day, survive the sync lag (Ori 2026-08-04)

Ori: "I already applied and approved this today — why is it shown again?"

Bulksheet uploads land in FACT_PPC_CHANGE_LOG immediately, but the config mirrors
(DIM_KEYWORD / sb config) lag Fivetran by 1-2 days. The engine kept reading the STALE bid
and re-derived the same daily-ladder step — inviting a double-apply (-15% on top of -15%).

Fix (`V_KEYWORD_LIFT`, wrapper over both arms): a row whose last logged change is within
48h shows **APPLIED_HOLD** (suggested_bid NULL, reason "applied $X at <ts> — step done;
suggestions resume when the new bid syncs from Amazon") when EITHER:
- the change was applied **today** (one ladder step per day, even if already synced), OR
- the applied value has **not reached the config yet** (bid mismatch > half a cent).

Same overlay for campaign budgets: applied BUDGET_CHANGE within 48h -> suggested_budget
NULL, budget_reason "budget applied $X at <ts> — waiting for Amazon sync". Held rows drop
out of "apply all N" automatically (no suggested value). Once Fivetran syncs, the ladder
resumes FROM the new bid — each day's step is a genuine next step.
At deploy: 17 bid holds (exactly the 00:58 upload) + today's budget moves held; 0 invalid.
Known gap: V_OOB_KEYWORD / V_OOB_BUDGET_PHASE don't have the overlay yet.

### v27.5 — low-budget autos react daily (Ori 2026-08-04)

Ori (BOTTLE-SP/AUTO): "in auto low budget you should focus on short term windows (prev
day, 2-3 prev days) and react base on it. In this case you should raise the bid a bit for
complements, close-match. Trim a bit loose-match."

Small-budget autos live day to day — the weekly windows react too slowly. New day rules
(`V_KEYWORD_LIFT`, both arms, campaign budget <= low cap $20/$30 peak), which OUTRANK the
weekly auto rules and the capped mechanics (the budget ladder owns the cap; the bid
follows yesterday):

- **AUTO_DAY_RAISE**: >= 3 clicks yesterday AND net-profitable AFTER ad spend
  (gp1 > sp1 — 0.53x "conversions" don't count) -> +5%/day, cap $2.
- **AUTO_DAY_TRIM**: no profit yesterday AND no profit prev-2d, >= 10 combined clicks
  -> -5%/day, floor $0.20. A conversion in EITHER window blocks the trim (the
  substitutes case: dead yesterday but 11x in prev-2d -> hold).
- Neither fires -> fall through to the weekly auto doctrine (trim/raise/nudge/fit/brake).
- Steps are deliberately half the weekly ladder (5% vs 15%) — daily windows are noisy,
  so daily steps are small; APPLIED_HOLD (v27.4) enforces one step per day.

BOTTLE at deploy = the directive verbatim: complements $0.55->$0.58, close-match
$0.26->$0.27 (raises), loose-match $0.24->$0.23 (trim), substitutes KEEP (prev-2d 11.44x
blocks). 2 raises + 10 trims fleet-wide; invariants clean (0 non-auto, 0 over-budget-cap,
0 wrong-direction, 0 raises under 1.0x).

### v27.4.1 — applied-hold fixes (Ori 2026-08-04, "can't see the recommendation")

- Budget-hold sync test compared the applied budget against the DISPLAY-ROUNDED budget
  ($14 vs $14.02 -> false "not synced", suggestion suppressed up to 48h after the value
  had already synced). Tolerance widened to $0.51 (covers the $1 rounding).
- The campaign "why" cell never showed the view's budget_reason — held rows displayed a
  bare "hold —" with no explanation. Cell now prefers: active suggestion reason ->
  view budget_reason (incl. "budget applied $X — waiting for Amazon sync") -> legacy map
  -> generic fallbacks.

### v27.5.1 — dark-auto terms come home + trim states its evidence (Ori 2026-08-04)

Ori: "why this do not have auto nudge" (Brave loose-match) + "can't see in auto low
budget any negate terms".

- **Nudge question**: working as designed — loose-match has 37 clicks this week (over
  the 30-click floor): the week is FULL evidence, 0.64x earns the honest trim; the nudge
  only protects starving clauses (4-29 clicks). But the AUTO_LOW display shows 1d/prev-2d
  only, so the AUTO_TRIM reason now states its weekly basis: "37 clicks at 0.64x this
  week (full evidence, over the 30-click floor): trim -15%/day".
- **Negates were orphaned**: dark auto campaigns' terms carry engine='OOB'
  (V_OOB_SEARCH_TERM population rule), but v24 evicted autos from the OOB sections and
  the Auto panels fetched engine='LIFT' only — 8 negates (+ dark-auto winners) had no
  home. Both KeywordLiftPhase term fetches now read engine IN (LIFT, OOB); campIds
  scoping keeps non-auto dark campaigns in their OOB sections. Auto low budget 0 -> 3
  negates, Auto 1 -> 6 at deploy.

### v27.6 — Auto low budget: the 7-day window is gone entirely (Ori 2026-08-04)

Ori (on the Brave loose-match weekly-trim explanation): "this should be based on prev
day" + "make sure auto low budget is not using 7 days window at all."

Low-budget autos are now governed by the day windows ALONE — no weekly rule can touch
them (`V_KEYWORD_LIFT`, both arms, budget <= low cap):

- **AUTO_DAY_RAISE**: yesterday net-profitable after spend (gp1 > sp1), ANY click count
  (was >= 3 — the 1-click 5.93x day now raises, per the original nudge directive) -> +5%.
- **AUTO_DAY_TRIM**: no profit yesterday AND prev-2d, >= 10 combined clicks -> -5%.
- Everything else HOLDS with a day-based reason: "sold yesterday under spend (0.53x) —
  not a raise, not a cut" / "sold in prev-2d (11.44x) — day windows mixed, tomorrow
  decides" / "N clicks over 3d, no sales, under the 10-click day bar" / "quiet".
- Weekly AUTO_RAISE / AUTO_NUDGE / AUTO_TRIM and the class-driven capped mechanics
  AUTO_FIT / AUTO_BRAKE are gated to budget > cap (big autos keep the v23/v24 doctrine;
  AUTO_NUDGE lives on there for starving 4-29-click clauses).
- Panel: the weekly class chip (winner/loser) is hidden on AUTO_LOW rows — it was the
  last 7d artifact in the section.
Invariants at deploy: 0 weekly actions and 0 weekly reason texts on low autos; 4 day
raises + 10 day trims; BOTTLE spec rows unchanged.

## v27.7 — ALL low-budget tiers decide on last day + prev-2d (Ori 2026-08-04)

Ori: "make sure all low budget types time window is based on last day and 2-3 days
(including the decision logic)."

The OOB sections already complied (1d/prev-2d budget ladder, 3-day winners, 1-day trims,
90d evidence). The gap was `V_KEYWORD_LIFT`'s LOW / SEASONAL_LOW tiers — classes and the
80/20 allowance ran on the weekly window. Fix = **W-rebase at the `base` layer**: for
campaigns with budget <= the low cap (not defense), W IS 3 DAYS (last day + days 2-3) —
`clk_w/sp_w/ord_w/roas_w/gp_w` swap to the 3d columns (new `ord3` in both kwW arms), so
class, the 20% loser allowance, seat economics (win_cpc), loser share, EASE/CUT/RAISE_TO_
TARGET and the 4-click trial gate ALL inherit the short window with zero duplicated logic.

- Weekly camp floor (30 clicks/7d) exempts low campaigns; the under-floor trigger
  (VOLUME_LIFT + honest holds) pro-rates to **13 clicks/3d**; floor texts say which.
- Winner reasons name the true window ("1.71x over 3d — funds the campaign").
- Big-budget tiers (budget > cap): nothing changes — every decision still weekly.
- Keyword-grain accumulation evidence stays at its own grain by design: 90d proven/parks,
  probe episodes (click-count), CUT_TO_BREAKEVEN 28d — those are not "the weekly window".
- Panel: fast tiers' campaign meta reads "spent $X/3d".
Invariants at deploy: 291 low rows all have clicks_w == 1d + prev-2d; 263 big rows all
still 7d; 0 weekly reason texts on low rows; machinery intact (38 window reductions,
19 VOLUME_LIFTs, parks/probes/queues normal).

### v27.8 — dark with no raise coming: bids own the dark (Ori 2026-08-04)

Ori (VIDEO- BALL SB, launch, $10 floor): "this campaign has 72% dark but there is no bid
trim."

The hole: every hold in the seat model leaned on "the budget raise is the lever while
capping" — but nothing checked whether a raise was actually coming. VIDEO- BALL: budget
verdict CUT at the $10 floor (both windows under 0.6x), converting seats + probe all
HOLD -> 72% dark, 102% spend, nothing moves. Dark must produce a raise or a trim.

Fix (`V_OOB_KEYWORD`, all 3 CASEs, ahead of the probe/converting/proven exemptions):
**campaign dark > 10% AND yesterday blended net ROAS under the ladder's 1.2x raise gate**
(c_roas1 — the exact budget-ladder input) -> every keyword that clicked UNPROFITABLY
yesterday (clk1 >= 1, roas_1d < 1.0) DARK_BRAKEs max(5%, 30% x dark)/day toward $0.20 —
including 3d-converting seats with a dead yesterday and IN-FLIGHT PROBES (a probe stops
hiding behind its verdict when the campaign is drowning). Exempt: 90d-proven seats
(winners never pulled down), keywords that PAID yesterday (roas_1d >= 1), no-click
keywords (their bid did not eat the budget).

VIDEO- BALL at deploy: tween girl $0.70->$0.55 (8c 0.00x), probe $1.03->$0.81,
gift-for-girls 1.58x holds. Fleet: 28 brakes; 0 wrong-direction / no-click / paying.
View-only change (BQ live; panel already styles DARK_BRAKE).

### v27.8.1 — the queue's answer is the park, not the brake (Ori 2026-08-04)

Ori (BUNNY-VIDEO/BROAD Hunter, $20, 40% dark): "I see 8 keywords active but only 5 have
seats — then this budget can hold."

Right, and it exposed a v27.8 bug: the dark-no-raise brake sat AHEAD of the beyond-seat
PARK_WAIT branch, so queued keywords that clicked yesterday got the gentle -N%/day brake
instead of the immediate $0.25 queue park. Yesterday the 5 seats spent $5.15 while the
7 queued keywords spent $17.93 — the queue was the entire cap. Fix: DARK_BRAKE requires
`seat_rank <= slots`; beyond-seat rows always fall through to PARK_WAIT $0.25.
After: queue #1-7 all PARK_WAIT $0.25 (~$18/day freed — the budget holds its 5 seats),
seats 2-3 brake, the 1.83x winner holds. Fleet: 0 beyond-seat brakes remain.

## v27.9 — working-tier dark reacts on short windows too (Ori 2026-08-04)

Ori (BOX-VIDEO/PT, dark 52%, held by "working cadence 7d not due yet"): "this should have
the short term window logic not 7 days."

`V_OOB_BUDGET_PHASE`: the working-cadence throttle (budget re-suggested only every 7d
off / 3d peak) and the working cut-evidence window (7d off / 3d peak) are REMOVED — both
tiers are judged daily on **today + prev-2d**, differing only in ladder multipliers (low
x2/x1.5 · working x1.5/x1.25, same 0.6x symmetric cut, same floors). First unthrottled
pass: BOX-SP/AUTO White 69% dark converting 1.38x -> RAISE x1.25 $70->$87.50 (the cadence
had been sitting on it for days); Hunter Gift-for-Girl -> RAISE_STRONG $46->$69.75.

Removing the throttle exposed that it had been accidentally masking re-suggestions of
APPLIED moves — so the **APPLIED_HOLD overlay (v27.4 doctrine) now covers this view too**:
last BUDGET_CHANGE within 48h + (applied today OR value not yet in config, $0.51
tolerance for the $1-rounded budget) -> action APPLIED_HOLD, suggestion suppressed,
reason "budget applied $X at <ts> — waiting for Amazon sync". 12 holds at deploy, 0
invalid; the low tier (which never had a guard) gets the same protection.
Remaining known gap: V_OOB_KEYWORD bid rows have days_since_change<1 ("changed today")
but no config-sync test — acceptable (bids sync fast and the 1-day gate holds the line).

## v27.10 — Portfolio-OOB asymmetric windows: fast levers daily, verdicts weekly (Ori 2026-08-04)

Ori: "portfolio 80/20 OOB — increase budget, dark brake keyword should be short term
window. Other actions should be regular window (7 days, 8-28 days)." + correction: the
raise is guarded by the regular windows — chronic bleeders don't get raises.

Match the window to the cost of being wrong. Working tier (budget > cap) only; low tiers
stay fully short-window (v27.7):

`V_OOB_BUDGET_PHASE` — CHRONIC FIRST: **7d AND 8-28d both under 0.6x** (peak: 3d AND
4-14d; new r8_28/r4_14 window cols, both channels) -> **CUT 20%** (floor $10/$15) — a hot
yesterday inside a chronic bleeder is noise, no raise. Otherwise raises fire on the SHORT
windows (today >= 1.2x -> x1.25 · + prev-2d >= 1.5x -> x1.5). Else hold. First pass:
BOX-VIDEO/PT $29 -> $23.20 (7d 0.41x AND 8-28d 0x — the campaign Ori flagged), Hunter
Gift-for-Girl keeps RAISE_STRONG on a 2.21x week; mixed-evidence campaigns hold.

`V_OOB_KEYWORD` — deliberate actions (**EASE / FIT_CPC / TRIM_BID**) for working-tier
campaigns judge on **7d clicks + 7d realized CPC** (daily ranges widened 3d -> 7d, both
arms; prev-2d bounds pinned explicitly; ev_clk/ev_cpc tier-aware aliases). **DARK_BRAKE
stays on yesterday for every tier** — the emergency lever. is_low_tier threaded from the
budget view and exposed.

The ratchet is intentional: money moves toward converting campaigns the same day; money
leaves only on a bad week. Brakes and negates own the in-between.

### v27.11 — RAISE_TO_TARGET generalized: winners glide up to their price (Ori 2026-08-04)

Ori ("why it is not raised toward target?" -> "what about RAISE_TO_TARGET"): the v13
season ramp was the ONLY path that raised a bid toward its target — seasonal_now + bid
under 60% of target. That left the asymmetry: MARGINALs EASE down to target, WINNERs
below target had no mirror.

General rule (`V_KEYWORD_LIFT`, both arms, ahead of the seasonal ramp): class **WINNER**
(weekly for big tiers, 3d for low per v27.7), not auto / defense / capped (never raise
into dark), target known, **bid < target − $0.05** -> **+10%/day toward target, never
past it** (same glide formula as the season ramp; beyond target stays coacher-only).
Seats and probes outrank the ramp (beyond-seat winners still queue-park first).

7 ramps at deploy, invariants clean (0 over-target / downward / bad-scope): the asked-for
keyword $0.40->$0.45 toward $0.50, plus real catches — a 4.48x winner on 80 clicks
bidding $0.19 against a $0.45 target, a 2.86x at $0.37 vs $0.59.
Cadence note: RAISE_TO_TARGET belongs to the STABLE bucket in the proposed maturity
cadence (winners step weekly / 3d peak) once that layer ships.

### v27.12 — breakeven cut: W window, glide, $0.15 floor (Ori 2026-08-04)

Ori: "cut to breakeven should be based on last 7 days (or 3 days in peak). If ads net
ROAS on last 7 days is 0.81x and bid is 0.40 then cut to breakeven should be about 10%
decrease of bid." + "cut to breakeven minimum should be 0.15."

The v26.1 shape (28d window, straight to profit-per-click, floor $0.02) produced corpse
bids ($0.40 -> $0.07) on keywords whose CURRENT week was only mildly under water. New
shape (`V_KEYWORD_LIFT`, both arms):

- **Window = W** (7d off / 3d peak — and low tiers' W is already 3d per v27.7).
- **Clicks gate**: >= 30 per 7d window / >= 13 per 3d window.
- **Trigger**: non-WINNER (not auto/defense), W net ROAS **< 1.0** with net profit > 0.
  (The old < 0.4 extreme bar guarded an aggressive jump; a gentle glide needs only
  "losing".)
- **Action**: glide **-10%/day** toward the window's profit-per-click
  (gp_w / clk_w), **floor $0.15** — never a one-shot cut to the bone.
- Zero-profit windows (>= gate clicks, gp_w <= 0) still PARK $0.25.

19 cuts at deploy; invariants clean (0 under $0.15 / upward / steeper than 10%/day /
not-losing). The asked-for case: $0.40 at 0.81x -> $0.36 toward $0.30.

### v27.12.1 — SB platform bid floor $0.25 (Ori 2026-08-04, upload report 30)

Amazon rejected 1 of 147 rows: SB keyword bid $0.10 — "minBid: 0.25". SB keywords have a
$0.25 platform minimum (SP allows $0.02); the old $0.02-floor breakeven cut generated an
illegal SB bid. Three layers, so it cannot recur:

- `V_KEYWORD_LIFT`: SB-arm suggestions clamp to $0.25 at the overlay choke point; if the
  clamp would not be a real move (current bid <= $0.30) the suggestion is suppressed.
- `V_OOB_KEYWORD`: bid_min is channel-aware — IF(is_sb, 0.25, $0.20) at all 8 floor/gate
  sites (DARK_BRAKE etc. never step an SB bid under $0.25).
- `DoPage` export: SB Update rows clamp Math.max(0.25, bid) in both bid builders —
  covers MANUAL hand-set bids too.
Corrected re-upload sheet delivered (sb_bid_floor_reupload.xlsx, 1 row at $0.25); the
other 146 rows of the 2026-08-04 upload landed.

### v27.13 — NUDGE_UP: no clicks need a nudge up (Ori 2026-08-04)

Ori (LOW section, seated keywords at $0.33-$0.57 with 0c yesterday): "no clicks need a
nudge up."

The last stuck case: a SEATED low-tier keyword priced out of the auction — no clicks, no
evidence, nothing ever fires. Rule (`V_KEYWORD_LIFT`, both arms, after VOLUME_LIFT):
low-tier (budget <= cap), seated, not auto/defense/capped, **under the 4-click trial bar
over 1d + prev-2d**, bid > $0.30 and more than 5c under the entry anchor -> **NUDGE_UP
+5%/day** (min +2c) **toward the entry anchor** (max($1, min(1.5x target, $2)) — never
past it). VOLUME_LIFT still outranks it (under-floor campaigns jump to the anchor in one
step; the nudge is the patient version for campaigns above their floor).
Also fixed in passing: the VOLUME_LIFT bid/reason branches were missing the clk28<30
guard the action branch has — a NUDGE_UP row could inherit the anchor-jump formula
(BOX-COMPETE $0.54 -> $1.00 instead of $0.57). All three CASEs aligned.
10 nudge-ups at deploy; 0 too-clicky / downward / out-of-scope / beyond-seat.

### v27.13.1 — low-tier window verdicts need the 10-click day bar (Ori 2026-08-04)

Ori (trial keyword, $0.81 bid, 1c + 4c over 3d, was CUT_TO_TARGET $0.55): "it needs
nudge up."

The v11 4-click trial gate was calibrated for 7-day windows; after the v27.7 rebase a
low-tier keyword could catch a window verdict (PARK / CUT_TO_TARGET) on 4-5 clicks in 3
days — a verdict without evidence. Now:

- Low-tier window verdicts (allowance PARK, CUT_TO_TARGET) require **>= 10 clicks in the
  3d window** (the established 10-click day bar); big tiers keep the 4-click gate on
  their 7d window.
- **NUDGE_UP widens to everything under the 10-click day bar** (was < 4) — an under-
  anchor seated keyword that hasn't reached decision volume keeps buying data at
  +5%/day instead of catching a thin cut.
- Accumulation verdicts are untouched by the bar (by design): 90d permanent parks and
  20-click probe episodes decide at their own grain.
The flagged row: CUT_TO_TARGET $0.55 -> NUDGE_UP $0.85. Fleet: 0 low-tier window
verdicts under 10 clicks.

### v27.14 — starving probes lift to $1; applied negates retire (Ori 2026-08-04)

Two rules from today's field reports:

**Starving probes** (Ori: "if last day probe is with less than 2 clicks need to raise it
to 1 bid"): an in-flight probe with **< 2 clicks yesterday** and bid under $0.95 lifts
straight to the **$1 entry floor** (PROBE_ADJUST) — at 1 click/day the 20-click verdict
never arrives. 77 lifts at deploy (mostly $0.25-$0.84 competitor-PT probes with 0-click
days); 0 too-clicky, 0 already-at-$1. APPLIED_HOLD paces it to one lift per day.

**Applied negates** (upload report 31: 2 of 32 rows rejected "NegativeKeyword already
exists"): the Fivetran negatives sync is frozen (2026-01-03), so the engine could not
see its own applied negates and re-suggested them forever — duplicate Create rows across
batches. `V_OOB_SEARCH_TERM` now retires is_negate permanently for any (campaign, term)
with a logged NEGATE_TERM in FACT_PPC_CHANGE_LOG (campaign-scoped: the same term can
still be negated elsewhere). The 2 rejected terms now False everywhere; 0 applied-dupes
fleet-wide; 3 genuinely-new negates remain. No re-upload needed for report 31 — the 2
"failures" were already-achieved end states.

### v27.15 — spend past the budget IS out of budget (Ori 2026-08-05)

**Ori:** *"if spend is greater then budget you should consider it out of budget as well"*

The dark clock (`pd`) is time-weighted `CAMPAIGN_OUT_OF_BUDGET` from
`V_SRC_AmazonAds_campaign_history`. Amazon does not always emit that status — SB overdelivers
up to 2× its daily budget without ever flipping it, and SP overdelivery lands the same way. The
old `JOIN dark d ON ... AND d.pd > 0` then dropped those campaigns from this view entirely, so a
campaign that spent **$82.55 against a $53 budget (156%) displayed `dark 0%`** and was routed to
the working section as healthy.

**Rule:** a campaign is out of budget when the dark clock fires **OR** it spent at/over its
budget. Concretely:

- `dark` is a LEFT JOIN; membership is `pd > 0 OR spend_1d >= budget`.
- `over_budget := spend_1d >= budget` (published as a column).
- Every ladder gate that read `pd <= dark_target` now reads `pd <= dark_target AND NOT over_budget`,
  so an over-budget campaign takes a real ladder verdict instead of falling into `WATCH`.
- `pct_dark` still reports the **measured** clock — it is not inflated with a fabricated
  percentage. `utilization` carries the over-budget evidence; the reason text says which signal
  fired.

**Single-home:** the frontend routing rule becomes `pctDark > 10 OR utilization >= 1.0`
(`KeywordLiftPhase` hides those campaigns; `OobBudgetPhase` owns them), so a newly-detected
over-budget campaign moves rather than appearing in both sections.

### v27.16 — dark is never a hold: the winner eases gently (Ori 2026-08-05)

**Ori:** *"this is dark>0 therefore you must act · in this case i would decrease bid gently"*

**The deadlock.** A capped campaign with one concentrated winner produced two mutually-deferring
holds and moved nothing:

| engine | verdict |
|---|---|
| `V_OOB_KEYWORD` (winner, `conv_share >= 0.80`) | *"converting in a winner-concentrated campaign — hold (**budget raise is the lever**)"* |
| `V_OOB_BUDGET_PHASE` (campaign ladder) | *"Dark 24% · evidence mid → hold budget, **bids do the work**"* |

The budget ladder will not raise because the blended evidence is mid (`r1 < 1.2`), and the bid
branch returned NULL whenever `ev_clk <= 6` **or** `current_bid <= ev_cpc + 0.05`. Meanwhile one
keyword ate ~80% of a budget that ran out 24% of the day.

**Rule:** when the campaign is dark at all (`pct_dark > 0`) and a converting keyword is
winner-concentrated, the bid **always** moves — glide it −5%/day. A capped campaign cannot buy
more clicks with money it does not have, so it buys them with a cheaper CPC.

- Floor: the platform minimum ($0.20 SP / $0.25 SB) — **not** the target CPC. Ori's own example
  sat at $0.42 against a $0.45 target CPC, i.e. already under target, and still had to move.
- Never a raise: guarded by `current_bid > floor + 0.01`.
- The pre-existing `EASE` (enough clicks and bid above realized CPC, floor = realized CPC) is
  unchanged and still takes precedence; this is the fallback that used to be a hold.

**Still open:** the budget half of Ori's rule — *"one keyword profitable but eaten 80% of budget
and dark > 30% → a budget raise"*. `V_OOB_BUDGET_PHASE` has no `conv_share` (it is a keyword-grain
measure), so the raise needs that signal joined in first. Not built.

### v27.17 — volume outranks every deferral (Ori 2026-08-05)

**Ori:** *"bid should be reduced as well above 10 clicks and dark%>0 even if probing can be reduced"*

A keyword burning **16 clicks at 0.00×** in a 43%-dark campaign held its bid, because the
queue-first deferral (v27.8.2) parked the seat brake while the queue leaked, and probes were
exempt entirely. Volume that size is real money burnt today.

**Rule:** `clk1 > 10 AND pct_dark > 0 AND roas1 < 1.0` brakes the bid ahead of **both** the
queue deferral and the mid-probe exemption — a probe that burnt 16 clicks at 0× already has its
answer. Step = the existing dark step `max(5%, 30% × dark)`, floored at the platform min.
Winners are still never pulled down (`roas1 < 1.0` gate). **11 keywords** braked on day one.

### v27.18 — the dark brake needs 4 clicks (Ori 2026-08-05)

**Ori:** *"dark break should not be on keywords under 4 clicks"*

`DARK_BRAKE` fired at `clk1 >= 1`. One click is not evidence — it is the same noise the TRIM rule
already refuses to act on. All three brake branches now gate at `x.click_goal_day` (4), matching
"TRIM needs REAL evidence" (v-2026-08-01). Verified: 0 brakes remain under 4 clicks.

### v27.47 — the proven-seat exemption stops at 4 clicks (Ori 2026-08-12)

**Ori:** *"clicks>4 , brake 5%"* — pointing at a `WATCH` keyword taking **10 clicks yesterday at
0.00×**, bid $1.00 against a $0.55 target CPC, which the engine answered with
`HOLD — "proven 1.xx× over 90d — holds its seat; the budget raise is the lever, not the brake"`.

The 4-click brake bar (v27.18) was never the blocker here — `clk1 >= 4` already passed. The blocker
was the branch **above** it: `WHEN roas90 >= 1.0 THEN NULL`, an unconditional exemption that let a
90d-proven keyword spend a capped budget all day on its reputation.

**Rule:** the exemption is now capped by volume, and both outcomes live inside the one branch so a
proven keyword can never fall through to the harsher mid-test `TRIM_BID`:

| proven keyword (`roas90 >= 1.0`) | action |
|---|---|
| `clk1 <= 4` (or bid already at the floor) | **HOLD** — the seat is cheap; the budget raise is the lever |
| `clk1 > 4` | **DARK_BRAKE, a flat 5%/day** toward the floor — paced, not punished (never the 15% trim) |

5% is exactly what the v27.46-A4 90d-scaled magnitude already gives a `roas90 >= 1.0` keyword, so
"brake 5%" needed no magnitude change — only the exemption had to yield.

Mirrored in all three ladders (`suggested_bid` / `bid_action` / `bid_reason`) plus the `WATCH` and
`WINNER` role tooltips in `OobBudgetPhase.tsx`. Verified on deploy (2026-08-12): the two held
10-click WATCH rows now brake — ME-VIDEO/BROAD "journal kit for girls ages 8-12" $0.78 → $0.74 and
FRESH-SB\BROAD "16 year old girl gifts" $0.50 → $0.47; every pre-existing DARK_BRAKE row kept its
step; no proven keyword routes to TRIM_BID.

⚠️ Stale doc fixed in the same pass: `V_OOB_KEYWORD.sql`'s header still described the retired
`< 4 PROBE · 4–5 HOLD · >= 6 SLOW` band, which lives only in the two LAUNCH engines
(`V_LAUNCH_PHASE1`, `V_SB_LAUNCH_TARGET`) — this view emits no PROBE/SLOW action at all, and its
`click_cap_day` (6) constant is dead.

### v27.19 — ACTIVATE is for DORMANT keywords only (Ori 2026-08-05)

**Ori:** *"already have 6 clicks no need to activate and raise bid to 1 because it is already
active. gentle raise in this case"*

The `current_bid <= 0.30` branch jumped a parked keyword straight to the $1 seat-entry floor —
a **4× move** — and it was firing on keywords already delivering (6 clicks at 6.15× yesterday).
The $1 floor is the *anchorless* on-ramp: defensible only with no delivery to price from.

**Rule:** ACTIVATE now requires `clk1 < click_goal_day` (4). A delivering keyword falls through
to the normal converting / click-band ladder and raises proportionately instead. Verified: 0
ACTIVATEs remain on keywords with 4+ clicks.

### ⚠️ OPEN — the seat order ignores recent conversion (Ori 2026-08-05)

**Ori:** *"why park this · seems like you should park different keyword"* — on `gift for 12 year
old`, prev-2d **3 clicks at 11.37×**, converting, being parked $0.45 → $0.25.

`seat_rank` orders by `roas90 DESC` after the converting/proven tier, so **90-day history
dominates recent conversion**. Observed in one 4-seat campaign:

| rank | keyword | conv? | 1d | prev-2d | seat |
|---|---|---|---|---|---|
| 2 | gift for 8+ year old girl | **no** | 0c | 0c (never clicked) | ✅ holds a seat |
| 4 | girls journals age 10-12 | **no** | 1c 0× | — | ✅ holds a seat |
| 6 | gift for 12 year old | **yes** | 1c | **3c 11.37×** | ❌ parked |
| 8 | girls journaling set | **yes** | 1c | **12c 3.51×** | ❌ parked |
| 9 | journal kit for girls ages 8-12 | **yes** | 0c | **4c 6.41×** | ❌ parked |

Two keywords that have never converted hold seats ahead of three that are converting now.
NOT FIXED — reshuffling `seat_rank` moves seats in every OOB campaign at once, and the
recent-vs-90d weighting is Ori's call (a 11.37× on 3 clicks is also thin evidence).

### v27.20 — converting NOW outranks proven-but-quiet in the seat order (Ori 2026-08-05)

**Ori:** *"why park this · seems like you should park different keyword"*, then
*"why it still want to park this and activate this"*

Both `PARK_WAIT` and `ACTIVATE` are decided by one number — `seat_rank`. Its second key lumped
"converting NOW" together with "proven over 90d" (`IF(converting OR roas90 >= 1.0, 0, 1)`), and
the next key sorted inside that group by `roas90 DESC`. So **90-day history decided the seats**
and a keyword converting today with thin 90d history sank below keywords that had never
converted at all. Measured, one 4-seat campaign:

| rank | keyword | conv? | 1d | prev-2d | verdict |
|---|---|---|---|---|---|
| 2 | gift for 8+ year old girl | **no** | 0c | 0c — *never clicked* | **ACTIVATE → $1.00** |
| 4 | girls journals age 10-12 | **no** | 1c 0× | — | holds a seat |
| 6 | gift for 12 year old | **yes** | 1c | **3c 11.37×** | **PARK_WAIT → $0.25** |
| 8 | girls journaling set | **yes** | 1c | **12c 3.51×** | queued |
| 9 | journal kit for girls ages 8-12 | **yes** | 0c | **4c 6.41×** | queued |

A keyword that had *never taken a click* was being activated to $1.00 while three live
converters were parked to $0.25.

**Rule:** a new tier `IF(b.converting, 0, 1)` is inserted directly below the quality group, so
converting in the last 3 days (net ROAS ≥ 1.0 on last day **or** prior-2d) outranks
proven-but-quiet. Ties **inside** each group still break on `roas90 DESC`, so this never
reorders two live converters against each other on thin evidence.

### v27.21 — the window strategies get a LAST DAY column, and it gates clicks (Ori 2026-08-06)

**Ori:** *"in all strategies with 7d, 8–28d window you should also show last day. the meaning of
last day in those cases is for seated active keywords to gate clicks — meaning if last day no
clicks that means the bid is too low and we may need to nudge it back up"*

The working tier is judged on **7d / 8–28d** windows, and those windows were the only thing
shown. But a window cannot refresh on a keyword that never enters the auction: a seated keyword
priced out of the auction takes 0 clicks, its 7d window ages without new evidence, and it sits
frozen forever. The last day is the **click gate** that detects it.

`NUDGE_UP` already existed but was gated to the **low tier only**
(`budget <= low_budget_cap`) and keyed on a 3-day click bar — i.e. it never applied to the very
strategies that use these windows.

**Rule (both SP and SB arms):** a seated, active, uncapped **working-tier** keyword with
`clk1 = 0` nudges **+5%/day** toward the entry anchor `max($1, min(1.5×tcpc, $2))`. Guards match
the low-tier rule: not auto, not defense, not capped (capped → the budget is the lever),
`current_bid > $0.30` (parked keywords excluded), and only while the bid is still below the
anchor — so it can never overshoot.

**Display:** the 7d / 8–28d tables now render a `last day` column (campaign row included, to keep
the columns aligned). A seated keyword showing **0 clicks is amber**, so "priced out" reads
differently from "quiet day".

### v27.22 — never trim a clause that is already stuck (Ori 2026-08-06)

**Ori:** *"the keyword already stuck"* — on an auto clause showing `0c` yesterday (amber, priced
out of the auction) whose action was **`auto trim`**.

`AUTO_TRIM` fired on `clk_w >= 4` — clicks over the **window** — with no last-day gate. So a
clause with 27 window clicks at 0× but **zero clicks yesterday** was told to cut its bid again.
That is the wrong direction: it is already out of the auction, so the trim has nothing left to
achieve and only entrenches the invisibility that the v27.21 click gate exists to detect.

**Rule:** `AUTO_TRIM` now also requires `clk1 >= 1` (all six sites — action, value and reason,
SP and SB arms). No clicks yesterday ⇒ **HOLD**, not a cut.

Deliberately NOT a nudge up: the clause is a genuine LOSER over its window (clicks, no sales),
so raising it would buy more of a known loss. Holding is the honest verdict — the trim already
achieved what it could. `AUTO_BRAKE` was checked in the same pass and already carried
`clk1 >= 1`, so it needed no change.

Verified: 0 `AUTO_TRIM` rows remain on zero-click clauses; 21 keywords now take the last-day
`NUDGE_UP`.

### v27.26 — a profitable last day vetoes every window move (Ori 2026-08-06)

**Ori:** *"if last day it was profitable and last 7 days doesnt. do not change anything. maybe we
start a wave. when a not profitable day will occur you can check the 7 days again and decide
what to do"*

Example row: **32c at 1.42× yesterday** against **260c at 0.47× over the window**. The window
logic wanted to cut. But the window is history — a profitable day inside a losing window may be
the turn, and cutting it kills the wave before it forms.

**Rule:** when `clk1 >= 1 AND roas_1d >= 1.0 AND roas_w < 1.0` → **HOLD, change nothing** —
neither up nor down ("do not change anything" is literal). The window regains authority on the
next unprofitable day. Placed after the probe branches (probes keep their own 20-click
lifecycle) and before every window-driven branch, in both SP and SB arms.

Verified: every matching keyword now returns HOLD with no suggested bid.

### v27.28 / v27.29 — output guards from the action audit (Ori 2026-08-06)

Ori: *"i saw 10% of wrong decisions ... investigate each action one by one, do not use logic only
table data per type"*. Auditing all 650 rows of V_KEYWORD_LIFT per action type found 25 wrong or
inert rows (~4%; the remaining suspicion was 40 KEEPs on winners, which the data showed are
1-3-click noise and correctly held). Both fixes live at the OUTPUT layer — one place, not
scattered across branch sites.

**C1 (v27.28) — never shelve a proven winner.** A keyword its own evidence window calls a winner
(`clicks_w >= 4 AND roas_w >= 1.0`) can no longer resolve to PARK / PARK_WAIT / IDLE /
PROBE_WAIT; it becomes WINNER_FOUND with no bid change. v27.27 had fixed this only for
`probe_done`, and it was still leaking through 15 PROBE_WAIT, 1 PARK_WAIT and 2 IDLE — e.g.
`journal kit for girls`, **157 clicks at 1.39x**, was being cut $0.75 -> $0.25. The **4-click bar
is load-bearing**: it keeps 28.65x-on-one-click noise from being promoted.

**C2 (v27.29) — an action that promises a change must carry one.** Any action outside the
no-change set (HOLD/KEEP/KEEP_TAIL/IDLE/WINNER_FOUND/DEFENSE/APPLIED_HOLD/PROBE_WAIT/
PROBE_ADJUST) whose final value is NULL or equals the current bid is forced to HOLD. The audit
found 5 PARKs suggesting the bid they already had and 2 rows labelled cut/raise with no value —
pure bulksheet noise. Evaluated AFTER the SB $0.25 clamp, so a clamp that erases the move also
resolves to HOLD.

Verified: 0 winners shelved, 0 no-op actions, WINNER_FOUND 4 -> 19.

**Still open (C3, needs Ori's call):** 26 PROBE_ADJUSTs jumping to $1.00 on zero window clicks
(one against a $0.55 target CPC); 13 DEFENSE keywords at up to $2.70 with zero delivery.

### v27.33 — the SB minimum bid is PER FORMAT (Ori 2026-08-06, upload reports 32 + 33)

Established by uploading real bulksheets of zero-click keywords and reading Amazon's rejections —
measured, not assumed:

| format | tested | Amazon's answer |
|---|---|---|
| SB `BRAND_VIDEO` / `VIDEO` | $0.15 (r32), $0.20 (r33) | **both rejected**, `minBid: 0.25` |
| SB `PRODUCT_COLLECTION` / `STORE_SPOTLIGHT` | $0.15 (r32), $0.10 (r33) | **both accepted** |
| SP | $0.20 (r33) | accepted |

The single `IF(is_sb, 0.25, bid_min)` constant was therefore wrong in both directions: too low for
nothing, but far too HIGH for every non-video SB campaign — which is what silently stranded
proven winners below $0.25.

**Implemented:**
- `V_OOB_KEYWORD`: new `agfmt` CTE (ad_group -> creative_type) and a per-arm `bid_floor`
  (SP `bid_min`; SB $0.10 for product-collection/store-spotlight, else $0.25). All **18** inline
  `IF(is_sb, 0.25, bid_min)` sites now read `b.bid_floor`.
- `V_KEYWORD_LIFT`: all **5** output-clamp sites take the same per-format floor AND now
  **clamp UP to the floor instead of suppressing**. The old rule dropped the suggestion whenever
  the clamped value "was not a real move", which is what stranded a winner at a below-floor bid
  indefinitely.
- `creative_type` NULL defaults to **$0.25** (conservative): bidding too high is recoverable, a
  rejected bulksheet row fails silently. Coverage is 40/41 ENABLED SB campaigns; the NULLs are
  177 archived + 5 paused + 1 enabled.

**Verified:** `teen girl gifts trendy stuff` (BRAND-STORE, product collection, 18c at 4.57x)
finally resolves **$0.15 -> $0.20, RAISE_TO_TARGET** — the case that exposed the whole chain.
0 SB suggestions below their format floor; 0 RAISE_TO_TARGET with a null value; 0 winners shelved.

**Live side effects of the experiments:** 11 non-video SB keywords moved to $0.15 (r32), plus
`tween girls gifts` to $0.10 and one SP product target to $0.20 (r33). All were zero-click.

### v27.34 — never keep FUNDING a proven loser (Ori 2026-08-06, audit #2)

The exact mirror of v27.28. That rule stopped the engine **shelving a proven winner**; nothing
stopped it **funding a proven loser**. Found by re-running the per-action audit on table data
after the v27.28-33 fixes — 36 rows across three actions:

| action | leak | worst example |
|---|---|---|
| PROBE_WAIT (24 of 69) | sat at a **$1.00** bid awaiting a 20-click verdict already failed | `asin="B0FCFTP2QT"` — 17c at 0.00x, **$23.99 spent** |
| PROBE_ADJUST (7 of 61) | raised to **$1.00** on losing evidence | `cheap gift for girl` — 31c at 0.00x, **$26.07 spent** |
| NUDGE_UP (5 of 20) | nudged up keywords with real losing evidence (the nudge exists for INVISIBLE keywords) | `fuzzy diary with lock for girls` — 12c at 0.00x |

**Rule:** `clicks_w >= 4 AND roas_w < 0.6` is a verdict. A keyword meeting it may not hold or take
a probe-path raise — it parks at $0.25 (clears every per-format floor from v27.33), or HOLDs if
already at/below that. Output layer, same place as v27.28/29, so no branch can bypass it.

**Verified:** 0 losers still funded, 0 winners shelved (no regression), PARK 9 -> 44.
All three named examples now park: $1.00 -> $0.25, $1.00 -> $0.25, $0.68 -> $0.25.

**Still open for Ori's call:** PROBE_ADJUST still issues 55 raises to $1.00 in one run (scale +
collides with "don't activate while dark"); 36 KEEP rows are proven winners with a median 31
clicks at 1.26x taking no action; DEFENSE holds 28 keywords at ~$2.00 with 13 at zero delivery.

## v27.45 — ONE membership function, ONE bid owner, ONE budget authority (2026-08-08, iteration-5 7.1)

The three engine views disagreed about who owns a capped campaign (iteration-4 D3/D5 +
iteration-5 3.2/3.7, all verifier-confirmed; ~$5.2k/wk of spend under contradictory or missing
instructions):

- **A. invisible to the ladder** — `V_OOB_BUDGET_PHASE` membership was an ANCHOR-DAY test
  (pd>0 OR spend_1d>=budget, v27.15). 25 chronically-capped campaigns ($3,227.04/7d) were
  invisible because their anchor day came in light — incl. **BOX-SP/PHRASE (Brand Defense)**
  capped 3 of 7 (doctrine: never starve defense) and **ME-VIDEO/BROAD (Hunter)** at 1.37x
  GP-ROAS/90d capped 5 of 7 that never saw its RAISE.
- **B. silent caps** — `V_OOB_KEYWORD` filtered further to `pct_dark > 10`, leaving 12 of the
  budget view's campaigns outside the bid engine while their budget rows said "bids do the work".
- **C. double instruction** — `V_KEYWORD_LIFT` had no DEFER_OOB, so capped campaigns took bids
  from BOTH engines; 6 of 8 OOB suggestions computed from DIM_KEYWORD's STALE bid instead of the
  last-applied bid (an applied CUT $0.65 flipped into an OOB RAISE $0.75 on 'surprise balls').
- **D. budget contradiction** — LIFT's own budget column contradicted PHASE on 3 campaigns
  ($31.7/day); whichever page the user read won.

### 1. `V_CAMPAIGN_CAP_STATE` — the single membership function (new view)

Per ENABLED campaign, per America/Los_Angeles day over the trailing 14 days:
`capped_day` = **per-day v27.15 dual signal** — >=1 CAMPAIGN_OUT_OF_BUDGET event in
`V_SRC_AmazonAds_campaign_history` that day OR day spend >= day budget (DIM_CAMPAIGN SCD2
effective ranges; SP spend FACT_AMAZON_ADS, SB spend sb_campaign_report; per-channel anchors
`LEAST(MAX(date), FN_ADS_ANCHOR_CAP())`). PARITY: the anchor-day flag reproduced live v27.15
membership 28/28 exactly.

**`is_oob_owned` = calibrated HYSTERESIS** (read-only calibration 2026-08-08, 14 anchors):
ENTER when `days_capped_7d >= 2`, EXIT only when `days_capped_7d = 0` (holds while >=1 once
entered). Implemented STATELESSLY: entry test evaluated over the last 7 anchor days (any day
with days_capped_7d >= 2 computed at that day, still >= 1 now) — no persisted state; both
formulations tested identically over 14 anchors. Numbers: **49 owned, $7,306.67/7d (76% of
ENABLED spend), 15.1 ownership flips/wk** (fixed N>=2: same capture, 27.5 flips/wk; N>=1: 7
weak-evidence ownerships incl. a 22%-util blip; N>=3: drops silent-cap ME-SP/PT D3 — recreates
gap B — DISQUALIFIED). Exit-at-0 tail: a campaign that stops capping stays owned up to 7 days
after its last capped day — the price of stability, and consistent with "OOB owns while dark".

### 2. Who reads it

- **`V_OOB_BUDGET_PHASE`**: membership = `is_oob_owned` (INNER JOIN). pct_dark / over_budget
  stay the MEASURED anchor-day signals. WATCH now requires `days_capped_7d <= 1` — a campaign
  capped 2+ of 7 runs the ladder even when its anchor day was light (reason opener restated:
  "Capped N of last 7 days (anchor day light)"). Output adds `days_capped_7d` + `is_oob_owned`
  **for the cube to adopt later** (dashboard is local-only; Cube schema + frontend routing are a
  follow-up — OobBudget cube does not read the new columns yet). DEFENSE GATE on the budget
  ladder: both CUT branches now carry `NOT is_defense` — never cut a defense budget on ROAS
  ("never starve defense"; raises and holds still apply). Latent before v27.45 (defense rarely
  entered PHASE under the anchor-day test), live now that defense membership is persistent.
- **`V_OOB_KEYWORD`**: population = every PHASE campaign on its channel (`is_oob_owned`, no
  pct_dark filter). DEFENSE campaigns' keywords appear but NEVER instruct (bid_action `DEFENSE`,
  no bid). The v27.23 activation gate reads `(pct_dark > 0 OR days_capped_7d >= 2)` so an
  anchor-light day cannot open the activation door on a chronically capped campaign.
- **`V_KEYWORD_LIFT`**: rows of owned campaigns emit **`DEFER_OOB`** (no suggested_bid, reason
  "capped Nd of 7 — out-of-budget engine owns the bids") at the TOP of the output-guard ladder —
  rows stay visible, they just don't instruct. DEFENSE rows exempt (stay `DEFENSE` — defense
  bids belong to NEITHER engine; the budget ladder is defense's remedy). `DEFER_OOB` +
  `APPLIED_HOLD` are no-change actions in the v27.29 no-empty-promises exempt set.

No campaign in both engines' emitting sets, none orphaned: OOB-owned -> V_OOB_KEYWORD emits
(except defense), LIFT defers; not owned -> absent from V_OOB_KEYWORD entirely, LIFT emits.

### 3. OOB gets the applied-bid doctrine

`V_OOB_KEYWORD` adopts LIFT's v27.4 applied/ap pattern verbatim (outermost wrapper, mirrors
PHASE's budget hold): last applied INCREASE_BID/REDUCE_BID per (campaign, targeting) within 48h;
applied TODAY (LA) or applied value not yet reflected in the config bid (|delta| > 0.005) =>
`bid_action 'APPLIED_HOLD'`, no suggestion. This kills the re-cut-from-stale-base and the
cut-flips-to-raise failure: while the config lags Fivetran, the row holds; once synced, the
suggestion computes FROM the applied bid (config == applied).

### 4. Single budget authority

`V_KEYWORD_LIFT.suggested_budget / budget_reason` for campaigns present in `V_OOB_BUDGET_PHASE`
read PHASE **verbatim** (join on campaign_id; PHASE carries its own applied-hold so LIFT's
bud_hold is bypassed for them). LIFT's healthy-campaign loss-cut budget rule survives ONLY for
campaigns not in PHASE. Verified: 0 mismatches account-wide; the 3 contradicting campaigns
(BOX-SBS/BROAD By Age, BOX-SP/AUTO White, FRESH-SP/BROAD BTS) now show ONE instruction.

### Deployed + verified (2026-08-08)

- Cap state: 109 ENABLED, 49 owned, $7,306/7d governed — matches calibration; BOX-STORE/BROAD
  (Discovery) correctly loses ownership (1/7, util 22%), LIFT resumes it.
- PHASE 28 -> 49 rows; ME-VIDEO/BROAD (Hunter) gets RAISE_STRONG $53 -> $79.50; Brand Defense
  present (HOLD, mixed evidence — visible, never starved silently again).
- V_OOB_KEYWORD 121 -> 345 rows (49 campaigns; 3 DEFENSE rows never instruct); LIFT 342 of 663
  rows DEFER_OOB across 48 campaigns (= 49 minus defense).
- Double-instructed keywords (both engines emitting a bid): 22 -> **0**.
- Season gates: LIFT context_gate counts byte-identical (548 null / 88 NONE / 27 ENTRY_BLOCK);
  OOB gate rows grew only by population.
- All guard suites 0 violations; determinism 2x on all three views.

**Out of scope / follow-ups:** Cube + dashboard routing for `is_oob_owned`/`days_capped_7d`
(OobBudget cube, Weekly Run sections) — the columns are live on the views, adoption pending.
`V_OOB_SEARCH_TERM` still routes its OOB/LIFT panels on `pct_dark > 10` (its negate doctrine is
identical in both panels, so no contradiction — but its "engine" label no longer matches bid
ownership; align it when the cube adopts cap state).
→ Both follow-ups closed by §v27.46 below.

## v27.46 — Ownership adoption: search-term panels + cube + dashboard (2026-08-09)

The alignment pass that closes the v27.45 follow-ups. LABEL/POPULATION alignment only — no
negate-doctrine change, no bid or budget logic touched.

- **`V_OOB_SEARCH_TERM`**: panel routing (`engine` label + OOB membership) switches from the
  old anchor-day `V_OOB_BUDGET_PHASE.pct_dark > 10` test to `V_CAMPAIGN_CAP_STATE.is_oob_owned`
  — the same single membership function both bid engines already read (v27.45). The two-window
  negate doctrine is identical in both panels, so every row keeps its `is_negate`/`is_winner`
  verdict; only the panel a campaign's terms appear under moves. Measured at deploy: 65,205
  rows total unchanged; 34 campaigns (30,548 rows) relabel LIFT → OOB — every one of them
  `is_oob_owned` with `days_capped_7d` 1–7 and anchor-day `pct_dark` ≈ 0 (the silent-cap
  population v27.45 exists to capture); zero rows move OOB → LIFT (anchor-day dark ⊆ owned,
  since PHASE membership is already `is_oob_owned`).
- **OobBudget cube**: exposes `isOobOwned` (boolean) + `daysCapped7d` (number) — passthrough
  dimensions of the PHASE output columns.
- **Weekly Run dashboard** (`KeywordLiftPhase.tsx` single-home rule): section ownership now
  reads the cube's `isOobOwned` flag instead of deriving it client-side as
  `pctDark > 10 || utilization >= 1.0`. The client-side derivation survives only as a FALLBACK
  when the flag is absent from the cube response (cube cache lag during rollout); pctDark /
  utilization remain display values. All decision logic stays in SQL (backend-first doctrine).

## v27.46 guard batch — A4 DARK_BRAKE scaled by 90d reality · A5 budget no-op guard (2026-08-09)

Approved batch (A1–A6); A1/A2/A3/A6 are documented in `SEASON_CONTEXT_LEDGER.md` §5.7. This
section is the spec for the two items that live in this phase's views.

### A4 — DARK_BRAKE scaled by 90d reality (`V_OOB_KEYWORD` 3 sites + `V_KEYWORD_LIFT` AUTO_BRAKE)

The dark brake's TRIGGERS are unchanged (v27.17 volume override `clk1 > 10`; v27.18 seated
brake `clk1 >= 4` or click-hog; the flat brake `clk1 >= 4`). Only the MAGNITUDE now reads the
keyword's settled-ish 90d GP-ROAS (`roas90` — the engines' existing tier-COGS-corrected 90d
net-ROAS; its unsettled tail UNDERSTATES GP, which only errs toward the harder brake —
conservative direction):

| 90d record | daily step |
|---|---|
| `roas90 >= 1.0` (proven earner) | **minimum ease −5%** (flat; `1 − 0.05`) |
| `0.6 <= roas90 < 1.0` (middling) | `max(5%, 15% × dark)` |
| `roas90 < 0.6` OR no 90d data | `max(5%, 30% × dark)` — the pre-v27.46 behavior |

- **"Dark is never a hold"** stands: the −5% minimum always applies; floors unchanged
  (SP $0.20 / SB per-format v27.33; every site's `GREATEST(..., floor)` untouched).
- **BLOCK_CUT still outranks:** the season gate's cut veto sits ABOVE the brake in the gated
  output layer — a WIN-prior-protected row stays vetoed to HOLD exactly as before (A4 edits the
  branch magnitude in place; the veto layer is untouched). `V_OOB_KEYWORD` exposes `roas90` as
  an output column for verification.
- `V_KEYWORD_LIFT` has NO action named DARK_BRAKE anymore (v27.45 DEFER_OOB hands every
  chronically-capped campaign's bids to OOB). Its one remaining dark-magnitude brake is
  **AUTO_BRAKE** (capped auto clauses, `max(5%, 30% × dark)`) — the same scaling is applied
  there (autos are outside the season gate, so only the roas90 tiers apply). Flagged as a
  judgment call in the deploy report; the trigger (`clk1 >= 1`, non-winner clause) unchanged.
- TRIM_BID's `max(15%, 30% × dark)` is a TRIM, not the dark brake — deliberately untouched.

### A5 — budget no-op guard (`V_OOB_BUDGET_PHASE`)

v27.29 "no empty promises" for the budget ladder: any CUT/RAISE whose `suggested_budget` equals
the current budget after floors/rounding (|Δ| < $0.005) resolves to **HOLD** with an honest
reason — `CUT` landing on the seasonal floor the budget already sits at → "already at the $10/$15
floor — hold"; any other rounding no-op → "no change after rounding — hold". HOLD carries no
suggested value. APPLIED_HOLD outranks it (a just-applied change is the more specific truth).
Measured at deploy: 7 rows converted (all CUT-at-$10-floor).

## v27.50 — the peak judged window is evidence-gated (Ori 2026-08-12)

**Spec of record: `architecture/PEAK_WINDOW_RULE.md`. Read that before touching anything below.**

`V_KEYWORD_LIFT`'s window W is no longer `IF(in_peak, 3, 7)`. Ori's rule: **in peak the engine
defaults to 3 days, and a 7-day window is granted for an occurrence type ONLY where the same
occurrence in a prior year was measured to produce better decisions at 7.** The burden of proof
sits on the slower window — no, thin, ambiguous or conflicting evidence all resolve to 3.

- `V_SEASON_PEAK_GATE` — the gate predicate, written once (v27.49 rule, unchanged; parity verified
  over 1,827 days, 0 divergent). `season` counts it.
- `DE_PEAK_WINDOW_OVERRIDE` — the proof, as data: window + verdict + occurrences tested + n + the
  deciding metric + robustness count + re-measure date, per occurrence type.
- `V_PEAK_WINDOW_RULE` — one row: today's `in_peak`, `occurrence_type`, `w_days`, `w_days_reason`.
  `cap` reads `w_days` from it.

Granted 2026-08-12: **XMAS_EARLY, XMAS_PEAK, EASTER → 7.** Everything else — BTS (the live season),
VDAY, MDAY, GRAD, FDAY, PRIME — **→ 3.** `low_cap`, the 20/40% exploration allowance, probe slots,
the budget floor, the click bars and the CPC band are all untouched.

**`V_OOB_BUDGET_PHASE` was deliberately NOT changed.** Its own `IF(b.in_peak, b.r3, b.r7)` cut at
lines 278/292/314, and the `today AND prev-2d` construct at 136–139, are the same 3-vs-7 question
at budget grain and Ori's rule logically covers them — but they were not measured, so they were not
moved. Recommendation and the reason it is lower risk (it needs BOTH a short leg and a settled long
leg to cut, so a fresh-data understatement alone cannot condemn) are in
`PEAK_WINDOW_RULE.md` §6.1. If a 7-override is ever applied to PHASE it must read
`V_PEAK_WINDOW_RULE.w_days` so the two engines cannot disagree about the same campaign on the same
day.

## §v27.70 — the ladder's evidence windows under V_PEAK_WINDOW_RULE (Task 2.3, 2026-08-16)

`in_peak` and the judged-window length now come from `V_PEAK_WINDOW_RULE` — the same
burden-of-proof source the keyword engines read (3-day default in peak; 7 only for a peak that
PROVED 7 better on last year's same occurrence; the local v27.49 season CTE is retired — two peak
definitions in one engine eventually disagree). Every ladder leg reads a named EVIDENCE column
defined once in `base` (`ev_s`/`ev_p` for raises and the low-tier cut, `evc_s`/`evc_p` for the
working chronic test, plus their labels): off-peak keeps the deliberate v27.9 shape (today +
prev-2d; 7d + 8-28d chronic); in peak every leg follows `w_days` (3 ⇒ 3d + 4-14d, 7 ⇒ 7d + 8-28d).
Reasons print the SAME labels the predicates judge, so the sentence can never describe a window
the decision did not read. Published: `w_days` column. First deploy (BTS, w=3): 6 of 30 flipped,
all evidence-WIDENING — 5 HOLD→RAISE_WEAK (a noisy anchor day was blocking raises the 3-day
window supports, e.g. VIDEO- BALL "last 3d 1.32x → raise ×1.25") and 1 CUT→HOLD (a cut that fired
on one bad day + prev-2d, unsupported by the peak windows). Downstream note: the published
`roas_1d`/`roas_prev2` columns are UNCHANGED (display + V_OOB_KEYWORD's raise-gate inputs) — only
the ladder's own judgment legs moved.
