/**
 * DropSync Universal Relay & Web Server
 * Runs standalone on any Node.js host: Render, Railway, Fly.io, Glitch, Docker, VPS, or locally.
 * Zero external dependencies.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');
const apiHandler = require('./api/index');
const { hasRedis } = require('./api/_store');

const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';
const PUBLIC_DIR = path.join(__dirname, 'public');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
};

const server = http.createServer(async (req, res) => {
  // Global CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, DELETE, PUT');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-DropSync-Peer, Authorization, Accept');

  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = parsedUrl.pathname;

  // Enhance res with status and json helpers for serverless handler compatibility
  res.status = function (code) {
    res.statusCode = code;
    return res;
  };
  res.json = function (data) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify(data));
    return res;
  };

  // Enhance req with query dictionary
  req.query = Object.fromEntries(parsedUrl.searchParams.entries());

  // 1. API Route Handler
  if (pathname.startsWith('/api/')) {
    let bodyBuffer = '';
    req.on('data', chunk => {
      bodyBuffer += chunk;
      // 10 MB maximum request body guard
      if (bodyBuffer.length > 10 * 1024 * 1024) {
        res.status(413).json({ error: 'Payload Too Large' });
        req.destroy();
      }
    });

    req.on('end', async () => {
      if (bodyBuffer) {
        try {
          req.body = JSON.parse(bodyBuffer);
        } catch (_) {
          req.body = bodyBuffer;
        }
      } else {
        req.body = {};
      }

      try {
        await apiHandler(req, res);
      } catch (err) {
        console.error('[Relay Error]', err);
        if (!res.writableEnded) {
          res.status(500).json({ error: 'Internal Server Error', message: err.message });
        }
      }
    });
    return;
  }

  // 2. Static File Serving (Web Receiver UI)
  let relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\//, '');
  let filePath = path.join(PUBLIC_DIR, relativePath);

  // Security check: prevent directory traversal
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.status(403).end('Forbidden');
    return;
  }

  // SPA fallback: if file doesn't exist, serve index.html
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(PUBLIC_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.status(404).end('Not Found');
    } else {
      res.setHeader('Content-Type', contentType);
      res.setHeader('Cache-Control', ext === '.html' ? 'no-cache' : 'public, max-age=86400');
      res.statusCode = 200;
      res.end(data);
    }
  });
});

server.listen(PORT, HOST, () => {
  console.log('====================================================');
  console.log('🚀 DropSync Universal High-Performance Relay Server');
  console.log('====================================================');
  console.log(`🌐 Web UI:       http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`);
  console.log(`📡 Health Check: http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}/api/health`);
  console.log(`💾 Storage:      ${hasRedis ? 'Upstash Redis (Distributed Cloud)' : 'In-Memory (Fast Local)'}`);
  console.log(`🔒 Security:     256-bit AES-GCM Zero-Knowledge E2EE`);
  console.log('====================================================\n');
});

// Graceful termination
process.on('SIGINT', () => {
  console.log('\nStopping DropSync Relay Server...');
  server.close(() => process.exit(0));
});

process.on('SIGTERM', () => {
  console.log('\nTerminating DropSync Relay Server...');
  server.close(() => process.exit(0));
});
