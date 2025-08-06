# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of ASUS router utility scripts, specifically designed for the RT-AX86U Pro router running Asuswrt-Merlin firmware. The primary component is a DNS watchdog system that monitors and automatically fixes DNS resolution issues.

## Architecture

The system consists of two main components that work together to provide DNS monitoring with real-time notifications:

### Core Components
- **DNS Watchdog** (`dns_watchdog.sh`): Main monitoring script that tests DNS resolution against local dnsmasq service (127.0.0.1)
- **Telegram Notifier** (`telegram_notify.sh`): Notification system that sends alerts even when DNS is down using direct IP addresses
- **Installation Script** (`install.sh`): Automated deployment using symlinks for easy updates

### System Integration
- **Cron Integration**: DNS watchdog runs every 5 minutes via router's cron system
- **Dual Logging**: Writes to both file (`/tmp/dns_watchdog.log`) and syslog
- **Fallback Communication**: Telegram notifications work during DNS outages using hardcoded Telegram server IPs
- **Git-based Updates**: Symlinked deployment allows updates via `git pull` without reinstallation

## Key Components

### DNS Watchdog Script (`dns_watchdog.sh`)
- **Location**: Deployed to `/jffs/scripts/dns_watchdog.sh` on router (symlinked)
- **Test Domain**: Uses `google.com` as the default test target
- **Timeout Handling**: Implements both `timeout` command and manual timeout fallback
- **Process Monitoring**: Tracks dnsmasq PID and memory usage
- **Log Management**: Automatic log rotation when file exceeds 500 lines
- **Telegram Integration**: Sends notifications on DNS failure, recovery, and critical failures

### Telegram Notification System (`telegram_notify.sh`)
- **Configuration**: Uses `telegram.conf` file with BOT_TOKEN and CHAT_ID
- **DNS-Independent**: Works during DNS outages using hardcoded Telegram server IPs
- **Message Types**: Supports HTML formatting with router info and timestamps
- **Security**: Configuration file permissions set to 600, never committed to git

## Git Discipline Requirements

**CRITICAL**: Always follow strict git discipline when working in this repository.

### Mandatory Git Practices
- **Review before commit**: Always run `git status` and `git diff` before committing
- **Atomic commits**: Each commit must have single, clear responsibility
- **Descriptive messages**: Write clear commit messages explaining the "why", not just the "what"
- **Clean staging**: Only stage files relevant to the current commit using `git add <specific-file>`
- **Separate concerns**: Never bundle unrelated changes in the same commit
- **Verify state**: Always check `git status` after commits to ensure clean working tree

### Required Git Workflow
```bash
# 1. Review all changes before committing
git status                    # Check what files are modified/untracked
git diff                      # Review unstaged changes
git diff --cached            # Review staged changes

# 2. Stage only relevant files for atomic commits
git add specific-file.sh     # Stage individual files, not git add .

# 3. Create descriptive commit with proper format
git commit -m "Brief summary of change

- Detailed explanation of what was changed
- Why the change was necessary
- Any important implementation details

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# 4. Verify clean state
git status                   # Ensure working tree is clean
git log --oneline -3         # Review recent commits
```

### Examples of Good vs Bad Commits
**✅ Good**: `Add Telegram bot configuration validation`  
**❌ Bad**: `Fixed stuff and updated files`

**✅ Good**: Separate commits for documentation and code changes  
**❌ Bad**: Single commit with mixed README updates and script modifications

## Deployment and Usage

## Development Commands

### Testing and Debugging
```bash
# Test Telegram notifications
/jffs/scripts/telegram_notify.sh
/jffs/scripts/telegram_notify.sh "Custom test message"

# Test DNS watchdog in verbose mode
/jffs/scripts/dns_watchdog.sh --verbose

# Monitor system logs in real-time
tail -f /tmp/dns_watchdog.log
logread -f | grep "DNS Watchdog"

# Check system status
cru l                          # List active cron jobs
ps | grep dns_watchdog         # Check for running processes
```

