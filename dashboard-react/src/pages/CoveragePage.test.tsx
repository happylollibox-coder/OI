import { render, screen } from '@testing-library/react';
import { StrategyTile, CampaignEvidenceRow, KeywordRow } from './CoveragePage';
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
test('evidence row shows campaign name and state', () => {
  render(<CampaignEvidenceRow c={{campaign_name:'ME-SP/PHRASE (Mint)', state:'ENABLED', is_enabled:true, impressions:100, clicks:12, units:3, ad_spend:9, net_roas:1.8, last_seen:'2026-07-21'}} />);
  expect(screen.getByText(/ME-SP\/PHRASE/)).toBeInTheDocument();
  expect(screen.getByText('ENABLED')).toBeInTheDocument();
});
test('keyword row: running shows spend and rank', () => {
  render(<KeywordRow k={{parent_name:'LolliME',match_type:'PHRASE',keyword_text:'cute diary',is_running:true,is_enabled:true,is_recommended:false,clicks:31,cost:30,net_profit:5,research_rank:82,overall_fit:80,is_relevant:true,ads_net_roas:2.12,rec_type:null,last_seen:'2026-07-21',status:'running'}} />);
  expect(screen.getByText(/cute diary/)).toBeInTheDocument();
  expect(screen.getByText(/rank 82/)).toBeInTheDocument();
});
test('keyword row: orphan shows reason', () => {
  render(<KeywordRow k={{parent_name:'Lollibox',match_type:'BROAD',keyword_text:'mystery box for girls',is_running:true,is_enabled:true,is_recommended:false,clicks:22,cost:21,net_profit:-21,research_rank:23,overall_fit:40,is_relevant:false,ads_net_roas:null,rec_type:null,last_seen:'2026-07-20',status:'orphan'}} />);
  expect(screen.getByText(/not relevant/)).toBeInTheDocument();
});
