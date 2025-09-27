#!/bin/bash

# Anoma Network and Client Stop Script
# This script stops all Anoma services (3 nodes and 1 client)

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

# Function to check if a process is running
is_process_running() {
    local pid=$1
    if kill -0 "$pid" 2>/dev/null; then
        return 0  # Process is running
    else
        return 1  # Process is not running
    fi
}

# Function to stop a process gracefully
stop_process() {
    local pid=$1
    local name=$2
    local timeout=${3:-10}
    
    if is_process_running "$pid"; then
        print_status "Stopping $name (PID: $pid)..."
        
        # Try graceful shutdown first
        kill -TERM "$pid" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local count=0
        while [ $count -lt $timeout ] && is_process_running "$pid"; do
            sleep 1
            count=$((count + 1))
        done
        
        # Force kill if still running
        if is_process_running "$pid"; then
            print_warning "$name didn't stop gracefully, force killing..."
            kill -KILL "$pid" 2>/dev/null || true
            sleep 1
        fi
        
        # Check if stopped
        if is_process_running "$pid"; then
            print_error "Failed to stop $name (PID: $pid)"
            return 1
        else
            print_success "$name stopped successfully"
            return 0
        fi
    else
        print_warning "$name (PID: $pid) is not running"
        return 0
    fi
}

# Function to stop services by PID files
stop_services_by_pid() {
    local stopped_any=false
    
    # Stop client
    if [ -f "$PID_DIR/client.pid" ]; then
        local client_pid=$(cat "$PID_DIR/client.pid")
        if stop_process "$client_pid" "Client"; then
            stopped_any=true
        fi
        rm -f "$PID_DIR/client.pid"
    fi
    
    # Stop network
    if [ -f "$PID_DIR/network.pid" ]; then
        local network_pid=$(cat "$PID_DIR/network.pid")
        if stop_process "$network_pid" "Network"; then
            stopped_any=true
        fi
        rm -f "$PID_DIR/network.pid"
    fi
    
    if [ "$stopped_any" = false ]; then
        print_warning "No services found running from PID files"
    fi
}

# Function to force stop all beam.smp processes
force_stop_beam_processes() {
    print_status "Checking for any remaining beam.smp processes..."
    
    local beam_pids=$(pgrep -f "beam.smp" 2>/dev/null || true)
    if [ -n "$beam_pids" ]; then
        print_warning "Found remaining beam.smp processes, force stopping them..."
        echo "$beam_pids" | while read -r pid; do
            if [ -n "$pid" ]; then
                print_status "Force killing beam.smp process (PID: $pid)"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
    else
        print_success "No remaining beam.smp processes found"
    fi
}

# Function to free up ports
free_ports() {
    print_status "Checking and freeing up ports..."
    
    local ports_freed=false
    for port in 50051 50052 50053 4001; do
        local port_pids=$(lsof -ti :$port 2>/dev/null || true)
        if [ -n "$port_pids" ]; then
            print_warning "Port $port is still in use, freeing it..."
            echo "$port_pids" | xargs -r kill -9 2>/dev/null || true
            ports_freed=true
        fi
    done
    
    if [ "$ports_freed" = true ]; then
        sleep 1
        print_success "Ports freed"
    else
        print_success "All ports are free"
    fi
}

# Function to clean up files
cleanup_files() {
    print_status "Cleaning up temporary files..."
    
    # Remove PID files
    rm -f "$PID_DIR"/*.pid
    
    # Optionally clean up log files (commented out to preserve logs)
    # rm -f "$LOG_DIR"/*.log
    
    print_success "Cleanup completed"
}

# Function to verify all services are stopped
verify_stopped() {
    print_status "Verifying all services are stopped..."
    
    local all_stopped=true
    
    # Check for beam.smp processes
    if pgrep -f "beam.smp" > /dev/null 2>&1; then
        print_error "Some beam.smp processes are still running"
        all_stopped=false
    fi
    
    # Check ports
    for port in 50051 50052 50053 4001; do
        if lsof -ti :$port > /dev/null 2>&1; then
            print_error "Port $port is still in use"
            all_stopped=false
        fi
    done
    
    if [ "$all_stopped" = true ]; then
        print_success "All services stopped successfully"
        return 0
    else
        print_error "Some services may still be running"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}==============================${NC}"
    echo -e "${BLUE}  Anoma Network Stop Script   ${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo
    
    print_status "Stopping Anoma services..."
    echo
    
    # Stop services by PID files
    stop_services_by_pid
    
    echo
    
    # Force stop any remaining beam processes
    force_stop_beam_processes
    
    echo
    
    # Free up ports
    free_ports
    
    echo
    
    # Clean up files
    cleanup_files
    
    echo
    
    # Verify everything is stopped
    if verify_stopped; then
        echo
        print_success "🛑 All Anoma services have been stopped successfully!"
        echo -e "${BLUE}Logs are preserved in:${NC} $LOG_DIR/"
        echo -e "${YELLOW}To start services again, run:${NC} ./start_anoma.sh"
    else
        echo
        print_error "Some services may still be running. Please check manually."
        exit 1
    fi
}

# Run main function
main "$@"