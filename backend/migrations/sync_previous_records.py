import sys
import os
from datetime import datetime

# Add the parent directory to the path so we can import from backend
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import cursor, conn, _process_session_absences

def sync_previous_records():
    print("Starting sync of previous attendance records...")
    
    # 1. Get all distinct dates that have some attendance data
    # (We assume these are working days since people have checked in)
    cursor.execute("SELECT DISTINCT date FROM daily_attendance_status ORDER BY date ASC")
    dates = [row[0] for row in cursor.fetchall()]
    
    total_dates = len(dates)
    print(f"Found {total_dates} dates with attendance data.")
    
    if total_dates == 0:
        print("No dates found to sync.")
        return
        
    for idx, date_str in enumerate(dates):
        print(f"[{idx+1}/{total_dates}] Syncing records for {date_str}...")
        try:
            # We treat past dates as if the entire day (AN) is over
            _process_session_absences(date_str, "AN")
        except Exception as e:
            print(f"Failed to sync {date_str}: {e}")
            
    print("Sync completed successfully.")

if __name__ == "__main__":
    sync_previous_records()
