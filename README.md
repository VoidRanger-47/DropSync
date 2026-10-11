# DropSync: Next-Gen Cross-Platform P2P File & Clipboard Sync with Quick Share Interoperability

**DropSync** is a unified, high-performance cross-platform application targeting **Windows Desktop (.exe)** and **Android (.apk)**. It features full interoperability with **Google & Samsung Quick Share (Nearby Share)** while fundamentally resolving Quick Share's core architectural flaws through an in-band dual-engine network architecture.

---

## Part 1: How DropSync Resolves Quick Share's Core Flaws

| Quick Share Architectural Flaw | DropSync Architectural Solution |
| :--- | :--- |
| **1. Cloud & Google Account Lock-in**<br>Requires active Google/Samsung accounts, contact graph synchronization, and authentication queries to external servers. Stalls when offline. | **100% Serverless Local Operation**<br>Operates completely decentralized over LAN. Zero account requirements, zero Google cloud queries, and zero telemetry. Complete privacy by design. |
| **2. Bluetooth-Dependent Discovery Stall**<br>Quick Share fails to discover peers or stalls indefinitely if Bluetooth / BLE hardware is unavailable or disabled. | **Zero-Bluetooth Fallback (mDNS + Dynamic QR)**<br>Full peer discovery using standard mDNS multicast (`_FC9F5ED42C8A._tcp.local`) and dynamic visual QR handshakes (`https://quickshare.google/qrcode#key=...`) that work over any standard Wi-Fi network. |
| **3. Wi-Fi Direct Network Disconnections**<br>Forces Wi-Fi Direct frequency shifts that disconnect active internet connections, interrupting cloud streams, Zoom calls, or game sessions. | **In-Band Subnet Socket Streaming**<br>Streams directly over the existing connected local Wi-Fi subnet. Active internet streams and local connections remain completely uninterrupted. |
| **4. Hidden App Caches & Transient Logs**<br>Received payloads often land in obfuscated system caches without transparent audit trails or custom destination control. | **Transparent File System & Persistent History**<br>Every payload writes directly to user-selected directories with collision handling `(1)`, `.part` atomic safety, SQLite/JSON persistent audit logs, and one-click "Show in Folder" (`explorer.exe /select,`). |

---

## Part 2: Quick Share Protocol Interoperability Specification

DropSync implements the reverse-engineered Google Nearby Connections / Quick Share wire protocol alongside its native socket engine:

### 1. Service Discovery (mDNS)
- **Service Type:** Advertises and browses for `_FC9F5ED42C8A._tcp.local`.
- **TXT & PTR Record:** Contains endpoint identification metadata conforming to Nearby Connections specs.
- **Android Intent & QR Trigger:** Generates the official pairing URI (`https://quickshare.google/qrcode#key=...`) or triggers Android's `ReceiveSurfaceActivity`, allowing un-modded Android devices to beacon via mDNS without Bluetooth.

### 2. Cryptographic Handshake (UKEY2)
- **Diffie-Hellman Key Exchange:** Ephemeral Curve25519 (`X25519`) key generation with exchange of `ClientInit` and `ServerInit` messages.
- **Key Derivation (HKDF-SHA256):**
  - Salt: `UKEY2_PIN_SALT` & Info: `QuickShareAuthPin` -> Generates the exact 4-digit security PIN displayed on Android devices.
  - Salt: `UKEY2_CLIENT_WRITE_KEY` / `UKEY2_SERVER_WRITE_KEY` -> Derives directional 256-bit symmetric session keys.
- **Authenticated Encryption:** AES-256-GCM session cipher with sequential nonces and MAC tag verification.

### 3. Framing & Payload Serialization (Protobuf)
- **Wire Framing:** Google 4-byte big-endian length prefix framing.
- **Frames:**
  - `OfflineFrame`: `ConnectionRequest`, `ConnectionResponse` (status 1 = ACCEPT), and `PayloadTransfer`.
  - `IntroductionFrame`: File metadata payload (`fileName`, `fileSize`, `mimeType`, `payloadId`).
  - `DataPayload`: Decrypted AES-GCM data stream written to target destination using `.part` atomic file replacement.

