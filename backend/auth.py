# Authentication and Authorization Module
# Extracted from main.py for better organization

import os
import base64
import bcrypt
import secrets
import jwt
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from fastapi import HTTPException, Request

import pg_adapter
cursor = pg_adapter.cursor

# JWT Configuration - loaded from environment variables
JWT_SECRET = os.environ.get("JWT_SECRET", "visiongate_default_jwt_secret_change_in_production")
JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256")
JWT_EXPIRATION_HOURS = int(os.environ.get("JWT_EXPIRATION_HOURS", "24"))


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    """Verify a password against its hash."""
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))
    except Exception:
        return False


def create_jwt_token(user_data: dict) -> str:
    """Create JWT token for user authentication."""
    expire = datetime.utcnow() + timedelta(hours=JWT_EXPIRATION_HOURS)
    to_encode = user_data.copy()
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return encoded_jwt


def verify_jwt_token(token: str) -> Optional[dict]:
    """Verify and decode JWT token."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.PyJWTError:
        return None


def extract_token_from_request(request: Request) -> Optional[str]:
    """Extract token from request headers or query parameters."""
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        return auth_header[7:]

    return request.query_params.get("token")


def get_user_by_username(username: str):
    """Get user by username."""
    cursor.execute("SELECT * FROM users WHERE username = ?", (username,))
    return cursor.fetchone()


def get_user_by_reg_no(reg_no: str):
    """Get user by registration number (case-insensitive)."""
    cursor.execute("SELECT * FROM users WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    return cursor.fetchone()


# Other staff functions
OTHER_STAFF_ROLES = (
    "principal",
    "placement_staff",
    "lab_technician",
    "system_admin",
    "office_staff",
)


def get_other_staff_by_username(username: str):
    """Get other_staff by username."""
    cursor.execute("SELECT * FROM other_staff WHERE username = ?", (username,))
    return cursor.fetchone()


def get_other_staff_by_reg_no(reg_no: str):
    """Get other_staff by registration number (case-insensitive)."""
    cursor.execute(
        "SELECT * FROM other_staff WHERE LOWER(reg_no) = LOWER(?)", (reg_no,)
    )
    return cursor.fetchone()


def get_default_department_for_role(role: str) -> Optional[str]:
    """Return the default department for roles that should never have an empty department."""
    role_defaults = {
        "principal": "Administration",
        "placement_staff": "Placement Staff",
        "lab_technician": "Lab Technician",
        "system_admin": "System Admin",
        "office_staff": "Office Staff",
    }
    return role_defaults.get((role or "").strip().lower())


# Authentication verification functions
def verify_staff_token(request: Request) -> dict:
    """Verify staff authentication token."""
    token = extract_token_from_request(request)
    if not token:
        raise HTTPException(status_code=401, detail="Authentication token required")

    # Accept base64 encoded username:password or JWT token
    try:
        # Check JWT first
        jwt_payload = verify_jwt_token(token)
        if jwt_payload:
            return jwt_payload

        # Fallback to Base64 credential token
        decoded = base64.b64decode(token).decode("utf-8")
        username, password = decoded.split(":", 1)

        # Try users table first
        user = get_user_by_username(username)
        if user and verify_password(password, user[2]):
            return {
                "id": user[0],
                "username": user[1],
                "reg_no": user[3],
                "name": user[4],
                "dept": user[5],
                "role": user[6],
            }

        # Try other_staff table
        other_staff = get_other_staff_by_username(username)
        if other_staff and verify_password(password, other_staff[2]):
            return {
                "id": other_staff[0],
                "username": other_staff[1],
                "reg_no": other_staff[3],
                "name": other_staff[4],
                "dept": other_staff[7],
                "role": other_staff[6],
            }

    except Exception:
        pass

    raise HTTPException(status_code=401, detail="Invalid authentication token")


def verify_admin_token(request: Request) -> dict:
    """Verify admin authentication token."""
    user = verify_staff_token(request)
    if user.get("role") not in ["admin", "hod"]:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


def verify_hod_token(request: Request) -> dict:
    """Verify HOD authentication token."""
    user = verify_staff_token(request)
    if user.get("role") not in ["hod", "admin"]:
        raise HTTPException(status_code=403, detail="HOD access required")
    return user


def verify_user_token(request: Request) -> Optional[dict]:
    """Verify general user token (for any authenticated user)."""
    try:
        return verify_staff_token(request)
    except HTTPException:
        return None