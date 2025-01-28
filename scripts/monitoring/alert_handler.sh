#!/bin/bash

# Base directories
BASE_DIR="/Documents/dvpn-iot"
LOG_DIR="${BASE_DIR}/logs/monitoring"
ALERTS_DIR="${BASE_DIR}/monitoring/alerts"
METRICS_DIR="${BASE_DIR}/monitoring/metrics"

# Ensure directories exist
mkdir -p "${LOG_DIR}" "${ALERTS_DIR}"/{active,history}

# Initialize logging
exec 1> >(tee -a "${LOG_DIR}/alert_handler.log")
exec 2>&1

# Load configuration
source "${BASE_DIR}/vpn/config/vars"

# Alert thresholds
declare -A THRESHOLDS=(
    ["cpu_usage"]=80
    ["memory_usage"]=80
    ["disk_usage"]=85
    ["vpn_latency"]=100
    ["block_latency"]=10
    ["peer_count_min"]=2
    ["client_count_min"]=1
)

# Alert severities
declare -A SEVERITIES=(
    ["critical"]="CRITICAL"
    ["warning"]="WARNING"
    ["info"]="INFO"
)

# Timestamp function
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Function to generate alert ID
generate_alert_id() {
    echo "$(date +%s)_${RANDOM}"
}

# Function to create alert
create_alert() {
    local alert_id=$1
    local severity=$2
    local component=$3
    local message=$4
    local metric_value=$5
    
    local alert_file="${ALERTS_DIR}/active/${alert_id}.alert"
    
    cat > "${alert_file}" << EOF
{
    "id": "${alert_id}",
    "timestamp": "$(get_timestamp)",
    "severity": "${severity}",
    "component": "${component}",
    "message": "${message}",
    "metric_value": "${metric_value}",
    "status": "active"
}
EOF
}

# Function to resolve alert
resolve_alert() {
    local alert_id=$1
    local resolution=$2
    
    if [ -f "${ALERTS_DIR}/active/${alert_id}.alert" ]; then
        local alert_file="${ALERTS_DIR}/active/${alert_id}.alert"
        local history_file="${ALERTS_DIR}/history/$(date +%Y%m%d)_${alert_id}.alert"
        
        # Add resolution information
        jq --arg resolution "$resolution" \
           --arg timestamp "$(get_timestamp)" \
           '. + {resolution: $resolution, resolved_at: $timestamp, status: "resolved"}' \
           "${alert_file}" > "${history_file}"
        
        # Remove active alert
        rm "${alert_file}"
    fi
}

