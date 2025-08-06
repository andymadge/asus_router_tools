# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of ASUS router utility scripts, specifically designed for the RT-AX86U Pro router running Asuswrt-Merlin firmware. The primary component is a DNS watchdog system that monitors and automatically fixes DNS resolution issues.

## Architecture

The codebase consists of a single shell script (`dns_watchdog.sh`) that provides DNS monitoring and recovery functionality:

- **DNS Monitoring**: Tests DNS resolution against local dnsmasq service (127.0.0.1)
- **Automatic Recovery**: Restarts dnsmasq service when DNS failures are detected
- **Logging**: Comprehensive logging with configurable verbosity
- **Cron Integration**: Designed to run as a scheduled task every 5 minutes

## Key Components

### DNS Watchdog Script (`dns_watchdog.sh`)
- **Location**: Deployed to `/jffs/scripts/dns_watchdog.sh` on router
- **Test Domain**: Uses `google.com` as the default test target
- **Timeout Handling**: Implements both `timeout` command and manual timeout fallback
- **Process Monitoring**: Tracks dnsmasq PID and memory usage
- **Log Management**: Automatic log rotation when file exceeds 500 lines

## Deployment and Usage

### Installation on Router
```bash
# Copy script to router
chmod +x /jffs/scripts/dns_watchdog.sh

# Set up cron job (every 5 minutes)
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"

# Verify cron job
cru l
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

## Script Features

- **Dual Logging**: Writes to both file (`/tmp/dns_watchdog.log`) and syslog
- **Verbose Mode**: Optional detailed logging via `--verbose` flag
- **Recovery Escalation**: Falls back to router reboot if dnsmasq restart fails
- **Memory Monitoring**: Tracks dnsmasq memory usage for troubleshooting
- **Silent Operation**: Minimal output in normal mode to reduce log noise

## Development Notes

- Shell script uses POSIX-compliant syntax for maximum compatibility
- Implements manual timeout handling for systems without `timeout` command
- All temporary files use process ID suffix to avoid conflicts
- Error handling includes graceful cleanup of background processes