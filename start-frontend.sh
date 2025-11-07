#!/bin/bash

# Colors for output
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
echo -e "${BLUE}     OpenWebUI Frontend Development Server${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check if backend is running
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    log_warn "Backend doesn't seem to be running at http://localhost:8080"
    log_warn "Make sure to start the backend first with ./start-backend.sh"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    log_warn "node_modules not found. Installing dependencies..."
    npm install --legacy-peer-deps
    if [ $? -ne 0 ]; then
        log_error "Failed to install dependencies"
        exit 1
    fi
fi

# Check if another dev server is running on port 3000
if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    log_error "Port 3000 is already in use. Is another server running?"
    exit 1
fi

# Start frontend
log_info "Starting frontend server on port 3000 (your configured port)..."
log_info "URL: http://localhost:3000"
log_info "Backend API: http://localhost:8080"
log_info "Hot-reload: Enabled (instant updates on save)"
log_info "Cloudflare tunnel: Should work with your existing setup"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"

# Set backend URL for development
export PUBLIC_API_BASE_URL="http://localhost:8080"
export VITE_API_BASE_URL="http://localhost:8080"

# Run the dev server on port 3000
npm run dev -- --host 0.0.0.0 --port 3000