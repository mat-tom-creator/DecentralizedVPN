#!/bin/bash

# Base directory
BASE_DIR="/Documents/dvpn-iot"
LOG_DIR="${BASE_DIR}/logs/installation"

# Log output
exec 1> >(tee -a "${LOG_DIR}/dependencies.log")
exec 2>&1

echo "Starting dependencies installation at $(date)"

# Function to update package lists
update_packages() {
    echo "Updating package lists..."
    apt-get update
    if [ $? -ne 0 ]; then
        echo "Failed to update package lists"
        return 1
    fi
}

# Function to install system packages
install_system_packages() {
    echo "Installing system packages..."
    
    # Core system packages
    apt-get install -y \
        curl \
        wget \
        git \
        jq \
        unzip \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common
    
    if [ $? -ne 0 ]; then
        echo "Failed to install core system packages"
        return 1
    fi
}

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group
    usermod -aG docker $SUDO_USER
}

# Function to install OpenVPN
install_openvpn() {
    echo "Installing OpenVPN..."
    
    apt-get install -y openvpn easy-rsa
    
    if [ $? -ne 0 ]; then
        echo "Failed to install OpenVPN"
        return 1
    fi
}

# Function to install Node.js
install_nodejs() {
    echo "Installing Node.js..."
    
    # Add NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_14.x | bash -
    
    # Install Node.js
    apt-get install -y nodejs
    
    # Install required global packages
    npm install -g npm@latest
    npm install -g fabric-client fabric-ca-client
}

# Function to install Go
install_golang() {
    echo "Installing Go..."
    
    # Download and install Go
    local GO_VERSION="1.17.5"
    wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"
    
    # Set up Go environment
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    echo 'export GOPATH=$HOME/go' >> /etc/profile
    source /etc/profile
}

# Function to install monitoring tools
install_monitoring() {
    echo "Installing monitoring tools..."
    
    # Install Prometheus
    apt-get install -y prometheus
    systemctl start prometheus
    systemctl enable prometheus
    
    # Install Grafana
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
    echo "deb https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
    apt-get update
    apt-get install -y grafana
    systemctl start grafana-server
    systemctl enable grafana-server
}

# Function to install Python dependencies
install_python_deps() {
    echo "Installing Python dependencies..."
    
    apt-get install -y python3 python3-pip
    
    # Install required Python packages
    pip3 install \
        prometheus_client \
        psutil \
        requests \
        pyyaml \
        python-dotenv
}

# Function to install security tools
install_security_tools() {
    echo "Installing security tools..."
    
    apt-get install -y \
        ufw \
        fail2ban \
        snort \
        iptables-persistent \
        auditd
}

# Function to verify installations
verify_installations() {
    echo "Verifying installations..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker installation failed"
        return 1
    fi
    
    # Check OpenVPN
    if ! command -v openvpn &> /dev/null; then
        echo "OpenVPN installation failed"
        return 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        echo "Node.js installation failed"
        return 1
    fi
    
    # Check Go
    if ! command -v go &> /dev/null; then
        echo "Go installation failed"
        return 1
    fi
    
    echo "All installations verified successfully"
}

# Main function
main() {
    # Update package lists
    update_packages
    
    # Install dependencies
    install_system_packages
    install_docker
    install_openvpn
    install_nodejs
    install_golang
    install_monitoring
    install_python_deps
    install_security_tools
    
    # Verify installations
    verify_installations
    
    echo "Dependencies installation completed at $(date)"
}

# Start installation
main