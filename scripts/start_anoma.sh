#!/bin/bash

# Anoma Network and Client Startup Script
# This script starts 3 nodes and 1 client for the Anoma network

set -e  # Exit on any error

# Print current Anoma directory path
echo "🏠 当前Anoma目录路径: $(pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_DIR="$SCRIPT_DIR/pids"
LOG_DIR="$SCRIPT_DIR/logs"

# Create directories if they don't exist
mkdir -p "$PID_DIR"
mkdir -p "$LOG_DIR"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -ti :$port > /dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to wait for port to be available
wait_for_port() {
    local port=$1
    local timeout=${2:-30}
    local count=0
    
    print_status "Waiting for port $port to be available..."
    while [ $count -lt $timeout ]; do
        if check_port $port; then
            print_success "Port $port is now available"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    print_error "Timeout waiting for port $port"
    return 1
}

# Function to stop existing processes
stop_existing_processes() {
    print_status "Stopping any existing Anoma processes..."
    
    # Kill any existing beam.smp processes
    if pgrep -f "beam.smp" > /dev/null; then
        print_warning "Found existing beam.smp processes, stopping them..."
        pkill -f "beam.smp" || true
        sleep 2
    fi
    
    # Clean up any remaining processes on our ports
    for port in 50051 50052 50053 4001; do
        if check_port $port; then
            print_warning "Port $port is in use, attempting to free it..."
            lsof -ti :$port | xargs -r kill -9 || true
        fi
    done
    
    # Clean up old PID files
    rm -f "$PID_DIR"/*.pid
    
    print_success "Cleanup completed"
}

# Function to start the network (3 nodes)
start_network() {
    print_status "Starting Anoma network (3 nodes)..."
    
    cd "$SCRIPT_DIR"
    
    # Start network in background
    nohup mix run start_network_and_client.exs > "$LOG_DIR/network.log" 2>&1 &
    local network_pid=$!
    echo $network_pid > "$PID_DIR/network.pid"
    
    print_status "Network starting with PID: $network_pid"
    
    # Wait for all gRPC ports to be available
    print_status "Waiting for network nodes to start..."
    sleep 5  # Give it some time to start
    
    for port in 50051 50052 50053; do
        if ! wait_for_port $port 30; then
            print_error "Failed to start network - port $port not available"
            return 1
        fi
    done
    
    print_success "Network started successfully (ports 50051, 50052, 50053)"
    return 0
}

# Function to start the client
start_client() {
    print_status "Starting Anoma gRPC client..."
    
    cd "$SCRIPT_DIR"
    
    # Start client in background
    nohup elixir start_grpc_client_only.exs > "$LOG_DIR/client.log" 2>&1 &
    local client_pid=$!
    echo $client_pid > "$PID_DIR/client.pid"
    
    print_status "Client starting with PID: $client_pid"
    
    # Give client time to connect
    sleep 3
    
    # Check if client is still running
    if kill -0 $client_pid 2>/dev/null; then
        print_success "Client started successfully"
        return 0
    else
        print_error "Client failed to start"
        return 1
    fi
}

# Function to check status
check_status() {
    print_status "Checking Anoma services status..."
    
    # Check network
    if [ -f "$PID_DIR/network.pid" ]; then
        local network_pid=$(cat "$PID_DIR/network.pid")
        if kill -0 $network_pid 2>/dev/null; then
            print_success "Network is running (PID: $network_pid)"
            
            # Check gRPC ports
            for port in 50051 50052 50053; do
                if check_port $port; then
                    echo -e "  ${GREEN}✓${NC} Node on port $port is active"
                else
                    echo -e "  ${RED}✗${NC} Node on port $port is not responding"
                fi
            done
        else
            print_warning "Network PID file exists but process is not running"
        fi
    else
        print_warning "Network is not running"
    fi
    
    # Check client
    if [ -f "$PID_DIR/client.pid" ]; then
        local client_pid=$(cat "$PID_DIR/client.pid")
        if kill -0 $client_pid 2>/dev/null; then
            print_success "Client is running (PID: $client_pid)"
        else
            print_warning "Client PID file exists but process is not running"
        fi
    else
        print_warning "Client is not running"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Anoma Network Startup Script  ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    
    # Stop any existing processes
    stop_existing_processes
    
    echo
    print_status "Starting Anoma services..."
    echo
    
    # Start network
    if start_network; then
        echo
        # Start client
        if start_client; then
            echo
            print_success "All services started successfully!"
            echo
            check_status
            echo
            echo -e "${GREEN}🎉 Anoma network is ready!${NC}"
            echo -e "${BLUE}Network:${NC} 3 nodes running on ports 50051, 50052, 50053"
            echo -e "${BLUE}Client:${NC} gRPC client connected to node 1"
            echo
            echo -e "${YELLOW}To stop all services, run:${NC} ./stop_anoma.sh"
            echo -e "${YELLOW}To check status, run:${NC} ./status_anoma.sh"
            echo -e "${YELLOW}Logs are available in:${NC} $LOG_DIR/"
        else
            print_error "Failed to start client"
            exit 1
        fi
    else
        print_error "Failed to start network"
        exit 1
    fi
}

# Run main function
main "$@"