#!/usr/bin/env python3
"""
DropSync Host Daemon (Windows / Cross-Platform)
-----------------------------------------------
A serverless, peer-to-peer (P2P) local network daemon providing:
1. Zero-configuration UDP broadcast peer discovery on the local subnet.
2. Bidirectional clipboard synchronization with SHA-256 loopback suppression.
3. High-speed 64 KB chunked binary file streaming with low memory footprint (<50 MB RAM).
4. Secure PIN-based handshake and connection authorization.

Usage:
    python dropsync_host.py
    python dropsync_host.py --pin 7788 --save-dir ./downloads
    python dropsync_host.py --send myfile.mp4 192.168.1.50
"""

import asyncio
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import logging
import os
import platform
import random
import socket
import struct
import sys
import threading
import time
from typing import Dict, List, Optional, Tuple, Callable

# ---------------------------------------------------------------------------
# Logging Configuration
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("DropSync")

# ---------------------------------------------------------------------------
# Protocol Constants
# ---------------------------------------------------------------------------
MAGIC_BYTES = b"DSYN"
DEFAULT_TCP_PORT = 52525
DEFAULT_UDP_PORT = 53535
BEACON_INTERVAL = 2.5
PEER_TIMEOUT = 10.0
CHUNK_SIZE = 64 * 1024  # 64 KB chunk streaming


