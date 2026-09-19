from datetime import date
from typing import Optional, Literal
from pydantic import BaseModel, Field, ConfigDict

class DailyStatusResponse(BaseModel):
    """Daily attendance status for a user."""
    date: date = Field(..., description="Date of status")
    status: Literal["present", "absent", "half_day", "leave", "holiday"] = Field(..., description="Attendance status")
    leave_type: Optional[Literal["casual", "earned", "od", "sick"]] = Field(None, description="Leave type if on leave")
    leave_request_id: Optional[int] = Field(None, description="Associated leave request ID")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "date": "2024-01-15",
                    "status": "present",
                    "leave_type": None,
                    "leave_request_id": None
                }
            ]
        }
    )

print("DailyStatusResponse defined")
