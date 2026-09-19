import logging
import sys
import json
from datetime import datetime
from typing import Any
from contextvars import ContextVar

try:
    import structlog
    STRUCTLOG_AVAILABLE = True
except ImportError:
    STRUCTLOG_AVAILABLE = False

from .config import settings


request_id_var: ContextVar[str] = ContextVar("request_id", default="")
user_reg_no_var: ContextVar[str] = ContextVar("user_reg_no", default="")


class RequestIDFilter(logging.Filter):
    """Logging filter to add request ID and user registration number to log records."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get("")
        record.user_reg_no = user_reg_no_var.get("")
        return True


class JSONFormatter(logging.Formatter):
    """JSON formatter for structured logging."""

    def format(self, record: logging.LogRecord) -> str:
        data = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "event": record.getMessage(),
            "module": record.module,
            "user_reg_no": getattr(record, "user_reg_no", ""),
            "request_id": getattr(record, "request_id", ""),
        }

        if record.exc_info:
            data["exception"] = self.formatException(record.exc_info)

        return json.dumps(data)


class ColoredFormatter(logging.Formatter):
    """Colored console formatter for development."""

    COLORS = {
        "DEBUG": "\033[36m",
        "INFO": "\033[32m",
        "WARNING": "\033[33m",
        "ERROR": "\033[31m",
        "CRITICAL": "\033[35m",
    }
    RESET = "\033[0m"

    def format(self, record: logging.LogRecord) -> str:
        color = self.COLORS.get(record.levelname, "")
        request_id = getattr(record, "request_id", "")
        user_reg_no = getattr(record, "user_reg_no", "")

        base = f"{color}{record.levelname:8}\033[0m {record.module}:{record.lineno} | {record.getMessage()}"
        if request_id:
            base += f" | request_id={request_id}"
        if user_reg_no:
            base += f" | user={user_reg_no}"
        return base


def setup_logging() -> None:
    """Configure application logging based on environment."""
    log_level = getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO)

    if STRUCTLOG_AVAILABLE:
        _setup_structlog(log_level)
    else:
        _setup_standard_logging(log_level)


def _setup_structlog(log_level: int) -> None:
    """Setup structlog for structured logging."""
    processors = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
    ]

    if settings.is_production:
        processors.extend([
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ])
    else:
        processors.extend([
            structlog.dev.ConsoleRenderer(colors=True),
        ])

    structlog.configure(
        processors=processors,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    logging.basicConfig(
        level=log_level,
        format="%(message)s",
        handlers=[
            logging.StreamHandler(sys.stdout),
        ],
    )


def _setup_standard_logging(log_level: int) -> None:
    """Setup standard Python logging with JSON/colored output."""
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)

    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)

    info_handler = logging.StreamHandler(sys.stdout)
    info_handler.setLevel(log_level)
    info_handler.addFilter(RequestIDFilter())

    error_handler = logging.StreamHandler(sys.stderr)
    error_handler.setLevel(logging.ERROR)
    error_handler.addFilter(RequestIDFilter())

    if settings.is_production:
        info_handler.setFormatter(JSONFormatter())
        error_handler.setFormatter(JSONFormatter())
    else:
        info_handler.setFormatter(ColoredFormatter())
        error_handler.setFormatter(ColoredFormatter())

    root_logger.addHandler(info_handler)
    root_logger.addHandler(error_handler)


def get_logger(name: str) -> logging.Logger:
    """Get a logger instance."""
    return logging.getLogger(name)


def bind_request_id(request_id: str) -> None:
    """Bind request ID to context for logging."""
    request_id_var.set(request_id)


def bind_user_reg_no(user_reg_no: str) -> None:
    """Bind user registration number to context for logging."""
    user_reg_no_var.set(user_reg_no)


def clear_context() -> None:
    """Clear logging context variables."""
    request_id_var.set("")
    user_reg_no_var.set("")