import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// A lightweight in-memory synthesizer that generates WAV audio for
/// MIDI note numbers and plays it via [AudioPlayer].
///
/// Generates a triangle-wave with harmonics + ADSR envelope — good enough
/// for "tap to hear" feedback. Architecture is pluggable: swap [playMidi]
/// for a real SoundFont synth later by replacing the synthesis step.
class NotePlayer {
  static const _sampleRate = 44100;
  static const _durationSec = 1.0;
  static const _attackSec = 0.01;
  static const _decaySec = 0.08;
  static const _sustainLevel = 0.6;
  static const _releaseSec = 0.25;

  final AudioPlayer _player = AudioPlayer();

  /// Plays [midiNote] (e.g. 60 = C4) for 1 second.
  Future<void> playMidi(int midiNote) async {
    final freq = 440.0 * pow(2, (midiNote - 69) / 12);
    final wav = _generateWav(freq);
    await _player.play(BytesSource(wav));
  }

  /// Plays all [midiNotes] simultaneously (chord).
  Future<void> playChord(List<int> midiNotes) async {
    if (midiNotes.isEmpty) return;
    final freqs =
        midiNotes.map((n) => 440.0 * pow(2, (n - 69) / 12)).toList();
    final wav = _generateWavChord(freqs);
    await _player.play(BytesSource(wav));
  }

  /// Releases resources.
  Future<void> dispose() async => await _player.dispose();

  // ---- WAV generation ----

  static double _envelope(int sample, int totalSamples) {
    final attackSamples = (_attackSec * _sampleRate).toInt();
    final decaySamples = (_decaySec * _sampleRate).toInt();
    final releaseSamples = (_releaseSec * _sampleRate).toInt();
    final sustainSamples = totalSamples - attackSamples - decaySamples - releaseSamples;

    if (sample < attackSamples) {
      return sample / attackSamples;
    } else if (sample < attackSamples + decaySamples) {
      final t = (sample - attackSamples) / decaySamples;
      return 1.0 - (1.0 - _sustainLevel) * t;
    } else if (sample < attackSamples + decaySamples + sustainSamples) {
      return _sustainLevel;
    } else if (sample < totalSamples) {
      final t = (sample - attackSamples - decaySamples - sustainSamples) /
          releaseSamples;
      return _sustainLevel * (1.0 - t);
    }
    return 0;
  }

  static double _triangle(double phase) {
    // Triangle wave: 2/π * arcsin(sin(2πt))
    final s = sin(phase);
    return (2 / pi) * asin(s);
  }

  Uint8List _generateWav(double freq) {
    final totalSamples = (_durationSec * _sampleRate).toInt();
    final data = Uint8List(totalSamples * 2); // 16-bit mono

    for (var i = 0; i < totalSamples; i++) {
      final t = i / _sampleRate;
      final phase = 2 * pi * freq * t;
      // Fundamental + 2nd harmonic (softer) + 3rd (even softer)
      final sample = _triangle(phase) * 0.6 +
          _triangle(2 * phase) * 0.25 +
          _triangle(3 * phase) * 0.15;
      final env = _envelope(i, totalSamples);
      final value = (sample * env * 32767).toInt().clamp(-32768, 32767);
      data[i * 2] = (value & 0xFF);
      data[i * 2 + 1] = ((value >> 8) & 0xFF);
    }

    return _buildWavFile(data);
  }

  Uint8List _generateWavChord(List<double> freqs) {
    final totalSamples = (_durationSec * _sampleRate).toInt();
    final data = Uint8List(totalSamples * 2);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / _sampleRate;
      double sample = 0;
      for (final freq in freqs) {
        final phase = 2 * pi * freq * t;
        sample += _triangle(phase) * 0.6 +
            _triangle(2 * phase) * 0.25 +
            _triangle(3 * phase) * 0.15;
      }
      sample /= freqs.length; // normalize
      final env = _envelope(i, totalSamples);
      final value = (sample * env * 32767).toInt().clamp(-32768, 32767);
      data[i * 2] = (value & 0xFF);
      data[i * 2 + 1] = ((value >> 8) & 0xFF);
    }

    return _buildWavFile(data);
  }

  Uint8List _buildWavFile(Uint8List pcmData) {
    final header = Uint8List(44);
    final dataLen = pcmData.length;

    // RIFF header
    header[0] = 0x52; // R
    header[1] = 0x49; // I
    header[2] = 0x46; // F
    header[3] = 0x46; // F
    _writeUint32(header, 4, 36 + dataLen);
    header[8] = 0x57; // W
    header[9] = 0x41; // A
    header[10] = 0x56; // V
    header[11] = 0x45; // E

    // fmt chunk
    header[12] = 0x66; // f
    header[13] = 0x6D; // m
    header[14] = 0x74; // t
    header[15] = 0x20; // (space)
    _writeUint32(header, 16, 16); // chunk size
    _writeUint16(header, 20, 1); // PCM format
    _writeUint16(header, 22, 1); // mono
    _writeUint32(header, 24, _sampleRate);
    _writeUint32(header, 28, _sampleRate * 2); // byte rate
    _writeUint16(header, 32, 2); // block align
    _writeUint16(header, 34, 16); // bits per sample

    // data chunk
    header[36] = 0x64; // d
    header[37] = 0x61; // a
    header[38] = 0x74; // t
    header[39] = 0x61; // a
    _writeUint32(header, 40, dataLen);

    return Uint8List.fromList([...header, ...pcmData]);
  }

  static void _writeUint32(Uint8List buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
  }

  static void _writeUint16(Uint8List buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
  }
}
