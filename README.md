# ASUS Router DNS Watchdog with Telegram Notifications

A comprehensive DNS monitoring and notification system for ASUS routers running Asuswrt-Merlin firmware.

## Features

- **DNS Monitoring**: Continuous monitoring of DNS resolution every 5 minutes
- **Automatic Recovery**: Restarts dnsmasq service when DNS failures are detected
- **Telegram Notifications**: Real-time alerts sent to your phone via Telegram
- **Fallback Communication**: Works even when DNS is down using direct IP addresses
- **Comprehensive Logging**: Detailed logs with configurable verbosity
- **Router Reboot Protection**: Escalates to router reboot if dnsmasq restart fails

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

## Usage

### Monitoring
```bash
# View recent logs
tail -20 /tmp/dns_watchdog.log

# Monitor logs in real-time
tail -f /tmp/dns_watchdog.log

# Check cron jobs
cru l
```

### Debugging
```bash
# Enable verbose mode temporarily
cru d DNSWatchdog
cru a DNSWatchdogVerbose "*/5 * * * * /jffs/scripts/dns_watchdog.sh --verbose"

# Switch back to normal mode
cru d DNSWatchdogVerbose
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"
```

### Manual Operations
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

## Updates

Updates are easy with git:
```bash
cd /jffs/asus_router_tools
git pull
```

No need to reinstall or reconfigure - symlinks automatically use the updated scripts.

## File Structure

```
asus_router_tools/
├── dns_watchdog.sh          # Main DNS monitoring script
├── telegram_notify.sh       # Telegram notification system  
├── telegram.conf.example    # Configuration template
├── telegram.conf            # Your credentials (not in git)
├── install.sh              # Installation script
└── CLAUDE.md               # AI assistant guidance
```

## Notification Types

The system sends three types of Telegram notifications:

1. **DNS Failure** 🚨 - When DNS resolution initially fails
2. **DNS Recovery** ✅ - When DNS is restored after dnsmasq restart
3. **Critical Failure** 🚨 - When DNS persists after restart (before reboot)

## Configuration

### DNS Watchdog (`dns_watchdog.sh`)
- **Test Domain**: `google.com` (configurable in script)
- **Test Frequency**: Every 5 minutes via cron
- **Log Location**: `/tmp/dns_watchdog.log`
- **Log Rotation**: Automatic when file exceeds 500 lines

### Telegram Notifications (`telegram_notify.sh`)
- **Config File**: `telegram.conf` in same directory as script
- **Fallback IPs**: Multiple Telegram server IPs for DNS-down scenarios
- **Message Format**: HTML with router info and timestamps

## Security

- Telegram credentials stored in separate config file
- Config file has restricted permissions (600)
- Credentials never committed to git repository
- Uses secure HTTPS connections to Telegram API

## Troubleshooting

### Common Issues

1. **Notifications not working**: Check `telegram.conf` credentials
2. **Cron job not running**: Verify with `cru l` and check system time
3. **DNS false positives**: Test with different domain in script
4. **Permission errors**: Ensure scripts are executable (`chmod +x`)

### Support

- Check router syslog: `logread | grep "DNS Watchdog"`
- Verify network connectivity: `ping 8.8.8.8`  
- Test Telegram API manually: `curl -X POST "https://api.telegram.org/bot<TOKEN>/getMe"`

## License

This project is provided as-is for educational and personal use.