"""End-to-end API tests against your REAL database.

Usage (from the backend folder, venv active, MySQL running):
    python tests/test_api.py

IMPORTANT: this test creates/cancels bookings and flights. Re-run the four SQL
files (schema, seed_data, triggers, procedures) before running it again.
"""
import os, sys, threading
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.dont_write_bytecode = True
from app import app

c = app.test_client()
passed = failed = 0
def check(name, cond, info=None):
    global passed, failed
    if cond: passed += 1; print("PASS", name)
    else:    failed += 1; print("FAIL", name, "->", info)

def call(method, url, token=None, **kw):
    h = {"Authorization": "Bearer " + token} if token else {}
    r = getattr(c, method)(url, headers=h, **kw)
    return r.status_code, (r.get_json(silent=True) if r.is_json else r.data[:200])

def login(u, p):
    s, d = call("post", "/api/login", json={"username": u, "password": p})
    return s, d

s, d = call("get", "/api/health"); check("health db connected", s == 200 and d["database"] is True, d)
s, d = login("admin", "admin123"); check("login admin", s == 200 and d.get("token"), d); A = d["token"]
s, d = login("staff1", "staff123"); check("login staff", s == 200, d); S = d["token"]
s, d = login("agent1", "agent123"); check("login agent", s == 200, d); G = d["token"]
s, d = login("admin", "wrong"); check("wrong password 401", s == 401, (s, d))
s, d = call("get", "/api/me", A); check("me", s == 200 and d["role"] == "Admin", d)
s, d = call("get", "/api/dashboard/stats", A); check("dashboard stats", s == 200 and d["total_flights"] == 20, d); print("   ", d)

# ---------- flights ----------
s, d = call("get", "/api/flights", A); check("flights all = 20", s == 200 and len(d) == 20, (s, len(d) if isinstance(d, list) else d))
s, d = call("get", "/api/flights?from=MAA&to=DEL&date=2026-10-10", A); check("search MAA->DEL", s == 200 and len(d) == 1 and d[0]["flight_no"] == "AI101", d)
if isinstance(d, list) and d: print("   ", {k: d[0][k] for k in ("flight_no","departure_time","economy_fare","business_fare","economy_seats")})
s, d = call("get", "/api/flights/1", A); check("flight detail", s == 200 and len(d["fares"]) == 2 and len(d["crew"]) >= 3, d if s != 200 else len(d["crew"]))
s, d = call("get", "/api/flights/999", A); check("flight 404", s == 404, (s, d))
s, d = call("get", "/api/flights/1/seats", A); check("seat map 120", s == 200 and len(d) == 120 and sum(x["is_taken"] for x in d) == 3, (s, len(d), sum(x["is_taken"] for x in d) if isinstance(d, list) else d))
s, d = call("get", "/api/flights/1/manifest", A); check("manifest", s == 200 and len(d["passengers"]) == 3, d if s != 200 else len(d["passengers"]))

# ---------- passengers ----------
s, d = call("get", "/api/passengers?q=Arjun", G); check("passenger search", s == 200 and len(d) == 1, d)
s, d = call("post", "/api/passengers", G, json={"first_name": "Test", "last_name": "User", "passport_no": "T9999999", "passport_expiry": "2035-01-01", "gender": "Male"})
check("create passenger (agent)", s == 201, d); pid = d.get("passenger_id")
s, d = call("post", "/api/passengers", G, json={"first_name": "Dup", "passport_no": "T9999999"}); check("duplicate passport 409", s == 409, (s, d))
s, d = call("post", "/api/passengers", G, json={"first_name": "NoPass"}); check("missing field 400", s == 400, (s, d))
s, d = call("put", f"/api/passengers/{pid}", G, json={"phone_no": "+919999999999"}); check("update passenger", s == 200, d)
s, d = call("delete", f"/api/passengers/{pid}", G); check("agent cannot delete passenger 403", s == 403, (s, d))
s, d = call("delete", "/api/passengers/1", A); check("delete passenger with bookings 409", s == 409, (s, d))

