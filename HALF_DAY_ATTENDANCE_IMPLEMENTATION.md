# Half-Day Attendance System Implementation

## Overview
This implementation adds half-day attendance tracking with 0.5 values to the existing attendance system. Each half-day session (first half or second half) counts as 0.5 attendance points, enabling precise attendance calculation.

## Implementation Summary

### 1. Database Model Changes
- **File**: `backend/app/database/models.py`
- **Change**: Added `attendance_value` field to `DailyAttendanceStatus` dataclass
- **Type**: `Optional[Decimal]` - Stores 0.0, 0.5, or 1.0

### 2. API Schema Updates
- **File**: `backend/app/api/schemas/attendance.py`
- **Changes**:
  - Added `attendance_value` field to `DailyStatusResponse`
  - Created `AttendanceValueSummary` schema for period summaries
  - Created `HalfDayReport` schema for daily half-day breakdowns
  - Added validation to ensure values are between 0.0 and 1.0

### 3. Service Layer Logic
- **File**: `backend/app/services/attendance_service.py`
- **Changes**:
  - Added `_calculate_attendance_value()` method for 0.5 calculation logic
  - Updated `_sync_daily_status()` to calculate and store attendance values
  - Updated `get_daily_status()` to include attendance_value in response
  - Added `get_attendance_value_summary()` for period-based reporting
  - Added `get_half_day_report()` for daily half-day breakdowns

### 4. Repository Layer Updates
- **File**: `backend/app/database/repositories/attendance_repository.py`
- **Changes**:
  - Added `update_attendance_value()` for manual value updates
  - Added `get_attendance_value_sum()` for aggregating values over periods
  - Added `recalculate_attendance_values()` for recalculation based on half statuses

### 5. API Endpoints
- **File**: `backend/app/api/v1/attendance.py`
- **New Endpoints**:
  - `GET /api/v1/attendance/value-summary/{reg_no}?start_date=&end_date=` - Get attendance value summary
  - `GET /api/v1/attendance/percentage/{reg_no}?period=month:YYYY-MM` - Get attendance percentage
  - `GET /api/v1/attendance/half-day-report/{report_date}` - Get half-day breakdown report

### 6. Migration Scripts
- **File**: `backend/migrations/add_attendance_value_column.py`
  - Adds `attendance_value` column to database
  - Backfills existing records with calculated values
  
- **File**: `backend/migrations/backfill_attendance_values.py`
  - Recalculates attendance values for all existing records
  - Provides statistics and verification

## Attendance Value Calculation Logic

### Calculation Rules
```
Both halves present (Present + Present) = 1.0
One half present (Present + Absent) = 0.5
One half present (Absent + Present) = 0.5
Full day present (no half info) = 1.0
Half day status = 0.5
Holiday = 1.0
Leave = 0.0
Absent = 0.0
```

### Implementation Details
The calculation uses the following priority:
1. If `first_half_status` and `second_half_status` exist, calculate based on them
2. Otherwise, fall back to overall `status` field
3. Holidays count as full day (1.0) per institutional policy
4. Leave and absent days count as 0.0

## Deployment Steps

### 1. Run Database Migration
```bash
cd backend
python migrations/add_attendance_value_column.py
```

### 2. Verify Migration
The migration script will:
- Add the `attendance_value` column
- Backfill existing records
- Show statistics and sample data

### 3. Test the Endpoints
```bash
# Get daily status with attendance value
GET /api/v1/attendance/daily-status/{reg_no}

# Get attendance value summary for a period
GET /api/v1/attendance/value-summary/{reg_no}?start_date=2024-01-01&end_date=2024-01-31

# Get attendance percentage for a month
GET /api/v1/attendance/percentage/{reg_no}?period=month:2024-01

# Get half-day report for a specific date
GET /api/v1/attendance/half-day-report/2024-01-15
```

### 4. Recalculate if Needed
If you need to recalculate attendance values after changes:
```bash
python migrations/backfill_attendance_values.py
```

## API Response Examples

### Daily Status Response
```json
{
  "date": "2024-01-15",
  "status": "present",
  "leave_type": null,
  "leave_request_id": null,
  "attendance_value": 1.0
}
```

### Attendance Value Summary
```json
{
  "success": true,
  "reg_no": "2020CS001",
  "name": "John Doe",
  "dept": "CSE",
  "start_date": "2024-01-01",
  "end_date": "2024-01-31",
  "total_attendance_value": 22.5,
  "total_working_days": 22,
  "attendance_percentage": 102.27,
  "full_days": 20,
  "half_days": 5,
  "absent_days": 2,
  "leave_days": 1
}
```

### Half-Day Report
```json
{
  "success": true,
  "date": "2024-01-15",
  "total_users": 50,
  "full_day_present": 40,
  "first_half_only": 3,
  "second_half_only": 2,
  "full_day_absent": 3,
  "on_leave": 2,
  "details": [...]
}
```

## Integration with Existing System

### Existing Half-Day Status Columns
The system already has:
- `first_half_status` - Status of first half (Present/Absent)
- `second_half_status` - Status of second half (Present/Absent)
- `first_half_in_time` - First half check-in time
- `second_half_in_time` - Second half check-in time

The new `attendance_value` column complements these by providing a numeric value for calculations.

### Compatibility
- The implementation is backward compatible
- Existing records are backfilled with calculated values
- New attendance marking will automatically calculate values
- The system works with or without half-day status information

## Testing Recommendations

### Unit Tests
1. Test `_calculate_attendance_value()` with all combinations
2. Test attendance value calculation for various scenarios
3. Test aggregation methods for accuracy

### Integration Tests
1. Test API endpoints with real data
2. Verify migration scripts on test database
3. Test backfill script on existing data

### Manual Testing
1. Mark attendance for first half only → verify 0.5 value
2. Mark attendance for second half only → verify 0.5 value
3. Mark attendance for both halves → verify 1.0 value
4. Check monthly aggregation accuracy
5. Verify percentage calculations

## Troubleshooting

### Migration Issues
If the migration fails:
1. Check database connection settings in `app/config.py`
2. Verify you have necessary permissions
3. Check if column already exists (script handles this)

### Incorrect Values
If attendance values seem incorrect:
1. Run the backfill script: `python migrations/backfill_attendance_values.py`
2. Check half-day status columns are properly set
3. Verify the calculation logic in `_calculate_attendance_value()`

### API Errors
If endpoints return errors:
1. Verify the attendance router is included in main routes
2. Check database connection is working
3. Review service dependency injection

## Future Enhancements

Potential improvements:
1. Add custom period support (week, semester, academic year)
2. Add department-wide attendance value reports
3. Export attendance value reports to Excel/PDF
4. Add attendance value trends and analytics
5. Configurable holiday/leave value policies

## Support
For issues or questions about this implementation, refer to:
- Migration scripts in `backend/migrations/`
- Service logic in `backend/app/services/attendance_service.py`
- API documentation via FastAPI auto-docs at `/docs`
