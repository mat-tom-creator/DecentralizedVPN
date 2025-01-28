package main

import (
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
    "github.com/prometheus/client_golang/prometheus"
)

// HealthStatus represents the health status of a device
type HealthStatus struct {
    DeviceID string `json:"deviceId"`
    Timestamp int64 `json:"timestamp"`
    CPU float64 `json:"cpu"`
    Memory float64 `json:"memory"`
    Bandwidth float64 `json:"bandwidth"`
    Status string `json:"status"`
}

var (
    deviceHealthStatus = prometheus.NewGaugeVec(
        prometheus.GaugeOpts{
            Name: "device_health_status",
            Help: "Current health status of devices",
        },
        []string{"device_id", "status"},
    )
)

func init() {
    prometheus.MustRegister(deviceHealthStatus)
}

// UpdateHealthStatus updates the health status of a device
func (c *DVPNContract) UpdateHealthStatus(ctx contractapi.TransactionContextInterface, deviceID string, cpu float64, memory float64, bandwidth float64) error {
    status := HealthStatus{
        DeviceID: deviceID,
        Timestamp: ctx.GetStub().GetTxTimestamp().Seconds,
        CPU: cpu,
        Memory: memory,
        Bandwidth: bandwidth,
        Status: determineStatus(cpu, memory, bandwidth),
    }

    statusJSON, err := json.Marshal(status)
    if err != nil {
        return fmt.Errorf("failed to marshal health status: %v", err)
    }

    statusKey := fmt.Sprintf("HEALTH_%s", deviceID)
    deviceHealthStatus.WithLabelValues(deviceID, status.Status).Set(1)

    return ctx.GetStub().PutState(statusKey, statusJSON)
}

// determineStatus calculates overall status based on metrics
func determineStatus(cpu float64, memory float64, bandwidth float64) string {
    if cpu > 90 || memory > 90 || bandwidth > 90 {
        return "CRITICAL"
    }
    if cpu > 70 || memory > 70 || bandwidth > 70 {
        return "WARNING"
    }
    return "HEALTHY"
}

// GetHealthStatus retrieves the health status of a device
func (c *DVPNContract) GetHealthStatus(ctx contractapi.TransactionContextInterface, deviceID string) (*HealthStatus, error) {
    statusKey := fmt.Sprintf("HEALTH_%s", deviceID)
    statusBytes, err := ctx.GetStub().GetState(statusKey)
    if err != nil {
        return nil, fmt.Errorf("failed to read health status: %v", err)
    }
    if statusBytes == nil {
        return nil, fmt.Errorf("health status not found for device: %s", deviceID)
    }

    var status HealthStatus
    if err := json.Unmarshal(statusBytes, &status); err != nil {
        return nil, fmt.Errorf("failed to unmarshal health status: %v", err)
    }

    return &status, nil
}
