/* Competitor (conquest) bulksheet row building — extracted from DoPage so it can be TESTED.
 *
 * WHY THIS FILE EXISTS: three consecutive uploads to Amazon failed on mechanics that only
 * surfaced as rejection reports, because the row building lived inline in a React click handler
 * and had no test coverage (Ori 2026-07-24):
 *   1. SB `Bid Optimization: false` without bidAdjustmentsByPlacement  → 3/3 campaigns rejected.
 *   2. Child rows addressing an EXISTING campaign by NAME               → "Missing Parent ID",
 *      and because Amazon validates the whole sheet, 37 records → 0 applied.
 *   3. Targets added to a campaign already holding some, blowing the 10-per-campaign cap.
 * (3) is enforced in SQL (FN_COMPETITOR_CAMPAIGN_PLAN); (1) and (2) are enforced here and locked
 * down by competitorBulksheet.test.ts.
 *
 * These functions are PURE: no fetching, no XLSX, no React. Everything the rows depend on is
 * passed in via ctx, so a test can state the world exactly.
 */

export type BulksheetRow = Record<string, string>;

export interface CompetitorItem {
  action: string;
  campaign: string;          // campaign NAME — decided by FN_COMPETITOR_CAMPAIGN_PLAN
  ad_group_name?: string;
  targeting?: string;        // competitor ASIN as asin="B0…"
  asin?: string;             // OUR winner-variation ASIN (the advertised/promoted product)
  product?: string;
  recommended_bid?: number | null;
}

export interface CampaignTemplate {
  daily_budget?: number | null;
  bid_min?: number | null;
  product_page_pct?: number | null;
}

export interface CompetitorCtx {
  spTemplate?: CampaignTemplate | null;
  sbTemplate?: CampaignTemplate | null;
  /** UPPERCASED campaign name -> Amazon's real ids. Empty campaign_id means "unknown". */
  liveIds: Map<string, { campaign_id: string; ad_group_id: string }>;
  /** Does this campaign already exist ON AMAZON? Broader than liveIds (which may lack ids).
   *  Must NOT report true merely because an earlier row of this export created it. */
  isLiveOnAmazon: (name: string) => boolean;
  /** UPPERCASED names already scaffolded in THIS export. The builder adds to it. */
  scaffolded: Set<string>;
  /** Family prefix (ME/BOX/…) -> Amazon video asset id. '' when the family has no video. */
  videoAssetFor: (prefix: string) => string;
  portfolioFor: (prefix: string) => string;
  skuFor: (asin: string) => string;
  brandEntityId: string;
  brandName: string;
  startDate: string;         // YYYYMMDD
  formatPTExpression: (targeting: string) => string;
}

export interface BuildResult {
  spRows: BulksheetRow[];
  sbRows: BulksheetRow[];
  warnings: string[];
}

const norm = (s: string) => s.trim().toUpperCase();
const prefixOf = (campaignName: string) => campaignName.match(/^([A-Z]+)-/)?.[1] || 'PRODUCT';

/** Resolve how a child row must address its parent campaign. THREE distinct cases — conflating the
 *  last two silently dropped every target after the first for a new multi-ASIN campaign:
 *   1. Live on Amazon with known ids -> real numeric ids, no scaffold. A name here fails
 *      "Missing Parent ID" and, because validation is whole-sheet, voids the ENTIRE upload.
 *   2. Live on Amazon but ids unknown -> unaddressable; caller DROPS the row (losing one target
 *      beats losing the whole upload).
 *   3. Not live -> being created in this sheet. Address by NAME, and scaffold exactly once even
 *      though later rows of the same campaign are no longer "new". */
function resolveParent(
  campaignName: string, adGroupName: string, ctx: CompetitorCtx,
): { emitScaffold: boolean; campRef: string; agRef: string; isNew: boolean } {
  const key = norm(campaignName);
  const live = ctx.liveIds.get(key);
  if (live?.campaign_id) {
    return { emitScaffold: false, campRef: live.campaign_id, agRef: live.ad_group_id || '', isNew: false };
  }
  if (ctx.isLiveOnAmazon(campaignName)) {
    return { emitScaffold: false, campRef: '', agRef: '', isNew: false };   // caller drops
  }
  const emitScaffold = !ctx.scaffolded.has(key);
  if (emitScaffold) ctx.scaffolded.add(key);
  return { emitScaffold, campRef: campaignName, agRef: adGroupName, isNew: true };
}

