# Airport Flight and Passenger Management System

A Flask and MySQL operations system for managing flight schedules, passengers, bookings, tickets, payments, baggage, and airport reference data. The existing database-backed API and SQL rules are retained; this project includes a responsive browser dashboard and DBMS documentation.

## Problem statement and objectives

Airport operations rely on related information about flights, airlines, aircraft, gates, passengers, and reservations. Disconnected records make it harder to prevent conflicting schedules, invalid references, and duplicate seat allocation. This project demonstrates a normalized relational design, database-enforced rules, and a small web application for staff workflows.

## Features

- JWT sign-in and role checks for Admin, Staff, and Agent.
- Dashboard statistics and recent booking/flight data from MySQL.
- Flight search and detail, seat map, and passenger manifest endpoints.
- Passenger, airline, airport, aircraft, gate, and crew management API.
- Transactional booking/ticket/payment creation and cancellation with seat reuse.
- Payment, baggage, check-in/boarding, user management, and audit endpoints.
- SQL constraints, indexes, triggers, stored procedures, and reporting views.
- Responsive HTML, CSS, and JavaScript served by Flask.

## Technology and architecture

Browser (`frontend/index.html`, `styles.css`, `app.js`) → same-origin JSON requests → Flask API (`backend/`) → parameterized SQL/stored procedures → MySQL 8.0.16+ (`airport_db`). The browser never connects directly to MySQL. The schema uses InnoDB, enforced CHECK constraints, and stored routines.

## Project structure

```text
airport-system/
├── backend/       Flask app, routes, config, auth, tests, requirements
├── database/      schema.sql, seed_data.sql, triggers.sql, procedures.sql, views.sql
├── docs/          API contract, ER/schema/SQL/testing/viva guides
└── frontend/      index.html, styles.css, app.js
```

## Database initialization

Use a dedicated disposable development database. **`database/schema.sql` begins with `DROP DATABASE IF EXISTS airport_db` and recreates it.** Do not run it against production, shared, or cloud data you need to retain.

Run these files in order in MySQL Workbench or the MySQL CLI:

1. `database/schema.sql`
2. `database/seed_data.sql`
3. `database/triggers.sql`
4. `database/procedures.sql`
5. `database/views.sql`

## Backend setup (Windows PowerShell)

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
```

Configure these values in `backend/.env` (or in the process environment, which takes precedence over `.env`):

- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`: the MySQL server connection. Keep the host and port for your existing cloud server if that is where your database lives; the current local `.env` points to `localhost:3306`.
- `DB_NAME`: database name; the current schema and routines use `airport_db`.
- `SECRET_KEY`: a unique random value used to sign JWTs. Generate one locally with `python -c "import secrets; print(secrets.token_urlsafe(48))"`, then paste it into `.env`. Never share or commit it.
- `JWT_EXPIRY_HOURS`: token lifetime (default 8).

Replace the example DB password and signing key before use. The app refuses to start with the example signing key. The root `.gitignore` excludes `.env` at any directory depth and explicitly excludes `backend/.env`; never commit it.

Start the service from `backend/`:

```powershell
python app.py
```

Open [http://localhost:5000](http://localhost:5000). `/api/health` reports whether MySQL can be reached. The UI and API use one origin, so CORS is not enabled.

**Verified workspace status (2026-10-24):** the configured local MySQL connection is working and the live `/api/health` response is `{"database":true,"status":"ok"}`. Read-only inspection found 18 base tables, 23 foreign keys, 21 triggers, and 10 stored procedures. The three reporting views described in `database/views.sql` were missing; those exact `CREATE OR REPLACE VIEW` definitions have now been installed and queried successfully. No pre-existing table or record was deleted or recreated. The server reports version `26.7.0`; the schema documentation's MySQL 8.0.16+ minimum is therefore not a literal version match, although the installed routines, triggers, views, and tested application paths worked on this server. Keep the existing host and credentials in `backend/.env`; do not replace a hosted database configuration with local settings.

The seed script contains demo account credentials; inspect its account section for the values and replace them before any shared deployment. These sample credentials are for local demonstration only.

## API and documentation

See [docs/API_CONTRACT.md](docs/API_CONTRACT.md) for routes, request fields, roles, and JSON errors. See [docs/ER_DIAGRAM.md](docs/ER_DIAGRAM.md), [docs/RELATIONAL_SCHEMA.md](docs/RELATIONAL_SCHEMA.md), [docs/SQL_FEATURES.md](docs/SQL_FEATURES.md), and [docs/VIVA_PREPARATION.md](docs/VIVA_PREPARATION.md) for DBMS and demonstration material.

## Testing

- Python syntax: `python -m compileall -q backend` from the repository root.
- JavaScript syntax: `node --check frontend/app.js`.
- Safe live MySQL/API verification: from the repository root, run `backend\venv\Scripts\python.exe backend\tests\test_live_safe.py` (or activate your backend virtual environment and run `python tests/test_live_safe.py` from `backend/`). It creates run-unique temporary records and removes only those records in a `finally` cleanup. Latest verified run: 130 checks passed, all 62 API route-method pairs were exercised, and cleanup reported zero errors.
- `backend/tests/test_api.py` is a legacy data-writing test with fixed sample expectations and instructions to reinitialize the schema before reruns. It was not run against the existing database; use only with a disposable isolated database after adapting its assumptions.
- Manual smoke test: sign in, inspect dashboard, search flights, create a passenger/booking, inspect baggage/payments, and sign out.

See [docs/TESTING.md](docs/TESTING.md) for verified results and remaining limits. The browser page, JavaScript and CSS assets, and API health endpoint were also checked over `http://127.0.0.1:5000/`.
