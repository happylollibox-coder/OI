# Family Seat Register — implementation plan

Spec: `docs/superpowers/specs/2026-08-22-family-seat-register-design.md` (Approach A, approved
2026-08-22). Standing rules: SOP first · Standing Rule 0 (mechanism in prose, queries for numbers) ·
register every object in `config.yaml` (parses, no duplicate names, never append at the end) · deploy
with `bq query --nouse_cache "$(grep -v '^--' FILE)"`, never `cat` · back up before deploy · stage
only the task's files · tree clean · a task's code block is a RECORD once shipped.

STATUS (2026-08-23, warehouse clock): ALL FIVE TASKS DONE — shipped, deployed, verified, and the
first production night has run (two orchestrator passes on 2026-08-23, New York clock, every step
`OK`; `SP_MAINTAIN_FAMILY_SEATS` logged in both; the ledger closed its first real seats with the
mapped codes and sentences). Commits (read `git log`, not this line, for the repair passes between):
Task 1 `a45992d` (repairs `e553f96`, `1521672`, `9334bce`) · Task 2 `7ccafda` (repairs `942c3ed`,
`41bdb93`, `aaa519e`, `2f70827`, R-l passes `bcbb0af` … `1947572`, `899172e`) · Task 3 `492bea8`
(`f69e2b4`, `cda9581`, `88dad93`) · Task 4 `7a2b85a` (`99440f9`, `fa373f2`, `fc39d52`) · Task 5: the
commit that carries this STATUS line (SOP restructured as the document a new user reads first;
`V_ENGINE_HEALTH` v27.127 `seat_*` checks). Each task was TDD (assertion fails first, passes after)
with three-lens adversarial review before the next task started. Implementer self-reports contained
false claims in nearly every round of this project — verifiers re-derive, never trust. Open for
Ori, never decided here: SOP "Open rulings for Ori" items 7, 8, 9, 21 (the park source), 22 (the
overdue-settling ladder fix).

---

## Task 1 — `DE_FAMILY_SEAT_LEDGER` (seat numbers that survive the night)

**DONE `a45992d`.**

**Why:** a seat number means nothing if it changes every morning. The ledger is the only state the
register keeps.

- DDL: `family, campaign_id STRING, keyword_id STRING, seat_no INT64, opened_on DATE,
  closed_on DATE, closed_reason STRING, occupant_kind_at_open STRING`. Key (family, campaign_id,
  keyword_id, opened_on). Registered in `config.yaml` under tables.
- `SP_MAINTAIN_FAMILY_SEATS`: reads today's occupants from `FACT_KEYWORD_STATE` (+ spend basis),
  assigns the **lowest free `seat_no`** per family to a new occupant, keeps numbers for continuing
  occupants, closes rows whose keyword left the occupant set with the reason (`TO_GOOD_SIDE`,
  `KILLED`, `PAUSED`, `LEFT_FAMILY`). Idempotent: running twice on the same day changes nothing.
- Orchestrator: called right after `SP_SNAPSHOT_KEYWORD_STATE` (Task 20.8 → 20.8b).
- **Acceptance:** run → rerun → ledger identical; a synthetic occupant added → gets the lowest free
  number; removed → row closed with reason, number reusable; no launch-family rows.

## Task 2 — `V_FAMILY_SEAT_REGISTER` (the object Ori reads)

**DONE `7ccafda`.**

- FAMILY / SEAT / LEAK / GAP / REFERENCE rows exactly as spec §4. Declared constants in a `k` CTE:
  `allowance_share 0.20`, `at_line_band` (derive from the 7-day spend noise of the smallest
  working family — publish the derivation), `basis_days 7`, `context_days 28`.
- Category mapping per spec §3; the probe test reads the keyword's bid against `V_BID_FLOOR` /
  the park bid as the engine defines it (never a literal 0.25).
