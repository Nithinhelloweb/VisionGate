#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Native Linux Nginx Setup Script
# Configures Nginx reverse proxy with Cloudflare Real-IP restoration,
# WebSocket support, 50MB image payload capacity, and proxy to backend:8001.
# Usage: sudo bash 04_setup_nginx.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run with sudo or as root.${NC}"
    echo -e "Usage: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Native Nginx Configuration                          ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# Check for Flutter Web build directory
WEB_BUILD_DIR="${ROOT_DIR}/siet_sync/build/web"
STATIC_CONFIG=""
if [ -d "${WEB_BUILD_DIR}" ]; then
    echo -e "${GREEN}[✓] Detected compiled Flutter Web build at: ${WEB_BUILD_DIR}${NC}"
    STATIC_CONFIG="
        # Serve Flutter Web SPA frontend
        location / {
            root ${WEB_BUILD_DIR};
            try_files \$uri \$uri/ /index.html;
            add_header Cache-Control \"no-cache\";
        }

        # Route API requests to FastAPI backend
        location /api/ {
            proxy_pass http://attenda_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection \"\";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
            proxy_connect_timeout 60s;
            proxy_send_timeout 120s;
            proxy_read_timeout 120s;
        }

        location /docs {
            proxy_pass http://attenda_backend;
            proxy_set_header Host \$host;
        }

        location /openapi.json {
            proxy_pass http://attenda_backend;
            proxy_set_header Host \$host;
        }

        location /health {
            proxy_pass http://attenda_backend;
            proxy_set_header Host \$host;
        }
"
else
    echo -e "${YELLOW}[i] No Flutter Web build directory found. Proxying all traffic directly to FastAPI backend.${NC}"
    STATIC_CONFIG="
        # Proxy all traffic to FastAPI backend
        location / {
            proxy_pass http://attenda_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection \"\";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
            proxy_connect_timeout 60s;
            proxy_send_timeout 120s;
            proxy_read_timeout 120s;
            proxy_buffering on;
            proxy_buffers 8 16k;
            proxy_buffer_size 32k;
        }
"
fi

# Write Nginx configuration
NGINX_CONF="/etc/nginx/sites-available/attenda"
echo -e "\n${CYAN}[1/3] Generating Nginx site configuration at ${NGINX_CONF}...${NC}"

cat << 'EOF' > "${NGINX_CONF}"
# Attenda / VisionGate Native Production Nginx Configuration
upstream attenda_backend {
    server 127.0.0.1:8001;
    keepalive 32;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name attenda.srishakthicgpa.in _;

    # Cloudflare Real IP Restoration
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 2400:cb00::/32;
    set_real_ip_from 2606:4700::/32;
    set_real_ip_from 2803:f800::/32;
    set_real_ip_from 2405:b500::/32;
    set_real_ip_from 2405:8100::/32;
    set_real_ip_from 2a06:98c0::/29;
    set_real_ip_from 2c0f:f248::/32;
    set_real_ip_from 127.0.0.1;
    real_ip_header CF-Connecting-IP;
    real_ip_recursive on;

    # Payload limits for facial biometric images
    client_max_body_size 50M;
    client_body_buffer_size 10M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # Security Headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Frame-Options SAMEORIGIN always;

    # WebSocket Support
    location /ws/ {
        proxy_pass http://attenda_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header CF-Connecting-IP $http_cf_connecting_ip;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # Internal healthcheck endpoint
    location /healthz {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
EOF

# Append location block based on static presence
cat << EOF >> "${NGINX_CONF}"
${STATIC_CONFIG}
}
EOF

# Enable site
echo -e "\n${CYAN}[2/3] Enabling Nginx configuration...${NC}"
ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/attenda
rm -f /etc/nginx/sites-enabled/default

# Test and reload
echo -e "\n${CYAN}[3/3] Testing Nginx syntax and reloading...${NC}"
nginx -t
systemctl reload nginx
echo -e "${GREEN}[✓] Nginx is configured and running on port 80!${NC}"
echo -e "\nNext step: sudo bash 05_setup_cloudflared.sh"
