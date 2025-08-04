#!/bin/bash

# Zabbix API Configuration
ZABBIX_URL="http://your-zabbix-server/zabbix/api_jsonrpc.php"
USER="your-username"
PASSWORD="your-password"

# Time range configuration
START_TIME="2025-08-01 00:00:00"
END_TIME="2025-08-01 00:59:59"

# Convert timestamps (seconds, compatible with Zabbix 5.0.x)
TIME_FROM=$(date -d "$START_TIME" +%s)
TIME_TILL=$(date -d "$END_TIME" +%s)
echo "查询时间范围："
echo "  起始时间：$START_TIME -> $TIME_FROM"
echo "  结束时间：$END_TIME -> $TIME_TILL"

# Get authentication token
AUTH_RESPONSE=$(curl -sk -X POST -H "Content-Type: application/json-rpc" \
-d '{"jsonrpc":"2.0","method":"user.login","params":{"user":"'$USER'","password":"'$PASSWORD'"},"id":1}' \
$ZABBIX_URL)
AUTH_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r .result)

if [ "$AUTH_TOKEN" = "null" ] || [ -z "$AUTH_TOKEN" ]; then
  echo "认证失败：$(echo "$AUTH_RESPONSE" | jq .error.data)"
  exit 1
fi

echo "认证成功，Token: ${AUTH_TOKEN:0:20}..."

# Get events (problems) data
echo -e "\n获取事件数据..."
EVENTS_PAYLOAD=$(jq -n \
  --arg auth "$AUTH_TOKEN" \
  --argjson from "$TIME_FROM" \
  --argjson till "$TIME_TILL" \
  '{
    "jsonrpc": "2.0",
    "method": "event.get",
    "params": {
      "output": ["eventid", "name", "clock", "severity", "r_clock", "value", "objectid"],
      "selectHosts": ["host", "name"],
      "time_from": $from,
      "time_till": $till,
      "limit": 10000,
      "object": 0,
      "value": [1, 0],
      "sortfield": "eventid",
      "sortorder": "DESC"
    },
    "auth": $auth,
    "id": 2
  }')

EVENTS_RESPONSE=$(curl -sk -X POST -H "Content-Type: application/json-rpc" -d "$EVENTS_PAYLOAD" $ZABBIX_URL)

# Check for events API errors
if echo "$EVENTS_RESPONSE" | jq -e '.error' > /dev/null; then
  echo "获取事件失败：$(echo "$EVENTS_RESPONSE" | jq .error.data)"
  exit 1
fi

# Get actions execution data
echo "获取动作执行数据..."
ACTION_PAYLOAD=$(jq -n \
  --arg auth "$AUTH_TOKEN" \
  --argjson from "$TIME_FROM" \
  --argjson till "$TIME_TILL" \
  '{
    "jsonrpc": "2.0",
    "method": "action.get",
    "params": {
      "output": ["actionid", "name"],
      "selectExecutions": ["executionid", "eventid", "clock"],
      "filter": {
        "status": 0
      },
      "executions_time_from": $from,
      "executions_time_till": $till
    },
    "auth": $auth,
    "id": 3
  }')

ACTION_RESPONSE=$(curl -sk -X POST -H "Content-Type: application/json-rpc" -d "$ACTION_PAYLOAD" $ZABBIX_URL)

# Check for actions API errors
if echo "$ACTION_RESPONSE" | jq -e '.error' > /dev/null; then
  echo "获取动作失败：$(echo "$ACTION_RESPONSE" | jq .error.data)"
  exit 1
fi

# Process and combine the data
echo -e "\n处理和合并数据..."

# Create a temporary file for processing
TEMP_FILE=$(mktemp)
COMBINED_REPORT=$(mktemp)