# ---------- bookings ----------
s, d = call("post", "/api/bookings", G, json={"passenger_id": 28, "flight_id": 1, "seat_no": "3A", "payment_mode": "UPI"})
check("book ticket", s == 201 and d.get("pnr", "").startswith("PNR") and d.get("ticket_no", "").startswith("TKT") and d.get("booking_id"), (s, d)); print("   ", d)
bid, tkt = d.get("booking_id"), d.get("ticket_no")
s, d2 = call("post", "/api/bookings", G, json={"passenger_id": 29, "flight_id": 1, "seat_no": "3A", "payment_mode": "Card"})
check("double-book seat blocked", s == 400 and "already booked" in d2["error"], (s, d2))
s, d2 = call("post", "/api/bookings", G, json={"passenger_id": 29, "flight_id": 1, "seat_no": "99Z", "payment_mode": "Card"}); check("invalid seat", s == 400, (s, d2))
s, d2 = call("post", "/api/bookings", G, json={"passenger_id": 28, "flight_id": 1, "seat_no": "4A", "payment_mode": "Card"}); check("same passenger twice blocked", s == 400 and "already has" in d2["error"], (s, d2))
s, d2 = call("post", "/api/bookings", G, json={"passenger_id": 29, "flight_id": 20, "seat_no": "4A", "payment_mode": "Card"}); check("booking on cancelled flight blocked", s == 400 and "closed" in d2["error"], (s, d2))
s, d2 = call("post", "/api/bookings", G, json={"passenger_id": 29, "flight_id": 1, "seat_no": "4A", "payment_mode": "Bitcoin"}); check("bad payment mode 400", s == 400, (s, d2))
s, d = call("get", f"/api/bookings/{bid}", A); check("booking detail", s == 200 and d["booking_status"] == "Confirmed" and len(d["payments"]) == 1 and d["payments"][0]["status"] == "Success", d)
fare = d.get("total_amount"); print("    fare:", fare)
s, d = call("get", f"/api/tickets/{tkt}", A); check("ticket detail", s == 200 and d["seat_no"] == "3A" and d["source"] == "MAA", d)
s, d = call("get", "/api/bookings?q=Arjun", A); check("booking search", s == 200 and len(d) >= 1, (s, d))
s, d = call("get", "/api/flights/1/seats", A); check("seat 3A now taken", sum(x["is_taken"] for x in d) == 4, sum(x["is_taken"] for x in d))
s, d = call("get", "/api/flights/1", A); biz = [f for f in d["fares"] if f["class"] == "Business"][0]; check("business seats_available decreased", biz["seats_available"] == 18 - 2, biz)

# ---------- baggage / payments / check-in ----------
s, d = call("post", "/api/baggage", G, json={"booking_id": bid, "weight": 20}); check("baggage fee 500", s == 201 and float(d["fee"]) == 500.0, (s, d))
s, d2 = call("post", "/api/baggage", G, json={"booking_id": bid, "weight": 40}); check("overweight blocked", s == 400, (s, d2))
s, d2 = call("post", "/api/baggage", G, json={"booking_id": bid, "weight": 8, "baggage_type": "Cabin"}); check("cabin >7kg blocked", s == 400, (s, d2))
s, d2 = call("put", f"/api/baggage/{d['baggage_id']}", G, json={"status": "Loaded"}); check("baggage status update", s == 200, (s, d2))
s, d = call("post", "/api/payments", G, json={"ticket_id": 1, "amount": 100, "payment_mode": "Cash"}); check("overpayment blocked", s == 400, (s, d))
s, d = call("get", "/api/payments?status=Success", A); check("payments list", s == 200 and len(d) > 0, (s, d))
s, d = call("get", "/api/tickets?booking_id=%d" % bid, A); check("tickets list", s == 200 and len(d) == 1, (s, d))
s, d = call("post", "/api/checkin", G, json={"ticket_no": tkt}); check("check-in", s == 201, (s, d))
s, d = call("post", "/api/checkin", G, json={"ticket_no": tkt}); check("double check-in blocked", s in (400, 409), (s, d))
s, d = call("post", "/api/checkin/board", G, json={"ticket_no": tkt}); check("board", s == 200, (s, d))
s, d = call("get", "/api/flights/1/manifest", A); row = [p for p in d["passengers"] if p["ticket_no"] == tkt][0]
check("manifest shows boarded + bags", row["check_in_status"] == "Boarded" and row["bags"] == 1, row)

