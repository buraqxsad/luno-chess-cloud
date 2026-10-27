import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const sampleRate = 22050;

void main() {
  final directory = Directory('assets/audio')..createSync(recursive: true);
  _write(directory, 'menu_loop.wav', _music(seconds: 12, battle: false));
  _write(directory, 'battle_loop.wav', _music(seconds: 10, battle: true));
  _write(directory, 'ui_click.wav', _effect(.09, (t) => _tone(t, 720, .34)));
  _write(directory, 'move.wav', _effect(.16, (t) => _tone(t, 285, .48)));
  _write(
    directory,
    'capture.wav',
    _effect(.22, (t) => _tone(t, 170, .54) + _tone(t, 430, .16)),
  );
  _write(
    directory,
    'victory.wav',
    _effect(1.35, (t) {
      final notes = [523.25, 659.25, 783.99, 1046.5];
      final index = math.min(notes.length - 1, (t / .23).floor());
      return _tone(t, notes[index], .42, decay: .42);
    }),
  );
  _write(
    directory,
    'defeat.wav',
    _effect(1.05, (t) {
      final notes = [392.0, 329.63, 261.63];
      final index = math.min(notes.length - 1, (t / .32).floor());
      return _tone(t, notes[index], .32, decay: .6);
    }),
  );
}

void _write(Directory directory, String name, Float64List samples) {
  File('${directory.path}/$name').writeAsBytesSync(_wav(samples));
}

Float64List _effect(double seconds, double Function(double seconds) voice) {
  final samples = Float64List((seconds * sampleRate).round());
  for (var index = 0; index < samples.length; index++) {
    final time = index / sampleRate;
    final fade = math.min(1, time * 85) * math.min(1, (seconds - time) * 14);
    samples[index] = (voice(time) * fade).clamp(-.95, .95).toDouble();
  }
  return samples;
}

Float64List _music({required int seconds, required bool battle}) {
  final samples = Float64List(seconds * sampleRate);
  final bpm = battle ? 102.0 : 78.0;
  final beat = 60 / bpm;
  final notes =
      battle
          ? [220.0, 261.63, 293.66, 349.23, 293.66, 261.63, 196.0, 220.0]
          : [261.63, 329.63, 392.0, 493.88, 392.0, 329.63, 293.66, 261.63];
  for (var index = 0; index < samples.length; index++) {
    final time = index / sampleRate;
    final step = (time / beat).floor();
    final local = time - step * beat;
    final note = notes[step % notes.length];
    final envelope = math.exp(-local * (battle ? 5.5 : 4.1));
    final lead = math.sin(2 * math.pi * note * time) * envelope;
    final fifth = math.sin(2 * math.pi * note * 1.5 * time) * envelope * .28;
    final bass =
        math.sin(2 * math.pi * (battle ? note / 2 : note / 4) * time) *
        (battle ? .16 : .10);
    final pulse =
        battle
            ? math.sin(2 * math.pi * 2.2 * time) * math.exp(-local * 15) * .12
            : 0.0;
    final value = (lead * (battle ? .13 : .10)) + fifth * .055 + bass + pulse;
    samples[index] = value.clamp(-.8, .8).toDouble();
  }
  return samples;
}

double _tone(
  double time,
  double frequency,
  double amplitude, {
  double decay = 9,
}) {
  return math.sin(2 * math.pi * frequency * time) *
      amplitude *
      math.exp(-time * decay);
}

Uint8List _wav(Float64List samples) {
  final dataLength = samples.length * 2;
  final bytes = BytesBuilder();
  void ascii(String value) => bytes.add(Uint8List.fromList(value.codeUnits));
  void u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  ascii('RIFF');
  u32(36 + dataLength);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  ascii('data');
  u32(dataLength);
  final pcm = ByteData(dataLength);
  for (var index = 0; index < samples.length; index++) {
    pcm.setInt16(index * 2, (samples[index] * 32767).round(), Endian.little);
  }
  bytes.add(pcm.buffer.asUint8List());
  return bytes.takeBytes();
}
