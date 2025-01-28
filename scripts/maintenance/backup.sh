#!/bin/bash
# backup.sh

BACKUP_DIR="/var/backups/dvpn-iot/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup configurations
cp -r /etc/openvpn $BACKUP_DIR/
cp -r /etc/prometheus $BACKUP_DIR/
cp -r /etc/grafana $BACKUP_DIR/

# Backup certificates
cp -r /opt/dvpn-iot/vpn/certificates $BACKUP_DIR/

# Backup blockchain data
cp -r /opt/dvpn-iot/blockchain/config $BACKUP_DIR/

# Compress backup
tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
rm -rf $BACKUP_DIR

echo "Backup completed: $BACKUP_DIR.tar.gz"
