// Upstash Redis Serverless Store with Graceful In-Memory Fallback
// Eliminates dropped rooms and cold-start state loss across Vercel Lambda invocations.

const UPSTASH_URL = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL;
const UPSTASH_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN;

const PEER_TIMEOUT_MS = 4000;
const ROOM_TTL_SEC = 15 * 60; // 15 minutes TTL

// Local in-memory fallback for offline/development environments
if (!globalThis._dropSyncLocalMemoryStore) {
  globalThis._dropSyncLocalMemoryStore = {
    rooms: new Map(),
    signals: new Map(), // roomCode:role -> []
    chunks: new Map(),  // roomCode -> []
  };
}

const memoryStore = globalThis._dropSyncLocalMemoryStore;

const hasRedis = Boolean(UPSTASH_URL && UPSTASH_TOKEN);

/**
 * Execute a command against Upstash Redis REST API.
 */
async function redisCommand(...args) {
  if (!hasRedis) return null;
  try {
    const url = `${UPSTASH_URL.replace(/\/$/, '')}/${args.map(a => encodeURIComponent(String(a))).join('/')}`;
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${UPSTASH_TOKEN}`,
      },
    });
    if (!res.ok) return null;
    const json = await res.json();
    return json.result;
  } catch (err) {
    console.warn('[Redis] Upstash request failed:', err.message);
    return null;
  }
}

/**
 * Execute a pipeline of commands against Upstash Redis REST API.
 */
async function redisPipeline(commands) {
  if (!hasRedis) return null;
  try {
    const url = `${UPSTASH_URL.replace(/\/$/, '')}/pipeline`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${UPSTASH_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(commands),
    });
    if (!res.ok) return null;
    return await res.json();
  } catch (err) {
    console.warn('[Redis] Pipeline failed:', err.message);
    return null;
  }
}

/**
 * Retrieve a room's state.
 */
async function getRoom(code) {
  if (!code) return null;
  const cleanCode = code.trim().toUpperCase();

  if (hasRedis) {
    try {
      const data = await redisCommand('GET', `dropsync:room:${cleanCode}`);
      if (!data) return null;
      return typeof data === 'string' ? JSON.parse(data) : data;
    } catch (_) {
      // Fallback to in-memory on error
    }
  }

  // Fallback to memory
  const room = memoryStore.rooms.get(cleanCode);
  if (!room) return null;
  if (Date.now() - room.createdAt > ROOM_TTL_SEC * 1000) {
    memoryStore.rooms.delete(cleanCode);
    return null;
  }
  return room;
}

/**
 * Save or update a room's state.
 */
async function saveRoom(room) {
  const cleanCode = room.roomCode.trim().toUpperCase();

  if (hasRedis) {
    try {
      await redisCommand('SET', `dropsync:room:${cleanCode}`, JSON.stringify(room), 'EX', ROOM_TTL_SEC);
      return;
    } catch (_) {}
  }

  memoryStore.rooms.set(cleanCode, room);
}

/**
 * Create or join an existing WebRTC signaling room.
 */
async function createOrJoinRoom({ roomCode, peerId, role, transferState, metadata }) {
  const cleanCode = roomCode.trim().toUpperCase();
  const now = Date.now();

  let room = await getRoom(cleanCode);

  if (!room) {
    room = {
      roomCode: cleanCode,
      createdAt: now,
      senderId: role === 'sender' ? peerId : null,
      receiverId: role === 'receiver' ? peerId : null,
      senderLastHeartbeat: role === 'sender' ? now : 0,
      receiverLastHeartbeat: role === 'receiver' ? now : 0,
      senderStatus: role === 'sender' ? 'active' : 'offline',
      receiverStatus: role === 'receiver' ? 'active' : 'offline',
      transferState: transferState || 'waiting',
      metadata: metadata || null,
      p2pReady: false,
    };
  } else {
    if (role === 'sender') {
      room.senderId = peerId;
      room.senderLastHeartbeat = now;
      room.senderStatus = 'active';
    } else {
      room.receiverId = peerId;
      room.receiverLastHeartbeat = now;
      room.receiverStatus = 'active';
    }
    if (transferState) room.transferState = transferState;
    if (metadata) room.metadata = metadata;
  }

  await saveRoom(room);
  return { room, presence: checkPresence(room) };
}

/**
 * Update peer heartbeat in persistent store.
 */
async function updateHeartbeat({ roomCode, peerId, role, status = 'active', transferState }) {
  const room = await getRoom(roomCode);
  if (!room) return null;

  const now = Date.now();
  if (role === 'sender') {
    room.senderId = peerId || room.senderId;
    room.senderLastHeartbeat = status === 'active' ? now : 0;
    room.senderStatus = status;
  } else {
    room.receiverId = peerId || room.receiverId;
    room.receiverLastHeartbeat = status === 'active' ? now : 0;
    room.receiverStatus = status;
  }

  if (transferState) {
    room.transferState = transferState;
  }

  await saveRoom(room);
  return checkPresence(room);
}

/**
 * Queue a WebRTC signaling payload (SDP offer/answer or ICE candidate) for the peer.
 */
async function pushSignal({ roomCode, senderRole, signalType, payload }) {
  const cleanCode = roomCode.trim().toUpperCase();
  const targetRole = senderRole === 'sender' ? 'receiver' : 'sender';
  const signal = {
    senderRole,
    signalType, // 'offer' | 'answer' | 'candidate'
    payload,
    timestamp: Date.now(),
  };

  if (hasRedis) {
    try {
      const key = `dropsync:signals:${cleanCode}:${targetRole}`;
      await redisPipeline([
        ['RPUSH', key, JSON.stringify(signal)],
        ['EXPIRE', key, ROOM_TTL_SEC],
      ]);
      return true;
    } catch (_) {}
  }

  const memKey = `${cleanCode}:${targetRole}`;
  if (!memoryStore.signals.has(memKey)) {
    memoryStore.signals.set(memKey, []);
  }
  memoryStore.signals.get(memKey).push(signal);
  return true;
}

/**
 * Pop and return all pending WebRTC signaling payloads for a peer role.
 */
async function pullSignals({ roomCode, role }) {
  const cleanCode = roomCode.trim().toUpperCase();

  if (hasRedis) {
    try {
      const key = `dropsync:signals:${cleanCode}:${role}`;
      // LRANGE 0 -1 to get all, then DEL to clear
      const res = await redisPipeline([
        ['LRANGE', key, 0, -1],
        ['DEL', key],
      ]);
      if (res && res[0] && Array.isArray(res[0].result)) {
        return res[0].result.map(item => typeof item === 'string' ? JSON.parse(item) : item);
      }
      return [];
    } catch (_) {}
  }

  const memKey = `${cleanCode}:${role}`;
  const list = memoryStore.signals.get(memKey) || [];
  memoryStore.signals.set(memKey, []);
  return list;
}

/**
 * Push an encrypted file chunk into the room's streaming queue.
 */
async function pushChunk({ roomCode, peerId, chunkIndex, totalChunks, isHeader, dataBase64 }) {
  if (!roomCode || dataBase64 === undefined) return false;
  const cleanCode = roomCode.trim().toUpperCase();
  const chunk = {
    peerId: peerId || 'unknown',
    chunkIndex: Number(chunkIndex) || 0,
    totalChunks: Number(totalChunks) || 1,
    isHeader: Boolean(isHeader),
    dataBase64,
    timestamp: Date.now(),
  };

  if (hasRedis) {
    try {
      const key = `dropsync:chunks:${cleanCode}`;
      await redisPipeline([
        ['RPUSH', key, JSON.stringify(chunk)],
        ['EXPIRE', key, ROOM_TTL_SEC],
      ]);
      return true;
    } catch (err) {
      console.warn('[Redis] pushChunk failed:', err.message);
    }
  }

  if (!memoryStore.chunks) memoryStore.chunks = new Map();
  if (!memoryStore.chunks.has(cleanCode)) {
    memoryStore.chunks.set(cleanCode, []);
  }
  const queue = memoryStore.chunks.get(cleanCode);
  // Cap at 1000 chunks to prevent memory exhaust
  if (queue.length > 1000) {
    queue.splice(0, queue.length - 1000);
  }
  queue.push(chunk);
  return true;
}

/**
 * Pull pending encrypted file chunks from the room's streaming queue.
 */
async function pullChunks({ roomCode, maxChunks = 20 }) {
  if (!roomCode) return [];
  const cleanCode = roomCode.trim().toUpperCase();
  const limit = Math.max(1, Math.min(Number(maxChunks) || 20, 50));

  if (hasRedis) {
    try {
      const key = `dropsync:chunks:${cleanCode}`;
      const res = await redisPipeline([
        ['LRANGE', key, 0, limit - 1],
        ['LTRIM', key, limit, -1],
      ]);
      if (res && res[0] && Array.isArray(res[0].result)) {
        return res[0].result.map(item => typeof item === 'string' ? JSON.parse(item) : item);
      }
      return [];
    } catch (err) {
      console.warn('[Redis] pullChunks failed:', err.message);
    }
  }

  if (!memoryStore.chunks) memoryStore.chunks = new Map();
  const queue = memoryStore.chunks.get(cleanCode) || [];
  if (queue.length === 0) return [];
  const pulled = queue.splice(0, Math.min(queue.length, limit));
  return pulled;
}

/**
 * Delete a room and its signals and chunks.
 */
async function deleteRoom(code) {
  if (!code) return;
  const cleanCode = code.trim().toUpperCase();

  if (hasRedis) {
    try {
      await redisPipeline([
        ['DEL', `dropsync:room:${cleanCode}`],
        ['DEL', `dropsync:signals:${cleanCode}:sender`],
        ['DEL', `dropsync:signals:${cleanCode}:receiver`],
        ['DEL', `dropsync:chunks:${cleanCode}`],
      ]);
    } catch (_) {}
  }

  memoryStore.rooms.delete(cleanCode);
  memoryStore.signals.delete(`${cleanCode}:sender`);
  memoryStore.signals.delete(`${cleanCode}:receiver`);
  if (memoryStore.chunks) memoryStore.chunks.delete(cleanCode);
}

/**
 * Calculate mutual presence and timeout status.
 */
function checkPresence(room) {
  if (!room) return { bothPresent: false, status: 'closed', transferState: 'closed' };

  const now = Date.now();
  const isSenderActive = room.senderStatus === 'active' && (now - room.senderLastHeartbeat < PEER_TIMEOUT_MS);
  const isReceiverActive = room.receiverStatus === 'active' && (now - room.receiverLastHeartbeat < PEER_TIMEOUT_MS);

  const bothPresent = Boolean(isSenderActive && isReceiverActive);

  return {
    bothPresent,
    senderActive: isSenderActive,
    receiverActive: isReceiverActive,
    senderLastSeenAgo: room.senderLastHeartbeat ? now - room.senderLastHeartbeat : -1,
    receiverLastSeenAgo: room.receiverLastHeartbeat ? now - room.receiverLastHeartbeat : -1,
    transferState: room.transferState || 'waiting',
    metadata: room.metadata || null,
    p2pReady: room.p2pReady || false,
  };
}

module.exports = {
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
  PEER_TIMEOUT_MS,
};
