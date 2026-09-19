"""Authentication routes."""
from fastapi import APIRouter, Request, HTTPException
from typing import Optional

from app.services.auth_service import AuthService
from app.database.repositories.user_repository import UserRepository
from app.database.connection import db_pool
from app.api.schemas.auth import LoginRequest, LoginResponse

router = APIRouter()
auth_service = AuthService(UserRepository())


@router.post("/login", response_model=LoginResponse)
async def login(request: Request, login_data: LoginRequest):
    """Login with username and password - checks both users and other_staff tables"""
    try:
        # Check for VPN before processing login
        client_ip = request.client.host
        # TODO: Add VPN checking logic here

        # For now, delegate to auth service
        # This will need to be implemented in the AuthService
        raise HTTPException(status_code=501, detail="Login endpoint needs implementation")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Login failed")


@router.post("/login_face")
async def login_face(request: Request):
    """Login with face recognition (existing functionality)"""
    # This would integrate with existing face recognition
    # For now, return error to indicate face login not implemented
    raise HTTPException(status_code=501, detail="Face login not implemented")


@router.get("/settings/allow_any_network")
async def get_network_setting():
    """Public endpoint to check if any network is allowed (for client-side validation)"""
    # TODO: Implement settings service
    return {
        "allow_any_network": False,
        "college_ssid": "",
        "enforce_geo_fence": True,
        "enforce_app_geo_fence": True,
        "enforce_vpn_blocking": True,
    }


@router.get("/check_vpn")
async def check_vpn(request: Request):
    """Check if client IP is from a known VPN or hosting provider"""
    client_ip = request.client.host

    # TODO: Implement VPN checking
    return {
        "vpn_detected": False,
        "client_ip": client_ip,
        "message": "VPN check not implemented",
    }