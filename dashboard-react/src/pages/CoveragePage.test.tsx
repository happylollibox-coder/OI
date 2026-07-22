import { render, screen } from '@testing-library/react';
import { StrategyTile, CampaignEvidenceRow, KeywordRow, ProfitChip, ProfitRollup, MonthRow, KwMonthRow, groupByFamily, parseCampaignId } from './CoveragePage';

function cell(over: Partial<Parameters<typeof groupByFamily>[0][number]> = {}) {
  return {
    grain: 'ASIN' as const,
    parent_name: 'LolliME',
    asin: 'B01',
    product_short_name: 'Journal',
    strategy: 'AUTO',
    expected: true,
    n_enabled: 0,
    n_any: 0,
    impressions: 0,
    clicks: 0,
    units: 0,
    net_roas: null,
    campaigns: null,
    suppressed: false,
    status: 'ok' as const,
    reason: '',
    cell_key: 'k',
    cost: 0,
    cpc: null,
    profit_state: 'unknown',
    ...over,
  };
}

test('groupByFamily clusters cells by parent_name and labels null as Store', () => {
  const groups = groupByFamily([
    cell({ parent_name: 'LolliME', asin: 'B01', cell_key: 'a', status: 'ok' }),
    cell({ parent_name: 'Bottle', asin: 'B02', cell_key: 'b', status: 'missing' }),
    cell({ parent_name: 'LolliME', asin: 'B03', cell_key: 'c', status: 'missing' }),
    cell({ parent_name: null, asin: null, cell_key: 'd', status: 'ok', grain: 'STORE' }),
  ]);
  // LolliME (1 missing) and Bottle (1 missing) sort before Store (0 missing); tie broken by name
  expect(groups.map(g => g.family)).toEqual(['Bottle', 'LolliME', 'Store']);
  const lollime = groups.find(g => g.family === 'LolliME')!;
  expect(lollime.cells.map(c => c.cell_key)).toEqual(['c', 'a']); // missing sorts before ok
  expect(lollime.missingCount).toBe(1);
  expect(groups.find(g => g.family === 'Store')!.family).toBe('Store');
});
test('tile shows defined + to-do counts', () => {
  render(<StrategyTile name="INTENT" t={{defined:1,missing:2,redundant:3,informational:0,suppressed:0}} open={false} onOpen={()=>{}} />);
  expect(screen.getByText(/1 defined/)).toBeInTheDocument();
  expect(screen.getByText(/2 to do/)).toBeInTheDocument();
});
test('informational strategy shows no to-do', () => {
  render(<StrategyTile name="EXACT_BOOST" t={{defined:2,missing:0,redundant:0,informational:4,suppressed:0}} open={false} onOpen={()=>{}} />);
  expect(screen.queryByText(/to do/)).toBeNull();
  expect(screen.getByText(/4 idle/)).toBeInTheDocument();
});
test('unmapped tile shows count', () => {
  render(<StrategyTile name="UNMAPPED" t={{defined:0,missing:0,redundant:0,informational:8,suppressed:0}} open={false} onOpen={()=>{}} />);
  expect(screen.getByText(/8 unmapped/)).toBeInTheDocument();
});
test('unmapped tile with zero shows none unmapped', () => {
  render(<StrategyTile name="UNMAPPED" t={{defined:0,missing:0,redundant:0,informational:0,suppressed:0}} open={false} onOpen={()=>{}} />);
  expect(screen.getByText(/none unmapped/)).toBeInTheDocument();
});
test('evidence row shows campaign name and state', () => {
  render(<CampaignEvidenceRow c={{campaign_id:'123', campaign_name:'ME-SP/PHRASE (Mint)', state:'ENABLED', is_enabled:true, impressions:100, clicks:12, units:3, ad_spend:9, net_roas:1.8, last_seen:'2026-07-21', cpc:0.75, profit_state:'profitable'}} />);
  expect(screen.getByText(/ME-SP\/PHRASE/)).toBeInTheDocument();
  expect(screen.getByText('ENABLED')).toBeInTheDocument();
});
test('keyword row: running shows spend and rank', () => {
  render(<KeywordRow k={{parent_name:'LolliME',match_type:'PHRASE',keyword_text:'cute diary',is_running:true,is_enabled:true,is_recommended:false,clicks:31,cost:30,net_profit:5,research_rank:82,overall_fit:80,is_relevant:true,ads_net_roas:2.12,rec_type:null,last_seen:'2026-07-21',status:'running',cpc:0.97,profit_state:'profitable',intent_key:'journal-diary',intent_label:'Journal / diary',is_brand:false,brand_name:null}} />);
  expect(screen.getByText(/cute diary/)).toBeInTheDocument();
  expect(screen.getByText(/rank 82/)).toBeInTheDocument();
});
test('keyword row: orphan shows reason', () => {
  render(<KeywordRow k={{parent_name:'Lollibox',match_type:'BROAD',keyword_text:'mystery box for girls',is_running:true,is_enabled:true,is_recommended:false,clicks:22,cost:21,net_profit:-21,research_rank:23,overall_fit:40,is_relevant:false,ads_net_roas:null,rec_type:null,last_seen:'2026-07-20',status:'orphan',cpc:0.95,profit_state:'unprofitable',intent_key:null,intent_label:null,is_brand:false,brand_name:null}} />);
  expect(screen.getByText(/not relevant/)).toBeInTheDocument();
});
// brand keyword row still renders (component is mode-agnostic; filtering happens in KeywordPanel)
test('brand keyword row renders', () => {
  render(<KeywordRow k={{parent_name:'LolliME',match_type:'PHRASE',keyword_text:'happy lolli journal',is_running:true,is_enabled:true,is_recommended:false,clicks:6,cost:3,net_profit:0,research_rank:15,overall_fit:40,is_relevant:true,ads_net_roas:null,rec_type:null,last_seen:'2026-07-20',status:'running',cpc:0.49,profit_state:'unknown',intent_key:null,intent_label:null,is_brand:true,brand_name:'Happy Lolli'}} />);
  expect(screen.getByText(/happy lolli journal/)).toBeInTheDocument();
});
test('profit rollup shows counts and net split', () => {
  render(<ProfitRollup s={{total:22,profitable:2,net_profit_profitable:116,net_profit_unprofitable:-979}} />);
  expect(screen.getByText(/2\/22 profit/)).toBeInTheDocument();
  expect(screen.getByText(/\+\$116/)).toBeInTheDocument();
  expect(screen.getByText(/979/)).toBeInTheDocument();
});
test('profit rollup shows no-spend for empty', () => {
  render(<ProfitRollup s={{total:0,profitable:0,net_profit_profitable:0,net_profit_unprofitable:0}} />);
  expect(screen.getByText(/no spend/)).toBeInTheDocument();
});
test('month row shows month and net profit', () => {
  render(<MonthRow m={{month:'2026-05-01', impressions:1000, clicks:170, spend:148, units:17, net_profit:58, net_roas:1.39}} />);
  expect(screen.getByText(/2026-05/)).toBeInTheDocument();
  expect(screen.getByText(/1\.39x/)).toBeInTheDocument();
});
test('keyword month row shows month and spend', () => {
  render(<KwMonthRow m={{month:'2026-03-01', clicks:710, spend:943, units:21, impressions:66272}} />);
  expect(screen.getByText(/2026-03/)).toBeInTheDocument();
  expect(screen.getByText(/710 clk/)).toBeInTheDocument();
});
test('month row shows cpc', () => {
  render(<MonthRow m={{month:'2026-03-01', impressions:1000, clicks:100, spend:50, units:5, net_profit:10, net_roas:1.2}} />);
  expect(screen.getByText(/\$0\.50 cpc/)).toBeInTheDocument();
});
test('parseCampaignId pulls the id out of an UNMAPPED cell_key', () => {
  expect(parseCampaignId('UNMAPPED|1234567890')).toBe('1234567890');
  expect(parseCampaignId('UNMAPPED')).toBe('');
});
test('profit chip renders verdict', () => {
  const { rerender } = render(<ProfitChip state="profitable" />);
  expect(screen.getByText(/profit/i)).toBeInTheDocument();
  rerender(<ProfitChip state="unprofitable" />);
  expect(screen.getByText(/loss/i)).toBeInTheDocument();
});
