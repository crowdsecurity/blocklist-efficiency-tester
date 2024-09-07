![CrowdSec Logo](https://raw.githubusercontent.com/crowdsecurity/blocklist-efficiency-tester/main/crowdsec_logo.png)

# CrowdSec Blocklist efficiency tester
> Fast evaluation of ingress traffic mass-attacks
> Demonstration of proactive value of the CrowdSec Intelligence Blocklist.

## Usage
### Requierements

The crowdsec-efficienty-tester.sh bash script requires:
- A CrowdSec Service API Key
- A log file from incoming traffic or at least a file containing IPs that hit your server in the past 24-48hours
- The curl command must be available on your system (to download the list)
- Run the script like so:
```
  LOG_FILE=/path/to/log/file.log API_KEY=your-api-key ./crowdsec-efficiency-tester.sh
```

### Log files that you can use
> Any file that contains the source IP for a given request
- Auth logs
- NGINX logs
- HAProxy logs
- AWS CloudFront access logs
- Kubernetes ingress controller logs
- FTP server logs
- Mail server (Postfix, Exim) logs
- ...

### Alternate commands
> You can run the script directly from the repo
> You'll be prompted to enter the path to your file and API key
``` 
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crowdsecurity/blocklist-efficiency-tester/main/crowdsec-efficiency-tester.sh)"
```

### Example Output
```
✨✨✨ CrowdSec efficiency tester ✨✨✨

Extracting and counting IP addresses from logs... ✅
Downloading blocklist... ✅
Analyzing IPs against the blocklist... ✅


=== Summary ===
Blocklist hits (IPs)       : 1.85% (4/216)
Blocklist hits (Requests)  : 73.78% (4890/6627)

TOP 10 IPs in the blocklist:
------------------------------------------------
IP Address           | Count
-------------------- | -----
212.102.57.94        |  4853
207.102.138.19       |  34  
185.241.208.115      |  2   
142.44.160.96        |  1   
                     |   
```

## Troubleshooting
- If the log file is not found, the script will not work. Ensure you provide a valid path.
- If the API key is incorrect the blocklist won't be downloaded. Note that API keys may expires depending on creation preferences
- IPs in your log files must be ingress source IPs (be sure not to have CDN IPs)