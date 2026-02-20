![CrowdSec Logo](https://raw.githubusercontent.com/crowdsecurity/blocklist-efficiency-tester/main/crowdsec_logo.png)

# CrowdSec Blocklist efficiency tester
> Fast evaluation of ingress traffic mass-attacks.<br>
> Demonstrating the proactive value your [Blocklist as a Service integration](https://doc.crowdsec.net/u/integrations/intro)  
> We recommend a [Raw IP list integration](https://doc.crowdsec.net/u/integrations/rawiplist).

## Requirements

The crowdsec-efficiency-tester.sh bash script requires:
  - **CrowdSec Blocklist as a Service Endpoint** ([Raw IP list mode](https://doc.crowdsec.net/u/integrations/rawiplist))
- A **log file from incoming traffic** or at least a file containing IPs that hit your server in the past 24-48hours
- The curl command must be available on your system (to download the list)

## Usage

### ENV SETUP: Optionnal

If you plan to test multiple log files against the content of your Blocklist Integration content it's convenient to create a `.env` file.  

Copy `.env.example`:
```bash  
cp .env.example .env
```

Then uncomment and replace the following values with your endpoint's credentials
```bash
BLOCKLIST_URL=<integration_url>
BLOCKLIST_USERNAME=your_username
BLOCKLIST_PASSWORD=your_password
```

> You can specify only BLOCKLIST_URL if using the `https://username:password@url` format  
> Hence you can pull from anywhere


### Running the evaluation

#### Getting your credentials:
1. Go to the [CrowdSec Console](https://app.crowdsec.net/)
2. Navigate to **Integrations** > **Add Integration**
3. Select **"Raw IP list"** integration
4. Copy your **integration ID**, **username**, and **password**

#### Running with .env file:

```bash
./crowdsec-efficiency-tester.sh /path/to/log/file.log
```

#### Overriding your .env you can run:

```bash
BLOCKLIST_URL=https://admin.api.crowdsec.net/v1/integrations/YOUR_INTEGRATION_ID/content \
BLOCKLIST_USERNAME=your_username \
BLOCKLIST_PASSWORD=your_password \
./crowdsec-efficiency-tester.sh /path/to/log/file.log
```

#### Cache and Performance:
- Blocklist content is **cached for 10 minutes** to improve performance
- Use the `-f` flag to force a fresh download: `./crowdsec-efficiency-tester.sh /path/to/log/file.log -f`
- Cache files: `.cache` (metadata) and `latestBlocklistContent.ips` (IP list)

### Log files that you can use
> ℹ️ Script currently supports logs formats where the **IP address** is the **first element** in the log line.<br>
> Example of logs you might want to evaluate:
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
- This script can take a few minutes. Average 1-2 minutes per 20k lines of log
- If the log file is not found, the script will not work. Ensure you provide a valid path.
- If the API key is incorrect the blocklist won't be downloaded. Note that API keys may expires depending on creation preferences
- IPs in your log files must be ingress source IPs (be sure not to have CDN IPs)

## More info about CrowdSec
- [Blocklists](https://www.crowdsec.net/blocklists)
- [Security Engine](https://www.crowdsec.net/security-engine)
- [CTI](https://www.crowdsec.net/cyber-threat-intelligence)
- [Integrations](https://www.crowdsec.net/integrations)