#!/bin/bash

# Script to run Zed with local collaboration server
# This starts both the collab server and Zed pointing to it

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
COLLAB_PORT=8080
ZED_DIR="vendor/zed"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if we're in the right directory
if [ ! -d "$ZED_DIR" ]; then
    echo -e "${RED}Error: Cannot find $ZED_DIR directory${NC}"
    echo "Please run this script from the zed-mobile root directory"
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    # Kill all child processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup EXIT INT TERM

# Check dependencies
echo -e "${GREEN}Checking dependencies...${NC}"

# Check for Docker PostgreSQL first
if [ -f "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env" ]; then
    echo -e "${GREEN}Found Docker PostgreSQL configuration${NC}"
    source "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env"
    # Test connection
    if docker exec zed-postgres pg_isready -U "$POSTGRES_USER" &> /dev/null; then
        echo "✓ Docker PostgreSQL is running"
    else
        echo -e "${YELLOW}Docker PostgreSQL is not running${NC}"
        echo "Starting Docker PostgreSQL..."
        "$SCRIPT_DIR/docker-postgres.sh" start
        source "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env"
    fi
elif command -v pg_isready &> /dev/null; then
    if pg_isready -q; then
        echo "✓ PostgreSQL is running"
        # Set default connection info
        export DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@localhost/zed}"
        export LLM_DATABASE_URL="${LLM_DATABASE_URL:-postgres://postgres:postgres@localhost/zed_llm}"
    else
        echo -e "${RED}Error: PostgreSQL is not running${NC}"
        echo "Please start PostgreSQL or use Docker:"
        echo "  $SCRIPT_DIR/docker-postgres.sh start"
        exit 1
    fi
else
    echo -e "${YELLOW}PostgreSQL not found locally${NC}"
    echo "Starting Docker PostgreSQL..."
    "$SCRIPT_DIR/docker-postgres.sh" start
    source "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env"
fi

# Bootstrap database
echo -e "${GREEN}Setting up database...${NC}"
cd "$ZED_DIR"

# Use .env file if it exists, otherwise create one
if [ ! -f "crates/collab/.env" ]; then
    echo -e "${YELLOW}Creating .env file for collab server...${NC}"
    cat > "crates/collab/.env" << EOF
DATABASE_URL="$DATABASE_URL"
LLM_DATABASE_URL="$LLM_DATABASE_URL"
DATABASE_MAX_CONNECTIONS="5"
API_TOKEN="secret"
SESSION_SECRET="super-secret-session-key"
LIVE_KIT_SERVER="http://localhost:7880"
LIVE_KIT_KEY="devkey"
LIVE_KIT_SECRET="devsecret"
HTTP_PORT="$COLLAB_PORT"
RUST_LOG="info"
LOG_JSON="false"
INVITE_LINK_PREFIX="http://localhost:$COLLAB_PORT"
ARCHIVE_BUCKET=""
EOF
fi

# Create seed.json if it doesn't exist
if [ ! -f "$PROJECT_ROOT/$ZED_DIR/seed.json" ]; then
    echo -e "${YELLOW}Creating default seed.json...${NC}"
    cat > "$PROJECT_ROOT/$ZED_DIR/seed.json" << EOF
{
  "admins": ["admin"],
  "channels": ["general", "random"]
}
EOF
fi

# Run bootstrap if needed
if [ ! -f ".bootstrap_done" ] || [ "$1" == "--reset" ]; then
    echo "Running bootstrap script..."
    ./script/bootstrap
    touch .bootstrap_done
fi

# Start collab server
echo -e "\n${GREEN}Starting collab server on port $COLLAB_PORT...${NC}"

# Make sure we export the required env vars
export DATABASE_URL="$DATABASE_URL"
export LLM_DATABASE_URL="$LLM_DATABASE_URL"

cargo run -p collab -- serve all &
COLLAB_PID=$!

# Wait for collab server to start
echo -n "Waiting for collab server to start"
for i in {1..30}; do
    if curl -s http://localhost:$COLLAB_PORT/healthz > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

if ! curl -s http://localhost:$COLLAB_PORT/healthz > /dev/null 2>&1; then
    echo -e " ${RED}✗${NC}"
    echo -e "${RED}Error: Collab server failed to start${NC}"
    echo "Check the logs above for errors"
    exit 1
fi

# Start Zed with local server configuration
echo -e "\n${GREEN}Starting Zed with local server configuration...${NC}"
echo -e "${YELLOW}Using server: http://localhost:$COLLAB_PORT${NC}"
echo -e "${YELLOW}Impersonating user: admin${NC}"

cd "$PROJECT_ROOT/$ZED_DIR"

# Export environment variables for Zed
export ZED_SERVER_URL="http://localhost:$COLLAB_PORT"
export ZED_ADMIN_API_TOKEN="secret"
export ZED_IMPERSONATE="admin"
export RUST_LOG="client=debug,collab=debug"

# Run Zed
echo -e "\n${GREEN}Launching Zed...${NC}"
cargo run &

ZED_PID=$!

# Show instructions
echo -e "\n${GREEN}=== Local Collaboration Server Running ===${NC}"
echo -e "Collab Server: http://localhost:$COLLAB_PORT"
echo -e "Database: PostgreSQL"
if [ -f "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env" ]; then
    echo -e "  (Docker container: zed-postgres)"
fi
echo -e "Zed is configured to use the local server"
echo -e "\nTo connect from mobile:"
echo -e "  - Android Emulator: http://10.0.2.2:$COLLAB_PORT"
echo -e "  - iOS Simulator: http://localhost:$COLLAB_PORT"
echo -e "  - Physical Device: http://<your-ip>:$COLLAB_PORT"
echo -e "\nAPI Token: secret"
echo -e "User: admin"
echo -e "\n${YELLOW}Press Ctrl+C to stop all services${NC}\n"

# Wait for processes
wait $COLLAB_PID $ZED_PID
