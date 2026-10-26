import uuid

from flask import Blueprint, g, jsonify, request

from auth import auth_required
from routes.crud import delete_row, insert_row, update_row
from db import call_proc, execute, query_all, query_one
from utils import ApiError, json_body, require

bp = Blueprint("bookings", __name__)
ALL_ROLES = ("Admin", "Staff", "Agent")

BOOKING_SELECT = """
SELECT b.booking_id, b.booking_reference, b.booking_date, b.booking_status, b.total_amount,
       b.passenger_id, CONCAT(p.first_name, ' ', IFNULL(p.last_name, '')) AS passenger_name,
       b.flight_id, f.flight_no, f.departure_date, f.departure_time,
       b.seat_id, s.seat_no, s.`class` AS seat_class,
       t.ticket_id, t.ticket_no, t.status AS ticket_status
FROM BOOKING b
JOIN PASSENGER p ON p.passenger_id = b.passenger_id
JOIN FLIGHT f ON f.flight_id = b.flight_id
LEFT JOIN SEAT s ON s.seat_id = b.seat_id
LEFT JOIN TICKET t ON t.booking_id = b.booking_id
"""


# ====================== BOOKINGS ======================
@bp.get("/bookings")
@auth_required()
def list_bookings():
    where, params = [], []
    for arg, col in (("flight_id", "b.flight_id"), ("passenger_id", "b.passenger_id"),
                     ("status", "b.booking_status")):
        v = request.args.get(arg)
        if v:
            where.append(f"{col} = %s")
            params.append(v)
    q = request.args.get("q")
    if q:
        where.append("(b.booking_reference LIKE %s OR p.first_name LIKE %s OR p.last_name LIKE %s "
                     "OR p.passport_no LIKE %s)")
        params += [f"%{q}%"] * 4
    sql = BOOKING_SELECT + (" WHERE " + " AND ".join(where) if where else "") \
        + " ORDER BY b.booking_id DESC LIMIT 500"
    return jsonify(query_all(sql, params))


@bp.get("/bookings/<int:booking_id>")
@auth_required()
def get_booking(booking_id):
    booking = query_one(BOOKING_SELECT + " WHERE b.booking_id = %s", (booking_id,))
    if not booking:
        raise ApiError("Booking not found", 404)
    booking["payments"] = query_all(
        "SELECT p.* FROM PAYMENT p JOIN TICKET t ON t.ticket_id = p.ticket_id "
        "WHERE t.booking_id = %s ORDER BY p.payment_id", (booking_id,))
    booking["baggage"] = query_all("SELECT * FROM BAGGAGE WHERE booking_id = %s", (booking_id,))
    booking["cancellation"] = query_one("SELECT * FROM CANCELLATION WHERE booking_id = %s", (booking_id,))
    return jsonify(booking)


@bp.post("/bookings")
@auth_required(*ALL_ROLES)
def create_booking():
    """Books seat + issues ticket + records payment in one transaction."""
    data = json_body()
    require(data, ["passenger_id", "flight_id", "seat_no", "payment_mode"])
    _, out = call_proc("sp_book_ticket", [
        data["passenger_id"], data["flight_id"], data["seat_no"], data["payment_mode"],
        g.user_id, 0, "", ""])
    return jsonify(booking_id=out[5], ticket_no=out[6], pnr=out[7],
                   message="Booking confirmed"), 201


@bp.delete("/bookings/<int:booking_id>")
@auth_required(*ALL_ROLES)
def cancel_booking(booking_id):
    """Optional JSON body: {"reason": "..."}"""
    reason = json_body().get("reason")
    _, out = call_proc("sp_cancel_booking", [booking_id, reason, g.user_id, 0])
    return jsonify(refund_amount=out[3], message="Booking cancelled")


# ====================== TICKETS ======================
@bp.get("/tickets")
@auth_required()
def list_tickets():
    where, params = [], []
    for arg, col in (("booking_id", "t.booking_id"), ("status", "t.status")):
        v = request.args.get(arg)
        if v:
            where.append(f"{col} = %s")
            params.append(v)
    sql = ("SELECT t.*, b.booking_reference FROM TICKET t "
           "JOIN BOOKING b ON b.booking_id = t.booking_id"
           + (" WHERE " + " AND ".join(where) if where else "")
           + " ORDER BY t.ticket_id DESC LIMIT 500")
    return jsonify(query_all(sql, params))


@bp.get("/tickets/<ticket_no>")
@auth_required()
def get_ticket(ticket_no):
    row = query_one("""
        SELECT t.*, b.booking_reference, b.booking_status,
               CONCAT(p.first_name, ' ', IFNULL(p.last_name, '')) AS passenger_name, p.passport_no,
               f.flight_no, f.departure_date, f.departure_time, f.arrival_date, f.arrival_time,
               sa.airport_code AS source, da.airport_code AS destination,
               g.terminal, g.gate_no, s.seat_no, s.`class` AS seat_class,
               ci.boarding_status AS check_in_status
        FROM TICKET t
        JOIN BOOKING b ON b.booking_id = t.booking_id
        JOIN PASSENGER p ON p.passenger_id = b.passenger_id
        JOIN FLIGHT f ON f.flight_id = b.flight_id
        JOIN AIRPORT sa ON sa.airport_id = f.source_airport_id
        JOIN AIRPORT da ON da.airport_id = f.destination_airport_id
        LEFT JOIN GATE g ON g.gate_id = f.gate_id
        LEFT JOIN SEAT s ON s.seat_id = b.seat_id
        LEFT JOIN CHECK_IN ci ON ci.ticket_id = t.ticket_id
        WHERE t.ticket_no = %s""", (ticket_no,))
    if not row:
        raise ApiError("Ticket not found", 404)
    return jsonify(row)


