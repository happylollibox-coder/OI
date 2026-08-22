-- =============================================
-- DE_FAMILY_SEAT_LEDGER — the seat numbers that survive the night. Spec: architecture/FAMILY_SEAT_REGISTER.md.
--
-- WHAT A SEAT IS. For a WORKING family (the HARVEST book in V_BOOK_ASSIGNMENT — never a launch),
-- a seat is a dollar-sized slot inside the family's 20% allowance, occupied by ONE keyword the
-- family is knowingly paying for while it is repaired (REPRICE), on probation at its floor
-- (FLOOR_PROBATION), failed (LOSER), probed (a TRIAL keyword bought at an entry bid — on the
-- engine's probe list T_LIFT_PROBES, spend or no spend — or at the park bid — the ladder's
-- at_floor, with spend), a STALLED probe (a TRIAL keyword whose latest applied bid change is an
-- INCREASE_BID that still stands — live bid at or above the logged new_bid, never lowered since —
-- past the engine's probe window with fewer than the verdict's clicks since, and no longer on the
-- engine's list — a test that cannot produce a verdict at its pace is a seat with a standing
-- proposal, not "waiting for results"), or waiting for a verdict
-- to settle (REVIVED_SETTLING, PENDING_SETTLE). A brand-defense keyword is never seated:
-- defense is never judged on profit, and a seat is a profit judgment. Ori, verbatim: "number them
-- per family so you always know what seat you are opening and what you are probing or waiting
-- for results".
--
-- WHY A TABLE. A seat number means nothing if it changes every morning. V_FAMILY_SEAT_REGISTER
-- re-derives everything else from today's snapshots; the NUMBER is the one thing that must be
-- remembered, so it lives here. One row per OCCUPANCY: (family, campaign_id, keyword_id,
-- opened_on). An open occupancy has closed_on NULL. A keyword that leaves the occupant set gets
-- its row CLOSED with a reason code (TO_GOOD_SIDE | TO_WAITING | KILLED | PAUSED | LEFT_FAMILY |
-- DEFENSE_EXEMPT | STATE_CHANGED — the last names the new state in plain words), the same reason as a plain sentence (closed_reason_text), and its number
-- becomes free; the next admission takes the LOWEST free number in the family, so the register
-- can read "seat 4 (open)". A keyword that returns later is a NEW occupancy and may get a
-- different number — numbers are stable for as long as the keyword stays seated, not forever.
--
-- WHY THE LEDGER REMEMBERS THE LAST VERDICT. FACT_KEYWORD_STATE is CREATE OR REPLACE'd by
-- SP_SNAPSHOT_KEYWORD_STATE every run and holds exactly ONE snapshot. A keyword still on it
-- carries prior_state (the snapshot procedure reads the old table before replacing it); a
-- keyword that has VANISHED from the snapshot (paused or archived in Amazon) has no row at all —
-- and that vanish is exactly the KILLED-vs-PAUSED question. The ledger keeps last_observed_kind /
-- last_observed_state, refreshed on every run while the row is open, as the only memory for a
-- vanished keyword; KILLED vs PAUSED is decided from them.
--
-- WRITTEN BY: SP_MAINTAIN_FAMILY_SEATS (orchestrator Task 20.8b, immediately after the keyword
-- state snapshot 20.8 it reads). Idempotent: a second run on the same snapshot changes nothing.
-- READ BY: V_FAMILY_SEAT_REGISTER (the seat_no on every SEAT row). NO ENGINE reads it.
-- ids are STRING end to end (19-digit Amazon ids exceed 2^53).
-- Columns added after first ship are appended with ALTER TABLE ... ADD COLUMN IF NOT EXISTS so a
-- redeploy of this file is idempotent on the live table.
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` (
  family                STRING NOT NULL,  -- the working family (HARVEST book) that owns the seat
  campaign_id           STRING NOT NULL,  -- campaign_id AS STRING
  keyword_id            STRING NOT NULL,  -- keyword_id AS STRING
  seat_no               INT64  NOT NULL,  -- the family's seat number; unique among OPEN rows of a family
  opened_on             DATE   NOT NULL,  -- the keyword-state snapshot date the occupancy was admitted on
  closed_on             DATE,             -- NULL while the keyword is seated
  closed_reason         STRING,           -- TO_GOOD_SIDE | TO_WAITING | KILLED | PAUSED | LEFT_FAMILY | DEFENSE_EXEMPT | STATE_CHANGED (NULL while open)
  occupant_kind_at_open STRING NOT NULL,  -- repair | probation | failed | probe | stalled probe | settling — what the seat held on admission
  last_observed_kind    STRING,           -- the occupant kind on the latest snapshot the row was open on (refreshed every run)
  last_observed_state   STRING,           -- the ladder state on that snapshot — decides KILLED vs PAUSED when the keyword vanishes
  closed_reason_text    STRING            -- closed_reason as one plain sentence (NULL while open)
)
CLUSTER BY family, campaign_id, keyword_id
OPTIONS (description = 'Seat numbers for the family seat register — one row per occupancy (family, campaign_id, keyword_id, opened_on) of a keyword inside the 20% allowance of a WORKING family (HARVEST book only; launches never appear). Occupants: REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), a TRIAL keyword at an entry bid (engine probe list T_LIFT_PROBES, spend or not) or at the park bid (ladder at_floor, with spend in the basis window) (probe), a TRIAL keyword whose latest applied bid change is an INCREASE_BID that still stands (live bid at or above the logged new_bid, never lowered since) past the engine probe window with fewer than the verdict clicks since and no longer engine-listed (stalled probe), REVIVED_SETTLING / PENDING_SETTLE (settling); brand-defense keywords never seated. seat_no is assigned on admission as the LOWEST number not held by an open row of the family and is kept for as long as the keyword stays an occupant, whatever its kind becomes; last_observed_kind / last_observed_state are refreshed on every run while the row is open (FACT_KEYWORD_STATE holds one snapshot; a keyword still on it carries prior_state, but a keyword that vanished has no row, and the ledger is the only memory for it); when the keyword leaves the occupant set the row is closed with closed_on, closed_reason and closed_reason_text (KILLED = dead, or gone from the snapshot after a LOSER/DEAD last observed state; PAUSED = parked, or gone otherwise; LEFT_FAMILY = the campaign now maps to another family or the family left the HARVEST book; DEFENSE_EXEMPT = now brand defense; TO_GOOD_SIDE = winning or at its bar; TO_WAITING = still TRIAL but at neither an entry nor a park bid and not stalled; STATE_CHANGED = any other state, named in plain words in closed_reason_text) and the number is free for the next admission. Maintained by SP_MAINTAIN_FAMILY_SEATS (orchestrator Task 20.8b, right after SP_SNAPSHOT_KEYWORD_STATE); idempotent on the same snapshot. Read by V_FAMILY_SEAT_REGISTER only; no engine reads it. Spec: architecture/FAMILY_SEAT_REGISTER.md.');

ALTER TABLE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  ADD COLUMN IF NOT EXISTS last_observed_kind  STRING OPTIONS (description = 'the occupant kind (repair | probation | failed | probe | stalled probe | settling) on the latest snapshot the row was open on; refreshed every run'),
  ADD COLUMN IF NOT EXISTS last_observed_state STRING OPTIONS (description = 'the ladder state on the latest snapshot the row was open on; decides KILLED vs PAUSED when the keyword vanishes from the snapshot'),
  ADD COLUMN IF NOT EXISTS closed_reason_text  STRING OPTIONS (description = 'closed_reason as one plain sentence; NULL while the seat is open');
