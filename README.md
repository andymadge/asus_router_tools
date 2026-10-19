# ASUS Router Tools

A collection of utilities and monitoring tools for ASUS routers running Asuswrt-Merlin firmware. Currently includes DNS monitoring, USB storage health monitoring and firmware update alerts with Telegram notifications, with more router management tools planned for future releases.

## Current Tools

### DNS Watchdog
There is a common problem with dnsmasq on ASUS routers where it will randomly stop resolving. This script continuously monitors DNS resolution and automatically restarts dnsmasq or the entire router to fix issues.

**Key Features:**
- Continuous DNS monitoring every 5 minutes via cron job
- Cron job survives reboots (re-registered at boot via `/jffs/scripts/services-start`)
- Automatic recovery via dnsmasq service restart  
- Real-time Telegram notifications
- Fallback communication using direct IP addresses since DNS will be down at the time
- Formatted messages with HTML support
- Detailed logging to `/tmp/dns_watchdog.log`
- Daily heartbeat log line — healthy runs are otherwise silent, so the heartbeat proves the watchdog is alive (also logged on first run after each reboot)
- Configurable test domain (default: `google.com`)
- Router reboot protection as last resort (currently commented out)

### USB Health Check
USB sticks used for Entware, swap or traffic history wear out, and a failing stick causes confusing errors elsewhere long before anyone notices it. amtm's boot-time disk check may already be reporting errors in a log nobody reads. This script watches for those signs and sends a Telegram alert.

**Checks (hourly via cron, survives reboots):**
- **Kernel log**: media and filesystem errors on USB disks (`Unrecovered read error`, `critical medium error`, `EXT4-fs error`, …)
- **amtm disk check**: new results in `/jffs/addons/amtm/disk_check.log` that report filesystem errors (`RUN fsck MANUALLY`)
- **Read-only remounts**: a USB filesystem the kernel has switched to read-only after errors

**Key Features:**
- Alerts once per problem, not on every run
- Daily heartbeat log line, including while a known problem persists, so a dead check is distinguishable from a quiet one
- Logs to `/tmp/usb_health_check.log` and syslog
- Inputs can be overridden with environment variables for testing (see the script header)

### Firmware Check
The firmware checks for new releases every day, but only shows the result as a banner in the web UI, so a router nobody logs into falls months behind. Stale firmware is risky in its own right: in October 2026 a DNSSEC root key change broke all DNS on firmware that predated the fix by ~8 months. This script turns the firmware's own check into a Telegram alert.

**Key Features:**
- Reads the firmware's update check result from nvram (`webs_state_flag`, `webs_state_info`); no extra network requests
- One alert per new release, and one reminder if it's still not installed 30 days after the alert
- Runs daily via cron (survives reboots); state persists in `/jffs/addons/asus_router_tools/`
- Daily heartbeat log line, which also notes when the firmware's own update check is failing (`webs_state_error`)
- Logs to `/tmp/firmware_check.log` and syslog
- Inputs can be overridden with environment variables for testing, and `FW_CHECK_DRY_RUN=1` prints alerts instead of sending them (see the script header)

## Quick Setup

### Prerequisites
- ASUS router with Asuswrt-Merlin firmware
- Entware package manager installed
- SSH access to router

### 1. Install Entware and Git
```bash
# Enable JFFS in router web interface: Administration > System > Enable JFFS custom scripts and configs

# SSH to router and install Entware via amtm
amtm
# Select option 'ep' to install Entware
# Follow prompts to complete installation

# Install git
opkg update
opkg install git git-http
```

### 2. Clone and Install
```bash
# Clone repository to persistent storage
cd /jffs
git clone https://github.com/andymadge/asus_router_tools.git
cd asus_router_tools

# Run installation script
./install.sh
```

### 3. Configure Telegram Bot
1. Message @BotFather on Telegram
2. Create a new bot with `/newbot` command
3. Copy the bot token provided
4. Message your new bot (send any text like "hello")
5. Visit `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
6. Find your chat ID in the response
7. Edit the config file:
```bash
nano /jffs/asus_router_tools/telegram.conf
```

### 4. Test Installation
```bash
# Test Telegram notifications
/jffs/scripts/telegram_notify.sh

# Test DNS watchdog in verbose mode
/jffs/scripts/dns_watchdog.sh --verbose
```

## DNS Watchdog Tool

The DNS watchdog is the primary tool currently included in this collection. It provides robust DNS monitoring with automatic recovery capabilities.

### How It Works

The DNS watchdog system consists of two main components:

1. **dns_watchdog.sh** - Core monitoring script that:
   - Tests DNS resolution against local dnsmasq service (127.0.0.1)
   - Uses `google.com` as the default test domain
   - Runs every 5 minutes via cron job (registered at install and re-registered at every boot via `/jffs/scripts/services-start` — `cru` entries live in RAM and are lost on reboot)
   - Automatically restarts dnsmasq when DNS failures are detected
   - If DNS is still broken after the restart, diagnoses why (upstream/WAN outage vs DNSSEC validation failure vs unknown) and only recommends a reboot when that could actually help
   - Logs to both file (`/tmp/dns_watchdog.log`) and syslog

2. **telegram_notify.sh** - Notification system that:
   - Sends real-time alerts to your Telegram chat
   - Works even during DNS outages using hardcoded IP addresses
   - Supports rich HTML formatting with emojis and styled text
   - Includes router information and timestamps in all messages

### Usage

#### Monitoring
```bash
# View recent logs
tail -20 /tmp/dns_watchdog.log

# Confirm the watchdog is alive (one line per day; healthy checks are otherwise silent)
grep Heartbeat /tmp/dns_watchdog.log

# Monitor logs in real-time
tail -f /tmp/dns_watchdog.log

