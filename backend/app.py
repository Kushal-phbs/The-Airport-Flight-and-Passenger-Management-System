import datetime
import os
from decimal import Decimal

import mysql.connector
from flask import Flask, jsonify, request, send_from_directory
from flask.json.provider import DefaultJSONProvider

import db
from config import Config
from utils import ApiError

FRONTEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))


class AppJSONProvider(DefaultJSONProvider):
    """Dates -> 'YYYY-MM-DD', datetimes -> 'YYYY-MM-DD HH:MM:SS',
    TIME columns -> 'HH:MM:SS', DECIMAL -> number."""

    def default(self, o):
        if isinstance(o, datetime.datetime):
            return o.strftime("%Y-%m-%d %H:%M:%S")
        if isinstance(o, datetime.date):
            return o.isoformat()
        if isinstance(o, datetime.timedelta):
            total = int(o.total_seconds())
            return "%02d:%02d:%02d" % (total // 3600, (total % 3600) // 60, total % 60)
        if isinstance(o, Decimal):
            return float(o)
        return super().default(o)


def create_app():
    if not Config.SECRET_KEY or Config.SECRET_KEY == "change-this-to-a-long-random-string":
        raise RuntimeError("Set a unique SECRET_KEY in backend/.env before starting the application.")
    app = Flask(__name__, static_folder=FRONTEND_DIR, static_url_path="")
    app.config["SECRET_KEY"] = Config.SECRET_KEY
    app.json = AppJSONProvider(app)
    app.teardown_appcontext(db.close_conn)

    from routes.auth_routes import bp as auth_bp
    from routes.crud import bp as crud_bp
    from routes.flights import bp as flights_bp
    from routes.bookings import bp as bookings_bp

    for bp in (auth_bp, crud_bp, flights_bp, bookings_bp):
        app.register_blueprint(bp, url_prefix="/api")

    # ---------------- error handling ----------------
    @app.errorhandler(ApiError)
    def handle_api_error(e):
        return jsonify(error=e.message), e.status

    @app.errorhandler(mysql.connector.Error)
    def handle_db_error(e):
        errno = getattr(e, "errno", None)
        msg = getattr(e, "msg", None) or str(e)
        if errno == 1644:      # SIGNAL from our triggers / procedures
            return jsonify(error=msg), 400
        if errno == 1062:
            return jsonify(error="Duplicate value: " + msg), 409
        if errno == 1451:
            return jsonify(error="Cannot delete: this record is used by other records"), 409
        if errno == 1452:
            return jsonify(error="Invalid reference: the related record does not exist"), 400
        if errno == 3819:
            return jsonify(error="A value violates a database check rule"), 400
        if errno in (1048, 1265, 1292, 1366, 1406):
            return jsonify(error="Invalid or missing value: " + msg), 400
        app.logger.exception("Database error")
        return jsonify(error="Database error. See the server log."), 500

    @app.errorhandler(404)
    def not_found(e):
        if request.path.startswith("/api/"):
            return jsonify(error="Endpoint not found"), 404
        return e

    @app.errorhandler(405)
    def method_not_allowed(e):
        if request.path.startswith("/api/"):
            return jsonify(error="Method not allowed"), 405
        return e

    @app.get("/")
    def index():
        if os.path.exists(os.path.join(FRONTEND_DIR, "index.html")):
            return send_from_directory(FRONTEND_DIR, "index.html")
        return jsonify(message="Airport API is running. Frontend folder not found.")

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=Config.DEBUG)
