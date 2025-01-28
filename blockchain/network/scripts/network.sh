#!/bin/bash

# Initialize variables
export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}/../config/
export VERBOSE=false

# Organization names
ORDERER_ORG="OrdererOrg"
DVPN_ORG="DVPNMSP"

# Channel names
CHANNEL_NAME="dvpnchannel"
CHANNEL_PROFILE="DVPNChannel"

# Function to print the usage message
printHelp() {
    echo "Usage: "
    echo "  network.sh <Mode> [Flags]"
    echo "    Modes:"
    echo "      up - Bring up the network"
    echo "      down - Bring down the network"
    echo "      restart - Restart the network"
    echo "      createChannel - Create and join a channel"
    echo "      deployCC - Deploy chaincode"
    echo "    Flags:"
    echo "      -h - Print this message"
    echo "      -c <channel name> - Channel name (default \"dvpnchannel\")"
    echo "      -v - Verbose mode"
}

# Function to create crypto material
createCryptoMaterial() {
    echo "Generating crypto material..."
    cryptogen generate --config=../config/crypto-config.yaml --output="../crypto"
    if [ $? -ne 0 ]; then
        echo "Failed to generate crypto material..."
        exit 1
    fi
}

# Function to generate genesis block
generateGenesisBlock() {
    echo "Generating genesis block..."
    configtxgen -profile DVPNOrdererGenesis -channelID system-channel -outputBlock ../config/genesis.block
    if [ $? -ne 0 ]; then
        echo "Failed to generate genesis block..."
        exit 1
    fi
}

# Function to bring up the network
networkUp() {
    if [ ! -d "../crypto" ]; then
        createCryptoMaterial
    fi
    
    if [ ! -f "../config/genesis.block" ]; then
        generateGenesisBlock
    fi
    
    echo "Starting the network..."
    docker-compose -f docker-compose.yaml up -d
    if [ $? -ne 0 ]; then
        echo "Failed to start network..."
        exit 1
    fi
    
    # Wait for all containers to be ready
    sleep 10
    echo "Network is up"
}

# Function to bring down the network
networkDown() {
    echo "Stopping the network..."
    docker-compose -f docker-compose.yaml down --volumes --remove-orphans
    
    # Clean up generated files
    rm -rf ../crypto/*
    rm -rf ../config/genesis.block
    rm -rf ../config/${CHANNEL_NAME}.tx
    
    echo "Network is down"
}

# Function to create a channel
createChannel() {
    echo "Creating channel ${CHANNEL_NAME}..."
    
    # Generate channel transaction
    configtxgen -profile ${CHANNEL_PROFILE} -outputCreateChannelTx ../config/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
    if [ $? -ne 0 ]; then
        echo "Failed to generate channel transaction..."
        exit 1
    fi
    
    # Create channel using peer0
    docker exec -e CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp \
        peer0.dvpn.example.com peer channel create \
        -o orderer.example.com:7050 \
        -c $CHANNEL_NAME \
        -f /etc/hyperledger/config/${CHANNEL_NAME}.tx \
        --tls --cafile /etc/hyperledger/fabric/tls/ca.crt

    sleep 5

    # Join peer0 to channel
    echo "Joining peer0.dvpn.example.com to channel..."
    docker exec -e CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp \
        peer0.dvpn.example.com peer channel join \
        -b /etc/hyperledger/fabric/${CHANNEL_NAME}.block

    # Join peer1 to channel
    echo "Joining peer1.dvpn.example.com to channel..."
    docker exec -e CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp \
        peer1.dvpn.example.com peer channel join \
        -b /etc/hyperledger/fabric/${CHANNEL_NAME}.block

    # Update anchor peers
    echo "Updating anchor peers..."
    peer channel update \
        -o orderer.example.com:7050 \
        -c $CHANNEL_NAME \
        -f /etc/hyperledger/config/${DVPN_ORG}anchors.tx \
        --tls --cafile /etc/hyperledger/fabric/tls/ca.crt
}

# Function to deploy chaincode
deployChaincode() {
    echo "Deploying chaincode..."
    ./chaincode-ops.sh deploy
}

# Main script logic
MODE=$1
shift

# Parse command line flags
while getopts "h?c:v" opt; do
    case "$opt" in
        h|\?)
            printHelp
            exit 0
            ;;
        c)
            CHANNEL_NAME=$OPTARG
            ;;
        v)
            VERBOSE=true
            ;;
    esac
done

# Process mode
case "$MODE" in
    up)
        networkUp
        ;;
    down)
        networkDown
        ;;
    restart)
        networkDown
        networkUp
        ;;
    createChannel)
        createChannel
        ;;
    deployCC)
        deployChaincode
        ;;
    *)
        printHelp
        exit 1
esac