#!/bin/bash
# update.sh

# Update system packages
sudo apt update
sudo apt upgrade -y

# Update Docker images
docker-compose -f /opt/dvpn-iot/blockchain/network/docker/docker-compose.yaml pull

# Update Node.js dependencies
cd /opt/dvpn-iot/iot-client
npm update

# Update Python dependencies
pip3 install --upgrade -r /opt/dvpn-iot/monitoring/requirements.txt

# Restart services
sudo systemctl restart docker
sudo systemctl restart openvpn
sudo systemctl restart prometheus
sudo systemctl restart grafana-server

echo "System update completed"
