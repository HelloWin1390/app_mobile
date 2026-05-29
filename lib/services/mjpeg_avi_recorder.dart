import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class MjpegAviRecorder {
  static Future<File> writeAvi({
    required List<Uint8List> frames,
    required int width,
    required int height,
    required int fps,
    required String fileName,
  }) async {
    if (frames.isEmpty) {
      throw StateError('No frames to write');
    }

    final safeWidth = math.max(1, width);
    final safeHeight = math.max(1, height);
    final safeFps = math.max(1, fps);
    final maxFrameSize = frames.fold<int>(
      0,
      (maxSize, frame) => math.max(maxSize, frame.length),
    );

    final movi = BytesBuilder(copy: false);
    final index = <_AviIndexEntry>[];
    var moviOffset = 4;

    movi.add(_ascii('movi'));
    for (final frame in frames) {
      index.add(
        _AviIndexEntry(
          offset: moviOffset,
          size: frame.length,
        ),
      );
      movi.add(_ascii('00dc'));
      movi.add(_u32(frame.length));
      movi.add(frame);
      if (frame.length.isOdd) {
        movi.addByte(0);
      }
      moviOffset += 8 + frame.length + (frame.length.isOdd ? 1 : 0);
    }

    final idx = BytesBuilder(copy: false);
    for (final entry in index) {
      idx.add(_ascii('00dc'));
      idx.add(_u32(0x10));
      idx.add(_u32(entry.offset));
      idx.add(_u32(entry.size));
    }

    final hdrl = _buildHeader(
      width: safeWidth,
      height: safeHeight,
      fps: safeFps,
      totalFrames: frames.length,
      maxFrameSize: maxFrameSize,
    );
    final moviBytes = movi.toBytes();
    final idxBytes = idx.toBytes();

    final file = BytesBuilder(copy: false);
    final riffSize =
        4 + (8 + hdrl.length) + (8 + moviBytes.length) + 8 + idxBytes.length;
    file.add(_ascii('RIFF'));
    file.add(_u32(riffSize));
    file.add(_ascii('AVI '));
    file.add(_chunkList('hdrl', hdrl));
    file.add(_chunkListRaw(moviBytes));
    file.add(_ascii('idx1'));
    file.add(_u32(idxBytes.length));
    file.add(idxBytes);

    final output = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await output.writeAsBytes(file.toBytes(), flush: true);
    return output;
  }

  static Uint8List _buildHeader({
    required int width,
    required int height,
    required int fps,
    required int totalFrames,
    required int maxFrameSize,
  }) {
    final out = BytesBuilder(copy: false);

    final avih = BytesBuilder(copy: false);
    avih.add(_u32(1000000 ~/ fps));
    avih.add(_u32(maxFrameSize * fps));
    avih.add(_u32(0));
    avih.add(_u32(0x10));
    avih.add(_u32(totalFrames));
    avih.add(_u32(0));
    avih.add(_u32(1));
    avih.add(_u32(maxFrameSize));
    avih.add(_u32(width));
    avih.add(_u32(height));
    for (var i = 0; i < 4; i += 1) {
      avih.add(_u32(0));
    }
    out.add(_chunk('avih', avih.toBytes()));

    final strl = BytesBuilder(copy: false);
    final strh = BytesBuilder(copy: false);
    strh.add(_ascii('vids'));
    strh.add(_ascii('MJPG'));
    strh.add(_u32(0));
    strh.add(_u16(0));
    strh.add(_u16(0));
    strh.add(_u32(0));
    strh.add(_u32(1));
    strh.add(_u32(fps));
    strh.add(_u32(0));
    strh.add(_u32(totalFrames));
    strh.add(_u32(maxFrameSize));
    strh.add(_u32(0xFFFFFFFF));
    strh.add(_u32(0));
    strh.add(_u16(0));
    strh.add(_u16(0));
    strh.add(_u16(width));
    strh.add(_u16(height));
    strl.add(_chunk('strh', strh.toBytes()));

    final strf = BytesBuilder(copy: false);
    strf.add(_u32(40));
    strf.add(_u32(width));
    strf.add(_u32(height));
    strf.add(_u16(1));
    strf.add(_u16(24));
    strf.add(_ascii('MJPG'));
    strf.add(_u32(maxFrameSize));
    strf.add(_u32(0));
    strf.add(_u32(0));
    strf.add(_u32(0));
    strf.add(_u32(0));
    strl.add(_chunk('strf', strf.toBytes()));

    out.add(_chunkList('strl', strl.toBytes()));
    return out.toBytes();
  }

  static Uint8List _chunk(String name, Uint8List bytes) {
    final out = BytesBuilder(copy: false);
    out.add(_ascii(name));
    out.add(_u32(bytes.length));
    out.add(bytes);
    if (bytes.length.isOdd) {
      out.addByte(0);
    }
    return out.toBytes();
  }

  static Uint8List _chunkList(String name, Uint8List bytes) {
    final out = BytesBuilder(copy: false);
    out.add(_ascii('LIST'));
    out.add(_u32(bytes.length + 4));
    out.add(_ascii(name));
    out.add(bytes);
    if (bytes.length.isOdd) {
      out.addByte(0);
    }
    return out.toBytes();
  }

  static Uint8List _chunkListRaw(Uint8List bytes) {
    final out = BytesBuilder(copy: false);
    out.add(_ascii('LIST'));
    out.add(_u32(bytes.length));
    out.add(bytes);
    if (bytes.length.isOdd) {
      out.addByte(0);
    }
    return out.toBytes();
  }

  static Uint8List _ascii(String value) {
    return Uint8List.fromList(value.codeUnits);
  }

  static Uint8List _u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}

class _AviIndexEntry {
  final int offset;
  final int size;

  const _AviIndexEntry({
    required this.offset,
    required this.size,
  });
}
