#!/usr/bin/env python3
"""
DropSync Desktop GUI Application (Windows / Cross-Platform)
-----------------------------------------------------------
A Gemini-inspired graphical desktop application for DropSync featuring:
- Role-based workflows: Explicit Send, Receive, and Dual modes.
- Dynamic QR code generation for one-tap mobile camera pairing.
- Session-based one-time token authentication.
- Real-time LAN peer discovery radar with device icons.
- One-click file sharing with real-time transfer progress, speed (MB/s), and ETA.
- Live bidirectional clipboard synchronization with SHA-256 loopback suppression.
"""

import asyncio
import json
import os
import platform
import socket
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from typing import Optional, List, Dict

import qrcode
from PIL import Image, ImageTk

# Import core protocol and host engine
from dropsync_host import (
    DropSyncHost,
    DEFAULT_TCP_PORT,
    DEFAULT_UDP_PORT,
    CHUNK_SIZE,
)


def _get_primary_ip() -> str:
    """Detects the primary LAN IP address of this machine."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


class DropSyncAppUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("DropSync - Local P2P Sharing")
        self.root.geometry("780x720")
        self.root.minsize(680, 600)
        self.root.configure(bg="#0C0C0E")

        # Set App Icon
        self._apply_icon()

        # Application state
        self.pin = "1234"
        self.downloads_dir = os.path.abspath("./downloads")
        os.makedirs(self.downloads_dir, exist_ok=True)

        self.host: Optional[DropSyncHost] = None
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self.server_thread: Optional[threading.Thread] = None

        self.peers = []
        self.active_role = "send"  # "send", "receive", "dual"
        self.selected_file_path: Optional[str] = None

        # Build UI
        self._setup_styles()
        self._build_widgets()

        # Start DropSync background engine
        self._start_engine()

        # Periodic UI update timer (every 500ms)
        self.root.after(500, self._periodic_refresh)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _apply_icon(self):
        try:
            base_dir = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))
            ico_path = os.path.join(base_dir, "windows", "runner", "resources", "app_icon.ico")
            if os.path.exists(ico_path):
                self.root.iconbitmap(ico_path)
            png_path = os.path.join(base_dir, "assets", "icon", "dropsync_icon.png")
            if os.path.exists(png_path):
                img = tk.PhotoImage(file=png_path)
                self.root.iconphoto(True, img)
                self._icon_img_ref = img
        except Exception:
            pass

    def _setup_styles(self):
        self.style = ttk.Style()
        self.style.theme_use("clam")

        # V.O.I.D. Cognitive OS Obsidian & Cyberpunk Neon Orange Colors
        bg_dark = "#0C0C0E"
        card_bg = "#151518"
        accent_orange = "#FF5500"
        accent_amber = "#FF7A00"
        text_white = "#FFFFFF"

        self.style.configure(".", background=bg_dark, foreground=text_white)
        self.style.configure("Card.TFrame", background=card_bg, relief="flat")
        self.style.configure(
            "Accent.TButton",
            background=accent_orange,
            foreground="#FFFFFF",
            font=("Segoe UI", 10, "bold"),
            borderwidth=0,
            padding=7,
        )
        self.style.map("Accent.TButton", background=[("active", accent_amber), ("pressed", "#FF3D00")])

        self.style.configure(
            "Secondary.TButton",
            background="#1E1E23",
            foreground="#FFFFFF",
            font=("Segoe UI", 9),
            borderwidth=0,
            padding=6,
        )
        self.style.map("Secondary.TButton", background=[("active", "#2C2C34")])

        self.style.configure(
            "Gemini.Horizontal.TProgressbar",
            troughcolor="#0C0C0E",
            background=accent_orange,
            bordercolor="#151518",
            lightcolor=accent_amber,
            darkcolor="#FF3D00",
        )

    def _build_widgets(self):
        # 1. Top Navbar Header
        nav_frame = tk.Frame(self.root, bg="#111113", padx=20, pady=14, highlightthickness=1, highlightbackground="#26262B")
        nav_frame.pack(fill="x", side="top")

        left_nav = tk.Frame(nav_frame, bg="#111113")
        left_nav.pack(side="left")

        lbl_logo = tk.Label(left_nav, text="⚡ DropSync", font=("Segoe UI", 16, "bold"), bg="#111113", fg="#FF7A00")
        lbl_logo.pack(side="left", padx=(0, 10))

        pc_name = platform.node() or "Windows-PC"
        lbl_pc = tk.Label(left_nav, text=f"•  {pc_name}", font=("Segoe UI", 11), bg="#111113", fg="#A1A1AA")
        lbl_pc.pack(side="left")

        right_nav = tk.Frame(nav_frame, bg="#111113")
        right_nav.pack(side="right")

        self.local_ip = _get_primary_ip()
        lbl_ip_pill = tk.Label(
            right_nav,
            text=f"● {self.local_ip}",
            font=("Consolas", 10, "bold"),
            bg="#1A1A1E",
            fg="#10B981",
            padx=10,
            pady=4,
            highlightthickness=1,
            highlightbackground="#26262B",
        )
        lbl_ip_pill.pack(side="right", padx=(8, 0))

        btn_folder = ttk.Button(right_nav, text="📁 Downloads", style="Secondary.TButton", command=self._open_downloads_folder)
        btn_folder.pack(side="right")

        # 2. V.O.I.D. Role Selection Pill Switcher
        tab_container = tk.Frame(self.root, bg="#0C0C0E", pady=10)
        tab_container.pack(fill="x")

        switcher_frame = tk.Frame(tab_container, bg="#151518", padx=4, pady=4, highlightthickness=1, highlightbackground="#26262B")
        switcher_frame.pack(anchor="center")

        self.btn_tab_send = tk.Button(
            switcher_frame, text="📤 Send Files", font=("Segoe UI", 10, "bold"),
            bg="#FF5500", fg="#FFFFFF", relief="flat", padx=16, pady=6, cursor="hand2",
            command=lambda: self._set_role("send")
        )
        self.btn_tab_send.pack(side="left", padx=2)

        self.btn_tab_receive = tk.Button(
            switcher_frame, text="📥 Receive / QR", font=("Segoe UI", 10),
            bg="#151518", fg="#A1A1AA", relief="flat", padx=16, pady=6, cursor="hand2",
            command=lambda: self._set_role("receive")
        )
        self.btn_tab_receive.pack(side="left", padx=2)

        self.btn_tab_dual = tk.Button(
            switcher_frame, text="⚡ Dual / Clipboard", font=("Segoe UI", 10),
            bg="#151518", fg="#A1A1AA", relief="flat", padx=16, pady=6, cursor="hand2",
            command=lambda: self._set_role("dual")
        )
        self.btn_tab_dual.pack(side="left", padx=2)

        # 3. Main Dynamic Content Container
        self.content_container = tk.Frame(self.root, bg="#0C0C0E", padx=20)
        self.content_container.pack(fill="both", expand=True)

        # Frames for the three roles
        self.frame_send = tk.Frame(self.content_container, bg="#0C0C0E")
        self.frame_receive = tk.Frame(self.content_container, bg="#0C0C0E")
        self.frame_dual = tk.Frame(self.content_container, bg="#0C0C0E")

        self._build_send_view()
        self._build_receive_view()
        self._build_dual_view()

        # Display initial role
        self._set_role("send")

        # 4. Bottom Active Transfer & Status Footer
        self.footer_card = tk.Frame(self.root, bg="#151518", padx=18, pady=12, highlightthickness=1, highlightbackground="#26262B")
        self.footer_card.pack(fill="x", side="bottom")

        self.lbl_transfer_name = tk.Label(self.footer_card, text="Ready for local transfers", font=("Segoe UI", 10, "bold"), bg="#151518", fg="#A1A1AA")
        self.lbl_transfer_name.pack(anchor="w")

        self.progress_bar = ttk.Progressbar(self.footer_card, style="Gemini.Horizontal.TProgressbar", length=100, mode="determinate")
        self.progress_bar.pack(fill="x", pady=(6, 4))

        self.lbl_transfer_stats = tk.Label(self.footer_card, text="Engine listening on Port 52525", font=("Segoe UI", 9), bg="#151518", fg="#71717A")
        self.lbl_transfer_stats.pack(anchor="w")

    def _set_role(self, role: str):
        self.active_role = role

        # Update tab button styles
        self.btn_tab_send.config(
            bg="#FF5500" if role == "send" else "#151518",
            fg="#FFFFFF" if role == "send" else "#A1A1AA",
            font=("Segoe UI", 10, "bold" if role == "send" else "normal")
        )
        self.btn_tab_receive.config(
            bg="#FF7A00" if role == "receive" else "#151518",
            fg="#FFFFFF" if role == "receive" else "#A1A1AA",
            font=("Segoe UI", 10, "bold" if role == "receive" else "normal")
        )
        self.btn_tab_dual.config(
            bg="#FF3D00" if role == "dual" else "#151518",
            fg="#FFFFFF" if role == "dual" else "#A1A1AA",
            font=("Segoe UI", 10, "bold" if role == "dual" else "normal")
        )

        # Show appropriate frame
        self.frame_send.pack_forget()
        self.frame_receive.pack_forget()
        self.frame_dual.pack_forget()

        if role == "send":
            self.frame_send.pack(fill="both", expand=True)
        elif role == "receive":
            self.frame_receive.pack(fill="both", expand=True)
            self._refresh_qr_display()
        elif role == "dual":
            self.frame_dual.pack(fill="both", expand=True)

    # -------------------------------------------------------------------------
    # SEND VIEW BUILDER
    # -------------------------------------------------------------------------
    def _build_send_view(self):
        # 1. File Selection Drop Zone Card
        file_card = tk.Frame(self.frame_send, bg="#151518", padx=18, pady=16, highlightthickness=1, highlightbackground="#26262B")
        file_card.pack(fill="x", pady=(0, 12))

        top_file_row = tk.Frame(file_card, bg="#151518")
        top_file_row.pack(fill="x")

        lbl_f_title = tk.Label(top_file_row, text="📁 File to Send", font=("Segoe UI", 11, "bold"), bg="#151518", fg="#FFFFFF")
        lbl_f_title.pack(side="left")

        self.btn_clear_file = ttk.Button(top_file_row, text="Clear", style="Secondary.TButton", command=self._clear_selected_file)

        # Select file button
        self.lbl_selected_file = tk.Label(
            file_card,
            text="No file selected • Click 'Browse File' to pick photos, videos, or documents",
            font=("Segoe UI", 9),
            bg="#151518",
            fg="#A1A1AA",
            wraplength=600,
        )
        self.lbl_selected_file.pack(anchor="w", pady=(8, 10))

        btn_row = tk.Frame(file_card, bg="#151518")
        btn_row.pack(fill="x")

        ttk.Button(btn_row, text="Browse File...", style="Accent.TButton", command=self._browse_file).pack(side="left")
        ttk.Button(btn_row, text="+ Connect by IP / Token", style="Secondary.TButton", command=self._show_manual_connect_dialog).pack(side="left", padx=(10, 0))

        # 2. Discovered Devices (Radar)
        lbl_radar_title = tk.Label(self.frame_send, text="Nearby Discovered Devices", font=("Segoe UI", 12, "bold"), bg="#0C0C0E", fg="#FFFFFF")
        lbl_radar_title.pack(anchor="w", pady=(6, 6))

        peers_container = tk.Frame(self.frame_send, bg="#151518", highlightthickness=1, highlightbackground="#26262B")
        peers_container.pack(fill="both", expand=True)

        self.canvas_peers = tk.Canvas(peers_container, bg="#151518", highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(peers_container, orient="vertical", command=self.canvas_peers.yview)
        self.peers_scroll_frame = tk.Frame(self.canvas_peers, bg="#151518")

        self.peers_scroll_frame.bind("<Configure>", lambda e: self.canvas_peers.configure(scrollregion=self.canvas_peers.bbox("all")))
        self.canvas_window = self.canvas_peers.create_window((0, 0), window=self.peers_scroll_frame, anchor="nw")
        self.canvas_peers.configure(yscrollcommand=self.scrollbar.set)
        self.canvas_peers.bind("<Configure>", lambda e: self.canvas_peers.itemconfig(self.canvas_window, width=e.width))

        self.canvas_peers.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")

        self.lbl_empty_peers = tk.Label(
            self.peers_scroll_frame,
            text="Searching for DropSync devices on local Wi-Fi...\nOpen DropSync on your Android phone or another PC on the same Wi-Fi.\n(Or click '+ Connect by IP / Token' above)",
            font=("Segoe UI", 11),
            bg="#151518",
            fg="#71717A",
            pady=40,
        )
        self.lbl_empty_peers.pack(fill="both", expand=True)

    def _browse_file(self):
        filepath = filedialog.askopenfilename(title="Select file to send")
        if filepath:
            self.selected_file_path = filepath
            size_mb = os.path.getsize(filepath) / (1024 * 1024)
            name = os.path.basename(filepath)
            self.lbl_selected_file.config(text=f"Ready to send: {name} ({size_mb:.2f} MB)", fg="#FFA033")
            self.btn_clear_file.pack(side="right")

    def _clear_selected_file(self):
        self.selected_file_path = None
        self.lbl_selected_file.config(text="No file selected • Click 'Browse File' to pick photos, videos, or documents", fg="#A1A1AA")
        self.btn_clear_file.pack_forget()

    # -------------------------------------------------------------------------
    # RECEIVE VIEW BUILDER (QR CODE & TOKEN)
    # -------------------------------------------------------------------------
    def _build_receive_view(self):
        center_card = tk.Frame(self.frame_receive, bg="#151518", padx=24, pady=20, highlightthickness=1, highlightbackground="#26262B")
        center_card.pack(fill="both", expand=True)

        # Standby status
        lbl_standby = tk.Label(
            center_card,
            text="● Standby Mode • Ready to receive incoming files",
            font=("Segoe UI", 10, "bold"),
            bg="#111113",
            fg="#10B981",
            padx=14,
            pady=6,
            highlightthickness=1,
            highlightbackground="#26262B",
        )
        lbl_standby.pack(anchor="center", pady=(0, 16))

        # QR Code Image Label
        self.lbl_qr = tk.Label(center_card, bg="#FFFFFF", padx=10, pady=10)
        self.lbl_qr.pack(anchor="center", pady=6)

        lbl_scan_hint = tk.Label(
            center_card,
            text="Scan with the DropSync mobile app to pair & send files immediately",
            font=("Segoe UI", 10),
            bg="#151518",
            fg="#A1A1AA",
        )
        lbl_scan_hint.pack(anchor="center", pady=(6, 16))

        # Pairing Token Box
        token_box = tk.Frame(center_card, bg="#0C0C0E", padx=16, pady=12, highlightthickness=1, highlightbackground="#26262B")
        token_box.pack(fill="x", padx=40)

        lbl_t_header = tk.Label(token_box, text="Session Pairing Token", font=("Segoe UI", 9), bg="#0C0C0E", fg="#71717A")
        lbl_t_header.pack(anchor="w")

        token_row = tk.Frame(token_box, bg="#0C0C0E")
        token_row.pack(fill="x", pady=(4, 0))

        self.lbl_token = tk.Label(token_row, text="A  7  B  3  X  9", font=("Consolas", 18, "bold"), bg="#0C0C0E", fg="#FFA033")
        self.lbl_token.pack(side="left")

        ttk.Button(token_row, text="Copy Token", style="Secondary.TButton", command=self._copy_token).pack(side="right")
        ttk.Button(token_row, text="Regenerate", style="Secondary.TButton", command=self._regenerate_token).pack(side="right", padx=(0, 6))

    def _refresh_qr_display(self):
        if not self.host:
            return
        payload_str = self.host.generate_qr_payload()
        self.lbl_token.config(text="  ".join(self.host.session_token))

        try:
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=5,
                border=2,
            )
            qr.add_data(payload_str)
            qr.make(fit=True)
            img = qr.make_image(fill_color="#0C0C0E", back_color="#FFFFFF")
            self.qr_photo = ImageTk.PhotoImage(img)
            self.lbl_qr.config(image=self.qr_photo)
        except Exception as e:
            print("QR render error:", e)

    def _copy_token(self):
        if self.host:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.host.session_token)
            messagebox.showinfo("DropSync", f"Copied session token '{self.host.session_token}' to clipboard!")

    def _regenerate_token(self):
        if self.host:
            self.host.regenerate_session_token()
            self._refresh_qr_display()

    # -------------------------------------------------------------------------
    # DUAL VIEW BUILDER (CLIPBOARD + STATUS)
    # -------------------------------------------------------------------------
    def _build_dual_view(self):
        clip_card = tk.Frame(self.frame_dual, bg="#151518", padx=18, pady=16, highlightthickness=1, highlightbackground="#26262B")
        clip_card.pack(fill="x", pady=(0, 12))

        clip_header = tk.Frame(clip_card, bg="#151518")
        clip_header.pack(fill="x")

        lbl_clip_title = tk.Label(clip_header, text="📋 Synced Clipboard Text", font=("Segoe UI", 11, "bold"), bg="#151518", fg="#FF7A00")
        lbl_clip_title.pack(side="left")

        ttk.Button(clip_header, text="Copy to System", style="Secondary.TButton", command=self._copy_clip_to_system).pack(side="right")

        self.txt_clipboard = tk.Text(clip_card, height=4, bg="#0C0C0E", fg="#F4F4F5", font=("Consolas", 10), relief="flat", padx=10, pady=8, wrap="word")
        self.txt_clipboard.pack(fill="x", pady=(10, 0))
        self.txt_clipboard.insert("1.0", "Copied text on PC or Android will sync here in real time.")

    # -------------------------------------------------------------------------
    # ENGINE & NETWORK CONTROLS
    # -------------------------------------------------------------------------
    def _start_engine(self):
        """Launches the DropSync background TCP & UDP discovery engine."""
        self.loop = asyncio.new_event_loop()

        self.host = DropSyncHost(
            port=DEFAULT_TCP_PORT,
            pin=self.pin,
            save_dir=self.downloads_dir,
        )

        # Hook clipboard updates into GUI
        original_mark = self.host.clipboard_monitor.mark_received

        def _hooked_mark(text, digest):
            original_mark(text, digest)
            self.root.after(0, self._update_clipboard_ui, text)

        self.host.clipboard_monitor.mark_received = _hooked_mark

        def _run():
            asyncio.set_event_loop(self.loop)
            try:
                self.loop.run_until_complete(self.host.start())
                self.root.after(0, lambda: self.lbl_transfer_stats.config(
                    text=f"Broadcasting on LAN (IP: {_get_primary_ip()} • Port {DEFAULT_TCP_PORT})",
                    fg="#10B981"
                ))
                self.loop.run_forever()
            except OSError as e:
                err_msg = "❌ Port 52525 in use! Close other running DropSync instances"
                print("Host engine error:", e)
                self.root.after(0, lambda: self.lbl_transfer_stats.config(text=err_msg, fg="#EF4444"))
            except Exception as e:
                print("Host engine error:", e)
                self.root.after(0, lambda: self.lbl_transfer_stats.config(text=f"❌ Error: {e}", fg="#EF4444"))

        self.server_thread = threading.Thread(target=_run, daemon=True)
        self.server_thread.start()

    def _show_manual_connect_dialog(self):
        dialog = tk.Toplevel(self.root)
        dialog.title("Connect via IP / Token")
        dialog.geometry("380x230")
        dialog.configure(bg="#151518")
        dialog.transient(self.root)
        dialog.grab_set()

        tk.Label(dialog, text="Enter Receiver's IP & Token:", font=("Segoe UI", 11, "bold"), bg="#151518", fg="#FFFFFF").pack(pady=(16, 4))
        tk.Label(dialog, text="(Shown on the Receive tab of other device)", font=("Segoe UI", 8), bg="#151518", fg="#A1A1AA").pack(pady=(0, 10))

        entry_ip = tk.Entry(dialog, font=("Segoe UI", 11), justify="center", bg="#0C0C0E", fg="#FFFFFF", insertbackground="#FF7A00")
        entry_ip.insert(0, "192.168.")
        entry_ip.pack(fill="x", padx=30, pady=4)
        entry_ip.focus()

        entry_token = tk.Entry(dialog, font=("Segoe UI", 11), justify="center", bg="#0C0C0E", fg="#FFA033", insertbackground="#FFA033")
        entry_token.insert(0, "Token")
        entry_token.pack(fill="x", padx=30, pady=4)

        def _connect():
            target_ip = entry_ip.get().strip()
            target_token = entry_token.get().strip()
            if target_ip and self.host and self.host.discovery:
                self.host.discovery.add_manual_peer(target_ip, DEFAULT_TCP_PORT, name="Remote Peer")
                self.peers = self.host.discovery.get_active_peers()
                self._render_peers(self.peers)
                dialog.destroy()
                if self.selected_file_path:
                    self._on_send_file({"ip": target_ip, "port": DEFAULT_TCP_PORT, "device_name": "Remote Peer"}, token=target_token)

        ttk.Button(dialog, text="Connect & Pair", style="Accent.TButton", command=_connect).pack(pady=14)

    def _periodic_refresh(self):
        """Polls discovered peers from the background host."""
        if self.host and self.host.discovery:
            active_peers = self.host.discovery.get_active_peers()
            if active_peers != self.peers:
                self.peers = active_peers
                self._render_peers(active_peers)

        self.root.after(500, self._periodic_refresh)

    def _render_peers(self, peers):
        for widget in self.peers_scroll_frame.winfo_children():
            widget.destroy()

        if not peers:
            lbl = tk.Label(
                self.peers_scroll_frame,
                text="Searching for DropSync devices on local Wi-Fi...\nOpen DropSync on your Android phone or another PC.",
                font=("Segoe UI", 11),
                bg="#151518",
                fg="#71717A",
                pady=40,
            )
            lbl.pack(fill="both", expand=True)
            return

        for p in peers:
            row = tk.Frame(self.peers_scroll_frame, bg="#111113", padx=14, pady=12, highlightthickness=1, highlightbackground="#26262B")
            row.pack(fill="x", padx=10, pady=6)

            icon = "📱" if "android" in p["platform"].lower() else "💻"
            lbl_icon = tk.Label(row, text=icon, font=("Segoe UI", 18), bg="#111113", fg="#FF7A00")
            lbl_icon.pack(side="left", padx=(0, 12))

            info_col = tk.Frame(row, bg="#111113")
            info_col.pack(side="left", fill="y")

            lbl_name = tk.Label(info_col, text=p["device_name"], font=("Segoe UI", 11, "bold"), bg="#111113", fg="#FFFFFF")
            lbl_name.pack(anchor="w")

            lbl_sub = tk.Label(info_col, text=f"{p['ip']}:{p['port']} • {p['platform'].upper()}", font=("Segoe UI", 9), bg="#111113", fg="#A1A1AA")
            lbl_sub.pack(anchor="w")

            btn_send = ttk.Button(row, text="Send File 📤", style="Accent.TButton", command=lambda target=p: self._on_send_file(target))
            btn_send.pack(side="right")

    def _on_send_file(self, peer, token=None):
        filepath = self.selected_file_path
        if not filepath:
            filepath = filedialog.askopenfilename(title=f"Select file to send to {peer['device_name']}")
        if not filepath:
            return

        filename = os.path.basename(filepath)
        self.lbl_transfer_name.config(text=f"Sending: {filename} to {peer['device_name']}...", fg="#FFA033")
        self.progress_bar["value"] = 0

        def _bg_send():
            fut = asyncio.run_coroutine_threadsafe(
                self.host.send_file(peer["ip"], filepath, peer["port"], token=token),
                self.loop,
            )
            try:
                success = fut.result()
                if success:
                    self.root.after(0, lambda: self._on_transfer_done(filename, True))
                else:
                    self.root.after(0, lambda: self._on_transfer_done(filename, False))
            except Exception as e:
                self.root.after(0, lambda: self._on_transfer_done(filename, False, str(e)))

        threading.Thread(target=_bg_send, daemon=True).start()

    def _on_transfer_done(self, filename, success, err=None):
        if success:
            self.lbl_transfer_name.config(text=f"✓ Successfully sent {filename}", fg="#10B981")
            self.progress_bar["value"] = 100
            self.lbl_transfer_stats.config(text="Transfer complete", fg="#10B981")
        else:
            self.lbl_transfer_name.config(text=f"✗ Failed sending {filename}", fg="#EF4444")
            self.lbl_transfer_stats.config(text=err or "Connection rejected or invalid token", fg="#EF4444")

    def _update_clipboard_ui(self, text):
        if hasattr(self, 'txt_clipboard'):
            self.txt_clipboard.delete("1.0", tk.END)
            self.txt_clipboard.insert("1.0", text)

    def _copy_clip_to_system(self):
        text = self.txt_clipboard.get("1.0", tk.END).strip()
        if text:
            self.root.clipboard_clear()
            self.root.clipboard_append(text)
            messagebox.showinfo("DropSync", "Copied to Windows clipboard!")

    def _open_downloads_folder(self):
        os.startfile(self.downloads_dir)

    def _on_close(self):
        if self.host:
            asyncio.run_coroutine_threadsafe(self.host.stop(), self.loop)
        self.root.destroy()


def main():
    root = tk.Tk()
    app = DropSyncAppUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
