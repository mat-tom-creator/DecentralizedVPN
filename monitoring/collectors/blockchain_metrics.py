#!/usr/bin/env python3
import time
import psutil
import subprocess
import json
import os
from prometheus_client import start_http_server, Gauge, Counter

# Define Prometheus metrics
block_height = Gauge('blockchain_height', 'Current blockchain height')
peer_count = Gauge('blockchain_peer_count', 'Number of connected peers')
tx_throughput = Counter('blockchain_tx_throughput', 'Transaction throughput')
chain_latency = Gauge('blockchain_latency', 'Block propagation latency')
resource_usage = Gauge('blockchain_resource_usage', 'Resource usage by blockchain node', ['resource_type'])
error_count = Counter('blockchain_error_count', 'Number of blockchain errors')

class BlockchainMetricsCollector:
    def __init__(self):
        self.fabric_home = "/home/mathew/Documents/dvpn-iot/fabric-samples/config"
        self.peer_address = "localhost:7051"
        self.msp_path = "/home/mathew/Documents/dvpn-iot/fabric-samples/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/msp"
        self.msp_id = "Org1MSP"

    def get_env(self):
        """Get environment variables needed for Fabric commands"""
        return {
            **os.environ,
            'PATH': f"{os.environ.get('PATH')}:/home/mathew/Documents/dvpn-iot/fabric-samples/bin",
            'FABRIC_CFG_PATH': self.fabric_home,
            'CORE_PEER_ADDRESS': self.peer_address,
            'CORE_PEER_LOCALMSPID': self.msp_id,
            'CORE_PEER_MSPCONFIGPATH': self.msp_path
        }

    def get_block_height(self):
        """Get current blockchain height"""
        try:
            which_peer = subprocess.run(['which', 'peer'], capture_output=True, env=self.get_env())
            if which_peer.returncode != 0:
                print("Warning: Fabric peer command not found")
                return 0
                
            cmd = "peer channel getinfo -c dvpnchannel"
            result = subprocess.run(cmd.split(), capture_output=True, text=True, env=self.get_env())
            if result.returncode == 0:
                height = int(result.stdout.strip())
                block_height.set(height)
                return height
            return 0
        except Exception as e:
            print(f"Error getting block height: {e}")
            error_count.inc()
            return 0

    def get_peer_count(self):
        """Get number of connected peers"""
        try:
            which_peer = subprocess.run(['which', 'peer'], capture_output=True, env=self.get_env())
            if which_peer.returncode != 0:
                print("Warning: Fabric peer command not found")
                return 0
                
            cmd = "peer node status"
            result = subprocess.run(cmd.split(), capture_output=True, text=True, env=self.get_env())
            if result.returncode == 0 and result.stdout.strip():
                try:
                    status = json.loads(result.stdout)
                    count = len(status.get('peers', []))
                    peer_count.set(count)
                    return count
                except json.JSONDecodeError as e:
                    print(f"Error parsing peer status JSON: {e}")
                    print(f"Raw output: {result.stdout}")
                    return 0
            else:
                print(f"Error running peer command: {result.stderr}")
                return 0
        except Exception as e:
            print(f"Error getting peer count: {e}")
            error_count.inc()
            return 0

    def get_resource_usage(self):
        """Get resource usage metrics"""
        try:
            for proc in psutil.process_iter(['name', 'cmdline']):
                if 'peer node start' in ' '.join(proc.info['cmdline']):
                    cpu_percent = proc.cpu_percent(interval=1)
                    memory_percent = proc.memory_percent()

                    resource_usage.labels('cpu').set(cpu_percent)
                    resource_usage.labels('memory').set(memory_percent)
                    return cpu_percent, memory_percent
            return 0, 0
        except Exception as e:
            print(f"Error getting resource usage: {e}")
            error_count.inc()
            return 0, 0

    def measure_latency(self):
        """Measure block propagation latency"""
        try:
            cmd = "peer channel fetch newest"
            result = subprocess.run(cmd.split(), capture_output=True, text=True, env=self.get_env())
            if result.returncode == 0:
                block_data = json.loads(result.stdout)
                creation_time = block_data['data']['data'][0]['payload']['header']['channel_header']['timestamp']
                current_time = time.time()
                latency = current_time - creation_time
                chain_latency.set(latency)
                return latency
            return 0
        except Exception as e:
            print(f"Error measuring latency: {e}")
            error_count.inc()
            return 0

    def collect_metrics(self):
        """Main metrics collection loop"""
        print("Starting blockchain metrics collection...")
        print(f"Using Fabric home: {self.fabric_home}")
        print(f"Using peer address: {self.peer_address}")
        
        # Check if peer command exists
        which_peer = subprocess.run(['which', 'peer'], capture_output=True, env=self.get_env())
        if which_peer.returncode != 0:
            print("Warning: Fabric peer command not found. Please ensure Hyperledger Fabric is installed.")
        
        while True:
            try:
                height = self.get_block_height()
                print(f"Current block height: {height}")
                
                count = self.get_peer_count()
                print(f"Connected peers: {count}")
                
                cpu, mem = self.get_resource_usage()
                print(f"Resource usage - CPU: {cpu}%, Memory: {mem}%")
                
                latency = self.measure_latency()
                print(f"Block latency: {latency}")
                
            except Exception as e:
                print(f"Error in metrics collection: {e}")
                error_count.inc()

            time.sleep(15)

if __name__ == '__main__':
    # Start Prometheus HTTP server
    start_http_server(9106)

    # Create and start metrics collector
    collector = BlockchainMetricsCollector()
    collector.collect_metrics()