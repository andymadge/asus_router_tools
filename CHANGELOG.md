# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Rich HTML formatting for all Telegram notifications with emojis, bold headers, and styled text
- HTML formatting examples in script headers and README documentation
- Enhanced DNS watchdog notifications with visual hierarchy and better readability
- Support for custom HTML formatting in telegram_notify.sh messages

### Changed
- Improved Telegram message order to prioritize content in notification previews
- Enhanced message presentation with code blocks and italic descriptions
- Updated telegram_notify.sh to version 0.2.0 with new formatting features
- Updated dns_watchdog.sh to version 0.2.0 with rich notification formatting
- Repository versioning system changed to semantic versioning (v0.x.x)

### Fixed
- Install script bugs: missing telegram.conf symlink and incorrect git pull directory
- Corrected newline formatting in DNS watchdog notification messages
- Fixed execute permissions on scripts

## [v0.2.0] - 2025-08-06

### Added
- Comprehensive security requirements and credential protection guidelines
- Mandatory git discipline requirements and workflow documentation

### Changed
- Updated all documentation for renamed repository folder structure (asus_router → asus_router_tools)
- Fixed repository URL references for correct installation instructions
- Enhanced Entware installation instructions to use amtm tool

### Fixed
- Repository naming consistency throughout documentation

## [v0.1.0] - 2024-08-06

### Added
- Initial DNS watchdog system for ASUS routers with Asuswrt-Merlin firmware
- Telegram notification system with DNS-independent operation using direct IP addresses
- Automated installation script with symlink management for easy updates
- Comprehensive documentation and setup instructions in README.md
- CLAUDE.md with system architecture and development guidelines
- Semantic versioning requirements for individual scripts
- Dual logging system (file and syslog) with automatic log rotation
- Memory monitoring and dnsmasq process tracking
- Cron job integration for continuous DNS monitoring (every 5 minutes)
- Fallback router reboot mechanism for critical DNS failures
- Three notification types: DNS failure, recovery, and critical failure

### Security
- Telegram credentials stored separately in telegram.conf (never committed to git)
- Configuration files protected with restrictive permissions (600)
- Git discipline requirements to prevent credential exposure
- Direct IP address fallbacks for Telegram API during DNS outages

---

## Notes

- Repository versions are independent of individual script versions
- All releases maintain backward compatibility with existing configurations
- No migration steps required between versions