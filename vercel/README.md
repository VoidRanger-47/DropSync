# DropSync Vercel Serverless Relay Engine

This package contains the official Vercel Serverless Relay deployment for **DropSync Internet Transfers**.

## Key Architecture & Features

1. **Zero-Knowledge End-to-End Encryption (E2EE)**:
   - All files are chunked and encrypted with **256-Bit AES-GCM** on the sender device before reaching the relay.
   - Keys are derived via **HKDF-SHA256** directly from the shared Room Code (`XXX-XXX`).
   - The Vercel relay only sees opaque encrypted ciphertext bytes and never has access to encryption keys, plaintext data, or cleartext file names.

2. **Strict Mutual Presence Guard**:
   - Transfers **strictly only occur when both sender and receiver are actively on the page** inside the app.
   - If either user leaves the page or minimizes the app, real-time heartbeats immediately pause streaming.
   - The `/api/chunk` serverless endpoint returns HTTP 403 `Transfer paused: Mutual presence required` if either party is not active.

3. **Serverless Scale on Vercel**:
   - Zero servers or persistent VMs to maintain.
   - Microsecond cold starts and global edge CDN availability.

---

## 🚀 1-Click Deployment to Vercel

### Option 1: Via Vercel CLI (Fastest)

1. Open your terminal in this directory:
   ```bash
   cd vercel
   ```

2. Run the Vercel deploy command:
   ```bash
   npx vercel
   ```

3. Follow the CLI prompts:
   - **Set up and deploy?** `yes`
   - **Which scope?** (Select your Vercel account)
   - **Link to existing project?** `no`
   - **Project name:** `dropsync-relay`
   - **Directory:** `./`

4. Deploy to production:
   ```bash
   npx vercel --prod
   ```

5. Copy your production URL (e.g. `https://dropsync-relay.vercel.app`).

---

### Option 2: Deploy via GitHub / GitLab

1. Push your repository to GitHub.
2. In your [Vercel Dashboard](https://vercel.com/new), click **Add New Project**.
3. Select your repository and set the **Root Directory** to `vercel`.
4. Click **Deploy**.

---

## 📱 Connecting DropSync App to Your Vercel Relay

1. Launch **DropSync**.
2. Tap the **Internet (E2EE)** tab on the top role switcher.
3. Tap the **Relay / DNS icon** (`Icons.dns_rounded`) on the top-right of the header card.
4. Paste your Vercel deployment URL (e.g., `https://dropsync-relay.vercel.app`).
5. Tap **Save Endpoint**.

The app is now synced with your custom Vercel Serverless relay!