- Seat cost = the occupant's 7-day spend ÷ 7; probe admission cost from `V_OOB_KEYWORD`'s seat
  economics (read the published `seat_cpc` and slots; never restate).
- Horizons: `today`, `day_one` (apply the current book's `new_bid/old_bid` to occupants' spend,
  closed leaks → 0), `rejudged` (repairs at their affordable price → marginal; probation → floor;
  published with `horizon_assumption` text). Carry `as_of`.
- Absorption line: an above-bar campaign in the family with `days_capped_7d ≥ 4`
  (`V_CAMPAIGN_CAP_STATE`), advisory text only.
- Holdout marker from `DE_HOLDOUT_ASSIGNMENT` on every SEAT/LEAK row.
- Plain-sentence `verdict` on every row; no codes. Reasons follow TRIGGER — EVIDENCE ⇒ MOVE.
- **Planner:** reads `FACT_KEYWORD_STATE`, `T_FAMILY_BAR`, `FACT_AMAZON_ADS`, `DE_FAMILY_SEAT_LEDGER`,
  `V_CAMPAIGN_CAP_STATE` (measure it — if heavy, read its T_), `DE_HOLDOUT_ASSIGNMENT`. Never a
  ceiling view. Dry-run before/after, report bytes and wall time.
- **Acceptance (all asserted, all must fail before the view exists):** categories sum to family
  spend basis to the cent; SEAT+LEAK+GAP = bad side; every spending keyword in a working family on
  exactly one side; exactly one `seat_no` per occupant; zero launch-family FAMILY rows; zero
  brand-defense keywords with a move; determinism (two uncached pulls, all rows, identical MD5).

## Task 3 — the LEAK generator arm

**DONE `492bea8` — shipped as the sibling `tools/build_seat_moves_bulksheet.py` (the argument is in its docstring and the SOP).**

- Extend `tools/build_reprice_bulksheet.py` (or a sibling `build_seat_moves_bulksheet.py` if the
  file would exceed its readable size — argue which) with **pause rows for closed-but-spending
  keywords** and **ad-group-grain negates for leaking search terms** under parked keywords.
  Acting-grain rule: a negate needs the ad group's own record losing over the window and lifetime
  (the `V_ADS_COACH` block-grain standard). Holdout excluded from eligible_from. Batch logged
  `PENDING_UPLOAD`; restore generator covers pause rows (re-enable) and negates (cannot be undone by
  sheet — say so in the README).
- **Acceptance:** every LEAK row in the register maps to exactly one sheet row or one stated
  no-action reason; zero holdout rows; zero negates on terms profitable at ad-group grain.

## Task 4 — the morning surface

**DONE `7a2b85a`.**

- One line per working family into `V_DAILY_BRIEF` (new section `SEATS`) and a `SeatRegister` cube;
  `V_RUN_SUMMARY` gains the doctrine status per family. Label CASEs learn every category; nothing
  falls through to blank.
- `config.yaml` descriptions describe the mechanism only.
- **Acceptance:** each consumer renders all categories; brief line reconciles to the register.

## Task 5 — SOP + health

**DONE — the commit carrying this STATUS line.**

- `architecture/FAMILY_SEAT_REGISTER.md`: the doctrine, the rulings table from the spec, the seat
  lifecycle, the daily loop, the holdout rule, what the register never does.
- `V_ENGINE_HEALTH` checks: reconciliation gap 0; ledger idempotence; every occupant numbered.

## Review gates (after every task)

Three adversarial lenses, independent, re-deriving from live data: **numbers** (reconciliation,
determinism, horizons re-derived on five families/rows), **doctrine** (no launch or defense row
judged on profit, sides per ruling, seat stability, holdout), **read** (every sentence aloud as a new
user; counts reconcile wherever they appear; Standing Rule 0 sweep).

## Out of scope (deliberately)

Budget moves (shown, never made) · any engine reading the register · changes to the ladder, bar or
floors · the launch families' governance (`V_INVEST_STATUS` owns it).
