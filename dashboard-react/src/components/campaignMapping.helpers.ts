export interface CampaignMappingRow {
  campaign_id: string;
  campaign_name: string;
  spend_60d: number;
  current_experiment_id: string | null;
  current_experiment_name: string | null;
  current_strategy_id: string | null;
  suggested_family: string | null;
  suggested_strategy: string | null;
  suggested_experiment_id: string | null;
  confidence: number | null;
  source: string;
}

export interface MappingCoverageCheck {
  check_key: string;
  label: string;
  scope: string;
  total: number;
  mapped: number;
  gap: number;
  pct: number;
  critical: boolean;
  items: string[];
}

// Mirrors data-entry-app/app.py `_STRATEGY_LABEL`.
export const STRATEGY_LABELS: Record<string, string> = {
  EXACT_BOOST: 'Exact Boost',
  HUNTER: 'Broad Hunter',
  LOW_COST_DISCOVERY: 'Auto Discovery',
  BRAND_DEFENSE: 'Brand Defense',
  PRODUCT_DEFENSE: 'Product Defense',
  COMPETITOR_CONQUEST: 'Competitor Conquest',
  CATEGORY_CONQUEST: 'Category Conquest',
};

const UNMAPPED_SOURCES = new Set(['unmapped', 'default']);

/** A campaign still needs a family+strategy mapping. */
export function needsMapping(row: CampaignMappingRow): boolean {
  return UNMAPPED_SOURCES.has(row.source);
}

/** Rows the "Approve all suggestions" action will act on: needs-mapping AND a complete suggestion. */
export function approveAllEligible(rows: CampaignMappingRow[]): CampaignMappingRow[] {
  return rows.filter(r => needsMapping(r) && !!r.suggested_family && !!r.suggested_strategy);
}

/** Human-readable strategy label, falling back to the raw id (or a dash for empty). */
export function friendlyStrategy(id: string | null | undefined): string {
  if (!id) return '—';
  return STRATEGY_LABELS[id] || id;
}
