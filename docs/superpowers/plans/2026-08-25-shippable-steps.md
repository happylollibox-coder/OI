# Shippable steps — small, verifiable, mostly uploadable

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` or
> `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** get real actions onto Amazon in small slices, each one verifiable before the next begins.

**Ori's constraint, 2026-08-25:** *"every step is small but with results that can be verified before
continuing to next step (for example if I can upload a few actions after a step this is good)."*

**Architecture:** every step either (a) unlocks a **new kind of action** you can upload, or (b) adds a
**check that makes an existing kind safe**. Nothing here is a refactor with no visible result. Doctrine:
`architecture/THREE_LAYERS.md`. Book SOP: `architecture/WEEKLY_BOOK.md`.

**The ordering rule:** *soonest uploadable first, except where a check must precede the money it guards.*
That is why Step 2 (a check) sits between Step 1 and Step 3 (both uploads).

---

## The arc at a glance

| step | what it adds | uploadable after? | size |
|---|---|---|---|
| **1** | Fresh bids + pauses, no budgets | **yes — 19 rows today** | minutes |
| **2** | The budget-carry check (violation 28) | no — it guards step 3 | half a day |
| **3** | Budget rows, bounded slice | **yes — the small movers** | half a day |
| **4** | A seat names N clicks by date D (violation 27) | no — makes requests gradeable | 1 day |
| **5** | The request ledger, write arm (§6.0) | no — records what was asked | 1 day |
| **6** | The delivery grade + out-of-budget read-back (29) | no — first real answer to "is this working" | 1–2 days |
| **7** | Negative removal rows (violation 25) | **yes — a new action type** | half a day |
| **8** | Campaign history joined on id (violation 23) | no — gates step 9 | 1–2 days |
| **9** | Campaign open/close with reopen dates (violation 22) | **yes — the dated seasonal chain** | 3–5 days |
| **10** | Market volume reaches the Catalog (violations 4, 21) | no — `expected_clicks` becomes real | 3–5 days |

---

## Step 1 — Upload today's bids and pauses

**Goal:** 19 real rows on Amazon, from the new book, with a logged batch.

**Why now:** nothing is blocking it. The staleness and the missing batch were both *how I built the
draft*, not defects. The action vocabulary was a defect and is fixed (`c9d3122`).

**Files:** none changed. This step is a run.

- [ ] **1.1 Build fresh, budgets excluded, batch logged**

```bash
/usr/bin/python3 tools/build_weekly_book.py --no-budgets -o .tmp/weekly_book_$(date +%Y%m%d).xlsx
```

Expected: `tiers -> CATALOG 2, BRAIN 0, PACING 17` (counts will differ — the shape will not), and a
line reading `logged NN rows as batch weekly_book_YYYYMMDD_HHMMSS (PENDING_UPLOAD)`.
**No `--reuse-stage`** — the sources must run fresh so the prices match what the ladder knows today.