# ---------- cancel ----------
s, d = call("delete", f"/api/bookings/{bid}", G, json={"reason": "Change of plans"}); check("cancel booking 80% refund", s == 200 and abs(d["refund_amount"] - round(fare * 0.8, 2)) < 0.01, (s, d, fare))
s, d = call("delete", f"/api/bookings/{bid}", G); check("cancel twice blocked", s == 400, (s, d))
s, d = call("get", f"/api/bookings/{bid}", A); check("cancelled booking state", d["booking_status"] == "Cancelled" and d["seat_id"] is None and d["cancellation"]["reason"] == "Change of plans" and d["ticket_status"] == "Cancelled" and d["payments"][0]["status"] == "Refunded", d)
s, d = call("get", "/api/flights/1", A); biz = [f for f in d["fares"] if f["class"] == "Business"][0]; check("seat count restored", biz["seats_available"] == 17 and True, biz)
s, d = call("get", "/api/cancellations", A); check("cancellations list", s == 200 and len(d) >= 3, (s, len(d)))
s, d = call("post", "/api/bookings", S, json={"passenger_id": 29, "flight_id": 1, "seat_no": "3A", "payment_mode": "Card"}); check("freed seat can be rebooked", s == 201, (s, d))

# ---------- flights admin ----------
base = {"flight_no": "XX100", "departure_date": "2026-11-05", "departure_time": "10:00:00", "arrival_date": "2026-11-05", "arrival_time": "12:00:00",
        "airline_id": 1, "aircraft_id": 8, "source_airport_id": 1, "destination_airport_id": 3, "gate_id": 2, "fares": {"Economy": 4000, "Business": 11000}}
s, d = call("post", "/api/flights", A, json=base); check("create flight + fares", s == 201, (s, d)); fid = d.get("flight_id")
s, d = call("get", f"/api/flights/{fid}", A); check("new flight fares", len(d["fares"]) == 2 and d["fares"][0]["seats_available"] in (18, 102), d["fares"])
s, d = call("post", "/api/flights", A, json={**base, "flight_no": "XX101", "destination_airport_id": 1}); check("same source/dest blocked", s == 400 and "different" in d["error"], (s, d))
s, d = call("post", "/api/flights", A, json={**base, "flight_no": "XX102", "departure_time": "10:30:00", "arrival_time": "12:30:00", "aircraft_id": 1, "airline_id": 1}); check("gate conflict blocked", s == 400 and "Gate" in d["error"], (s, d))
s, d = call("post", "/api/flights", A, json={**base, "flight_no": "XX103", "aircraft_id": 3}); check("aircraft/airline mismatch blocked", s == 400 and "airline" in d["error"], (s, d))
s, d = call("post", "/api/flights", S, json={**base, "flight_no": "XX104", "gate_id": 3, "aircraft_id": 1, "departure_time": "13:00:00", "arrival_time": "15:00:00"}); check("staff can create flight", s == 201, (s, d))
s, d = call("post", "/api/flights", G, json=base); check("agent cannot create flight 403", s == 403, (s, d))
s, d = call("put", f"/api/flights/{fid}/fares", A, json={"Economy": 4200}); check("update fare", s == 200, (s, d))
s, d = call("put", f"/api/flights/{fid}/crew", A, json={"crew_ids": [1, 2, 3]}); check("assign crew", s == 200, (s, d))
s, d = call("put", f"/api/flights/{fid}", A, json={"actual_departure": "2026-11-05 10:25:00"}); check("actual departure", s == 200, (s, d))
s, d = call("get", f"/api/flights/{fid}", A); check("trigger set Departed + 25 min delay", d["status"] == "Departed" and d["delay_minutes"] == 25, (d["status"], d["delay_minutes"]))
# cancel whole flight with bookings (flight 11: AI111, bookings 15,16)
s, d = call("put", "/api/flights/11", A, json={"status": "Cancelled"}); check("cancel flight", s == 200, (s, d))
s, d = call("get", "/api/bookings?flight_id=11", A); check("flight cancel cascades to bookings", all(b["booking_status"] == "Cancelled" for b in d) and len(d) == 2, [b["booking_status"] for b in d])
s, d = call("get", "/api/cancellations", A); full = [x for x in d if x["reason"] == "Flight cancelled by airline" and x["booking_id"] in [b["booking_id"] for b in call("get", "/api/bookings?flight_id=11", A)[1]]]
check("full refunds for airline cancellation", len(full) == 2 and all(x["refund_amount"] > 0 for x in full), full)
s, d = call("put", "/api/flights/11", A, json={"status": "Scheduled"}); check("cannot reactivate cancelled flight", s == 400, (s, d))
s, d = call("delete", "/api/flights/1", A); check("delete flight with bookings 409", s == 409, (s, d))
s, d = call("delete", f"/api/flights/{fid}", S); check("staff cannot delete 403", s == 403, (s, d))

