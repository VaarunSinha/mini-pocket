import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../utils.dart';

/// On-device transcription using sherpa_onnx Whisper tiny.en from assets.
class TranscriptionService {
  Future<void>? _init;
  sherpa_onnx.OfflineRecognizer? _recognizer;

  static const String _encoderAsset = 'assets/tiny.en-encoder.int8.onnx';
  static const String _decoderAsset = 'assets/tiny.en-decoder.int8.onnx';
  static const String _tokensAsset = 'assets/tiny.en-tokens.txt';
  static const int _sampleRate = 16000;

  Future<void> _loadRecognizer() async {
    sherpa_onnx.initBindings();

    final encoderPath = await copyAssetToSupport(_encoderAsset);
    final decoderPath = await copyAssetToSupport(_decoderAsset);
    final tokensPath = await copyAssetToSupport(_tokensAsset);

    final config = sherpa_onnx.OfflineRecognizerConfig(
      feat: const sherpa_onnx.FeatureConfig(
        sampleRate: _sampleRate,
        featureDim: 80,
      ),
      model: sherpa_onnx.OfflineModelConfig(
        whisper: sherpa_onnx.OfflineWhisperModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
          language: 'en',
          task: 'transcribe',
        ),
        tokens: tokensPath,
      ),
    );

    _recognizer = sherpa_onnx.OfflineRecognizer(config);
  }

  /// Transcribe audio file to text. Expects raw PCM 16-bit mono 16 kHz (.pcm).
  Future<String> transcribe(String audioFilePath) async {
    _init ??= _loadRecognizer();
    await _init;
    final recognizer = _recognizer;
    if (recognizer == null) return _fallback();

    try {
      final file = File(audioFilePath);
      if (!await file.exists()) return _fallback();
      final bytes = await file.readAsBytes();
      if (bytes.length < 2) return _fallback();

      final samples = _pcm16ToFloat32(bytes);

      sherpa_onnx.OfflineStream? stream;
      try {
        stream = recognizer.createStream();
        stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        final text = result.text.trim();
        return text.isEmpty ? _fallback() : text;
      } finally {
        stream?.free();
      }
    } catch (e) {
      debugPrint('TranscriptionService error: $e');
      return _fallback();
    }
  }

  static Float32List _pcm16ToFloat32(List<int> bytes) {
    final out = Float32List(bytes.length ~/ 2);
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    for (var i = 0; i < bytes.length; i += 2) {
      out[i ~/ 2] = data.getInt16(i, Endian.little) / 32768.0;
    }
    return out;
  }

  static String _fallback() =>
      'Recording at ${DateTime.now().toIso8601String()}';
}
