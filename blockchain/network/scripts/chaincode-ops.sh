#!/bin/bash

# Initialize variables
CHANNEL_NAME="dvpnchannel"
CC_NAME="dvpn"
CC_SRC_PATH="../chaincode/dvpn"
CC_VERSION="1.0"
CC_SEQUENCE="1"
CC_INIT_FCN="InitLedger"
CC_END_POLICY="AND('DVPNMSP.peer')"
CC_COLL_CONFIG=""
DELAY="3"
MAX_RETRY="5"
VERBOSE=false

# Environment setup
export FABRIC_CFG_PATH=$PWD/../config/
export PATH=${PWD}/../bin:${PWD}:$PATH

# Print the usage message
printHelp() {
    echo "Usage: "
    echo "  chaincode-ops.sh <Mode>"
    echo "    Modes:"
    echo "      package - Package the chaincode"
    echo "      install - Install the chaincode package"
    echo "      approve - Approve chaincode definition"
    echo "      commit - Commit chaincode definition"
    echo "      init - Initialize the chaincode"
    echo "      invoke - Invoke chaincode function"
    echo "      query - Query chaincode function"
    echo "      deploy - Full deployment (package, install, approve, commit, init)"
    echo "      upgrade - Upgrade chaincode to new version"
    echo ""
    echo "    Flags:"
    echo "      -h - Print this help message"
    echo "      -n <name> - Chaincode name"
    echo "      -v <version> - Chaincode version"
    echo "      -s <sequence> - Chaincode sequence"
    echo "      -c <channel name> - Channel name"
    echo "      -f <function name> - Function to invoke/query"
    echo "      -a <args> - Arguments for function invocation"
}

# Package the chaincode
packageChaincode() {
    echo "Packaging chaincode ${CC_NAME}..."
    peer lifecycle chaincode package ${CC_NAME}.tar.gz \
        --path ${CC_SRC_PATH} \
        --lang golang \
        --label ${CC_NAME}_${CC_VERSION}
    
    if [ $? -ne 0 ]; then
        echo "Failed to package chaincode"
        exit 1
    fi
}

# Install chaincode package
installChaincode() {
    echo "Installing chaincode on peer0..."
    peer lifecycle chaincode install ${CC_NAME}.tar.gz

    if [ $? -ne 0 ]; then
        echo "Failed to install chaincode on peer0"
        exit 1
    fi

    echo "Installing chaincode on peer1..."
    CORE_PEER_ADDRESS=peer1.dvpn.example.com:7051 \
    peer lifecycle chaincode install ${CC_NAME}.tar.gz

    if [ $? -ne 0 ]; then
        echo "Failed to install chaincode on peer1"
        exit 1
    fi
}

# Query installed chaincode
queryInstalled() {
    echo "Querying installed chaincode..."
    peer lifecycle chaincode queryinstalled > log.txt
    PACKAGE_ID=$(sed -n "/${CC_NAME}_${CC_VERSION}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
    echo "PackageID is ${PACKAGE_ID}"
    if [ -z "$PACKAGE_ID" ]; then
        echo "Failed to get package ID"
        exit 1
    fi
}

# Approve chaincode definition
approveForMyOrg() {
    echo "Approving chaincode definition for org..."
    peer lifecycle chaincode approveformyorg \
        -o orderer.example.com:7050 \
        --channelID $CHANNEL_NAME \
        --name ${CC_NAME} \
        --version ${CC_VERSION} \
        --package-id ${PACKAGE_ID} \
        --sequence ${CC_SEQUENCE} \
        --tls --cafile $ORDERER_CA \
        ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG}

    if [ $? -ne 0 ]; then
        echo "Failed to approve chaincode definition"
        exit 1
    fi
}

# Check commit readiness
checkCommitReadiness() {
    echo "Checking commit readiness..."
    peer lifecycle chaincode checkcommitreadiness \
        --channelID $CHANNEL_NAME \
        --name ${CC_NAME} \
        --version ${CC_VERSION} \
        --sequence ${CC_SEQUENCE} \
        --tls --cafile $ORDERER_CA \
        ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG}
}

