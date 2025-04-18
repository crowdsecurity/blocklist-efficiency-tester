#!/bin/bash

# Usage:
# API_KEY=INSERT_YOUR_KEY LOG_FILE=./nginx-access-sample.log /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crowdsecurity/blocklist-efficiency-tester/main/crowdsec-efficiency-tester.sh)"

echo "
✨✨✨ CrowdSec efficiency tester ✨✨✨
"

show_end() {
  echo "
Typical efficiency observed for the CrowdSec Intelligence Blocklist is 20 to 50%.
If you have less than 10% efficiency, you may want to check the following:
* The IPs in your logs are from ingress on an exposed service (website, api, ssh, etc.)
* The IPs in your logs are not from a CDN but properly x-forwarded-for

If you want to check what CrowdSec knows about an attacker IP visit https://app.crowdsec.net/cti/

If you have any questions about our blocklists API, please visit https://doc.crowdsec.net/u/service_api/getting_started or join our community on https://crowdsec.net/community/
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

### Step 1: Extract and count IPs from the log file
  # Validate PARSED_IPS_FILE or LOG_FILE has been provided
if [ -z "$PARSED_IPS_FILE" ]; then
  if [ -z "$LOG_FILE" ]; then
    read -p "Path to your log file: " LOG_FILE
  fi
  if [ -z "$LOG_FILE" ]; then
    echo "Error: Either LOG_FILE or PARSED_IPS_FILE must be provided"
    exit 1
  fi
  echo -n "Extracting and counting IP addresses from logs..."
  PARSED_IPS_FILE="ips-from-logs.txt"
  CLEAR_PARSED_IPS_FILE="true"
  awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n $MAX_LINES | awk '{print $2","$1}' > "$PARSED_IPS_FILE"
  echo " ✅"
else
  echo "Using pre-parsed IPs file: $PARSED_IPS_FILE"
  echo "cleaning bad return carriage characters from $PARSED_IPS_FILE"
  sed -i 's/\r$//' "$PARSED_IPS_FILE"
fi

# Default blocklist ID(s)
DEFAULT_BLOCKLIST_ID="65ea27cc1d712714ef096abc"
BLOCKLIST_ID="${BLOCKLIST_ID:-$DEFAULT_BLOCKLIST_ID}"

### Step 2: Download blocklist
echo -n "Downloading blocklist..."
BLOCKLIST_CONTENT=""
IFS=',' read -ra BLOCKLIST_IDS <<< "$BLOCKLIST_ID"
for id in "${BLOCKLIST_IDS[@]}"; do
  echo -n "Fetching blocklist ID $id..."
  CONTENT=$(curl -X 'GET' -s \
    "https://admin.api.crowdsec.net/v1/blocklists/${id}/download" \
    -H 'accept: text/plain' \
    -H "x-api-key: $API_KEY")
  if [ -z "$CONTENT" ] || [ "$CONTENT" == '{"message":"Forbidden"}' ]; then
    echo " ❌"
    echo "Error: Unable to download blocklist ID $id. Please check your API key or ID."
    exit 1
  fi
  BLOCKLIST_CONTENT="${BLOCKLIST_CONTENT}"$'\n'"${CONTENT}"
  echo " ✅"
done

### Step 3: Analyzing parsed IPs against the blocklist
# Build an associative array from the blocklist for fast lookup
declare -A blocklist_ips
while IFS= read -r ip; do
  if [[ -n "$ip" ]]; then
    blocklist_ips["$ip"]=1
  fi
done <<< "$BLOCKLIST_CONTENT"

# Initialize counters for the report
TOTAL_DISTINCT_IPS_IN_LOGS=0
TOTAL_REQUESTS_IN_LOGS=0
BLOCKLIST_IP_HITS=0
BLOCKLIST_REQUESTS_HITS=0
BAD_IPS=""

# Process the pre-parsed IP file line by line
while IFS=, read -r ip count; do
  TOTAL_REQUESTS_IN_LOGS=$((TOTAL_REQUESTS_IN_LOGS + count))
  TOTAL_DISTINCT_IPS_IN_LOGS=$((TOTAL_DISTINCT_IPS_IN_LOGS + 1))
  
  # Instead of grepping, check if the IP exists in the associative array
  if [[ ${blocklist_ips[$ip]} ]]; then
    BLOCKLIST_IP_HITS=$((BLOCKLIST_IP_HITS + 1))
    BLOCKLIST_REQUESTS_HITS=$((BLOCKLIST_REQUESTS_HITS + count))
    BAD_IPS+="${ip}, ${count}\n"
  fi
done < "$PARSED_IPS_FILE"

if [ -n "$CLEAR_PARSED_IPS_FILE" ]; then
  rm "$PARSED_IPS_FILE"
fi
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