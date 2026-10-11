const { updateHeartbeat, getRoom, checkPresence } = require('./_store');

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // POST /api/heartbeat
  // Body: { roomCode, peerId, role: 'sender'|'receiver', status: 'active'|'left' }
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
      // If either peer is not actively on page, transfer is strictly paused
      transferPermitted: presence.bothPresent,
    });
  }

  // GET /api/heartbeat?roomCode=XXX-XXX
  if (req.method === 'GET') {
    const code = req.query.roomCode;
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
};