# Check cron jobs
cru l
```

Note: healthy 5-minute checks write nothing — only failures, recoveries, and the daily heartbeat reach the log. An empty or missing log right after a reboot is normal until the first check runs; no heartbeat for more than a day means the watchdog is not running (check `cru l` and `/jffs/scripts/services-start`).

#### Debugging
```bash
# Enable verbose mode temporarily
cru d DNSWatchdog
cru a DNSWatchdogVerbose "*/5 * * * * /jffs/scripts/dns_watchdog.sh --verbose"

# Switch back to normal mode
cru d DNSWatchdogVerbose
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"
```

#### Manual Operations
```bash
# Send test notification
/jffs/scripts/telegram_notify.sh "Test message"

# Send notifications with HTML formatting
/jffs/scripts/telegram_notify.sh "<b>DNS Failed</b>"                                    # → **DNS Failed**
/jffs/scripts/telegram_notify.sh "<i>Warning:</i> <code>High CPU usage detected</code>" # → *Warning:* `High CPU usage detected`
/jffs/scripts/telegram_notify.sh "🔥 <b>Critical:</b> Router temperature: <code>85°C</code>" # → 🔥 **Critical:** Router temperature: `85°C`

# Run DNS check manually
/jffs/scripts/dns_watchdog.sh --verbose
```

### Notification Types

The DNS watchdog sends three types of Telegram notifications:

1. **DNS Failure** 🚨 - When DNS resolution initially fails
2. **DNS Recovery** ✅ - When DNS is restored after dnsmasq restart
3. **Critical Failure** 🚨 - When DNS failure persists after restart, with a diagnosis and a matching recommendation

### Configuration

#### DNS Watchdog Settings
- **Test Domain**: `google.com` (configurable in script)
- **Test Frequency**: Every 5 minutes via cron
- **Log Location**: `/tmp/dns_watchdog.log`
- **Log Rotation**: Automatic when file exceeds 500 lines

#### Telegram Notifications
- **Config File**: `telegram.conf` in same directory as script
- **Fallback IPs**: Multiple Telegram server IPs for DNS-down scenarios
- **Message Format**: HTML with router info and timestamps

## Updates

Updates are easy with git:
```bash
cd /jffs/asus_router_tools
git pull
```

No need to reinstall or reconfigure - symlinks automatically use the updated scripts. (Exception: when an update adds a new tool, re-run `./install.sh` to register its symlink and cron job. Upgrading to install.sh 0.3.0 adds the USB Health Check; 0.4.0 adds the Firmware Check.)

## File Structure

```
asus_router_tools/
├── dns_watchdog.sh          # DNS monitoring script
├── usb_health_check.sh      # USB storage health monitoring
├── firmware_check.sh        # Firmware update alerts
├── telegram_notify.sh       # Telegram notification system  
├── telegram.conf.example    # Configuration template
├── telegram.conf            # Your credentials (not in git)
├── install.sh              # Installation script
└── CLAUDE.md               # AI assistant guidance
```

## Security

- Telegram credentials stored in separate config file
- Config file has restricted permissions (600)
- Credentials never committed to git repository
- Uses secure HTTPS connections to Telegram API

## Troubleshooting

### Common Issues

1. **Notifications not working**: Check `telegram.conf` credentials
2. **Cron job not running**: Verify with `cru l` and check system time. If it's missing after a reboot, check `/jffs/scripts/services-start` exists, is executable, and contains the `cru a DNSWatchdog` line (installs made with install.sh < 0.2.0 didn't set this up — re-run `./install.sh`)
3. **DNS false positives**: Test with different domain in script
4. **Permission errors**: Ensure scripts are executable (`chmod +x`)
5. **"Likely DNSSEC validation failure" alert**: upstream DNS works but dnsmasq rejects everything, and rebooting won't help. Most likely cause: the firmware's hard-coded DNSSEC root trust anchor is out of date. The root zone switched to KSK-2024 (key tag 38696) on 11 October 2026; Asuswrt-Merlin includes it from 3006.102.7. Fix: update the firmware, or add the anchor to `/jffs/configs/dnsmasq.conf.add` and `service restart_dnsmasq`:
   ```
   trust-anchor=.,38696,8,2,683D2D0ACB8C9B712A1948B27F741219298D0A450D612C483AF444A4C0FB2B16
   ```
   Temporary workaround: disable DNSSEC (WAN → Internet Connection).
6. **"USB Disk Errors" / "USB Disk Check Failed" alert**: the USB disk is reporting media or filesystem errors. Confirm with `dmesg | grep -iE 'medium error|EXT4-fs error'` and `tail /jffs/addons/amtm/disk_check.log`. Media errors ("Unrecovered read error") mean failing hardware, which fsck can't repair: back up anything needed (e.g. traffic history in `nvram get rstats_path`) and replace the stick. Small "nano" sticks run hot and wear quickly; prefer a normal-sized stick and avoid swap if the router doesn't need it.
7. **"Router Firmware Update Available" alert**: check the [Merlin changelog](https://www.asuswrt-merlin.net/changelog) and skim the release thread on SNBForums, then update at a quiet time (Administration → Firmware Upgrade). After the update, the next daily run clears the alert state. No alerts at all? Check `grep Heartbeat /tmp/firmware_check.log`; a heartbeat mentioning "update check reports error" means the firmware itself can't reach ASUS's update server.

### Support

- Check router syslog: `logread | grep "DNS Watchdog"`
- Verify network connectivity: `ping 8.8.8.8`  
- Test Telegram API manually: `curl -X POST "https://api.telegram.org/bot<TOKEN>/getMe"`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

The MIT License allows for:
- ✅ Personal and commercial use
- ✅ Modification and distribution
- ✅ Private use
- ✅ Sublicensing

Requires only attribution of copyright notice in distributions.