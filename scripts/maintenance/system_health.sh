#!/bin/bash
# health_check.sh

# Check system resources
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1)

# Check services
check_service() {
    if systemctl is-active --quiet $1; then
        echo "$1 is running"
    else
        echo "WARNING: $1 is not running"
    fi
}

check_service "docker"
check_service "openvpn"
check_service "prometheus"
check_service "grafana-server"

# Check network connectivity
ping -c 1 8.8.8.8 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Internet connectivity: OK"
else
    echo "WARNING: Internet connectivity issue"
fi

# Check VPN tunnel
if ip addr show tun0 > /dev/null 2>&1; then
    echo "VPN tunnel: Active"
else
    echo "WARNING: VPN tunnel not found"
fi

# Output resource usage
echo "CPU Usage: $CPU_USAGE%"
echo "Memory Usage: $MEMORY_USAGE%"
echo "Disk Usage: $DISK_USAGE%"
