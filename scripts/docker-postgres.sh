#!/bin/bash

# Script to run PostgreSQL in Docker for Zed local collaboration
# Stores connection information in tmp/postgres-docker/

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="zed-postgres"
POSTGRES_VERSION="15"
POSTGRES_PORT="5432"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres"
POSTGRES_DB="zed"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/tmp/postgres-docker"
CONN_INFO_FILE="$DATA_DIR/connection-info.env"

# Create data directory
mkdir -p "$DATA_DIR"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi

# Function to start PostgreSQL
start_postgres() {
    echo -e "${GREEN}Starting PostgreSQL in Docker...${NC}"

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        # Check if it's running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo -e "${YELLOW}PostgreSQL container is already running${NC}"
        else
            echo "Starting existing PostgreSQL container..."
            docker start "$CONTAINER_NAME"
        fi
    else
        echo "Creating new PostgreSQL container..."
        docker run -d \
            --name "$CONTAINER_NAME" \
            -e POSTGRES_USER="$POSTGRES_USER" \
            -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
            -e POSTGRES_DB="$POSTGRES_DB" \
            -p "$POSTGRES_PORT:5432" \
            -v "$DATA_DIR/pgdata:/var/lib/postgresql/data" \
            "postgres:$POSTGRES_VERSION"
    fi

    # Wait for PostgreSQL to be ready
    echo -n "Waiting for PostgreSQL to be ready"
    for i in {1..30}; do
        if docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" &> /dev/null; then
            echo -e " ${GREEN}✓${NC}"
            break
        fi
        echo -n "."
        sleep 1
    done

    if ! docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" &> /dev/null; then
        echo -e " ${RED}✗${NC}"
        echo -e "${RED}Error: PostgreSQL failed to start${NC}"
        exit 1
    fi

    # Create additional databases if needed
    echo "Setting up databases..."
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -c "CREATE DATABASE zed_llm;" 2>/dev/null || true

    # Write connection info
    cat > "$CONN_INFO_FILE" << EOF
# PostgreSQL connection information
export DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/$POSTGRES_DB"
export LLM_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/zed_llm"
export POSTGRES_USER="$POSTGRES_USER"
export POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
export POSTGRES_HOST="localhost"
export POSTGRES_PORT="$POSTGRES_PORT"
export POSTGRES_DB="$POSTGRES_DB"
EOF

    echo -e "${GREEN}PostgreSQL is running!${NC}"
    echo -e "Connection info saved to: ${CONN_INFO_FILE}"
    echo -e "\nConnection details:"
    echo -e "  Host: localhost"
    echo -e "  Port: $POSTGRES_PORT"
    echo -e "  User: $POSTGRES_USER"
    echo -e "  Password: $POSTGRES_PASSWORD"
    echo -e "  Database: $POSTGRES_DB"
    echo -e "\nConnection URL:"
    echo -e "  postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/$POSTGRES_DB"
}

# Function to stop PostgreSQL
stop_postgres() {
    echo -e "${YELLOW}Stopping PostgreSQL container...${NC}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "$CONTAINER_NAME"
        echo -e "${GREEN}PostgreSQL stopped${NC}"
    else
        echo "PostgreSQL container is not running"
    fi
}

# Function to remove PostgreSQL container and data
remove_postgres() {
    echo -e "${RED}Removing PostgreSQL container and data...${NC}"

    # Stop container if running
    stop_postgres

    # Remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker rm "$CONTAINER_NAME"
    fi

    # Ask before removing data
    read -p "Remove PostgreSQL data directory? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR"
        echo -e "${GREEN}PostgreSQL data removed${NC}"
    fi
}

# Function to show status
status_postgres() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${GREEN}PostgreSQL is running${NC}"
        docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

        if [ -f "$CONN_INFO_FILE" ]; then
            echo -e "\nConnection info file: $CONN_INFO_FILE"
            echo "To load connection info: source $CONN_INFO_FILE"
        fi
    else
        echo -e "${YELLOW}PostgreSQL is not running${NC}"
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "Container exists but is stopped. Use 'start' to start it."
        else
            echo "No PostgreSQL container found. Use 'start' to create one."
        fi
    fi
}

# Function to show logs
logs_postgres() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker logs "$CONTAINER_NAME" "$@"
    else
        echo -e "${RED}No PostgreSQL container found${NC}"
    fi
}

# Main script logic
case "${1:-start}" in
    start)
        start_postgres
        ;;
    stop)
        stop_postgres
        ;;
    restart)
        stop_postgres
        start_postgres
        ;;
    remove|rm)
        remove_postgres
        ;;
    status)
        status_postgres
        ;;
    logs)
        shift
        logs_postgres "$@"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|remove|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start    - Start PostgreSQL in Docker"
        echo "  stop     - Stop PostgreSQL container"
        echo "  restart  - Restart PostgreSQL container"
        echo "  remove   - Remove container and optionally data"
        echo "  status   - Show container status"
        echo "  logs     - Show container logs"
        echo ""
        echo "Connection info is saved to: $DATA_DIR/connection-info.env"
        exit 1
        ;;
esac
