"""Settings repository for application configuration and key-value storage."""
import json
import logging
from typing import Any, Dict, Optional, List
import asyncpg
from ..connection import db_pool
from .base_repository import BaseRepository

logger = logging.getLogger(__name__)


class SettingsRepository(BaseRepository):
    """Repository for persistent application settings and key-value storage."""

    async def get_all_settings(self) -> Dict[str, Any]:
        """Get all settings from the key-value store.
        
        Returns:
            Dict mapping setting keys to their values
        """
        rows = await self.fetch(
            "SELECT key, value, data_type FROM app_settings WHERE is_active = TRUE"
        )
        settings: Dict[str, Any] = {}
        for row in rows:
            key = row["key"]
            value_str = row["value"]
            data_type = row["data_type"]
            settings[key] = self._deserialize_value(value_str, data_type)
        return settings
    
    async def get_setting(self, key: str, default: Any = None) -> Any:
        """Get a single setting value by key.
        
        Args:
            key: Setting key
            default: Default value if key not found
            
        Returns:
            Setting value or default
        """
        row = await self.fetchrow(
            "SELECT value, data_type FROM app_settings WHERE key = $1 AND is_active = TRUE",
            key
        )
        if row:
            return self._deserialize_value(row["value"], row["data_type"])
        return default
    
    async def update_setting(self, key: str, value: Any) -> None:
        """Update or create a setting.
        
        Args:
            key: Setting key
            value: Setting value (can be any JSON-serializable type)
        """
        value_str, data_type = self._serialize_value(value)
        
        await self.execute(
            """
            INSERT INTO app_settings (key, value, data_type)
            VALUES ($1, $2, $3)
            ON CONFLICT (key) DO UPDATE SET
                value = EXCLUDED.value,
                data_type = EXCLUDED.data_type,
                updated_at = NOW()
            """,
            key, value_str, data_type
        )
        logger.info(f"Updated setting: {key} = {value}")
    
    async def delete_setting(self, key: str) -> bool:
        """Soft-delete a setting.
        
        Args:
            key: Setting key to delete
            
        Returns:
            True if deleted, False if not found
        """
        result = await self.execute(
            "UPDATE app_settings SET is_active = FALSE WHERE key = $1",
            key
        )
        deleted = result is not None and "UPDATE 1" in result
        if deleted:
            logger.info(f"Deleted setting: {key}")
        return deleted
    
    async def bulk_update_settings(self, settings: Dict[str, Any]) -> None:
        """Bulk update multiple settings in a transaction.
        
        Args:
            settings: Dict of key-value pairs to update
        """
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                for key, value in settings.items():
                    value_str, data_type = self._serialize_value(value)
                    await conn.execute(
                        """
                        INSERT INTO app_settings (key, value, data_type)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (key) DO UPDATE SET
                            value = EXCLUDED.value,
                            data_type = EXCLUDED.data_type,
                            updated_at = NOW()
                        """,
                        key, value_str, data_type
                    )
        logger.info(f"Bulk updated {len(settings)} settings")
    
    async def get_settings_by_prefix(self, prefix: str) -> Dict[str, Any]:
        """Get all settings with a given key prefix.
        
        Args:
            prefix: Key prefix (e.g., 'app.')
            
        Returns:
            Dict of matching settings with prefix stripped
        """
        rows = await self.fetch(
            "SELECT key, value, data_type FROM app_settings WHERE key LIKE $1 AND is_active = TRUE",
            prefix + "%"
        )
        settings: Dict[str, Any] = {}
        for row in rows:
            key = row["key"][len(prefix):]  # Strip prefix
            settings[key] = self._deserialize_value(row["value"], row["data_type"])
        return settings
    
    async def get_setting_history(self, key: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Get change history for a specific setting.
        
        Args:
            key: Setting key
            limit: Maximum number of history records to return
            
        Returns:
            List of historical setting values
        """
        rows = await self.fetch(
            """
            SELECT value, data_type, updated_at, updated_by
            FROM app_settings_history
            WHERE key = $1
            ORDER BY updated_at DESC
            LIMIT $2
            """,
            key, limit
        )
        history = []
        for row in rows:
            history.append({
                "value": self._deserialize_value(row["value"], row["data_type"]),
                "updated_at": row["updated_at"],
                "updated_by": row["updated_by"]
            })
        return history
    
    @staticmethod
    def _serialize_value(value: Any) -> tuple[str, str]:
        """Serialize a value to string and determine its data type.
        
        Args:
            value: Value to serialize
            
        Returns:
            Tuple of (string_value, data_type)
        """
        if value is None:
            return "", "null"
        if isinstance(value, bool):
            return "true" if value else "false", "bool"
        if isinstance(value, int):
            return str(value), "int"
        if isinstance(value, float):
            return str(value), "float"
        if isinstance(value, (list, dict)):
            return json.dumps(value), "json"
        return str(value), "str"
    
    @staticmethod
    def _deserialize_value(value_str: str, data_type: str) -> Any:
        """Deserialize a value string based on its data type.
        
        Args:
            value_str: String representation of the value
            data_type: Data type identifier
            
        Returns:
            Deserialized value
        """
        if data_type == "null":
            return None
        if data_type == "bool":
            return value_str.lower() == "true"
        if data_type == "int":
            return int(value_str)
        if data_type == "float":
            return float(value_str)
        if data_type == "json":
            return json.loads(value_str)
        return value_str