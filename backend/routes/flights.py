from flask import Blueprint, jsonify, request

from auth import auth_required
from routes.crud import delete_row, insert_row, update_row
from db import call_proc, execute, query_all, query_one
from utils import ApiError, json_body, require

bp = Blueprint("flights", __name__)

FLIGHT_COLS = ["flight_no", "departure_date", "departure_time", "arrival_date", "arrival_time",
               "status", "airline_id", "aircraft_id", "source_airport_id",
               "destination_airport_id", "gate_id"]
FLIGHT_REQUIRED = ["flight_no", "departure_date", "departure_time", "arrival_date", "arrival_time",
                   "airline_id", "aircraft_id", "source_airport_id", "destination_airport_id"]
FLIGHT_UPDATE_COLS = FLIGHT_COLS + ["actual_departure", "actual_arrival"]

FLIGHT_DETAIL_SQL = """
SELECT f.*, al.airline_name, al.airline_code, ac.aircraft_code, ac.model, ac.capacity,
       sa.airport_code AS source_code, sa.city AS source_city,
       da.airport_code AS destination_code, da.city AS destination_city,
       g.gate_no, g.terminal
FROM FLIGHT f
JOIN AIRLINE al ON al.airline_id = f.airline_id
JOIN AIRCRAFT ac ON ac.aircraft_id = f.aircraft_id
JOIN AIRPORT sa ON sa.airport_id = f.source_airport_id
JOIN AIRPORT da ON da.airport_id = f.destination_airport_id
LEFT JOIN GATE g ON g.gate_id = f.gate_id
"""


def _set_fares(flight_id, aircraft_id, fares):
    """fares = {"Economy": 5000, "Business": 14000}"""
    counts = {r["cls"]: r["n"] for r in query_all(
        "SELECT `class` AS cls, COUNT(*) AS n FROM SEAT "
        "WHERE aircraft_id = %s AND is_active = 1 GROUP BY `class`", (aircraft_id,))}
    for cls, price in fares.items():
        if cls not in counts:
            raise ApiError(f"This aircraft has no {cls} seats")
        execute(
            "INSERT INTO FLIGHT_FARE (flight_id, `class`, base_price, seats_available) "
            "VALUES (%s, %s, %s, %s) ON DUPLICATE KEY UPDATE base_price = %s",
            (flight_id, cls, price, counts[cls], price))


@bp.get("/flights")
@auth_required()
def search_flights():
    sets, _ = call_proc("sp_search_flights", [
        request.args.get("from") or None,
        request.args.get("to") or None,
        request.args.get("date") or None])
    return jsonify(sets[0] if sets else [])


@bp.get("/flights/<int:flight_id>")
@auth_required()
def get_flight(flight_id):
    flight = query_one(FLIGHT_DETAIL_SQL + " WHERE f.flight_id = %s", (flight_id,))
    if not flight:
        raise ApiError("Flight not found", 404)
    flight["fares"] = query_all(
        "SELECT fare_id, `class`, base_price, seats_available FROM FLIGHT_FARE WHERE flight_id = %s",
        (flight_id,))
    flight["crew"] = query_all(
        "SELECT c.crew_id, c.first_name, c.last_name, c.role FROM FLIGHT_CREW fc "
        "JOIN CREW c ON c.crew_id = fc.crew_id WHERE fc.flight_id = %s", (flight_id,))
    return jsonify(flight)


@bp.post("/flights")
@auth_required("Admin", "Staff")
def create_flight():
    data = json_body()
    require(data, FLIGHT_REQUIRED)
    new_id = insert_row("FLIGHT", FLIGHT_COLS, data)
    if isinstance(data.get("fares"), dict):
        _set_fares(new_id, data["aircraft_id"], data["fares"])
    return jsonify(flight_id=new_id, message="Flight created"), 201


@bp.put("/flights/<int:flight_id>")
@auth_required("Admin", "Staff")
def update_flight(flight_id):
    update_row("FLIGHT", "flight_id", FLIGHT_UPDATE_COLS, flight_id, json_body())
    return jsonify(message="Flight updated")


@bp.delete("/flights/<int:flight_id>")
@auth_required("Admin")
def delete_flight(flight_id):
    delete_row("FLIGHT", "flight_id", flight_id)
    return jsonify(message="Flight deleted")


@bp.put("/flights/<int:flight_id>/fares")
@auth_required("Admin", "Staff")
def update_fares(flight_id):
    flight = query_one("SELECT aircraft_id FROM FLIGHT WHERE flight_id = %s", (flight_id,))
    if not flight:
        raise ApiError("Flight not found", 404)
    data = json_body()
    if not data:
        raise ApiError('Send fares like {"Economy": 5000, "Business": 14000}')
    _set_fares(flight_id, flight["aircraft_id"], data)
    return jsonify(message="Fares updated")


@bp.get("/flights/<int:flight_id>/manifest")
@auth_required()
def flight_manifest(flight_id):
    flight = query_one(FLIGHT_DETAIL_SQL + " WHERE f.flight_id = %s", (flight_id,))
    if not flight:
        raise ApiError("Flight not found", 404)
    sets, _ = call_proc("sp_get_flight_manifest", [flight_id])
    return jsonify(flight=flight, passengers=sets[0] if sets else [])


@bp.get("/flights/<int:flight_id>/seats")
@auth_required()
def flight_seats(flight_id):
    sets, _ = call_proc("sp_seat_map", [flight_id])
    return jsonify(sets[0] if sets else [])


@bp.put("/flights/<int:flight_id>/crew")
@auth_required("Admin", "Staff")
def assign_crew(flight_id):
    """Body: {"crew_ids": [1,2,3]}  -- replaces the crew of the flight."""
    data = json_body()
    ids = data.get("crew_ids")
    if not isinstance(ids, list):
        raise ApiError('Send {"crew_ids": [1, 2, 3]}')
    if not query_one("SELECT 1 AS x FROM FLIGHT WHERE flight_id = %s", (flight_id,)):
        raise ApiError("Flight not found", 404)
    execute("DELETE FROM FLIGHT_CREW WHERE flight_id = %s", (flight_id,))
    for cid in ids:
        execute("INSERT INTO FLIGHT_CREW (flight_id, crew_id) VALUES (%s, %s)", (flight_id, cid))
    return jsonify(message="Crew assigned")
