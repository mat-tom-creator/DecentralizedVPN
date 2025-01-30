#!/bin/bash

# Base directories
BASE_DIR="/opt/dvpn-iot"
VPN_DIR="${BASE_DIR}/vpn"
CERT_DIR="${VPN_DIR}/certificates"
CONFIG_DIR="${VPN_DIR}/config"
LOG_DIR="${BASE_DIR}/logs/vpn"

# Source variables
source ${CONFIG_DIR}/vars

# Initialize logging
mkdir -p "${LOG_DIR}"
exec 1> >(tee -a "${LOG_DIR}/setup.log")
exec 2>&1

echo "Starting VPN setup at $(date)"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" 
        exit 1
    fi
}

# Function to install required packages
install_packages() {
    echo "Installing required packages..."
    apt-get update
    apt-get install -y openvpn easy-rsa net-tools iptables-persistent

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p
}

# Function to setup PKI infrastructure
setup_pki() {
    echo "Setting up PKI infrastructure..."
    
    # Create certificate directories
    mkdir -p "${CERT_DIR}"/{ca,server,clients,crl}
    
    # Copy EasyRSA files
    cp -r /usr/share/easy-rsa/* "${CERT_DIR}/ca/"
    
    # Initialize PKI
    cd "${CERT_DIR}/ca"
    ./easyrsa init-pki
    
    # Generate CA
    EASYRSA_BATCH=1 EASYRSA_REQ_CN="dVPN-IoT-CA" ./easyrsa build-ca nopass
    
    # Generate server certificate
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass
    
    # Generate DH parameters
    ./easyrsa gen-dh
    
    # Generate TLS auth key
    openvpn --genkey --secret ta.key
    
    # Copy server certificates to correct location
    cp "${CERT_DIR}/ca/pki/ca.crt" "${CERT_DIR}/server/"
    cp "${CERT_DIR}/ca/pki/issued/server.crt" "${CERT_DIR}/server/"
    cp "${CERT_DIR}/ca/pki/private/server.key" "${CERT_DIR}/server/"
    cp "${CERT_DIR}/ca/pki/dh.pem" "${CERT_DIR}/server/"
    cp "${CERT_DIR}/ca/ta.key" "${CERT_DIR}/server/"
    
    # Set proper permissions
    chmod -R 700 "${CERT_DIR}"
    chmod -R 600 "${CERT_DIR}/server/"*
}

# Function to configure server
configure_server() {
    echo "Configuring OpenVPN server..."
    
    # Generate server configuration
    cat > "${CONFIG_DIR}/server.conf" << EOL
port ${OPENVPN_PORT}
proto ${OPENVPN_PROTOCOL}
dev tun

ca ${CERT_DIR}/server/ca.crt
cert ${CERT_DIR}/server/server.crt
key ${CERT_DIR}/server/server.key
dh ${CERT_DIR}/server/dh.pem
tls-auth ${CERT_DIR}/server/ta.key 0

server ${OPENVPN_SERVER_SUBNET} ${OPENVPN_SERVER_NETMASK}
ifconfig-pool-persist /var/log/openvpn/ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Performance settings
keepalive 10 120
cipher ${OPENVPN_CIPHER}
auth ${OPENVPN_AUTH}
tls-version-min ${OPENVPN_TLS_VERSION_MIN}
tls-cipher ${OPENVPN_TLS_CIPHER}

# Network optimization
tun-mtu ${OPENVPN_MTU}
fragment ${OPENVPN_FRAGMENT}
mssfix ${OPENVPN_MSS}
sndbuf 393216
rcvbuf 393216
push "sndbuf 393216"
push "rcvbuf 393216"

# Security
user nobody
group nogroup
persist-key
persist-tun
crl-verify ${CERT_DIR}/crl/crl.pem

# Logging
status ${OPENVPN_STATUS_LOG} 30
log-append ${LOG_DIR}/openvpn.log
verb 3

# Management Interface
management localhost 7505

# Client-specific configurations
client-config-dir ${CONFIG_DIR}/ccd
EOL

    # Create client config directory
    mkdir -p "${CONFIG_DIR}/ccd"
    
    # Create client configuration template
    cat > "${CONFIG_DIR}/client.conf.template" << EOL
client
dev tun
proto ${OPENVPN_PROTOCOL}

remote SERVER_ADDRESS ${OPENVPN_PORT}
resolv-retry infinite
nobind

# Security
cipher ${OPENVPN_CIPHER}
auth ${OPENVPN_AUTH}
tls-version-min ${OPENVPN_TLS_VERSION_MIN}
tls-cipher ${OPENVPN_TLS_CIPHER}

# Performance
tun-mtu ${OPENVPN_MTU}
fragment ${OPENVPN_FRAGMENT}
mssfix ${OPENVPN_MSS}
sndbuf 393216
rcvbuf 393216

persist-key
persist-tun
remote-cert-tls server
verify-x509-name server name

<ca>
</ca>
<cert>
</cert>
<key>
</key>
<tls-auth>
</tls-auth>
key-direction 1

verb 3
EOL
}

# Function to configure firewall
configure_firewall() {
    echo "Configuring firewall..."
    
    # Configure iptables
    iptables -t nat -A POSTROUTING -s ${OPENVPN_SERVER_SUBNET}/${OPENVPN_SERVER_NETMASK} -o eth0 -j MASQUERADE
    iptables -A INPUT -i tun+ -j ACCEPT
    iptables -A FORWARD -i tun+ -j ACCEPT
    iptables -A FORWARD -i tun+ -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i eth0 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Save iptables rules
    netfilter-persistent save
}

# Function to setup monitoring
setup_monitoring() {
    echo "Setting up VPN monitoring..."
    
    # Create monitoring directory
    mkdir -p "${BASE_DIR}/monitoring/collectors"
    
    # Copy monitoring script
    cp "${VPN_DIR}/scripts/monitor-vpn.sh" "${BASE_DIR}/monitoring/collectors/"
    chmod +x "${BASE_DIR}/monitoring/collectors/monitor-vpn.sh"
    
    # Setup systemd service for monitoring
    cat > /etc/systemd/system/vpn-monitoring.service << EOL
[Unit]
Description=VPN Monitoring Service
After=network.target

[Service]
ExecStart=${BASE_DIR}/monitoring/collectors/monitor-vpn.sh
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable vpn-monitoring
    systemctl start vpn-monitoring
}

# Main setup process
check_root
install_packages
setup_pki
configure_server
configure_firewall
setup_monitoring

# Start OpenVPN service
systemctl enable openvpn@server
systemctl start openvpn@server

echo "VPN setup completed at $(date)"