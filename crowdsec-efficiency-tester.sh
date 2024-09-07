#!/bin/bash

# Usage:
# API_KEY=INSERT_YOUR_KEY LOG_FILE=./nginx-access-sample.log /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crowdsecurity/blocklist-efficiency-tester/main/crowdsec-efficiency-tester.sh)"

echo "
✨✨✨ CrowdSec efficiency tester ✨✨✨
"

show_end() {
  echo "
Typical efficiency observed is 20 to 50%.
If you have less than 10% efficiency, you may want to check the following:
* The IPs in your logs are from ingress on an exposed service (website, api, ssh, etc.)
* The IPs in your logs are not from a CDN but properly x-forwarded-for

If you want to check what CrowdSec knows about an attacker IP visit https://app.crowdsec.net/cti/

If you have any questions or need help, please visit https://docs.crowdsec.net/u/troubleshooting/intro/ or join our community on https://crowdsec.net/community/
"
}

# Max lines to process from the log file (here for performance reasons - Change it at your convenience)
MAX_LINES=100000
TOP_ATTACKERS_DISPLAY=10

# Check required arguments
if [ -z "$LOG_FILE" ] || [ -z "$API_KEY" ]; then
  echo "Usage: LOG_FILE=/path/to/log/file.log API_KEY=your-api-key ./crowdsec-efficiency-tester.sh"
fi

# Validate API Key has been provided
if [ -z "$API_KEY" ]; then
  read -p "Enter your API key: " API_KEY
fi
if [ -z "$API_KEY" ]; then
  echo "Error: Api Key required"
  exit 1
fi

# Validate LOG_FILE has been provided
if [ -z "$LOG_FILE" ]; then
  read -p "Path to your log file: " LOG_FILE
fi
if [ -z "$LOG_FILE" ]; then
  echo "Error: log file is required"
  exit 1
fi

### Step 1: Extract and count IPs from the log file
echo -n "Extracting and counting IP addresses from logs..."
PARSED_IPS_FILE="ips-from-logs.txt"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n $MAX_LINES | awk '{print $2","$1}' > "$PARSED_IPS_FILE"
echo " ✅"

### Step 2: Download blocklist
echo -n "Downloading blocklist..."
BLOCKLIST_CONTENT=$(curl -X 'GET' -s \
  'https://admin.api.crowdsec.net/v1/blocklists/65ea27cc1d712714ef096abc/download' \
  -H 'accept: text/plain' \
  -H "x-api-key: $API_KEY")
echo " ✅"

### Step 3: Analyzing parsed IPs against the blocklist

# Initialize counters for report
TOTAL_DISTINCT_IPS_IN_LOGS=0
TOTAL_REQUESTS_IN_LOGS=0
BLOCKLIST_IP_HITS=0
BLOCKLIST_REQUESTS_HITS=0
BAD_IPS=""
# Count blocklist hits
echo -n "Analyzing IPs against the blocklist..."
while IFS=, read -r ip count; do
  TOTAL_REQUESTS_IN_LOGS=$((TOTAL_REQUESTS_IN_LOGS + count))
  TOTAL_DISTINCT_IPS_IN_LOGS=$((TOTAL_DISTINCT_IPS_IN_LOGS + 1))
  if echo "$BLOCKLIST_CONTENT" | grep -qx "$ip"; then
    BLOCKLIST_IP_HITS=$((BLOCKLIST_IP_HITS + 1))
    BLOCKLIST_REQUESTS_HITS=$((BLOCKLIST_REQUESTS_HITS + count))

     # Concatenate the IP and count to the HIT_IPS string
    BAD_IPS="${BAD_IPS}${ip}, ${count}\n"
  fi
done < "$PARSED_IPS_FILE"

# Remove the temporary IPs file
rm "$PARSED_IPS_FILE"
echo " ✅"

### Step 4: Efficiency calculations
LC_NUMERIC=C
IP_EFFICIENCY=$(bc <<< "scale=4; $BLOCKLIST_IP_HITS / $TOTAL_DISTINCT_IPS_IN_LOGS * 100")
REQUEST_EFFICIENCY=$(bc <<< "scale=4; $BLOCKLIST_REQUESTS_HITS / $TOTAL_REQUESTS_IN_LOGS * 100")
FORMATTED_IP_EFFICIENCY=$(printf "%.2f" $IP_EFFICIENCY)
FORMATTED_REQUEST_EFFICIENCY=$(printf "%.2f" $REQUEST_EFFICIENCY)

### Step 5: Display summary
# Hits ratio
echo "

=== Summary ===
Blocklist hits (IPs)       : $FORMATTED_IP_EFFICIENCY% ($BLOCKLIST_IP_HITS/$TOTAL_DISTINCT_IPS_IN_LOGS)
Blocklist hits (Requests)  : $FORMATTED_REQUEST_EFFICIENCY% ($BLOCKLIST_REQUESTS_HITS/$TOTAL_REQUESTS_IN_LOGS)"

# Top 10 Attackers IPs
echo "
TOP $TOP_ATTACKERS_DISPLAY IPs in the blocklist:
------------------------------------------------"

printf "%-20s | %-5s\n" "IP Address" "Count"
printf "%-20s | %-5s\n" "--------------------" "-----"
echo -e $BAD_IPS | sort -t',' -k2,2nr | head -n$TOP_ATTACKERS_DISPLAY | awk -F',' '{ printf "%-20s | %-5s\n", $1, $2 }'

show_end