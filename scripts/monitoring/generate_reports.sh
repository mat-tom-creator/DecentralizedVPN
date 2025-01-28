#!/bin/bash

# Base directories
BASE_DIR="/Documents/dvpn-iot"
LOG_DIR="${BASE_DIR}/logs/monitoring"
METRICS_DIR="${BASE_DIR}/monitoring/metrics"
DATA_DIR="${BASE_DIR}/monitoring/data"
REPORTS_DIR="${BASE_DIR}/monitoring/reports"

# Ensure directories exist
mkdir -p "${LOG_DIR}" "${REPORTS_DIR}"/{daily,weekly,monthly}

# Initialize logging
exec 1> >(tee -a "${LOG_DIR}/report_generation.log")
exec 2>&1

# Load configuration
source "${BASE_DIR}/vpn/config/vars"

# Timestamp function
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Function to generate VPN report
generate_vpn_report() {
    local report_type=$1
    local output_file=$2
    
    echo "# VPN Performance Report" > "${output_file}"
    echo "Generated at: $(get_timestamp)" >> "${output_file}"
    echo "" >> "${output_file}"
    
    echo "## Connection Statistics" >> "${output_file}"
    
    # Get average client count
    local avg_clients=$(awk '/openvpn_connected_clients/ {sum += $2; count++} END {print sum/count}' "${DATA_DIR}"/*/*/*.prom)
    echo "Average Connected Clients: ${avg_clients}" >> "${output_file}"
    
    # Get bandwidth usage
    local total_received=$(awk '/openvpn_bytes_received/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    local total_sent=$(awk '/openvpn_bytes_sent/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    echo "Total Data Received: $(numfmt --to=iec-i ${total_received}B)" >> "${output_file}"
    echo "Total Data Sent: $(numfmt --to=iec-i ${total_sent}B)" >> "${output_file}"
    
    # Get average latency
    local avg_latency=$(awk '/openvpn_latency_ms/ {sum += $2; count++} END {print sum/count}' "${DATA_DIR}"/*/*/*.prom)
    echo "Average Latency: ${avg_latency} ms" >> "${output_file}"
}

# Function to generate blockchain report
generate_blockchain_report() {
    local report_type=$1
    local output_file=$2
    
    echo "# Blockchain Performance Report" >> "${output_file}"
    echo "" >> "${output_file}"
    
    # Get block statistics
    local current_height=$(tail -n 1 "${METRICS_DIR}/blockchain_metrics.prom" | grep blockchain_height | awk '{print $2}')
    local blocks_added=$(awk '/blockchain_height/ {max = $2 > max ? $2 : max; min = min == 0 ? $2 : min} END {print max - min}' "${DATA_DIR}"/*/*/*.prom)
    
    echo "## Block Statistics" >> "${output_file}"
    echo "Current Block Height: ${current_height}" >> "${output_file}"
    echo "Blocks Added: ${blocks_added}" >> "${output_file}"
    
    # Get transaction statistics
    local tx_count=$(tail -n 1 "${METRICS_DIR}/blockchain_metrics.prom" | grep blockchain_transactions_total | awk '{print $2}')
    echo "Total Transactions: ${tx_count}" >> "${output_file}"
}

# Function to generate system report
generate_system_report() {
    local report_type=$1
    local output_file=$2
    
    echo "# System Performance Report" >> "${output_file}"
    echo "" >> "${output_file}"
    
    # CPU statistics
    local avg_cpu=$(awk '/system_cpu_usage/ {sum += $2; count++} END {print sum/count}' "${DATA_DIR}"/*/*/*.prom)
    local max_cpu=$(awk '/system_cpu_usage/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    
    echo "## CPU Usage" >> "${output_file}"
    echo "Average CPU Usage: ${avg_cpu}%" >> "${output_file}"
    echo "Peak CPU Usage: ${max_cpu}%" >> "${output_file}"
    
    # Memory statistics
    local avg_mem=$(awk '/system_memory_usage_percent/ {sum += $2; count++} END {print sum/count}' "${DATA_DIR}"/*/*/*.prom)
    local max_mem=$(awk '/system_memory_usage_percent/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    
    echo "## Memory Usage" >> "${output_file}"
    echo "Average Memory Usage: ${avg_mem}%" >> "${output_file}"
    echo "Peak Memory Usage: ${max_mem}%" >> "${output_file}"
    
    # Disk statistics
    local current_disk=$(tail -n 1 "${METRICS_DIR}/system_metrics.prom" | grep system_disk_usage_percent | awk '{print $2}')
    
    echo "## Disk Usage" >> "${output_file}"
    echo "Current Disk Usage: ${current_disk}%" >> "${output_file}"
}

# Function to generate security report
generate_security_report() {
    local report_type=$1
    local output_file=$2
    
    echo "# Security Report" >> "${output_file}"
    echo "" >> "${output_file}"
    
    # Authentication failures
    local ssh_failures=$(awk '/security_failed_ssh_attempts/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    local vpn_failures=$(awk '/security_failed_vpn_attempts/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    
    echo "## Authentication Failures" >> "${output_file}"
    echo "SSH Failed Attempts: ${ssh_failures}" >> "${output_file}"
    echo "VPN Failed Attempts: ${vpn_failures}" >> "${output_file}"
    
    # Firewall statistics
    local firewall_drops=$(awk '/security_firewall_drops/ {max = $2 > max ? $2 : max} END {print max}' "${DATA_DIR}"/*/*/*.prom)
    
    echo "## Firewall Statistics" >> "${output_file}"
    echo "Total Dropped Packets: ${firewall_drops}" >> "${output_file}"
}

# Function to generate full report
generate_full_report() {
    local report_type=$1
    local date_str=$(date +%Y%m%d)
    local output_file="${REPORTS_DIR}/${report_type}/report_${date_str}.md"
    
    echo "$(get_timestamp) Generating ${report_type} report..."
    
    # Generate report header
    echo "# dVPN IoT System ${report_type^} Report" > "${output_file}"
    echo "Generated at: $(get_timestamp)" >> "${output_file}"
    echo "" >> "${output_file}"
    
    # Generate individual sections
    generate_vpn_report "${report_type}" "${output_file}"
    generate_blockchain_report "${report_type}" "${output_file}"
    generate_system_report "${report_type}" "${output_file}"
    generate_security_report "${report_type}" "${output_file}"
    
    # Add summary section
    echo "# Executive Summary" >> "${output_file}"
    echo "" >> "${output_file}"
    echo "System Status: " >> "${output_file}"
    
    # Check system health
    local cpu_status="OK"
    local mem_status="OK"
    local disk_status="OK"
    
    local current_cpu=$(tail -n 1 "${METRICS_DIR}/system_metrics.prom" | grep system_cpu_usage | awk '{print $2}')
    local current_mem=$(tail -n 1 "${METRICS_DIR}/system_metrics.prom" | grep system_memory_usage_percent | awk '{print $2}')
    local current_disk=$(tail -n 1 "${METRICS_DIR}/system_metrics.prom" | grep system_disk_usage_percent | awk '{print $2}')
    
    [[ ${current_cpu%.*} -gt 80 ]] && cpu_status="WARNING"
    [[ ${current_mem%.*} -gt 80 ]] && mem_status="WARNING"
    [[ ${current_disk%.*} -gt 80 ]] && disk_status="WARNING"
    
    echo "* CPU Usage: ${cpu_status} (${current_cpu}%)" >> "${output_file}"
    echo "* Memory Usage: ${mem_status} (${current_mem}%)" >> "${output_file}"
    echo "* Disk Usage: ${disk_status} (${current_disk}%)" >> "${output_file}"
    
    # Convert to PDF if pandoc is available
    if command -v pandoc &> /dev/null; then
        pandoc "${output_file}" -o "${output_file%.md}.pdf"
    fi
}

# Function to cleanup old reports
cleanup_old_reports() {
    echo "$(get_timestamp) Cleaning up old reports..."
    
    # Keep last 30 daily reports
    find "${REPORTS_DIR}/daily" -type f -mtime +30 -delete
    
    # Keep last 12 weekly reports
    find "${REPORTS_DIR}/weekly" -type f -mtime +90 -delete
    
    # Keep last 12 monthly reports
    find "${REPORTS_DIR}/monthly" -type f -mtime +365 -delete
}

# Function to send report
send_report() {
    local report_file=$1
    local report_type=$2
    
    if [ -f "${report_file}" ]; then
        # If email configuration exists, send report
        if [ -f "${BASE_DIR}/config/email.conf" ]; then
            source "${BASE_DIR}/config/email.conf"
            mail -s "dVPN IoT System ${report_type^} Report" \
                 -a "${report_file}" \
                 "${EMAIL_RECIPIENTS}" < /dev/null
        fi
    fi
}

# Main execution
case "$1" in
    daily)
        generate_full_report "daily"
        send_report "${REPORTS_DIR}/daily/report_$(date +%Y%m%d).md" "daily"
        ;;
    weekly)
        if [ "$(date +%u)" -eq 7 ]; then  # Sunday
            generate_full_report "weekly"
            send_report "${REPORTS_DIR}/weekly/report_$(date +%Y%m%d).md" "weekly"
        fi
        ;;
    monthly)
        if [ "$(date +%d)" -eq 1 ]; then  # First day of month
            generate_full_report "monthly"
            send_report "${REPORTS_DIR}/monthly/report_$(date +%Y%m%d).md" "monthly"
        fi
        ;;
    *)
        echo "Usage: $0 {daily|weekly|monthly}"
        exit 1
        ;;
esac

# Cleanup old reports
cleanup_old_reports