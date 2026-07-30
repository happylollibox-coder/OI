# The Intent System — every rule, end to end, in plain words

*Written 2026-07-25 for Ori to verify. Every number here is the live value.
If a rule below is wrong, the code is wrong — this document is the contract.*

---

## Part 1 — What a keyword means (the intent layer)

1. Every search term is broken into **facets**: product type, gender, age, occasion,
   holiday, and **customer budget** ("deals", "under 10 dollars" → small budget;
   "stuff"/"things" → implied low budget).
2. The facets compose an **intent key**, e.g. `tween-girl-birthday-gift`,
   `age8-14-girl-journal-diary`, `implied_low-teen-girl-gift`.
3. Machine suggestions go to a physical table (`DE_SEARCH_TERM_INTENT`). **You verify
   one by one** on the Intent Configuration page. A human verdict is never overwritten
   by the machine — if the machine later disagrees, the row is flagged RECHECK and your
   answer stays until you change it.

## Part 2 — What a click is worth (the model layer)

For every **product × intent**:

4. **Base CVR** = orders ÷ clicks over 12 months, *shrunk* toward the intent's average:
   we add 200 phantom clicks at the intent-average CVR. A cell with 40 real clicks
   mostly inherits the intent average; a cell with 5,000 clicks speaks for itself.
5. **Season index** per intent per calendar month = that month's CVR ÷ the intent's
   year-round CVR, pooled across all products (shrunk with 500 phantom clicks).
   A product's **first 90 days are excluded** from season pooling — a launch ramp is
   not seasonality (this is what corrected August for LolliME).
6. **CVR forecast for a month** = base CVR × season index.
7. **Value per click** = CVR forecast × gross profit per order (product-level).
8. **Target bid** = 70% of value per click (you keep 30% of the value as profit).
9. **Expected net ROAS at market price** = value per click ÷ what a click actually
   costs lately (trailing 28-day CPC). No market read → treated as RUN (we probe).

## Part 3 — The four bands (the monthly cockpit decision)

Per product × intent × month, compare expected net ROAS at market to three thresholds
(all editable in `DE_COACH_THRESHOLDS`, strategy INTENT):

| Expected net ROAS | Band | What it means |
|---|---|---|
| ≥ 1.1 | **RUN** | profitable — run at target bid, max CPC = value ÷ 1.1 |
| 0.7 – 1.1 | **VELOCITY** | marginal — run **only while the product is behind its velocity floor**, max CPC = value ÷ 0.7, cheapest marginal sales first |
| 0.5 – 0.7 | **MARGINAL** | off unless we are deliberately probing |
| < 0.5 | **OFF** | paused, no exceptions |

10. **Velocity floor** (why we sell even marginal): floor = the LARGER of
    (a) last month's badge tier (50/100/500/1,000 "bought in past month") and
    (b) the plan's forecast units × 85%. Behind the floor → VELOCITY cells run.
    At/above the floor → VELOCITY cells stop. Amazon rewards velocity with badges,
    rank, and organic sales — that's the asset being bought.
11. **Hysteresis**: a band only flips when it crosses the line by more than 0.1, or
    holds on the other side for two consecutive weekly checkpoints. No ping-ponging.
12. Decisions carry **dates, not months**: holiday intents move on `DIM_US_HOLIDAYS`
    boost/peak/cooldown dates (Back-to-School boosts Aug 1, peaks Aug 10);
    generic intents move on month boundaries.
    A holiday cell is **born paused** — a new holiday campaign uploads PAUSED whatever
    its band says, and its first resume is the dated boost_start row (Christmas: Oct 1).

## Part 4 — The campaign grid (where the money lives)

13. One **permanent campaign** per product × intent × rung. Rungs: SP Broad, Exact,
    Phrase, Video, Spotlight. Campaigns are never deleted — bands pause/resume them.
14. **Rungs are earned**: Tier A (≥5,000 clicks/12m on the intent) starts with
    Broad + Exact. Phrase/Video/Spotlight are earned by performance. Demotion = pause.
15. **Exact owns terms**: each search term belongs to exactly ONE product's Exact
    campaign (the one with the highest value per click). Every Broad campaign of that
    product carries negativeExact for all its exact-owned terms — Broad explores,
    Exact exploits, they never bid against each other (the graduation mechanism).
