import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Search, RefreshCw, Filter, X } from 'lucide-react';
import { Section } from '../components/Section';
import { SearchableDropdown } from '../components/SearchableDropdown';
import { fShort } from '../utils';
import {
  SEASONS,
  type ResearchRow, type ConversionCurveRow, type SortKey, type SortDir,
  type ProductInfo, type FamilyInfo, type SegmentReasoning, type TermRanksMap,
  type RecommendationsByType,
} from './research/types';
import { mapResearchRow } from './research/mapRow';
import { mapRecommendationsByType } from './research/mapRecommendation';
import { FamilyTabs } from './research/FamilyTabs';
import { FamilyInfoCard } from './research/FamilyInfoCard';
import { RecommendationsCard } from './research/RecommendationsCard';
import { ConversionCurveCard } from './research/ConversionCurveCard';
import { ResultsTable } from './research/ResultsTable';
import { apiFetch } from '../utils/apiFetch';

// All scoring lives in SQL (V_RESEARCH_RANKED → FACT_RESEARCH_RANKED).
// This page fetches, filters, sorts, and formats — it never computes scores.
// SOP: architecture/RESEARCH_PAGE.md

const PAGE_SIZE = 200;

export function ResearchPage() {
  const [term, setTerm] = useState('');
  const [submittedTerm, setSubmittedTerm] = useState('');
  const [parent, setParent] = useState<string>('');
  const [selectedProduct, setSelectedProduct] = useState<string>('');

  const [searchMode, setSearchMode] = useState<'direct' | 'phrase' | 'broad'>('phrase');
  // Bumped on each explicit Search so re-searching the current term always re-fetches.
  const [searchNonce, setSearchNonce] = useState(0);
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<ResearchRow[]>([]);
  const [curve, setCurve] = useState<ConversionCurveRow[]>([]);
  const [activeSeason, setActiveSeason] = useState('_ALL');
  const [products, setProducts] = useState<ProductInfo[]>([]);
  const [overviewLoading, setOverviewLoading] = useState(true);

  // Filters
  const [filterGender, setFilterGender] = useState<string>('');
  const [filterAge, setFilterAge] = useState<string>('');
  const [filterOccasion, setFilterOccasion] = useState<string>('');
  const [filterCostTier, setFilterCostTier] = useState<string>('');
  const [filterProductType, setFilterProductType] = useState<string>('');
  const [filterBrand, setFilterBrand] = useState<string>('');
  const [familyInfo, setFamilyInfo] = useState<FamilyInfo | null>(null);
  const [segmentReasoning, setSegmentReasoning] = useState<SegmentReasoning | null>(null);
  const [recommendations, setRecommendations] = useState<RecommendationsByType | null>(null);

  // Sorting + pagination
  const [sortKey, setSortKey] = useState<SortKey>('rank');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [currentPage, setCurrentPage] = useState(1);

  // Per-family comparison data for the search-term hover (batched per page)
  const [termRanks, setTermRanks] = useState<TermRanksMap>({});

  const productPrice = useMemo(() => {
    const p = products.find(p => p.name === selectedProduct);
    return p?.price ?? 0;
  }, [selectedProduct, products]);

  // ─── Load conversion curve + products ─────────────────
  useEffect(() => {
    setOverviewLoading(true);
    Promise.all([
      apiFetch('/api/research/conversion-curve').then(r => r.ok ? r.json() : []).catch(() => []),
      apiFetch('/api/research/products').then(r => r.ok ? r.json() : []).catch(() => []),
    ]).then(([curveData, productsData]) => {
      setCurve(curveData);
      setProducts(productsData);
      if (productsData.length > 0 && !selectedProduct) {
        setSelectedProduct(productsData[0].name);
        setParent(productsData[0].name);
      }
    }).finally(() => setOverviewLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ─── Load family info + reasoning when product changes ─────
  const fetchFamily = useCallback(async (signal?: AbortSignal) => {
    const get = (path: string) =>
      apiFetch(path, { signal }).then(r => r.ok ? r.json() : null).catch(() => null);
    // Set each piece of state as soon as its own request resolves — never let a
    // slow/failing endpoint (segment-reasoning can be expensive) block the others
    // via Promise.all, which previously hid the family + recommendations cards.
    get(`/api/research/family-info?family=${encodeURIComponent(selectedProduct)}`)
      .then(fi => { if (!signal?.aborted) setFamilyInfo(fi); });
    get(`/api/research/recommendations?parent=${encodeURIComponent(selectedProduct)}`)
      .then(rc => { if (!signal?.aborted) setRecommendations(rc ? mapRecommendationsByType(rc) : null); });
    // awaited so onRefreshFamily() resolves after the (optional) reasoning lands
    await get(`/api/research/segment-reasoning?family=${encodeURIComponent(selectedProduct)}`)
      .then(sr => { if (!signal?.aborted) setSegmentReasoning(sr); });
  }, [selectedProduct]);

  useEffect(() => {
    if (!selectedProduct) { setFamilyInfo(null); setSegmentReasoning(null); setRecommendations(null); return; }
    const controller = new AbortController();
    fetchFamily(controller.signal);
    return () => controller.abort();
  }, [selectedProduct, fetchFamily]);

  // ─── Top terms (default view) when parent changes ──────
  useEffect(() => {
    // submittedTerm '__top__' means showing top terms (not a real search) — allow refetch
    if (!parent || (submittedTerm && submittedTerm !== '__top__')) return;
    setOverviewLoading(true);
    apiFetch(`/api/research/top-terms?parent=${encodeURIComponent(parent)}`)
      .then(r => r.ok ? r.json() : [])
      .then((topData: Record<string, unknown>[]) => {
        setResults(topData.map(mapResearchRow));
        setSubmittedTerm('__top__');
      })
      .catch(() => {})
      .finally(() => setOverviewLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [parent]);

  // ─── Search ───────────────────────────────────────────
  const [synonyms, setSynonyms] = useState<Record<string, string[]>>({});
  const [synonymsLoading, setSynonymsLoading] = useState(false);
  const [synonymsReady, setSynonymsReady] = useState(false);

  const doSearch = useCallback(async () => {
    if (!term.trim()) {
      // Empty search → reload top terms
      setLoading(true);
      setSubmittedTerm('');
      setSynonyms({});
      setSynonymsReady(false);
      try {
        const res = await apiFetch(`/api/research/top-terms${parent ? `?parent=${encodeURIComponent(parent)}` : ''}`);
        if (res.ok) {
          const topData: Record<string, unknown>[] = await res.json();
          setResults(topData.map(mapResearchRow));
          setSubmittedTerm('__top__');
        }
      } catch (e) {
        console.error('Failed to reload top terms:', e);
      } finally {
        setLoading(false);
      }
      return;
    }

    const searchTerm = term.trim();
    setLoading(true);
    setSubmittedTerm(searchTerm);
    setSynonyms({});
    setSynonymsReady(false);
    setSearchMode('phrase');  // default match-type after a search; the mode effect fetches
    setCurrentPage(1);
    setSearchNonce(n => n + 1);  // force the mode effect to fetch even on an identical re-search

    // Results are fetched by the mode effect below (keyed on submittedTerm + searchMode).
    // Background: fetch synonyms (DE_SYNONYM_CACHE + hardcoded fallback) to enable Broad.
    const stopWords = new Set(['a', 'an', 'the', 'for', 'and', 'or', 'of', 'to', 'in', 'on', 'at', 'by', 'is', 'it', 'my', 'with']);
    const searchWords = searchTerm.split(/\s+/).filter(w => !stopWords.has(w.toLowerCase()));
    if (searchWords.length > 0) {
      setSynonymsLoading(true);
      try {
        const synRes = await apiFetch('/api/research/get-synonyms', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ words: searchWords }),
        });
        if (synRes.ok) {
          const synData: Record<string, string[]> = await synRes.json();
          const hasSynonyms = Object.values(synData).some(arr => arr.length > 0);
          setSynonyms(synData);
          setSynonymsReady(hasSynonyms);
        }
      } catch (e) {
        console.error('Synonym fetch failed:', e);
      } finally {
        setSynonymsLoading(false);
      }
    }
  }, [term, parent]);

  // Single fetch path for a live search: runs whenever the term, family, or match-type
  // mode changes. Synonyms only matter for Broad, so a synonym arrival re-fetches only
  // in that mode (reqKey dedupes against modes synonyms don't affect). Replaces the old
  // per-mode and per-parent effects, and the inline fetch that doSearch used to do.
  const searchReqRef = useRef('');
  useEffect(() => {
    if (!submittedTerm || submittedTerm === '__top__') return;
    const synActive = searchMode === 'broad' && synonymsReady;
    const reqKey = `${submittedTerm}|${parent}|${searchMode}|${synActive}|${searchNonce}`;
    if (searchReqRef.current === reqKey) return;
    searchReqRef.current = reqKey;
    setLoading(true);
    apiFetch('/api/research/related-terms', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        term: submittedTerm,
        parent: parent || undefined,
        mode: searchMode,
        ...(searchMode === 'broad' ? { synonyms } : {}),
      }),
    })
      .then(r => r.ok ? r.json() : [])
      .then((data: Record<string, unknown>[]) => setResults(data.map(mapResearchRow)))
      .catch(e => console.error('Research mode fetch failed:', e))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [submittedTerm, parent, searchMode, synonymsReady, searchNonce]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') doSearch();
  };

  // ─── Unique filter values ─────────────────────────────
  const filterOptions = useMemo(() => {
    const genders = new Set<string>();
    const ages = new Set<string>();
    const occasions = new Set<string>();
    const costTiers = new Set<string>();
    const productTypes = new Set<string>();
    const brands = new Set<string>();
    results.forEach(r => {
      if (r.gender) genders.add(r.gender);
      if (r.age_group) ages.add(r.age_group);
      if (r.occasion) occasions.add(r.occasion);
      if (r.holiday) occasions.add(r.holiday);
      if (r.cost_tier) costTiers.add(r.cost_tier);
      if (r.product_type) productTypes.add(r.product_type);
      if (r.brand) brands.add(r.brand);
    });
    return {
      genders: Array.from(genders).sort(),
      ages: Array.from(ages).sort(),
      occasions: Array.from(occasions).sort(),
      costTiers: Array.from(costTiers).sort(),
      productTypes: Array.from(productTypes).sort(),
      brands: Array.from(brands).sort(),
    };
  }, [results]);

  // ─── Filter + Sort (word filtering happens server-side) ──
  const displayRows = useMemo(() => {
    let rows = results;

    // Filter by season tab
    if (activeSeason === 'Off-Season') {
      rows = rows.filter(r => !r.occasion);
    } else if (activeSeason !== '_ALL') {
      rows = rows.filter(r => r.occasion === activeSeason);
    }

    // Apply segment filters ('__OTHER__' = unclassified/null)
    if (filterGender) rows = rows.filter(r => filterGender === '__OTHER__' ? !r.gender : r.gender === filterGender);
    if (filterAge) rows = rows.filter(r => filterAge === '__OTHER__' ? !r.age_group : r.age_group === filterAge);
    if (filterOccasion) rows = rows.filter(r => filterOccasion === '__OTHER__' ? (!r.occasion && !r.holiday) : (r.occasion === filterOccasion || r.holiday === filterOccasion));
    if (filterCostTier) rows = rows.filter(r => filterCostTier === '__OTHER__' ? !r.cost_tier : r.cost_tier === filterCostTier);
    if (filterProductType) rows = rows.filter(r => filterProductType === '__OTHER__' ? !r.product_type : r.product_type === filterProductType);
    if (filterBrand) rows = rows.filter(r => filterBrand === '__OTHER__' ? !r.brand : r.brand === filterBrand);

    // Sort (aliased sort keys map onto SQL-computed columns)
    rows = [...rows].sort((a, b) => {
      let av: number | string | null, bv: number | string | null;
      if (sortKey === 'est_clicks_per_sale') {
        av = a.est_cps;
        bv = b.est_cps;
      } else if (sortKey === 'match_rank') {
        av = a.seg_fit;
        bv = b.seg_fit;
      } else if (sortKey === 'purchase_rank') {
        av = a.purchase_rank_score;
        bv = b.purchase_rank_score;
      } else if (sortKey === 'rank') {
        av = a.rank_score;
        bv = b.rank_score;
      } else {
        av = a[sortKey] as number | string | null;
        bv = b[sortKey] as number | string | null;
      }
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      const cmp = typeof av === 'string' ? av.localeCompare(bv as string) : (av as number) - (bv as number);
      return sortDir === 'desc' ? -cmp : cmp;
    });

    return rows;
  }, [results, activeSeason, filterGender, filterAge, filterOccasion, filterCostTier, filterProductType, filterBrand, sortKey, sortDir]);

  const pagedRows = useMemo(
    () => displayRows.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE),
    [displayRows, currentPage]
  );

  // ─── Fetch per-family rank comparison for visible rows ─────
  const pagedRowTerms = useMemo(() => pagedRows.map(r => r.query_text.toLowerCase()), [pagedRows]);
  useEffect(() => {
    const missing = pagedRowTerms.filter(t => !(t in termRanks));
    if (missing.length === 0) return;
    const controller = new AbortController();
    apiFetch('/api/research/term-ranks', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ terms: missing }), signal: controller.signal,
    }).then(r => r.ok ? r.json() : {})
      .then((data: TermRanksMap) => {
        // Terms with no ranked rows still get an entry so we don't refetch them
        const filled: TermRanksMap = {};
        for (const t of missing) filled[t] = data[t] ?? [];
        setTermRanks(prev => ({ ...prev, ...filled }));
      })
      .catch(() => {});
    return () => controller.abort();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pagedRowTerms]);

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir(prev => (prev === 'desc' ? 'asc' : 'desc'));
    } else {
      setSortKey(key);
      setSortDir('desc');
    }
    setCurrentPage(1);
  };

  const hasActiveFilters = filterGender || filterAge || filterOccasion || filterCostTier || filterProductType || filterBrand;

  const clearFilters = () => {
    setFilterGender('');
    setFilterAge('');
    setFilterOccasion('');
    setFilterCostTier('');
    setFilterProductType('');
    setFilterBrand('');
  };

  // ─── Save manual segment overrides (MERGE upsert server-side) ──
  const onSaveSegments = useCallback(async (queryText: string, segs: Record<string, string | null>) => {
    await apiFetch('/api/research/update-segments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query_text: queryText, ...segs }),
    });
    setResults(prev => prev.map(r =>
      r.query_text === queryText ? { ...r, ...segs } as ResearchRow : r
    ));
  }, []);

  // ─── Stats ────────────────────────────────────────────
  const directCount = results.filter(r => r.match_type === 'direct').length;
  const relatedCount = results.filter(r => r.match_type === 'related').length;

  return (
    <>
      <Section title="Keyword Research">
        <FamilyTabs
          products={products}
          selected={selectedProduct}
          onSelect={(name) => { setSelectedProduct(name); setParent(name); }}
        />

        {familyInfo && selectedProduct && (
          <FamilyInfoCard
            familyInfo={familyInfo}
            selectedProduct={selectedProduct}
            segmentReasoning={segmentReasoning}
            onRefreshFamily={() => fetchFamily()}
          />
        )}

        {selectedProduct && (
          <RecommendationsCard recs={recommendations} selectedProduct={selectedProduct} />
        )}

        {/* ─── Season Selector ─── */}
        {results.length > 0 && (
          <div className="flex items-center gap-2 mb-4">
            <span className="text-[9px] text-muted uppercase tracking-wide mr-1">Season:</span>
            {SEASONS.map(s => (
              <button
                key={s.key}
                onClick={() => setActiveSeason(s.key)}
                className={`px-2.5 py-1 text-[10px] font-medium rounded-md transition-all ${
                  activeSeason === s.key
                    ? 'bg-blue-500/15 text-blue-400 border border-blue-500/30'
                    : 'text-muted hover:text-subtle border border-transparent'
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>
        )}

        {/* ─── Segment Filters ─── */}
        {results.length > 0 && (
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <Filter size={12} className="text-muted" />

            {filterOptions.genders.length > 0 && (
              <SearchableDropdown
                value={filterGender}
                onChange={setFilterGender}
                options={filterOptions.genders}
                placeholder="Gender"
                activeClass="border-pink-500/40 text-pink-400"
              />
            )}

            {filterOptions.ages.length > 0 && (
              <SearchableDropdown
                value={filterAge}
                onChange={setFilterAge}
                options={filterOptions.ages}
                placeholder="Age Group"
                activeClass="border-cyan-500/40 text-cyan-400"
              />
            )}

            {filterOptions.occasions.length > 0 && (
              <SearchableDropdown
                value={filterOccasion}
                onChange={setFilterOccasion}
                options={filterOptions.occasions}
                placeholder="Occasion"
                activeClass="border-amber-500/40 text-amber-400"
              />
            )}

            {filterOptions.costTiers.length > 0 && (
              <SearchableDropdown
                value={filterCostTier}
                onChange={setFilterCostTier}
                options={filterOptions.costTiers}
                placeholder="Cost Tier"
                activeClass="border-emerald-500/40 text-emerald-400"
              />
            )}

            {filterOptions.productTypes.length > 0 && (
              <SearchableDropdown
                value={filterProductType}
                onChange={setFilterProductType}
                options={filterOptions.productTypes}
                placeholder="Product Type"
                activeClass="border-violet-500/40 text-violet-400"
              />
            )}

            {filterOptions.brands.length > 0 && (
              <SearchableDropdown
                value={filterBrand}
                onChange={setFilterBrand}
                options={filterOptions.brands}
                placeholder="Brand"
                activeClass="border-cyan-500/40 text-cyan-400"
              />
            )}

            {hasActiveFilters && (
              <button
                onClick={clearFilters}
                className="inline-flex items-center gap-1 px-2 py-1 text-[10px] text-red-400 hover:bg-red-500/10 rounded-md transition-colors"
              >
                <X size={10} /> Clear
              </button>
            )}

            <span className="ml-auto text-[10px] text-muted">
              {displayRows.length} results
              {hasActiveFilters && ` (filtered from ${results.length})`}
            </span>
          </div>
        )}

        {/* ─── Summary Stats ─── */}
        {results.length > 0 && (
          <div className="grid grid-cols-5 gap-3 mb-5">
            <div className="p-3 rounded-lg border border-border bg-white/[0.02]">
              <div className="text-[9px] text-muted uppercase tracking-wide mb-1">Direct Matches</div>
              <div className="text-lg font-bold text-heading">{directCount}</div>
            </div>
            <div className="p-3 rounded-lg border border-purple-500/20 bg-purple-500/5">
              <div className="text-[9px] text-purple-400 uppercase tracking-wide mb-1">Related Terms</div>
              <div className="text-lg font-bold text-purple-300">{relatedCount}</div>
            </div>
            <div className="p-3 rounded-lg border border-border bg-white/[0.02]">
              <div className="text-[9px] text-muted uppercase tracking-wide mb-1">Total Market Volume</div>
              <div className="text-lg font-bold text-heading">{fShort(displayRows.reduce((s, r) => s + (r.market_impressions || 0), 0))}</div>
            </div>
            <div className="p-3 rounded-lg border border-border bg-white/[0.02]">
              <div className="text-[9px] text-muted uppercase tracking-wide mb-1">Estimating For</div>
              <div className="text-lg font-bold text-heading">{selectedProduct} <span className="text-sm text-muted font-normal">${productPrice}</span></div>
            </div>
            <div className="p-3 rounded-lg border border-border bg-white/[0.02]">
              <div className="text-[9px] text-muted uppercase tracking-wide mb-1">Season</div>
              <div className="text-lg font-bold text-heading">{SEASONS.find(s => s.key === activeSeason)?.label}</div>
            </div>
          </div>
        )}

        {/* ─── Conversion Curve (always visible) ─── */}
        {!loading && !overviewLoading && (
          <ConversionCurveCard curve={curve} products={products} selectedProduct={selectedProduct} />
        )}

        {/* ─── Search Bar ─── */}
        <div className="flex items-center gap-3 mb-5">
          <div className="relative flex-1">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              id="research-search-input"
              type="text"
              value={term}
              onChange={e => setTerm(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Search keywords — e.g. birthday, cute stuff, friend..."
              className="w-full pl-9 pr-3 py-2.5 text-sm bg-white/[0.04] border border-border rounded-lg text-heading placeholder:text-faint/40 focus:outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/20 transition-all"
            />
          </div>
          <button
            onClick={doSearch}
            disabled={loading}
            className="inline-flex items-center gap-1.5 px-5 py-2.5 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-500 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading ? <RefreshCw size={14} className="animate-spin" /> : <Search size={14} />}
            Search
          </button>
        </div>

        {/* ─── Loading ─── */}
        {overviewLoading && (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="animate-spin text-blue-400" size={20} />
            <span className="ml-2 text-muted text-sm">Loading overview...</span>
          </div>
        )}

        {/* ─── No Results ─── */}
        {!loading && results.length === 0 && submittedTerm && (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <Search className="text-amber-500/30 mb-3" size={32} />
            <h3 className="text-sm font-medium text-amber-400 mb-1">No results for "{submittedTerm}"</h3>
            <p className="text-[10px] text-muted max-w-xs">
              Try a different term or broader scope.
            </p>
          </div>
        )}

        {/* ─── Loading ─── */}
        {loading && (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="animate-spin text-blue-400" size={20} />
            <span className="ml-2 text-muted text-sm">Searching co-occurrence network...</span>
          </div>
        )}

        {/* ─── Direct / Phrase / Broad toggle (above table) ─── */}
        {!loading && submittedTerm && submittedTerm !== '__top__' && (
          <div className="flex items-center gap-3 mb-3">
            <div className="inline-flex rounded-lg border border-border overflow-hidden">
              <button
                onClick={() => setSearchMode('direct')}
                title="Exact term + plurals only"
                className={`px-4 py-1.5 text-xs font-semibold transition-all ${
                  searchMode === 'direct'
                    ? 'text-white bg-blue-600'
                    : 'text-muted bg-white/[0.02] hover:text-subtle'
                }`}
              >
                Direct
              </button>
              <button
                onClick={() => setSearchMode('phrase')}
                title="All words, any order, extra words allowed"
                className={`px-4 py-1.5 text-xs font-semibold transition-all border-l border-border ${
                  searchMode === 'phrase'
                    ? 'text-white bg-blue-600'
                    : 'text-muted bg-white/[0.02] hover:text-subtle'
                }`}
              >
                Phrase
              </button>
              <button
                onClick={() => setSearchMode('broad')}
                className={`px-4 py-1.5 text-xs font-semibold transition-all border-l border-border relative ${
                  searchMode === 'broad'
                    ? 'text-white bg-purple-600'
                    : synonymsReady
                      ? 'text-purple-400 bg-purple-500/10 hover:bg-purple-500/20'
                      : 'text-muted bg-white/[0.02] hover:text-subtle'
                }`}
                title={
                  synonymsLoading ? 'Finding synonyms...'
                  : synonymsReady ? `Phrase reach + synonyms: ${Object.entries(synonyms).map(([w, s]) => `${w} → ${s.join(', ')}`).join(' | ')}`
                  : 'Phrase reach + synonyms (none found yet for these words)'
                }
              >
                {synonymsLoading && <RefreshCw size={10} className="inline animate-spin mr-1" />}
                Broad
                {synonymsReady && (
                  <span className="absolute -top-1.5 -right-1.5 min-w-[16px] h-4 flex items-center justify-center rounded-full bg-purple-500 text-white text-[9px] font-bold px-1">
                    {Object.values(synonyms).flat().length}
                  </span>
                )}
              </button>
            </div>
            {searchMode === 'broad' && synonymsReady && (
              <span className="text-[11px] text-muted">
                {Object.entries(synonyms).filter(([, s]) => s.length > 0).map(([w, s]) => (
                  <span key={w} className="mr-3">
                    <span className="text-purple-400 font-semibold">{w}</span>
                    <span className="text-muted/60"> → {s.join(', ')}</span>
                  </span>
                ))}
              </span>
            )}
          </div>
        )}

        {/* ─── Results Table ─── */}
        {!loading && displayRows.length > 0 && (
          <ResultsTable
            rows={pagedRows}
            totalCount={displayRows.length}
            currentPage={currentPage}
            pageSize={PAGE_SIZE}
            onPageChange={setCurrentPage}
            sortKey={sortKey}
            sortDir={sortDir}
            onSort={handleSort}
            selectedProduct={selectedProduct}
            productPrice={productPrice}
            termRanks={termRanks}
            onSaveSegments={onSaveSegments}
            clusterSyn={searchMode === 'broad' && synonymsReady ? synonyms : undefined}
          />
        )}
      </Section>
    </>
  );
}
