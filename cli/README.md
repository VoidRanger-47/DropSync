# DropSync Headless CLI Daemon

This directory contains the lightweight headless Python host daemon for DropSync.

## Overview
- **Primary Desktop UI**: The native Flutter application (`windows/`, `linux/`, `android/`) serves as the official DropSync graphical desktop & mobile interface.
- **Headless Host Daemon**: `dropsync_host.py` provides a standalone, lightweight, zero-GUI CLI receiver for servers, background headless services, and automated integration testing without needing a display server or Flutter runtime.

## Usage
```bash
# Start headless receiver with default PIN 1234 on port 52530
python dropsync_host.py --pin 1234

# Run with custom port and save directory
python dropsync_host.py --port 52530 --pin 4321 --save-dir ./downloads

# Run end-to-end automated protocol tests
python test_dropsync.py
```

## Protocol Specifications
The Python daemon adheres to the official specification documented in [PROTOCOL.md](../PROTOCOL.md), supporting:
1. UDP Discovery Beacon broadcast & parsing (`DROPSYNC:DISCOVER:<name>:<port>:<deviceId>`)
2. Binary frame protocol with 2-byte magic `0x4453` (`DS`)
3. 64 KB chunked TCP streaming with SHA-256 integrity validation
4. Bidirectional clipboard sync with loopback echo suppression
