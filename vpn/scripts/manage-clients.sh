#!/bin/bash

# Base directories
BASE_DIR="/opt/dvpn-iot"
VPN_DIR="${BASE_DIR}/vpn"
CERT_DIR="${VPN_DIR}/certificates"
CONFIG_DIR="${VPN_DIR}/config"
LOG_DIR="${BASE_DIR}/logs/vpn"
CLIENT_DIR="${CERT_DIR}/clients"

# Source variables
source ${CONFIG_DIR}/vars

# Initialize logging
mkdir -p "${LOG_DIR}"
exec 1> >(tee -a "${LOG_DIR}/client-management.log")
exec 2>&1

# Function to create a new client
create_client() {
    local CLIENT_NAME=$1
    local CLIENT_IP=$2
    
    if [ -z "$CLIENT_NAME" ]; then
        echo "Error: Client name not provided"
        return 1
    fi
    
    echo "Creating client: ${CLIENT_NAME}"
    
    # Create client directory
    mkdir -p "${CLIENT_DIR}/${CLIENT_NAME}"
    
    # Generate client key and certificate
    cd "${CERT_DIR}/ca"
    ./easyrsa build-client-full "${CLIENT_NAME}" nopass
    
    # Copy client certificates
    cp "pki/ca.crt" "${CLIENT_DIR}/${CLIENT_NAME}/"
    cp "pki/issued/${CLIENT_NAME}.crt" "${CLIENT_DIR}/${CLIENT_NAME}/"
    cp "pki/private/${CLIENT_NAME}.key" "${CLIENT_DIR}/${CLIENT_NAME}/"
    cp "ta.key" "${CLIENT_DIR}/${CLIENT_NAME}/"
    
    # Generate client config
    generate_client_config "${CLIENT_NAME}" "${CLIENT_IP}"
    
    echo "Client ${CLIENT_NAME} created successfully"
}