# Commit chaincode definition
commitChaincodeDefinition() {
    echo "Committing chaincode definition..."
    peer lifecycle chaincode commit \
        -o orderer.example.com:7050 \
        --channelID $CHANNEL_NAME \
        --name ${CC_NAME} \
        --version ${CC_VERSION} \
        --sequence ${CC_SEQUENCE} \
        --tls --cafile $ORDERER_CA \
        --peerAddresses peer0.dvpn.example.com:7051 \
        --tlsRootCertFiles /etc/hyperledger/fabric/tls/ca.crt \
        ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG}

    if [ $? -ne 0 ]; then
        echo "Failed to commit chaincode definition"
        exit 1
    fi
}

# Initialize chaincode
chaincodeInvokeInit() {
    echo "Initializing chaincode..."
    peer chaincode invoke \
        -o orderer.example.com:7050 \
        --channelID $CHANNEL_NAME \
        --name ${CC_NAME} \
        --tls --cafile $ORDERER_CA \
        --peerAddresses peer0.dvpn.example.com:7051 \
        --tlsRootCertFiles /etc/hyperledger/fabric/tls/ca.crt \
        -c '{"function":"'${CC_INIT_FCN}'","Args":[]}' \
        --isInit

    if [ $? -ne 0 ]; then
        echo "Failed to initialize chaincode"
        exit 1
    fi
}

# Invoke chaincode function
chaincodeInvoke() {
    echo "Invoking chaincode function ${INVOKE_FUNCTION} with args: ${INVOKE_ARGS}"
    peer chaincode invoke \
        -o orderer.example.com:7050 \
        --channelID $CHANNEL_NAME \
        --name ${CC_NAME} \
        --tls --cafile $ORDERER_CA \
        --peerAddresses peer0.dvpn.example.com:7051 \
        --tlsRootCertFiles /etc/hyperledger/fabric/tls/ca.crt \
        -c '{"function":"'${INVOKE_FUNCTION}'","Args":['${INVOKE_ARGS}']}'
}

# Query chaincode function
chaincodeQuery() {
    echo "Querying chaincode function ${QUERY_FUNCTION} with args: ${QUERY_ARGS}"
    peer chaincode query \
        -C $CHANNEL_NAME \
        -n ${CC_NAME} \
        -c '{"function":"'${QUERY_FUNCTION}'","Args":['${QUERY_ARGS}']}'
}

# Full deployment of chaincode
deployChaincode() {
    packageChaincode
    installChaincode
    queryInstalled
    approveForMyOrg
    checkCommitReadiness
    commitChaincodeDefinition
    chaincodeInvokeInit
}

# Upgrade chaincode
upgradeChaincode() {
    CC_VERSION=$1
    CC_SEQUENCE=$((CC_SEQUENCE + 1))
    
    packageChaincode
    installChaincode
    queryInstalled
    approveForMyOrg
    checkCommitReadiness
    commitChaincodeDefinition
}

# Main script logic
MODE=$1
shift

# Parse command line flags
while getopts "h?n:v:s:c:f:a:" opt; do
    case "$opt" in
        h|\?)
            printHelp
            exit 0
            ;;
        n)
            CC_NAME=$OPTARG
            ;;
        v)
            CC_VERSION=$OPTARG
            ;;
        s)
            CC_SEQUENCE=$OPTARG
            ;;
        c)
            CHANNEL_NAME=$OPTARG
            ;;
        f)
            if [ "$MODE" = "invoke" ]; then
                INVOKE_FUNCTION=$OPTARG
            else
                QUERY_FUNCTION=$OPTARG
            fi
            ;;
        a)
            if [ "$MODE" = "invoke" ]; then
                INVOKE_ARGS=$OPTARG
            else
                QUERY_ARGS=$OPTARG
            fi
            ;;
    esac
done

# Process mode
case "$MODE" in
    package)
        packageChaincode
        ;;
    install)
        installChaincode
        ;;
    approve)
        queryInstalled
        approveForMyOrg
        ;;
    commit)
        commitChaincodeDefinition
        ;;
    init)
        chaincodeInvokeInit
        ;;
    invoke)
        chaincodeInvoke
        ;;
    query)
        chaincodeQuery
        ;;
    deploy)
        deployChaincode
        ;;
    upgrade)
        if [ -z "$1" ]; then
            echo "Error: Version number required for upgrade"
            exit 1
        fi
        upgradeChaincode $1
        ;;
    *)
        printHelp
        exit 1
esac