# Extract events data and create a lookup structure
echo "$EVENTS_RESPONSE" | jq -r '.result[] | 
  @base64' | while read -r event_base64; do
    echo "$event_base64" | base64 -d | jq -r '
      {
        eventid: .eventid,
        event_name: .name,
        clock: .clock,
        severity: .severity,
        r_clock: .r_clock,
        value: .value,
        host: (.hosts[0].host // "Unknown"),
        host_name: (.hosts[0].name // "Unknown")
      }' >> "$TEMP_FILE"
done

# Create combined report header
echo "EventID,Event Name,Host,Host Name,Severity,Event Time,Recovery Time,Status,Action ID,Action Name,Execution Time" > "$COMBINED_REPORT"

# Process actions and match with events
echo "$ACTION_RESPONSE" | jq -r '.result[] as $action | 
  $action.executions[]? | 
  select(.eventid != null) |
  [$action.actionid, $action.name, .eventid, .clock] | 
  @csv' | while IFS=',' read -r actionid actionname eventid exec_clock; do
    
    # Remove quotes from CSV values
    actionid=$(echo "$actionid" | tr -d '"')
    actionname=$(echo "$actionname" | tr -d '"')
    eventid=$(echo "$eventid" | tr -d '"')
    exec_clock=$(echo "$exec_clock" | tr -d '"')
    
    # Find matching event data
    event_data=$(cat "$TEMP_FILE" | jq -r --arg eid "$eventid" 'select(.eventid == $eid)')
    
    if [ -n "$event_data" ]; then
        # Extract event details
        event_name=$(echo "$event_data" | jq -r '.event_name')
        host=$(echo "$event_data" | jq -r '.host')
        host_name=$(echo "$event_data" | jq -r '.host_name')
        severity=$(echo "$event_data" | jq -r '.severity')
        event_clock=$(echo "$event_data" | jq -r '.clock')
        recovery_clock=$(echo "$event_data" | jq -r '.r_clock')
        value=$(echo "$event_data" | jq -r '.value')
        
        # Convert timestamps to readable format
        event_time=$(date -d "@$event_clock" "+%Y-%m-%d %H:%M:%S")
        exec_time=$(date -d "@$exec_clock" "+%Y-%m-%d %H:%M:%S")
        
        if [ "$recovery_clock" != "0" ] && [ "$recovery_clock" != "null" ]; then
            recovery_time=$(date -d "@$recovery_clock" "+%Y-%m-%d %H:%M:%S")
        else
            recovery_time="N/A"
        fi
        
        # Determine status
        if [ "$value" == "1" ]; then
            status="PROBLEM"
        else
            status="OK"
        fi
        
        # Convert severity to text
        case $severity in
            0) severity_text="Not classified" ;;
            1) severity_text="Information" ;;
            2) severity_text="Warning" ;;
            3) severity_text="Average" ;;
            4) severity_text="High" ;;
            5) severity_text="Disaster" ;;
            *) severity_text="Unknown" ;;
        esac
        
        # Add to combined report
        echo "\"$eventid\",\"$event_name\",\"$host\",\"$host_name\",\"$severity_text\",\"$event_time\",\"$recovery_time\",\"$status\",\"$actionid\",\"$actionname\",\"$exec_time\"" >> "$COMBINED_REPORT"
    fi
done

# Also include events without actions
cat "$TEMP_FILE" | jq -r '. | 
  [.eventid, .event_name, .host, .host_name, .severity, .clock, .r_clock, .value] | 
  @csv' | while IFS=',' read -r eventid event_name host host_name severity event_clock recovery_clock value; do
    
    # Remove quotes
    eventid=$(echo "$eventid" | tr -d '"')
    
    # Check if this event already has actions
    if ! grep -q "^\"$eventid\"," "$COMBINED_REPORT"; then
        event_name=$(echo "$event_name" | tr -d '"')
        host=$(echo "$host" | tr -d '"')
        host_name=$(echo "$host_name" | tr -d '"')
        severity=$(echo "$severity" | tr -d '"')
        event_clock=$(echo "$event_clock" | tr -d '"')
        recovery_clock=$(echo "$recovery_clock" | tr -d '"')
        value=$(echo "$value" | tr -d '"')
        
        # Convert timestamps to readable format
        event_time=$(date -d "@$event_clock" "+%Y-%m-%d %H:%M:%S")
        
        if [ "$recovery_clock" != "0" ] && [ "$recovery_clock" != "null" ]; then
            recovery_time=$(date -d "@$recovery_clock" "+%Y-%m-%d %H:%M:%S")
        else
            recovery_time="N/A"
        fi
        
        # Determine status
        if [ "$value" == "1" ]; then
            status="PROBLEM"
        else
            status="OK"
        fi
        
        # Convert severity to text
        case $severity in
            0) severity_text="Not classified" ;;
            1) severity_text="Information" ;;
            2) severity_text="Warning" ;;
            3) severity_text="Average" ;;
            4) severity_text="High" ;;
            5) severity_text="Disaster" ;;
            *) severity_text="Unknown" ;;
        esac
        
        # Add to combined report (no action)
        echo "\"$eventid\",\"$event_name\",\"$host\",\"$host_name\",\"$severity_text\",\"$event_time\",\"$recovery_time\",\"$status\",\"N/A\",\"No Action\",\"N/A\"" >> "$COMBINED_REPORT"
    fi
done

# Display results
echo -e "\n=== 合并报告 ==="
echo "时间范围: $START_TIME 到 $END_TIME"
echo "总事件数: $(echo "$EVENTS_RESPONSE" | jq '.result | length')"
echo "有动作执行的事件数: $(grep -v '^EventID,' "$COMBINED_REPORT" | grep -v ',\"No Action\",' | wc -l)"
echo "无动作执行的事件数: $(grep -v '^EventID,' "$COMBINED_REPORT" | grep ',\"No Action\",' | wc -l)"

echo -e "\n=== 详细报告 ==="
cat "$COMBINED_REPORT" | column -t -s ','

# Save to file
OUTPUT_FILE="zabbix_combined_report_$(date +%Y%m%d_%H%M%S).csv"
cp "$COMBINED_REPORT" "$OUTPUT_FILE"
echo -e "\n报告已保存到: $OUTPUT_FILE"

# Cleanup temporary files
rm -f "$TEMP_FILE" "$COMBINED_REPORT"

# Logout
curl -sk -X POST -H "Content-Type: application/json-rpc" \
-d '{"jsonrpc":"2.0","method":"user.logout","params":[],"auth":"'$AUTH_TOKEN'","id":4}' \
$ZABBIX_URL > /dev/null

echo "完成！"