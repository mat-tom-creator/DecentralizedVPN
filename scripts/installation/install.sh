#!/bin/bash

# Base directories
BASE_DIR="$HOME/Documents/dvpn-iot"
LOG_DIR="${BASE_DIR}/logs/installation"

# Create log directory
mkdir -p "${LOG_DIR}"
exec 1> >(tee -a "${LOG_DIR}/install.log")
exec 2>&1

echo "Starting installation at $(date)"

# Function to check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Function to install system dependencies
install_dependencies() {
    echo "Installing system dependencies..."
    
    # Update package lists
    apt-get update
    
    # Install required packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        git \
        docker.io \
        docker-compose \
        openvpn \
        prometheus \
        grafana \
        python3 \
        python3-pip \
        ca-certificates \
        gnupg \
        jq

    # Install Python dependencies
    pip3 install prometheus_client psutil

    # Add user to docker group
    usermod -aG docker $USER

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
}

# Function to install Hyperledger Fabric
install_fabric() {
    echo "Installing Hyperledger Fabric..."
    
    cd "${BASE_DIR}"
    
    # Temporarily disable SSL verification for git
    git config --global http.sslVerify false
    
    # Clone Fabric samples repository
    if [ -d "fabric-samples" ]; then
        mv fabric-samples fabric-samples.bak
    fi
    git clone --branch main --depth 1 https://github.com/hyperledger/fabric-samples.git
    
    # Download Fabric binaries
    curl -sSL --insecure https://github.com/hyperledger/fabric/releases/download/v2.5.0/hyperledger-fabric-linux-amd64-2.5.0.tar.gz -o fabric.tar.gz
    tar xzf fabric.tar.gz -C fabric-samples
    rm fabric.tar.gz
    
    # Set up CA configuration
    mkdir -p fabric-samples/test-network/organizations/fabric-ca/org1
    mkdir -p fabric-samples/test-network/organizations/fabric-ca/org2
    mkdir -p fabric-samples/test-network/organizations/fabric-ca/ordererOrg

    # Create CA config files
    cat > fabric-samples/test-network/organizations/fabric-ca/org1/fabric-ca-server-config.yaml <<EOF
version: 1.4.0
port: 7054
operations:
    listenAddress: 127.0.0.1:17054
tls:
    enabled: true
    certfile: tls-cert.pem
    keyfile: tls-key.pem
EOF

    cat > fabric-samples/test-network/organizations/fabric-ca/org2/fabric-ca-server-config.yaml <<EOF
version: 1.4.0
port: 8054
operations:
    listenAddress: 127.0.0.1:18054
tls:
    enabled: true
    certfile: tls-cert.pem
    keyfile: tls-key.pem
EOF

    cat > fabric-samples/test-network/organizations/fabric-ca/ordererOrg/fabric-ca-server-config.yaml <<EOF
version: 1.4.0
port: 9054
operations:
    listenAddress: 127.0.0.1:19054
tls:
    enabled: true
    certfile: tls-cert.pem
    keyfile: tls-key.pem
EOF

    # Download Docker images
    curl -sSL --insecure https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh | bash -s -- binary docker
    
    # Re-enable SSL verification
    git config --global http.sslVerify true
    
    # Set up environment variables
    echo 'export PATH=$PATH:'"${BASE_DIR}/fabric-samples/bin" >> $HOME/.profile
    echo 'export FABRIC_CFG_PATH='"${BASE_DIR}/fabric-samples/config" >> $HOME/.profile
    
    # Source the environment variables
    source $HOME/.profile
}

