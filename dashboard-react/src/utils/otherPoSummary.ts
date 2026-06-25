/**
 * Pure helpers for the "Connected Other POs" section of the New Shipment modal.
 * Summarizes the selected Other POs whose amounts roll into the shipment's
 * landed cost. Currency handling is face-value (no FX); non-USD picks are flagged.
 */
export interface OtherPoLite {
  other_po_id: string;
  supplier_name?: string | null;
  service_type?: string | null;
  total_amount?: number | null;
  currency?: string | null;
}

export interface ConnectedOtherPoSummary {
  /** Sum of selected total_amount (face value). */
  total: number;
  /** Number of selected Other POs that matched the list. */
  count: number;
  /** Distinct currencies among the selection (defaults missing to 'USD'). */
  currencies: string[];
  /** True if any selected currency is not USD. */
  hasNonUsd: boolean;
}

export function summarizeConnectedOtherPos(
  all: OtherPoLite[],
  selectedIds: string[],
): ConnectedOtherPoSummary {
  const selected = new Set(selectedIds);
  const picked = all.filter((o) => selected.has(o.other_po_id));
  let total = 0;
  const currencies = new Set<string>();
  for (const o of picked) {
    total += Number(o.total_amount) || 0;
    currencies.add((o.currency || 'USD').toUpperCase());
  }
  const currencyList = [...currencies];
  return {
    total,
    count: picked.length,
    currencies: currencyList,
    hasNonUsd: currencyList.some((c) => c !== 'USD'),
  };
}