### Configuration Management
```bash
# Edit Telegram configuration
nano /jffs/asus_router/tools/telegram.conf

# Validate Telegram bot connection
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/getMe"

# Get chat updates for debugging
curl "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
```

### Installation on Router (Git Workflow)
```bash
# Install Entware and git (one-time setup)
/usr/sbin/entware-setup.sh
opkg update && opkg install git git-http

# Clone repository and install
cd /jffs
git clone <repository-url> asus_router
cd asus_router/tools
./install.sh
```

### Cron Job Management
```bash
# Install DNS watchdog cron job
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"

# Switch to verbose mode for debugging
cru d DNSWatchdog
cru a DNSWatchdogVerbose "*/5 * * * * /jffs/scripts/dns_watchdog.sh --verbose"

# Switch back to normal mode
cru d DNSWatchdogVerbose
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"

# Remove cron job completely
cru d DNSWatchdog
```

### Updates
```bash
# With git workflow (recommended)
cd /jffs/asus_router && git pull

# Manual update
# Re-copy updated scripts to /jffs/scripts/
```

### Debugging and Monitoring
```bash
# View recent logs
tail -20 /tmp/dns_watchdog.log

# Monitor in real-time
tail -f /tmp/dns_watchdog.log

# Enable verbose mode for debugging
cru d DNSWatchdog
cru a DNSWatchdogVerbose "*/5 * * * * /jffs/scripts/dns_watchdog.sh --verbose"
```

## Configuration

### Telegram Setup (`telegram.conf`)
```bash
# Required configuration file in same directory as scripts
BOT_TOKEN="your_bot_token_from_botfather"
CHAT_ID="your_telegram_chat_id"

# File permissions must be 600 for security
chmod 600 telegram.conf
```

### DNS Watchdog Configuration
Key variables that can be modified in `dns_watchdog.sh`:
- `TEST_DOMAIN="google.com"` - Domain to test DNS resolution against
- `LOGFILE="/tmp/dns_watchdog.log"` - Location of log file
- Log rotation triggers at 500 lines

### Telegram Bot Setup Process
1. Message @BotFather on Telegram
2. Create bot: `/newbot`
3. Copy the provided bot token
4. Message your new bot to initiate chat
5. Get chat ID: `https://api.telegram.org/bot<TOKEN>/getUpdates`
6. Configure `telegram.conf` with both values

## Script Features

- **Dual Logging**: Writes to both file (`/tmp/dns_watchdog.log`) and syslog
- **Verbose Mode**: Optional detailed logging via `--verbose` flag
- **Recovery Escalation**: Falls back to router reboot if dnsmasq restart fails
- **Memory Monitoring**: Tracks dnsmasq memory usage for troubleshooting
- **Silent Operation**: Minimal output in normal mode to reduce log noise
- **DNS-Independent Notifications**: Telegram alerts work even during DNS outages

## Development Notes

### Code Architecture
- **POSIX Compliance**: Shell scripts use POSIX-compliant syntax for maximum compatibility
- **Timeout Handling**: Manual timeout implementation for systems without `timeout` command
- **Process Safety**: All temporary files use process ID suffix to avoid conflicts
- **Error Handling**: Graceful cleanup of background processes and DNS test subshells
- **Symlinked Deployment**: Scripts remain in git repo, symlinked to `/jffs/scripts/` for easy updates

### Security Considerations
- Telegram credentials stored separately in `telegram.conf` (never committed to git)
- Configuration files use restrictive permissions (600)
- Direct IP address fallbacks for Telegram API during DNS outages
- No sensitive information in logs or syslog messages

### Router-Specific Implementation
- Uses router's `cru` command for cron job management
- Logs to both `/tmp/dns_watchdog.log` and syslog for persistence across reboots
- Integrates with router's `service restart_dnsmasq` command
- Fallback to full router reboot (`reboot`) for critical DNS failures