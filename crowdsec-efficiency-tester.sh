#!/bin/bash

# Function to fetch blocklist with basic auth support
fetch_blocklist() {
  local url="$1"
  local username="$2"
  local password="$3"

  if [ -n "$username" ] && [ -n "$password" ]; then
    # Use basic auth
    curl -s -u "${username}:${password}" "$url"
  else
    # No auth
    curl -s "$url"
  fi
}

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

# Load .env file early if it exists (to check for BLOCKLIST_URL)
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

# Read arguments
LOG_FILE="$1"

# Check required arguments
if [ -z "$LOG_FILE" ] || [ -z "$BLOCKLIST_URL" ]; then
  echo "Usage: ./crowdsec-efficiency-tester.sh /path/to/log/file.log"
  echo "   Or: BLOCKLIST_URL=https://... [BLOCKLIST_USERNAME=user] [BLOCKLIST_PASSWORD=pass] ./crowdsec-efficiency-tester.sh /path/to/log/file.log"
  echo "---"
fi

# Validate API Key has been provided (only if not using BLOCKLIST_URL)
if [ -z "$BLOCKLIST_URL" ]; then
  echo "Error: BLOCKLIST_URL must be provided"
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

### Step 2: Download blocklist
echo -n "Downloading blocklist..."
BLOCKLIST_CONTENT=""
CACHE_FILE=".cache"
BLOCKLIST_CACHE_FILE="latestBlocklistContent.ips"
FORCE_REFRESH=false

# Check for -f flag for force refresh
if [[ "$*" == *"-f"* ]]; then
  FORCE_REFRESH=true
  echo "(forced refresh) "
fi

# Check if BLOCKLIST_URL is provided (new method with basic auth)
if [ -n "$BLOCKLIST_URL" ]; then
  # Calculate MD5 of the URL
  URL_MD5=$(echo -n "$BLOCKLIST_URL" | md5sum | awk '{print $1}')
  CURRENT_TIME=$(date +%s)
  USE_CACHE=false

  # Check if cache exists and is valid
  if [ -f "$CACHE_FILE" ] && [ -f "$BLOCKLIST_CACHE_FILE" ] && [ "$FORCE_REFRESH" = false ]; then
    # Read cache file
    CACHED_URL_MD5=$(grep "^URL_MD5=" "$CACHE_FILE" | cut -d'=' -f2)
    CACHED_TIMESTAMP=$(grep "^TIMESTAMP=" "$CACHE_FILE" | cut -d'=' -f2)

    # Check if URL matches and cache is less than 10 minutes old (600 seconds)
    if [ "$CACHED_URL_MD5" = "$URL_MD5" ]; then
      TIME_DIFF=$((CURRENT_TIME - CACHED_TIMESTAMP))
      if [ $TIME_DIFF -lt 600 ]; then
        USE_CACHE=true
        echo -n "Using cached blocklist ($(($TIME_DIFF / 60))m old)..."
      fi
    fi
  fi

  if [ "$USE_CACHE" = true ]; then
    # Load from cache
    CONTENT=$(cat "$BLOCKLIST_CACHE_FILE")
    IP_COUNT=$(echo "$CONTENT" | grep -v '^$' | sort -u | wc -l | xargs)
    echo " ✅ ($IP_COUNT IPs)"
  else
    # Fetch fresh content
    echo -n "Fetching blocklist from custom URL..."

    # Use environment variables as defaults, but allow override
    CONTENT=$(fetch_blocklist "$BLOCKLIST_URL" "$BLOCKLIST_USERNAME" "$BLOCKLIST_PASSWORD")

    if [ -z "$CONTENT" ] || [ "$CONTENT" == '{"message":"Forbidden"}' ] || [[ "$CONTENT" == *"error"* ]]; then
      echo " ❌"
      echo "Error: Unable to download blocklist from $BLOCKLIST_URL"
      exit 1
    fi

    IP_COUNT=$(echo "$CONTENT" | grep -v '^$' | sort -u | wc -l | xargs)
    echo " ✅ ($IP_COUNT IPs)"

    # Save to cache
    echo "$CONTENT" > "$BLOCKLIST_CACHE_FILE"
    cat > "$CACHE_FILE" << EOF
URL_MD5=$URL_MD5
TIMESTAMP=$CURRENT_TIME
URL=$BLOCKLIST_URL
EOF
  fi

  BLOCKLIST_CONTENT="$CONTENT"
fi

# Ensure the blocklist content unicity
BLOCKLIST_CONTENT=$(echo "$BLOCKLIST_CONTENT" | sort -u | grep -v '^$')

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
  echo "Cleaning up temporary parsed IPs file..."
  # rm "$PARSED_IPS_FILE"
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