# Function to create directory structure
create_directory_structure() {
    echo "Creating directory structure..."
    
    directories=(
        "blockchain/chaincode/dvpn"
        "blockchain/config"
        "blockchain/network/docker"
        "blockchain/network/scripts"
        "vpn/config"
        "vpn/certificates/ca"
        "vpn/certificates/server"
        "vpn/certificates/clients"
        "vpn/scripts"
        "monitoring/prometheus"
        "monitoring/grafana/provisioning/dashboards"
        "monitoring/grafana/provisioning/datasources"
        "monitoring/grafana/dashboards"
        "monitoring/collectors"
        "iot-client/src"
        "iot-client/config/connection-profiles"
        "iot-client/certificates"
        "security/firewall"
        "security/ids"
        "security/ssl"
        "logs/vpn"
        "logs/blockchain"
        "logs/monitoring"
        "logs/security"
        "scripts/installation"
        "scripts/maintenance"
        "scripts/monitoring"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "${BASE_DIR}/${dir}"
        echo "Created directory: ${BASE_DIR}/${dir}"
    done

    # Set proper permissions
    chmod -R 755 "${BASE_DIR}"
}

# Function to configure services
configure_services() {
    echo "Configuring services..."
    
    # Configure Prometheus
    mkdir -p "${BASE_DIR}/monitoring/prometheus"
    cat > "${BASE_DIR}/monitoring/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'blockchain'
    static_configs:
      - targets: ['localhost:9106']
  - job_name: 'vpn'
    static_configs:
      - targets: ['localhost:9103']
  - job_name: 'device'
    static_configs:
      - targets: ['localhost:9104']
EOF

    # Configure Grafana
    mkdir -p "${BASE_DIR}/monitoring/grafana/provisioning/datasources"
    cat > "${BASE_DIR}/monitoring/grafana/provisioning/datasources/prometheus.yml" <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF
}

# Function to start blockchain network
start_blockchain_network() {
    echo "Starting blockchain network..."
    cd "${BASE_DIR}/fabric-samples/test-network"

    # Clean up any existing network
    ./network.sh down

    # Start the network with CA
    ./network.sh up -ca
    sleep 10  # Wait for CAs to initialize

    # Create the channel
    ./network.sh createChannel -c dvpnchannel
}

# Function to verify installation
verify_installation() {
    echo "Verifying installation..."
    
    # Check core services
    services=(
        "docker"
        "openvpn"
        "prometheus"
        "grafana-server"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "${service}"; then
            echo "${service}: Running"
        else
            echo "WARNING: ${service} is not running"
        fi
    done
    
    # Check ports
    ports=(
        7050  # Orderer
        7051  # Peer
        1194  # OpenVPN
        9090  # Prometheus
        3000  # Grafana
        9103  # VPN metrics
        9104  # Device metrics
        9106  # Blockchain metrics
    )
    
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":${port} "; then
            echo "Port ${port}: Open"
        else
            echo "WARNING: Port ${port} is not open"
        fi
    done
    
    # Check Fabric installation
    if [ -f "${BASE_DIR}/fabric-samples/bin/peer" ]; then
        echo "Fabric binaries: Installed"
    else
        echo "WARNING: Fabric binaries not found"
    fi
    
    # Check Docker images
    if docker images | grep -q "hyperledger/fabric-peer"; then
        echo "Fabric Docker images: Present"
    else
        echo "WARNING: Fabric Docker images not found"
    fi
}

# Function to perform backup
backup_existing() {
    echo "Backing up existing installation..."
    
    if [ -d "${BASE_DIR}" ]; then
        BACKUP_DIR="$HOME/Documents/dvpn-iot-backup/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${BACKUP_DIR}"
        cp -r "${BASE_DIR}" "${BACKUP_DIR}/"
        echo "Backup created at: ${BACKUP_DIR}"
    fi
}

# Function to handle cleanup on failure
cleanup_on_failure() {
    echo "Installation failed, cleaning up..."
    
    # Stop services
    services=(
        "docker"
        "openvpn"
        "prometheus"
        "grafana-server"
    )
    
    for service in "${services[@]}"; do
        systemctl stop "${service}" 2>/dev/null
    done
    
    echo "Cleanup completed"
    exit 1
}

# Main installation flow
main() {
    # Check root privileges
    check_root
    
    # Backup existing installation
    backup_existing
    
    # Create directory structure
    create_directory_structure
    
    # Install dependencies
    install_dependencies
    
    # Install Hyperledger Fabric
    install_fabric
    
    # Configure services
    configure_services
    
    # Start blockchain network
    start_blockchain_network
    
    # Verify installation
    verify_installation
    
    echo "Installation completed successfully at $(date)"
    echo "Please log out and log back in for group changes to take effect"
}

# Trap errors
trap cleanup_on_failure ERR

# Start installation
main
