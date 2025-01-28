#!/bin/bash

# Base directory
BASE_DIR="/Documents/dvpn-iot"
LOG_DIR="${BASE_DIR}/logs/installation"

# Log output
exec 1> >(tee -a "${LOG_DIR}/configure.log")
exec 2>&1

echo "Starting system configuration at $(date)"

# Function to configure system limits
configure_system_limits() {
    echo "Configuring system limits..."
    
    cat > /etc/security/limits.d/dvpn-iot.conf << EOF
*       soft    nofile      65536
*       hard    nofile      65536
*       soft    nproc       65536
*       hard    nproc       65536
root    soft    nofile      65536
root    hard    nofile      65536
root    soft    nproc       65536
root    hard    nproc       65536
EOF

    # Update sysctl configuration
    cat > /etc/sysctl.d/99-dvpn-iot.conf << EOF
# Network performance tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 10000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.ip_forward = 1

# System limits
kernel.pid_max = 65536
vm.max_map_count = 262144
kernel.threads-max = 65536
EOF

    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-dvpn-iot.conf
}

# Function to configure firewall
configure_firewall() {
    echo "Configuring firewall..."
    
    # Enable UFW
    ufw enable
    
    # Allow SSH
    ufw allow 22/tcp
    
    # Allow OpenVPN
    ufw allow 1194/udp
    
    # Allow Blockchain ports
    ufw allow 7050/tcp # Orderer
    ufw allow 7051/tcp # Peer
    ufw allow 7052/tcp # Chaincode
    ufw allow 7053/tcp # Event Hub
    ufw allow 7054/tcp # CA
    
    # Allow monitoring ports
    ufw allow 9090/tcp # Prometheus
    ufw allow 3000/tcp # Grafana
    ufw allow 9100/tcp # Node exporter
    
    # Enable firewall
    ufw --force enable
}

# Function to configure logging
configure_logging() {
    echo "Configuring logging..."
    
    # Create rsyslog configuration
    cat > /etc/rsyslog.d/30-dvpn-iot.conf << EOF
# VPN logs
local0.*    /var/log/dvpn-iot/vpn/openvpn.log
# Blockchain logs
local1.*    /var/log/dvpn-iot/blockchain/fabric.log
# Security logs
local2.*    /var/log/dvpn-iot/security/security.log
EOF

    # Create logrotate configuration
    cat > /etc/logrotate.d/dvpn-iot << EOF
/var/log/dvpn-iot/*/*.log {
    daily
    rotate 7
    missingok
    compress
    delaycompress
    notifempty
    create 0640 syslog adm
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

    # Restart rsyslog
    systemctl restart rsyslog
}

# Function to configure Docker
configure_docker() {
    echo "Configuring Docker..."
    
    # Create daemon configuration
    cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "5"
    },
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 65536,
            "Soft": 65536
        }
    },
    "metrics-addr" : "0.0.0.0:9323",
    "experimental" : true
}
EOF

    # Restart Docker
    systemctl restart docker
}

# Function to configure monitoring
configure_monitoring() {
    echo "Configuring monitoring services..."
    
    # Configure Prometheus
    cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/opt/dvpn-iot/monitoring/prometheus/alert.rules"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

scrape_configs:
  - job_name: 'vpn_nodes'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'vpn_node'

  - job_name: 'blockchain_nodes'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'blockchain_node'

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF

    # Configure Grafana datasources
    mkdir -p /etc/grafana/provisioning/datasources/
    cat > /etc/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

deleteDatasources:
  - name: Prometheus
    orgId: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    url: http://localhost:9090
    basicAuth: false
    isDefault: true
    editable: false
    version: 1
    jsonData:
      timeInterval: "5s"
EOF

    # Restart monitoring services
    systemctl restart prometheus
    systemctl restart grafana-server
}

# Function to configure security
configure_security() {
    echo "Configuring security settings..."
    
    # Configure fail2ban
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 3600
findtime  = 600
maxretry = 5

[sshd]
enabled = true

[openvpn]
enabled = true
port    = 1194
protocol = udp
filter  = openvpn
logpath = /var/log/dvpn-iot/vpn/openvpn.log
maxretry = 3
EOF

    # Create fail2ban OpenVPN filter
    cat > /etc/fail2ban/filter.d/openvpn.conf << EOF
[Definition]
failregex = ^.*MULITIPLE_AUTH_FAILED.*$
            ^.*AUTH_FAILED.*$
ignoreregex =
EOF

    # Configure audit rules
    cat > /etc/audit/rules.d/audit.rules << EOF
# Delete all existing rules
-D

# Increase the buffers to survive stress events
-b 8192

# Monitor file system mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# Monitor changes to network environment
-w /etc/sysconfig/network -p wa -k network
-w /etc/network/ -p wa -k network
-w /etc/hosts -p wa -k hosts

# Monitor changes to VPN configuration
-w /opt/dvpn-iot/vpn/config/ -p wa -k vpn_config
-w /opt/dvpn-iot/vpn/certificates/ -p wa -k vpn_certs

# Monitor changes to blockchain configuration
-w /opt/dvpn-iot/blockchain/config/ -p wa -k blockchain_config
-w /opt/dvpn-iot/blockchain/chaincode/ -p wa -k chaincode

# Monitor privileged commands
-a always,exit -F path=/usr/bin/docker -F perm=x -F auid>=1000 -F auid!=4294967295 -k docker
-a always,exit -F path=/usr/bin/openvpn -F perm=x -F auid>=1000 -F auid!=4294967295 -k openvpn
EOF

    # Restart security services
    systemctl restart fail2ban
    systemctl restart auditd
}

# Function to verify configuration
verify_configuration() {
    echo "Verifying configuration..."
    
    # Check system limits
    ulimit -n
    
    # Check firewall status
    ufw status verbose
    
    # Check Docker configuration
    docker info
    
    # Check monitoring services
    systemctl status prometheus
    systemctl status grafana-server
    
    # Check security services
    systemctl status fail2ban
    systemctl status auditd
}

# Main function
main() {
    configure_system_limits
    configure_firewall
    configure_logging
    configure_docker
    configure_monitoring
    configure_security
    verify_configuration
    
    echo "System configuration completed at $(date)"
}

# Start configuration
main