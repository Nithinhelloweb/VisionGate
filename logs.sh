#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda — Universal Log Viewer (Bash)
# Tails logs for all containers or specific service with real-time stream
# ==============================================================================

SERVICE="${1:-all}"
LINES="${2:-100}"

TARGET=""
case "${SERVICE,,}" in
    backend|app)
        TARGET="backend"
        ;;
    cloudflared|tunnel)
        TARGET="cloudflared"
        ;;
    postgres|db)
        TARGET="postgres"
        ;;
    nginx)
        TARGET="nginx"
        ;;
    all|"")
        TARGET=""
        ;;
    *)
        TARGET="${SERVICE}"
        ;;
esac

if docker compose version &>/dev/null; then
    COMPOSE_BASE="docker compose"
else
    COMPOSE_BASE="docker-compose"
fi

if [ -n "$TARGET" ]; then
    echo "Tailing logs for $TARGET (last $LINES lines, streaming)..."
    ${COMPOSE_BASE} logs --tail "$LINES" -f "$TARGET"
else
    echo "Tailing unified logs for all containers (last $LINES lines, streaming)..."
    ${COMPOSE_BASE} logs --tail "$LINES" -f
fi
