/**
 * Family attribution for the Ads page hierarchy.
 *
 * The canonical OI family lives in DIM_PRODUCT.parent_name (surfaced on ads rows via
 * the most-advertised-ASIN join, and mapped by V_PRODUCT_FAMILY_MAP) — the same key the
 * Home "Per Product Family" table, the Family page, and the Coach all use. We prefer it
 * here so the Ads page "Family" grouping/filter lines up with the rest of the dashboard.
 *
 * `extractFamilyFromCampaign` is the legacy campaign-name heuristic, kept only as a
 * fallback for rows that have no parent_name (e.g. a campaign with no resolvable ASIN).
 */

/** Minimal shape needed to resolve a row's family. */
export interface FamilyRow {
  parent_name?: string | null;
  campaign_name?: string | null;
}

/** Legacy fallback: guess family from the campaign name. */
export function extractFamilyFromCampaign(campaignName: string): string {
  const cn = (campaignName || '').toLowerCase();
  if (cn.includes('box')) return 'Lollibox';
  if (cn.includes('me') || cn.includes('mint') || cn.includes('lollime')) return 'LolliME';
  if (cn.includes('bottle') || cn.includes('truth')) return 'Bottle';
  if (cn.includes('fresh')) return 'Fresh';
  if (cn.includes('brand')) return 'Brand';
  return 'Other';
}

/** Canonical family for an ads row: parent_name when present, else the campaign-name fallback. */
export function familyForRow(r: FamilyRow): string {
  const pn = (r.parent_name || '').trim();
  if (pn) return pn;
  return extractFamilyFromCampaign(r.campaign_name || '');
}

/** True when the row belongs to `family` (case-insensitive). A null/empty filter matches all rows. */
export function rowMatchesFamily(r: FamilyRow, family: string | null | undefined): boolean {
  if (!family) return true;
  return familyForRow(r).toLowerCase() === family.toLowerCase();
}
