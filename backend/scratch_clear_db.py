import psycopg2
import os
from dotenv import load_dotenv

load_dotenv()

def clear_db():
    conn = psycopg2.connect(
        host=os.environ.get("PG_HOST", "127.0.0.1"),
        user=os.environ.get("PG_USER", "attenda"),
        password=os.environ.get("PG_PASSWORD", "attenda_password"),
        database=os.environ.get("PG_DB", "attenda"),
        port=os.environ.get("PG_PORT", "5432")
    )
    cursor = conn.cursor()
    try:
        print("Clearing tables...")
        # Get list of all tables in public schema
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
        """)
        tables = [row[0] for row in cursor.fetchall()]
        
        for table in tables:
            if table == 'users':
                # Delete all users except admin
                cursor.execute("DELETE FROM users WHERE role != 'admin'")
                print("Cleaned users table (kept admin)")
            elif table in ('system_config', 'ccl_settings', 'leave_settings'):
                # Keep configuration
                print(f"Skipping configuration table: {table}")
            else:
                try:
                    cursor.execute(f"TRUNCATE TABLE {table} CASCADE")
                    print(f"Truncated table: {table}")
                except Exception as e:
                    print(f"Failed to truncate {table}: {e}")
                    conn.rollback()
        
        conn.commit()
        print("Database cleared successfully!")
    except Exception as e:
        print(f"Error: {e}")
        conn.rollback()
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    clear_db()
