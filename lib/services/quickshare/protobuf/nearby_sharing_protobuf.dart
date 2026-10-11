import 'dart:convert';
import 'dart:typed_data';

/// Minimal, high-performance Protocol Buffers encoder and decoder
/// tailored for Google Quick Share / Nearby Connections frames.
class PbWire {
  static const int wireVarint = 0;
  static const int wireFixed64 = 1;
  static const int wireLengthDelimited = 2;
  static const int wireFixed32 = 5;

  static Uint8List encodeVarint(int value) {
    final bytes = <int>[];
    int v = value;
    while (v >= 0x80) {
      bytes.add((v & 0x7F) | 0x80);
      v = (v >> 7);
    }
    bytes.add(v & 0x7F);
    return Uint8List.fromList(bytes);
  }

  static Uint8List encodeTag(int fieldNumber, int wireType) {
    return encodeVarint((fieldNumber << 3) | wireType);
  }

  static Uint8List encodeString(int fieldNumber, String value) {
    final strBytes = utf8.encode(value);
    final b = BytesBuilder();
    b.add(encodeTag(fieldNumber, wireLengthDelimited));
    b.add(encodeVarint(strBytes.length));
    b.add(strBytes);
    return b.toBytes();
  }

  static Uint8List encodeBytes(int fieldNumber, List<int> bytes) {
    final b = BytesBuilder();
    b.add(encodeTag(fieldNumber, wireLengthDelimited));
    b.add(encodeVarint(bytes.length));
    b.add(bytes);
    return b.toBytes();
  }

  static Uint8List encodeInt(int fieldNumber, int value) {
    final b = BytesBuilder();
    b.add(encodeTag(fieldNumber, wireVarint));
    b.add(encodeVarint(value));
    return b.toBytes();
  }
}

/// Represents UKEY2 handshake messages.
class Ukey2Message {
  final int messageType; // 1 = CLIENT_INIT, 2 = SERVER_INIT, 3 = CLIENT_FINISH
  final Uint8List payload;

  Ukey2Message({required this.messageType, required this.payload});

  Uint8List toBytes() {
    final b = BytesBuilder();
    b.add(PbWire.encodeInt(1, messageType));
    b.add(PbWire.encodeBytes(2, payload));
    return b.toBytes();
  }

  static Ukey2Message? parse(Uint8List data) {
    int offset = 0;
    int msgType = 1;
    Uint8List? payload;

    while (offset < data.length) {
      final tagRes = _readVarint(data, offset);
      offset = tagRes.nextOffset;
      final fieldNum = tagRes.value >> 3;
      final wireType = tagRes.value & 0x07;

      if (wireType == PbWire.wireVarint) {
        final valRes = _readVarint(data, offset);
        offset = valRes.nextOffset;
        if (fieldNum == 1) msgType = valRes.value;
      } else if (wireType == PbWire.wireLengthDelimited) {
        final lenRes = _readVarint(data, offset);
        offset = lenRes.nextOffset;
        final length = lenRes.value;
        final valBytes = data.sublist(offset, offset + length);
        offset += length;
        if (fieldNum == 2) payload = valBytes;
      } else {
        break;
      }
    }

    if (payload != null) {
      return Ukey2Message(messageType: msgType, payload: payload);
    }
    return null;
  }
}

/// OfflineFrame representing Nearby Connections communication.
class OfflineFrame {
  final int type; // 1 = CONNECTION_REQUEST, 2 = CONNECTION_RESPONSE, 3 = PAYLOAD_TRANSFER
  final String? endpointId;
  final String? endpointName;
  final Uint8List? payloadHeader;
  final Uint8List? payloadChunk;

  OfflineFrame({
    required this.type,
    this.endpointId,
    this.endpointName,
    this.payloadHeader,
    this.payloadChunk,
  });

