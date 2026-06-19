/** Append a window label to a Section count string (e.g. "82 active · week of Jun 8–14"). */
export function withWindow(count: string, windowLabel: string): string {
  return windowLabel ? `${count} · ${windowLabel}` : count;
}
