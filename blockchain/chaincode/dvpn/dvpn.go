package main

import (
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
    "github.com/prometheus/client_golang/prometheus"
)

// DVPNContract for handling VPN connections
type DVPNContract struct {
    contractapi.Contract
}

// Device represents an IoT device
type Device struct {
    ID string `json:"id"`
    Name string `json:"name"`
    IPAddress string `json:"ipAddress"`
    Status string `json:"status"`
    LastSeen int64 `json:"lastSeen"`
}

// Connection represents a VPN connection
type Connection struct {
    ID string `json:"id"`
    DeviceID string `json:"deviceId"`
    StartTime int64 `json:"startTime"`
    EndTime int64 `json:"endTime"`
    Status string `json:"status"`
}

var (
    vpnConnectionsTotal = prometheus.NewCounter(prometheus.CounterOpts{
        Name: "vpn_connections_total",
        Help: "Total number of VPN connections established",
    })
)

func init() {
    prometheus.MustRegister(vpnConnectionsTotal)
}

// RegisterDevice adds a new device to the network
func (c *DVPNContract) RegisterDevice(ctx contractapi.TransactionContextInterface, id string, name string) error {
    device := Device{
        ID: id,
        Name: name,
        Status: "REGISTERED",
        LastSeen: ctx.GetStub().GetTxTimestamp().Seconds,
    }

    deviceJSON, err := json.Marshal(device)
    if err != nil {
        return fmt.Errorf("failed to marshal device: %v", err)
    }

    return ctx.GetStub().PutState(id, deviceJSON)
}

// EstablishConnection creates a new VPN connection
func (c *DVPNContract) EstablishConnection(ctx contractapi.TransactionContextInterface, deviceID string) error {
    // Check if device exists
    deviceBytes, err := ctx.GetStub().GetState(deviceID)
    if err != nil {
        return fmt.Errorf("failed to read device: %v", err)
    }
    if deviceBytes == nil {
        return fmt.Errorf("device does not exist: %s", deviceID)
    }

    // Create connection record
    connectionID := fmt.Sprintf("CONN_%s_%d", deviceID, ctx.GetStub().GetTxTimestamp().Seconds)
    connection := Connection{
        ID: connectionID,
        DeviceID: deviceID,
        StartTime: ctx.GetStub().GetTxTimestamp().Seconds,
        Status: "ACTIVE",
    }

    connectionJSON, err := json.Marshal(connection)
    if err != nil {
        return fmt.Errorf("failed to marshal connection: %v", err)
    }

    vpnConnectionsTotal.Inc()
    return ctx.GetStub().PutState(connectionID, connectionJSON)
}

func main() {
    contract := new(DVPNContract)
    chaincode, err := contractapi.NewChaincode(contract)
    if err != nil {
        fmt.Printf("Error creating chaincode: %v\\n", err)
        return
    }

    if err := chaincode.Start(); err != nil {
        fmt.Printf("Error starting chaincode: %v\\n", err)
    }
}