  /// Serializes OfflineFrame with Google 4-byte big-endian length framing.
  Uint8List toFramedBytes() {
    final raw = toBytes();
    final framed = ByteData(4 + raw.length);
    framed.setUint32(0, raw.length, Endian.big);
    for (int i = 0; i < raw.length; i++) {
      framed.setUint8(4 + i, raw[i]);
    }
    return framed.buffer.asUint8List();
  }

  Uint8List toBytes() {
    final b = BytesBuilder();
    // Field 1: Version = 1
    b.add(PbWire.encodeInt(1, 1));
    // Field 2: Type
    b.add(PbWire.encodeInt(2, type));

    if (type == 1 && endpointId != null && endpointName != null) {
      // ConnectionRequest in Field 3
      final sub = BytesBuilder();
      sub.add(PbWire.encodeString(1, endpointId!));
      sub.add(PbWire.encodeString(2, endpointName!));
      b.add(PbWire.encodeBytes(3, sub.toBytes()));
    } else if (type == 2) {
      // ConnectionResponse in Field 4 (status 1 = ACCEPT)
      final sub = BytesBuilder();
      sub.add(PbWire.encodeInt(1, 1));
      b.add(PbWire.encodeBytes(4, sub.toBytes()));
    } else if (type == 3 && payloadChunk != null) {
      // PayloadTransfer in Field 5
      final sub = BytesBuilder();
      if (payloadHeader != null) {
        sub.add(PbWire.encodeBytes(1, payloadHeader!));
      }
      sub.add(PbWire.encodeBytes(2, payloadChunk!));
      b.add(PbWire.encodeBytes(5, sub.toBytes()));
    }

    return b.toBytes();
  }

  static OfflineFrame? parseFramed(Uint8List framedData) {
    if (framedData.length < 4) return null;
    final length = ByteData.sublistView(framedData).getUint32(0, Endian.big);
    if (framedData.length < 4 + length) return null;
    final raw = framedData.sublist(4, 4 + length);
    return parse(raw);
  }

  static OfflineFrame? parse(Uint8List data) {
    int offset = 0;
    int type = 1;
    String? epId;
    String? epName;

    while (offset < data.length) {
      final tagRes = _readVarint(data, offset);
      offset = tagRes.nextOffset;
      final fieldNum = tagRes.value >> 3;
      final wireType = tagRes.value & 0x07;

      if (wireType == PbWire.wireVarint) {
        final valRes = _readVarint(data, offset);
        offset = valRes.nextOffset;
        if (fieldNum == 2) type = valRes.value;
      } else if (wireType == PbWire.wireLengthDelimited) {
        final lenRes = _readVarint(data, offset);
        offset = lenRes.nextOffset;
        final length = lenRes.value;
        final valBytes = data.sublist(offset, offset + length);
        offset += length;

        if (fieldNum == 3) {
          // ConnectionRequest sub-message
          final parsedConn = _parseConnectionRequest(valBytes);
          epId = parsedConn['id'];
          epName = parsedConn['name'];
        }
      } else {
        break;
      }
    }

    return OfflineFrame(
      type: type,
      endpointId: epId,
      endpointName: epName,
    );
  }

  static Map<String, String> _parseConnectionRequest(Uint8List sub) {
    int offset = 0;
    String id = '';
    String name = '';
    while (offset < sub.length) {
      final tagRes = _readVarint(sub, offset);
      offset = tagRes.nextOffset;
      final fieldNum = tagRes.value >> 3;
      final wireType = tagRes.value & 0x07;
      if (wireType == PbWire.wireLengthDelimited) {
        final lenRes = _readVarint(sub, offset);
        offset = lenRes.nextOffset;
        final length = lenRes.value;
        final str = utf8.decode(sub.sublist(offset, offset + length), allowMalformed: true);
        offset += length;
        if (fieldNum == 1) id = str;
        if (fieldNum == 2) name = str;
      } else if (wireType == PbWire.wireVarint) {
        final valRes = _readVarint(sub, offset);
        offset = valRes.nextOffset;
      }
    }
    return {'id': id, 'name': name};
  }
}

