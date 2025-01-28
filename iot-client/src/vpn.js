const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { promisify } = require('util');
const execAsync = promisify(exec);

class VPNManager {
    constructor(config) {
        this.config = config;
        this.configPath = path.join(process.cwd(), 'vpn.conf');
        this.connected = false;
        this.process = null;
        this.connectionTimeout = 30000; // 30 seconds timeout
    }

    async initialize() {
        try {
            // Generate VPN configuration
            const configContent = this.generateConfig();
            await fs.promises.writeFile(this.configPath, configContent, { mode: 0o600 }); // Secure permissions
            console.log('VPN configuration generated');
            
            // Verify certificates exist and are readable
            await this.verifyCertificates();
        } catch (error) {
            console.error('VPN initialization failed:', error);
            throw error;
        }
    }

    async verifyCertificates() {
        const certificates = [
            this.config.certificates.ca,
            this.config.certificates.cert,
            this.config.certificates.key
        ];

        for (const cert of certificates) {
            try {
                await fs.promises.access(cert, fs.constants.R_OK);
            } catch (error) {
                throw new Error(`Certificate not accessible: ${cert}`);
            }
        }
    }

    generateConfig() {
        // Enhanced configuration with security and performance optimizations
        return `
client
dev tun
proto ${this.config.protocol || 'udp'}
remote ${this.config.serverAddress} ${this.config.port}
resolv-retry infinite
nobind
persist-key
persist-tun

# Certificates
ca ${this.config.certificates.ca}
cert ${this.config.certificates.cert}
key ${this.config.certificates.key}

# Security settings
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
remote-cert-tls server

# Performance optimization
tun-mtu 1500
mssfix 1450
sndbuf 393216
rcvbuf 393216
comp-lzo

# Connection handling
keepalive 10 60
ping-timer-rem
persist-tun
persist-key

# Logging
verb 3
`.trim();
    }

    async connect() {
        if (this.connected) {
            console.log('VPN already connected');
            return;
        }

        try {
            // Start OpenVPN process
            this.process = exec(`openvpn --config ${this.configPath}`, {
                maxBuffer: 1024 * 1024 // 1MB buffer for logs
            });

            // Handle process events
            this.process.stdout.on('data', (data) => {
                console.log('OpenVPN:', data.trim());
                if (data.includes('Initialization Sequence Completed')) {
                    this.connected = true;
                }
            });

            this.process.stderr.on('data', (data) => {
                console.error('OpenVPN Error:', data.trim());
            });

            this.process.on('error', (error) => {
                console.error('OpenVPN Process Error:', error);
                this.connected = false;
            });

            this.process.on('exit', (code) => {
                console.log(`OpenVPN process exited with code ${code}`);
                this.connected = false;
            });

            // Wait for connection or timeout
            await this.waitForConnection();
            
            // Verify connection
            await this.verifyConnection();
            
            console.log('VPN connected successfully');
        } catch (error) {
            console.error('VPN connection failed:', error);
            await this.disconnect();
            throw error;
        }
    }

    async waitForConnection() {
        return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                reject(new Error('VPN connection timeout'));
            }, this.connectionTimeout);

            const checkInterval = setInterval(() => {
                if (this.connected) {
                    clearTimeout(timeout);
                    clearInterval(checkInterval);
                    resolve();
                }
            }, 1000);
        });
    }

    async verifyConnection() {
        try {
            // Check if tun interface exists
            const { stdout } = await execAsync('ip addr show tun0');
            if (!stdout.includes('state UP')) {
                throw new Error('TUN interface not up');
            }

            // Verify connectivity to VPN server
            await execAsync(`ping -c 1 ${this.config.serverAddress}`);
        } catch (error) {
            throw new Error(`VPN connection verification failed: ${error.message}`);
        }
    }

    async disconnect() {
        if (!this.connected) {
            return;
        }

        try {
            // Terminate OpenVPN process
            if (this.process) {
                this.process.kill();
                await new Promise((resolve) => {
                    this.process.on('exit', resolve);
                });
            }

            // Clean up TUN interface
            try {
                await execAsync('ip link delete tun0');
            } catch (error) {
                console.warn('Failed to clean up TUN interface:', error.message);
            }

            this.connected = false;
            this.process = null;
            console.log('VPN disconnected successfully');
        } catch (error) {
            console.error('VPN disconnection failed:', error);
            throw error;
        }
    }

    async getStatus() {
        if (!this.connected) {
            return { status: 'disconnected' };
        }

        try {
            const { stdout: ipAddr } = await execAsync('ip addr show tun0');
            const { stdout: routes } = await execAsync('ip route show dev tun0');
            const { stdout: stats } = await execAsync('cat /sys/class/net/tun0/statistics/rx_bytes');

            return {
                status: 'connected',
                interface: 'tun0',
                ipAddress: ipAddr.match(/inet\s+([^\s]+)/)?.[1] || 'unknown',
                routes: routes.split('\n').filter(Boolean),
                bytesReceived: parseInt(stats, 10)
            };
        } catch (error) {
            console.error('Failed to get VPN status:', error);
            return { status: 'error', error: error.message };
        }
    }
}

module.exports = VPNManager;