#!/usr/bin/env python3
import time
import json
import logging
from prometheus_client import start_http_server, Gauge, Counter, Summary
import psutil
import os
import asyncio
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    filename='/opt/dvpn-iot/logs/monitoring/metrics_processor.log'
)
logger = logging.getLogger('MetricsProcessor')

# Define Prometheus metrics
SYSTEM_METRICS = {
    'cpu': Gauge('system_cpu_usage', 'System CPU usage percentage'),
    'memory': Gauge('system_memory_usage', 'System memory usage percentage'),
    'disk': Gauge('system_disk_usage', 'System disk usage percentage'),
    'network_in': Counter('system_network_in_bytes', 'Incoming network traffic in bytes'),
    'network_out': Counter('system_network_out_bytes', 'Outgoing network traffic in bytes')
}

VPN_METRICS = {
    'connections': Gauge('vpn_active_connections', 'Number of active VPN connections'),
    'bandwidth': Gauge('vpn_bandwidth_usage', 'VPN bandwidth usage', ['direction']),
    'latency': Summary('vpn_latency_seconds', 'VPN connection latency')
}

BLOCKCHAIN_METRICS = {
    'block_height': Gauge('blockchain_height', 'Current blockchain height'),
    'tx_count': Counter('blockchain_transactions_total', 'Total number of blockchain transactions'),
    'peer_count': Gauge('blockchain_peer_count', 'Number of connected blockchain peers'),
    'chain_latency': Gauge('blockchain_latency', 'Block propagation latency')
}

class MetricsProcessor:
    def __init__(self, config_path='/opt/dvpn-iot/monitoring/config/metrics.json'):
        self.config = self.load_config(config_path)
        self.metrics_cache = {}
        self.last_update = {}
        
    def load_config(self, config_path):
        """Load metrics configuration from JSON file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return {
                'collection_interval': 15,
                'retention_days': 7,
                'alert_thresholds': {
                    'cpu': 80,
                    'memory': 80,
                    'disk': 90,
                    'latency': 1000
                }
            }

    async def collect_system_metrics(self):
        """Collect system-level metrics"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            SYSTEM_METRICS['cpu'].set(cpu_percent)

            # Memory usage
            memory = psutil.virtual_memory()
            SYSTEM_METRICS['memory'].set(memory.percent)

            # Disk usage
            disk = psutil.disk_usage('/')
            SYSTEM_METRICS['disk'].set(disk.percent)

            # Network usage
            net = psutil.net_io_counters()
            SYSTEM_METRICS['network_in'].inc(net.bytes_recv)
            SYSTEM_METRICS['network_out'].inc(net.bytes_sent)

            return {
                'cpu': cpu_percent,
                'memory': memory.percent,
                'disk': disk.percent,
                'network': {
                    'in': net.bytes_recv,
                    'out': net.bytes_sent
                }
            }
        except Exception as e:
            logger.error(f"Error collecting system metrics: {e}")
            return None

    async def collect_vpn_metrics(self):
        """Collect VPN-related metrics"""
        try:
            # Read VPN status file
            vpn_status_path = '/var/log/openvpn/openvpn-status.log'
            if not os.path.exists(vpn_status_path):
                return None

            with open(vpn_status_path, 'r') as f:
                status_content = f.read()

            # Parse VPN connections
            connections = len([line for line in status_content.split('\n') 
                            if line.startswith('CLIENT_LIST')])
            VPN_METRICS['connections'].set(connections)

            # Measure VPN bandwidth
            tun0_stats = psutil.net_io_counters(pernic=True).get('tun0')
            if tun0_stats:
                VPN_METRICS['bandwidth'].labels('in').set(tun0_stats.bytes_recv)
                VPN_METRICS['bandwidth'].labels('out').set(tun0_stats.bytes_sent)

            return {
                'connections': connections,
                'bandwidth': {
                    'in': tun0_stats.bytes_recv if tun0_stats else 0,
                    'out': tun0_stats.bytes_sent if tun0_stats else 0
                }
            }
        except Exception as e:
            logger.error(f"Error collecting VPN metrics: {e}")
            return None

    async def collect_blockchain_metrics(self):
        """Collect blockchain-related metrics"""
        try:
            # These values would typically come from your blockchain node
            # This is a placeholder implementation
            block_height = 0
            tx_count = 0
            peer_count = 0
            chain_latency = 0

            BLOCKCHAIN_METRICS['block_height'].set(block_height)
            BLOCKCHAIN_METRICS['tx_count'].inc()
            BLOCKCHAIN_METRICS['peer_count'].set(peer_count)
            BLOCKCHAIN_METRICS['chain_latency'].set(chain_latency)

            return {
                'block_height': block_height,
                'tx_count': tx_count,
                'peer_count': peer_count,
                'chain_latency': chain_latency
            }
        except Exception as e:
            logger.error(f"Error collecting blockchain metrics: {e}")
            return None

    def check_alerts(self, metrics):
        """Check metrics against alert thresholds"""
        alerts = []
        thresholds = self.config['alert_thresholds']

        if metrics.get('system'):
            system = metrics['system']
            if system['cpu'] > thresholds['cpu']:
                alerts.append({
                    'level': 'warning',
                    'message': f'High CPU usage: {system["cpu"]}%'
                })
            if system['memory'] > thresholds['memory']:
                alerts.append({
                    'level': 'warning',
                    'message': f'High memory usage: {system["memory"]}%'
                })
            if system['disk'] > thresholds['disk']:
                alerts.append({
                    'level': 'critical',
                    'message': f'High disk usage: {system["disk"]}%'
                })

        return alerts

    async def process_metrics(self):
        """Main metrics processing loop"""
        logger.info("Starting metrics processing...")
        
        while True:
            try:
                # Collect all metrics
                metrics = {
                    'system': await self.collect_system_metrics(),
                    'vpn': await self.collect_vpn_metrics(),
                    'blockchain': await self.collect_blockchain_metrics(),
                    'timestamp': datetime.now().isoformat()
                }

                # Check for alerts
                alerts = self.check_alerts(metrics)
                if alerts:
                    logger.warning(f"Alerts detected: {alerts}")

                # Cache metrics
                self.metrics_cache[metrics['timestamp']] = metrics

                # Clean up old metrics
                self.cleanup_old_metrics()

            except Exception as e:
                logger.error(f"Error in metrics processing: {e}")

            await asyncio.sleep(self.config['collection_interval'])

    def cleanup_old_metrics(self):
        """Remove metrics older than retention period"""
        retention_seconds = self.config['retention_days'] * 24 * 3600
        current_time = datetime.now()

        for timestamp in list(self.metrics_cache.keys()):
            metric_time = datetime.fromisoformat(timestamp)
            if (current_time - metric_time).total_seconds() > retention_seconds:
                del self.metrics_cache[timestamp]

    def get_metrics_summary(self):
        """Generate summary of collected metrics"""
        return {
            'total_metrics': len(self.metrics_cache),
            'latest_timestamp': max(self.metrics_cache.keys()) if self.metrics_cache else None,
            'metrics_size': len(json.dumps(self.metrics_cache))
        }

async def main():
    # Start Prometheus HTTP server
    start_http_server(9105)
    
    # Create and start metrics processor
    processor = MetricsProcessor()
    await processor.process_metrics()

if __name__ == '__main__':
    asyncio.run(main())