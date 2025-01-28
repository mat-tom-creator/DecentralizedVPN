package main

import (
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// AccessPolicy defines access control rules
type AccessPolicy struct {
    DeviceID string `json:"deviceId"`
    Permissions []string `json:"permissions"`
    ValidUntil int64 `json:"validUntil"`
}

// CreateAccessPolicy creates a new access policy for a device
func (c *DVPNContract) CreateAccessPolicy(ctx contractapi.TransactionContextInterface, deviceID string, permissions []string, validUntil int64) error {
    policy := AccessPolicy{
        DeviceID: deviceID,
        Permissions: permissions,
        ValidUntil: validUntil,
    }

    policyJSON, err := json.Marshal(policy)
    if err != nil {
        return fmt.Errorf("failed to marshal policy: %v", err)
    }

    policyKey := fmt.Sprintf("POLICY_%s", deviceID)
    return ctx.GetStub().PutState(policyKey, policyJSON)
}

// CheckAccess verifies if a device has required permissions
func (c *DVPNContract) CheckAccess(ctx contractapi.TransactionContextInterface, deviceID string, requiredPermission string) (bool, error) {
    policyKey := fmt.Sprintf("POLICY_%s", deviceID)
    policyBytes, err := ctx.GetStub().GetState(policyKey)
    if err != nil {
        return false, fmt.Errorf("failed to read policy: %v", err)
    }
    if policyBytes == nil {
        return false, nil
    }

    var policy AccessPolicy
    if err := json.Unmarshal(policyBytes, &policy); err != nil {
        return false, fmt.Errorf("failed to unmarshal policy: %v", err)
    }

    // Check if policy is still valid
    if ctx.GetStub().GetTxTimestamp().Seconds > policy.ValidUntil {
        return false, nil
    }

    // Check if permission exists
    for _, perm := range policy.Permissions {
        if perm == requiredPermission {
            return true, nil
        }
    }

    return false, nil
}
package main

import (
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// AccessPolicy defines access control rules
type AccessPolicy struct {
    DeviceID string `json:"deviceId"`
    Permissions []string `json:"permissions"`
    ValidUntil int64 `json:"validUntil"`
}

// CreateAccessPolicy creates a new access policy for a device
func (c *DVPNContract) CreateAccessPolicy(ctx contractapi.TransactionContextInterface, deviceID string, permissions []string, validUntil int64) error {
    policy := AccessPolicy{
        DeviceID: deviceID,
        Permissions: permissions,
        ValidUntil: validUntil,
    }

    policyJSON, err := json.Marshal(policy)
    if err != nil {
        return fmt.Errorf("failed to marshal policy: %v", err)
    }

    policyKey := fmt.Sprintf("POLICY_%s", deviceID)
    return ctx.GetStub().PutState(policyKey, policyJSON)
}

// CheckAccess verifies if a device has required permissions
func (c *DVPNContract) CheckAccess(ctx contractapi.TransactionContextInterface, deviceID string, requiredPermission string) (bool, error) {
    policyKey := fmt.Sprintf("POLICY_%s", deviceID)
    policyBytes, err := ctx.GetStub().GetState(policyKey)
    if err != nil {
        return false, fmt.Errorf("failed to read policy: %v", err)
    }
    if policyBytes == nil {
        return false, nil
    }

    var policy AccessPolicy
    if err := json.Unmarshal(policyBytes, &policy); err != nil {
        return false, fmt.Errorf("failed to unmarshal policy: %v", err)
    }

    // Check if policy is still valid
    if ctx.GetStub().GetTxTimestamp().Seconds > policy.ValidUntil {
        return false, nil
    }

    // Check if permission exists
    for _, perm := range policy.Permissions {
        if perm == requiredPermission {
            return true, nil
        }
    }

    return false, nil
}