16. Exact entry gate: research rank > 75 AND top SQP volume. No fit rank → no Exact;
    the Broad probes it instead.
17. Family junk negatives ship on every campaign, with two exceptions:
    a cell never negates its own defining words ("stuff" on an implied_low cell),
    and a term with **≥3 orders** beats a colliding negative (your school-supplies
    precedent). Brand negatives are never overridden (brand → defense only).

## Part 5 — The monthly cockpit (high-level decision maker)

Once a month it produces one reviewable plan; you approve it once:

18. For every grid campaign: the band for the month, the target bid, the max CPC,
    the state changes at their **trigger dates**, keyword adds (from research, gated
    rank > 75) with the worst incumbent paused when the campaign is full (10 keywords),
    and the daily budget from the pool (trailing-28d spend × plan ratio).
19. Approved rows become **dated bulksheets** — you upload them on their dates.
    Nothing touches Amazon automatically.

## Part 6 — The coacher (the performer, weekly/daily)

Between monthly plans, the coacher enforces the plan with the existing Weekly-Run flow:

20. **NEGATE** a search term with ≥15 clicks and 0 orders in 4 weeks — at the term
    level, in the campaign where it bleeds. This is the ONLY bleed control.
21. **No loss-driven bid cuts** — a bid is never cut because of losses (the 2026-07-21
    doctrine: launch = find the right bid). The only bid cut allowed is the dark-brake
    (impression-share capping) and band max-CPC enforcement.
22. **RAISE +15%** when a keyword is selling AND profitable (lagged 1-week net ROAS
    ≥ 1.1), capped at the band's max CPC.
23. **PROBE +5%** when a target has fewer than 4 clicks — not enough evidence to judge.
24. **HOLD** everything else. Order-bearing windows end at today−4 (attribution lag);
    click-only counters stay fresh.
25. Checkpoint rows appended mid-month enter your normal review queue individually —
    the machine proposes, you accept/reject, dated bulksheets execute.

## Part 7 — Launches (no data yet)

26. A launch cell starts from the **family prior** CVR (the ladder in rule 4 does this
    automatically) at the family-prior bid, and PROBES. No OFF, no cuts for 20 days.
27. **Admission**: ≥100 clicks AND CVR ≥ the family prior → the cell earns a permanent
    grid campaign. Fails → auto-reject, budget goes elsewhere.
28. Launch keywords come from the Research page ranking, proposed inside the monthly
    plan as ADD_KEYWORD rows.
28a. **Launch phases** (`V_LAUNCH_OPTIMIZER`, per family × week; goals differ from regular
    campaigns): SETUP (wk 0–1, reviews + CVR validation) → RANK (wk 2–7, honeymoon:
    velocity/badges/organic, losses = launch investment, NO loss cuts) → EXIT (wk 8–11,
    taper bids to value, fix price/margin) → POST. Verdicts on complete weeks only:
    ON_TRACK / BEHIND / STALLED (units ≤90% of prior-3-week average AND absolute organic
    units flat). The cockpit shows phase, verdict, weekly budget recommendation, and the
    family's taper bid (70% of trailing-28d CVR × GP/order).
28b. **The coacher reacts**: when the optimizer says EXIT/POST or STALLED, targets that are
    not paying their way get **LAUNCH_TAPER** — bid walks down to the taper bid. This is
    the ONE sanctioned loss-driven cut on the launch track; profitable targets still RAISE.
28c. A launch includes **Video and Spotlight from day one** (Ori 2026-07-26): one SB video
    + one Spotlight per launch family, budget-capped inside the launch population (≤$20/day).
    A Spotlight is a **Store Spotlight**: 3 Store subpages shown side by side — families
    combined on purpose, each subpage with its own selling text — while the campaign's
    keywords and headline stay on one intent. The ad itself is built in the console
    (subpage picker); bulksheets only attach keywords afterwards.
28e. **The Store bridge is the launch weapon** (Ori 2026-07-26): a launch Spotlight bids
    the PROVEN best-selling keywords of two established families — terms that already
    convert across many products — and shows their subpages next to the new product's.
    The showcase carries the conversion; shoppers self-select into the new product.
    A Spotlight campaign is OWNED BY ITS INTENT, never by a product — the ad serves all
    three families it shows. Name = STORE-SPOTLIGHT (<intent>).
    This prices the click against the BLENDED value of all three subpages, so a launch
    with thin solo economics (Bunny $0.34/click alone) can afford head terms it could
    never buy directly. Keyword rule: bridge terms must have converted for ≥2 families
    at net ROAS ≥ 1.1; the two launch Spotlights never share a bridge term.
