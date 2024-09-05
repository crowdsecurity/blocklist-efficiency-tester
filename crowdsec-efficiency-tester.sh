#!/bin/bash

echo "
✨✨✨ CrowdSec efficiency tester ✨✨✨
"

show_end() {
  echo "
If you have any questions or need help, please visit https://docs.crowdsec.net/u/troubleshooting/intro/ or join our community on https://crowdsec.net/community/
"
}

# Default value for max lines
MAX_LINES=100000

# Check required arguments
if [ -z "$LOG_FILE" ] || [ -z "$API_KEY" ]; then
  echo "Usage: LOG_FILE=/path/to/log/file.log API_KEY=your-api-key ./crowdsec-efficiency-tester.sh"
fi

# Validate token is not empty
if [ -z "$API_KEY" ]; then
  echo "Error: Api Key required"
  exit 1
fi

### Step 1: Extract and count IPs from the log file
echo -n "Extracting and counting IP addresses from logs..."
IPS_FILE="ips-from-logs.txt"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n $MAX_LINES | awk '{print $2","$1}' > "$IPS_FILE"
echo " ✅"

### Step 2: Download blocklist
echo -n "Downloading blocklist..."
BLOCKLIST_CONTENT=$(curl -X 'GET' -s \
  'https://admin.api.crowdsec.net/v1/blocklists/65ea27cc1d712714ef096abc/download' \
  -H 'accept: text/plain' \
  -H "x-api-key: $API_KEY")
echo " ✅"

### Step 3: Analyze each IP against the blocklist

# Initialize counters
TOTAL_REQUESTS=0
BLOCKLIST_HIT_COUNT=0
BLOCKLIST_HIT_REQUESTS=0
TOTAL_IPS=0

# Loop through each IP in the file
echo -n "Analyzing IPs against the blocklist..."
while IFS=, read -r ip count; do
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + count))
  TOTAL_IPS=$((TOTAL_IPS + 1))
  if echo "$BLOCKLIST_CONTENT" | grep -qx "$ip"; then
    BLOCKLIST_HIT_COUNT=$((BLOCKLIST_HIT_COUNT + 1))
    BLOCKLIST_HIT_REQUESTS=$((BLOCKLIST_HIT_REQUESTS + count))
  fi
done < "$IPS_FILE"

# Remove the temporary IPs file
rm "$IPS_FILE"
echo " ✅"

### Step 4: Efficiency calculations
IP_EFFICIENCY=$(bc <<< "scale=2; $BLOCKLIST_HIT_COUNT / $TOTAL_IPS * 100")
REQUEST_EFFICIENCY=$(bc <<< "scale=2; $BLOCKLIST_HIT_REQUESTS / $TOTAL_REQUESTS * 100")

### Step 5: Display summary
echo "
Blocklist hits (IPs)       : $IP_EFFICIENCY% ($BLOCKLIST_HIT_COUNT/$TOTAL_IPS)
Blocklist hits (Requests)  : $REQUEST_EFFICIENCY% ($BLOCKLIST_HIT_REQUESTS/$TOTAL_REQUESTS)"

show_end