### 4. Dual-Engine Auto-Negotiation
- **⚡ DropSync Native Peers:** Detected via native UDP broadcast / mDNS / QR code. Utilizes zero-overhead binary framing and 64 KB chunking for maximum transfer speed.
- **🌐 Quick Share Peers:** Detected via `_FC9F5ED42C8A._tcp.local`. Seamlessly routes outgoing transfers through the UKEY2 + Protobuf driver.

---

## Part 3: Architecture & File Structure

```text
lib/
├── main.dart                                    # App entrypoint, Gemini Dark theme, MultiProvider setup
├── models/
│   ├── peer.dart                               # Peer model (DropSync vs Quick Share protocol badges)
│   ├── transfer_session.dart                   # Active transfer state, bytes transferred, speed calculation
│   └── transfer_record.dart                    # Persistent audit log model with date categorization
├── services/
│   ├── network_service.dart                    # Dual-engine coordinator routing transfers
│   ├── socket_engine.dart                      # Native 64 KB socket engine (<hHH binary framing)
│   ├── dropsync/
│   │   └── dropsync_engine.dart                # Native DropSync engine driver
│   ├── quickshare/
│   │   ├── quickshare_discovery.dart           # mDNS browser & advertiser for _FC9F5ED42C8A._tcp
│   │   ├── ukey2_handshake.dart                # Curve25519, HKDF-SHA256, 4-digit PIN & AES-256-GCM cipher
│   │   ├── quickshare_receiver.dart            # Inbound Quick Share receiver & UKEY2 session acceptor
│   │   └── protobuf/
│   │       └── nearby_sharing_protobuf.dart    # Pure Dart Protobuf wire parser (Offline & Intro frames)
│   ├── storage/
│   │   ├── storage_service.dart                # Directory overrides, collision avoidance, atomic rename
│   │   └── history_repository.dart             # Persistent transfer audit logs, OS explorer hooks
│   ├── clipboard_service.dart                  # Clipboard synchronization bridge
│   └── discovery_service.dart                  # Native DropSync UDP discovery broadcaster
└── views/
    ├── landing_view.dart                       # Dual-panel Home (Send / Receive / Stats)
    ├── sender_view.dart                        # Discovery radar with protocol badges (DropSync vs Quick Share)
    ├── receiver_view.dart                      # Inbound beacon server & pairing QR code
    ├── pin_confirmation_dialog.dart            # Visual UKEY2 PIN modal matching Android's security prompt
    ├── history_view.dart                       # Grouped audit log (Today, Yesterday, Older) + Open in Folder
    ├── settings_dialog.dart                    # Storage directory picker & Quick Share bridge toggle
    └── camera_scanner_view.dart                # Camera QR scanner for mobile instant pairing
```

---

## Part 4: Design Aesthetics (Gemini Dark Theme)

- **Color System:**
  - Background: Deep Void (`#0E0E10`)
  - Surface Container: Dark Slate (`#1E1F22`)
  - Surface Variant: Card Slate (`#28292A`)
  - Signature Gemini Glow: Linear gradient spanning Electric Blue (`#4E75FF`), Cyan (`#56C5FE`), to Violet (`#9B72CF`).
  - Outlines: Luminous semi-transparent borders (`Border.all(color: Colors.white.withOpacity(0.08))`).
- **Interactive Components:**
  - Real-time animated discovery radar with concentric ripple waves.
  - Visual protocol badges: `[⚡ DropSync]` vs `[🌐 Quick Share]`.
  - Android-matching UKEY2 4-digit PIN verification modal with glowing digits.
  - Native Explorer integration (`explorer.exe /select,`) to instantly reveal received files on Windows.

---

## Part 5: Testing & Verification

### Running Automated Unit Tests
The project includes automated unit test suites covering the data models, binary wire format, UKEY2 cryptographic handshake, 4-digit PIN derivation, AES-256-GCM encryption/decryption, and Protobuf framing:

```bash
flutter test
```

### Running Static Analysis
```bash
flutter analyze
```

---

## Part 6: Build & Deployment

### Windows Desktop (.exe)
```bash
# Debug / Development run:
flutter run -d windows

# Production Release Build:
flutter build windows --release
# Executable located at: build/windows/x64/runner/Release/dropsync.exe
```

### Android (.apk)
```bash
# Debug run on connected Android phone:
flutter run -d android

# Production Split ABI APKs (optimized size for arm64-v8a, armeabi-v7a):
flutter build apk --split-per-abi --release
# Output APKs located in: build/app/outputs/flutter-apk/
```
