#!/bin/bash

# Simple script to run Zed with local collaboration server
# Uses the official zed-local script approach

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ZED_DIR="${PROJECT_ROOT}/vendor/zed"
TMP_DIR="${PROJECT_ROOT}/tmp"

. "${SCRIPT_DIR}/.env"


echo "Script dir: ${SCRIPT_DIR}"
echo "Project root: ${PROJECT_ROOT}"
echo "Zed dir: ${ZED_DIR}"
echo "Tmp dir: ${TMP_DIR}"

# Check if we're in the right directory
if [ ! -d "$ZED_DIR" ]; then
    echo -e "${RED}Error: Cannot find $ZED_DIR directory${NC}"
    echo "Please run this script from the zed-mobile root directory"
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup EXIT INT TERM

# Check PostgreSQL
echo -e "${GREEN}Checking PostgreSQL...${NC}"
if [ -f "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env" ]; then
    echo -e "${GREEN}Found Docker PostgreSQL configuration${NC}"
    source "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env"
    if ! docker exec zed-postgres pg_isready -U "$POSTGRES_USER" &> /dev/null; then
        echo -e "${YELLOW}Starting Docker PostgreSQL...${NC}"
        "$SCRIPT_DIR/docker-postgres.sh" start
        source "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env"
    fi
elif command -v pg_isready &> /dev/null && pg_isready -q; then
    echo "✓ PostgreSQL is running"
    export DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@localhost/zed}"
    export LLM_DATABASE_URL="${LLM_DATABASE_URL:-postgres://postgres:postgres@localhost/zed_llm}"
else
    echo -e "${YELLOW}Starting Docker PostgreSQL...${NC}"
    "$SCRIPT_DIR/docker-postgres.sh" start
    source "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env"
fi

# Bootstrap if needed
echo -e "${GREEN}Setting up database...${NC}"
cd "$ZED_DIR"
if [ ! -f "${TMP_DIR}/.bootstrap_done" ] || [ "$1" == "--reset" ]; then
    echo "Running bootstrap script..."
    ./script/bootstrap
    touch "${TMP_DIR}/.bootstrap_done"
fi

# Clean up previous data directory
rm -rf "$TMP_DIR/zed-data"
mkdir -p "$TMP_DIR"

# Start collab server
echo -e "\n${GREEN}Starting collab server...${NC}"
export DATABASE_URL="$DATABASE_URL"
export LLM_DATABASE_URL="$LLM_DATABASE_URL"
export HTTP_PORT=3000

# killall collab
# sleep 2
RUST_LOG=info cargo run -p collab -- serve all >  "$TMP_DIR/collab.log" 2>&1 &
COLLAB_PID=$!

# Wait for collab server to start
echo -n "Waiting for collab server"
for i in {1..30}; do
    if curl -s ${ZED_HEALTH_URL} > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

if ! curl -s ${ZED_HEALTH_URL} > /dev/null 2>&1; then
    echo -e " ${RED}✗${NC}"
    echo -e "${RED}Error: Collab server failed to start${NC}"
    echo "Check logs: tail -f $TMP_DIR/collab.log"
    exit 1
fi

# Start Zed instances
echo -e "\n${GREEN}Starting Zed instances...${NC}"
./script/zed-local --data-dir "$TMP_DIR/zed-data" -1 &
ZED_PID=$!

# Show instructions
echo -e "\n${GREEN}=== Local Collaboration Server Running ===${NC}"
echo -e "Collab server: http://localhost:3000"
echo -e "RPC server: http://localhost:8080/rpc"
echo -e "Database: PostgreSQL"
if [ -f "$PROJECT_ROOT/tmp/postgres-docker/connection-info.env" ]; then
    echo -e "  (Docker container: zed-postgres)"
fi
echo -e "\nTwo Zed instances should be starting with local server configuration"
echo -e "\nFor mobile development:"
echo -e "  - Android Emulator: http://10.0.2.2:3000"
echo -e "  - iOS Simulator: http://localhost:3000"
echo -e "  - Physical Device: http://<your-ip>:3000"
echo -e "\nLogs: tail -f $TMP_DIR/collab.log"
echo -e "\n${YELLOW}Press Ctrl+C to stop all services${NC}\n"

# Wait for processes
wait $COLLAB_PID $ZED_PID
