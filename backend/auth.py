import datetime
from functools import wraps

import jwt
from flask import g, jsonify, request

from config import Config
from db import query_one


def create_token(user):
    payload = {
        "user_id": user["user_id"],
        "username": user["username"],
        "role": user["role"],
        "exp": datetime.datetime.now(datetime.timezone.utc)
        + datetime.timedelta(hours=Config.JWT_EXPIRY_HOURS),
    }
    return jwt.encode(payload, Config.SECRET_KEY, algorithm="HS256")


def auth_required(*roles):
    """@auth_required()                 -> any logged-in user
       @auth_required("Admin","Staff")  -> only those roles"""

    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            if not header.startswith("Bearer "):
                return jsonify(error="Authentication required"), 401
            try:
                data = jwt.decode(header[7:], Config.SECRET_KEY, algorithms=["HS256"])
            except jwt.ExpiredSignatureError:
                return jsonify(error="Session expired, please log in again"), 401
            except jwt.InvalidTokenError:
                return jsonify(error="Invalid token"), 401

            g.user_id = data["user_id"]
            # re-check the account on every request so deactivated users / role
            # changes take effect immediately (not only when the token expires)
            row = query_one("SELECT role, is_active FROM USER_ACCOUNT WHERE user_id = %s",
                            (data["user_id"],))
            if not row or not row["is_active"]:
                return jsonify(error="Account is disabled or no longer exists"), 401
            g.username = data["username"]
            g.role = row["role"]
            if roles and g.role not in roles:
                return jsonify(error="You do not have permission to do this"), 403
            return fn(*args, **kwargs)

        return wrapper

    return decorator
