# dVPN IoT System Installation Guide

## System Requirements
- Ubuntu 22.04 LTS
- 4GB RAM minimum
- 20GB free disk space
- Root or sudo access
- Internet connection

## 1. Initial Setup

### Update System
```bash
sudo apt update
sudo apt upgrade -y
```

### Install Basic Dependencies
```bash
sudo apt install -y git ufw curl wget
```

### Clone Repository
```bash
cd ~/Documents
git clone https://github.com/mat-tom-creator/DecentralizedVPN dvpn-iot
cd dvpn-iot
```

### Create Directory Structure
```bash
mkdir -p scripts/installation
mkdir -p blockchain/network
mkdir -p vpn/scripts
mkdir -p monitoring/collectors
mkdir -p security/firewall
mkdir -p logs/installation
```

## 2. Configure Firewall
Configure firewall before main installation:

```bash
# Reset UFW to default
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (important to prevent lockout)
sudo ufw allow ssh

# Blockchain ports
sudo ufw allow 7050/tcp comment 'Fabric orderer'
sudo ufw allow 7051/tcp comment 'Fabric peer'
sudo ufw allow 7052/tcp comment 'Fabric chaincode'
sudo ufw allow 7053/tcp comment 'Fabric events'

# VPN ports
sudo ufw allow 1194/udp comment 'OpenVPN'

# Monitoring ports
sudo ufw allow 3000/tcp comment 'Grafana'
sudo ufw allow 9090/tcp comment 'Prometheus'
sudo ufw allow 9103/tcp comment 'VPN metrics'
sudo ufw allow 9104/tcp comment 'Device metrics'
sudo ufw allow 9106/tcp comment 'Blockchain metrics'

# Enable UFW
sudo ufw enable

# Verify rules
sudo ufw status numbered
```

## 3. Run Installation Scripts

### Prepare Installation
```bash
# Make scripts executable
chmod +x scripts/installation/install.sh
chmod +x vpn/scripts/*.sh
chmod +x monitoring/collectors/*.sh
chmod +x security/firewall/*.sh
```

### Run Main Installation
```bash
sudo ./scripts/installation/install.sh
```

The script will automatically:
- Check system requirements
- Install dependencies
- Configure services
- Initialize configurations

## 4. Setup VPN
```bash
# Configure VPN
sudo ./vpn/scripts/setup-vpn.sh

# Create initial client certificate
sudo ./vpn/scripts/manage-clients.sh create client1
```

## 5. Setup Blockchain Network
```bash
cd blockchain/network

# Start network
./scripts/network.sh up

# Create channel
./scripts/network.sh createChannel

# Deploy chaincode
./scripts/network.sh deployCC
```

## 6. Configure Monitoring

### Start Core Services
```bash
# Start and enable Prometheus
sudo systemctl start prometheus
sudo systemctl enable prometheus

# Start and enable Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

### Start Collectors
```bash
# Start metric collectors
sudo ./monitoring/collectors/collect_metrics.sh &
sudo ./monitoring/collectors/vpn_metrics.py &
sudo ./monitoring/collectors/blockchain_metrics.py &
sudo ./monitoring/collectors/device_metrics.py &
```

## 7. Setup Alerts and Reports

### Configure Alert System
```bash
# Start alert handler
sudo ./scripts/monitoring/alert_handler.sh &
```

### Setup Automated Reports
```bash
# Add to crontab
(crontab -l 2>/dev/null; echo "0 0 * * * ${HOME}/Documents/dvpn-iot/scripts/monitoring/generate_reports.sh daily") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * 0 ${HOME}/Documents/dvpn-iot/scripts/monitoring/generate_reports.sh weekly") | crontab -
(crontab -l 2>/dev/null; echo "0 0 1 * * ${HOME}/Documents/dvpn-iot/scripts/monitoring/generate_reports.sh monthly") | crontab -
```

## 8. Verify Installation

### Check Services
```bash
for service in docker openvpn prometheus grafana-server; do
    echo "Checking $service..."
    sudo systemctl status $service
done
```

### Verify Ports
```bash
sudo netstat -tulpn | grep -E '7050|7051|1194|3000|9090|9103|9104|9106'
```

### Check Blockchain
```bash
cd blockchain/network
./scripts/network.sh status
```

## 9. Access Dashboards

### Grafana Dashboard
- URL: http://localhost:3000
- Default login: admin/admin
- Available dashboards:
  - System Overview
  - VPN Status
  - Blockchain Metrics
  - Device Status

### Prometheus
- URL: http://localhost:9090

## 10. Regular Maintenance

### System Updates
```bash
sudo ./scripts/maintenance/update.sh
```

### Backup System
```bash
sudo ./scripts/maintenance/backup.sh
```

### Health Check
```bash
sudo ./scripts/maintenance/system_health.sh
```

## 11. Installation Modes

### Development Mode
```bash
# Install with development settings
sudo ./scripts/installation/install.sh --dev

# Enable debug logging
export DEBUG=true

# Install additional development tools
sudo apt install -y golang-go nodejs npm python3-pip
```

### Production Mode
```bash
# Install with production hardening
sudo ./scripts/installation/install.sh --prod

# Enable security hardening
sudo ./scripts/security/harden.sh

# Configure automatic updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

## 12. Troubleshooting

### Check Logs
```bash
# VPN logs
sudo tail -f /var/log/openvpn/openvpn.log

# Blockchain logs
sudo tail -f logs/blockchain/fabric.log

# Monitoring logs
sudo tail -f logs/monitoring/prometheus.log
sudo tail -f logs/monitoring/grafana.log
```

### Common Issues
1. If services fail to start:
```bash
sudo systemctl restart docker
sudo systemctl restart openvpn
```

2. If firewall blocks legitimate traffic:
```bash
sudo ufw status numbered
sudo ufw delete [rule-number]
```

3. If blockchain network fails:
```bash
./blockchain/network/scripts/network.sh teardown
./blockchain/network/scripts/network.sh up
```

## 13. Security Recommendations

1. Change default passwords
2. Enable 2FA where possible
3. Regular security updates
4. Monitor system logs
5. Regular backups
