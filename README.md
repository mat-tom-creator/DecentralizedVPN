# dVPN IoT System Installation Guide


# dVPN IoT System Installation Guide

## Prerequisites

- Ubuntu 22.04 LTS
- Minimum 4GB RAM
- 20GB free disk space
- Root or sudo access
- Internet connection

## 1. Initial Setup

```bash
# Create project directory
mkdir -p /home/$USER/Documents/dvpn-iot
cd /home/$USER/Documents/dvpn-iot

# Clone the repository
git clone https://github.com/mat-tom-creator/DecentralizedVPN .

# Install system dependencies
sudo apt-get update
sudo apt-get install -y \
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
    jq \
    golang-go \
    build-essential

# Install Hyperledger Fabric prerequisites
curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/bootstrap.sh | bash -s

# Add Docker permissions
sudo usermod -aG docker $USER

# Install Hyperledger Fabric samples, binaries, and Docker images
curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.0 1.5.5

# Add Fabric binaries to PATH
echo 'export PATH=$PATH:$HOME/fabric-samples/bin' >> ~/.bashrc
source ~/.bashrc

# Verify installations
fabric-ca-client version
peer version
```

## 2. Run Installation Scripts

```bash
# Make scripts executable
chmod +x scripts/installation/*.sh

# Run main installation script
sudo ./scripts/installation/install.sh

```

The script will:

- Create directory structure
- Install dependencies
- Configure basic services
- Set up environment variables
- Initialize security settings

## 3. Setup VPN

```bash
# Make VPN scripts executable
chmod +x vpn/scripts/*.sh

# Run VPN setup
sudo ./vpn/scripts/setup-vpn.sh

# Create a client (example)
sudo ./vpn/scripts/manage-clients.sh create client1

```

## 4. Setup Blockchain Network

```bash
cd blockchain/network

# Start the network
sudo ./scripts/network.sh up

# Create channel
sudo ./scripts/network.sh createChannel

# Deploy chaincode
sudo ./scripts/network.sh deployCC

```

## 5. Configure Firewall

```bash
# Allow required ports
sudo ufw allow 7050/tcp  # Fabric orderer
sudo ufw allow 7051/tcp  # Fabric peer
sudo ufw allow 1194/udp  # OpenVPN
sudo ufw allow 3000/tcp  # Grafana
sudo ufw allow 9090/tcp  # Prometheus
sudo ufw allow 9103/tcp  # VPN metrics
sudo ufw allow 9104/tcp  # Device metrics
sudo ufw allow 9106/tcp  # Blockchain metrics

# Enable firewall
sudo ufw enable

```

## 6. Start Monitoring

```bash
# Start monitoring services
sudo systemctl start prometheus
sudo systemctl start grafana-server

# Start monitoring collectors
sudo ./monitoring/collectors/collect_metrics.sh &
python3 ./monitoring/collectors/vpn_metrics.py &
python3 ./monitoring/collectors/blockchain_metrics.py &
python3 ./monitoring/collectors/device_metrics.py &

```

## 7. Setup Alert System

```bash
# Start alert handler
sudo ./scripts/monitoring/alert_handler.sh &

# Configure report generation
sudo crontab -e

# Add these lines:
0 0 * * * /Documents/dvpn-iot/scripts/monitoring/generate_reports.sh daily
0 0 * * 0 /Documents/dvpn-iot/scripts/monitoring/generate_reports.sh weekly
0 0 1 * * /Documents/dvpn-iot/scripts/monitoring/generate_reports.sh monthly

```

## 8. Verify Installation

```bash
# Check services status
sudo systemctl status openvpn
sudo systemctl status docker
sudo systemctl status prometheus
sudo systemctl status grafana-server

# Check VPN status
sudo ./vpn/scripts/manage-clients.sh list

# Check blockchain status
cd blockchain/network
sudo ./scripts/network.sh status

# Check monitoring
curl localhost:9090/metrics  # Prometheus
curl localhost:3000  # Grafana

```

## 9. Access Dashboards

### Grafana

- URL: [http://localhost:3000](http://localhost:3000/)
- Default credentials: admin/admin
- Available dashboards:
    - System Overview
    - VPN Performance
    - Blockchain Metrics
    - IoT Device Status

### Prometheus

- URL: [http://localhost:9090](http://localhost:9090/)
- Metrics endpoints:
    - Blockchain: :9106
    - VPN: :9103
    - Device: :9104

## 10. Maintenance

### Regular Updates

```bash
# System updates
sudo apt-get update
sudo apt-get upgrade -y

# Docker images
docker pull hyperledger/fabric-peer:latest
docker pull hyperledger/fabric-orderer:latest

```

### Backup

```bash
# Run backup
sudo ./scripts/maintenance/backup.sh

# Check system health
sudo ./scripts/maintenance/health_check.sh

```

## 11. Directory Structure

```
/home/$USER/Documents/dvpn-iot/
├── blockchain/
│   ├── chaincode/
│   ├── config/
│   └── network/
├── vpn/
│   ├── config/
│   ├── certificates/
│   └── scripts/
├── monitoring/
│   ├── prometheus/
│   ├── grafana/
│   └── collectors/
├── security/
│   ├── firewall/
│   └── ssl/
├── logs/
└── scripts/
    ├── installation/
    ├── maintenance/
    └── monitoring/

```

## 12. Installation Modes

### Development Mode

```bash
# Install with development settings
sudo ./scripts/installation/install.sh --dev

# Enable debug logging
export DEBUG=true

# Additional development tools
sudo apt-get install -y \\
    golang-go \\
    nodejs \\
    npm

```

### Production Mode

```bash
# Install with production settings
sudo ./scripts/installation/install.sh --prod

# Enable security hardening
sudo ./scripts/security/harden.sh

# Enable automatic updates
sudo systemctl enable dvpn-autoupdate

```

For additional configuration options or troubleshooting, please refer to the project documentation or open an issue on the GitHub repository.
