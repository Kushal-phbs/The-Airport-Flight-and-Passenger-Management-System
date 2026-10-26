"""MySQL access helpers.

Every request gets ONE pooled connection (stored in flask.g). When it is
opened we run  SET @app_user_id = <logged-in user>  so the triggers can write
the user into AUDIT_LOG.  All SQL values are passed as parameters (%s) to
prevent SQL injection.
"""
from flask import g
from mysql.connector import pooling

from config import Config

_pool = None


def _get_pool():
    global _pool
    if _pool is None:
        _pool = pooling.MySQLConnectionPool(
            pool_name="airport_pool",
            pool_size=5,
            pool_reset_session=True,
            host=Config.DB_HOST,
            port=Config.DB_PORT,
            user=Config.DB_USER,
            password=Config.DB_PASSWORD,
            database=Config.DB_NAME,
            autocommit=True,
            use_pure=True,
            charset="utf8mb4",
        )
    return _pool


def get_conn():
    if "db" not in g:
        conn = _get_pool().get_connection()
        cur = conn.cursor()
        cur.execute("SET @app_user_id = %s", (getattr(g, "user_id", None),))
        cur.close()
        g.db = conn
    return g.db


def close_conn(exc=None):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def query_all(sql, params=None):
    cur = get_conn().cursor(dictionary=True)
    try:
        cur.execute(sql, params or ())
        return cur.fetchall()
    finally:
        cur.close()


def query_one(sql, params=None):
    cur = get_conn().cursor(dictionary=True)
    try:
        cur.execute(sql, params or ())
        return cur.fetchone()
    finally:
        cur.close()


def execute(sql, params=None):
    """INSERT / UPDATE / DELETE. Returns (last_insert_id, rows_affected)."""
    cur = get_conn().cursor()
    try:
        cur.execute(sql, params or ())
        return cur.lastrowid, cur.rowcount
    finally:
        cur.close()


def call_proc(name, args=()):
    """Call a stored procedure.

    Returns (result_sets, out_args):
      result_sets = list of result sets, each a list of dict rows
      out_args    = list of all arguments, OUT parameters filled in
    """
    cur = get_conn().cursor()
    try:
        out_args = cur.callproc(name, list(args))
        sets = []
        for res in cur.stored_results():
            cols = [d[0] for d in res.description]
            sets.append([dict(zip(cols, row)) for row in res.fetchall()])
        return sets, list(out_args)
    finally:
        cur.close()
