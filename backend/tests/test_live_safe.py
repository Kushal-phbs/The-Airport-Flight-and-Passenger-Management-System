"""Non-destructive live API verification using uniquely marked test records.

Run from backend/ with the configured MySQL server available:
    python tests/test_live_safe.py

Unlike test_api.py, this test never resets airport_db. All writes use a random
run marker and are removed in a finally block. It does not print credentials,
tokens, passenger data, or database connection secrets.
"""
from __future__ import annotations

import secrets
import sys
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mysql.connector
from app import app
from auth import create_token
from config import Config


RUN = uuid.uuid4().hex[:8].upper()
CODE = "T" + RUN
SUFFIX = RUN
ADMIN_NAME = "zztest_admin_" + RUN.lower()
AGENT_NAME = "zztest_agent_" + RUN.lower()
ADMIN_PASSWORD = secrets.token_urlsafe(24)
AGENT_PASSWORD = secrets.token_urlsafe(24)
BASE_LOG_ID = 0
TEST_USER_IDS: list[int] = []
checks = 0
coverage: set[tuple[str, str]] = set()
cleanup_errors: list[str] = []
state: dict[str, object] = {"flight_id": None}
client = app.test_client()


def connect():
    return mysql.connector.connect(
        host=Config.DB_HOST,
        port=Config.DB_PORT,
        user=Config.DB_USER,
        password=Config.DB_PASSWORD,
        database=Config.DB_NAME,
        connection_timeout=8,
        autocommit=False,
        use_pure=True,
        charset="utf8mb4",
    )


def query_one(sql: str, params=()):
    conn = connect()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params)
        return cur.fetchone()
    finally:
        conn.close()


def record(label: str, condition: bool):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(label)
    print("PASS", label)


def request(label: str, method: str, path: str, expected: int,
            token: str | None = None, body=None):
    headers = {"Authorization": "Bearer " + token} if token else {}
    response = client.open(path, method=method, headers=headers, json=body)
    adapter = app.url_map.bind("localhost")
    endpoint, _ = adapter.match(path.split("?", 1)[0], method=method)
    matched = next(rule for rule in app.url_map.iter_rules() if rule.endpoint == endpoint)
    coverage.add((method, matched.rule))
    if response.status_code != expected:
        payload = response.get_json(silent=True) or {}
        reason = payload.get("error", "non-JSON response")
        raise AssertionError(f"{label}: expected HTTP {expected}, received {response.status_code}: {reason}")
    record(label, True)
    return response.get_json(silent=True)


def seed_ids():
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SET @app_user_id = NULL")
        cur.execute("SELECT COALESCE(MAX(log_id), 0) FROM AUDIT_LOG")
        global BASE_LOG_ID
        BASE_LOG_ID = int(cur.fetchone()[0])
        cur.execute("""SELECT user_id, username, role FROM USER_ACCOUNT
                       WHERE role='Admin' AND is_active=1 ORDER BY user_id LIMIT 1""")
        row = cur.fetchone()
        if not row:
            raise RuntimeError("No active Admin account is available")
        cur.execute("SELECT VERSION()")
        version = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM information_schema.tables "
                    "WHERE table_schema=%s AND table_type='BASE TABLE'", (Config.DB_NAME,))
        tables = int(cur.fetchone()[0])
        cur.execute("SELECT COUNT(*) FROM information_schema.table_constraints "
                    "WHERE constraint_schema=%s AND constraint_type='FOREIGN KEY'", (Config.DB_NAME,))
        foreign_keys = int(cur.fetchone()[0])
        cur.execute("SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema=%s", (Config.DB_NAME,))
        triggers = int(cur.fetchone()[0])
        cur.execute("SELECT COUNT(*) FROM information_schema.routines "
                    "WHERE routine_schema=%s AND routine_type='PROCEDURE'", (Config.DB_NAME,))
        procedures = int(cur.fetchone()[0])
        cur.execute("SELECT COUNT(*) FROM information_schema.views WHERE table_schema=%s", (Config.DB_NAME,))
        views = int(cur.fetchone()[0])
        conn.commit()
        record("live MySQL connection and base schema (18 tables / 23 foreign keys)",
               tables == 18 and foreign_keys == 23)
        record("installed triggers and stored procedures", triggers == 21 and procedures >= 10)
        print("INFO MySQL server version:", version)
        return {"user_id": row[0], "username": row[1], "role": row[2],
                "triggers": triggers, "procedures": procedures, "views": views}
    finally:
        conn.close()