28f. **Customer-facing text never uses internal names** (Ori 2026-07-26): shoppers don't
    know "Lollibox" — they know "Confetti Surprise Ball". Every display name, headline,
    and subpage label in ads uses category/benefit selling text; internal family names
    live only in campaign names and the registry. Ratified mapping (Ori 2026-07-26):
    LolliBall → "Confetti Surprise Ball" · Lollibox → "8 gifts inside" · LolliME →
    "Girls Journal Set" · Bunny → "Plush Bunny Keychain" · Fresh → "Bath Gift Set" ·
    Bottle → "Truth or Dare Game".
28d. **margin_flag**: GP/order < $6 means no bid can ever work — the fix is price or
    bundle, never ads (LolliBall $3.31, Bunny $4.80).

## Part 8 — What the 2025 backtest tests (this session)

- **Cockpit test**: for each 2025 month, rebuild the model using ONLY data before that
  month, produce the band + bids, then check (a) did the advice match what you actually
  did, (b) did the realized ROAS land in the predicted band, (c) profit delta under a
  conservative counterfactual — OFF credit = the actual loss avoided; bid-cap credit =
  spend trimmed linearly; **raising-bid upside is never credited** (unverifiable).
- **Coach test**: 1,000 scenarios (strategy × intent × product × keyword), walked
  week by week through 2025 with the rules in Part 6; every NEGATE scored against the
  term's real forward tail (would-have-saved $), every RAISE against whether ROAS held,
  every PROBE against whether the term got clicks and converted.
- Cockpit and coach are scored **separately** — the cockpit is judged on months,
  the coach on weeks.

## Part 9 — Auto campaigns (the discovery layer, added 2026-07-25)

29. Auto campaigns join the system as **one discovery unit per product** — never intent
    cells (Amazon picks the queries, so an auto campaign cannot be steered to an intent).
30. Their **search-query traffic feeds the intent model** exactly like manual clicks
    (98% of it resolves to a verified intent — same as manual). Product-page (ASIN)
    placements have no search intent and stay OUT of the intent model.
31. Auto CVR runs 40–50% HIGHER than manual on the same intents — pooling is safe and
    slightly conservative for bids.
32. **The fence extends to auto**: every exact-owned term is negativeExact'd in the
    product's auto campaigns too. Auto explores, Exact exploits — auto may not skim
    owned winners (today it skims ~10% of its spend from them).
33. Auto budget is band-governed like any cell, using the product's blended value per
    click. Harvest flow: auto surfaces a term → term maps to an intent → graduates into
    that intent's Broad/Exact per the normal rules.

## Part 10 — Competitor campaigns (ASIN cells, added 2026-07-25)

34. A competitor cell = **product × targeted competitor ASIN**. Same math, one change of
    grain: value per click = target CVR × your GP/order; same four bands, same 70% target
    bid, same $2 ceiling.
35. The cell key is the **targeting expression** (`asin="B0..."`), never the search term —
    58% of competitor-PT "search terms" are just the ASIN (product-page placements).
36. The CVR prior for a new target = the parent's pooled competitor CVR (~6.5%), because
    an ASIN has no facets. Season index is borrowed from the account keyword curve
    (they move together, correlation 0.82).
37. Competitor brand KEYWORDS are not a segment (about $93/year) — ignore; brand-term
    doctrine (rule 17) already covers them. Own-ASIN defense targeting stays outside
    this system.
38. Admission gate is the same ≥100 clicks (97% of competitor spend already clears it);
    demotion = pause, never delete. Search-placement competitor traffic partially serves
    intent demand, so the ownership rules (rule 15) count competitor-PT campaigns as
    bidders when resolving term ownership.

**Stated simplifications**: GP/order is today's margin (assumed stable across 2025);
season pooling in the backtest skips the 90-day launch quarantine; the coach backtest
cannot simulate bids Amazon never ran — so it judges direction and timing, not exact
dollar paths.
