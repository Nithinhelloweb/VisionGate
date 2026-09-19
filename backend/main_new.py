"""VisionGate - Automated Face Attendance System

Main application entry point using modular async architecture.
"""
import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.logging import setup_logging
from app.database.connection import db_pool
from app.api.routes import api_router

# Setup logging
setup_logging()
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan context manager for startup/shutdown events."""
    # Startup
    logger.info("Starting VisionGate application...")

    # Initialize database pool
    await db_pool.init_pool()

    # Initialize face recognition system (will be moved to service)
    logger.info("Application startup complete")

    yield

    # Shutdown
    logger.info("Shutting down VisionGate application...")
    await db_pool.close()
    logger.info("Application shutdown complete")


# Create FastAPI app with lifespan
app = FastAPI(
    title="VisionGate - Automated Face Attendance System",
    description="Secure face recognition based attendance system with real-time verification",
    version="2.0.0",
    lifespan=lifespan,
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure based on your frontend domains in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(api_router, prefix="/api")


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "version": "2.0.0"}


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": "VisionGate - Automated Face Attendance System",
        "version": "2.0.0",
        "status": "running"
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )