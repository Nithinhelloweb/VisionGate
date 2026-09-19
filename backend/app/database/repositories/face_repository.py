"""Face repository for face embedding database operations."""
import logging
import struct
from typing import List, Optional, Tuple
import asyncpg
from ..connection import db_pool

logger = logging.getLogger(__name__)


FaceMatch = Tuple[str, str, str, str, float]  # (reg_no, name, dept, role, similarity)


class FaceRepository:
    """Repository for face embedding and pgvector similarity search operations."""
    
    @staticmethod
    def _bytes_to_vector_str(embedding: bytes) -> str:
        """Convert 512-dim embedding bytes to pgvector format string.
        
        Args:
            embedding: 512 * 4 = 2048 bytes (float32 array)
            
        Returns:
            pgvector format string like '[0.1,0.2,...,0.5]'
        """
        vector = struct.unpack("<512f", embedding)
        return "[" + ",".join(str(f) for f in vector) + "]"
    
    @staticmethod
    def _vector_str_to_bytes(vec_str: str) -> bytes:
        """Convert pgvector format string back to bytes.
        
        Args:
            vec_str: pgvector format string
            
        Returns:
            2048 bytes (512-dim float32 array)
        """
        vec_list = [float(x) for x in vec_str.strip("[]").split(",") if x.strip()]
        return struct.pack("<512f", *vec_list)
    
    async def search_similar_faces(
        self,
        query_embedding: bytes,
        limit: int = 10,
        threshold: float = 0.7,
        exclude_reg_no: str | None = None
    ) -> List[FaceMatch]:
        """Search for similar faces using pgvector cosine similarity.
        
        Cosine distance (operator <=>) ranges from 0 to 2.
        Cosine similarity = 1 - cosine_distance, so it ranges from -1 to 1.
        With normalized embeddings (unit vectors), cosine_distance ranges 0-2
        and cosine_similarity ranges -1 to 1, but typically we expect 0-1.
        
        The threshold parameter is cosine similarity (0.7 = 70% similar).
        Matches with similarity > threshold are returned.
        
        Args:
            query_embedding: Query face embedding as bytes
            limit: Maximum number of results to return
            threshold: Minimum cosine similarity threshold (0.0-1.0)
            exclude_reg_no: Optional reg_no to exclude from results
            
        Returns:
            List of FaceMatch tuples (reg_no, name, dept, role, similarity)
            sorted by highest similarity first
        """
        vector_str = self._bytes_to_vector_str(query_embedding)
        
        query = """
            SELECT 
                u.reg_no,
                u.name,
                u.dept,
                u.role,
                1 - (u.face_embedding <=> $1::vector) as similarity
            FROM users u
            WHERE u.face_embedding IS NOT NULL
            AND 1 - (u.face_embedding <=> $1::vector) > $2
        """
        params = [vector_str, threshold]
        
        if exclude_reg_no is not None:
            query += " AND u.reg_no != $" + str(len(params) + 1)
            params.append(exclude_reg_no)
        
        query += " ORDER BY u.face_embedding <=> $1::vector LIMIT $" + str(len(params) + 1)
        params.append(limit)
        
        async with db_pool.pool.acquire() as conn:
            rows = await conn.fetch(query, *params)
        
        results: List[FaceMatch] = []
        for row in rows:
            results.append((
                row["reg_no"],
                row["name"],
                row["dept"],
                row["role"],
                float(row["similarity"])
            ))
        return results