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

## Security Requirements

**CRITICAL**: Always follow strict security practices to protect credentials and maintain safe public repository.

### Mandatory Security Checks Before Any Commit
```bash
# 1. Verify no credentials in tracked files
git ls-files | xargs grep -l "BOT_TOKEN\|CHAT_ID" | grep -v "\.example$"
# Should only return files ending in .example or containing placeholder text

# 2. Check .gitignore is protecting credential files  
git check-ignore telegram.conf
# Should confirm file is ignored

# 3. Verify no sensitive data in git history
git log --patch --all | grep -i "bot.*token\|chat.*id" | grep -v "placeholder\|example\|your_.*_here"
# Should return no real credential values

# 4. Test git prevents committing credentials
git add telegram.conf 2>&1 | grep -q "ignored by.*gitignore"
# Should show ignore warning, not stage the file
```

### Required .gitignore Protection
```gitignore
# Telegram credentials - never commit these
telegram.conf

# Router-specific config files  
*.conf

# Log files
*.log
```

### Credential File Security Rules
- **telegram.conf**: Must contain real credentials, never commit to git
- **telegram.conf.example**: Template with placeholders only, safe to commit
- **File permissions**: Always set credential files to 600 (user read/write only)
- **Documentation**: Always emphasize "never commit credentials" in setup instructions

### Security Validation Commands
```bash
# Ensure credential file has proper permissions
chmod 600 telegram.conf

# Verify gitignore is working
git status --ignored | grep telegram.conf

# Check no real credentials in any tracked files
git grep -i "8[0-9]\{9\}:" -- ':!*.example'  # Telegram bot token pattern
git grep -i "[0-9]\{10,\}" -- ':!*.example'   # Telegram chat ID pattern
```

### Pre-Public-Release Security Checklist
- [ ] No real API keys, tokens, or passwords in any tracked files
- [ ] All credential files properly gitignored
- [ ] Template files contain only placeholder values
- [ ] Documentation emphasizes credential security
- [ ] Installation scripts set proper file permissions
- [ ] Git history contains no committed secrets

## Semantic Versioning Requirements

**CRITICAL**: Follow semantic versioning (semver) for all scripts using per-script versioning.

### Version Format
Each script maintains its own version in the header: `# Version: MAJOR.MINOR.PATCH`

### Semver Rules
- **MAJOR** (X.y.z): Breaking changes, incompatible API changes, or major functionality overhauls
- **MINOR** (x.Y.z): New features, new functionality, backwards-compatible additions
- **PATCH** (x.y.Z): Bug fixes, security patches, documentation updates, backwards-compatible fixes

### Version Update Process
```bash
# 1. Identify which scripts have changed since last release tag
git diff --name-only <last-release-tag>..HEAD

# 2. For each changed script, determine version bump needed:
# - Breaking change? Bump MAJOR version (1.0.0 → 2.0.0)
# - New feature? Bump MINOR version (1.0.0 → 1.1.0)
# - Bug fix? Bump PATCH version (1.0.0 → 1.0.1)

# 3. Update version in script header
# Edit: # Version: 0.1.0 → # Version: 0.2.0

# 4. Commit version bumps
git add changed-script.sh
git commit -m "Bump script-name.sh version to 0.2.0

- Added new feature X
- Improved functionality Y
- Maintains backward compatibility"

# 5. Create semantic version release tag when ready
git tag v0.2.0 -m "v0.2.0: Add new features and improvements"
```

### Repository Release Tagging
Repository uses semantic versioning completely **independent** of individual script versions:
- **Format**: `v1.0.0`, `v1.1.0`, `v2.0.0` etc. (standard semantic versioning)
- **Purpose**: Mark stable snapshots of the entire repository as a product
- **Independence**: Repository version has no relationship to individual script version numbers
- **Multiple daily releases**: Semantic versioning handles multiple releases per day naturally

### Repository Release Guidelines
- **MAJOR** (v0.1.0 → v1.0.0): Breaking changes, major architectural changes, API changes, or first stable release
- **MINOR** (v0.1.0 → v0.2.0): New features, script additions, enhanced functionality
- **PATCH** (v0.1.0 → v0.1.1): Bug fixes, documentation updates, minor improvements

### Example Timeline
```bash
# Initial pre-release
git tag v0.1.0 -m "v0.1.0: Initial alpha release"

# Later same day: Add new features  
git tag v0.2.0 -m "v0.2.0: Add rich HTML formatting to notifications"

# Next day: Bug fixes
git tag v0.2.1 -m "v0.2.1: Fix install script symlink issues"

# Ready for production
git tag v1.0.0 -m "v1.0.0: First stable release"
```

### Current Script Versions
- `dns_watchdog.sh`: 0.2.0
- `telegram_notify.sh`: 0.2.0
- `install.sh`: 0.1.0

### Version Bump Examples
**PATCH (0.1.0 → 0.1.1)**: Fix DNS timeout bug, improve error logging  
**MINOR (0.1.0 → 0.2.0)**: Add new notification types, new configuration options  
**MAJOR (0.1.0 → 1.0.0)**: Change script API, require different installation method

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
nano /jffs/asus_router_tools/telegram.conf

# Validate Telegram bot connection
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/getMe"

# Get chat updates for debugging
curl "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
```

### Installation on Router (Git Workflow)
```bash
# Install Entware via amtm (one-time setup)
amtm
# Select option 'ep' to install Entware
# Follow prompts to complete installation

# Install git
opkg update && opkg install git git-http

# Clone repository and install
cd /jffs
git clone <repository-url> asus_router_tools
cd asus_router_tools
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
cd /jffs/asus_router_tools && git pull

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