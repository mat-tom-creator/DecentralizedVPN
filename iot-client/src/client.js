const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');
const path = require('path');
const { VPNManager } = require('./vpn');
const { BlockchainManager } = require('./blockchain');

class IoTClient {
    constructor(config) {
        this.config = config;
        this.vpnManager = new VPNManager(config.vpn);
        this.blockchainManager = new BlockchainManager(config.blockchain);
    }

    async initialize() {
        try {
            // Initialize wallet and gateway
            const walletPath = path.join(process.cwd(), 'wallet');
            this.wallet = await Wallets.newFileSystemWallet(walletPath);

            // Load connection profile
            const ccpPath = path.resolve(__dirname, '..', 'config',
                'connection-profiles', 'connection.json');
            this.connectionProfile = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

            // Connect to gateway
            this.gateway = new Gateway();
            await this.gateway.connect(this.connectionProfile, {
                wallet: this.wallet,
                identity: this.config.identity,
                discovery: { enabled: true, asLocalhost: true }
            });

            // Initialize VPN connection
            await this.vpnManager.initialize();
            console.log('IoT client initialized successfully');
        } catch (error) {
            console.error('Failed to initialize IoT client:', error);
            throw error;
        }
    }

    async connect() {
        try {
            // Establish VPN connection
            await this.vpnManager.connect();

            // Register device on blockchain
            await this.blockchainManager.registerDevice({
                id: this.config.deviceId,
                name: this.config.deviceName,
                type: this.config.deviceType
            });

            // Start health monitoring
            this.startHealthMonitoring();
            console.log('Device connected successfully');
        } catch (error) {
            console.error('Connection failed:', error);
            throw error;
        }
    }

    async startHealthMonitoring() {
        setInterval(async () => {
            try {
                const metrics = await this.collectMetrics();
                await this.blockchainManager.updateHealthStatus(metrics);
            } catch (error) {
                console.error('Health monitoring error:', error);
            }
        }, this.config.healthCheckInterval || 60000);
    }

    async collectMetrics() {
        // Implement metric collection logic
        return {
            cpu: process.cpuUsage().system,
            memory: process.memoryUsage().heapUsed,
            timestamp: Date.now(),
            status: 'ACTIVE'
        };
    }

    async disconnect() {
        try {
            await this.vpnManager.disconnect();
            await this.gateway.disconnect();
            console.log('Device disconnected successfully');
        } catch (error) {
            console.error('Disconnection failed:', error);
            throw error;
        }
    }
}

module.exports = IoTClient;
