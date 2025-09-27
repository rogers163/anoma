#!/bin/bash

# Anoma Network and Client Status Script
# This script checks the status of all Anoma services

set -e  # Exit on any error

# Print current Anoma directory path
echo "🏠 当前Anoma目录路径: $(pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_DIR="$SCRIPT_DIR/pids"
LOG_DIR="$SCRIPT_DIR/logs"

# Function to print colored output
print_header() {
    echo -e "${CYAN}$1${NC}"
}

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

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -ti :$port > /dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to get process info for a port
get_port_process_info() {
    local port=$1
    lsof -ti :$port 2>/dev/null | head -1
}

# Function to format uptime
format_uptime() {
    local pid=$1
    if [ -n "$pid" ] && is_process_running "$pid"; then
        local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | xargs)
        if [ -n "$start_time" ]; then
            echo "Started: $start_time"
        else
            echo "Started: Unknown"
        fi
    else
        echo "Not running"
    fi
}

# Function to get memory usage
get_memory_usage() {
    local pid=$1
    if [ -n "$pid" ] && is_process_running "$pid"; then
        local mem=$(ps -o rss= -p "$pid" 2>/dev/null | xargs)
        if [ -n "$mem" ]; then
            local mem_mb=$((mem / 1024))
            echo "${mem_mb}MB"
        else
            echo "Unknown"
        fi
    else
        echo "N/A"
    fi
}

# Function to check network status
check_network_status() {
    print_header "📡 Network Status (3 Nodes)"
    echo "================================"
    
    local network_running=false
    local network_pid=""
    
    # Check PID file
    if [ -f "$PID_DIR/network.pid" ]; then
        network_pid=$(cat "$PID_DIR/network.pid")
        if is_process_running "$network_pid"; then
            network_running=true
            echo -e "  ${GREEN}✓${NC} Network process is running (PID: $network_pid)"
            echo -e "    Memory usage: $(get_memory_usage $network_pid)"
            echo -e "    $(format_uptime $network_pid)"
        else
            echo -e "  ${RED}✗${NC} Network PID file exists but process is not running"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Network PID file not found"
    fi
    
    echo
    echo "  Node Status:"
    
    # Check each gRPC port
    local nodes_running=0
    for i in 1 2 3; do
        local port=$((50050 + i))
        if check_port $port; then
            local port_pid=$(get_port_process_info $port)
            echo -e "    ${GREEN}✓${NC} Node $i (port $port) - Active (PID: $port_pid)"
            nodes_running=$((nodes_running + 1))
        else
            echo -e "    ${RED}✗${NC} Node $i (port $port) - Not responding"
        fi
    done
    
    echo
    if [ $nodes_running -eq 3 ]; then
        echo -e "  ${GREEN}🎉 All 3 nodes are running successfully!${NC}"
    elif [ $nodes_running -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  Only $nodes_running out of 3 nodes are running${NC}"
    else
        echo -e "  ${RED}❌ No nodes are running${NC}"
    fi
    
    return $nodes_running
}

# Function to check client status
check_client_status() {
    print_header "🔌 Client Status"
    echo "==================="
    
    local client_running=false
    local client_pid=""
    
    # Check PID file
    if [ -f "$PID_DIR/client.pid" ]; then
        client_pid=$(cat "$PID_DIR/client.pid")
        if is_process_running "$client_pid"; then
            client_running=true
            echo -e "  ${GREEN}✓${NC} Client process is running (PID: $client_pid)"
            echo -e "    Memory usage: $(get_memory_usage $client_pid)"
            echo -e "    $(format_uptime $client_pid)"
            echo -e "    Connected to: Node 1 (127.0.0.1:50051)"
        else
            echo -e "  ${RED}✗${NC} Client PID file exists but process is not running"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Client PID file not found"
    fi
    
    echo
    if [ "$client_running" = true ]; then
        echo -e "  ${GREEN}🎉 Client is connected and ready!${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Client is not running${NC}"
        return 1
    fi
}

# Function to check system resources
check_system_resources() {
    print_header "💻 System Resources"
    echo "====================="
    
    # Check all beam.smp processes
    local beam_processes=$(pgrep -f "beam.smp" 2>/dev/null || true)
    if [ -n "$beam_processes" ]; then
        local process_count=$(echo "$beam_processes" | wc -l | xargs)
        echo -e "  ${BLUE}📊${NC} Total beam.smp processes: $process_count"
        
        local total_memory=0
        echo "$beam_processes" | while read -r pid; do
            if [ -n "$pid" ]; then
                local mem=$(ps -o rss= -p "$pid" 2>/dev/null | xargs || echo "0")
                local mem_mb=$((mem / 1024))
                local cmd=$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-50 || echo "Unknown")
                echo -e "    PID $pid: ${mem_mb}MB - $cmd..."
                total_memory=$((total_memory + mem))
            fi
        done
        
        local total_memory_mb=$((total_memory / 1024))
        echo -e "  ${BLUE}💾${NC} Total memory usage: ${total_memory_mb}MB"
    else
        echo -e "  ${YELLOW}!${NC} No beam.smp processes found"
    fi
    
    echo
    
    # Check port usage
    echo -e "  ${BLUE}🔌${NC} Port usage:"
    for port in 50051 50052 50053 4001; do
        if check_port $port; then
            local port_pid=$(get_port_process_info $port)
            echo -e "    Port $port: ${GREEN}In use${NC} (PID: $port_pid)"
        else
            echo -e "    Port $port: ${YELLOW}Free${NC}"
        fi
    done
}

