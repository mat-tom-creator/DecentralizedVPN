#!/bin/bash

# Base directories
BASE_DIR="/Documents/dvpn-iot"
LOG_DIR="${BASE_DIR}/logs/monitoring"
METRICS_DIR="${BASE_DIR}/monitoring/metrics"
DATA_DIR="${BASE_DIR}/monitoring/data"

# Ensure directories exist
mkdir -p "${LOG_DIR}" "${METRICS_DIR}" "${DATA_DIR}"

# Initialize logging
exec 1> >(tee -a "${LOG_DIR}/metrics_collection.log")
exec 2>&1

# Load configuration
source "${BASE_DIR}/vpn/config/vars"

# Timestamp function
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Function to collect VPN metrics
collect_vpn_metrics() {
    echo "$(get_timestamp) Collecting VPN metrics..."
    
    # Create metrics file
    local vpn_metrics="${METRICS_DIR}/vpn_metrics.prom"
    
    # Get connected clients count
    local client_count=$(grep -c "^CLIENT_LIST" "${OPENVPN_STATUS_LOG}" 2>/dev/null || echo "0")
    echo "openvpn_connected_clients ${client_count}" > "${vpn_metrics}"
    
    # Get bandwidth metrics
    if [ -f "${OPENVPN_STATUS_LOG}" ]; then
        local bytes_received=0
        local bytes_sent=0
        while IFS=',' read -r _ received sent _; do
            if [[ $received =~ ^[0-9]+$ ]] && [[ $sent =~ ^[0-9]+$ ]]; then
                ((bytes_received += received))
                ((bytes_sent += sent))
            fi
        done < <(grep "^ROUTING_TABLE" "${OPENVPN_STATUS_LOG}")
        echo "openvpn_bytes_received ${bytes_received}" >> "${vpn_metrics}"
        echo "openvpn_bytes_sent ${bytes_sent}" >> "${vpn_metrics}"
    fi
    
    # Get VPN latency
    if ip addr show tun0 >/dev/null 2>&1; then
        local latency=$(ping -c 1 10.8.0.1 2>/dev/null | grep -oP 'time=\K[0-9.]+' || echo "0")
        echo "openvpn_latency_ms ${latency}" >> "${vpn_metrics}"
    fi
}

# Function to collect blockchain metrics
collect_blockchain_metrics() {
    echo "$(get_timestamp) Collecting blockchain metrics..."
    
    # Create metrics file
    local blockchain_metrics="${METRICS_DIR}/blockchain_metrics.prom"
    
    # Get peer status
    local peer_count=$(docker ps -f name=peer -q | wc -l)
    echo "blockchain_peer_count ${peer_count}" > "${blockchain_metrics}"
    
    # Get block height
    if [ -f "${BASE_DIR}/blockchain/ledger/chains/index" ]; then
        local block_height=$(ls -1 "${BASE_DIR}/blockchain/ledger/chains/index" | wc -l)
        echo "blockchain_height ${block_height}" >> "${blockchain_metrics}"
    fi
    
    # Get transaction metrics
    local tx_count=$(docker logs $(docker ps -qf name=peer0) 2>&1 | grep -c "Committed block")
    echo "blockchain_transactions_total ${tx_count}" >> "${blockchain_metrics}"
}

# Function to collect system metrics
collect_system_metrics() {
    echo "$(get_timestamp) Collecting system metrics..."
    
    # Create metrics file
    local system_metrics="${METRICS_DIR}/system_metrics.prom"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    echo "system_cpu_usage ${cpu_usage}" > "${system_metrics}"
    
    # Memory usage
    local memory_total=$(free | grep Mem | awk '{print $2}')
    local memory_used=$(free | grep Mem | awk '{print $3}')
    local memory_percentage=$(awk "BEGIN {printf \"%.2f\", ${memory_used}/${memory_total}*100}")
    echo "system_memory_total ${memory_total}" >> "${system_metrics}"
    echo "system_memory_used ${memory_used}" >> "${system_metrics}"
    echo "system_memory_usage_percent ${memory_percentage}" >> "${system_metrics}"
    
    # Disk usage
    local disk_total=$(df / | tail -1 | awk '{print $2}')
    local disk_used=$(df / | tail -1 | awk '{print $3}')
    local disk_percentage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    echo "system_disk_total ${disk_total}" >> "${system_metrics}"
    echo "system_disk_used ${disk_used}" >> "${system_metrics}"
    echo "system_disk_usage_percent ${disk_percentage}" >> "${system_metrics}"
    
    # Network metrics
    local net_stats=$(cat /proc/net/dev | grep 'eth0:' | awk '{print $2,$10}')
    local bytes_in=$(echo ${net_stats} | cut -d' ' -f1)
    local bytes_out=$(echo ${net_stats} | cut -d' ' -f2)
    echo "system_network_bytes_in ${bytes_in}" >> "${system_metrics}"
    echo "system_network_bytes_out ${bytes_out}" >> "${system_metrics}"
}

# Function to collect security metrics
collect_security_metrics() {
    echo "$(get_timestamp) Collecting security metrics..."
    
    # Create metrics file
    local security_metrics="${METRICS_DIR}/security_metrics.prom"
    
    # Failed login attempts
    local failed_ssh=$(grep "Failed password" /var/log/auth.log | wc -l)
    echo "security_failed_ssh_attempts ${failed_ssh}" > "${security_metrics}"
    
    # Failed VPN authentications
    local failed_vpn=$(grep "AUTH_FAILED" "${OPENVPN_LOG_DIR}/openvpn.log" | wc -l)
    echo "security_failed_vpn_attempts ${failed_vpn}" >> "${security_metrics}"
    
    # Firewall drops
    local firewall_drops=$(iptables -nvL | grep "DROP" | awk '{sum += $1} END {print sum}')
    echo "security_firewall_drops ${firewall_drops}" >> "${security_metrics}"
}

# Function to store historical data
store_historical_data() {
    echo "$(get_timestamp) Storing historical data..."
    
    # Create timestamp
    local timestamp=$(date +%s)
    local date_dir="${DATA_DIR}/$(date +%Y/%m/%d)"
    mkdir -p "${date_dir}"
    
    # Combine all metrics
    cat "${METRICS_DIR}"/*.prom > "${date_dir}/metrics_${timestamp}.prom"
    
    # Clean up old data (keep 30 days)
    find "${DATA_DIR}" -type f -mtime +30 -delete
}

# Main collection loop
main() {
    while true; do
        echo "$(get_timestamp) Starting metrics collection cycle..."
        
        # Collect all metrics
        collect_vpn_metrics
        collect_blockchain_metrics
        collect_system_metrics
        collect_security_metrics
        
        # Store historical data
        store_historical_data
        
        # Wait for next collection cycle
        sleep 60
        
        echo "$(get_timestamp) Metrics collection cycle completed"
    done
}

# Start collection
main