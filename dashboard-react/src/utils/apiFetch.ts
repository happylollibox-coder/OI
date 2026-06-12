// All dashboard calls to the Flask /api/* endpoints must go through apiFetch:
// it attaches the dashboard JWT, which the backend now requires
// (see architecture/API_AUTH.md). Never call fetch('/api/…') directly.
export function apiFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const token = localStorage.getItem('dashboard_token');
  const headers = new Headers(init.headers || {});
  if (token && !headers.has('Authorization')) {
    headers.set('Authorization', `Bearer ${token}`);
  }
  return fetch(input, { ...init, headers });
}
