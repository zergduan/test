#!/usr/bin/env python3
"""
Zabbix API Combined Report Generator
Combines event (problem) data with action execution data for comprehensive reporting.
Compatible with Zabbix 5.0.4
"""

import json
import requests
import csv
import sys
from datetime import datetime
import urllib3

# Disable SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class ZabbixReporter:
    def __init__(self, zabbix_url, username, password):
        self.zabbix_url = zabbix_url
        self.username = username
        self.password = password
        self.auth_token = None
        self.session = requests.Session()
        self.session.verify = False  # Disable SSL verification
        
    def authenticate(self):
        """Authenticate with Zabbix API"""
        payload = {
            "jsonrpc": "2.0",
            "method": "user.login",
            "params": {
                "user": self.username,
                "password": self.password
            },
            "id": 1
        }
        
        try:
            response = self.session.post(self.zabbix_url, json=payload)
            response.raise_for_status()
            result = response.json()
            
            if 'error' in result:
                print(f"认证失败: {result['error']['data']}")
                return False
                
            self.auth_token = result['result']
            print(f"认证成功，Token: {self.auth_token[:20]}...")
            return True
            
        except Exception as e:
            print(f"认证请求失败: {e}")
            return False
    
    def logout(self):
        """Logout from Zabbix API"""
        if self.auth_token:
            payload = {
                "jsonrpc": "2.0",
                "method": "user.logout",
                "params": [],
                "auth": self.auth_token,
                "id": 4
            }
            try:
                self.session.post(self.zabbix_url, json=payload)
            except:
                pass  # Ignore logout errors
    
    def get_events(self, time_from, time_till):
        """Get events (problems) from Zabbix"""
        payload = {
            "jsonrpc": "2.0",
            "method": "event.get",
            "params": {
                "output": ["eventid", "name", "clock", "severity", "r_clock", "value", "objectid"],
                "selectHosts": ["host", "name"],
                "time_from": time_from,
                "time_till": time_till,
                "limit": 10000,
                "object": 0,
                "value": [1, 0],  # Both problem and ok events
                "sortfield": "eventid",
                "sortorder": "DESC"
            },
            "auth": self.auth_token,
            "id": 2
        }
        
        try:
            response = self.session.post(self.zabbix_url, json=payload)
            response.raise_for_status()
            result = response.json()
            
            if 'error' in result:
                print(f"获取事件失败: {result['error']['data']}")
                return None
                
            print(f"获取到 {len(result['result'])} 个事件")
            return result['result']
            
        except Exception as e:
            print(f"获取事件请求失败: {e}")
            return None
    
    def get_actions(self, time_from, time_till):
        """Get action executions from Zabbix"""
        payload = {
            "jsonrpc": "2.0",
            "method": "action.get",
            "params": {
                "output": ["actionid", "name"],
                "selectExecutions": ["executionid", "eventid", "clock"],
                "filter": {
                    "status": 0  # Only enabled actions
                },
                "executions_time_from": time_from,
                "executions_time_till": time_till
            },
            "auth": self.auth_token,
            "id": 3
        }
        
        try:
            response = self.session.post(self.zabbix_url, json=payload)
            response.raise_for_status()
            result = response.json()
            
            if 'error' in result:
                print(f"获取动作失败: {result['error']['data']}")
                return None
                
            # Count total executions
            total_executions = sum(len(action.get('executions', [])) for action in result['result'])
            print(f"获取到 {len(result['result'])} 个动作，共 {total_executions} 次执行")
            return result['result']
            
        except Exception as e:
            print(f"获取动作请求失败: {e}")
            return None
    
    def format_timestamp(self, timestamp):
        """Convert Unix timestamp to readable format"""
        if timestamp and timestamp != "0":
            return datetime.fromtimestamp(int(timestamp)).strftime("%Y-%m-%d %H:%M:%S")
        return "N/A"
    
    def get_severity_text(self, severity):
        """Convert severity number to text"""
        severity_map = {
            0: "Not classified",
            1: "Information", 
            2: "Warning",
            3: "Average",
            4: "High",
            5: "Disaster"
        }
        return severity_map.get(int(severity), "Unknown")
    
    def combine_data(self, events, actions):
        """Combine events and actions data"""
        combined_data = []
        
        # Create a mapping of eventid to action executions
        event_actions = {}
        for action in actions:
            for execution in action.get('executions', []):
                eventid = execution.get('eventid')
                if eventid:
                    if eventid not in event_actions:
                        event_actions[eventid] = []
                    event_actions[eventid].append({
                        'action_id': action['actionid'],
                        'action_name': action['name'],
                        'execution_time': self.format_timestamp(execution['clock'])
                    })
        
        # Process each event
        for event in events:
            eventid = event['eventid']
            
            # Basic event data
            event_data = {
                'eventid': eventid,
                'event_name': event['name'],
                'host': event['hosts'][0]['host'] if event['hosts'] else 'Unknown',
                'host_name': event['hosts'][0]['name'] if event['hosts'] else 'Unknown',
                'severity': self.get_severity_text(event['severity']),
                'event_time': self.format_timestamp(event['clock']),
                'recovery_time': self.format_timestamp(event['r_clock']) if event['r_clock'] != "0" else "N/A",
                'status': 'PROBLEM' if event['value'] == '1' else 'OK'
            }
            
            # Add action data if exists
            if eventid in event_actions:
                for action_exec in event_actions[eventid]:
                    combined_data.append({
                        **event_data,
                        'action_id': action_exec['action_id'],
                        'action_name': action_exec['action_name'], 
                        'execution_time': action_exec['execution_time']
                    })
            else:
                # Event without actions
                combined_data.append({
                    **event_data,
                    'action_id': 'N/A',
                    'action_name': 'No Action',
                    'execution_time': 'N/A'
                })
        
        return combined_data
    
    def save_to_csv(self, data, filename):
        """Save combined data to CSV file"""
        if not data:
            print("没有数据可保存")
            return False
            
        fieldnames = [
            'eventid', 'event_name', 'host', 'host_name', 'severity',
            'event_time', 'recovery_time', 'status', 'action_id', 
            'action_name', 'execution_time'
        ]
        
        try:
            with open(filename, 'w', newline='', encoding='utf-8') as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(data)
            return True
        except Exception as e:
            print(f"保存CSV文件失败: {e}")
            return False
    
    def print_summary(self, data):
        """Print summary statistics"""
        if not data:
            return
            
        total_events = len(set(item['eventid'] for item in data))
        events_with_actions = len([item for item in data if item['action_name'] != 'No Action'])
        events_without_actions = len([item for item in data if item['action_name'] == 'No Action'])
        
        print(f"\n=== 统计摘要 ===")
        print(f"总事件数: {total_events}")
        print(f"有动作执行的记录数: {events_with_actions}")
        print(f"无动作执行的事件数: {events_without_actions}")
        
        # Print sample data
        print(f"\n=== 前5条记录预览 ===")
        for i, item in enumerate(data[:5]):
            print(f"{i+1}. 事件ID: {item['eventid']}, 主机: {item['host']}, "
                  f"严重程度: {item['severity']}, 动作: {item['action_name']}")