def generate_session_token(length: int = 6) -> str:
    """Generates a high-entropy, human-friendly 6-character session token."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(random.choice(alphabet) for _ in range(length))


def _get_local_broadcast_addresses() -> List[str]:
    """
    Returns all usable subnet-directed broadcast addresses on this host
    (e.g. 192.168.1.255) PLUS the global '255.255.255.255' as a fallback.
    Falls back to ['255.255.255.255'] on error.
    """
    addrs = set()
    addrs.add("255.255.255.255")
    try:
        for _, iface_addrs in socket.if_nameindex() if hasattr(socket, 'if_nameindex') else []:
            pass  # not needed; use getsockname trick below
    except Exception:
        pass

    try:
        # Query all interface IPs via socket.getaddrinfo for localhost name
        hostname = socket.gethostname()
        for item in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = item[4][0]
            # Only private-range addresses
            if ip.startswith(("192.168.", "10.", "172.")):
                parts = ip.split(".")
                bcast = f"{parts[0]}.{parts[1]}.{parts[2]}.255"
                addrs.add(bcast)
    except Exception:
        pass

    return list(addrs)


def _apply_firewall_rules():
    """
    Silently adds Windows Firewall allow rules for DropSync TCP + UDP ports.
    Requires elevation; if not elevated, logs a warning and continues.
    """
    if platform.system() != "Windows":
        return
    import subprocess
    rules = [
        ("DropSync-TCP-In",  "TCP", str(DEFAULT_TCP_PORT)),
        ("DropSync-UDP-In",  "UDP", str(DEFAULT_UDP_PORT)),
    ]
    for name, proto, port in rules:
        try:
            # Check if rule already exists
            check = subprocess.run(
                ["netsh", "advfirewall", "firewall", "show", "rule", f"name={name}"],
                capture_output=True, text=True
            )
            if "No rules match" in check.stdout or check.returncode != 0:
                subprocess.run(
                    [
                        "netsh", "advfirewall", "firewall", "add", "rule",
                        f"name={name}",
                        "dir=in",
                        "action=allow",
                        f"protocol={proto}",
                        f"localport={port}",
                        "profile=private,domain",
                    ],
                    capture_output=True, check=False
                )
                logger.info("[Firewall] Added allow rule: %s %s/%s", name, proto, port)
        except Exception as e:
            logger.debug("[Firewall] Could not set firewall rule %s: %s", name, e)

# Message Types
MSG_AUTH_REQ = 0x01
MSG_AUTH_RESP = 0x02
MSG_AUTH_OK = 0x03
MSG_AUTH_FAIL = 0x04
MSG_CLIPBOARD = 0x05
MSG_FILE_OFFER = 0x06
MSG_FILE_ACCEPT = 0x07
MSG_FILE_REJECT = 0x08
MSG_FILE_STREAM = 0x10
MSG_PING = 0xFE
MSG_PONG = 0xFF


# ---------------------------------------------------------------------------
# Framing & Packet Utilities
# ---------------------------------------------------------------------------
def encode_frame(msg_type: int, payload: bytes) -> bytes:
    """Encodes a control frame: Magic (4B) | Type (1B) | Length (4B uint32) | Payload."""
    header = struct.pack(">4sBI", MAGIC_BYTES, msg_type, len(payload))
    return header + payload


async def read_frame(reader: asyncio.StreamReader) -> Tuple[int, bytes]:
    """Reads a control frame from the stream. Returns (msg_type, payload)."""
    header = await reader.readexactly(9)
    magic, msg_type, length = struct.unpack(">4sBI", header)
    if magic != MAGIC_BYTES:
        raise ValueError(f"Invalid frame magic: {magic!r}")
    payload = await reader.readexactly(length)
    return msg_type, payload


def encode_file_header(filename: str, filesize: int) -> bytes:
    """
    Encodes the binary file transfer header:
    Magic (4B: 'DSYN') | File Name Length (2B uint16) | File Name (UTF-8) | File Size (8B uint64)
    """
    name_bytes = filename.encode("utf-8")
    header = struct.pack(">4sH", MAGIC_BYTES, len(name_bytes))
    header += name_bytes
    header += struct.pack(">Q", filesize)
    return header


async def read_file_header(reader: asyncio.StreamReader) -> Tuple[str, int]:
    """Reads and parses the binary file transfer header from the stream."""
    magic_len = await reader.readexactly(6)  # 4B magic + 2B name length
    magic, name_len = struct.unpack(">4sH", magic_len)
    if magic != MAGIC_BYTES:
        raise ValueError(f"Invalid file header magic: {magic!r}")

    name_bytes = await reader.readexactly(name_len)
    filename = name_bytes.decode("utf-8")

    size_bytes = await reader.readexactly(8)
    (filesize,) = struct.unpack(">Q", size_bytes)

    # Sanitize filename against directory traversal
    clean_name = os.path.basename(filename.replace("\\", "/"))
    if not clean_name:
        clean_name = f"received_file_{int(time.time())}"
    return clean_name, filesize


# ---------------------------------------------------------------------------
# Native Windows & Fallback Clipboard Engine
# ---------------------------------------------------------------------------
class ClipboardEngine:
    """
    High-performance clipboard reader and writer.
    Uses native Win32 ctypes API on Windows (zero pip dependencies required)
    with seamless fallback to pyperclip if present.
    """

    def __init__(self):
        self.is_windows = platform.system() == "Windows"
        self._init_win32()

    def _init_win32(self):
        if not self.is_windows:
            return
        try:
            self.user32 = ctypes.windll.user32
            self.kernel32 = ctypes.windll.kernel32

            self.CF_UNICODETEXT = 13
            self.GMEM_MOVEABLE = 0x0002

            # Define 64-bit safe argtypes and restypes
            self.user32.OpenClipboard.argtypes = [wintypes.HWND]
            self.user32.OpenClipboard.restype = wintypes.BOOL
            self.user32.EmptyClipboard.argtypes = []
            self.user32.EmptyClipboard.restype = wintypes.BOOL
            self.user32.CloseClipboard.argtypes = []
            self.user32.CloseClipboard.restype = wintypes.BOOL
            self.user32.GetClipboardData.argtypes = [wintypes.UINT]
            self.user32.GetClipboardData.restype = wintypes.HANDLE
            self.user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
            self.user32.SetClipboardData.restype = wintypes.HANDLE

            self.kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
            self.kernel32.GlobalAlloc.restype = wintypes.HGLOBAL
            self.kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
            self.kernel32.GlobalLock.restype = wintypes.LPVOID
            self.kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
            self.kernel32.GlobalUnlock.restype = wintypes.BOOL
            self.has_win32 = True
        except Exception as e:
            logger.warning("Win32 clipboard initialization error: %s", e)
            self.has_win32 = False

    def get_text(self) -> Optional[str]:
        if self.is_windows and self.has_win32:
            # Retry up to 3 times in case clipboard is locked by another window
            for _ in range(3):
                if self.user32.OpenClipboard(None):
                    break
                time.sleep(0.02)
            else:
                return None
            try:
                h_clip = self.user32.GetClipboardData(self.CF_UNICODETEXT)
                if not h_clip:
                    return None
                p_text = self.kernel32.GlobalLock(h_clip)
                if not p_text:
                    return None
                try:
                    return ctypes.c_wchar_p(p_text).value
                finally:
                    self.kernel32.GlobalUnlock(h_clip)
            finally:
                self.user32.CloseClipboard()

        # Fallback to pyperclip
        try:
            import pyperclip
            return pyperclip.paste()
        except ImportError:
            return None

    def set_text(self, text: str) -> bool:
        if self.is_windows and self.has_win32:
            for _ in range(5):
                if self.user32.OpenClipboard(None):
                    break
                time.sleep(0.03)
            else:
                return False
            try:
                self.user32.EmptyClipboard()
                data = text.encode("utf-16le") + b"\x00\x00"
                h_mem = self.kernel32.GlobalAlloc(self.GMEM_MOVEABLE, len(data))
                if not h_mem:
                    return False
                p_mem = self.kernel32.GlobalLock(h_mem)
                if not p_mem:
                    return False
                ctypes.memmove(p_mem, data, len(data))
                self.kernel32.GlobalUnlock(h_mem)
                res = self.user32.SetClipboardData(self.CF_UNICODETEXT, h_mem)
                return bool(res)
            finally:
                self.user32.CloseClipboard()

        # Fallback to pyperclip
        try:
            import pyperclip
            pyperclip.copy(text)
            return True
        except ImportError:
            logger.warning("No clipboard write provider available (install pyperclip for non-Windows platforms).")
            return False


# ---------------------------------------------------------------------------
# Background Clipboard Monitor
# ---------------------------------------------------------------------------
class ClipboardMonitor:
    """
    Watches system clipboard changes in a background worker thread.
    Prevents loopbacks/echoes using SHA-256 digest matching.
    """

    def __init__(self, engine: ClipboardEngine, on_change_callback: Callable[[str, str], None]):
        self.engine = engine
        self.on_change = on_change_callback
        self.last_local_hash: Optional[str] = None
        self.last_received_hash: Optional[str] = None
        self.running = False
        self._thread: Optional[threading.Thread] = None

    def start(self):
        self.running = True
        # Prime the initial hash so we don't spam peers on startup
        initial = self.engine.get_text()
        if initial:
            self.last_local_hash = hashlib.sha256(initial.encode("utf-8")).hexdigest()
        self._thread = threading.Thread(target=self._poll_loop, daemon=True, name="ClipboardWatcher")
        self._thread.start()
        logger.info("[Clipboard] Monitor started.")

    def stop(self):
        self.running = False
        if self._thread:
            self._thread.join(timeout=1.0)

    def mark_received(self, text: str, digest: str):
        """Sets incoming remote text and updates last_received_hash to prevent loopback."""
        self.last_received_hash = digest
        self.last_local_hash = digest
        self.engine.set_text(text)
        preview = (text[:40] + "...") if len(text) > 40 else text
        logger.info("[Clipboard] Updated local clipboard from peer (%d chars): %r", len(text), preview)

    def _poll_loop(self):
        while self.running:
            try:
                text = self.engine.get_text()
                if text:
                    text_bytes = text.encode("utf-8")
                    digest = hashlib.sha256(text_bytes).hexdigest()

                    # Loopback check: Ignore if this text was just received from a remote peer
                    if digest == self.last_received_hash:
                        time.sleep(0.3)
                        continue

                    # Change check: Ignore if it hasn't changed locally
                    if digest != self.last_local_hash:
                        self.last_local_hash = digest
                        preview = (text[:40] + "...") if len(text) > 40 else text
                        logger.info("[Clipboard] Local copy detected (%d chars): %r", len(text), preview)
                        self.on_change(text, digest)
            except Exception as e:
                logger.debug("Clipboard poll error: %s", e)
            time.sleep(0.35)


# ---------------------------------------------------------------------------
# Zero-Configuration Discovery Service (UDP Broadcast / Beacon)
# ---------------------------------------------------------------------------
class PeerDiscoveryService:
    """
    Announces this device's presence via UDP broadcast beacons and
    listens for announcements from other DropSync instances on the subnet.
    """

    def __init__(self, device_name: str, device_id: str, tcp_port: int, udp_port: int = DEFAULT_UDP_PORT, pin_required: bool = True):
        self.device_name = device_name
        self.device_id = device_id
        self.tcp_port = tcp_port
        self.udp_port = udp_port
        self.pin_required = pin_required
        self.peers: Dict[str, dict] = {}  # device_id -> peer metadata
        self.running = False
        self._sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None

    def start(self):
        self.running = True
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            self._sock.bind(("", self.udp_port))
        except Exception as e:
            logger.warning("[Discovery] Could not bind UDP port %d: %s. Using send-only broadcast.", self.udp_port, e)

        self._sock.settimeout(1.0)
        self._thread = threading.Thread(target=self._run_loop, daemon=True, name="PeerDiscovery")
        self._thread.start()
        logger.info("[Discovery] Beacon active on UDP port %d (Broadcasting every %.1fs)", self.udp_port, BEACON_INTERVAL)

    def stop(self):
        self.running = False
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
        if self._thread:
            self._thread.join(timeout=1.0)

    def _build_beacon(self) -> bytes:
        payload = {
            "magic": "DROPSYNC_BEACON",
            "version": 1,
            "device_id": self.device_id,
            "device_name": self.device_name,
            "platform": platform.system().lower(),
            "port": self.tcp_port,
            "pin_required": self.pin_required,
        }
        return json.dumps(payload).encode("utf-8")

    def _run_loop(self):
        last_broadcast = 0.0
        # Send 3 rapid beacons at startup for fast initial discovery
        burst_done = False
        burst_count = 0
        burst_times = [0.1, 0.6, 1.2]  # seconds after start
        start_time = time.time()

        while self.running:
            now = time.time()

            # Startup burst beacons
            if not burst_done and burst_count < len(burst_times):
                if now - start_time >= burst_times[burst_count]:
                    try:
                        beacon_bytes = self._build_beacon()
                        for bcast_addr in _get_local_broadcast_addresses():
                            self._sock.sendto(beacon_bytes, (bcast_addr, self.udp_port))
                    except Exception as e:
                        logger.debug("Burst beacon error: %s", e)
                    burst_count += 1
                    if burst_count >= len(burst_times):
                        burst_done = True

            # Periodic beacon
            if now - last_broadcast >= BEACON_INTERVAL:
                try:
                    beacon_bytes = self._build_beacon()
                    for bcast_addr in _get_local_broadcast_addresses():
                        self._sock.sendto(beacon_bytes, (bcast_addr, self.udp_port))
                    last_broadcast = now
                except Exception as e:
                    logger.debug("Beacon broadcast error: %s", e)

            # Receive incoming beacons
            try:
                data, addr = self._sock.recvfrom(4096)
                msg = json.loads(data.decode("utf-8"))
                if msg.get("magic") == "DROPSYNC_BEACON":
                    peer_id = msg.get("device_id")
                    if peer_id and peer_id != self.device_id:
                        ip = addr[0]
                        port = msg.get("port", DEFAULT_TCP_PORT)
                        name = msg.get("device_name", "Unknown")
                        plat = msg.get("platform", "unknown")

                        is_new = peer_id not in self.peers
                        self.peers[peer_id] = {
                            "device_id": peer_id,
                            "device_name": name,
                            "platform": plat,
                            "ip": ip,
                            "port": port,
                            "last_seen": now,
                            "pin_required": msg.get("pin_required", True),
                        }
                        if is_new:
                            logger.info("[Discovery] Discovered new peer: '%s' (%s) at %s:%d", name, plat, ip, port)
            except (socket.timeout, BlockingIOError):
                pass
            except Exception as e:
                logger.debug("Beacon receive error: %s", e)

            # Clean up stale peers (except manual entries)
            stale_keys = [k for k, v in self.peers.items() if not v.get("is_manual") and now - v["last_seen"] > PEER_TIMEOUT]
            for k in stale_keys:
                peer = self.peers.pop(k)
                logger.info("[Discovery] Peer timed out: '%s' (%s)", peer["device_name"], peer["ip"])

            time.sleep(0.05)

    def add_manual_peer(self, ip: str, port: int = DEFAULT_TCP_PORT, name: str = "Mobile Device") -> dict:
        peer_id = f"manual-{ip}:{port}"
        peer = {
            "device_id": peer_id,
            "device_name": name,
            "platform": "manual",
            "ip": ip,
            "port": port,
            "last_seen": time.time(),
            "pin_required": True,
            "is_manual": True,
        }
        self.peers[peer_id] = peer
        logger.info("[Discovery] Added manual peer: %s:%d", ip, port)
        return peer

    def get_active_peers(self) -> List[dict]:
        now = time.time()
        return [v for v in self.peers.values() if v.get("is_manual") or now - v["last_seen"] <= PEER_TIMEOUT]

    def find_peer(self, target: str) -> Optional[dict]:
        """Finds peer by IP address or device name."""
        active = self.get_active_peers()
        for p in active:
            if p["ip"] == target or p["device_name"].lower() == target.lower():
                return p
        return None


# ---------------------------------------------------------------------------
# DropSync Host Server (TCP Core)
# ---------------------------------------------------------------------------
class DropSyncHost:
    """
    Main TCP Host coordinating client connections, PIN authentication,
    clipboard distribution, and high-speed binary file streams.
    """

    def __init__(self, host: str = "0.0.0.0", port: int = DEFAULT_TCP_PORT, pin: str = "1234", save_dir: str = "./downloads"):
        self.host = host
        self.port = port
        self.pin = pin
        self.save_dir = os.path.abspath(save_dir)
        os.makedirs(self.save_dir, exist_ok=True)

        self.device_name = platform.node() or "Windows-PC"
        self.device_id = hashlib.sha256(f"{self.device_name}-{self.port}".encode()).hexdigest()[:16]
        self.session_token = generate_session_token()

        self.clipboard_engine = ClipboardEngine()
        self.clipboard_monitor = ClipboardMonitor(self.clipboard_engine, self._on_local_clipboard_changed)
        self.discovery = PeerDiscoveryService(self.device_name, self.device_id, self.port, DEFAULT_UDP_PORT, pin_required=True)

        self.active_sessions: Dict[str, Tuple[asyncio.StreamReader, asyncio.StreamWriter]] = {}
        self.server: Optional[asyncio.Server] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def _on_local_clipboard_changed(self, text: str, digest: str):
        """Callback from clipboard monitor thread when local user copies text."""
        if not self._loop or self._loop.is_closed():
            return
        payload = json.dumps({"text": text, "hash": digest, "timestamp": int(time.time())}).encode("utf-8")
        frame = encode_frame(MSG_CLIPBOARD, payload)

        async def _broadcast():
            disconnected = []
            for peer_ip, (reader, writer) in list(self.active_sessions.items()):
                try:
                    writer.write(frame)
                    await writer.drain()
                except Exception as e:
                    logger.debug("Failed sending clipboard to %s: %s", peer_ip, e)
                    disconnected.append(peer_ip)
            for ip in disconnected:
                self.active_sessions.pop(ip, None)

        asyncio.run_coroutine_threadsafe(_broadcast(), self._loop)

    async def start(self):
        """Starts the DropSync daemon services."""
        self._loop = asyncio.get_running_loop()

        # Auto-configure Windows Firewall so Android can discover this host
        _apply_firewall_rules()

        try:
            self.server = await asyncio.start_server(self._handle_client, self.host, self.port)
        except OSError as e:
            if getattr(e, 'winerror', None) == 10048 or 'address already in use' in str(e).lower():
                logger.error("[Port Conflict] TCP Port %d is already in use by another running DropSync instance.", self.port)
                logger.error("-> If a previous host is still running in the background, close it or use a different port, e.g.:")
                logger.error("   python dropsync_host.py --port %d", self.port + 1)
            raise

        self.clipboard_monitor.start()
        self.discovery.start()

        # Log local IP for manual fallback
        local_ip = "unknown"
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            pass

        addrs = ", ".join(str(sock.getsockname()) for sock in self.server.sockets)
        logger.info("=" * 65)
        logger.info(" DropSync Host Daemon Running")
        logger.info(" Device Name : %s (%s)", self.device_name, platform.system())
        logger.info(" Local IP    : %s  <-- enter this on Android if discovery fails", local_ip)
        logger.info(" TCP Listener: %s", addrs)
        logger.info(" Active PIN  : %s", self.pin)
        logger.info(" Pairing Token: %s", self.session_token)
        logger.info(" Save Folder : %s", self.save_dir)
        logger.info("=" * 65)

    def regenerate_session_token(self) -> str:
        """Regenerates a fresh session token for QR code pairing."""
        self.session_token = generate_session_token()
        logger.info("[Auth] Regenerated session token: %s", self.session_token)
        return self.session_token

    def generate_qr_payload(
        self,
        ssid: Optional[str] = None,
        password: Optional[str] = None,
        is_hotspot: bool = False,
    ) -> str:
        """Encodes receiver connection parameters into a JSON string for QR pairing, including optional Hotspot info."""
        local_ip = "127.0.0.1"
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            pass

        # If hotspot mode is requested and on Windows/Linux, check for common hotspot subnets
        if is_hotspot and local_ip == "127.0.0.1":
            local_ip = "192.168.137.1" if platform.system() == "Windows" else "192.168.43.1"

        payload = {
            "magic": "DROPSYNC_QR",
            "ip": local_ip,
            "port": self.port,
            "token": self.session_token,
            "device": self.device_name,
            "platform": platform.system().lower(),
        }
        if is_hotspot and ssid:
            payload["ssid"] = ssid
            payload["password"] = password or ""
            payload["auth"] = "WPA2"
            payload["isHotspot"] = True

        return json.dumps(payload)

    def generate_wifi_qr_payload(
        self,
        ssid: str,
        password: str = "",
        auth_type: str = "WPA",
    ) -> str:
        """Generates standard ZXing Wi-Fi QR payload (WIFI:S:...;T:WPA;P:...;;) for mobile camera pairing."""
        local_ip = "127.0.0.1"
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            pass
        return f"WIFI:S:{ssid};T:{auth_type};P:{password};IP:{local_ip};PORT:{self.port};TOKEN:{self.session_token};;"

    async def stop(self):
        """Shuts down all listeners and workers cleanly."""
        self.clipboard_monitor.stop()
        self.discovery.stop()
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        for ip, (r, w) in list(self.active_sessions.items()):
            try:
                w.close()
                await w.wait_closed()
            except Exception:
                pass
        self.active_sessions.clear()
        logger.info("[DropSync] Daemon stopped cleanly.")

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Manages an incoming TCP client connection lifecycle."""
        peer_addr = writer.get_extra_info("peername")
        peer_ip = peer_addr[0] if peer_addr else "unknown"
        logger.info("[Connection] Incoming connection from %s:%s", peer_ip, peer_addr[1] if peer_addr else "")

        # Step 1: Authentication Handshake
        try:
            auth_req = json.dumps({
                "device_name": self.device_name,
                "platform": platform.system().lower(),
                "pin_required": bool(self.pin),
            }).encode("utf-8")
            writer.write(encode_frame(MSG_AUTH_REQ, auth_req))
            await writer.drain()

            msg_type, payload = await asyncio.wait_for(read_frame(reader), timeout=15.0)
            if msg_type != MSG_AUTH_RESP:
                logger.warning("[Auth] Expected AUTH_RESP, got 0x%02X from %s", msg_type, peer_ip)
                writer.close()
                await writer.wait_closed()
                return

            auth_data = json.loads(payload.decode("utf-8"))
            provided_pin = str(auth_data.get("pin", "")).strip()
            provided_token = str(auth_data.get("token", "")).strip()
            client_name = auth_data.get("device_name", peer_ip)

            is_token_match = bool(self.session_token and (provided_token == self.session_token or provided_pin == self.session_token))
            is_pin_match = bool(self.pin and provided_pin == self.pin)

            if not is_token_match and not is_pin_match and (self.pin or self.session_token):
                logger.warning("[Auth] REJECTED connection from %s ('%s'): Invalid Token/PIN (token='%s', pin='%s')", peer_ip, client_name, provided_token, provided_pin)
                writer.write(encode_frame(MSG_AUTH_FAIL, json.dumps({"error": "invalid_auth"}).encode()))
                await writer.drain()
                writer.close()
                await writer.wait_closed()
                return

            # Auth OK
            writer.write(encode_frame(MSG_AUTH_OK, json.dumps({"status": "authenticated"}).encode()))
            await writer.drain()
            logger.info("[Auth] SUCCESS: Connected and paired with '%s' (%s)", client_name, peer_ip)
            self.active_sessions[peer_ip] = (reader, writer)
        except Exception as e:
            logger.warning("[Auth] Handshake failed with %s: %s", peer_ip, e)
            writer.close()
            await writer.wait_closed()
            return

        # Step 2: Message & Stream Processing Loop
        try:
            while True:
                # Peek 4 bytes to check if it's a binary file stream header or a control frame
                header_peek = await reader.readexactly(4)
                if header_peek != MAGIC_BYTES:
                    logger.warning("[Stream] Unexpected magic bytes: %r from %s", header_peek, peer_ip)
                    break

                # Next byte determines if it's a binary file stream or standard framed control message
                next_byte = await reader.readexactly(1)
                b = next_byte[0]

                # In control frames, byte 4 is msg_type (0x01-0x08, 0xFE, 0xFF)
                # In binary file header, byte 4-5 is uint16 filename length
                # To support both seamlessly: MSG_FILE_STREAM (0x10) triggers binary file reader.
                if b == MSG_FILE_STREAM:
                    # Payload length of control frame is ignored; directly streams file
                    (payload_len,) = struct.unpack(">I", await reader.readexactly(4))
                    await self._receive_file_stream(reader, writer, peer_ip)
                elif b == MSG_CLIPBOARD:
                    (payload_len,) = struct.unpack(">I", await reader.readexactly(4))
                    payload = await reader.readexactly(payload_len)
                    data = json.loads(payload.decode("utf-8"))
                    text = data.get("text", "")
                    digest = data.get("hash", "")
                    self.clipboard_monitor.mark_received(text, digest)
                elif b == MSG_PING:
                    (payload_len,) = struct.unpack(">I", await reader.readexactly(4))
                    if payload_len > 0:
                        await reader.readexactly(payload_len)
                    writer.write(encode_frame(MSG_PONG, b""))
                    await writer.drain()
                elif b == MSG_FILE_OFFER:
                    (payload_len,) = struct.unpack(">I", await reader.readexactly(4))
                    payload = await reader.readexactly(payload_len)
                    offer = json.loads(payload.decode("utf-8"))
                    logger.info("[File Offer] Incoming offer from %s: '%s' (%s bytes)", peer_ip, offer.get("name"), offer.get("size"))
                    # Auto-accept since connection was authenticated via PIN
                    writer.write(encode_frame(MSG_FILE_ACCEPT, json.dumps({"accept": True}).encode()))
                    await writer.drain()
                else:
                    (payload_len,) = struct.unpack(">I", await reader.readexactly(4))
                    payload = await reader.readexactly(payload_len)
                    logger.debug("Received unhandled frame type 0x%02X (%d bytes)", b, payload_len)
        except (asyncio.IncompleteReadError, ConnectionResetError, BrokenPipeError):
            logger.info("[Connection] Peer %s disconnected.", peer_ip)
        except Exception as e:
            logger.error("[Connection] Session error with %s: %s", peer_ip, e)
        finally:
            self.active_sessions.pop(peer_ip, None)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _receive_file_stream(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, peer_ip: str):
        """
        Receives an arbitrary-sized binary file streamed in 64 KB chunks.
        Saves directly to a temporary `.part` file, updates live progress,
        and atomically renames upon completion verification.
        """
        filename, filesize = await read_file_header(reader)
        logger.info("[File Transfer] Started incoming: '%s' (%s bytes / %.2f MB)", filename, f"{filesize:,}", filesize / (1024 * 1024))

        # Target and temporary file paths
        final_path = self._resolve_unique_path(self.save_dir, filename)
        part_path = final_path + ".part"

        bytes_received = 0
        start_time = time.time()
        last_progress_time = start_time

        try:
            with open(part_path, "wb") as f:
                while bytes_received < filesize:
                    remaining = filesize - bytes_received
                    chunk_size = min(CHUNK_SIZE, remaining)
                    chunk = await reader.readexactly(chunk_size)
                    f.write(chunk)
                    bytes_received += len(chunk)

                    # Progress reporting every 0.25s
                    now = time.time()
                    if now - last_progress_time >= 0.25 or bytes_received == filesize:
                        elapsed = max(0.001, now - start_time)
                        speed_mb = (bytes_received / (1024 * 1024)) / elapsed
                        pct = (bytes_received / filesize) * 100 if filesize > 0 else 100.0
                        eta = (filesize - bytes_received) / (speed_mb * 1024 * 1024) if speed_mb > 0 else 0
                        sys.stdout.write(f"\r[Transfer] Recv '{filename}': {pct:5.1f}% | {bytes_received / (1024 * 1024):6.1f}/{filesize / (1024 * 1024):6.1f} MB | {speed_mb:5.1f} MB/s | ETA: {eta:3.0f}s")
                        sys.stdout.flush()
                        last_progress_time = now

            sys.stdout.write("\n")
            sys.stdout.flush()

            # Atomic rename upon completion verification
            if bytes_received == filesize:
                os.replace(part_path, final_path)
                total_time = max(0.001, time.time() - start_time)
                avg_speed = (filesize / (1024 * 1024)) / total_time
                logger.info("[File Transfer] Completed: '%s' saved to '%s' (Avg: %.2f MB/s in %.2fs)", filename, final_path, avg_speed, total_time)
            else:
                raise IOError(f"Byte count mismatch: received {bytes_received} of {filesize}")
        except Exception as e:
            logger.error("[File Transfer] Failed receiving '%s': %s", filename, e)
            if os.path.exists(part_path):
                try:
                    os.remove(part_path)
                except Exception:
                    pass
            raise

    def _resolve_unique_path(self, directory: str, filename: str) -> str:
        """Appends (1), (2), etc. if destination file already exists."""
        base, ext = os.path.splitext(filename)
        candidate = os.path.join(directory, filename)
        counter = 1
        while os.path.exists(candidate):
            candidate = os.path.join(directory, f"{base} ({counter}){ext}")
            counter += 1
        return candidate

    async def send_file(self, target_ip: str, file_path: str, target_port: int = DEFAULT_TCP_PORT, pin: Optional[str] = None, token: Optional[str] = None) -> bool:
        """
        Sends an arbitrary binary file to a remote peer over a high-throughput chunked stream.
        """
        if not os.path.isfile(file_path):
            logger.error("[File Transfer] File not found: '%s'", file_path)
            return False

        filesize = os.path.getsize(file_path)
        filename = os.path.basename(file_path)
        logger.info("[File Transfer] Preparing to send '%s' (%s bytes / %.2f MB) to %s:%d", filename, f"{filesize:,}", filesize / (1024 * 1024), target_ip, target_port)

        writer: Optional[asyncio.StreamWriter] = None
        try:
            # Check if we have an existing authenticated session, or open a new connection
            if target_ip in self.active_sessions:
                reader, writer = self.active_sessions[target_ip]
            else:
                logger.info("[File Transfer] Establishing connection to %s:%d...", target_ip, target_port)
                reader, writer = await asyncio.open_connection(target_ip, target_port)
                # Auth Handshake
                msg_type, payload = await asyncio.wait_for(read_frame(reader), timeout=10.0)
                if msg_type != MSG_AUTH_REQ:
                    raise ConnectionError("Peer did not request authentication")
                used_pin = pin if pin is not None else self.pin
                used_token = token if token is not None else used_pin
                auth_resp = json.dumps({"pin": used_pin, "token": used_token, "device_name": self.device_name}).encode("utf-8")
                writer.write(encode_frame(MSG_AUTH_RESP, auth_resp))
                await writer.drain()

                msg_type, payload = await asyncio.wait_for(read_frame(reader), timeout=10.0)
                if msg_type != MSG_AUTH_OK:
                    raise ConnectionError(f"Authentication rejected by peer: {payload.decode('utf-8', errors='ignore')}")

            # Notify peer of file stream
            stream_notify = encode_frame(MSG_FILE_STREAM, b"")
            writer.write(stream_notify)
            await writer.drain()

            # Write binary wire protocol header:
            # Magic (4B) | Name Len (2B) | Name (UTF-8) | File Size (8B)
            header_bytes = encode_file_header(filename, filesize)
            writer.write(header_bytes)
            await writer.drain()

            # Stream body in 64 KB chunks
            bytes_sent = 0
            start_time = time.time()
            last_progress = start_time

            with open(file_path, "rb") as f:
                while bytes_sent < filesize:
                    chunk = f.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    writer.write(chunk)
                    await writer.drain()
                    bytes_sent += len(chunk)

                    now = time.time()
                    if now - last_progress >= 0.25 or bytes_sent == filesize:
                        elapsed = max(0.001, now - start_time)
                        speed_mb = (bytes_sent / (1024 * 1024)) / elapsed
                        pct = (bytes_sent / filesize) * 100 if filesize > 0 else 100.0
                        eta = (filesize - bytes_sent) / (speed_mb * 1024 * 1024) if speed_mb > 0 else 0
                        sys.stdout.write(f"\r[Transfer] Send '{filename}': {pct:5.1f}% | {bytes_sent / (1024 * 1024):6.1f}/{filesize / (1024 * 1024):6.1f} MB | {speed_mb:5.1f} MB/s | ETA: {eta:3.0f}s")
                        sys.stdout.flush()
                        last_progress = now

            sys.stdout.write("\n")
            sys.stdout.flush()
            total_time = max(0.001, time.time() - start_time)
            avg_speed = (filesize / (1024 * 1024)) / total_time
            logger.info("[File Transfer] Successfully sent '%s' to %s in %.2fs (Avg: %.2f MB/s)", filename, target_ip, total_time, avg_speed)
            return True
        except Exception as e:
            logger.error("[File Transfer] Send failed to %s: %s", target_ip, e)
            return False


