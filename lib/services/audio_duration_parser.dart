import 'dart:io';

/// Pure-Dart audio duration parser — no player, no native plugins.
/// Reads only a few KB of headers per file, so it is tens of ms
/// instead of seconds per song.
class AudioDurationParser {
  static Future<int?> getDurationMs(String path) async {
    try {
      final lower = path.toLowerCase();
      if (lower.endsWith('.flac')) return await _flac(path);
      if (lower.endsWith('.wav')) return await _wav(path);
      if (lower.endsWith('.m4a') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.aac') && await _isMp4(path)) {
        return await _mp4(path);
      }
      if (lower.endsWith('.ogg') ||
          lower.endsWith('.oga') ||
          lower.endsWith('.opus')) {
        return await _ogg(path);
      }
      if (lower.endsWith('.mp3')) return await _mp3(path);
      if (lower.endsWith('.aac')) return await _aacAdts(path);
      if (lower.endsWith('.wma')) return await _wma(path);
      // Fallback: try mp3-style estimate for unknown containers.
      return await _mp3(path);
    } catch (_) {
      return null;
    }
  }

  // ─── FLAC: STREAMINFO has totalSamples + sampleRate ───
  static Future<int?> _flac(String path) async {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      final magic = await raf.read(4);
      if (magic.length < 4 ||
          magic[0] != 0x66 ||
          magic[1] != 0x4C ||
          magic[2] != 0x61 ||
          magic[3] != 0x43) {
        return null; // not fLaC
      }
      var last = false;
      while (!last) {
        final h = await raf.read(4);
        if (h.length < 4) return null;
        last = (h[0] & 0x80) != 0;
        final type = h[0] & 0x7F;
        final len = (h[1] << 16) | (h[2] << 8) | h[3];
        if (type == 0) {
          // STREAMINFO, 34 bytes
          final d = await raf.read(34);
          if (d.length < 34) return null;
          // bytes 10..17 hold sr(20) + ch(3) + bps(5) + totalSamples(36)
          final sr = (d[10] << 12) | (d[11] << 4) | (d[12] >> 4);
          if (sr == 0) return null;
          // 36-bit totalSamples across bytes 12..17.
          int totalSamples = (d[12] & 0x0F);
          for (var i = 13; i <= 17; i++) {
            totalSamples = (totalSamples << 8) | d[i];
          }
          if (totalSamples == 0) return null;
          return (totalSamples * 1000 ~/ sr);
        } else {
          await raf.setPosition(await raf.position() + len);
        }
        if (len < 0 || len > 16 * 1024 * 1024) return null;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  // ─── WAV: dataSize / byteRate ───
  static Future<int?> _wav(String path) async {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      final head = await raf.read(44);
      if (head.length < 44) return null;
      // Walk chunks (handles extra chunks like LIST/bext)
      await raf.setPosition(12);
      int? byteRate;
      int? dataSize;
      for (var guard = 0; guard < 32; guard++) {
        final h = await raf.read(8);
        if (h.length < 8) break;
        final id = String.fromCharCodes(h.sublist(0, 4));
        final size = h[4] | (h[5] << 8) | (h[6] << 16) | (h[7] << 24);
        if (id == 'fmt ') {
          final fmt = await raf.read(size < 16 ? size : 16);
          if (fmt.length >= 16) {
            byteRate = fmt[8] |
                (fmt[9] << 8) |
                (fmt[10] << 16) |
                (fmt[11] << 24);
          }
          if (size > 16) {
            await raf.setPosition(await raf.position() + (size - 16));
          }
        } else if (id == 'data') {
          dataSize = size;
          break;
        } else {
          if (size < 0 || size > 1 << 31) break;
          // word-align
          await raf.setPosition(await raf.position() + size + (size % 2));
        }
      }
      if (byteRate != null && byteRate > 0 && dataSize != null) {
        return dataSize * 1000 ~/ byteRate;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  // ─── MP4/M4A: moov/mvhd timescale + duration ───
  static Future<int?> _mp4(String path) async {
    final f = File(path);
    final len = await f.length();
    final raf = await f.open(mode: FileMode.read);
    try {
      final scanLen = len < 2 * 1024 * 1024 ? len : 2 * 1024 * 1024;
      var pos = 0;
      while (pos + 8 <= scanLen) {
        await raf.setPosition(pos);
        final h = await raf.read(8);
        if (h.length < 8) break;
        int size = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
        final type = String.fromCharCodes(h.sublist(4, 8));
        int headerLen = 8;
        if (size == 1) {
          final ext = await raf.read(8);
          if (ext.length < 8) break;
          size = 0;
          for (var i = 0; i < 8; i++) {
            size = (size << 8) | ext[i];
          }
          headerLen = 16;
        }
        if (size <= 0) break;
        if (type == 'mvhd') {
          final v = await raf.read(4);
          if (v.length < 4) break;
          final version = v[0];
          if (version == 0) {
            final d = await raf.read(12);
            if (d.length < 12) break;
            final timescale =
                (d[8] << 24) | (d[9] << 16) | (d[10] << 8) | d[11];
            final durBytes = await raf.read(4);
            final duration = (durBytes[0] << 24) |
                (durBytes[1] << 16) |
                (durBytes[2] << 8) |
                durBytes[3];
            if (timescale > 0) return duration * 1000 ~/ timescale;
            return null;
          } else {
            await raf.setPosition(await raf.position() + 8 + 8);
            final d = await raf.read(12);
            if (d.length < 12) break;
            final timescale =
                (d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3];
            int duration = 0;
            final db = await raf.read(8);
            for (var i = 0; i < 8; i++) {
              duration = (duration << 8) | db[i];
            }
            if (timescale > 0) return duration * 1000 ~/ timescale;
            return null;
          }
        }
        // Only descend into containers to stay fast.
        if (type == 'moov' ||
            type == 'trak' ||
            type == 'mdia' ||
            type == 'minf' ||
            type == 'stbl' ||
            type == 'edts' ||
            type == 'udta' ||
            type == 'meta' ||
            type == 'uuid') {
          pos += headerLen;
          continue;
        }
        pos += size;
        if (size < 8) break;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  static Future<bool> _isMp4(String path) async {
    try {
      final raf = await File(path).open(mode: FileMode.read);
      try {
        final h = await raf.read(12);
        if (h.length < 12) return false;
        final type = String.fromCharCodes(h.sublist(4, 8));
        return type == 'ftyp';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  // ─── Ogg Vorbis / Opus: last granule / sampleRate ───
  static Future<int?> _ogg(String path) async {
    final f = File(path);
    final len = await f.length();
    if (len < 100) return null;
    final raf = await f.open(mode: FileMode.read);
    try {
      // First page: detect codec + sample rate.
      await raf.setPosition(0);
      final head = await raf.read(128);
      final text = String.fromCharCodes(head);
      final isOpus = text.contains('OpusHead');
      final isVorbis = text.contains('vorbis');
      int sampleRate = 48000;
      if (isVorbis) {
        // Vorbis id header: search for 'vorbis' then sample rate 4 LE after.
        for (var i = 0; i + 12 < head.length; i++) {
          if (head[i] == 0x76 &&
              head[i + 1] == 0x6F &&
              head[i + 2] == 0x72 &&
              head[i + 3] == 0x62 &&
              head[i + 4] == 0x69 &&
              head[i + 5] == 0x73) {
            // packet_type(1) + 'vorbis'(6) + version(4) + channels(1) + sr(4)
            final o = i + 6 + 4 + 1;
            if (o + 4 <= head.length) {
              sampleRate = head[o] |
                  (head[o + 1] << 8) |
                  (head[o + 2] << 16) |
                  (head[o + 3] << 24);
            }
            break;
          }
        }
      } else if (!isOpus) {
        // Unknown ogg flavour — fall through to estimate.
      }

      // Tail scan for last OggS granule.
      final tailSize = len < 64 * 1024 ? len : 64 * 1024;
      await raf.setPosition(len - tailSize);
      final tail = await raf.read(tailSize);
      int lastGranule = 0;
      for (var i = tail.length - 14; i >= 0; i--) {
        if (tail[i] == 0x4F &&
            tail[i + 1] == 0x67 &&
            tail[i + 2] == 0x67 &&
            tail[i + 3] == 0x53) {
          // granule at +6, 8 bytes LE
          if (i + 14 <= tail.length) {
            int g = 0;
            for (var b = 7; b >= 0; b--) {
              g = (g << 8) | tail[i + 6 + b];
            }
            if (g > lastGranule) lastGranule = g;
            if (g > 0) break; // pages are in order at tail; first found backwards may not be last — keep max then break after one?
          }
        }
      }
      // The loop above scans backwards so first hit is the last page.
      if (lastGranule > 0 && sampleRate > 0) {
        return lastGranule * 1000 ~/ sampleRate;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  // ─── MP3: Xing/VBRI or CBR estimate ───
  static const _mp3Bitrates = [
    [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448], // MPEG1 L1
    [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384], // MPEG1 L2
    [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320], // MPEG1 L3
    [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256], // MPEG2 L1
    [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160], // MPEG2 L2/L3
  ];
  static const _mp3SampleRates = [
    [44100, 48000, 32000],
    [22050, 24000, 16000],
    [11025, 12000, 8000],
  ];

  static Future<int?> _mp3(String path) async {
    final f = File(path);
    final fileSize = await f.length();
    final raf = await f.open(mode: FileMode.read);
    try {
      int audioStart = 0;
      final h10 = await raf.read(10);
      if (h10.length == 10 &&
          h10[0] == 0x49 &&
          h10[1] == 0x44 &&
          h10[2] == 0x53) {
        final size = (h10[6] << 21) | (h10[7] << 14) | (h10[8] << 7) | h10[9];
        final flags = h10[5];
        if (size > 0 && size < 20 * 1024 * 1024) {
          audioStart = 10 + size;
          if ((flags & 0x10) != 0) audioStart += 10; // footer
        }
      }
      // Trailing tags (ID3v1 128B, APEv2) should not count as audio.
      int audioEnd = fileSize;
      if (fileSize > 128) {
        await raf.setPosition(fileSize - 128);
        final tail = await raf.read(3);
        if (tail.length == 3 &&
            tail[0] == 0x54 &&
            tail[1] == 0x41 &&
            tail[2] == 0x47) {
          audioEnd -= 128;
        }
      }

      final probeLen = 256 * 1024;
      await raf.setPosition(audioStart);
      final maxProbe =
          (audioEnd - audioStart) < probeLen ? (audioEnd - audioStart) : probeLen;
      if (maxProbe <= 4) return null;
      final buf = await raf.read(maxProbe);
      if (buf.isEmpty) return null;

      // 1) Fast path: Xing / Info / VBRI (exact for most VBR files).
      final xingFrames = _mp3XingFrames(buf);
      if (xingFrames != null && xingFrames.$2 > 0 && xingFrames.$3 > 0) {
        return xingFrames.$1 * xingFrames.$2 * 1000 ~/ xingFrames.$3;
      }

      // 2) Sample first frames to detect CBR vs VBR.
      final sample = _mp3SampleFrames(buf, maxFrames: 30);
      if (sample.isEmpty) return null;
      final first = sample.first;
      final allSame = sample.every((s) =>
          s.$1 == first.$1 && s.$2 == first.$2 && s.$3 == first.$3);
      if (allSame && sample.length >= 5) {
        // CBR: estimate from average frame length — far more stable
        // than a single first-frame bitrate (quiet intros mislead it).
        int totalLen = 0;
        for (final s in sample) {
          totalLen += s.$4;
        }
        final avgLen = totalLen ~/ sample.length;
        if (avgLen > 0) {
          final audioBytes = audioEnd - audioStart;
          final estFrames = audioBytes ~/ avgLen;
          if (estFrames > 0) {
            return estFrames * first.$2 * 1000 ~/ first.$3;
          }
        }
        // Fallback to bitrate formula.
        final audioBytes = audioEnd - audioStart;
        if (first.$1 > 0 && audioBytes > 0) {
          return audioBytes * 8 * 1000 ~/ (first.$1 * 1000);
        }
      }

      // 3) VBR without Xing: full frame walk counting samples.
      // Accurate and still fast (header seeks only, no decode).
      return await _mp3WalkCount(raf, audioStart, audioEnd);
    } finally {
      await raf.close();
    }
  }

  /// Returns (frames, samplesPerFrame, sampleRate) from Xing/Info/VBRI.
  static (int, int, int)? _mp3XingFrames(List<int> buf) {
    for (var i = 0; i + 4 < buf.length && i < 64 * 1024; i++) {
      if (buf[i] != 0xFF || (buf[i + 1] & 0xE0) != 0xE0) continue;
      final parsed = _mp3ParseHeader(buf, i);
      if (parsed == null) continue;
      final (bitrate, spf, sr, ver, channels, frameLen) = parsed;
      final isMpeg1 = ver == 0;
      final xingOff = i +
          4 +
          (isMpeg1 ? (channels == 1 ? 17 : 32) : (channels == 1 ? 9 : 17));
      if (xingOff + 12 < buf.length) {
        final magic = String.fromCharCodes(buf.sublist(xingOff, xingOff + 4));
        if (magic == 'Xing' || magic == 'Info') {
          final flags = (buf[xingOff + 4] << 24) |
              (buf[xingOff + 5] << 16) |
              (buf[xingOff + 6] << 8) |
              buf[xingOff + 7];
          if ((flags & 0x1) != 0) {
            final frames = (buf[xingOff + 8] << 24) |
                (buf[xingOff + 9] << 16) |
                (buf[xingOff + 10] << 8) |
                buf[xingOff + 11];
            if (frames > 0 && sr > 0) return (frames, spf, sr);
          }
          return null; // Xing without frames flag — fall through to walk
        }
      }
      // VBRI after 32 bytes of first frame.
      final vOff = i + 4 + 32;
      if (vOff + 18 < buf.length &&
          buf[vOff] == 0x56 &&
          buf[vOff + 1] == 0x42 &&
          buf[vOff + 2] == 0x52 &&
          buf[vOff + 3] == 0x49) {
        final frames = (buf[vOff + 14] << 24) |
            (buf[vOff + 15] << 16) |
            (buf[vOff + 16] << 8) |
            buf[vOff + 17];
        if (frames > 0 && sr > 0) return (frames, spf, sr);
      }
      break; // only first valid frame carries Xing
    }
    return null;
  }

  /// Parse one MPEG header at [i]: returns
  /// (bitrateKbps, samplesPerFrame, sampleRate, ver, channels, frameLen).
  static (int, int, int, int, int, int)? _mp3ParseHeader(
      List<int> buf, int i) {
    if (i + 4 > buf.length) return null;
    if (buf[i] != 0xFF || (buf[i + 1] & 0xE0) != 0xE0) return null;
    final verId = (buf[i + 1] >> 3) & 0x03;
    final layerId = (buf[i + 1] >> 1) & 0x03;
    final brIdx = (buf[i + 2] >> 4) & 0x0F;
    final srIdx = (buf[i + 2] >> 2) & 0x03;
    final pad = (buf[i + 2] >> 1) & 0x01;
    if (verId == 1 || layerId == 0 || brIdx == 0 || brIdx == 15 || srIdx == 3) {
      return null;
    }
    final ver = verId == 3 ? 0 : (verId == 2 ? 1 : 2);
    final sr = _mp3SampleRates[ver][srIdx];
    int table;
    if (ver == 0) {
      table = layerId == 3 ? 0 : (layerId == 2 ? 1 : 2);
    } else {
      table = layerId == 3 ? 3 : 4;
    }
    final bitrate = _mp3Bitrates[table][brIdx];
    final channels = ((buf[i + 3] >> 6) & 0x03) == 3 ? 1 : 2;
    int spf;
    int frameLen;
    if (layerId == 3) {
      // Layer I
      spf = 384;
      frameLen = ((12 * bitrate * 1000 ~/ sr) + pad) * 4;
    } else if (layerId == 2) {
      // Layer II
      spf = 1152;
      frameLen = (144 * bitrate * 1000 ~/ sr) + pad;
    } else {
      // Layer III
      if (ver == 0) {
        spf = 1152;
        frameLen = (144 * bitrate * 1000 ~/ sr) + pad;
      } else {
        spf = 576;
        frameLen = (72 * bitrate * 1000 ~/ sr) + pad;
      }
    }
    if (frameLen <= 0 || frameLen > 4000) return null;
    return (bitrate, spf, sr, ver, channels, frameLen);
  }

  /// Sample consecutive valid frames in [buf]:
  /// list of (bitrate, spf, sr, frameLen).
  static List<(int, int, int, int)> _mp3SampleFrames(List<int> buf,
      {int maxFrames = 30}) {
    final out = <(int, int, int, int)>[];
    var i = 0;
    // Find first sync.
    while (i + 4 < buf.length && out.isEmpty) {
      if (buf[i] == 0xFF && (buf[i + 1] & 0xE0) == 0xE0) {
        final p = _mp3ParseHeader(buf, i);
        if (p != null) {
          out.add((p.$1, p.$2, p.$3, p.$6));
          i += p.$6;
          break;
        }
      }
      i++;
    }
    while (i + 4 < buf.length && out.length < maxFrames) {
      final p = _mp3ParseHeader(buf, i);
      if (p == null) {
        // Resync: scan forward for next sync (tolerates 1 garbage byte).
        i++;
        var found = false;
        while (i + 4 < buf.length && i < buf.length) {
          if (buf[i] == 0xFF && (buf[i + 1] & 0xE0) == 0xE0) {
            final q = _mp3ParseHeader(buf, i);
            if (q != null) {
              found = true;
              break;
            }
          }
          i++;
          if (i > buf.length - 8) break;
        }
        if (!found) break;
        continue;
      }
      out.add((p.$1, p.$2, p.$3, p.$6));
      i += p.$6;
    }
    return out;
  }

  /// Full VBR walk with buffered reads — counts every frame's samples.
  static Future<int?> _mp3WalkCount(
      RandomAccessFile raf, int start, int end) async {
    const chunk = 256 * 1024;
    var pos = start;
    var totalSamples = 0;
    var sampleRate = 0;
    var frames = 0;
    List<int> carry = [];
    while (pos < end && frames < 60000) {
      final toRead = (end - pos) < chunk ? (end - pos) : chunk;
      await raf.setPosition(pos);
      final data = await raf.read(toRead);
      if (data.isEmpty) break;
      final buf = carry.isEmpty ? data : [...carry, ...data];
      var i = 0;
      // Align to first sync in this window (except continuation).
      if (carry.isEmpty) {
        var synced = false;
        while (i + 4 < buf.length) {
          if (buf[i] == 0xFF && (buf[i + 1] & 0xE0) == 0xE0) {
            if (_mp3ParseHeader(buf, i) != null) {
              synced = true;
              break;
            }
          }
          i++;
        }
        if (!synced) {
          pos += toRead;
          carry = [];
          continue;
        }
        pos += i; // account skipped garbage
      }
      final windowStart = pos;
      while (i + 4 <= buf.length && frames < 60000) {
        final p = _mp3ParseHeader(buf, i);
        if (p == null) break;
        totalSamples += p.$2;
        sampleRate = p.$3;
        frames++;
        i += p.$6;
      }
      final consumed = i;
      pos = windowStart + consumed;
      // Keep unparsed tail for next chunk.
      if (i < buf.length) {
        carry = buf.sublist(i);
        // Avoid infinite loop on garbage: if we made no progress, skip ahead.
        if (consumed == 0) {
          pos = windowStart + buf.length;
          carry = [];
        }
      } else {
        carry = [];
      }
      if (data.length < chunk) break;
    }
    if (frames > 0 && sampleRate > 0 && totalSamples > 0) {
      return totalSamples * 1000 ~/ sampleRate;
    }
    return null;
  }

  // ─── Raw AAC ADTS: sample first frames, extrapolate ───
  static Future<int?> _aacAdts(String path) async {
    final f = File(path);
    final fileSize = await f.length();
    final raf = await f.open(mode: FileMode.read);
    try {
      final buf = await raf.read(64 * 1024);
      const srTable = [
        96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
        16000, 12000, 11025, 8000, 7350
      ];
      int frames = 0;
      int totalLen = 0;
      int sr = 44100;
      var i = 0;
      while (i + 7 < buf.length && frames < 32) {
        if (buf[i] == 0xFF && (buf[i + 1] & 0xF0) == 0xF0) {
          final srIdx = (buf[i + 2] >> 2) & 0x0F;
          if (srIdx < srTable.length) sr = srTable[srIdx];
          final flen = ((buf[i + 3] & 0x03) << 11) |
              (buf[i + 4] << 3) |
              ((buf[i + 5] >> 5) & 0x07);
          if (flen < 7 || i + flen > buf.length + 1024) {
            i++;
            continue;
          }
          frames++;
          totalLen += flen;
          i += flen;
        } else {
          i++;
        }
      }
      if (frames > 0 && totalLen > 0) {
        final avg = totalLen ~/ frames;
        final totalFrames = fileSize ~/ avg;
        return totalFrames * 1024 * 1000 ~/ sr;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  // ─── WMA/ASF: File Properties play duration (100ns units) ───
  static Future<int?> _wma(String path) async {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      final head = await raf.read(64 * 1024);
      // File Properties GUID: A1 DC AB 8C 47 A9 CF 11 8E 44 00 C0 0C 20 53 65
      const guid = [0xA1, 0xDC, 0xAB, 0x8C, 0x47, 0xA9, 0xCF, 0x11,
          0x8E, 0x44, 0x00, 0xC0, 0x0C, 0x20, 0x53, 0x65];
      for (var i = 0; i + 16 + 8 + 104 < head.length; i++) {
        var match = true;
        for (var g = 0; g < 16; g++) {
          if (head[i + g] != guid[g]) {
            match = false;
            break;
          }
        }
        if (!match) continue;
        // Object size 8 LE at +16, then data; play duration at data+40 (8 LE)
        final dOff = i + 24 + 40;
        int dur100ns = 0;
        for (var b = 7; b >= 0; b--) {
          dur100ns = (dur100ns << 8) | head[dOff + b];
        }
        if (dur100ns > 0) return dur100ns ~/ 10000;
        return null;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Keep result small + safe for UI.
  static int? sanitize(int? ms) {
    if (ms == null || ms <= 0 || ms > 24 * 3600 * 1000) return null;
    return ms;
  }
}