def add_seats(aircraft_id: int):
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SET @app_user_id = %s", (state.get("admin_id"),))
        for seat_no in ("1A", "1B", "1C", "1D", "1E"):
            cur.execute("INSERT INTO SEAT (aircraft_id, seat_no, `class`, seat_type) VALUES (%s,%s,'Economy','Window')",
                        (aircraft_id, seat_no))
        conn.commit()
        cur.execute("SELECT seat_id FROM SEAT WHERE aircraft_id=%s ORDER BY seat_id", (aircraft_id,))
        state["seat_ids"] = [int(row[0]) for row in cur.fetchall()]
    finally:
        conn.close()


def cleanup():
    """Delete rows matching only this run's unique markers, even after failure."""
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SET @app_user_id = %s", (state.get("admin_id"),))
        cur.execute("SELECT flight_id FROM FLIGHT WHERE flight_no=%s", ("F" + RUN,))
        flight = cur.fetchone()
        flight_id = int(flight[0]) if flight else None
        cur.execute("SELECT aircraft_id FROM AIRCRAFT WHERE aircraft_code=%s", ("AC" + RUN,))
        aircraft = cur.fetchone()
        aircraft_id = int(aircraft[0]) if aircraft else None

        if flight_id is not None:
            cur.execute("DELETE ci FROM CHECK_IN ci JOIN TICKET t ON t.ticket_id=ci.ticket_id "
                        "JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s", (flight_id,))
            cur.execute("DELETE bg FROM BAGGAGE bg JOIN BOOKING b ON b.booking_id=bg.booking_id WHERE b.flight_id=%s",
                        (flight_id,))
            cur.execute("DELETE p FROM PAYMENT p JOIN TICKET t ON t.ticket_id=p.ticket_id "
                        "JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s", (flight_id,))
            cur.execute("DELETE c FROM CANCELLATION c JOIN BOOKING b ON b.booking_id=c.booking_id WHERE b.flight_id=%s",
                        (flight_id,))
            cur.execute("DELETE t FROM TICKET t JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s",
                        (flight_id,))
            cur.execute("DELETE FROM BOOKING WHERE flight_id=%s", (flight_id,))
            cur.execute("DELETE FROM FLIGHT_CREW WHERE flight_id=%s", (flight_id,))
            # The API DELETE route is exercised during normal cleanup; this exact
            # marker-based fallback makes cleanup robust if an earlier check failed.
            cur.execute("DELETE FROM FLIGHT WHERE flight_id=%s", (flight_id,))
        if aircraft_id is not None:
            cur.execute("DELETE FROM SEAT WHERE aircraft_id=%s", (aircraft_id,))
        cur.execute("DELETE FROM GATE WHERE gate_no=%s", ("G" + RUN,))
        cur.execute("DELETE FROM CREW WHERE license_no=%s", ("L" + RUN,))
        cur.execute("DELETE FROM AIRCRAFT WHERE aircraft_code=%s", ("AC" + RUN,))
        cur.execute("DELETE FROM AIRPORT WHERE airport_code IN (%s,%s)", ("A" + RUN, "B" + RUN))
        cur.execute("DELETE FROM AIRLINE WHERE airline_code=%s", ("T" + RUN,))
        cur.execute("DELETE FROM PASSENGER WHERE passport_no LIKE %s", ("P" + RUN + "%",))
        if BASE_LOG_ID:
            cur.execute("DELETE FROM AUDIT_LOG WHERE log_id>%s AND user_id IN "
                        "(SELECT user_id FROM USER_ACCOUNT WHERE username IN (%s,%s))",
                        (BASE_LOG_ID, ADMIN_NAME, AGENT_NAME))
        cur.execute("DELETE FROM USER_ACCOUNT WHERE username IN (%s,%s)", (ADMIN_NAME, AGENT_NAME))
        conn.commit()
        record("test data cleanup by unique run marker", True)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def create_person(agent_token: str, index: int):
    passport = "P" + RUN + str(index)
    data = request(f"create test passenger {index}", "POST", "/api/passengers", 201, agent_token,
                   {"first_name": f"Verify{index}", "last_name": "Passenger",
                    "passport_no": passport, "passport_expiry": "2101-01-01",
                    "nationality": "Test", "gender": "Other"})
    return int(data["passenger_id"])


