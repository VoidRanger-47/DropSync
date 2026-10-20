/**
 * DropSync Cloudflare Pages Advanced Worker (_worker.js)
 * Serves static assets via env.ASSETS and handles WebSockets (/ws) & API (/api/*) at the edge.
 */

const rooms = new Map();

function sweepOldRooms() {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    if (now - room.lastActive > 5 * 60 * 1000 && (!room.sockets || room.sockets.size === 0)) {
      rooms.delete(code);
    }
  }
}

function getOrCreateRoom(code) {
  sweepOldRooms();
  let room = rooms.get(code);
  if (!room) {
    room = {
      code,
      senderId: null,
      receiverId: null,
      senderLastHeartbeat: 0,
      receiverLastHeartbeat: 0,
      createdAt: Date.now(),
      lastActive: Date.now(),
      sockets: new Map(),
      chunkQueue: [],
      signalQueue: [],
    };
    rooms.set(code, room);
  }
  room.lastActive = Date.now();
  return room;
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS, PUT, DELETE',
  'Access-Control-Allow-Headers': 'Content-Type, X-DropSync-Peer, Authorization, Accept',
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders,
    },
  });
}

async function handleApiAndWs(request) {
  const url = new URL(request.url);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (url.pathname === '/api/health') {
    return jsonResponse({
      status: 'ok',
      service: 'DropSync Cloudflare Edge Relay (Pages)',
      edgeRegion: request.cf?.colo || 'GLOBAL',
      timestamp: new Date().toISOString(),
      activeRooms: rooms.size,
    });
  }

  // Persistent WebSockets: /ws?room=XXX-XXX&peer=peer_123&role=sender
  if (url.pathname === '/ws') {
    const upgradeHeader = request.headers.get('Upgrade');
    if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
      return new Response('Expected WebSocket Upgrade', { status: 426, headers: corsHeaders });
    }

    const roomCode = (url.searchParams.get('room') || '').toUpperCase().trim();
    const peerId = url.searchParams.get('peer') || `peer_${Math.random().toString(36).substring(2, 8)}`;
    const role = url.searchParams.get('role') || 'receiver';

    if (!roomCode) {
      return new Response('Missing room parameter', { status: 400, headers: corsHeaders });
    }

    const webSocketPair = new WebSocketPair();
    const [clientSocket, serverSocket] = Object.values(webSocketPair);

    serverSocket.accept();

    const room = getOrCreateRoom(roomCode);
    if (role === 'sender') {
      room.senderId = peerId;
      room.senderLastHeartbeat = Date.now();
    } else {
      room.receiverId = peerId;
      room.receiverLastHeartbeat = Date.now();
    }
    room.sockets.set(peerId, serverSocket);

    const broadcastPresence = () => {
      const hasSender = !!room.senderId && room.sockets.has(room.senderId);
      const hasReceiver = !!room.receiverId && room.sockets.has(room.receiverId);
      const bothPresent = hasSender && hasReceiver;

      const payload = JSON.stringify({
        type: 'presence',
        roomCode,
        senderId: room.senderId,
        receiverId: room.receiverId,
        bothPresent,
        timestamp: Date.now(),
      });

      for (const [_, ws] of room.sockets.entries()) {
        try {
          ws.send(payload);
        } catch (_) {}
      }
    };

    broadcastPresence();

    serverSocket.addEventListener('message', event => {
      room.lastActive = Date.now();
      if (role === 'sender') room.senderLastHeartbeat = Date.now();
      if (role === 'receiver') room.receiverLastHeartbeat = Date.now();

      try {
        const msg = typeof event.data === 'string' ? JSON.parse(event.data) : null;
        if (msg && msg.type === 'ping') {
          serverSocket.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
          return;
        }
      } catch (_) {}

      // Forward blind encrypted message directly to other peers
      for (const [otherPeerId, otherSocket] of room.sockets.entries()) {
        if (otherPeerId !== peerId) {
          try {
            otherSocket.send(event.data);
          } catch (_) {}
        }
      }
    });

    const handleClose = () => {
      room.sockets.delete(peerId);
      if (role === 'sender' && room.senderId === peerId) room.senderId = null;
      if (role === 'receiver' && room.receiverId === peerId) room.receiverId = null;

      for (const [_, otherSocket] of room.sockets.entries()) {
        try {
          otherSocket.send(JSON.stringify({
            type: 'peer_left',
            departedPeerId: peerId,
            role,
            timestamp: Date.now(),
          }));
        } catch (_) {}
      }
    };

    serverSocket.addEventListener('close', handleClose);
    serverSocket.addEventListener('error', handleClose);

    return new Response(null, {
      status: 101,
      webSocket: clientSocket,
      headers: corsHeaders,
    });
  }

  // REST API: /api/room
  if (url.pathname === '/api/room') {
    const action = url.searchParams.get('action') || (request.method === 'GET' ? 'poll_chunk' : 'create');

    let body = {};
    if (request.method === 'POST') {
      try {
        body = await request.json();
      } catch (_) {}
    }

    const roomCode = ((body.roomCode || url.searchParams.get('roomCode') || '')).toUpperCase().trim();
    const peerId = body.peerId || url.searchParams.get('peerId') || '';

    if (!roomCode) {
      return jsonResponse({ error: 'Missing roomCode' }, 400);
    }

    const room = getOrCreateRoom(roomCode);

    if (action === 'create') {
      room.senderId = peerId;
      room.senderLastHeartbeat = Date.now();
      return jsonResponse({
        success: true,
        roomCode,
        senderId: peerId,
        presence: {
          isSenderPresent: true,
          isReceiverPresent: !!room.receiverId && (Date.now() - room.receiverLastHeartbeat < 4000),
          bothPresent: false,
        },
      });
    }

    if (action === 'join' || (!action && body.role === 'receiver')) {
      room.receiverId = peerId;
      room.receiverLastHeartbeat = Date.now();
      const senderAlive = !!room.senderId && (Date.now() - room.senderLastHeartbeat < 4000);
      return jsonResponse({
        success: true,
        roomCode,
        receiverId: peerId,
        presence: {
          isSenderPresent: senderAlive,
          isReceiverPresent: true,
          bothPresent: senderAlive,
        },
      });
    }

    if (action === 'heartbeat') {
      const isSender = body.isSender ?? (peerId === room.senderId);
      if (isSender) {
        room.senderLastHeartbeat = Date.now();
      } else {
        room.receiverLastHeartbeat = Date.now();
      }

      const senderAlive = !!room.senderId && (Date.now() - room.senderLastHeartbeat < 4000);
      const receiverAlive = !!room.receiverId && (Date.now() - room.receiverLastHeartbeat < 4000);

      return jsonResponse({
        success: true,
        presence: {
          isSenderPresent: senderAlive,
          isReceiverPresent: receiverAlive,
          bothPresent: senderAlive && receiverAlive,
        },
        lastHeartbeat: Date.now(),
      });
    }

    if (action === 'poll_heartbeat') {
      const senderAlive = !!room.senderId && (Date.now() - room.senderLastHeartbeat < 4000);
      const receiverAlive = !!room.receiverId && (Date.now() - room.receiverLastHeartbeat < 4000);
      return jsonResponse({
        presence: {
          isSenderPresent: senderAlive,
          isReceiverPresent: receiverAlive,
          bothPresent: senderAlive && receiverAlive,
        },
        lastHeartbeat: Date.now(),
      });
    }

    if (action === 'chunk') {
      room.chunkQueue.push({
        chunkIndex: body.chunkIndex,
        totalChunks: body.totalChunks,
        isHeader: body.isHeader,
        dataBase64: body.dataBase64,
        timestamp: Date.now(),
      });
      if (room.chunkQueue.length > 200) room.chunkQueue.shift();
      return jsonResponse({ success: true, queued: room.chunkQueue.length });
    }

    if (action === 'poll_chunk') {
      const chunk = room.chunkQueue.length > 0 ? room.chunkQueue.shift() : null;
      return jsonResponse({ chunk });
    }

    if (action === 'signal') {
      room.signalQueue.push({
        peerId,
        signal: body.signal,
        timestamp: Date.now(),
      });
      return jsonResponse({ success: true });
    }

    if (action === 'poll_signal') {
      const signals = room.signalQueue.filter(s => s.peerId !== peerId);
      room.signalQueue = room.signalQueue.filter(s => s.peerId === peerId);
      return jsonResponse({ signals });
    }

    return jsonResponse({ error: `Unknown action: ${action}` }, 400);
  }

  return jsonResponse({ error: 'Not found' }, 404);
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 1. Route API and WebSockets through the Edge Worker
    if (url.pathname === '/ws' || url.pathname.startsWith('/api/')) {
      return handleApiAndWs(request);
    }

    // 2. Serve static files (HTML, CSS, JS, images) via Cloudflare Pages Asset Pipeline
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    return handleApiAndWs(request);
  },
};
