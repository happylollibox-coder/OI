import { useState, useEffect, useCallback } from 'react';
import { Plus, Trash2, Copy, Upload, Search, X, Check, CheckSquare, Square, AlertTriangle, RefreshCw } from 'lucide-react';
import { Card } from './Card';
import { Badge } from './Badge';
import { apiFetch } from '../utils/apiFetch';

interface PhraseNegative {
  id: string;
  parent_name: string;
  product_short_name: string | null;
  phrase: string;
  match_type: string;
  source: string;
  status: string;
}

const FAMILIES = ['_ALL', 'Lollibox', 'Fresh', 'LolliME', 'Bottle', 'Bunny', 'LolliBall'];
const FAMILY_LABELS: Record<string, string> = {
  '_ALL': 'All Products',
  'Lollibox': 'Lollibox (BOX)',
  'Fresh': 'Fresh',
  'LolliME': 'LolliME (ME)',
  'Bottle': 'Bottle (DARE)',
  'Bunny': 'Bunny',
  'LolliBall': 'LolliBall',
};

const FLASK_API = '';

export function NegativePhrases() {
  const [phrases, setPhrases] = useState<PhraseNegative[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [activeFamily, setActiveFamily] = useState('_ALL');
  const [searchQuery, setSearchQuery] = useState('');

  // Add single phrase
  const [addInput, setAddInput] = useState('');
  const [addMatchType, setAddMatchType] = useState('Negative Phrase');

  // Bulk add
  const [showBulkAdd, setShowBulkAdd] = useState(false);
  const [bulkInput, setBulkInput] = useState('');
  const [bulkMatchType, setBulkMatchType] = useState('Negative Phrase');

  // Copy modal
  const [showCopyModal, setShowCopyModal] = useState(false);
  const [copyTo, setCopyTo] = useState('');

  // Selection
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Feedback
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; msg: string } | null>(null);
  const [pendingDelete, setPendingDelete] = useState<string | null>(null);

  const showFeedback = (type: 'success' | 'error', msg: string) => {
    setFeedback({ type, msg });
    setTimeout(() => setFeedback(null), 3000);
  };

  const fetchPhrases = useCallback(async () => {
    setLoading(true);
    setLoadError(false);
    try {
      const res = await apiFetch(`${FLASK_API}/api/admin/phrase-negatives`);
      if (res.ok) {
        const data = await res.json();
        if (data.success) setPhrases(data.phrases || []);
        else setLoadError(true);
      } else {
        setLoadError(true);
      }
    } catch (e) {
      console.error('Failed to fetch phrase negatives', e);
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchPhrases(); }, [fetchPhrases]);

  // Clear selection when switching families
  useEffect(() => { setSelectedIds(new Set()); }, [activeFamily]);

  // Filtered phrases for current tab + search
  const filtered = phrases
    .filter(p => p.parent_name === activeFamily)
    .filter(p => !searchQuery || p.phrase.toLowerCase().includes(searchQuery.toLowerCase()))
    .sort((a, b) => a.phrase.localeCompare(b.phrase));

  const familyCounts = FAMILIES.reduce((acc, f) => {
    acc[f] = phrases.filter(p => p.parent_name === f).length;
    return acc;
  }, {} as Record<string, number>);

  // Selection helpers
  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const selectAll = () => {
    setSelectedIds(new Set(filtered.map(p => p.id)));
  };

  const deselectAll = () => {
    setSelectedIds(new Set());
  };

  const hasSelection = selectedIds.size > 0;
  const allSelected = filtered.length > 0 && filtered.every(p => selectedIds.has(p.id));

  // Add single phrase
  const handleAdd = async () => {
    const phrase = addInput.trim().toLowerCase();
    if (!phrase) return;
    try {
      const res = await apiFetch(`${FLASK_API}/api/admin/phrase-negatives`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parent_name: activeFamily, phrase, match_type: addMatchType }),
      });
      const data = await res.json();
      if (data.success) {
        setAddInput('');
        showFeedback('success', `Added "${phrase}"`);
        fetchPhrases();
      } else {
        showFeedback('error', data.error || 'Failed to add');
      }
    } catch (e) {
      showFeedback('error', 'Network error');
    }
  };

  // Delete phrase
  const handleDelete = async (id: string, phrase: string) => {
    try {
      const res = await apiFetch(`${FLASK_API}/api/admin/phrase-negatives/${id}`, { method: 'DELETE' });
      const data = await res.json();
      if (data.success) {
        showFeedback('success', `Removed "${phrase}"`);
        setPendingDelete(null);
        fetchPhrases();
      } else {
        showFeedback('error', data.error || 'Failed to delete');
      }
    } catch (e) {
      showFeedback('error', 'Network error');
    }
  };

  // Bulk add
  const handleBulkAdd = async () => {
    const lines = bulkInput.split('\n').map(l => l.trim().toLowerCase()).filter(Boolean);
    if (lines.length === 0) return;
    try {
      const res = await apiFetch(`${FLASK_API}/api/admin/phrase-negatives/bulk`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parent_name: activeFamily, phrases: lines, match_type: bulkMatchType }),
      });
      const data = await res.json();
      if (data.success) {
        setBulkInput('');
        setShowBulkAdd(false);
        showFeedback('success', `Added ${data.count} phrases`);
        fetchPhrases();
      } else {
        showFeedback('error', data.error || 'Failed to bulk add');
      }
    } catch (e) {
      showFeedback('error', 'Network error');
    }
  };

  // Copy phrases (all or selected)
  const handleCopy = async () => {
    if (!copyTo || copyTo === activeFamily) return;
    try {
      const body: Record<string, unknown> = { from_family: activeFamily, to_family: copyTo };
      if (hasSelection) {
        body.phrase_ids = Array.from(selectedIds);
      }
      const res = await apiFetch(`${FLASK_API}/api/admin/phrase-negatives/copy`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (data.success) {
        setShowCopyModal(false);
        setCopyTo('');
        setSelectedIds(new Set());
        showFeedback('success', `Copied ${data.copied} phrases to ${FAMILY_LABELS[copyTo] || copyTo} (${data.skipped} already existed)`);
        fetchPhrases();
      } else {
        showFeedback('error', data.error || 'Failed to copy');
      }
    } catch (e) {
      showFeedback('error', 'Network error');
    }
  };

  const copyCount = hasSelection ? selectedIds.size : (familyCounts[activeFamily] || 0);

  return (
    <div className="space-y-4">
      {/* Feedback toast */}
      {feedback && (
        <div className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-medium animate-in ${
          feedback.type === 'success' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-red-500/10 text-red-400 border border-red-500/20'
        }`}>
          {feedback.type === 'success' ? <Check size={16} /> : <X size={16} />}
          {feedback.msg}
        </div>
      )}

      {/* Family tabs */}
      <div className="flex flex-wrap gap-1.5">
        {FAMILIES.map(f => (
          <button
            key={f}
            onClick={() => { setActiveFamily(f); setSearchQuery(''); }}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
              activeFamily === f
                ? 'bg-blue-500/15 text-blue-400 border border-blue-500/30'
                : 'bg-surface/50 text-subtle border border-border/30 hover:border-border hover:text-default'
            }`}
          >
            {FAMILY_LABELS[f] || f}
            <span className="font-mono text-[10px] opacity-70">{familyCounts[f] || 0}</span>
          </button>
        ))}
      </div>

      {/* Toolbar: search + actions */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-[360px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-subtle" />
          <input
            type="text"
            placeholder="Search phrases…"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg bg-card border border-border/50 focus:border-blue-500/50 focus:outline-none transition-colors"
          />
          {searchQuery && (
            <button onClick={() => setSearchQuery('')} className="absolute right-2 top-1/2 -translate-y-1/2 text-subtle hover:text-default">
              <X size={14} />
            </button>
          )}
        </div>

        {/* Select all / deselect */}
        {filtered.length > 0 && (
          <button
            onClick={allSelected ? deselectAll : selectAll}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg border border-border/50 bg-card hover:border-border hover:bg-white/[.02] transition-all"
          >
            {allSelected ? <CheckSquare size={14} className="text-blue-400" /> : <Square size={14} />}
            {allSelected ? 'Deselect All' : 'Select All'}
          </button>
        )}

        <button
          onClick={() => setShowBulkAdd(!showBulkAdd)}
          className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg border border-border/50 bg-card hover:border-blue-500/40 hover:bg-blue-500/5 transition-all"
        >
          <Upload size={14} />
          Bulk Add
        </button>

        <button
          onClick={() => { setShowCopyModal(true); setCopyTo(''); }}
          className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg border bg-card transition-all ${
            hasSelection
              ? 'border-purple-500/40 bg-purple-500/5 text-purple-300'
              : 'border-border/50 hover:border-purple-500/40 hover:bg-purple-500/5'
          }`}
        >
          <Copy size={14} />
          {hasSelection ? `Copy ${selectedIds.size} selected to…` : 'Copy to…'}
        </button>

        {hasSelection && (
          <button
            onClick={deselectAll}
            className="flex items-center gap-1 px-2 py-2 text-xs text-subtle hover:text-default transition-colors"
          >
            <X size={12} />
            Clear
          </button>
        )}
      </div>

      {/* Add single phrase inline */}
      <div className="flex items-center gap-2">
        <div className="relative flex-1 max-w-[400px]">
          <Plus size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-subtle" />
          <input
            type="text"
            placeholder={`Add phrase to ${FAMILY_LABELS[activeFamily] || activeFamily}…`}
            value={addInput}
            onChange={e => setAddInput(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter') handleAdd(); }}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg bg-card border border-border/50 focus:border-emerald-500/50 focus:outline-none transition-colors"
          />
        </div>
        <select
          value={addMatchType}
          onChange={e => setAddMatchType(e.target.value)}
          className="px-2 py-2 text-xs rounded-lg bg-card border border-border/50 text-subtle"
        >
          <option value="Negative Phrase">Phrase</option>
          <option value="Negative Exact">Exact</option>
        </select>
        <button
          onClick={handleAdd}
          disabled={!addInput.trim()}
          className="px-3 py-2 text-xs font-semibold rounded-lg bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 hover:bg-emerald-500/25 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
        >
          Add
        </button>
      </div>

      {/* Bulk add panel */}
      {showBulkAdd && (
        <Card className="!p-4 space-y-3 border-blue-500/20 bg-blue-500/[.02]">
          <div className="flex items-center justify-between">
            <div className="text-sm font-semibold">Bulk Add to {FAMILY_LABELS[activeFamily] || activeFamily}</div>
            <button onClick={() => setShowBulkAdd(false)} className="text-subtle hover:text-default"><X size={16} /></button>
          </div>
          <p className="text-xs text-subtle">One phrase per line. Duplicates will be skipped.</p>
          <textarea
            value={bulkInput}
            onChange={e => setBulkInput(e.target.value)}
            placeholder={"word1\nword2\nanother phrase\n..."}
            rows={8}
            className="w-full px-3 py-2 text-sm font-mono rounded-lg bg-black/30 border border-border/50 focus:border-blue-500/50 focus:outline-none resize-y"
          />
          <div className="flex items-center gap-2">
            <select
              value={bulkMatchType}
              onChange={e => setBulkMatchType(e.target.value)}
              className="px-2 py-1.5 text-xs rounded-lg bg-card border border-border/50 text-subtle"
            >
              <option value="Negative Phrase">Negative Phrase</option>
              <option value="Negative Exact">Negative Exact</option>
            </select>
            <button
              onClick={handleBulkAdd}
              disabled={!bulkInput.trim()}
              className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold rounded-lg bg-blue-500/15 text-blue-400 border border-blue-500/30 hover:bg-blue-500/25 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
            >
              <Upload size={14} />
              Add {bulkInput.split('\n').filter(l => l.trim()).length} phrases
            </button>
          </div>
        </Card>
      )}

      {/* Copy modal */}
      {showCopyModal && (
        <Card className="!p-4 space-y-3 border-purple-500/20 bg-purple-500/[.02]">
          <div className="flex items-center justify-between">
            <div className="text-sm font-semibold">
              Copy {hasSelection ? `${selectedIds.size} selected` : 'all'} from {FAMILY_LABELS[activeFamily]}
            </div>
            <button onClick={() => setShowCopyModal(false)} className="text-subtle hover:text-default"><X size={16} /></button>
          </div>
          <p className="text-xs text-subtle">
            {hasSelection ? (
              <>Copy <strong>{selectedIds.size}</strong> selected phrases to another family. Existing phrases in the target won't be duplicated.</>
            ) : (
              <>Copy all <strong>{familyCounts[activeFamily] || 0}</strong> phrases from <strong>{FAMILY_LABELS[activeFamily]}</strong> to another family. Existing phrases in the target won't be duplicated. To copy specific phrases, select them first.</>
            )}
          </p>
          <div className="flex items-center gap-2">
            <select
              value={copyTo}
              onChange={e => setCopyTo(e.target.value)}
              className="px-3 py-2 text-sm rounded-lg bg-card border border-border/50 min-w-[180px]"
            >
              <option value="">Select target family…</option>
              {FAMILIES.filter(f => f !== activeFamily).map(f => (
                <option key={f} value={f}>{FAMILY_LABELS[f]} ({familyCounts[f] || 0})</option>
              ))}
            </select>
            <button
              onClick={handleCopy}
              disabled={!copyTo}
              className="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold rounded-lg bg-purple-500/15 text-purple-400 border border-purple-500/30 hover:bg-purple-500/25 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
            >
              <Copy size={14} />
              Copy {copyCount}
            </button>
          </div>
        </Card>
      )}

      {/* Phrases list */}
      {loading ? (
        <div className="py-12 text-center text-subtle text-sm animate-pulse">Loading phrases…</div>
      ) : loadError ? (
        <Card className="p-6 text-center text-sm border-dashed border-red-500/30">
          <AlertTriangle size={20} className="mx-auto mb-2 text-red-400" />
          <div className="text-default">Couldn't load negative phrases.</div>
          <div className="text-xs text-subtle mt-1">Is the data-entry API running? (local: Flask on :5050)</div>
          <button onClick={fetchPhrases} className="mt-3 inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-border bg-card hover:bg-white/[.04] transition-colors">
            <RefreshCw size={14} /> Retry
          </button>
        </Card>
      ) : filtered.length === 0 ? (
        <Card className="py-8 text-center text-subtle text-sm border-dashed">
          {searchQuery ? `No phrases matching "${searchQuery}"` : `No phrases for ${FAMILY_LABELS[activeFamily] || activeFamily}`}
        </Card>
      ) : (
        <div className="flex flex-wrap gap-1.5">
          {filtered.map(p => {
            const isSelected = selectedIds.has(p.id);
            return (
              <div
                key={p.id}
                className={`group flex items-center gap-1.5 pl-1.5 pr-1.5 py-1.5 rounded-lg text-xs font-mono border transition-all cursor-pointer ${
                  isSelected
                    ? 'bg-purple-500/10 border-purple-500/30 text-purple-200'
                    : p.match_type === 'Negative Exact'
                      ? 'bg-amber-500/[.06] border-amber-500/20 text-amber-200'
                      : 'bg-surface/50 border-border/30 text-default'
                }`}
                onClick={() => toggleSelect(p.id)}
              >
                {/* Checkbox */}
                <span className={`flex-shrink-0 w-4 h-4 rounded flex items-center justify-center transition-all ${
                  isSelected ? 'bg-purple-500/30 text-purple-300' : 'bg-white/[.04] text-transparent group-hover:text-subtle'
                }`}>
                  <Check size={10} />
                </span>
                <span>{p.phrase}</span>
                {p.match_type === 'Negative Exact' && (
                  <Badge variant="yellow">Exact</Badge>
                )}
                {pendingDelete === p.id ? (
                  <span className="flex items-center gap-0.5 ml-1" onClick={e => e.stopPropagation()}>
                    <button
                      onClick={() => handleDelete(p.id, p.phrase)}
                      className="p-1 rounded-md bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors"
                      title="Confirm delete"
                    >
                      <Check size={12} />
                    </button>
                    <button
                      onClick={() => setPendingDelete(null)}
                      className="p-1 rounded-md bg-surface text-subtle hover:text-default transition-colors"
                      title="Cancel"
                    >
                      <X size={12} />
                    </button>
                  </span>
                ) : (
                  <button
                    onClick={e => { e.stopPropagation(); setPendingDelete(p.id); }}
                    className="p-1 rounded-md text-transparent group-hover:text-subtle hover:!text-red-400 hover:bg-red-500/10 transition-all"
                    title="Remove"
                  >
                    <Trash2 size={12} />
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Footer stats */}
      {!loading && (
        <div className="text-[11px] text-faint flex items-center gap-3 pt-1">
          <span>Showing {filtered.length} of {familyCounts[activeFamily] || 0} phrases</span>
          {hasSelection && (
            <>
              <span>•</span>
              <span className="text-purple-400">{selectedIds.size} selected</span>
            </>
          )}
          <span>•</span>
          <span>Total across all families: {phrases.length}</span>
          {filtered.filter(p => p.match_type === 'Negative Exact').length > 0 && (
            <>
              <span>•</span>
              <span>{filtered.filter(p => p.match_type === 'Negative Exact').length} exact match</span>
            </>
          )}
        </div>
      )}
    </div>
  );
}
