"""JWT-based authentication service for secure user authentication."""
from datetime import datetime, timedelta, timezone
from typing import Optional
from dataclasses import dataclass
import jwt
import bcrypt
from fastapi import HTTPException, status
from app.config import settings
from app.database.repositories.user_repository import UserRepository
from app.database.models import User


@dataclass
class TokenData:
    reg_no: str
    username: str
    role: str
    name: str


class AuthService:
    def __init__(self, user_repo: UserRepository):
        self.user_repo = user_repo

    def hash_password(self, password: str) -> str:
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    def verify_password(self, plain_password: str, hashed: str) -> bool:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed.encode('utf-8'))

    def create_access_token(
        self,
        user: User,
        expires_delta: Optional[timedelta] = None
    ) -> str:
        to_encode = {
            "sub": user.username,
            "reg_no": user.reg_no,
            "role": user.role,
            "name": user.name,
            "dept": user.dept,
            "type": "access",
            "iat": datetime.now(timezone.utc),
        }
        if expires_delta:
            expire = datetime.now(timezone.utc) + expires_delta
        else:
            expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

        to_encode["exp"] = expire
        return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

    def decode_token(self, token: str) -> TokenData:
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
            return TokenData(
                reg_no=payload["reg_no"],
                username=payload["sub"],
                role=payload["role"],
                name=payload["name"]
            )
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired"
            )
        except jwt.InvalidTokenError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token"
            )

    async def authenticate_user(self, username: str, password: str) -> Optional[User]:
        user = await self.user_repo.get_by_username(username)
        if not user:
            user = await self.user_repo.get_by_reg_no(username)

        if not user:
            return None

        if not self.verify_password(password, user.password_hash):
            return None

        return user

    def verify_token(self, token: str) -> TokenData:
        return self.decode_token(token)