# ====================== PAYMENTS ======================
@bp.get("/payments")
@auth_required()
def list_payments():
    where, params = [], []
    for arg, col in (("ticket_id", "p.ticket_id"), ("status", "p.status"),
                     ("payment_mode", "p.payment_mode")):
        v = request.args.get(arg)
        if v:
            where.append(f"{col} = %s")
            params.append(v)
    sql = ("SELECT p.*, t.ticket_no, b.booking_reference FROM PAYMENT p "
           "JOIN TICKET t ON t.ticket_id = p.ticket_id "
           "JOIN BOOKING b ON b.booking_id = t.booking_id"
           + (" WHERE " + " AND ".join(where) if where else "")
           + " ORDER BY p.payment_id DESC LIMIT 500")
    return jsonify(query_all(sql, params))


@bp.post("/payments")
@auth_required(*ALL_ROLES)
def add_payment():
    """Extra / retry payment for an existing ticket."""
    data = json_body()
    require(data, ["ticket_id", "amount", "payment_mode"])
    data["transaction_id"] = "TXN" + uuid.uuid4().hex[:12].upper()
    data.setdefault("status", "Success")
    new_id = insert_row("PAYMENT", ["ticket_id", "amount", "payment_mode",
                                    "transaction_id", "status", "currency"], data)
    return jsonify(payment_id=new_id, transaction_id=data["transaction_id"],
                   message="Payment recorded"), 201


# ====================== BAGGAGE ======================
@bp.get("/baggage")
@auth_required()
def list_baggage():
    where, params = [], []
    for arg, col in (("booking_id", "bg.booking_id"), ("status", "bg.status")):
        v = request.args.get(arg)
        if v:
            where.append(f"{col} = %s")
            params.append(v)
    sql = ("SELECT bg.*, b.booking_reference FROM BAGGAGE bg "
           "JOIN BOOKING b ON b.booking_id = bg.booking_id"
           + (" WHERE " + " AND ".join(where) if where else "")
           + " ORDER BY bg.baggage_id DESC LIMIT 500")
    return jsonify(query_all(sql, params))


@bp.post("/baggage")
@auth_required(*ALL_ROLES)
def add_baggage():
    """The fee is calculated by a trigger (15 kg free, Rs.100 per extra kg)."""
    data = json_body()
    require(data, ["booking_id", "weight"])
    data["baggage_tag"] = "BG" + uuid.uuid4().hex[:8].upper()
    data.setdefault("baggage_type", "Checked")
    new_id = insert_row("BAGGAGE", ["baggage_tag", "baggage_type", "weight", "dimensions", "booking_id"], data)
    row = query_one("SELECT baggage_id, baggage_tag, fee FROM BAGGAGE WHERE baggage_id = %s", (new_id,))
    return jsonify(row), 201


@bp.put("/baggage/<int:baggage_id>")
@auth_required(*ALL_ROLES)
def update_baggage(baggage_id):
    update_row("BAGGAGE", "baggage_id", ["status"], baggage_id, json_body())
    return jsonify(message="Baggage updated")


@bp.delete("/baggage/<int:baggage_id>")
@auth_required("Admin")
def delete_baggage(baggage_id):
    delete_row("BAGGAGE", "baggage_id", baggage_id)
    return jsonify(message="Baggage deleted")


# ====================== CHECK-IN / BOARDING ======================
@bp.post("/checkin")
@auth_required(*ALL_ROLES)
def check_in():
    data = json_body()
    require(data, ["ticket_no"])
    _, out = call_proc("sp_check_in", [data["ticket_no"], g.user_id, 0])
    return jsonify(checkin_id=out[2], message="Checked in"), 201


@bp.post("/checkin/board")
@auth_required(*ALL_ROLES)
def board():
    data = json_body()
    require(data, ["ticket_no"])
    call_proc("sp_board_passenger", [data["ticket_no"], g.user_id])
    return jsonify(message="Passenger boarded")


# ====================== CANCELLATIONS ======================
@bp.get("/cancellations")
@auth_required()
def list_cancellations():
    return jsonify(query_all(
        "SELECT c.*, b.booking_reference, b.flight_id, u.username AS processed_by_name "
        "FROM CANCELLATION c JOIN BOOKING b ON b.booking_id = c.booking_id "
        "LEFT JOIN USER_ACCOUNT u ON u.user_id = c.processed_by "
        "ORDER BY c.cancel_id DESC LIMIT 500"))
