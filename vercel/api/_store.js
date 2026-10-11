// Shared In-Memory Store for DropSync Serverless Relay
// Note: In serverless environments, globalThis persists across warm invocations.
if (!globalThis._dropSyncRooms) {
  globalThis._dropSyncRooms = new Map();
}

const PEER_TIMEOUT_MS = 4000;
const ROOM_TTL_MS = 15 * 60 * 1000; // 15 minutes max lifetime

function getStore() {
  return globalThis._dropSyncRooms;
}

function cleanExpiredRooms() {
  const now = Date.now();
  const store = getStore();
  for (const [code, room] of store.entries()) {
    if (now - room.createdAt > ROOM_TTL_MS) {
      store.delete(code);
    }
  }
}

function getRoom(code) {
  cleanExpiredRooms();
  if (!code) return null;
  const cleanCode = code.trim().toUpperCase();
  return getStore().get(cleanCode) || null;
}

function createOrJoinRoom({ roomCode, peerId, role, transferState, metadata }) {
  cleanExpiredRooms();
  const cleanCode = roomCode.trim().toUpperCase();
  const store = getStore();
  const now = Date.now();

  let room = store.get(cleanCode);
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
      transferState: transferState || 'waiting', // 'waiting' | 'transferring' | 'completed' | 'closed'
      metadata: metadata || null,
      chunks: [],
    };
    store.set(cleanCode, room);
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
    if (transferState) {
      room.transferState = transferState;
    }
    if (metadata) {
      room.metadata = metadata;
    }
  }

  return { room, presence: checkPresence(room) };
}

function updateTransferState({ roomCode, state, metadata }) {
  const room = getRoom(roomCode);
  if (!room) return null;
  if (state) room.transferState = state;
  if (metadata) room.metadata = metadata;
  return checkPresence(room);
}

function updateHeartbeat({ roomCode, peerId, role, status = 'active', transferState }) {
  const room = getRoom(roomCode);
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

  return checkPresence(room);
}

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
  };
}

module.exports = {
  getStore,
  getRoom,
  createOrJoinRoom,
  updateHeartbeat,
  updateTransferState,
  checkPresence,
  PEER_TIMEOUT_MS,
};