# Function to check log files
check_logs() {
    print_header "📋 Log Files"
    echo "=============="
    
    if [ -d "$LOG_DIR" ]; then
        local log_files=$(find "$LOG_DIR" -name "*.log" 2>/dev/null || true)
        if [ -n "$log_files" ]; then
            echo "$log_files" | while read -r log_file; do
                if [ -f "$log_file" ]; then
                    local size=$(du -h "$log_file" 2>/dev/null | cut -f1 || echo "Unknown")
                    local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$log_file" 2>/dev/null || echo "Unknown")
                    local basename=$(basename "$log_file")
                    echo -e "  ${BLUE}📄${NC} $basename: $size (modified: $modified)"
                fi
            done
        else
            echo -e "  ${YELLOW}!${NC} No log files found"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Log directory does not exist"
    fi
}

# Function to provide recommendations
provide_recommendations() {
    local nodes_running=$1
    local client_running=$2
    
    print_header "💡 Recommendations"
    echo "==================="
    
    if [ $nodes_running -eq 3 ] && [ $client_running -eq 0 ]; then
        echo -e "  ${GREEN}✅${NC} System is running optimally!"
        echo -e "  ${BLUE}ℹ️${NC}  You can now use the gRPC client to interact with the network"
    elif [ $nodes_running -eq 0 ] && [ $client_running -eq 1 ]; then
        echo -e "  ${RED}⚠️${NC}  Network is not running but client is active"
        echo -e "  ${BLUE}💡${NC} Run: ./stop_anoma.sh && ./start_anoma.sh"
    elif [ $nodes_running -eq 0 ] && [ $client_running -eq 1 ]; then
        echo -e "  ${RED}⚠️${NC}  Nothing is running"
        echo -e "  ${BLUE}💡${NC} Run: ./start_anoma.sh"
    elif [ $nodes_running -lt 3 ]; then
        echo -e "  ${YELLOW}⚠️${NC}  Some nodes are not running properly"
        echo -e "  ${BLUE}💡${NC} Try restarting: ./stop_anoma.sh && ./start_anoma.sh"
    fi
    
    echo
    echo -e "  ${BLUE}📖${NC} Available commands:"
    echo -e "    ./start_anoma.sh  - Start all services"
    echo -e "    ./stop_anoma.sh   - Stop all services"
    echo -e "    ./status_anoma.sh - Check status (this script)"
}

# Main execution
main() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}  Anoma Network Status Report   ${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    # Check network status
    check_network_status
    local nodes_running=$?
    
    echo
    
    # Check client status
    check_client_status
    local client_running=$?
    
    echo
    
    # Check system resources
    check_system_resources
    
    echo
    
    # Check logs
    check_logs
    
    echo
    
    # Provide recommendations
    provide_recommendations $nodes_running $client_running
    
    echo
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}  Status check completed        ${NC}"
    echo -e "${CYAN}================================${NC}"
}

# Run main function
main "$@"