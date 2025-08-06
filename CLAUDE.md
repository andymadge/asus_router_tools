# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this ASUS router utilities repository.

## Project Overview

Collection of ASUS router utility scripts for RT-AX86U Pro running Asuswrt-Merlin firmware. Primary focus: DNS watchdog system that monitors and automatically fixes DNS resolution issues.

## System Architecture

### Core Scripts
- **`dns_watchdog.sh`** - Main DNS monitoring script, tests against local dnsmasq (127.0.0.1)  
- **`telegram_notify.sh`** - Notification system using direct IPs for DNS-outage resilience  
- **`install.sh`** - Symlinked deployment for easy git-based updates  

### Key Features  
- **5-minute monitoring** via router's cron system
- **Dual logging** to `/tmp/dns_watchdog.log` and syslog  
- **Telegram alerts** work during DNS outages using hardcoded server IPs
- **Recovery escalation** from dnsmasq restart to full router reboot
- **Git-based updates** via symlinks without reinstallation

## Required Practices

### Git Discipline (CRITICAL)

**Before every commit:**
```bash
git status                    # Check modified/untracked files
git diff                      # Review unstaged changes  
git diff --cached            # Review staged changes
```

**Commit workflow:**
```bash
git add specific-file.sh     # Stage individual files only
git commit -m "Brief summary

- Detailed explanation of changes
- Why the change was necessary  
- Implementation details

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

git status                   # Verify clean state
```

**Commit standards:**
- ✅ **Atomic commits** - single responsibility per commit
- ✅ **Clear messages** - explain "why", not just "what"  
- ✅ **Separate concerns** - never bundle unrelated changes
- ❌ **Never use** `git add .` - stage specific files only

### Security Requirements (CRITICAL)

**Pre-commit security checks:**
```bash
# Verify no credentials in tracked files
git ls-files | xargs grep -l "BOT_TOKEN\|CHAT_ID" | grep -v "\.example$"

# Confirm gitignore protection  
git check-ignore telegram.conf

# Check git history for leaked secrets
git log --patch --all | grep -i "bot.*token\|chat.*id" | grep -v "placeholder\|example"
```

**Required `.gitignore` protection:**
```gitignore
telegram.conf
*.conf  
*.log
```

**Security rules:**
- `telegram.conf` - real credentials, never commit
- `telegram.conf.example` - placeholder template only
- Always `chmod 600` on credential files

### Versioning Requirements

**Per-script versioning in headers:**
```bash
# Version: MAJOR.MINOR.PATCH
```

**Semver rules:**
- **MAJOR** - Breaking changes, API incompatibility
- **MINOR** - New features, backwards-compatible  
- **PATCH** - Bug fixes, documentation updates

**Current versions:**
- `dns_watchdog.sh`: 0.2.0
- `telegram_notify.sh`: 0.2.0  
- `install.sh`: 0.1.0

## Configuration & Setup

### Telegram Setup
Create `telegram.conf`:
```bash
BOT_TOKEN="your_bot_token_from_botfather"
CHAT_ID="your_telegram_chat_id"  
```

**Bot setup process:**
1. Message @BotFather → `/newbot`
2. Save bot token
3. Message your bot to start chat  
4. Get chat ID: `curl "https://api.telegram.org/bot<TOKEN>/getUpdates"`
5. Configure `telegram.conf` with both values
6. Set permissions: `chmod 600 telegram.conf`

### Router Installation
```bash
# Install Entware + git (one-time)
amtm → ep → follow prompts
opkg update && opkg install git git-http

# Deploy scripts
cd /jffs
git clone <repository-url> asus_router_tools
cd asus_router_tools  
./install.sh

# Enable monitoring  
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"
```

## Development Commands

### Testing
```bash
# Test notifications
/jffs/scripts/telegram_notify.sh "Test message"

# Test DNS watchdog  
/jffs/scripts/dns_watchdog.sh --verbose

# Monitor logs
tail -f /tmp/dns_watchdog.log
```

### Debugging  
```bash
# Check cron jobs
cru l

# Enable verbose logging
cru d DNSWatchdog
cru a DNSWatchdogVerbose "*/5 * * * * /jffs/scripts/dns_watchdog.sh --verbose"  

# Validate Telegram bot
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/getMe"
```

### Updates
```bash  
# Git-based update (recommended)
cd /jffs/asus_router_tools && git pull
```

## Technical Details

### DNS Watchdog (`dns_watchdog.sh`)
- Tests `google.com` resolution against local dnsmasq
- Timeout handling with manual fallback  
- Tracks dnsmasq PID and memory usage
- Auto log rotation at 500 lines
- Escalates: dnsmasq restart → router reboot

### Telegram Notifier (`telegram_notify.sh`)  
- HTML message formatting with router info
- Works during DNS outages via hardcoded IPs
- Secure credential handling
- Message queuing system for reliability

### Architecture Notes
- **POSIX compliant** shell scripts
- **Process safety** with PID-suffixed temp files
- **Symlinked deployment** for easy updates
- **Dual logging** to file and syslog
- **DNS-independent alerts** using IP addresses

## Maintenance

- Update README.md when making code changes
- Maintain changelog before each release  
- Follow semantic versioning for all scripts
- Test Telegram integration after updates
- Monitor logs for system health