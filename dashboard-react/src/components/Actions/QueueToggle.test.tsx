import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QueueToggle } from './QueueToggle';

describe('QueueToggle', () => {
  it('shows add affordance and calls onQueue when not queued', () => {
    const onQueue = vi.fn(), onUnqueue = vi.fn();
    render(<QueueToggle queued={false} onQueue={onQueue} onUnqueue={onUnqueue} />);
    fireEvent.click(screen.getByRole('button', { name: /^queue$/i }));
    expect(onQueue).toHaveBeenCalledTimes(1);
    expect(onUnqueue).not.toHaveBeenCalled();
  });

  it('shows unqueue affordance and calls onUnqueue when queued', () => {
    const onQueue = vi.fn(), onUnqueue = vi.fn();
    render(<QueueToggle queued={true} onQueue={onQueue} onUnqueue={onUnqueue} />);
    fireEvent.click(screen.getByRole('button', { name: /unqueue/i }));
    expect(onUnqueue).toHaveBeenCalledTimes(1);
    expect(onQueue).not.toHaveBeenCalled();
  });
});
