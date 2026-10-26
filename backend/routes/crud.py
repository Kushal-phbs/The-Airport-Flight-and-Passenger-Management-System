"""Generic CRUD for the simple master-data tables + reusable row helpers.

Columns are taken from a fixed whitelist, so user input is never placed in
the SQL text -- only passed as %s parameters.
"""
from flask import Blueprint, jsonify, request

from auth import auth_required
from db import execute, query_all, query_one
from utils import ApiError, json_body, require

bp = Blueprint("crud", __name__)


def _clean(v):
    return None if isinstance(v, str) and v.strip() == "" else v


def insert_row(table, columns, data):
    cols = [c for c in columns if c in data]
    if not cols:
        raise ApiError("No valid fields supplied")
    names = ", ".join(f"`{c}`" for c in cols)
    marks = ", ".join(["%s"] * len(cols))
    new_id, _ = execute(f"INSERT INTO {table} ({names}) VALUES ({marks})",
                        [_clean(data[c]) for c in cols])
    return new_id


def update_row(table, pk, columns, item_id, data):
    cols = [c for c in columns if c in data]
    if not cols:
        raise ApiError("No valid fields to update")
    if not query_one(f"SELECT 1 AS x FROM {table} WHERE {pk} = %s", (item_id,)):
        raise ApiError("Record not found", 404)
    sets = ", ".join(f"`{c}` = %s" for c in cols)
    execute(f"UPDATE {table} SET {sets} WHERE {pk} = %s",
            [_clean(data[c]) for c in cols] + [item_id])


def delete_row(table, pk, item_id):
    if not query_one(f"SELECT 1 AS x FROM {table} WHERE {pk} = %s", (item_id,)):
        raise ApiError("Record not found", 404)
    execute(f"DELETE FROM {table} WHERE {pk} = %s", (item_id,))


def register_crud(path, table, pk, columns, required=(), filters=(), search=(),
                  base_sql=None, write_roles=("Admin", "Staff"), delete_roles=("Admin",)):
    base = base_sql or f"SELECT t.* FROM {table} t"

    def list_items():
        where, params = [], []
        for f in filters:
            v = request.args.get(f)
            if v not in (None, ""):
                where.append(f"t.{f} = %s")
                params.append(v)
        q = request.args.get("q")
        if q and search:
            where.append("(" + " OR ".join(f"t.{c} LIKE %s" for c in search) + ")")
            params += [f"%{q}%"] * len(search)
        sql = base + (" WHERE " + " AND ".join(where) if where else "") \
            + f" ORDER BY t.{pk} LIMIT 500"
        return jsonify(query_all(sql, params))

    def get_item(item_id):
        row = query_one(base + f" WHERE t.{pk} = %s", (item_id,))
        if not row:
            raise ApiError("Record not found", 404)
        return jsonify(row)

    def create_item():
        data = json_body()
        require(data, required)
        return jsonify({pk: insert_row(table, columns, data), "message": "Created"}), 201

    def update_item(item_id):
        update_row(table, pk, columns, item_id, json_body())
        return jsonify(message="Updated")

    def delete_item(item_id):
        delete_row(table, pk, item_id)
        return jsonify(message="Deleted")

    rule = lambda suffix: f"/{path}{suffix}"
    bp.add_url_rule(rule(""), f"{path}_list", auth_required()(list_items), methods=["GET"])
    bp.add_url_rule(rule("/<int:item_id>"), f"{path}_get", auth_required()(get_item), methods=["GET"])
    bp.add_url_rule(rule(""), f"{path}_create", auth_required(*write_roles)(create_item), methods=["POST"])
    bp.add_url_rule(rule("/<int:item_id>"), f"{path}_update", auth_required(*write_roles)(update_item), methods=["PUT"])
    bp.add_url_rule(rule("/<int:item_id>"), f"{path}_delete", auth_required(*delete_roles)(delete_item), methods=["DELETE"])


register_crud(
    "airlines", "AIRLINE", "airline_id",
    ["airline_name", "airline_code", "country", "contact_no", "email", "is_active"],
    required=["airline_name", "airline_code"], filters=["country", "is_active"],
    search=["airline_name", "airline_code"], write_roles=("Admin",))

register_crud(
    "airports", "AIRPORT", "airport_id",
    ["airport_name", "city", "country", "airport_code", "timezone"],
    required=["airport_name", "airport_code"], filters=["city", "country"],
    search=["airport_name", "airport_code", "city"], write_roles=("Admin",))

register_crud(
    "aircraft", "AIRCRAFT", "aircraft_id",
    ["aircraft_code", "model", "manufacturer", "year_of_manufacture", "capacity", "status", "airline_id"],
    required=["aircraft_code", "capacity", "airline_id"], filters=["airline_id", "status"],
    search=["aircraft_code", "model"],
    base_sql="SELECT t.*, al.airline_name FROM AIRCRAFT t JOIN AIRLINE al ON al.airline_id = t.airline_id")

register_crud(
    "gates", "GATE", "gate_id",
    ["gate_no", "terminal", "status", "airport_id"],
    required=["gate_no", "airport_id"], filters=["airport_id", "status"],
    search=["gate_no", "terminal"],
    base_sql="SELECT t.*, a.airport_code, a.city FROM GATE t JOIN AIRPORT a ON a.airport_id = t.airport_id")

register_crud(
    "crew", "CREW", "crew_id",
    ["first_name", "last_name", "role", "license_no", "phone_no", "airline_id"],
    required=["first_name", "role", "airline_id"], filters=["airline_id", "role"],
    search=["first_name", "last_name", "license_no"],
    base_sql="SELECT t.*, al.airline_name FROM CREW t JOIN AIRLINE al ON al.airline_id = t.airline_id")

register_crud(
    "passengers", "PASSENGER", "passenger_id",
    ["first_name", "last_name", "dob", "gender", "nationality", "passport_no",
     "passport_expiry", "phone_no", "email", "address"],
    required=["first_name", "passport_no"], filters=["nationality", "gender"],
    search=["first_name", "last_name", "passport_no", "email", "phone_no"],
    write_roles=("Admin", "Staff", "Agent"))
