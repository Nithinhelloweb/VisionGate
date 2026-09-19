#!/usr/bin/env python3
"""
SQLite to PostgreSQL Data Importer for Attenda / VisionGate
Imports existing SQLite (.db) table data directly into the PostgreSQL database container.
"""

import os
import sys
import sqlite3
import psycopg2
from psycopg2.extras import execute_values

PG_HOST = os.environ.get("PG_HOST", "localhost")
PG_PORT = int(os.environ.get("PG_PORT", "5432"))
PG_USER = os.environ.get("PG_USER", "attenda")
PG_PASSWORD = os.environ.get("PG_PASSWORD", "attenda_password")
PG_DB = os.environ.get("PG_DB", "attenda")

SQLITE_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "backend", "attenda.db")

def main():
    if not os.path.exists(SQLITE_PATH):
        print(f"[!] SQLite file not found at: {SQLITE_PATH}")
        print("    If you want to import a specific sqlite database file, run:")
        print(f"    python scripts/migrate_sqlite_to_postgres.py <path_to_db_file.db>")
        sys.exit(1)

    print(f"Connecting to SQLite database: {SQLITE_PATH}")
    sqlite_conn = sqlite3.connect(SQLITE_PATH)
    sqlite_cursor = sqlite_conn.cursor()

    print(f"Connecting to PostgreSQL database at {PG_HOST}:{PG_PORT}/{PG_DB}...")
    try:
        pg_conn = psycopg2.connect(
            host=PG_HOST,
            port=PG_PORT,
            user=PG_USER,
            password=PG_PASSWORD,
            dbname=PG_DB
        )
        pg_conn.autocommit = True
        pg_cursor = pg_conn.cursor()
    except Exception as e:
        print(f"[ERROR] Could not connect to PostgreSQL: {e}")
        sys.exit(1)

    # Get all tables from SQLite
    sqlite_cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    tables = [t[0] for t in sqlite_cursor.fetchall()]
    print(f"Found {len(tables)} tables in SQLite database.")

    for table in tables:
        # Check if table exists in PostgreSQL
        pg_cursor.execute(
            "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = %s);",
            (table,)
        )
        exists = pg_cursor.fetchone()[0]
        if not exists:
            print(f"[-] Skipping table '{table}' (does not exist in PostgreSQL schema).")
            continue

        # Fetch rows from SQLite
        sqlite_cursor.execute(f"SELECT * FROM {table}")
        rows = sqlite_cursor.fetchall()
        if not rows:
            print(f"[-] Table '{table}' is empty in SQLite.")
            continue

        columns = [desc[0] for desc in sqlite_cursor.description]
        col_names_str = ", ".join([f'"{c}"' for c in columns])

        print(f"[+] Migrating {len(rows)} row(s) into PostgreSQL table '{table}'...")
        try:
            placeholders = ",".join(["%s"] * len(columns))
            query = f'INSERT INTO "{table}" ({col_names_str}) VALUES ({placeholders}) ON CONFLICT DO NOTHING'
            pg_cursor.executemany(query, rows)
            print(f"    ✓ Successfully migrated '{table}'.")
        except Exception as e:
            print(f"    [!] Error inserting into '{table}': {e}")

    sqlite_conn.close()
    pg_conn.close()
    print("\n[✓] Migration from SQLite to PostgreSQL completed successfully.")

if __name__ == "__main__":
    main()
