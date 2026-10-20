const {
  getRoom,
  saveRoom,
  createOrJoinRoom,
  updateHeartbeat,
  pushSignal,
  pullSignals,
  pushChunk,
  pullChunks,
  deleteRoom,
  checkPresence,
  hasRedis,
} = require('./_store');

module.exports = async function handler(req, res) {
  // CORS Preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Determine endpoint from URL path or action query parameter
  const urlPath = req.url ? req.url.split('?')[0] : '';
  const action = req.query.action || (
    urlPath.includes('/health') ? 'health' :
    urlPath.includes('/signal') ? 'signal' :
    urlPath.includes('/heartbeat') ? 'heartbeat' :
    urlPath.includes('/fallback') ? 'fallback' :
    urlPath.includes('/chunk') ? 'chunk' :
    urlPath.includes('/room') ? 'room' : 'room'
  );

  // -------------------------------------------------------------
  // 1. WEBRTC SIGNALING (SDP OFFERS/ANSWERS & ICE CANDIDATES)
  // Direct P2P DataChannel establishment - 0 byte Vercel chunk overhead!
  // -------------------------------------------------------------
  if (action === 'signal') {
    if (req.method === 'POST') {
      const { roomCode, role, signalType, payload } = req.body || {};
      if (!roomCode || !role || !signalType || !payload) {
        return res.status(400).json({ error: 'Missing required signaling fields' });
      }

      await pushSignal({
        roomCode,
        senderRole: role,
        signalType,
        payload,
      });

      return res.status(200).json({
        success: true,
        signalType,
        timestamp: Date.now(),
      });
    }

    if (req.method === 'GET') {
      const roomCode = req.query.roomCode || req.query.code;
      const role = req.query.role;
      if (!roomCode || !role) {
        return res.status(400).json({ error: 'Missing roomCode or role' });
      }

      const pendingSignals = await pullSignals({ roomCode, role });
      return res.status(200).json({
        roomCode,
        role,
        signals: pendingSignals,
        count: pendingSignals.length,
      });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  }

  // -------------------------------------------------------------
  // 2. HEARTBEAT & MUTUAL PRESENCE
  // -------------------------------------------------------------
  if (action === 'heartbeat') {
    if (req.method === 'POST') {
      const { roomCode, peerId, role, status = 'active', transferState } = req.body || {};
      if (!roomCode || !role) {
        return res.status(400).json({ error: 'Missing roomCode or role' });
      }

      const presence = await updateHeartbeat({ roomCode, peerId, role, status, transferState });
      if (!presence) {
        return res.status(404).json({ error: 'Room not found or expired', bothPresent: false, transferState: 'closed' });
      }

      return res.status(200).json({
        roomCode,
        status,
        presence,
        transferState: presence.transferState,
        transferPermitted: presence.bothPresent,
        storageEngine: hasRedis ? 'upstash-redis' : 'in-memory-fallback',
      });
    }

    if (req.method === 'GET') {
      const code = req.query.roomCode || req.query.code;
      const room = await getRoom(code);
      if (!room) {
        return res.status(404).json({ error: 'Room not found', bothPresent: false, transferState: 'closed' });
      }
      const presence = checkPresence(room);
      return res.status(200).json({
        roomCode: code,
        presence,
        transferState: presence.transferState,
        transferPermitted: presence.bothPresent,
      });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  }

  // -------------------------------------------------------------
  // 3. PRESIGNED STORAGE FALLBACK (CLOUDFLARE R2 / S3)
  // Used only when symmetric NAT blocks direct WebRTC P2P
  // -------------------------------------------------------------
  if (action === 'fallback') {
    const roomCode = req.query.roomCode || (req.body && req.body.roomCode);
    const fileName = req.query.fileName || (req.body && req.body.fileName) || 'transfer.bin';

    const r2Bucket = process.env.R2_BUCKET_NAME || process.env.S3_BUCKET;
    const r2PublicDomain = process.env.R2_PUBLIC_DOMAIN;

    // If Cloudflare R2 / S3 environment is configured, emit direct storage URL
    if (r2Bucket) {
      const objectKey = `dropsync/${roomCode || 'global'}/${encodeURIComponent(fileName)}`;
      const uploadUrl = r2PublicDomain
        ? `${r2PublicDomain}/${objectKey}`
        : `https://${r2Bucket}.r2.cloudflarestorage.com/${objectKey}`;

      return res.status(200).json({
        fallbackEnabled: true,
        storageProvider: 'Cloudflare R2',
        objectKey,
        uploadUrl,
        downloadUrl: uploadUrl,
        note: 'Direct client-to-storage stream bypassing Vercel body limits',
      });
    }

    // Default mock fallback indicator for client
    return res.status(200).json({
      fallbackEnabled: false,
      recommendedTransport: 'webrtc-p2p',
      message: 'WebRTC P2P DataChannel is active. Storage fallback optional.',
    });
  }

  // -------------------------------------------------------------
  // 4. HEALTH CHECK & LATENCY BENCHMARK
  // -------------------------------------------------------------
  if (action === 'health') {
    return res.status(200).json({
      status: 'healthy',
      storageEngine: hasRedis ? 'upstash-redis' : 'in-memory-fallback',
      uptime: process.uptime(),
      timestamp: Date.now(),
      version: '2.0.0',
      features: ['e2ee-aes-gcm', 'webrtc-signaling', 'chunk-streaming', 'presence-guard', 'storage-fallback'],
    });
  }

  // -------------------------------------------------------------
  // 5. ENCRYPTED CHUNK RELAY
  // High-performance encrypted chunk queue for WAN file transfers
  // -------------------------------------------------------------
  if (action === 'chunk') {
    if (req.method === 'POST') {
      const { roomCode, peerId, chunkIndex, totalChunks, isHeader, dataBase64 } = req.body || {};
      if (!roomCode || dataBase64 === undefined) {
        return res.status(400).json({ error: 'Missing roomCode or dataBase64' });
      }

      await pushChunk({
        roomCode,
        peerId,
        chunkIndex,
        totalChunks,
        isHeader,
        dataBase64,
      });

      return res.status(200).json({
        success: true,
        chunkIndex: Number(chunkIndex) || 0,
        queued: true,
        timestamp: Date.now(),
      });
    }

    if (req.method === 'GET') {
      const roomCode = req.query.roomCode || req.query.code;
      const maxChunks = req.query.max || req.query.limit || 20;
      if (!roomCode) {
        return res.status(400).json({ error: 'Missing roomCode' });
      }

      const chunks = await pullChunks({ roomCode, maxChunks });
      return res.status(200).json({
        success: true,
        roomCode,
        chunks,
        count: chunks.length,
      });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  }

  // -------------------------------------------------------------
  // 5. ROOM REGISTRATION & DISCOVERY
  // -------------------------------------------------------------
  if (req.method === 'GET') {
    const code = req.query.code || req.query.roomCode;
    const room = await getRoom(code);
    if (!room) {
      return res.status(404).json({ error: 'Room not found or expired', code, transferState: 'closed' });
    }
    const presence = checkPresence(room);
    return res.status(200).json({
      roomCode: room.roomCode,
      createdAt: room.createdAt,
      transferState: room.transferState || 'waiting',
      metadata: room.metadata || null,
      presence,
      p2pReady: room.p2pReady || false,
      storageEngine: hasRedis ? 'upstash-redis' : 'in-memory-fallback',
    });
  }

  if (req.method === 'POST') {
    const { roomCode, peerId, role, transferState, metadata } = req.body || {};
    if (!roomCode || !peerId || !role) {
      return res.status(400).json({ error: 'Missing required fields: roomCode, peerId, role' });
    }

    const result = await createOrJoinRoom({ roomCode, peerId, role, transferState, metadata });
    return res.status(200).json({
      success: true,
      roomCode: result.room.roomCode,
      role,
      transferState: result.room.transferState,
      metadata: result.room.metadata,
      presence: result.presence,
      storageEngine: hasRedis ? 'upstash-redis' : 'in-memory-fallback',
    });
  }

  if (req.method === 'DELETE') {
    const code = req.query.code || req.query.roomCode;
    if (code) {
      await deleteRoom(code);
    }
    return res.status(200).json({ success: true, message: 'Room and signaling state closed' });
  }

  return res.status(405).json({ error: 'Method not allowed' });
};
