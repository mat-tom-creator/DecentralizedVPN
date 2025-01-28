const { Gateway, Wallets } = require('fabric-network');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');

class BlockchainManager {
    constructor(config) {
        this.config = config;
        this.gateway = null;
        this.network = null;
        this.contract = null;
        this.reconnectAttempts = 3;
        this.reconnectDelay = 5000; // 5 seconds
    }

    async initialize() {
        try {
            // Initialize wallet
            const walletPath = path.join(process.cwd(), 'wallet');
            this.wallet = await Wallets.newFileSystemWallet(walletPath);

            // Load connection profile
            const ccpPath = path.resolve(this.config.connectionProfile);
            const connectionProfile = JSON.parse(
                await fs.readFile(ccpPath, 'utf8')
            );

            // Connect to gateway
            this.gateway = new Gateway();
            await this.gateway.connect(connectionProfile, {
                wallet: this.wallet,
                identity: this.config.identity,
                discovery: { enabled: true, asLocalhost: true }
            });

            // Get network and contract
            this.network = await this.gateway.getNetwork(this.config.channelName);
            this.contract = this.network.getContract(this.config.chaincodeName);

            console.log('BlockchainManager initialized successfully');
        } catch (error) {
            console.error('Failed to initialize BlockchainManager:', error);
            throw error;
        }
    }

    async registerDevice(deviceInfo) {
        await this.ensureConnection();
        try {
            // Generate unique device ID if not provided
            const deviceId = deviceInfo.id || this.generateDeviceId();

            // Create device registration
            const registration = {
                id: deviceId,
                name: deviceInfo.name,
                type: deviceInfo.type,
                publicKey: await this.getDevicePublicKey(),
                timestamp: Date.now(),
                status: 'REGISTERED'
            };

            // Submit transaction
            await this.contract.submitTransaction(
                'RegisterDevice',
                JSON.stringify(registration)
            );

            console.log('Device registered successfully:', deviceId);
            return deviceId;
        } catch (error) {
            console.error('Failed to register device:', error);
            throw error;
        }
    }

    async updateHealthStatus(metrics) {
        await this.ensureConnection();
        try {
            // Add security hash to metrics
            const secureMetrics = {
                ...metrics,
                deviceId: this.config.deviceId,
                timestamp: Date.now(),
                hash: this.generateMetricsHash(metrics)
            };

            await this.contract.submitTransaction(
                'UpdateHealthStatus',
                JSON.stringify(secureMetrics)
            );
        } catch (error) {
            console.error('Failed to update health status:', error);
            throw error;
        }
    }

    async getDeviceStatus() {
        await this.ensureConnection();
        try {
            const result = await this.contract.evaluateTransaction(
                'GetDeviceStatus',
                this.config.deviceId
            );
            return JSON.parse(result.toString());
        } catch (error) {
            console.error('Failed to get device status:', error);
            throw error;
        }
    }

    async ensureConnection() {
        if (!this.gateway || !this.network || !this.contract) {
            for (let i = 0; i < this.reconnectAttempts; i++) {
                try {
                    await this.initialize();
                    break;
                } catch (error) {
                    if (i === this.reconnectAttempts - 1) throw error;
                    await new Promise(resolve => setTimeout(resolve, this.reconnectDelay));
                }
            }
        }
    }

    generateDeviceId() {
        return crypto.randomBytes(16).toString('hex');
    }

    async getDevicePublicKey() {
        try {
            const keyPath = path.join(
                process.cwd(),
                'certificates',
                `${this.config.deviceId}.pub`
            );
            return await fs.readFile(keyPath, 'utf8');
        } catch (error) {
            console.error('Failed to read device public key:', error);
            throw error;
        }
    }

    generateMetricsHash(metrics) {
        const hash = crypto.createHash('sha256');
        hash.update(JSON.stringify(metrics) + this.config.deviceId);
        return hash.digest('hex');
    }

    async disconnect() {
        if (this.gateway) {
            await this.gateway.disconnect();
            this.gateway = null;
            this.network = null;
            this.contract = null;
        }
    }
}

module.exports = BlockchainManager;