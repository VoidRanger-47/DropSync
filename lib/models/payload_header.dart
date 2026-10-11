import 'dart:convert';
import 'dart:typed_data';

/// Magic markers identifying the DropSync binary protocol frames.
class DropSyncMagic {
  /// File streaming frame: 'DSYN' (0x44 0x53 0x59 0x4E)
  static const List<int> fileStream = [0x44, 0x53, 0x59, 0x4E];

  /// Compatibility file streaming frame: 'DSFS' (0x44 0x53 0x46 0x53)
  static const List<int> legacyFileStream = [0x44, 0x53, 0x46, 0x53];

  /// Legacy v1 prototype frame: (0x4E 0x4C 0x4E 0x4B)
  static const List<int> legacyV1FileStream = [0x4E, 0x4C, 0x4E, 0x4B];

  /// Clipboard text frame: 'DSCP' (0x44 0x53 0x43 0x50)
  static const List<int> clipboard = [0x44, 0x53, 0x43, 0x50];

  /// Legacy clipboard frame: (0x4E 0x4C 0x43 0x50)
  static const List<int> legacyClipboard = [0x4E, 0x4C, 0x43, 0x50];

  /// Handshake / auth frame: 'DSAU' (0x44 0x53 0x41 0x55)
  static const List<int> auth = [0x44, 0x53, 0x41, 0x55];

  /// Legacy auth frame: (0x4E 0x4C 0x41 0x55)
  static const List<int> legacyAuth = [0x4E, 0x4C, 0x41, 0x55];

  /// Ping frame: 'DSPF' (0x44 0x53 0x50 0x46)
  static const List<int> ping = [0x44, 0x53, 0x50, 0x46];
}

/// Represents the fixed-wire binary header for incoming and outgoing files.
/// Wire format:
/// `[4 bytes magic][2 bytes name_len][N bytes filename][8 bytes file_size][raw stream payload]`
class PayloadHeader {
  final List<int> magic;
  final String fileName;
  final int fileSize;
  final String? token;

  const PayloadHeader({
    required this.magic,
    required this.fileName,
    required this.fileSize,
    this.token,
  });

  /// Factory for standard file transfer
  factory PayloadHeader.file({
    required String fileName,
    required int fileSize,
    String? token,
  }) {
    return PayloadHeader(
      magic: DropSyncMagic.fileStream,
      fileName: fileName,
      fileSize: fileSize,
      token: token,
    );
  }

  /// Factory for clipboard synchronization
  factory PayloadHeader.clipboard({
    required String text,
    String? token,
  }) {
    final textBytes = utf8.encode(text);
    return PayloadHeader(
      magic: DropSyncMagic.clipboard,
      fileName: 'clipboard.txt',
      fileSize: textBytes.length,
      token: token,
    );
  }

  /// Serializes header to binary bytes ready for network transmission.
  Uint8List toBytes() {
    final nameBytes = utf8.encode(fileName);
    final nameLen = nameBytes.length;
    final totalLen = 4 + 2 + nameLen + 8;
    final data = ByteData(totalLen);

    // 4 bytes: Magic
    for (int i = 0; i < 4; i++) {
      data.setUint8(i, magic[i]);
    }

    // 2 bytes: name_len (uint16 big-endian)
    data.setUint16(4, nameLen, Endian.big);

    // N bytes: filename UTF-8
    int offset = 6;
    for (int i = 0; i < nameLen; i++) {
      data.setUint8(offset + i, nameBytes[i]);
    }
    offset += nameLen;

    // 8 bytes: file_size (uint64 big-endian)
    data.setUint64(offset, fileSize, Endian.big);

    return data.buffer.asUint8List();
  }

  /// Attempts to parse a header from a binary buffer.
  /// Returns null if the buffer is incomplete or magic does not match.
  static PayloadHeader? tryParse(Uint8List buffer, {int offset = 0}) {
    if (buffer.length - offset < 4 + 2 + 8) return null;

    final data = ByteData.sublistView(buffer, offset);
    final m0 = data.getUint8(0);
    final m1 = data.getUint8(1);
    final m2 = data.getUint8(2);
    final m3 = data.getUint8(3);
    final magic = [m0, m1, m2, m3];

    final isFile = _matchMagic(magic, DropSyncMagic.fileStream) ||
        _matchMagic(magic, DropSyncMagic.legacyFileStream) ||
        _matchMagic(magic, DropSyncMagic.legacyV1FileStream);
    final isClip = _matchMagic(magic, DropSyncMagic.clipboard) ||
        _matchMagic(magic, DropSyncMagic.legacyClipboard);
    final isAuth = _matchMagic(magic, DropSyncMagic.auth) ||
        _matchMagic(magic, DropSyncMagic.legacyAuth);

    if (!isFile && !isClip && !isAuth) {
      return null;
    }

    final nameLen = data.getUint16(4, Endian.big);
    final requiredTotal = 4 + 2 + nameLen + 8;
    if (buffer.length - offset < requiredTotal) return null;

    // Read filename
    final nameBytes = buffer.sublist(offset + 6, offset + 6 + nameLen);
    final fileName = utf8.decode(nameBytes, allowMalformed: true);

    // Read file size
    final fileSize = data.getUint64(6 + nameLen, Endian.big);

    return PayloadHeader(
      magic: magic,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  /// Total header length on wire in bytes
  int get wireHeaderLength {
    final nameBytes = utf8.encode(fileName);
    return 4 + 2 + nameBytes.length + 8;
  }

  bool get isClipboardTransfer =>
      _matchMagic(magic, DropSyncMagic.clipboard) ||
      _matchMagic(magic, DropSyncMagic.legacyClipboard);
  bool get isFileTransfer =>
      _matchMagic(magic, DropSyncMagic.fileStream) ||
      _matchMagic(magic, DropSyncMagic.legacyFileStream) ||
      _matchMagic(magic, DropSyncMagic.legacyV1FileStream);

  static bool _matchMagic(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'PayloadHeader(file: $fileName, size: $fileSize bytes, magic: ${utf8.decode(magic, allowMalformed: true)})';
}
