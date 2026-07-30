import { useState } from 'react';
import { apiFetch } from '../utils/apiFetch';
import { useDoQueue } from '../hooks/useDoQueue';

// Inline campaign management for the Weekly Run campaign rows. Four actions:
//  • Map      — assign family + strategy → POST /api/admin/campaign-mapping/assign (upserts
//               DIM_EXPERIMENT_CAMPAIGN). This is what unblocks an unmapped campaign so the bid
//               engine can manage it (NEEDS_STRATEGY → real decisions on the next refresh).
//  • Rename   — queue a Campaign-rename bulksheet row (prepare-only; exported on the Do page).
//  • Pause/Enable — queue a Campaign State change row.
//  • Open in Amazon Ads — deep-ish link to the console (best effort; per-campaign deep link needs
//               the advertiser entity id we don't store, so this opens the campaign manager).
// Mapping option lists mirror the Flask constants (MAPPING_FAMILIES / MAPPING_STRATEGIES).
// 'Store' = a cross-product campaign (advertises >1 family, e.g. a brand-store defense campaign).
// The per-keyword family still comes from each ad's ASIN; the mapping just sets the strategy so
// the engine manages it. camp.product is already 'Store' for these, so the modal pre-selects it.
const FAMILIES = ['Bottle', 'Bunny', 'Fresh', 'LolliBall', 'LolliME', 'Lollibox', 'Store'];
const STRATEGIES = ['AUTO', 'BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'PHRASE', 'EXACT', 'COMPETITOR', 'BRAND_DEFENSE', 'PRODUCT_DEFENSE'];

export type ManageCampaign = {
  id: string;
  campaignName: string;
  product: string;
  isSB: boolean;
  currentStrategyId: string;
  suggestedFamily: string;
  suggestedStrategy: string;
};

export function CampaignManageModal({ camp, onClose }: { camp: ManageCampaign; onClose: () => void }) {
  const doQueue = useDoQueue();
  const knownFamily = FAMILIES.includes(camp.product) ? camp.product : '';
  const [family, setFamily] = useState(camp.suggestedFamily || knownFamily || '');
  const [strategy, setStrategy] = useState(camp.currentStrategyId || camp.suggestedStrategy || '');
  const [newName, setNewName] = useState(camp.campaignName);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const campaignType = camp.isSB ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS';

  const saveMapping = async () => {
    if (!family || !strategy) { setMsg('Pick a family and a strategy.'); return; }
    setSaving(true); setMsg(null);
    try {
      const res = await apiFetch('/api/admin/campaign-mapping/assign', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ campaign_id: camp.id, family, strategy }),
      });
      const body = await res.json().catch(() => ({} as { success?: boolean; error?: string }));
      const ok = res.ok && body?.success !== false;
      // Surface the REAL reason instead of a generic fail — a 401 means the login token expired
      // (reload re-issues it); a 400 carries the backend's message (e.g. unknown family/strategy).
      const why = res.status === 401
        ? 'session expired — reload the page to re-login, then retry'
        : (body?.error || `HTTP ${res.status}`);
      setMsg(ok ? '✓ Mapped — the coach will manage it after the next refresh.' : `✗ ${why}`);
    } catch { setMsg('✗ Mapping failed (network/offline?) — reload and retry.'); }
    setSaving(false);
  };

  const queueRename = () => {
    const trimmed = newName.trim();
    if (!trimmed || trimmed === camp.campaignName) { setMsg('Enter a different name.'); return; }
    doQueue.addItem({
      search_term: '', action: 'CAMPAIGN_RENAME', campaign: camp.campaignName, campaign_id: camp.id,
      ad_group_id: '', targeting: '', keyword_id: '', match_type: '', new_campaign_name: trimmed,
      target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
      campaign_type: campaignType, product: camp.product, spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'MANUAL',
    });
    setMsg('✓ Rename queued — export the bulksheet on the Do page.');
  };

  const queueState = (state: 'enabled' | 'paused') => {
    doQueue.addItem({
      search_term: state, action: state === 'paused' ? 'CAMPAIGN_PAUSE' : 'CAMPAIGN_ENABLE',
      campaign: camp.campaignName, campaign_id: camp.id, ad_group_id: '', targeting: '', keyword_id: '', match_type: '',
      target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
      campaign_type: campaignType, product: camp.product, spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'MANUAL',
    });
    setMsg(`✓ ${state === 'paused' ? 'Pause' : 'Enable'} queued — export the bulksheet on the Do page.`);
  };

  const inputCls = 'w-full text-label bg-surface/40 border border-border rounded-md px-2 py-1 focus:outline-none focus:ring-1 focus:ring-blue-500/40';
  const btnCls = 'text-label px-3 py-1.5 rounded-md border border-blue-500/40 text-blue-400 hover:bg-blue-500/10 disabled:opacity-50';

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div className="bg-card border border-border rounded-xl p-4 w-full max-w-md max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-2 mb-3">
          <div className="text-body font-medium text-text min-w-0 truncate" title={camp.campaignName}>{camp.campaignName}</div>
          <button onClick={onClose} className="text-faint hover:text-text shrink-0">✕</button>
        </div>

        {/* Map */}
        <div className="rounded-lg border border-border/70 p-3 mb-3">
          <div className="text-label font-medium text-muted mb-2">Strategy mapping {!camp.currentStrategyId && <span className="text-amber-400">· not mapped</span>}</div>
          <div className="grid grid-cols-2 gap-2 mb-2">
            <label className="text-label text-faint">Family
              <select value={family} onChange={e => setFamily(e.target.value)} className={inputCls}>
                <option value="">—</option>{FAMILIES.map(f => <option key={f} value={f}>{f === 'Store' ? 'Store (mixed products)' : f}</option>)}
              </select>
            </label>
            <label className="text-label text-faint">Strategy
              <select value={strategy} onChange={e => setStrategy(e.target.value)} className={inputCls}>
                <option value="">—</option>{STRATEGIES.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </label>
          </div>
          <button disabled={saving} onClick={saveMapping} className={`${btnCls} border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10`}>
            {saving ? 'Saving…' : 'Save mapping'}
          </button>
        </div>

        {/* Rename */}
        <div className="rounded-lg border border-border/70 p-3 mb-3">
          <div className="text-label font-medium text-muted mb-2">Rename campaign</div>
          <input value={newName} onChange={e => setNewName(e.target.value)} className={`${inputCls} mb-2`} />
          <button onClick={queueRename} className={btnCls}>Queue rename</button>
        </div>

        {/* State */}
        <div className="rounded-lg border border-border/70 p-3 mb-3">
          <div className="text-label font-medium text-muted mb-2">Campaign state</div>
          <div className="flex gap-2">
            <button onClick={() => queueState('paused')} className="text-label px-3 py-1.5 rounded-md border border-red-500/40 text-red-400 hover:bg-red-500/10">Queue pause</button>
            <button onClick={() => queueState('enabled')} className="text-label px-3 py-1.5 rounded-md border border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10">Queue enable</button>
          </div>
        </div>

        {/* Amazon link */}
        <a href="https://advertising.amazon.com/cb/campaigns" target="_blank" rel="noopener noreferrer"
          className="text-label text-blue-400 hover:underline">Open in Amazon Ads console ↗</a>

        {msg && <div className="text-label mt-3 text-muted">{msg}</div>}
      </div>
    </div>
  );
}
