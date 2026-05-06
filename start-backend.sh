#!/bin/bash

set -e  # Exit on error

# Configuration
PROJECT_DIR="$(pwd)"
SECRET_KEY_FILE=".webui_secret_key"
ENV_FILE=".env"
CONTAINER_NAME="open-webui-backend"
IMAGE_NAME="open-webui"
PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Header
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}     OpenWebUI Backend Development Server${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Auto-detect public IP
log_info "Detecting public IP address..."
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null)

# Build CORS origins string
CORS_BASE="http://localhost:3000;http://localhost:8080;http://localhost:${PORT}"

if [ ! -z "$PUBLIC_IP" ]; then
    log_info "Detected public IP: ${GREEN}${PUBLIC_IP}${NC}"
    CORS_ORIGINS="${CORS_BASE};http://${PUBLIC_IP}:3000;http://${PUBLIC_IP}:8080;http://${PUBLIC_IP}:${PORT}"
    
    # Also add for frontend port if different
    if [ "${PORT}" != "3000" ]; then
        FRONTEND_PORT=3000
        log_info "Frontend will be accessible at: ${GREEN}http://${PUBLIC_IP}:${FRONTEND_PORT}${NC}"
    fi
else
    log_warn "Could not detect public IP. Using localhost only."
    log_warn "If you need external access, set manually in .env file"
    CORS_ORIGINS="${CORS_BASE}"
fi

# Check if container is already running
if sudo docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_warn "Container ${CONTAINER_NAME} is already running. Stopping it..."
    sudo docker stop ${CONTAINER_NAME}
fi

# Setup environment file
if [ ! -f "$ENV_FILE" ]; then
    log_warn "No .env file found. Creating development defaults..."
    cat > "$ENV_FILE" << EOF
# Development Environment
ENV=dev
HOST=${HOST}
PORT=${PORT}

# CORS is auto-detected from your public IP
# To override auto-detection, uncomment and set your own:
# CORS_ALLOW_ORIGIN=
EOF
    log_info "Created .env file with defaults"
fi

# Check for manual CORS override in .env
if grep -q "^CORS_ALLOW_ORIGIN=" "$ENV_FILE" 2>/dev/null; then
    MANUAL_CORS=$(grep "^CORS_ALLOW_ORIGIN=" "$ENV_FILE" | cut -d'=' -f2-)
    if [ ! -z "$MANUAL_CORS" ]; then
        log_info "Using manual CORS from .env file"
        CORS_ORIGINS="$MANUAL_CORS"
    fi
fi

# Setup secret key
if [ ! -f "$SECRET_KEY_FILE" ]; then
    log_info "Generating secure WEBUI_SECRET_KEY..."
    openssl rand -base64 32 > "$SECRET_KEY_FILE"
    log_info "Secret key saved to ${SECRET_KEY_FILE}"
fi

# Load secret key
WEBUI_SECRET_KEY=$(cat "$SECRET_KEY_FILE")

# Display CORS configuration
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log_info "CORS Origins configured:"
echo "$CORS_ORIGINS" | tr ';' '\n' | while read origin; do
    echo "  • $origin"
done
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Start backend
log_info "Starting backend server..."
log_info "Local URL: ${GREEN}http://localhost:${PORT}${NC}"
if [ ! -z "$PUBLIC_IP" ]; then
    log_info "External URL: ${GREEN}http://${PUBLIC_IP}:${PORT}${NC}"
fi
log_info "API Docs: ${GREEN}http://localhost:${PORT}/docs${NC}"
log_info "Hot-reload: ${GREEN}Enabled${NC} (changes auto-restart server)"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"

# Run Docker container
sudo docker run -it --rm \
  --network ai_default \
  --name ${CONTAINER_NAME} \
  -p ${PORT}:${PORT} \
  -v "${PROJECT_DIR}":/app \
  -v open-webui-data:/app/backend/data \
  -v "${PROJECT_DIR}/${SECRET_KEY_FILE}":/app/backend/${SECRET_KEY_FILE}:ro \
  --env-file "$ENV_FILE" \
  -e WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}" \
  -e HOST="${HOST}" \
  -e PORT="${PORT}" \
  -e CORS_ALLOW_ORIGIN="${CORS_ORIGINS}" \
  ${IMAGE_NAME} \
  bash -c "cd /app/backend && python -m uvicorn open_webui.main:app --host \${HOST} --port \${PORT} --reload --forwarded-allow-ips '*'"