#!/usr/bin/env python3
"""One-off: classify ENABLED-but-unmapped campaigns (dormant, so never surfaced by
V_CAMPAIGN_MAPPING_STATUS which only lists spending campaigns). Replicates the Admin
Campaign Mapping panel's assign_campaign_mapping() exactly: resolve experiment_id the
same way SP_AUTO_ASSIGN_CAMPAIGNS does, MERGE DIM_EXPERIMENT (+strategy) and
DIM_EXPERIMENT_CAMPAIGN. Also writes a DE_CAMPAIGN_FAMILY override so the family
attributes immediately (V_CAMPAIGN_FAMILY_MAP: override wins over advertised-ASIN).

Run:  data-entry-app/venv/bin/python tools/classify_campaigns.py --apply
Dry-run (default) prints the resolved experiment_ids without writing.
"""
import re
import sys
from datetime import date
from google.cloud import bigquery

PROJECT = "onyga-482313"
client = bigquery.Client(project=PROJECT)

_STRATEGY_LABEL = {
    'EXACT_BOOST': 'Exact Boost', 'INTENT': 'Broad Hunter',
    'INTENT': 'Auto Discovery', 'BRAND_DEFENSE': 'Brand Defense',
    'PRODUCT_DEFENSE': 'Product Defense', 'COMPETITOR': 'Competitor Conquest',
    'COMPETITOR': 'Category Conquest',
}

# (campaign_id, family, strategy) — determined from targeting terms (2026-07-09).
MAPPINGS = [
    ("346092157651715", "Lollibox", "COMPETITOR"),  # BOX- VIDEO (competitors-white) — reactivated
    ("493311842154449", "Lollibox", "INTENT"),               # BOX- VIDEO/BROAD (White) — generic gift terms
    ("558531709135233", "Lollibox", "INTENT"),               # BOX- VIDEO/PHRASE (Blue) — generic gift terms
    ("316780011343668", "Lollibox", "INTENT"),               # BOX-STORE/PHRASE — generic gift terms
]


def build_experiment_id(family, strategy, campaign_name):
    fam_token = re.sub(r'[^A-Z0-9]', '', family.upper())
    theme = None
    m = re.search(r'\((?:Boost, ?)?(.+?)\)', campaign_name or '')
    if m:
        theme = m.group(1)
    theme_token = re.sub(r'[^A-Z0-9]', '_', (theme or 'GENERAL').upper())
    return f"{fam_token}_{strategy}_{theme_token}", theme


def resolve_name(cid):
    rows = list(client.query(
        "SELECT campaign_name FROM `onyga-482313.OI.DIM_CAMPAIGN` "
        "WHERE campaign_id=@cid AND is_current=TRUE LIMIT 1",
        job_config=bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('cid', 'STRING', cid)])).result())
    return rows[0].campaign_name if rows else None


def dup_ec_rows(cid):
    r = list(client.query(
        "SELECT COUNT(*) n FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` WHERE campaign_id=@cid",
        job_config=bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('cid', 'STRING', cid)])).result())
    return r[0].n


def apply_one(cid, family, strategy, do_write):
    name = resolve_name(cid)
    if not name:
        print(f"  !! {cid}: campaign not found (is_current) — skip"); return
    eid, theme = build_experiment_id(family, strategy, name)
    ename = f"{family} - {_STRATEGY_LABEL.get(strategy, strategy)}" + (f" ({theme})" if theme else "")
    ndup = dup_ec_rows(cid)
    print(f"  {name!r}\n    -> experiment_id={eid}  ({ename})  [existing EC rows: {ndup}]")
    if not do_write:
        return
    note = f"manual: classify_campaigns.py {date.today().isoformat()}"
    # 1. experiment (idempotent create)
    client.query("""
      MERGE `onyga-482313.OI.DIM_EXPERIMENT` T USING (SELECT @eid AS experiment_id) S
      ON T.experiment_id=S.experiment_id
      WHEN NOT MATCHED THEN INSERT
        (experiment_id, experiment_name, description, start_date, baseline_days,
         status, strategy_id, lifecycle_stage, season_context, created_at, updated_at)
      VALUES (@eid,@ename,@desc,CURRENT_DATE(),14,'ACTIVE',@strategy,'ACTIVE','EVERGREEN',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP())
    """, job_config=bigquery.QueryJobConfig(query_parameters=[
        bigquery.ScalarQueryParameter('eid', 'STRING', eid),
        bigquery.ScalarQueryParameter('ename', 'STRING', ename),
        bigquery.ScalarQueryParameter('desc', 'STRING', f'Manually classified via tools/classify_campaigns.py on {date.today().isoformat()}'),
        bigquery.ScalarQueryParameter('strategy', 'STRING', strategy)])).result()
    # 2. campaign -> experiment. Delete any existing rows first (some campaigns carry
    #    >1 EC row, which would break the MERGE's one-target-row rule), then insert one.
    client.query("DELETE FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` WHERE campaign_id=@cid",
        job_config=bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('cid', 'STRING', cid)])).result()
    client.query("""
      INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` (experiment_id, campaign_id, campaign_name, notes)
      VALUES (@eid,@cid,@cname,@note)
    """, job_config=bigquery.QueryJobConfig(query_parameters=[
        bigquery.ScalarQueryParameter('eid', 'STRING', eid),
        bigquery.ScalarQueryParameter('cid', 'STRING', cid),
        bigquery.ScalarQueryParameter('cname', 'STRING', name),
        bigquery.ScalarQueryParameter('note', 'STRING', note)])).result()
    # 3. family override (immediate attribution while dormant)
    client.query("""
      MERGE `onyga-482313.OI.DE_CAMPAIGN_FAMILY` T USING (SELECT @cid AS campaign_id) S
      ON T.campaign_id=S.campaign_id
      WHEN MATCHED THEN UPDATE SET parent_name=@fam, note=@note, updated_at=CURRENT_TIMESTAMP(), updated_by='classify_campaigns.py'
      WHEN NOT MATCHED THEN INSERT (campaign_id, parent_name, note, updated_at, updated_by)
        VALUES (@cid,@fam,@note,CURRENT_TIMESTAMP(),'classify_campaigns.py')
    """, job_config=bigquery.QueryJobConfig(query_parameters=[
        bigquery.ScalarQueryParameter('cid', 'STRING', cid),
        bigquery.ScalarQueryParameter('fam', 'STRING', family),
        bigquery.ScalarQueryParameter('note', 'STRING', note)])).result()
    print(f"    ✓ written (strategy={strategy}, family={family})")


def main():
    do_write = '--apply' in sys.argv
    print(f"{'APPLY' if do_write else 'DRY-RUN'} — classifying {len(MAPPINGS)} campaigns\n")
    for cid, fam, strat in MAPPINGS:
        try:
            apply_one(cid, fam, strat, do_write)
        except Exception as e:
            print(f"  !! {cid}: ERROR {e}")
    print("\nDone." + ("" if do_write else "  Re-run with --apply to write."))


if __name__ == '__main__':
    main()
