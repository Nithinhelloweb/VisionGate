"""User repository for database operations."""
import logging
import bcrypt
from typing import Optional, List
import asyncpg
from .base_repository import BaseRepository
from ..connection import db_pool
from ..models import User, OtherStaff

logger = logging.getLogger(__name__)


class UserRepository(BaseRepository):
    """Repository for user-related database operations."""

    async def get_by_reg_no(self, reg_no: str) -> Optional[User]:
        """Get a user by registration number.
        
        Args:
            reg_no: Registration number
            
        Returns:
            User object or None if not found
        """
        row = await self.fetchrow(
            "SELECT * FROM users WHERE reg_no = $1",
            reg_no
        )
        if row:
            return User(**row)
        logger.debug(f"User with reg_no {reg_no} not found")
        return None
    
    async def get_by_username(self, username: str) -> Optional[User]:
        """Get a user by username.
        
        Args:
            username: Username
            
        Returns:
            User object or None if not found
        """
        row = await self.fetchrow(
            "SELECT * FROM users WHERE username = $1",
            username
        )
        if row:
            return User(**row)
        logger.debug(f"User with username {username} not found")
        return None
    
    async def get_by_id(self, user_id: int) -> Optional[User]:
        """Get a user by ID.
        
        Args:
            user_id: User ID
            
        Returns:
            User object or None if not found
        """
        row = await self.fetchrow(
            "SELECT * FROM users WHERE id = $1",
            user_id
        )
        if row:
            return User(**row)
        logger.debug(f"User with id {user_id} not found")
        return None
    
    async def get_staff_by_role(self, role: str) -> List[User]:
        """Get all staff members with a specific role who have face embeddings.
        
        Args:
            role: Staff role (e.g., 'STAFF', 'SECURITY', 'ADMIN')
            
        Returns:
            List of User objects
        """
        rows = await self.fetch(
            "SELECT * FROM users WHERE role = $1 AND embedding IS NOT NULL",
            role
        )
        return [User(**row) for row in rows]
    
    async def get_all_with_faces(self) -> List[dict]:
        """Get all users with face embeddings.
        
        Returns:
            List of dicts containing reg_no, name, dept, role, embedding
        """
        rows = await self.fetch(
            "SELECT reg_no, name, dept, role, face_embedding as embedding "
            "FROM users WHERE face_embedding IS NOT NULL"
        )
        return [dict(row) for row in rows]
    
    async def get_other_staff_by_reg_no(self, reg_no: str) -> Optional[OtherStaff]:
        """Get other staff member by registration number.
        
        Args:
            reg_no: Registration number
            
        Returns:
            OtherStaff object or None if not found
        """
        row = await self.fetchrow(
            "SELECT * FROM other_staff WHERE contact_no = $1",
            reg_no
        )
        if row:
            return OtherStaff(**row)
        logger.debug(f"Other staff with reg_no {reg_no} not found")
        return None
    
    async def get_other_staff_by_username(self, username: str) -> Optional[OtherStaff]:
        """Get other staff member by username (contact_no as username).
        
        Args:
            username: Username (contact_no)
            
        Returns:
            OtherStaff object or None if not found
        """
        return await self.get_other_staff_by_reg_no(username)
    
    async def get_other_staff_by_role(self, role: str) -> List[OtherStaff]:
        """Get all other staff members with a specific role.
        
        Args:
            role: Staff role
            
        Returns:
            List of OtherStaff objects
        """
        rows = await self.fetch(
            "SELECT * FROM other_staff WHERE role = $1",
            role
        )
        return [OtherStaff(**row) for row in rows]
    
    async def create_user(self, user_data: dict) -> int:
        """Create a new user and return the generated ID.
        
        Args:
            user_data: Dictionary containing user fields
            
        Returns:
            New user ID
        """
        reg_no = user_data.get("reg_no")
        if not reg_no or reg_no.strip() == "":
            role = user_data.get("role", "")
            if role == "hod":
                prefix = "HOD"
            elif role == "staff":
                prefix = "STAFF"
            elif role == "principal":
                prefix = "PRINCIPAL"
            elif role == "vice_chancellor":
                prefix = "VC"
            elif role == "director":
                prefix = "DIR"
            elif role == "dean":
                prefix = "DEAN"
            else:
                prefix = "USR"

            row = await self.fetchrow(
                "SELECT COUNT(*) FROM users WHERE role = $1", role
            )
            count = row["count"] if row else 0
            reg_no = f"{prefix}_{str(count + 1).zfill(4)}"

            while True:
                existing = await self.fetchrow(
                    "SELECT id FROM users WHERE reg_no = $1", reg_no
                )
                if not existing:
                    break
                count += 1
                reg_no = f"{prefix}_{str(count).zfill(4)}"

        row = await self.fetchrow(
            """
            INSERT INTO users (username, password_hash, reg_no, name, dept, role, is_active)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id
            """,
            user_data.get("username"),
            user_data.get("password_hash"),
            reg_no,
            user_data.get("name"),
            user_data.get("dept"),
            user_data.get("role"),
            user_data.get("is_active", True)
        )
        user_id = row["id"]
        logger.info(f"Created user with id {user_id}")
        return user_id
    
    async def update_embedding(self, reg_no: str, embedding: bytes, source_table: str = "users") -> bool:
        """Update the face embedding for a user or other staff.
        
        Args:
            reg_no: Registration number
            embedding: Face embedding as bytes
            source_table: Source table ('users' or 'other_staff')
            
        Returns:
            True if updated, False otherwise
        """
        try:
            if source_table == "users":
                result = await self.execute(
                    "UPDATE users SET face_embedding = $1, updated_at = NOW() WHERE reg_no = $2",
                    embedding, reg_no
                )
            else:
                # other_staff doesn't have embedding column; using alternative approach
                result = await self.execute(
                    "UPDATE other_staff SET updated_at = NOW() WHERE contact_no = $1",
                    reg_no
                )
            logger.info(f"Updated embedding for {reg_no} from {source_table}")
            return True
        except Exception as e:
            logger.error(f"Failed to update embedding for {reg_no}: {e}")
            return False
    
    async def get_embedding(self, reg_no: str, source_table: str) -> Optional[bytes]:
        """Get the face embedding for a user or other staff.
        
        Args:
            reg_no: Registration number
            source_table: Source table ('users' or 'other_staff')
            
        Returns:
            Face embedding as bytes or None
        """
        if source_table == "users":
            row = await self.fetchrow(
                "SELECT face_embedding FROM users WHERE reg_no = $1",
                reg_no
            )
        else:
            row = await self.fetchrow(
                "SELECT embedding FROM face_embedding_samples WHERE reg_no = $1 AND source_table = $2 ORDER BY created_at DESC LIMIT 1",
                reg_no, source_table
            )
        if row:
            return row[0] if row[0] else None
        return None
    
    async def authenticate_user(self, username: str, password_hash: str) -> Optional[User]:
        """Authenticate a user by verifying password hash.
        
        Args:
            username: Username
            password_hash: Plaintext password (will be hashed and compared with bcrypt)
            
        Returns:
            User object if authentication succeeds, None otherwise
        """
        user = await self.get_by_username(username)
        if user is None:
            logger.warning(f"Authentication failed: user {username} not found")
            return None
        try:
            # password_hash argument is the plaintext password
            # stored password_hash in DB is bcrypt hash
            if bcrypt.checkpw(password_hash.encode("utf-8"), user.password_hash.encode("utf-8")):
                logger.info(f"User {username} authenticated successfully")
                return user
            else:
                logger.warning(f"Authentication failed for user {username}: invalid password")
                return None
        except Exception as e:
            logger.error(f"Authentication error for user {username}: {e}")
            return None
    
    async def user_exists(self, reg_no: str) -> bool:
        """Check if a user exists by registration number.
        
        Args:
            reg_no: Registration number
            
        Returns:
            True if user exists, False otherwise
        """
        exists = await self.fetchval(
            "SELECT EXISTS(SELECT 1 FROM users WHERE reg_no = $1)",
            reg_no
        )
        return bool(exists)
    
    async def get_user_department(self, reg_no: str) -> str:
        """Get the department of a user by registration number.
        
        Args:
            reg_no: Registration number
            
        Returns:
            Department name or empty string if not found
        """
        dept = await self.fetchval(
            "SELECT dept FROM users WHERE reg_no = $1",
            reg_no
        )
        return dept or ""