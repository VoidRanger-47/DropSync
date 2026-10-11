const { getRoom, createOrJoinRoom, checkPresence, getStore } = require('./_store');

module.exports = async function handler(req, res) {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // GET /api/room?code=XXX-XXX
  if (req.method === 'GET') {
    const code = req.query.code;
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

  // POST /api/room
  // Body: { roomCode, peerId, role: 'sender'|'receiver', transferState, metadata }
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

  // DELETE /api/room?code=XXX-XXX
  if (req.method === 'DELETE') {
    const code = req.query.code;
    if (code) {
      getStore().delete(code.trim().toUpperCase());
    }
    return res.status(200).json({ success: true, message: 'Room closed' });
  }

  return res.status(405).json({ error: 'Method not allowed' });
};
