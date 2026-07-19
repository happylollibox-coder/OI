// One Update row per entity per Amazon bulksheet — guaranteed. Amazon voids the ENTIRE sheet
// ("no change was applied") if any two Update rows share an id: "Duplicate Id". So a keyword
// queued for a bid change PLUS a stray blank-bid row for the same keyword (the DO queue dedups on
// search_term|action|campaign|targeting, NOT keyword_id, so the same keyword reaches the export
// twice) sinks every other change in the file. Seen at the campaign level in report 10 and at the
// keyword level in report 17.
//
// This is the export-time analog of V_COACH_APPLY's "one row per entity to change" guarantee,
// applied to the actual XLSX regardless of how the queue was assembled — the last gate before upload.
//
// An Amazon Update row carries every mutable field at once (Bid + State + …), so we MERGE rather
// than drop: the first occurrence holds its position; later rows for the same entity fill in only
// their non-empty fields (last non-empty wins per field, so a real Bid always beats a blank one).
export type BulkRow = Record<string, string>;

// entity -> candidate id columns. The SP sheet spells it 'ID', the SB sheet spells it 'Id';
// try both so one merge pass covers both sheets. Only these entities are id-keyed Updates.
const UPDATE_ID_COLS: Record<string, string[]> = {
  'Campaign': ['Campaign ID', 'Campaign Id'],
  'Keyword': ['Keyword ID', 'Keyword Id'],
  'Product Targeting': ['Product Targeting ID', 'Product Targeting Id'],
};

export function mergeUpdateRows(rows: BulkRow[]): BulkRow[] {
  const out: BulkRow[] = [];
  const at = new Map<string, number>();
  for (const row of rows) {
    const idCols = row['Operation'] === 'Update' ? UPDATE_ID_COLS[row['Entity']] : undefined;
    const idCol = idCols?.find(c => row[c]);   // first id column this row actually carries
    if (idCol) {
      const key = `${row['Entity']}|${row[idCol]}`;   // Entity in the key so a keyword id can't collide with a campaign id
      const seen = at.get(key);
      if (seen != null) {
        const extras = Object.fromEntries(Object.entries(row).filter(([, v]) => v !== '' && v != null));
        out[seen] = { ...out[seen], ...extras };
        continue;
      }
      at.set(key, out.length);
    }
    out.push(row);
  }
  return out;
}
