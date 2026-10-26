# Testing and verification

## Latest verified run — 2026-10-24

The live target was the existing `airport_db`; its tables were not recreated. The safe suite created uniquely marked temporary fixtures and deleted only those fixtures in a `finally` cleanup.

- `backend/venv/Scripts/python.exe -m compileall -q backend` — passed.
- `node --check frontend/app.js` — passed.
- `backend/venv/Scripts/python.exe backend/tests/test_live_safe.py` — **130 checks passed**, including all 62 registered API route-method pairs; cleanup had zero errors.
- HTTP smoke check against the running Flask server — `/`, `/app.js`, and `/styles.css` returned 200; `/api/health` returned `{"database":true,"status":"ok"}`.
- Live database inventory — 18 base tables, 23 foreign keys, 21 triggers, 10 stored procedures, and 3 reporting views.
- The three views in `database/views.sql` were absent at initial inspection. Those documented view definitions were applied with `CREATE OR REPLACE VIEW` and scoped queries against each view passed. This operation did not change table data.
- Exact last-run fixture markers were checked after cleanup; no test flight, airline, airport, aircraft, or passenger rows remained.

### What the safe live test covers

- Every registered Flask API method/route pair, including master-data CRUD, search/list/detail, flight operations, bookings, tickets, payments, baggage, check-in/boarding, audit, cancellations, health, and auth/user endpoints.
- Admin and Agent login, invalid password, role restrictions, and rejecting a deactivated user's token.
- Unique and check constraints, invalid foreign key references, flight endpoint validation, SQL-injection-shaped search input, duplicate seat rejection, and concurrent requests for one seat (exactly one succeeds).
- Booking procedure creation, failed-booking rollback, capacity limit, seat release/reuse after cancellation, ticket and payment state, cancellation refund, baggage fee/weight rules, check-in/boarding, and all three reporting views.
- SQL-backed application routines exercised through their API routes: dashboard stats, booking, cancellation, flight manifest, seat map, check-in, boarding, and flight search. Audit triggers were exercised by the temporary writes; flight, payment, baggage, and cancellation rules were exercised through their corresponding operations.

## Commands

From the repository root in PowerShell:

```powershell
backend/venv/Scripts/python.exe -m compileall -q backend
node --check frontend/app.js
backend/venv/Scripts/python.exe backend/tests/test_live_safe.py
```

To start the service:

```powershell
cd backend
venv/Scripts/Activate.ps1
python app.py
```

Open `http://127.0.0.1:5000/`; verify `http://127.0.0.1:5000/api/health` reports both `status: ok` and `database: true`.

## Not run / limits

- `backend/tests/test_api.py` was not run. It assumes fixed demo rows and explicitly instructs reinitializing SQL before reruns; it is not safe for an existing shared database. Use only with a disposable, isolated test database after adapting its assumptions.
- `database/schema.sql` was not run: it contains `DROP DATABASE IF EXISTS airport_db`. No drop/recreate, seed-data load, or broad destructive initialization was performed.
- The safe API test used Flask's test client with the real MySQL connection; the actual HTTP server was separately checked for health and frontend asset responses. Browser click-through of every UI workflow was not performed.
- SQL object existence was checked, and application-facing routine/trigger behavior was exercised as listed above. This was not a line-by-line proof of every trigger branch or every SQL edge case.
- The server identifies itself as version `26.7.0`; the README describes the schema target as MySQL 8.0.16+. Routine and feature checks passed on the configured server, but do not assume compatibility with other MySQL-compatible products or versions without testing.

## Safety notes

- Keep `backend/.env` local; `.gitignore` excludes `.env` and `backend/.env`. Configure `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `SECRET_KEY`, and optionally `JWT_EXPIRY_HOURS`. The tested target currently uses the local MySQL instance and `airport_db`; preserve existing connection values when switching between local/hosted environments.
- Never paste `.env` values into issue reports or commit them. Generate a new signing key locally with `python -c "import secrets; print(secrets.token_urlsafe(48))"`.
- `database/schema.sql` drops and recreates the hard-coded `airport_db`. Do not run it against data you need to preserve.
