const { getRoom, checkPresence } = require('./_store');

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // POST /api/chunk: Sender submits an E2EE encrypted chunk
  // Body: { roomCode, peerId, chunkIndex, totalChunks, isHeader, dataBase64 }
  if (req.method === 'POST') {
    const { roomCode, peerId, chunkIndex, totalChunks, isHeader, dataBase64 } = req.body || {};

    if (!roomCode || !dataBase64) {
      return res.status(400).json({ error: 'Missing roomCode or dataBase64' });
    }

    const room = getRoom(roomCode);
    if (!room) {
      return res.status(404).json({ error: 'Room not found or expired' });
    }

    // SERVER-SIDE MUTUAL PRESENCE ENFORCEMENT:
    // DropSync strictly requires BOTH peers to be actively staying on the page.
    const presence = checkPresence(room);
    if (!presence.bothPresent) {
      return res.status(403).json({
        error: 'Transfer paused: Mutual presence required. Both sender and receiver must stay on the page.',
        presence,
      });
    }

    // Mark room as actively transferring once chunks start flowing
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

  // GET /api/chunk?roomCode=XXX-XXX&peerId=...: Receiver pulls pending encrypted chunks
  if (req.method === 'GET') {
    const { roomCode } = req.query;
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

    // Dequeue up to 4 chunks at a time for fast streaming
    const pulledChunks = room.chunks.splice(0, 4);

    return res.status(200).json({
      chunks: pulledChunks,
      remaining: room.chunks.length,
      transferState: room.transferState || 'transferring',
      presence,
    });
  }

  return res.status(405).json({ error: 'Method not allowed' });
};
