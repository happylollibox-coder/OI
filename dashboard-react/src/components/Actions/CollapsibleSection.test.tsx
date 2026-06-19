import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CollapsibleSection } from './CollapsibleSection';

beforeEach(() => localStorage.clear());

describe('CollapsibleSection', () => {
  it('starts collapsed by default and shows the summary, hides the body', () => {
    render(
      <CollapsibleSection id="t1" title="Budget" summary={<span>summary-here</span>} queueableCount={3} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    expect(screen.getByText('summary-here')).toBeTruthy();
    expect(screen.queryByText('body-content')).toBeNull();
  });

  it('expands on header click and reveals the body', () => {
    render(
      <CollapsibleSection id="t2" title="Budget" summary={null} queueableCount={3} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Budget/ }));
    expect(screen.getByText('body-content')).toBeTruthy();
  });

  it('disables Queue all when nothing is queueable, Unqueue all when nothing queued', () => {
    const onQueueAll = vi.fn(), onUnqueueAll = vi.fn();
    render(
      <CollapsibleSection id="t3" title="Budget" summary={null} queueableCount={0} queuedCount={0}
        onQueueAll={onQueueAll} onUnqueueAll={onUnqueueAll}>
        <div />
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Queue all/ }));
    fireEvent.click(screen.getByRole('button', { name: /Unqueue all/ }));
    expect(onQueueAll).not.toHaveBeenCalled();
    expect(onUnqueueAll).not.toHaveBeenCalled();
  });

  it('fires Queue all / Unqueue all when enabled', () => {
    const onQueueAll = vi.fn(), onUnqueueAll = vi.fn();
    render(
      <CollapsibleSection id="t3b" title="Budget" summary={null} queueableCount={3} queuedCount={1}
        onQueueAll={onQueueAll} onUnqueueAll={onUnqueueAll}>
        <div />
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Queue all/ }));
    fireEvent.click(screen.getByRole('button', { name: /Unqueue all/ }));
    expect(onQueueAll).toHaveBeenCalledTimes(1);
    expect(onUnqueueAll).toHaveBeenCalledTimes(1);
  });

  it('persists collapse state per id across remounts', () => {
    const { unmount } = render(
      <CollapsibleSection id="t4" title="Budget" summary={null} queueableCount={1} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Budget/ })); // expand
    unmount();
    render(
      <CollapsibleSection id="t4" title="Budget" summary={null} queueableCount={1} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    expect(screen.getByText('body-content')).toBeTruthy(); // still expanded
  });
});
