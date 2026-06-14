export type SynonymMap = Record<string, string[]>;

// Collapse a term to its CLUSTER KEY by replacing every synonym variant with its canonical word.
// - case-insensitive, whitespace-normalized
// - multi-word variants handled (e.g. "b day" → "birthday")
// - longest variants first + word-boundary matching so "present" doesn't fire inside "presents"
export function clusterKey(term: string, syn: SynonymMap): string {
  let s = ` ${term.toLowerCase().trim().replace(/\s+/g, ' ')} `;
  // Build [variantPhrase → canonical], longest variant first.
  const reps: { from: string; to: string }[] = [];
  for (const [canon, variants] of Object.entries(syn)) {
    for (const v of variants) {
      const vv = v.toLowerCase().trim();
      if (vv) reps.push({ from: vv, to: canon.toLowerCase().trim() });
    }
  }
  reps.sort((a, b) => b.from.length - a.from.length);
  for (const { from, to } of reps) {
    // whole-word/phrase replace (space-padded so internal substrings don't match)
    const re = new RegExp(`(?<=\\s)${from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?=\\s)`, 'g');
    s = s.replace(re, to);
  }
  return s.trim().replace(/\s+/g, ' ');
}

export interface Clusterable { query_text: string; market_impressions?: number | null; market_purchases?: number | null }
export interface TermCluster<T extends Clusterable> {
  key: string;            // the canonical cluster phrase
  representative: T;       // member with the most market_purchases (tie → most impressions)
  members: T[];           // all terms in the cluster, sorted by market_purchases desc
  size: number;
  totalImpressions: number;
  totalPurchases: number;
}

// Group rows into clusters by clusterKey. Clusters sorted by totalPurchases desc.
export function clusterTerms<T extends Clusterable>(rows: T[], syn: SynonymMap): TermCluster<T>[] {
  const groups = new Map<string, T[]>();
  for (const r of rows) {
    const k = clusterKey(r.query_text, syn);
    const arr = groups.get(k); if (arr) arr.push(r); else groups.set(k, [r]);
  }
  const out: TermCluster<T>[] = [];
  for (const [key, members] of groups) {
    const sorted = [...members].sort((a, b) =>
      (Number(b.market_purchases) || 0) - (Number(a.market_purchases) || 0)
      || (Number(b.market_impressions) || 0) - (Number(a.market_impressions) || 0));
    out.push({
      key, representative: sorted[0], members: sorted, size: sorted.length,
      totalImpressions: members.reduce((s, m) => s + (Number(m.market_impressions) || 0), 0),
      totalPurchases: members.reduce((s, m) => s + (Number(m.market_purchases) || 0), 0),
    });
  }
  return out.sort((a, b) => b.totalPurchases - a.totalPurchases);
}