# ---------- master data & admin ----------
s, d = call("get", "/api/airlines", G); check("airlines list (agent)", s == 200 and len(d) == 5, (s, d))
s, d = call("post", "/api/airlines", S, json={"airline_name": "X", "airline_code": "XX"}); check("staff cannot add airline 403", s == 403, (s, d))
s, d = call("post", "/api/airlines", A, json={"airline_name": "Test Air", "airline_code": "TA"}); check("admin adds airline", s == 201, (s, d)); aid = d.get("airline_id")
s, d = call("delete", f"/api/airlines/{aid}", A); check("admin deletes airline", s == 200, (s, d))
s, d = call("get", "/api/aircraft?airline_id=1", A); check("aircraft filter + airline_name", s == 200 and len(d) == 3 and "airline_name" in d[0], d)
s, d = call("get", "/api/gates?airport_id=1", A); check("gates filter", s == 200 and len(d) == 3 and "airport_code" in d[0], d)
s, d = call("get", "/api/crew?airline_id=1", A); check("crew list", s == 200 and len(d) == 4, (s, d))
s, d = call("get", "/api/airports?q=chennai", A); check("airport search", s == 200 and len(d) == 1, (s, d))
s, d = call("get", "/api/users", A); check("users list", s == 200 and len(d) == 3 and "password_hash" not in d[0], d)
s, d = call("get", "/api/users", S); check("staff cannot list users 403", s == 403, s)
s, d = call("post", "/api/users", A, json={"username": "newagent", "password": "pass1234", "role": "Agent"}); check("create user", s == 201, (s, d)); uid = d.get("user_id")
s, d = login("newagent", "pass1234"); check("new user can log in", s == 200, (s, d)); NT = d.get("token")
s, d = call("get", "/api/me", NT); check("new user token works", s == 200, (s, d))
s, d = call("put", f"/api/users/{uid}", A, json={"is_active": 0}); check("deactivate user", s == 200, (s, d))
s, d = call("get", "/api/me", NT); check("deactivated user's OLD token rejected", s == 401, (s, d))
s, d = login("newagent", "pass1234"); check("deactivated user blocked", s == 401, (s, d))
s, d = call("get", "/api/audit?limit=500", A); check("audit log has rows with usernames", s == 200 and len(d) > 10 and any(r["username"] for r in d), (s, len(d) if isinstance(d, list) else d))
users = {r["username"] for r in d if isinstance(d, list)}; print("    audit users:", users)
s, d = call("get", "/api/audit?table_name=BOOKING", A); check("audit filter", all(r["table_name"] == "BOOKING" for r in d), d[:1])
s, d = call("get", "/api/audit", G); check("agent cannot read audit 403", s == 403, s)
s, d = call("get", "/", None); check("root serves frontend", s == 200, s)

# ---------- concurrency ----------
results = []
def race(pid):
    cl = app.test_client()
    r = cl.post("/api/bookings", headers={"Authorization": "Bearer " + G},
                json={"passenger_id": pid, "flight_id": 3, "seat_no": "10C", "payment_mode": "Card"})
    results.append(r.status_code)
threads = [threading.Thread(target=race, args=(p,)) for p in (11, 12, 13, 14, 15)]
[t.start() for t in threads]; [t.join() for t in threads]
check("5 simultaneous bookings of one seat -> exactly 1 succeeds", results.count(201) == 1 and results.count(400) == 4, results)

print(f"\n{passed} passed, {failed} failed")