/** SP product-targeting conquest rows for one queued competitor ASIN. */
export function buildCompetitorSpRows(item: CompetitorItem, ctx: CompetitorCtx): BuildResult {
  const out: BuildResult = { spRows: [], sbRows: [], warnings: [] };
  const tmpl = ctx.spTemplate;
  if (!tmpl) { out.warnings.push(`no COMPETITOR/SP template — skipped ${item.campaign}`); return out; }

  const campName = item.campaign;
  const agName = item.ad_group_name || `${campName} - Competitors`;
  const bid = String(item.recommended_bid ?? tmpl.bid_min ?? '');
  const asin = item.asin || '';
  const sku = ctx.skuFor(asin);
  const targetExpr = ctx.formatPTExpression(item.targeting || '');
  const prefix = prefixOf(campName);

  if (!targetExpr) { out.warnings.push(`missing target expression for ${campName}`); return out; }

  const { emitScaffold, campRef, agRef, isNew } = resolveParent(campName, agName, ctx);
  if (!campRef || !agRef) {
    out.warnings.push(`${campName} already exists but its ids are unknown — dropped ${targetExpr}`);
    return out;
  }

  if (emitScaffold) {
    out.spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Campaign', 'Operation': 'Create',
      'Campaign ID': campName, 'Campaign Name': campName, 'Portfolio ID': ctx.portfolioFor(prefix),
      'Daily Budget': String(tmpl.daily_budget ?? ''), 'Targeting Type': 'MANUAL',
      'Bidding Strategy': 'Dynamic bids - down only', 'Start Date': ctx.startDate, 'State': 'ENABLED' });
    if ((tmpl.product_page_pct ?? 0) > 0) {
      out.spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Bidding Adjustment', 'Operation': 'Create',
        'Campaign ID': campName, 'Campaign Name': campName, 'Placement': 'Placement Product Page',
        'Percentage': String(tmpl.product_page_pct) });
    }
    out.spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Ad Group', 'Operation': 'Create',
      'Campaign ID': campName, 'Campaign Name': campName,
      'Ad Group ID': agName, 'Ad Group Name': agName,
      'Ad Group Default Bid': bid, 'State': 'ENABLED' });
    out.spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Product Ad', 'Operation': 'Create',
      'Campaign ID': campName, 'Campaign Name': campName,
      'Ad Group ID': agName, 'Ad Group Name': agName,
      ...(sku ? { 'SKU': sku } : asin ? { 'ASIN (Informational only)': asin } : {}),
      'State': 'ENABLED' });
  }

  out.spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Product Targeting', 'Operation': 'Create',
    'Campaign ID': campRef, 'Ad Group ID': agRef,
    ...(isNew
      ? { 'Campaign Name': campName, 'Ad Group Name': agName }
      : { 'Campaign Name (Informational only)': campName, 'Ad Group Name (Informational only)': agName }),
    'Product Targeting Expression': targetExpr, 'Bid': bid, 'State': 'ENABLED' });
  return out;
}

/** SB VIDEO conquest rows for one queued competitor ASIN. */
export function buildCompetitorSbRows(item: CompetitorItem, ctx: CompetitorCtx): BuildResult {
  const out: BuildResult = { spRows: [], sbRows: [], warnings: [] };
  const tmpl = ctx.sbTemplate;
  const campName = item.campaign;
  const agName = item.ad_group_name || `${campName} - Competitors`;
  const bid = String(item.recommended_bid ?? tmpl?.bid_min ?? '');
  const asin = item.asin || '';
  const prefix = prefixOf(campName);
  const videoAssetId = ctx.videoAssetFor(prefix);
  const targetExpr = ctx.formatPTExpression(item.targeting || '');

  if (!tmpl) { out.warnings.push(`no COMPETITOR/SB_VIDEO template — skipped ${campName}`); return out; }
  // No creative → no ad. Never emit an SB campaign that would fail Amazon's creative check.
  if (!videoAssetId) { out.warnings.push(`no video asset for ${prefix} — skipped ${campName}`); return out; }
  if (!targetExpr) { out.warnings.push(`missing target expression for ${campName}`); return out; }

  const { emitScaffold, campRef, agRef, isNew } = resolveParent(campName, agName, ctx);
  if (!campRef || !agRef) {
    out.warnings.push(`${campName} already exists but its ids are unknown — dropped ${targetExpr}`);
    return out;
  }

  if (emitScaffold) {
    out.sbRows.push({ 'Product': 'Sponsored Brands', 'Entity': 'Campaign', 'Operation': 'Create',
      'Campaign Id': campName, 'Campaign Name': campName, 'Portfolio Id': ctx.portfolioFor(prefix),
      'Start Date': ctx.startDate, 'State': 'enabled',
      'Budget Type': 'daily', 'Budget': String(tmpl.daily_budget ?? ''),
      // MUST be 'true' — Amazon rejects false unless the row carries bidAdjustmentsByPlacement.
      'Bid Optimization': 'true',
      'Brand Entity Id': ctx.brandEntityId, 'Brand Name': ctx.brandName });
    out.sbRows.push({ 'Product': 'Sponsored Brands', 'Entity': 'Ad Group', 'Operation': 'Create',
      'Campaign Id': campName, 'Campaign Name': campName,
      'Ad Group Id': agName, 'Ad Group Name': agName, 'State': 'enabled' });
    const adName = `${campName} - Video Ad`;
    out.sbRows.push({ 'Product': 'Sponsored Brands', 'Entity': 'Video Ad', 'Operation': 'Create',
      'Campaign Id': campName, 'Campaign Name': campName,
      'Ad Group Id': agName, 'Ad Group Name': agName,
      'Ad Id': adName, 'Ad Name': adName, 'State': 'enabled',
      'Ad Format': 'video', 'Creative ASINs': asin, 'Video asset IDs': videoAssetId,
      'Creative Type': 'video' });
  }

  out.sbRows.push({ 'Product': 'Sponsored Brands', 'Entity': 'Product Targeting', 'Operation': 'Create',
    'Campaign Id': campRef, 'Ad Group Id': agRef,
    ...(isNew ? { 'Campaign Name': campName, 'Ad Group Name': agName } : {}),
    'Product Targeting Expression': targetExpr, 'Bid': bid, 'State': 'enabled' });
  return out;
}