def main():
    # Configuration
    ZABBIX_URL = "http://your-zabbix-server/zabbix/api_jsonrpc.php"
    USERNAME = "your-username"
    PASSWORD = "your-password"
    
    # Time range
    START_TIME = "2025-08-01 00:00:00"
    END_TIME = "2025-08-01 00:59:59"
    
    # Convert to timestamps
    time_from = int(datetime.strptime(START_TIME, "%Y-%m-%d %H:%M:%S").timestamp())
    time_till = int(datetime.strptime(END_TIME, "%Y-%m-%d %H:%M:%S").timestamp())
    
    print(f"查询时间范围: {START_TIME} 到 {END_TIME}")
    print(f"时间戳范围: {time_from} 到 {time_till}")
    
    # Initialize reporter
    reporter = ZabbixReporter(ZABBIX_URL, USERNAME, PASSWORD)
    
    try:
        # Authenticate
        if not reporter.authenticate():
            sys.exit(1)
        
        print("\n获取事件数据...")
        events = reporter.get_events(time_from, time_till)
        if events is None:
            sys.exit(1)
        
        print("获取动作执行数据...")
        actions = reporter.get_actions(time_from, time_till)
        if actions is None:
            sys.exit(1)
        
        print("合并数据...")
        combined_data = reporter.combine_data(events, actions)
        
        # Display summary
        reporter.print_summary(combined_data)
        
        # Save to CSV
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = f"zabbix_combined_report_{timestamp}.csv"
        
        if reporter.save_to_csv(combined_data, output_file):
            print(f"\n报告已保存到: {output_file}")
        
        print("完成！")
        
    except KeyboardInterrupt:
        print("\n用户中断操作")
    except Exception as e:
        print(f"程序执行错误: {e}")
    finally:
        reporter.logout()

if __name__ == "__main__":
    main()