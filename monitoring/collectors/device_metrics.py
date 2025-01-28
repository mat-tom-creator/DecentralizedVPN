#!/usr/bin/env python3
import time
import psutil
import json
import os
from prometheus_client import start_http_server, Gauge, Counter

# Define Prometheus metrics
device_status = Gauge('device_status', 'IoT device status', ['device_id'])
device_cpu = Gauge('device_cpu_usage', 'CPU usage percentage', ['device_id'])
device_memory = Gauge('device_memory_usage', 'Memory usage percentage', ['device_id'])
device_network = Gauge('device_network_usage', 'Network usage', ['device_id', 'direction'])
device_errors = Counter('device_error_count', 'Error count', ['device_id', 'error_type'])
device_uptime = Counter('device_uptime_seconds', 'Device uptime in seconds', ['device_id'])

class DeviceMetricsCollector:
    def __init__(self):
        self.device_id = os.getenv('DEVICE_ID', 'unknown')
        self.interface = "tun0"

    def collect_system_metrics(self):
        """Collect system-level metrics"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            device_cpu.labels(device_id=self.device_id).set(cpu_percent)

            # Memory usage
            memory = psutil.virtual_memory()
            device_memory.labels(device_id=self.device_id).set(memory.percent)

            # Network usage
            if hasattr(psutil, "net_io_counters"):
                net = psutil.net_io_counters(pernic=True).get(self.interface)
                if net:
                    device_network.labels(device_id=self.device_id, direction="in").set(net.bytes_recv)
                    device_network.labels(device_id=self.device_id, direction="out").set(net.bytes_sent)

        except Exception as e:
            print(f"Error collecting system metrics: {e}")
            device_errors.labels(device_id=self.device_id, error_type="system").inc()

    def update_status(self):
        """Update device status"""
        try:
            # Check VPN connection
            if os.path.exists(f"/sys/class/net/{self.interface}"):
                device_status.labels(device_id=self.device_id).set(1)  # Connected
            else:
                device_status.labels(device_id=self.device_id).set(0)  # Disconnected

        except Exception as e:
            print(f"Error updating status: {e}")
            device_errors.labels(device_id=self.device_id, error_type="status").inc()

    def collect_metrics(self):
        """Main metrics collection loop"""
        print(f"Starting metrics collection for device: {self.device_id}")
        start_time = time.time()

        while True:
            try:
                self.collect_system_metrics()
                self.update_status()

                # Update uptime
                uptime = time.time() - start_time
                device_uptime.labels(device_id=self.device_id).inc(15)  # 15-second interval

            except Exception as e:
                print(f"Error in metrics collection: {e}")
                device_errors.labels(device_id=self.device_id, error_type="collection").inc()

            time.sleep(15)

if __name__ == '__main__':
    # Start Prometheus HTTP server
    start_http_server(9104)

    # Create and start metrics collector
    collector = DeviceMetricsCollector()
    collector.collect_metrics()