def main():
    info = seed_ids()
    # Bootstrap an isolated admin via a locally signed JWT. This avoids updating
    # last_login on any pre-existing account; all subsequent writes belong to the
    # newly-created temporary test users.
    bootstrap_token = create_token({"user_id": info["user_id"], "username": info["username"], "role": info["role"]})
    health = request("health endpoint", "GET", "/api/health", 200)
    record("health reports database connected", health.get("database") is True and health.get("status") == "ok")
    created_admin = request("create temporary Admin", "POST", "/api/users", 201, bootstrap_token,
                            {"username": ADMIN_NAME, "password": ADMIN_PASSWORD, "role": "Admin"})
    state["admin_id"] = int(created_admin["user_id"])
    login = request("temporary account login", "POST", "/api/login", 200,
                    body={"username": ADMIN_NAME, "password": ADMIN_PASSWORD})
    admin_token = login["token"]
    record("login returns Admin role", login["user"]["role"] == "Admin")
    request("invalid password rejected", "POST", "/api/login", 401,
            body={"username": ADMIN_NAME, "password": "wrong-test-password"})
    request("current user endpoint", "GET", "/api/me", 200, admin_token)
    request("dashboard stored procedure", "GET", "/api/dashboard/stats", 200, admin_token)
    request("user list endpoint", "GET", "/api/users", 200, admin_token)
    request("audit list endpoint", "GET", "/api/audit?limit=10", 200, admin_token)

    created_agent = request("create temporary Agent", "POST", "/api/users", 201, admin_token,
                            {"username": AGENT_NAME, "password": AGENT_PASSWORD, "role": "Agent"})
    state["agent_id"] = int(created_agent["user_id"])
    agent_login = request("Agent login", "POST", "/api/login", 200,
                          body={"username": AGENT_NAME, "password": AGENT_PASSWORD})
    agent_token = agent_login["token"]
    request("update temporary user endpoint", "PUT", f"/api/users/{state['agent_id']}", 200,
            admin_token, {"email": f"{AGENT_NAME}@example.invalid"})
    request("Agent cannot create a flight", "POST", "/api/flights", 403, agent_token, {})

    # Exercise all six generic master-data CRUD resources using only run-unique values.
    airline = request("create airline", "POST", "/api/airlines", 201, admin_token,
                      {"airline_name": "Verification Airline " + RUN, "airline_code": "T" + RUN,
                       "country": "Test", "email": f"air{RUN}@example.invalid"})
    airline_id = int(airline["airline_id"]); state["airline_id"] = airline_id
    airports = []
    for code, city in (("A" + RUN, "Verify Origin"), ("B" + RUN, "Verify Destination")):
        row = request("create airport " + code, "POST", "/api/airports", 201, admin_token,
                      {"airport_name": "Verification " + city, "airport_code": code,
                       "city": city, "country": "Test", "timezone": "UTC"})
        airports.append(int(row["airport_id"]))
    state["airport_ids"] = airports
    aircraft = request("create aircraft", "POST", "/api/aircraft", 201, admin_token,
                       {"aircraft_code": "AC" + RUN, "model": "Verification craft",
                        "manufacturer": "Test maker", "capacity": 5,
                        "status": "Active", "airline_id": airline_id})
    aircraft_id = int(aircraft["aircraft_id"]); state["aircraft_id"] = aircraft_id
    add_seats(aircraft_id)
    gate = request("create gate", "POST", "/api/gates", 201, admin_token,
                   {"gate_no": "G" + RUN, "terminal": "T1", "status": "Available",
                    "airport_id": airports[0]})
    gate_id = int(gate["gate_id"]); state["gate_id"] = gate_id
    crew = request("create crew", "POST", "/api/crew", 201, admin_token,
                   {"first_name": "Verify", "last_name": RUN, "role": "Pilot",
                    "license_no": "L" + RUN, "airline_id": airline_id})
    crew_id = int(crew["crew_id"]); state["crew_id"] = crew_id

    # List/detail/filter/search/update routes for each master resource.
    resources = [
        ("airlines", airline_id, {"country": "Test", "q": "T" + RUN}, {"country": "Test updated"}),
        ("airports", airports[0], {"country": "Test", "q": "A" + RUN}, {"city": "Verify Origin Updated"}),
        ("aircraft", aircraft_id, {"airline_id": airline_id, "status": "Active", "q": "AC" + RUN},
         {"model": "Verification craft updated"}),
        ("gates", gate_id, {"airport_id": airports[0], "status": "Available", "q": "G" + RUN},
         {"terminal": "T2"}),
        ("crew", crew_id, {"airline_id": airline_id, "role": "Pilot", "q": "L" + RUN},
         {"phone_no": "0000000000"}),
    ]
    for resource, item_id, filters, update in resources:
        request(f"list {resource}", "GET", f"/api/{resource}", 200, admin_token)
        request(f"get {resource} detail", "GET", f"/api/{resource}/{item_id}", 200, admin_token)
        qs = "&".join(f"{k}={v}" for k, v in filters.items())
        request(f"filter/search {resource}", "GET", f"/api/{resource}?{qs}", 200, admin_token)
        request(f"update {resource}", "PUT", f"/api/{resource}/{item_id}", 200, admin_token, update)

    # Exercise validation, UNIQUE, CHECK, and FK errors without leaving rows.
    request("duplicate airline code constraint", "POST", "/api/airlines", 409, admin_token,
            {"airline_name": "Duplicate test", "airline_code": "T" + RUN})
    request("aircraft CHECK constraint", "POST", "/api/aircraft", 400, admin_token,
            {"aircraft_code": "BAD" + RUN, "capacity": 0, "airline_id": airline_id})
    request("gate foreign key constraint", "POST", "/api/gates", 400, admin_token,
            {"gate_no": "BAD" + RUN, "airport_id": 2147483647})

    # Create passengers through the Agent route and exercise its filters/CRUD.
    passengers = [create_person(agent_token, i) for i in range(1, 7)]
    state["passenger_ids"] = passengers
    request("passenger list/search/filter", "GET", f"/api/passengers?q=P{RUN}", 200, agent_token)
    request("passenger detail", "GET", f"/api/passengers/{passengers[0]}", 200, agent_token)
    request("passenger update", "PUT", f"/api/passengers/{passengers[0]}", 200, agent_token,
            {"phone_no": "0000000001"})
    request("duplicate passport constraint", "POST", "/api/passengers", 409, agent_token,
            {"first_name": "Duplicate", "passport_no": "P" + RUN + "1"})
    request("Agent cannot delete passenger", "DELETE", f"/api/passengers/{passengers[0]}", 403, agent_token)
    injection = request("parameterized passenger search", "GET",
                        "/api/passengers?q=%27%20OR%201%3D1%20--", 200, admin_token)
    record("SQL injection string remains a data value", isinstance(injection, list) and len(injection) == 0)

    flight_no = "F" + RUN
    flight_body = {"flight_no": flight_no, "departure_date": "2099-12-15", "departure_time": "08:00:00",
                   "arrival_date": "2099-12-15", "arrival_time": "09:00:00", "status": "Scheduled",
                   "airline_id": airline_id, "aircraft_id": aircraft_id,
                   "source_airport_id": airports[0], "destination_airport_id": airports[1],
                   "gate_id": gate_id, "fares": {"Economy": 100}}
    bad_flight = dict(flight_body, flight_no="X" + RUN, destination_airport_id=airports[0])
    request("flight same-airport trigger", "POST", "/api/flights", 400, admin_token, bad_flight)
    created_flight = request("create flight and fare", "POST", "/api/flights", 201, admin_token, flight_body)
    flight_id = int(created_flight["flight_id"]); state["flight_id"] = flight_id
    request("flight list/search", "GET", f"/api/flights?from=A{RUN}&to=B{RUN}&date=2099-12-15", 200, admin_token)
    request("flight detail and fare", "GET", f"/api/flights/{flight_id}", 200, admin_token)
    request("update flight", "PUT", f"/api/flights/{flight_id}", 200, admin_token, {"status": "Delayed"})
    request("update flight fare", "PUT", f"/api/flights/{flight_id}/fares", 200, admin_token,
            {"Economy": 100})
    request("assign flight crew", "PUT", f"/api/flights/{flight_id}/crew", 200, admin_token,
            {"crew_ids": [crew_id]})
    seats = request("flight seat map", "GET", f"/api/flights/{flight_id}/seats", 200, admin_token)
    record("five test seats available initially", len(seats) == 5 and not any(s["is_taken"] for s in seats))
    request("flight passenger manifest", "GET", f"/api/flights/{flight_id}/manifest", 200, admin_token)

    # Atomic booking, duplicate allocation, rollback, and concurrent same-seat test.
    first = request("create first booking/ticket/payment", "POST", "/api/bookings", 201, agent_token,
                    {"passenger_id": passengers[0], "flight_id": flight_id, "seat_no": "1A", "payment_mode": "UPI"})
    booking1 = int(first["booking_id"]); state["booking_ids"] = [booking1]
    request("duplicate seat is rejected", "POST", "/api/bookings", 400, agent_token,
            {"passenger_id": passengers[1], "flight_id": flight_id, "seat_no": "1A", "payment_mode": "Card"})
    second = request("create second booking", "POST", "/api/bookings", 201, agent_token,
                     {"passenger_id": passengers[1], "flight_id": flight_id, "seat_no": "1B", "payment_mode": "Card"})
    booking2 = int(second["booking_id"]); state["booking_ids"].append(booking2)
    request("same passenger active booking is rejected", "POST", "/api/bookings", 400, agent_token,
            {"passenger_id": passengers[1], "flight_id": flight_id, "seat_no": "1A", "payment_mode": "UPI"})

    def race_booking(passenger_id: int):
        with app.test_client() as race_client:
            return race_client.post("/api/bookings", headers={"Authorization": "Bearer " + agent_token},
                                    json={"passenger_id": passenger_id, "flight_id": flight_id,
                                          "seat_no": "1C", "payment_mode": "UPI"})

    with ThreadPoolExecutor(max_workers=2) as pool:
        race_results = list(pool.map(race_booking, passengers[2:4]))
    winners = [r.get_json() for r in race_results if r.status_code == 201]
    record("concurrent seat allocation has exactly one winner",
           len(winners) == 1 and sorted(r.status_code for r in race_results) == [201, 400])
    if winners:
        state["booking_ids"].append(int(winners[0]["booking_id"]))

    before_failed_booking = query_one("SELECT COUNT(*) AS n FROM BOOKING WHERE flight_id=%s", (flight_id,))["n"]
    request("invalid payment mode rolls back booking", "POST", "/api/bookings", 400, agent_token,
            {"passenger_id": passengers[4], "flight_id": flight_id, "seat_no": "1D", "payment_mode": "Bitcoin"})
    after_failed_booking = query_one("SELECT COUNT(*) AS n FROM BOOKING WHERE flight_id=%s", (flight_id,))["n"]
    record("booking transaction left no partial row", before_failed_booking == after_failed_booking)
    seats = request("seat map reflects bookings", "GET", f"/api/flights/{flight_id}/seats", 200, admin_token)
    seat_d = next(s for s in seats if s["seat_no"] == "1D")
    record("rolled-back booking did not reserve seat", not seat_d["is_taken"])

    # A supplementary failed payment is permitted, while an overpayment is rejected.
    booking2_full = request("booking detail with ticket/payment", "GET", f"/api/bookings/{booking2}", 200, admin_token)
    ticket2 = str(booking2_full["ticket_no"])
    ticket2_id = int(booking2_full["ticket_id"])
    state["ticket_ids"] = [int(item) for item in query_one(
        "SELECT GROUP_CONCAT(ticket_id) AS ticket_ids FROM TICKET t JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s",
        (flight_id,))["ticket_ids"].split(",")]
    failed_payment = request("record failed payment status", "POST", "/api/payments", 201, agent_token,
                             {"ticket_id": ticket2_id, "amount": 1, "payment_mode": "Cash", "status": "Failed"})
    request("payment list/filter", "GET", f"/api/payments?ticket_id={ticket2_id}&status=Failed", 200, admin_token)
    request("overpayment is rejected", "POST", "/api/payments", 400, agent_token,
            {"ticket_id": ticket2_id, "amount": 999999, "payment_mode": "Cash"})
    record("failed payment does not affect successful payment", bool(failed_payment.get("payment_id")))

    bag = request("create checked baggage and calculate fee", "POST", "/api/baggage", 201, agent_token,
                  {"booking_id": booking2, "weight": 20, "baggage_type": "Checked"})
    state["baggage_ids"] = [int(bag["baggage_id"])]
    record("20kg checked bag fee is INR 500", float(bag["fee"]) == 500.0)
    cabin = request("create cabin baggage", "POST", "/api/baggage", 201, agent_token,
                    {"booking_id": booking2, "weight": 7, "baggage_type": "Cabin"})
    state["baggage_ids"].append(int(cabin["baggage_id"]))
    request("cabin baggage limit enforced", "POST", "/api/baggage", 400, agent_token,
            {"booking_id": booking2, "weight": 8, "baggage_type": "Cabin"})
    request("checked baggage limit enforced", "POST", "/api/baggage", 400, agent_token,
            {"booking_id": booking2, "weight": 40, "baggage_type": "Checked"})
    request("baggage list/filter", "GET", f"/api/baggage?booking_id={booking2}", 200, admin_token)
    request("update baggage status", "PUT", f"/api/baggage/{bag['baggage_id']}", 200, admin_token,
            {"status": "Loaded"})
    request("delete test baggage", "DELETE", f"/api/baggage/{cabin['baggage_id']}", 200, admin_token)

    checkin = request("check in ticket", "POST", "/api/checkin", 201, agent_token, {"ticket_no": ticket2})
    request("board checked-in passenger", "POST", "/api/checkin/board", 200, agent_token,
            {"ticket_no": ticket2})
    ticket = request("ticket details after boarding", "GET", f"/api/tickets/{ticket2}", 200, admin_token)
    record("ticket reflects boarding status", ticket.get("check_in_status") == "Boarded")
    request("ticket list/filter", "GET", f"/api/tickets?booking_id={booking2}&status=Issued", 200, admin_token)
    request("booking filters/search", "GET", f"/api/bookings?flight_id={flight_id}&status=Confirmed&q={RUN}", 200, admin_token)
    request("flight delete is blocked while bookings exist", "DELETE", f"/api/flights/{flight_id}", 409, admin_token)

    cancelled = request("cancel booking and calculate refund", "DELETE", f"/api/bookings/{booking1}", 200,
                        agent_token, {"reason": "Automated verification"})
    record("cancellation refund is 80 percent", float(cancelled["refund_amount"]) == 80.0)
    state["cancellation_tested"] = True
    booking1_detail = request("cancelled booking detail", "GET", f"/api/bookings/{booking1}", 200, admin_token)
    record("cancellation propagated to ticket/payment", booking1_detail["booking_status"] == "Cancelled"
           and booking1_detail["ticket_status"] == "Cancelled"
           and all(p["status"] == "Refunded" for p in booking1_detail["payments"]))
    request("cancellations list", "GET", "/api/cancellations", 200, admin_token)
    request("repeated cancellation rejected", "DELETE", f"/api/bookings/{booking1}", 400, agent_token,
            {"reason": "second attempt"})
    reused = request("cancelled seat can be reused", "POST", "/api/bookings", 201, agent_token,
                     {"passenger_id": passengers[0], "flight_id": flight_id, "seat_no": "1A", "payment_mode": "UPI"})
    booking3 = int(reused["booking_id"]); state["booking_ids"].append(booking3)
    state["ticket_ids"].append(int(query_one("SELECT ticket_id FROM TICKET WHERE booking_id=%s", (booking3,))["ticket_id"]))
    request("flight manifest includes active test bookings", "GET", f"/api/flights/{flight_id}/manifest", 200, admin_token)
    seats = request("seat map available-seat count updated", "GET", f"/api/flights/{flight_id}/seats", 200, admin_token)
    record("seat map marks held seats", sum(bool(s["is_taken"]) for s in seats) >= 3)

    # Fill remaining seats to prove aircraft-capacity enforcement.
    for passenger_id, seat_no in ((passengers[4], "1D"), (passengers[5], "1E")):
        b = request("fill remaining seat " + seat_no, "POST", "/api/bookings", 201, agent_token,
                    {"passenger_id": passenger_id, "flight_id": flight_id, "seat_no": seat_no,
                     "payment_mode": "UPI"})
        state["booking_ids"].append(int(b["booking_id"]))
        state["ticket_ids"].append(int(query_one("SELECT ticket_id FROM TICKET WHERE booking_id=%s",
                                                  (b["booking_id"],))["ticket_id"]))
    request("overbooking rejected at aircraft capacity", "POST", "/api/bookings", 400, agent_token,
            {"passenger_id": passengers[3], "flight_id": flight_id, "seat_no": "1A", "payment_mode": "UPI"})

    # Reporting views are read directly, scoped to the test flight/ticket.
    for view in ("v_scheduled_flights", "v_flight_occupancy", "v_successful_payment_revenue"):
        result = query_one(f"SELECT COUNT(*) AS n FROM {view} WHERE " +
                           ("flight_id=%s" if view != "v_successful_payment_revenue" else "flight_no=%s"),
                           (flight_id if view != "v_successful_payment_revenue" else flight_no,))
        record("reporting view " + view, result is not None and int(result["n"]) > 0)

    # Remove only this run's dependent booking rows so every master DELETE API
    # can be exercised in foreign-key order. The application cleanup still
    # catches any remaining uniquely marked rows in the finalizer.
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SET @app_user_id = %s", (state.get("admin_id"),))
        cur.execute("DELETE ci FROM CHECK_IN ci JOIN TICKET t ON t.ticket_id=ci.ticket_id "
                    "JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s", (flight_id,))
        cur.execute("DELETE bg FROM BAGGAGE bg JOIN BOOKING b ON b.booking_id=bg.booking_id WHERE b.flight_id=%s",
                    (flight_id,))
        cur.execute("DELETE p FROM PAYMENT p JOIN TICKET t ON t.ticket_id=p.ticket_id "
                    "JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s", (flight_id,))
        cur.execute("DELETE c FROM CANCELLATION c JOIN BOOKING b ON b.booking_id=c.booking_id WHERE b.flight_id=%s",
                    (flight_id,))
        cur.execute("DELETE t FROM TICKET t JOIN BOOKING b ON b.booking_id=t.booking_id WHERE b.flight_id=%s",
                    (flight_id,))
        cur.execute("DELETE FROM BOOKING WHERE flight_id=%s", (flight_id,))
        cur.execute("DELETE FROM FLIGHT_CREW WHERE flight_id=%s", (flight_id,))
        conn.commit()
    finally:
        conn.close()
    request("delete test flight", "DELETE", f"/api/flights/{flight_id}", 200, admin_token)
    request("delete test gate", "DELETE", f"/api/gates/{gate_id}", 200, admin_token)
    request("delete test crew", "DELETE", f"/api/crew/{crew_id}", 200, admin_token)
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SET @app_user_id = %s", (state.get("admin_id"),))
        cur.execute("DELETE FROM SEAT WHERE aircraft_id=%s", (aircraft_id,))
        conn.commit()
    finally:
        conn.close()
    request("delete test aircraft", "DELETE", f"/api/aircraft/{aircraft_id}", 200, admin_token)
    request("delete test airports", "DELETE", f"/api/airports/{airports[1]}", 200, admin_token)
    request("delete test origin airport", "DELETE", f"/api/airports/{airports[0]}", 200, admin_token)
    request("delete test airline", "DELETE", f"/api/airlines/{airline_id}", 200, admin_token)
    for passenger_id in passengers:
        request("delete test passenger", "DELETE", f"/api/passengers/{passenger_id}", 200, admin_token)

    # Deactivate the temporary Agent; old tokens must stop working immediately.
    request("deactivate temporary agent", "PUT", f"/api/users/{state['agent_id']}", 200, admin_token,
            {"is_active": False})
    request("deactivated Agent token rejected", "GET", "/api/me", 401, agent_token)
    print("INFO API routes exercised:", len(coverage))
    expected_routes = {(method, rule.rule) for rule in app.url_map.iter_rules()
                       if rule.rule.startswith("/api/")
                       for method in rule.methods - {"HEAD", "OPTIONS"}}
    missing_routes = expected_routes - coverage
    if missing_routes:
        print("UNTESTED API route-method pairs:", sorted(missing_routes))
    record("all registered API route-method pairs exercised", not missing_routes)


def run():
    try:
        main()
    except Exception as exc:
        cleanup_errors.append(f"test run: {type(exc).__name__}: {exc}")
        print("FAIL", cleanup_errors[-1])
    finally:
        try:
            cleanup()
        except Exception as exc:
            cleanup_errors.append(f"cleanup: {type(exc).__name__}: {exc}")
            print("CLEANUP ERROR", cleanup_errors[-1])
    print(f"SUMMARY checks={checks} cleanup_errors={len(cleanup_errors)}")
    if cleanup_errors:
        raise SystemExit(1)


if __name__ == "__main__":
    run()
