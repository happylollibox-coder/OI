import { render, screen } from '@testing-library/react';
import { StrategyTile, CampaignEvidenceRow } from './CoveragePage';
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
