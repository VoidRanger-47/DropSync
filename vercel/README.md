# DropSync Universal Relay & Web Receiver Engine

Deploy DropSync's E2EE Internet File Transfer relay to **any platform** (Vercel, Render, Railway, Fly.io, Docker, or self-hosted VPS) to unleash its maximum streaming speed and potential.

---

## ⚡ Maximum Potential Architecture

1. **Zero-Knowledge End-to-End Encryption (E2EE)**:
   - 256-Bit AES-GCM encryption executed entirely on-device (WebCrypto / Dart cryptography).
   - Keys derived via **HKDF-SHA256** from human-friendly room codes (`XXX-XXX`).
   - Zero plaintext, metadata, or keys ever touch the relay server.

2. **Pipelined High-Throughput Streaming**:
   - 128 KB chunks with parallel in-flight async upload windows.
   - Out-of-order packet reassembly buffer ensures 100% byte integrity even over high-latency WAN links.
   - WebRTC signaling (`/api/signal`) allows direct zero-server P2P transfers when NAT traversal succeeds.

3. **Strict Mutual Presence Guard**:
   - Transfers only stream while both peers are actively on the page.
   - Immediate heartbeat pausing prevents wasted bandwidth if either user navigates away or minimizes the app.

---

## 🚀 Choose Your Hosting Platform

### Option 1: Vercel (Serverless Cloud)
Ideal for zero-maintenance serverless deployment.
1. In the `vercel/` folder, run:
   ```bash
   npx vercel --prod
   ```
2. *(Optional for high volume)*: Add Upstash Redis environment variables in Vercel project settings:
   - `UPSTASH_REDIS_REST_URL`
   - `UPSTASH_REDIS_REST_TOKEN`
3. Copy your Vercel URL (e.g. `https://dropsync-relay.vercel.app`).

---

### Option 2: Render.com (Free / Persistent Cloud Service)
Ideal for continuous streaming with no serverless execution timeouts.
1. Connect your repository to [Render.com](https://render.com).
2. Choose **Web Service**.
3. Set **Root Directory** to `vercel`.
4. Set **Build Command**: *(leave empty)*
5. Set **Start Command**: `node server.js`
6. Click **Create Web Service**.

---

### Option 3: Railway.app / Fly.io (One-Click Docker)
Using the included `Dockerfile` or `server.js`:
- **Railway**: Click *New Project* -> *Deploy from GitHub repo* -> Select `vercel` folder.
- **Fly.io**:
  ```bash
  cd vercel
  fly launch
  fly deploy
  ```

---

### Option 4: Docker (Any Cloud VPS, NAS, or Home Server)
Run anywhere with Docker:
```bash
cd vercel
docker build -t dropsync-relay .
docker run -d -p 3000:3000 --name dropsync-relay dropsync-relay
```
Access at `http://your-server-ip:3000`.

---

### Option 5: Local / VPS Node.js
Zero external dependencies, runs on any Node.js 18+ runtime:
```bash
cd vercel
npm start
```
Starts relay at `http://localhost:3000` with health diagnostics at `http://localhost:3000/api/health`.

---

## 📱 Connecting DropSync App to Your Host

1. Open **DropSync** and tap the **Internet (E2EE)** tab.
2. Tap the **Relay / Public Cloud icon** (`Icons.dns_rounded`) on the top-right header.
3. Paste your deployed URL (e.g. `https://dropsync-relay.vercel.app` or `https://dropsync-relay.onrender.com`).
4. Tap **Test Connection & Ping** to verify latency in real-time.
5. Tap **Save & Connect**.