# Function to generate client configuration
generate_client_config() {
    local CLIENT_NAME=$1
    local CLIENT_IP=$2
    local SERVER_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    
    # Create base configuration from template
    cp "${CONFIG_DIR}/client.conf.template" "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    
    # Replace server address
    sed -i "s/SERVER_ADDRESS/${SERVER_ADDRESS}/" "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    
    # Add certificates to config file
    echo "<ca>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    cat "${CLIENT_DIR}/${CLIENT_NAME}/ca.crt" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    echo "</ca>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    
    echo "<cert>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    cat "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.crt" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    echo "</cert>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    
    echo "<key>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    cat "${CLIENT_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.key" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    echo "</key>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    
    echo "<tls-auth>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    cat "${CLIENT_DIR}/${CLIENT_NAME}/ta.key" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    echo "</tls-auth>" >> "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
    
    # If static IP is provided, create client-specific config
    if [ ! -z "$CLIENT_IP" ]; then
        echo "ifconfig-push ${CLIENT_IP} 255.255.255.0" > "${CONFIG_DIR}/ccd/${CLIENT_NAME}"
    fi
    
    # Set proper permissions
    chmod 600 "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn"
}

# Function to revoke a client
revoke_client() {
    local CLIENT_NAME=$1
    
    if [ -z "$CLIENT_NAME" ]; then
        echo "Error: Client name not provided"
        return 1
    fi
    
    echo "Revoking client: ${CLIENT_NAME}"
    
    # Revoke certificate
    cd "${CERT_DIR}/ca"
    ./easyrsa revoke "${CLIENT_NAME}"
    
    # Generate new CRL
    ./easyrsa gen-crl
    
    # Copy CRL to correct location
    cp "pki/crl.pem" "${CERT_DIR}/crl/"
    
    # Remove client-specific config
    rm -f "${CONFIG_DIR}/ccd/${CLIENT_NAME}"
    
    # Remove client directory
    rm -rf "${CLIENT_DIR}/${CLIENT_NAME}"
    
    # Restart OpenVPN to apply changes
    systemctl restart openvpn@server
    
    echo "Client ${CLIENT_NAME} revoked successfully"
}

# Function to list clients
list_clients() {
    echo "Active clients:"
    echo "----------------------------------------"
    
    # List certificates
    cd "${CERT_DIR}/ca"
    ./easyrsa show-issued
    
    echo -e "\nConnected clients:"
    echo "----------------------------------------"
    if [ -f "${OPENVPN_STATUS_LOG}" ]; then
        grep "CLIENT_LIST" "${OPENVPN_STATUS_LOG}" | awk '{print $2 " - " $3 " (connected since " $5 " " $6 " " $7 ")"}'
    else
        echo "No status log available"
    fi
}

# Function to show client status
client_status() {
    local CLIENT_NAME=$1
    
    if [ -z "$CLIENT_NAME" ]; then
        echo "Error: Client name not provided"
        return 1
    fi
    
    echo "Status for client: ${CLIENT_NAME}"
    echo "----------------------------------------"
    
    # Check certificate status
    cd "${CERT_DIR}/ca"
    ./easyrsa show-cert "${CLIENT_NAME}"
    
    # Check connection status
    if [ -f "${OPENVPN_STATUS_LOG}" ]; then
        echo -e "\nConnection status:"
        grep "${CLIENT_NAME}" "${OPENVPN_STATUS_LOG}" || echo "Not currently connected"
    fi
}

# Function to export client configuration
export_client() {
    local CLIENT_NAME=$1
    local OUTPUT_DIR=$2
    
    if [ -z "$CLIENT_NAME" ] || [ -z "$OUTPUT_DIR" ]; then
        echo "Error: Client name or output directory not provided"
        return 1
    fi
    
    if [ ! -d "${CLIENT_DIR}/${CLIENT_NAME}" ]; then
        echo "Error: Client ${CLIENT_NAME} does not exist"
        return 1
    fi
    
    mkdir -p "${OUTPUT_DIR}"
    cp "${CLIENT_DIR}/${CLIENT_NAME}/client.ovpn" "${OUTPUT_DIR}/"
    chmod 600 "${OUTPUT_DIR}/client.ovpn"
    
    echo "Client configuration exported to ${OUTPUT_DIR}/client.ovpn"
}

# Function to update client configuration
update_client() {
    local CLIENT_NAME=$1
    local CLIENT_IP=$2
    
    if [ -z "$CLIENT_NAME" ]; then
        echo "Error: Client name not provided"
        return 1
    fi
    
    if [ ! -d "${CLIENT_DIR}/${CLIENT_NAME}" ]; then
        echo "Error: Client ${CLIENT_NAME} does not exist"
        return 1
    fi
    
    echo "Updating client: ${CLIENT_NAME}"
    generate_client_config "${CLIENT_NAME}" "${CLIENT_IP}"
    
    # Restart OpenVPN if client-specific config was updated
    if [ ! -z "$CLIENT_IP" ]; then
        systemctl restart openvpn@server
    fi
    
    echo "Client ${CLIENT_NAME} updated successfully"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create <client_name> [client_ip]   - Create a new client"
    echo "  revoke <client_name>              - Revoke a client certificate"
    echo "  list                              - List all clients"
    echo "  status <client_name>              - Show client status"
    echo "  export <client_name> <output_dir> - Export client configuration"
    echo "  update <client_name> [client_ip]  - Update client configuration"
    echo ""
    echo "Examples:"
    echo "  $0 create device1 10.8.0.10"
    echo "  $0 revoke device1"
    echo "  $0 export device1 /tmp/vpn-config"
}

# Main script logic
case "$1" in
    create)
        create_client "$2" "$3"
        ;;
    revoke)
        revoke_client "$2"
        ;;
    list)
        list_clients
        ;;
    status)
        client_status "$2"
        ;;
    export)
        export_client "$2" "$3"
        ;;
    update)
        update_client "$2" "$3"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

exit 0