/// NearbySharing Introduction Frame containing file descriptors.
class IntroductionFrame {
  final List<QuickShareFileMeta> files;

  IntroductionFrame({required this.files});

  Uint8List toBytes() {
    final b = BytesBuilder();
    for (final f in files) {
      final sub = BytesBuilder();
      sub.add(PbWire.encodeString(1, f.name));
      sub.add(PbWire.encodeInt(2, f.type));
      sub.add(PbWire.encodeInt(3, f.payloadId));
      sub.add(PbWire.encodeInt(4, f.size));
      sub.add(PbWire.encodeString(5, f.mimeType));
      b.add(PbWire.encodeBytes(1, sub.toBytes()));
    }
    return b.toBytes();
  }

  static IntroductionFrame parse(Uint8List data) {
    int offset = 0;
    final files = <QuickShareFileMeta>[];

    while (offset < data.length) {
      final tagRes = _readVarint(data, offset);
      offset = tagRes.nextOffset;
      final fieldNum = tagRes.value >> 3;
      final wireType = tagRes.value & 0x07;

      if (wireType == PbWire.wireLengthDelimited) {
        final lenRes = _readVarint(data, offset);
        offset = lenRes.nextOffset;
        final length = lenRes.value;
        final sub = data.sublist(offset, offset + length);
        offset += length;

        if (fieldNum == 1) {
          final f = _parseFileMeta(sub);
          files.add(f);
        }
      } else if (wireType == PbWire.wireVarint) {
        final v = _readVarint(data, offset);
        offset = v.nextOffset;
      }
    }

    return IntroductionFrame(files: files);
  }

  static QuickShareFileMeta _parseFileMeta(Uint8List sub) {
    int offset = 0;
    String name = 'unnamed';
    int type = 1;
    int payloadId = 1;
    int size = 0;
    String mime = 'application/octet-stream';

    while (offset < sub.length) {
      final tagRes = _readVarint(sub, offset);
      offset = tagRes.nextOffset;
      final fieldNum = tagRes.value >> 3;
      final wireType = tagRes.value & 0x07;

      if (wireType == PbWire.wireLengthDelimited) {
        final lenRes = _readVarint(sub, offset);
        offset = lenRes.nextOffset;
        final length = lenRes.value;
        final s = utf8.decode(sub.sublist(offset, offset + length), allowMalformed: true);
        offset += length;
        if (fieldNum == 1) name = s;
        if (fieldNum == 5) mime = s;
      } else if (wireType == PbWire.wireVarint) {
        final valRes = _readVarint(sub, offset);
        offset = valRes.nextOffset;
        if (fieldNum == 2) type = valRes.value;
        if (fieldNum == 3) payloadId = valRes.value;
        if (fieldNum == 4) size = valRes.value;
      }
    }

    return QuickShareFileMeta(
      name: name,
      type: type,
      payloadId: payloadId,
      size: size,
      mimeType: mime,
    );
  }
}

class QuickShareFileMeta {
  final String name;
  final int type; // 1 = FILE, 2 = TEXT
  final int payloadId;
  final int size;
  final String mimeType;

  QuickShareFileMeta({
    required this.name,
    required this.type,
    required this.payloadId,
    required this.size,
    required this.mimeType,
  });
}

class _VarintResult {
  final int value;
  final int nextOffset;
  _VarintResult(this.value, this.nextOffset);
}

_VarintResult _readVarint(Uint8List data, int offset) {
  int result = 0;
  int shift = 0;
  int cur = offset;
  while (cur < data.length) {
    final b = data[cur++];
    result |= (b & 0x7F) << shift;
    if ((b & 0x80) == 0) break;
    shift += 7;
  }
  return _VarintResult(result, cur);
}
