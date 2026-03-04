import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import 'note_storage.dart';
import 'transcription_service.dart';

/// Records audio, transcribes, and saves as a local note. No auto-push.
class RecordingService {
  RecordingService({
    NoteStorage? storage,
    TranscriptionService? transcription,
  })  : _storage = storage ?? NoteStorage(),
        _transcription = transcription ?? TranscriptionService();

  final NoteStorage _storage;
  final TranscriptionService _transcription;
  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  String? _currentPath;

  /// Start recording. Returns path where audio will be saved.
  /// Records PCM 16-bit mono 16 kHz for sherpa_onnx Whisper.
  Future<String> startRecording() async {
    if (_isRecording) throw StateError('Already recording');
    final dir = await getTemporaryDirectory();
    _currentPath = '${dir.path}/${_uuid.v4()}.pcm';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _currentPath!,
    );
    _isRecording = true;
    return _currentPath!;
  }

  /// Stop recording and return the audio file path. Call [transcribeAndSave] in the background.
  Future<String> stopRecording() async {
    if (!_isRecording || _currentPath == null) throw StateError('Not recording');
    await _recorder.stop();
    _isRecording = false;
    final path = _currentPath!;
    _currentPath = null;
    return path;
  }

  /// Transcribe file, save note, delete temp file. Returns the saved note (with id).
  Future<Note> transcribeAndSave(String audioPath) async {
    final device = await _storage.getOrCreateDevice();
    final deviceId = device.id ?? 'local';
    final text = await _transcription.transcribe(audioPath);

    final note = Note(
      deviceId: deviceId,
      content: text,
      transcription: text,
      createdAt: DateTime.now().toUtc(),
    );
    final saved = await _storage.addNote(note);

    try {
      await File(audioPath).delete();
    } catch (_) {}

    return saved;
  }
}
