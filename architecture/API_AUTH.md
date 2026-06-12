# Architecture SOP: API Authentication (data-entry Flask `/api/*`)

**Status:** Active (2026-06-12)
**Code:** `data-entry-app/app.py` (`protect_api` before_request hook) · `dashboard-react/src/utils/apiFetch.ts`

## 1. Problem

The Flask data-entry service is deployed with `--allow-unauthenticated` (Cloud Run) because
personal-Gmail users can't use IAP. HTML pages are protected by session login
(`@login_required` + `ALLOWED_USERS`), but all `/api/*` JSON endpoints (74 routes — plans,
conclusions, alerts, PPC change log) were fully public: anyone with the URL could read
business data and write fake rows (e.g. poison `FACT_PPC_CHANGE_LOG`).

## 2. Solution — one gate, two credentials

A single `@app.before_request` hook rejects any `/api/*` request (except CORS `OPTIONS`)
unless ONE of these holds:

| Caller | Credential | How it's checked |
|---|---|---|
| React dashboard | `Authorization: Bearer <JWT>` | HS256-verified against `CUBEJS_API_SECRET` — the same 30-day token Flask issues at Google login and Cube already verifies |
| Data-entry HTML pages (same origin) | Flask session cookie | `session['user']['email'] ∈ ALLOWED_USERS` |

No per-route decorators: new `/api/*` routes are protected by default. Failure returns
`401 {"error": "unauthorized"}`.

**Bootstrap exemption:** `/api/auth/dashboard-token` is exempt from the gate. It is the
endpoint that ISSUES the JWT, so it must be reachable without one (otherwise a secret
rotation locks everyone out: stale token → 401 → can't reach the token dispenser).
It enforces its own auth — it only issues a token to an `ALLOWED_USERS` session and
redirects everyone else into the Google OAuth flow.

## 3. Dashboard side

All `/api/*` calls go through `apiFetch()` (`src/utils/apiFetch.ts`), which injects
`Authorization: Bearer <localStorage.dashboard_token>`. **Rule: never call `fetch('/api/…')`
directly from dashboard code — use `apiFetch`.**

**401 self-heal:** a stored token can be invalid in ways the client cannot detect
(signed with a rotated secret, or a Google credential JWT planted by the login screen —
the gate only accepts Flask-issued HS256 tokens). On any 401, `apiFetch` clears
`dashboard_token` and navigates to `/api/auth/dashboard-token` (the bootstrap exemption),
which re-issues a valid token via Google OAuth and redirects back with `?token=`.
Loop-guarded to one attempt per minute via sessionStorage.

## 4. CORS

`Access-Control-Allow-Origin` is no longer `*`: the request `Origin` is echoed only if it is
in `ALLOWED_ORIGINS` (prod dashboard URLs + `http://localhost:5173`).

## 5. Production routing

The dashboard nginx (`dashboard-react/Dockerfile`) proxies `/api/` to
`data-entry-forms` **us-central1** (the instance with OAuth + secrets configured).
It previously pointed to the me-west1 duplicate, which had no env vars at all.

## 6. Operational notes

- Tokens are signed/verified with `CUBEJS_API_SECRET` (rotated 2026-06-12, lives in `OI/.env`,
  fail-closed on Cloud Run). Rotating it invalidates dashboard tokens → users re-login.
- Local dev: Vite dev server proxies `/api` and the dev bypass token is signed with the
  local dev secret — local Flask (non-managed runtime) accepts it via the same verify path.
- Stale duplicate Cloud Run services (data-entry-app ×3, oi-cube ×2, oi-cube-api,
  oi-data-entry, oi-data-entry-app, me-west1/zf copies) were deleted 2026-06-12.