# Function to check system metrics
check_system_metrics() {
    # Check CPU usage
    local cpu_usage=$(awk '/system_cpu_usage/ {print $2}' "${METRICS_DIR}/system_metrics.prom")
    if (( ${cpu_usage%.*} > ${THRESHOLDS["cpu_usage"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "warning" "system" \
                    "High CPU usage detected" "${cpu_usage}%"
    fi
    
    # Check memory usage
    local memory_usage=$(awk '/system_memory_usage_percent/ {print $2}' "${METRICS_DIR}/system_metrics.prom")
    if (( ${memory_usage%.*} > ${THRESHOLDS["memory_usage"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "warning" "system" \
                    "High memory usage detected" "${memory_usage}%"
    fi
    
    # Check disk usage
    local disk_usage=$(awk '/system_disk_usage_percent/ {print $2}' "${METRICS_DIR}/system_metrics.prom")
    if (( ${disk_usage%.*} > ${THRESHOLDS["disk_usage"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "critical" "system" \
                    "High disk usage detected" "${disk_usage}%"
    fi
}

# Function to check VPN metrics
check_vpn_metrics() {
    # Check VPN latency
    local vpn_latency=$(awk '/openvpn_latency_ms/ {print $2}' "${METRICS_DIR}/vpn_metrics.prom")
    if (( ${vpn_latency%.*} > ${THRESHOLDS["vpn_latency"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "warning" "vpn" \
                    "High VPN latency detected" "${vpn_latency}ms"
    fi
    
    # Check connected clients
    local client_count=$(awk '/openvpn_connected_clients/ {print $2}' "${METRICS_DIR}/vpn_metrics.prom")
    if (( client_count < ${THRESHOLDS["client_count_min"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "warning" "vpn" \
                    "Low client count detected" "${client_count}"
    fi
}

# Function to check blockchain metrics
check_blockchain_metrics() {
    # Check block latency
    local block_latency=$(awk '/blockchain_latency/ {print $2}' "${METRICS_DIR}/blockchain_metrics.prom")
    if (( ${block_latency%.*} > ${THRESHOLDS["block_latency"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "warning" "blockchain" \
                    "High block latency detected" "${block_latency}s"
    fi
    
    # Check peer count
    local peer_count=$(awk '/blockchain_peer_count/ {print $2}' "${METRICS_DIR}/blockchain_metrics.prom")
    if (( peer_count < ${THRESHOLDS["peer_count_min"]} )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "critical" "blockchain" \
                    "Low peer count detected" "${peer_count}"
    fi
}

# Function to check security metrics
check_security_metrics() {
    # Check failed SSH attempts
    local ssh_failures=$(awk '/security_failed_ssh_attempts/ {print $2}' "${METRICS_DIR}/security_metrics.prom")
    if (( ssh_failures > 10 )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "critical" "security" \
                    "Multiple SSH authentication failures detected" "${ssh_failures}"
    fi
    
    # Check failed VPN authentications
    local vpn_failures=$(awk '/security_failed_vpn_attempts/ {print $2}' "${METRICS_DIR}/security_metrics.prom")
    if (( vpn_failures > 5 )); then
        local alert_id=$(generate_alert_id)
        create_alert "${alert_id}" "critical" "security" \
                    "Multiple VPN authentication failures detected" "${vpn_failures}"
    fi
}

# Function to send notifications
send_notification() {
    local alert_file=$1
    
    # If email configuration exists, send notification
    if [ -f "${BASE_DIR}/config/email.conf" ]; then
        source "${BASE_DIR}/config/email.conf"
        local alert_data=$(cat "${alert_file}")
        local severity=$(echo "${alert_data}" | jq -r .severity)
        local component=$(echo "${alert_data}" | jq -r .component)
        local message=$(echo "${alert_data}" | jq -r .message)
        
        mail -s "[${severity}] dVPN IoT System Alert - ${component}" \
             "${EMAIL_RECIPIENTS}" << EOF
Alert Details:
${message}

Time: $(get_timestamp)
Component: ${component}
Severity: ${severity}
EOF
    fi
    
    # If webhook configuration exists, send notification
    if [ -f "${BASE_DIR}/config/webhook.conf" ]; then
        source "${BASE_DIR}/config/webhook.conf"
        curl -X POST -H "Content-Type: application/json" \
             -d @"${alert_file}" "${WEBHOOK_URL}"
    fi
}

# Function to cleanup old alerts
cleanup_old_alerts() {
    # Remove resolved alerts older than 30 days
    find "${ALERTS_DIR}/history" -type f -mtime +30 -delete
    
    # Check for stale active alerts (older than 24 hours)
    find "${ALERTS_DIR}/active" -type f -mtime +1 | while read alert_file; do
        resolve_alert "$(basename "${alert_file}" .alert)" "Auto-resolved (stale alert)"
    done
}

# Main execution loop
main() {
    while true; do
        echo "$(get_timestamp) Starting alert check cycle..."
        
        # Check all metrics
        check_system_metrics
        check_vpn_metrics
        check_blockchain_metrics
        check_security_metrics
        
        # Process active alerts
        for alert_file in "${ALERTS_DIR}/active"/*.alert; do
            if [ -f "${alert_file}" ]; then
                send_notification "${alert_file}"
            fi
        done
        
        # Cleanup old alerts
        cleanup_old_alerts
        
        # Wait before next check
        sleep 60
        
        echo "$(get_timestamp) Alert check cycle completed"
    done
}

# Start alert handler
main