- [ ] **1.2 Verify before opening Amazon**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=pretty "SELECT action, COUNT(*) n, upload_status FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\` WHERE batch_id = 'PASTE_BATCH_ID' GROUP BY 1,3 ORDER BY n DESC"
```

Expected: only `INCREASE_BID`, `REDUCE_BID`, `KEYWORD_PAUSE`; every row `PENDING_UPLOAD`; the total
equals the row count the build printed. **If any action string is not one of those three, stop** — that
is the synonym defect returning.

- [ ] **1.3 Read the `Explained` sheet, then upload the two Amazon sheets by hand**

- [ ] **1.4 Close the loop**

```bash
/usr/bin/python3 tools/build_weekly_book.py --mark-uploaded PASTE_BATCH_ID
```

If you decide **not** to upload it, label it instead — never delete:
`--supersede PASTE_BATCH_ID`.

**Verified when:** the batch reads `NULL` upload_status (applied) and Amazon shows the new bids.

---

## Step 2 — The budget-carry check

**Goal:** the book refuses to raise a bid inside a campaign whose budget it is cutting, unless you say so.

**Why now:** violation 28. Measured 2026-08-25 — the same book cut `BOX-SP/EXACT (teen-girl-gift,
White 2)` from $20.48 to $13.94/day (−32%) while raising `teen girl gifts` from $0.72 to $0.83 inside it.
Neither row is wrong alone. Together they are a request the budget may not be able to carry, and **the
book's conflict detection deliberately does not relate them** — `test_campaign_and_keyword_rows_are_not_a_conflict`
asserts they are not a conflict, which is right in principle and insufficient in practice.

**Files:**
- Modify: `tools/build_weekly_book.py` — new `budget_carry_check()`, called from `resolve()`
- Modify: `tools/tests/test_weekly_book_preflight.py`
- Modify: `architecture/WEEKLY_BOOK.md` §3

- [ ] **2.1 Write the failing test**

```python
def test_bid_raise_inside_a_budget_cut_is_surfaced():
    """Not a conflict — the tiers are doing their own jobs — but the reader must SEE the pair."""
    budget = {'source': 'plan-budgets', 'sheet': w.SP_SHEET, 'cells': {},
              'audit': {'campaign_id': '9', 'keyword_id': '', 'disposition': 'BUDGET_DOWN',
                        '_old_budget': 20.48, '_new_budget': 13.94, 'campaign': 'C'}}
    bid = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
           'audit': {'campaign_id': '9', 'keyword_id': '77', 'disposition': 'BID_UP',
                     'old_bid': '0.72', 'new_bid': '0.83', 'target': 'kw', 'campaign': 'C'}}
    notes = w.budget_carry_check([budget, bid])
    assert len(notes) == 1
    assert notes[0]['campaign_id'] == '9'
    assert 'cut' in notes[0]['note'].lower()
```

- [ ] **2.2 Run it; expect `AttributeError: module has no attribute 'budget_carry_check'`**

```bash
/usr/local/bin/python3 -m pytest tools/tests/test_weekly_book_preflight.py -q -k budget_carry
```

- [ ] **2.3 Implement `budget_carry_check(records)`**

One note per campaign that carries **both** a `BUDGET_DOWN` row and at least one `BID_UP` row, stating
the budget move, the count of bid raises inside it, and their summed implied daily spend at the new bids.

- [ ] **2.4 Surface it — a `Budget carry` block on the `Conflicts` sheet**, and a README line. It is a
      **warning, not a refusal**: the pair may be intended, and refusing would make the book undeliverable
      for a legitimate rebalance.

- [ ] **2.5 Re-run the suite; expect all green, then commit**

**Verified when:** a build over today's data prints at least one carry note, and the `BOX-SP/EXACT` pair
is one of them.

---

## Step 3 — Budget rows, bounded

**Goal:** upload the budget changes that are small enough not to need an argument; hold the rest.

**Why now:** the 44 rows net to **+$78.41/day (+5.3%)**, which sounds mild and hides that **seven
campaigns move more than ±50%**, the largest **+127% ($70 → $159/day)**. A first upload of a brand-new
action type should not contain a 127% move.

**Files:** `tools/build_weekly_book.py` (new `--budget-max-move` flag), tests, SOP.

- [ ] **3.1 Test: a move beyond the cap is routed to `Refused`, not dropped silently**
- [ ] **3.2 Implement `--budget-max-move PCT` (default 0.25)**, with the excluded rows landing on the
      `Refused` sheet carrying `over the ±25% cap for a first budget upload — decide it explicitly`.
- [ ] **3.3 Build with budgets, cap on:**

```bash
/usr/bin/python3 tools/build_weekly_book.py --budget-max-move 0.25 -o .tmp/weekly_book_$(date +%Y%m%d)_b.xlsx
```

- [ ] **3.4 Verify the net daily change is small and reconciles**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=pretty "SELECT COUNT(*) n, ROUND(SUM(new_bid - old_bid),2) AS net_daily_change FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\` WHERE batch_id = 'PASTE_BATCH_ID' AND action = 'BUDGET_CHANGE'"
```

- [ ] **3.5 Upload, `--mark-uploaded`, then read the 7 held rows and decide them by hand**

**Verified when:** budget rows are live, and 7 days later `V_OOB_BUDGET_PHASE.pct_dark` has not risen on
the campaigns that were cut.

---

## Step 4 — A seat names its question

**Goal:** every funded seat carries **how many clicks, by what date** — violation 27.

**Why now:** §3.0 step 2. Until a seat says "40 clicks by 2026-09-08", no request can be graded, and
Steps 5 and 6 have nothing to grade against. This is the smallest change that makes the whole ledger
possible.

