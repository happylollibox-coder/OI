-- DE_LAUNCH_INVESTMENT seed — the two sanctions on record as of 2026-08-13 (Ori's launch-exemption
-- brief, transcribed verbatim: "Bunny $30/day through October, LolliBall $55/day through November,
-- both with dated stop gates").
--
-- MERGE, not INSERT: re-running must not duplicate. To RE-sanction (new amount or a later date),
-- edit the values here and re-run, or INSERT a fresh row with a newer updated_at — V_LAUNCH_EXEMPTION
-- takes the latest row per family.
MERGE `onyga-482313.OI.DE_LAUNCH_INVESTMENT` T
USING (
  SELECT 'Bunny'     AS parent_name, 30.0 AS daily_investment, DATE '2026-10-31' AS stop_date,
         DATE '2026-08-13' AS sanctioned_on,
         'Sanctioned launch investment $30/day through October 2026. Bunny first sold 2026-05-24 (3 months old) — a launch family is SUPPOSED to lose money while the right bid is found; bleed control is search-term negation, never a budget loss-cut.' AS note
  UNION ALL
  SELECT 'LolliBall', 55.0, DATE '2026-11-30', DATE '2026-08-13',
         'Sanctioned launch investment $55/day through November 2026. LolliBall first sold 2026-06-26 (2 months old) — a launch family is SUPPOSED to lose money while the right bid is found; bleed control is search-term negation, never a budget loss-cut.'
) S
ON T.parent_name = S.parent_name
WHEN MATCHED THEN UPDATE SET
  daily_investment = S.daily_investment,
  stop_date        = S.stop_date,
  sanctioned_on    = S.sanctioned_on,
  note             = S.note,
  updated_at       = CURRENT_TIMESTAMP(),
  updated_by       = 'launch_exemption_v27.56'
WHEN NOT MATCHED THEN INSERT
  (parent_name, daily_investment, stop_date, sanctioned_on, note, updated_at, updated_by)
VALUES
  (S.parent_name, S.daily_investment, S.stop_date, S.sanctioned_on, S.note, CURRENT_TIMESTAMP(), 'launch_exemption_v27.56');
