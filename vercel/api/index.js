const {
  getStore,
  getRoom,
  createOrJoinRoom,
  updateHeartbeat,
  updateTransferState,
  checkPresence,
} = require('./_store');

module.exports = async function handler(req, res) {
  // CORS Preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Determine endpoint either from path or explicit action query parameter
  // e.g., /api/room, /api/heartbeat, /api/chunk OR /api/index?action=chunk
  const urlPath = req.url ? req.url.split('?')[0] : '';
  const action = req.query.action || (urlPath.includes('/heartbeat')
    ? 'heartbeat'
    : (urlPath.includes('/chunk')
      ? 'chunk'
      : (urlPath.includes('/room') ? 'room' : '')));

  // -------------------------------------------------------------
  // 1. HEARTBEAT ACTION
  // -------------------------------------------------------------
  if (action === 'heartbeat') {
    if (req.method === 'POST') {
      const { roomCode, peerId, role, status = 'active', transferState } = req.body || {};
      if (!roomCode || !role) {
        return res.status(400).json({ error: 'Missing roomCode or role' });
      }

      const presence = updateHeartbeat({ roomCode, peerId, role, status, transferState });
      if (!presence) {
        return res.status(404).json({ error: 'Room not found or expired', bothPresent: false, transferState: 'closed' });
      }

      return res.status(200).json({
        roomCode,
        status,
        presence,
        transferState: presence.transferState,
        transferPermitted: presence.bothPresent,
      });
    }

    if (req.method === 'GET') {
      const code = req.query.roomCode || req.query.code;
      const room = getRoom(code);
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
  // 2. CHUNK ACTION
  // -------------------------------------------------------------
  if (action === 'chunk') {
    if (req.method === 'POST') {
      const { roomCode, peerId, chunkIndex, totalChunks, isHeader, dataBase64 } = req.body || {};
      if (!roomCode || !dataBase64) {
        return res.status(400).json({ error: 'Missing roomCode or dataBase64' });
      }

      const room = getRoom(roomCode);
      if (!room) {
        return res.status(404).json({ error: 'Room not found or expired' });
      }

      const presence = checkPresence(room);
      if (!presence.bothPresent) {
        return res.status(403).json({
          error: 'Transfer paused: Mutual presence required. Both sender and receiver must stay on the page.',
          presence,
        });
      }

      room.transferState = 'transferring';
      if (chunkIndex !== undefined && totalChunks !== undefined && chunkIndex + 1 >= totalChunks) {
        room.transferState = 'completed';
      }

      room.chunks.push({
        chunkIndex: chunkIndex ?? 0,
        totalChunks: totalChunks ?? 1,
        isHeader: Boolean(isHeader),
        dataBase64,
        timestamp: Date.now(),
      });

      return res.status(200).json({
        success: true,
        queuedIndex: chunkIndex,
        remainingInQueue: room.chunks.length,
        transferState: room.transferState,
      });
    }

    if (req.method === 'GET') {
      const roomCode = req.query.roomCode || req.query.code;
      if (!roomCode) {
        return res.status(400).json({ error: 'Missing roomCode' });
      }

      const room = getRoom(roomCode);
      if (!room) {
        return res.status(404).json({ error: 'Room not found or expired' });
      }

      const presence = checkPresence(room);
      if (!presence.bothPresent) {
        return res.status(403).json({
          error: 'Transfer paused: Mutual presence required. Both peers must stay on the page.',
          presence,
        });
      }

      // Dequeue up to 8 chunks at a time for fast streaming and accurate progress tracking
      const pulledChunks = room.chunks.splice(0, 8);
      return res.status(200).json({
        chunks: pulledChunks,
        remaining: room.chunks.length,
        transferState: room.transferState || 'transferring',
        presence,
      });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  }

  // -------------------------------------------------------------
  // 3. ROOM ACTION (DEFAULT)
  // -------------------------------------------------------------
  if (req.method === 'GET') {
    const code = req.query.code || req.query.roomCode;
    const room = getRoom(code);
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
      pendingChunks: room.chunks.length,
    });
  }

  if (req.method === 'POST') {
    const { roomCode, peerId, role, transferState, metadata } = req.body || {};
    if (!roomCode || !peerId || !role) {
      return res.status(400).json({ error: 'Missing required fields: roomCode, peerId, role' });
    }

    const result = createOrJoinRoom({ roomCode, peerId, role, transferState, metadata });
    return res.status(200).json({
      success: true,
      roomCode: result.room.roomCode,
      role,
      transferState: result.room.transferState,
      metadata: result.room.metadata,
      presence: result.presence,
    });
  }

  if (req.method === 'DELETE') {
    const code = req.query.code || req.query.roomCode;
    if (code) {
      getStore().delete(code.trim().toUpperCase());
    }
    return res.status(200).json({ success: true, message: 'Room closed' });
  }

  return res.status(405).json({ error: 'Method not allowed' });
};
