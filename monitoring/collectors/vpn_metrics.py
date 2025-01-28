#!/usr/bin/env python3
import time
import psutil
import subprocess
import json
import os
from prometheus_client import start_http_server, Gauge, Counter

# Define Prometheus metrics
vpn_connections = Gauge('vpn_active_connections', 'Number of active VPN connections')
vpn_bandwidth_in = Counter('vpn_bandwidth_in_bytes', 'Incoming VPN bandwidth in bytes')
vpn_bandwidth_out = Counter('vpn_bandwidth_out_bytes', 'Outgoing VPN bandwidth in bytes')
vpn_latency = Gauge('vpn_latency_ms', 'VPN connection latency in milliseconds')
vpn_cpu_usage = Gauge('vpn_cpu_usage_percent', 'VPN process CPU usage percentage')
vpn_memory_usage = Gauge('vpn_memory_usage_bytes', 'VPN process memory usage in bytes')
vpn_error_count = Counter('vpn_error_count', 'Number of VPN errors encountered')
vpn_connection_duration = Gauge('vpn_connection_duration_seconds', 'Duration of VPN connections')

class VPNMetricsCollector:
    def __init__(self):
        self.vpn_log_path = "/var/log/openvpn/openvpn.log"
        self.status_path = "/var/log/openvpn/openvpn-status.log"
        self.interface = "tun0"

    def get_vpn_pid(self):
        """Get OpenVPN process ID"""
        try:
            result = subprocess.run(['pgrep', 'openvpn'], capture_output=True, text=True)
            if result.stdout:
                return int(result.stdout.strip())
            return None
        except Exception as e:
            print(f"Error getting VPN PID: {e}")
            vpn_error_count.inc()
            return None

    def get_connection_count(self):
        """Get number of active VPN connections"""
        try:
            if os.path.exists(self.status_path):
                with open(self.status_path, 'r') as f:
                    lines = f.readlines()
                    client_count = sum(1 for line in lines if line.startswith("CLIENT_LIST"))
                return client_count
            return 0
        except Exception as e:
            print(f"Error reading status file: {e}")
            vpn_error_count.inc()
            return 0

    def get_bandwidth_usage(self):
        """Get bandwidth usage statistics"""
        try:
            if not os.path.exists(f"/sys/class/net/{self.interface}"):
                return 0, 0

            with open(f"/sys/class/net/{self.interface}/statistics/rx_bytes", 'r') as f:
                rx_bytes = int(f.read().strip())
            with open(f"/sys/class/net/{self.interface}/statistics/tx_bytes", 'r') as f:
                tx_bytes = int(f.read().strip())

            return rx_bytes, tx_bytes
        except Exception as e:
            print(f"Error getting bandwidth usage: {e}")
            vpn_error_count.inc()
            return 0, 0

    def measure_latency(self):
        """Measure VPN connection latency"""
        try:
            result = subprocess.run(['ping', '-c', '1', '10.8.0.1'],
                                  capture_output=True, text=True)
            if result.returncode == 0:
                time_ms = float(result.stdout.split('time=')[-1].split()[0])
                return time_ms
            return 0
        except Exception as e:
            print(f"Error measuring latency: {e}")
            vpn_error_count.inc()
            return 0

    def get_resource_usage(self, pid):
        """Get CPU and memory usage for VPN process"""
        try:
            if pid is None:
                return 0, 0

            process = psutil.Process(pid)
            cpu_percent = process.cpu_percent(interval=1)
            memory_bytes = process.memory_info().rss
            return cpu_percent, memory_bytes
        except Exception as e:
            print(f"Error getting resource usage: {e}")
            vpn_error_count.inc()
            return 0, 0

    def collect_metrics(self):
        """Main metrics collection loop"""
        print("Starting VPN metrics collection...")
        while True:
            try:
                # Get VPN process ID
                vpn_pid = self.get_vpn_pid()

                # Collect metrics
                connection_count = self.get_connection_count()
                rx_bytes, tx_bytes = self.get_bandwidth_usage()
                latency = self.measure_latency()
                cpu_usage, memory_usage = self.get_resource_usage(vpn_pid)

                # Update Prometheus metrics
                vpn_connections.set(connection_count)
                vpn_bandwidth_in.inc(rx_bytes)
                vpn_bandwidth_out.inc(tx_bytes)
                vpn_latency.set(latency)
                vpn_cpu_usage.set(cpu_usage)
                vpn_memory_usage.set(memory_usage)

                # Check VPN status and update duration
                if connection_count > 0:
                    vpn_connection_duration.inc(15)  # 15-second collection interval
            except Exception as e:
                print(f"Error in metrics collection: {e}")
                vpn_error_count.inc()

            time.sleep(15)

if __name__ == '__main__':
    # Start Prometheus HTTP server
    start_http_server(9103)

    # Create and start metrics collector
    collector = VPNMetricsCollector()
    collector.collect_metrics()