# ---------------------------------------------------------------------------
# Interactive Shell & CLI Management
# ---------------------------------------------------------------------------
async def interactive_cli(host: DropSyncHost):
    """Provides an interactive command prompt for testing and manual control."""
    loop = asyncio.get_running_loop()
    print("\nDropSync CLI Ready. Type 'help' for available commands.")

    while True:
        try:
            line = await loop.run_in_executor(None, input, "DropSync> ")
            cmd_parts = line.strip().split()
            if not cmd_parts:
                continue

            cmd = cmd_parts[0].lower()

            if cmd in ("exit", "quit", "q"):
                print("Exiting...")
                break
            elif cmd == "help":
                print("""
Available Commands:
  peers                - List all active peers discovered on the LAN
  send <target> <file> - Send file to peer (target can be IP or Peer Name)
  clip <text>          - Push text to local clipboard & sync to connected peers
  pin [new_pin]        - Show or update the current security PIN
  status               - Show active connections and local host info
  clear                - Clear console screen
  quit / exit          - Terminate DropSync host
                """)
            elif cmd == "peers":
                active = host.discovery.get_active_peers()
                if not active:
                    print("  No peers discovered yet on the local subnet.")
                else:
                    print(f"  {'DEVICE NAME':<20} {'PLATFORM':<12} {'IP ADDRESS':<16} {'PORT':<6}")
                    print("  " + "-" * 56)
                    for p in active:
                        print(f"  {p['device_name']:<20} {p['platform']:<12} {p['ip']:<16} {p['port']:<6}")
            elif cmd == "send":
                if len(cmd_parts) < 3:
                    print("  Usage: send <target_ip_or_name> <file_path>")
                    continue
                target = cmd_parts[1]
                filepath = " ".join(cmd_parts[2:]).strip('"').strip("'")

                # Resolve target IP if name was provided
                peer = host.discovery.find_peer(target)
                target_ip = peer["ip"] if peer else target
                target_port = peer["port"] if peer else host.port

                await host.send_file(target_ip, filepath, target_port)
            elif cmd == "clip":
                if len(cmd_parts) < 2:
                    print("  Usage: clip <text to copy and broadcast>")
                    continue
                text = " ".join(cmd_parts[1:])
                host.clipboard_engine.set_text(text)
                digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
                host.clipboard_monitor.last_local_hash = digest
                host._on_local_clipboard_changed(text, digest)
                print(f"  Copied and synced {len(text)} characters.")
            elif cmd == "pin":
                if len(cmd_parts) > 1:
                    host.pin = cmd_parts[1].strip()
                    print(f"  Security PIN updated to: {host.pin}")
                else:
                    print(f"  Current Security PIN: {host.pin}")
            elif cmd == "status":
                print(f"  Host: {host.device_name} ({platform.system()})")
                print(f"  Listening on TCP port: {host.port}, UDP port: {host.discovery.udp_port}")
                print(f"  Save folder: {host.save_dir}")
                print(f"  Active connections: {len(host.active_sessions)} peers ({', '.join(host.active_sessions.keys()) or 'None'})")
                print(f"  Discovered LAN peers: {len(host.discovery.get_active_peers())}")
            elif cmd == "clear":
                os.system("cls" if os.name == "nt" else "clear")
            else:
                print(f"  Unknown command '{cmd}'. Type 'help' for options.")
        except (EOFError, KeyboardInterrupt):
            break
        except Exception as e:
            print(f"  Error: {e}")


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="DropSync Host Daemon (Local P2P Clipboard & File Sync)")
    parser.add_argument("--port", type=int, default=DEFAULT_TCP_PORT, help=f"TCP port for data & streams (default: {DEFAULT_TCP_PORT})")
    parser.add_argument("--udp-port", type=int, default=DEFAULT_UDP_PORT, help=f"UDP port for discovery (default: {DEFAULT_UDP_PORT})")
    parser.add_argument("--pin", type=str, default="1234", help="Security PIN required to pair (default: 1234)")
    parser.add_argument("--save-dir", type=str, default="./downloads", help="Directory for received files (default: ./downloads)")
    parser.add_argument("--send", nargs=2, metavar=("FILE", "PEER_IP"), help="Directly send a file to a peer IP and exit")
    parser.add_argument("--daemon", action="store_true", help="Run in non-interactive daemon mode")

    args = parser.parse_args()

    host = DropSyncHost(
        port=args.port,
        pin=args.pin,
        save_dir=args.save_dir,
    )
    host.discovery.udp_port = args.udp_port

    async def _async_main():
        await host.start()

        if args.send:
            file_to_send, target_ip = args.send
            success = await host.send_file(target_ip, file_to_send, args.port)
            await host.stop()
            sys.exit(0 if success else 1)

        if args.daemon:
            logger.info("Running in daemon mode. Press Ctrl+C to terminate.")
            try:
                while True:
                    await asyncio.sleep(3600)
            except asyncio.CancelledError:
                pass
        else:
            await interactive_cli(host)

        await host.stop()

    try:
        asyncio.run(_async_main())
    except KeyboardInterrupt:
        logger.info("DropSync host shutting down.")
    except OSError as e:
        if getattr(e, "winerror", None) == 10048 or "address already in use" in str(e).lower():
            sys.exit(1)
        raise


if __name__ == "__main__":
    main()
