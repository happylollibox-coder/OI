import { render, screen } from '@testing-library/react';
import { StrategyTile } from './CoveragePage';
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
