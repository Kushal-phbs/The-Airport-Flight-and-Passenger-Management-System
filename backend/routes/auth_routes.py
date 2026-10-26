from flask import Blueprint, current_app, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from auth import auth_required, create_token
from db import call_proc, execute, query_all, query_one
from utils import ApiError, json_body, require

bp = Blueprint("auth", __name__)


@bp.get("/health")
def health():
    try:
        query_one("SELECT 1 AS ok")
        return jsonify(status="ok", database=True)
    except Exception as exc:
        # Keep the response minimal; log only the exception type and driver code,
        # never connection parameters or exception text that might contain them.
        current_app.logger.warning(
            "Database health check failed (%s, errno=%s)",
            type(exc).__name__, getattr(exc, "errno", None))
        return jsonify(status="ok", database=False)


@bp.post("/login")
def login():
    data = json_body()
    require(data, ["username", "password"])
    user = query_one(
        "SELECT user_id, username, password_hash, role, is_active "
        "FROM USER_ACCOUNT WHERE username = %s", (data["username"],))
    if (not user or not user["is_active"]
            or not check_password_hash(user["password_hash"], data["password"])):
        raise ApiError("Invalid username or password", 401)
    execute("UPDATE USER_ACCOUNT SET last_login = NOW() WHERE user_id = %s", (user["user_id"],))
    return jsonify(
        token=create_token(user),
        user={"user_id": user["user_id"], "username": user["username"], "role": user["role"]})


@bp.get("/me")
@auth_required()
def me():
    return jsonify(user_id=g.user_id, username=g.username, role=g.role)


@bp.get("/dashboard/stats")
@auth_required()
def dashboard_stats():
    sets, _ = call_proc("sp_dashboard_stats")
    return jsonify(sets[0][0] if sets and sets[0] else {})


# ---------------- user management (Admin only) ----------------
@bp.get("/users")
@auth_required("Admin")
def list_users():
    return jsonify(query_all(
        "SELECT user_id, username, role, email, is_active, created_at, last_login "
        "FROM USER_ACCOUNT ORDER BY user_id"))


@bp.post("/users")
@auth_required("Admin")
def create_user():
    data = json_body()
    require(data, ["username", "password", "role"])
    new_id, _ = execute(
        "INSERT INTO USER_ACCOUNT (username, password_hash, role, email) VALUES (%s, %s, %s, %s)",
        (data["username"], generate_password_hash(data["password"], method="pbkdf2:sha256"),
         data["role"], data.get("email") or None))
    return jsonify(user_id=new_id, message="User created"), 201


@bp.put("/users/<int:user_id>")
@auth_required("Admin")
def update_user(user_id):
    data = json_body()
    sets, params = [], []
    for col in ("role", "email", "is_active"):
        if col in data:
            sets.append(f"{col} = %s")
            params.append(data[col])
    if data.get("password"):
        sets.append("password_hash = %s")
        params.append(generate_password_hash(data["password"], method="pbkdf2:sha256"))
    if not sets:
        raise ApiError("No valid fields to update")
    if not query_one("SELECT 1 AS x FROM USER_ACCOUNT WHERE user_id = %s", (user_id,)):
        raise ApiError("User not found", 404)
    execute(f"UPDATE USER_ACCOUNT SET {', '.join(sets)} WHERE user_id = %s", params + [user_id])
    return jsonify(message="User updated")


# ---------------- audit log (Admin only) ----------------
@bp.get("/audit")
@auth_required("Admin")
def audit_log():
    where, params = [], []
    for col in ("table_name", "user_id", "action"):
        v = request.args.get(col)
        if v:
            where.append(f"a.{col} = %s")
            params.append(v)
    try:
        limit = min(int(request.args.get("limit", 200)), 1000)
    except ValueError:
        limit = 200
    sql = ("SELECT a.*, u.username FROM AUDIT_LOG a "
           "LEFT JOIN USER_ACCOUNT u ON u.user_id = a.user_id"
           + (" WHERE " + " AND ".join(where) if where else "")
           + " ORDER BY a.log_id DESC LIMIT %s")
    return jsonify(query_all(sql, params + [limit]))
