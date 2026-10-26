from flask import request


class ApiError(Exception):
    """Raise this anywhere to return {"error": message} with an HTTP status."""

    def __init__(self, message, status=400):
        super().__init__(message)
        self.message = message
        self.status = status


def json_body():
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}


def missing_fields(data, fields):
    out = []
    for f in fields:
        v = data.get(f)
        if v is None or (isinstance(v, str) and v.strip() == ""):
            out.append(f)
    return out


def require(data, fields):
    miss = missing_fields(data, fields)
    if miss:
        raise ApiError("Missing required field(s): " + ", ".join(miss))
