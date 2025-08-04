# Zabbix Combined Report Generator

This project provides scripts to combine Zabbix event (problem) data with action execution data for comprehensive reporting. Compatible with Zabbix 5.0.4.

## Features

- Retrieves events (problems and OK states) from Zabbix API
- Retrieves action execution data from Zabbix API
- Combines both datasets into a unified report
- Exports results to CSV format
- Handles events with and without associated actions
- Provides summary statistics

## Files

- `zabbix_combined_report.sh` - Bash script version
- `zabbix_combined_report.py` - Python script version (recommended)
- `requirements.txt` - Python dependencies

## Configuration

Before running either script, you need to update the configuration variables:

### Bash Script (`zabbix_combined_report.sh`)
```bash
ZABBIX_URL="http://your-zabbix-server/zabbix/api_jsonrpc.php"
USER="your-username"
PASSWORD="your-password"
START_TIME="2025-08-01 00:00:00"
END_TIME="2025-08-01 00:59:59"
```

### Python Script (`zabbix_combined_report.py`)
```python
ZABBIX_URL = "http://your-zabbix-server/zabbix/api_jsonrpc.php"
USERNAME = "your-username"
PASSWORD = "your-password"
START_TIME = "2025-08-01 00:00:00"
END_TIME = "2025-08-01 00:59:59"
```

## Prerequisites

### For Bash Script
- `curl` command
- `jq` JSON processor
- `date` command
- `base64` command

Install dependencies on Ubuntu/Debian:
```bash
sudo apt-get install curl jq coreutils
```

### For Python Script
- Python 3.6 or higher
- Required Python packages (install with pip)

```bash
pip install -r requirements.txt
```

## Usage

### Running the Bash Script
```bash
./zabbix_combined_report.sh
```

### Running the Python Script
```bash
python3 zabbix_combined_report.py
# or
./zabbix_combined_report.py
```

## Output

Both scripts generate:

1. **Console output** with:
   - Authentication status
   - Data retrieval progress
   - Summary statistics
   - Sample records preview

2. **CSV file** with combined data:
   - Filename format: `zabbix_combined_report_YYYYMMDD_HHMMSS.csv`
   - Contains all events with their associated actions (if any)

## CSV Columns

| Column | Description |
|--------|-------------|
| EventID | Zabbix event identifier |
| Event Name | Problem/trigger name |
| Host | Host technical name |
| Host Name | Host display name |
| Severity | Problem severity (Not classified, Information, Warning, Average, High, Disaster) |
| Event Time | When the event occurred |
| Recovery Time | When the problem was resolved (if applicable) |
| Status | PROBLEM or OK |
| Action ID | Zabbix action identifier |
| Action Name | Action name or "No Action" |
| Execution Time | When the action was executed |

## API Compatibility

These scripts are specifically designed for Zabbix 5.0.4 and use:

- `event.get` method to retrieve events
- `action.get` method with `selectExecutions` to retrieve action data
- `user.login`/`user.logout` for authentication

## Error Handling

- Authentication failures are reported with error details
- API errors are caught and displayed
- Network issues are handled gracefully
- Temporary files are cleaned up automatically

## Security Notes

- SSL certificate verification is disabled for self-signed certificates
- Consider using environment variables for credentials in production
- Ensure proper firewall rules for API access
- Use dedicated API user with minimal required permissions

## Troubleshooting

1. **Authentication fails**: Check URL, username, and password
2. **No data returned**: Verify time range and permissions
3. **jq command not found**: Install jq package
4. **Python import errors**: Install required packages with pip

## Example Output

```
查询时间范围: 2025-08-01 00:00:00 到 2025-08-01 00:59:59
认证成功，Token: abcd1234567890123456...
获取到 15 个事件
获取到 3 个动作，共 8 次执行

=== 统计摘要 ===
总事件数: 15
有动作执行的记录数: 8
无动作执行的事件数: 7

报告已保存到: zabbix_combined_report_20250115_143022.csv
完成！
```