**Files:**
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` — add `clicks_requested`,
  `clicks_due_date`, `expected_cpc`, `implied_daily_spend`
- Modify: `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` + a migration (the table is
  `CREATE TABLE IF NOT EXISTS`, so columns ship as an explicit `ALTER`)
- Modify: `config.yaml`
- Create: `scripts/bigquery/tests/PLAN_SEAT_REQUEST_acceptance.sql`

- [ ] **4.1 Acceptance first, failing:** every `is_candidate` row has a non-null click target, a due date
      in the future, and `implied_daily_spend = clicks_requested × expected_cpc ÷ days`
- [ ] **4.2 Migration adds the four columns; deploy; expect the acceptance to still fail on NULLs**
- [ ] **4.3 Populate them in `SP_BUILD_NEXT_WEEK_PLAN`**, from the seat's dollars and the subject's
      settled CPC — no new economics, just naming what the dollars already imply
- [ ] **4.4 Re-run acceptance; expect every check 0 violations**

**Verified when:** `SELECT clicks_requested, clicks_due_date FROM FACT_PLAN_NEXT_WEEK WHERE is_candidate`
returns no NULLs, and the numbers re-derive from the seat dollars by hand on three spot-checked rows.

---

## Step 5 — The request ledger, write arm

**Goal:** the Brain records what it asked for — §6.0.

**Files:**
- Create: `scripts/bigquery/tables/FACT/FACT_SEAT_REQUEST.sql` — append-only, partitioned by
  `requested_on`; one row per funded seat carrying subject, clicks, due date, expected CPC, implied daily
  spend, the campaign that must carry it, and the Catalog claim (`verdict`, `roas`, `bar`) it was bought on
- Create: `scripts/bigquery/procedures/SP_APPEND_SEAT_REQUEST.sql`, wired at orchestrator Task 20.8d
- Modify: `config.yaml`, `architecture/THREE_LAYERS.md` §6.0

- [ ] **5.1 Acceptance first:** one row per funded seat per window; no row ever mutated; every row
      carries the Catalog claim it was bought on
- [ ] **5.2 Build the table and the append step; run it twice in one session and prove the second call
      adds nothing** (the house rule after the 2026-08-24 cube outage)
- [ ] **5.3 Wire into the orchestrator inside the house `BEGIN ... EXCEPTION` block, so it can never
      break a pass**

**Verified when:** a night runs and `FACT_SEAT_REQUEST` holds one row per funded seat, and a second
manual `CALL` changes nothing.

---

## Step 6 — The delivery grade

**Goal:** the first honest answer to *is this working* — §6.0's closing half, and violation 29.

**Files:**
- Create: `scripts/bigquery/views/V_SEAT_REQUEST_OUTCOME.sql` — joins each request to what actually
  happened: clicks delivered vs requested, CPC actual vs expected, the window's return vs the Catalog's
  claim, and `pct_dark` / `days_capped_7d` from `V_OOB_BUDGET_PHASE` for the campaign that carried it
- Create: `scripts/bigquery/tests/SEAT_REQUEST_OUTCOME_acceptance.sql`

- [ ] **6.1 Acceptance first:** a request whose window has not closed reads `PENDING`, never a grade;
      no grade is published without both a request and an outcome
- [ ] **6.2 Implement the three grades — Catalog (claim vs actual), Pacing (clicks delivered vs asked),
      campaign (out-of-budget %, target zero)**
- [ ] **6.3 Publish a one-line sentence per request**, the way `V_UNOWNED_SPEND` does

**Verified when:** the first closed window produces three grades you can read, and a deliberately
under-delivered seat reads as a Pacing miss rather than a Catalog one.

---

## Step 7 — Remove a negative by bulksheet

**Goal:** a new uploadable action type — violation 25.

**Why now:** independent of everything above, small, and it closes the Catalog's `improve()` loop: the
Catalog can already say *un-negate this*, and no book can carry the answer. `negative_id` is populated on
all 9,684 live negatives and one removal has already executed by hand, so the platform accepts it.

**Files:** `tools/build_seat_moves_bulksheet.py` (a `REMOVE_NEGATIVE` row builder emitting
`Entity: Negative Keyword`, `Operation: Update`, `State: archived`), tests, SOP.

- [ ] **7.1 Test: the row carries `negative_id` and `State: archived`, and never `Operation: Create`**
- [ ] **7.2 Implement; build a book containing exactly one removal; upload it; verify in Amazon**

**Verified when:** one negative is archived on Amazon and the change log carries the row.

---

## Step 8 — Join campaign history on the id

**Goal:** violation 23, and the prerequisite for Step 9.

**Why now:** 53 real campaign ids carry more than one name, covering **46.7% of real-id lifetime spend**,
and 6 names are each shared by two ids, merging $68,126. Any seasonal reading by name is wrong.

**Files:** every view joining campaign history on `campaign_name` — enumerate with
`grep -rln "campaign_name" scripts/bigquery/views/ | xargs grep -l "JOIN"` and fix each.

- [ ] **8.1 Build a report-only `V_CAMPAIGN_NAME_DRIFT`** listing every id with >1 name and every name
      with >1 id, with the spend each mis-joins
- [ ] **8.2 Fix the joins one view at a time**, re-running that view's acceptance after each
- [ ] **8.3 Record the `-1` sentinel hole** — $32,773 spend and $91,733 sales in last season carry no
      campaign identity at all and **this step does not recover them**

**Verified when:** `V_CAMPAIGN_NAME_DRIFT` is published and no production view joins campaign history on
a name.

---

## Step 9 — Campaigns become subjects, with reopen dates

**Goal:** violation 22 and the dated seasonal chain — a new uploadable action type.

**Why now:** the deadline. 13 reopenable campaigns hold $184,689 of last-season sales; you are doing 2026
by hand (`REOPEN_CAMPAIGNS_20260825.md`). This builds the machine for 2027 and for every campaign after.

**Files:** `scripts/bigquery/views/V_CAMPAIGN_SEASON_VERDICT.sql`, a `DE_CAMPAIGN_REOPEN_DATE` table, and
campaign `State`/`End Date` rows in `build_weekly_book.py`.

- [ ] **9.1 The Catalog answers for a campaign subject** — `WORTH` / `NOT_WORTH_NOW · reopen D` /
      `UNKNOWN`, with lead time in the answer
- [ ] **9.2 A pause may only ship carrying its reopen date** — acceptance refuses a `CLOSE` without one
- [ ] **9.3 `OPEN · by date D` rows in the book**, including the `ENABLED`/`ENDED` case, which needs an
      `End Date` change and not a state change

**Verified when:** the book proposes a reopen for a campaign whose season is approaching, carrying a date
you can argue with.

---

## Step 10 — Market volume reaches the Catalog

**Goal:** violations 4 and 21, and `expected_clicks` stops meaning *our own history*.

**Why now:** `FACT_RESEARCH_RANKED` already holds it (§8.1). `teen girl gifts` runs **5,536 market clicks
and 400 purchases a week**; our settled take is 112 clicks in 90 days — **0.16%**. No layer can see that.

**Files:** `scripts/bigquery/views/V_CATALOG_MARKET_VOLUME.sql`, `SP_SNAPSHOT_KEYWORD_STATE.sql`.

- [ ] **10.1 One term, one verdict** — the non-negotiable acceptance condition. 291 of 649 owned subjects
      are ranked by both modules against different standards; publishing both is forbidden
- [ ] **10.2 Demand data may never move a verdict to `WORTH` on its own** (§2.3) — it sizes the
      opportunity, it does not prove it
- [ ] **10.3 Put it on probation** — the Catalog distrusts SQP until it earns trust, with the four
      recorded grounds

**Verified when:** the Catalog publishes a headroom figure per subject and no subject carries two verdicts.

---

## Rules that hold across every step

1. **Never delete a change-log row.** Label it. `PENDING_UPLOAD` → `--mark-uploaded`, or
   `SUPERSEDED_NEVER_UPLOADED`.
2. **Ori uploads.** No step uploads to Amazon.
3. **Failing test first, with a measured violation count**, then the fix, then the count at zero.
4. **A new BigQuery object is registered in `config.yaml`** in the same commit.
5. **Back up before deploying:** `FILE.bak.v27.NN.HHMM`.
6. **Publish the query, not the number** (Standing Rule 0).
7. **Holdout campaigns are untouchable from 2026-09-01.**
8. **If a step's verification fails, stop.** The next step assumes the previous one is true.
