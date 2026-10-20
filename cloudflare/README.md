# DropSync Cloudflare Edge Relay

An ultra-low latency, persistent WebSockets & REST Relay for DropSync End-to-End Encrypted (AES-256-GCM) Transfers.

### Why Cloudflare Workers over Vercel?
- **Zero Cold Starts**: Runs on Cloudflare's global edge network (300+ cities) in lightweight V8 isolates.
- **Persistent WebSockets**: Instant peer presence, real-time chunk forwarding, and sub-15ms message propagation.
- **100% Free**: 100,000 requests per day every day, unlimited WebSocket streaming minutes, no credit card required.
- **Zero-Knowledge E2EE**: DropSync encrypts all file payloads locally on your device with AES-256-GCM before sending. The relay only passes blind encrypted binary ciphertext.

---

## 🚀 Deployment (Takes Under 60 Seconds)

### Method A: One-Command CLI Deploy (Fastest)

1. Open a terminal in this directory:
   ```bash
   cd cloudflare
   ```

2. Run deploy (Wrangler will open your browser to log in to your free Cloudflare account if not already logged in):
   ```bash
   npx wrangler deploy
   ```

3. Copy your live deployed URL!
   ```text
   Uploaded dropsync (1.20 sec)
   Deployed dropsync triggers (0.42 sec)
     https://dropsync.voidranger.workers.dev
   ```

---

### Method B: Web Dashboard (No Node/CLI needed)

1. Go to [dash.cloudflare.com](https://dash.cloudflare.com) and log in or create a free account.
2. Click **Compute (Workers & Pages)** > **Create application** > **Create Worker**.
3. Name it `dropsync` and click **Deploy**.
4. Click **Edit code**, copy and paste the contents of [`worker.js`](worker.js) into the editor, and click **Save and Deploy**.
5. Copy your worker's `.workers.dev` URL.

---

## 📱 Connecting DropSync to Your Cloudflare Relay

1. Open the DropSync App on Android or Windows Desktop.
2. Go to **Internet** > tap the top relay pill (or **Settings**).
3. Confirm or paste your Cloudflare Worker URL:
   ```text
   https://dropsync.voidranger.workers.dev
   ```
4. Done! All internet transfers and presence checks now route through the ultra-fast Cloudflare Edge with 0ms cold starts.
