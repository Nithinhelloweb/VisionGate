"""
PostgreSQL adapter: drop-in replacement for sqlite3.
Provides a robust, thread-safe, pool-managed cursor that prevents connection leaks and exhaustion.
"""

import os
import re
import time
import threading
from dotenv import load_dotenv
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

# Load .env file if it exists (check backend/.env then root .env)
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))


class _ThreadLocalCursor:
    """
    A thread-local cursor that wraps psycopg2 connections.
    Mimics sqlite3 cursor API: execute(sql, params), fetchone(), fetchall().
    Uses ? placeholders (auto-converted to %s).
    """

    def __init__(self):
        self._local = threading.local()
        self._pool = None
        self._lock = threading.Lock()
        self._init_pool()

    def _init_pool(self):
        with self._lock:
            if self._pool is not None:
                try:
                    self._pool.closeall()
                except Exception:
                    pass
            self._pool = pool.ThreadedConnectionPool(
                minconn=8,
                maxconn=40,
                host=os.environ.get("PG_HOST", "localhost"),
                port=int(os.environ.get("PG_PORT", "5432")),
                dbname=os.environ.get("PG_DB", "attenda"),
                user=os.environ.get("PG_USER", "attenda"),
                password=os.environ.get("PG_PASSWORD", "attenda_password"),
            )

    def _is_conn_alive(self, conn):
        """Check if connection is alive and ready."""
        if conn is None:
            return False
        try:
            if getattr(conn, "closed", 1) != 0:
                return False
            return conn.status == psycopg2.extensions.STATUS_READY
        except Exception:
            return False

    def _get_conn(self):
        conn = getattr(self._local, "conn", None)
        cur = getattr(self._local, "cursor", None)

        if not self._is_conn_alive(conn) or cur is None or getattr(cur, "closed", True):
            if conn is not None:
                try:
                    if getattr(self._local, "is_from_pool", False):
                        self._pool.putconn(conn)
                    else:
                        conn.close()
                except Exception:
                    pass
                self._local.conn = None
                self._local.cursor = None

            new_conn = None
            is_from_pool = True
            for attempt in range(3):
                try:
                    new_conn = self._pool.getconn()
                    is_from_pool = True
                    break
                except (psycopg2.pool.PoolError, Exception):
                    if attempt < 2:
                        time.sleep(0.05 * (attempt + 1))
                    else:
                        try:
                            new_conn = psycopg2.connect(
                                host=os.environ.get("PG_HOST", "localhost"),
                                port=int(os.environ.get("PG_PORT", "5432")),
                                dbname=os.environ.get("PG_DB", "attenda"),
                                user=os.environ.get("PG_USER", "attenda"),
                                password=os.environ.get("PG_PASSWORD", "attenda_password"),
                            )
                            is_from_pool = False
                        except Exception:
                            self._init_pool()
                            new_conn = self._pool.getconn()
                            is_from_pool = True

            if new_conn is None:
                raise psycopg2.OperationalError("Unable to acquire PostgreSQL database connection.")

            new_conn.autocommit = True
            self._local.conn = new_conn
            self._local.is_from_pool = is_from_pool
            self._local.cursor = new_conn.cursor()

        return self._local.conn, self._local.cursor

    def execute(self, sql, params=None):
        conn, cur = self._get_conn()
        try:
            if params is not None:
                if "?" in sql:
                    sql = re.sub(r"%(?!%)", "%%", sql)
                    sql = sql.replace("?", "%s")
                else:
                    sql = re.sub(r"%(?!(?:s|%|\([a-zA-Z0-9_]+\)s))", "%%", sql)
                cur.execute(sql, params)
            else:
                cur.execute(sql)
        except (psycopg2.OperationalError, psycopg2.InterfaceError):
            self.close()
            conn, cur = self._get_conn()
            if params is not None:
                if "?" in sql:
                    sql = re.sub(r"%(?!%)", "%%", sql)
                    sql = sql.replace("?", "%s")
                else:
                    sql = re.sub(r"%(?!(?:s|%|\([a-zA-Z0-9_]+\)s))", "%%", sql)
                cur.execute(sql, params)
            else:
                cur.execute(sql)

        self._local.lastrowid = None
        if sql.strip().upper().startswith("INSERT"):
            try:
                with conn.cursor() as temp_cur:
                    temp_cur.execute("SELECT LASTVAL()")
                    row = temp_cur.fetchone()
                    if row:
                        self._local.lastrowid = row[0]
            except Exception:
                pass
        return self

    def executemany(self, sql, seq_of_params):
        conn, cur = self._get_conn()
        try:
            if "?" in sql:
                sql = re.sub(r"%(?!%)", "%%", sql)
                sql = sql.replace("?", "%s")
            else:
                sql = re.sub(r"%(?!(?:s|%|\([a-zA-Z0-9_]+\)s))", "%%", sql)
            cur.executemany(sql, seq_of_params)
        except (psycopg2.OperationalError, psycopg2.InterfaceError):
            self.close()
            conn, cur = self._get_conn()
            if "?" in sql:
                sql = re.sub(r"%(?!%)", "%%", sql)
                sql = sql.replace("?", "%s")
            else:
                sql = re.sub(r"%(?!(?:s|%|\([a-zA-Z0-9_]+\)s))", "%%", sql)
            cur.executemany(sql, seq_of_params)
        return self

    def fetchone(self):
        _, cur = self._get_conn()
        return cur.fetchone()

    def fetchall(self):
        _, cur = self._get_conn()
        return cur.fetchall()

    def fetchval(self, column=0):
        _, cur = self._get_conn()
        row = cur.fetchone()
        if row is None:
            return None
        return row[column] if column < len(row) else None

    @property
    def lastrowid(self):
        return getattr(self._local, "lastrowid", None)

    @property
    def rowcount(self):
        _, cur = self._get_conn()
        return cur.rowcount

    @property
    def description(self):
        _, cur = self._get_conn()
        return cur.description

    def cursor(self):
        return self

    def commit(self):
        pass

    def rollback(self):
        pass

    def close(self):
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            try:
                if getattr(self._local, "is_from_pool", False):
                    self._pool.putconn(conn)
                else:
                    conn.close()
            except Exception:
                try:
                    conn.close()
                except Exception:
                    pass
            self._local.conn = None
            self._local.cursor = None

    def closeall(self):
        with self._lock:
            if self._pool is not None:
                try:
                    self._pool.closeall()
                except Exception:
                    pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


# Global cursor instance - drop-in replacement for sqlite3 cursor
cursor = _ThreadLocalCursor()

# Compatibility alias & helper
conn = cursor

def get_db_connection():
    return cursor

