// All dashboard calls to the Flask /api/* endpoints must go through apiFetch:
// it attaches the dashboard JWT, which the backend now requires
// (see architecture/API_AUTH.md). Never call fetch('/api/…') directly.
//
// 401 self-heal: a stored token can be invalid in ways the client can't
// detect (signed with a rotated CUBEJS_API_SECRET, or a Google credential
// JWT planted by the login screen — the API only accepts Flask-issued HS256
// tokens). On a 401 we clear the token and bounce through the Flask
// bootstrap endpoint, which re-issues a valid token via Google OAuth and
// redirects back here with ?token=. Loop-guarded to one attempt per minute.
// Note: on local Vite dev the bounce lands on the prod dashboard URL —
// local dev sessions should use the LOCAL_DEV_TOKEN bypass instead.

const REAUTH_AT_KEY = 'apiFetch_reauth_at';

export async function apiFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const token = localStorage.getItem('dashboard_token');
  const headers = new Headers(init.headers || {});
  if (token && !headers.has('Authorization')) {
    headers.set('Authorization', `Bearer ${token}`);
  }
  const res = await fetch(input, { ...init, headers });

  if (res.status === 401) {
    if (import.meta.env.DEV) {
      // Dev: the bounce would land on the prod dashboard URL — fail loudly instead.
      console.warn(`[apiFetch] 401 from ${typeof input === 'string' ? input : ''} — dashboard_token is invalid for this backend (rotated secret?). Get a fresh one via /api/auth/dashboard-token.`);
      return res;
    }
    const lastAttempt = Number(sessionStorage.getItem(REAUTH_AT_KEY) || 0);
    if (Date.now() - lastAttempt > 60_000) {
      sessionStorage.setItem(REAUTH_AT_KEY, String(Date.now()));
      localStorage.removeItem('dashboard_token');
      window.location.assign('/api/auth/dashboard-token');
    }
  }
  return res;
}
