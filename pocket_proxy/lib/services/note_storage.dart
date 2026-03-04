import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/device.dart';
import '../models/note.dart';

/// Saves and loads notes locally. Does not push to backend.
class NoteStorage {
  NoteStorage() : _uuid = const Uuid();

  final Uuid _uuid;
  static const String _notesFileName = 'pocket_notes.json';
  static const String _deviceFileName = 'pocket_device.json';

  Future<File> _notesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_notesFileName');
  }

  Future<File> _deviceFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_deviceFileName');
  }

  /// Load or create this device (single device per app).
  Future<Device> getOrCreateDevice() async {
    final file = await _deviceFile();
    if (await file.exists()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return Device.fromJson(json);
    }
    final device = Device(
      id: _uuid.v4(),
      name: 'Mini Pocket',
      createdAt: DateTime.now().toUtc(),
    );
    await file.writeAsString(jsonEncode(device.toJson()));
    return device;
  }

  /// Load all notes for this device.
  Future<List<Note>> loadNotes(String deviceId) async {
    final file = await _notesFile();
    if (!await file.exists()) return [];
    final list = jsonDecode(await file.readAsString()) as List<dynamic>;
    return list
        .map((e) => Note.fromJson(e as Map<String, dynamic>))
        .where((n) => n.deviceId == deviceId)
        .toList()
      ..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
  }

  /// Save a new or updated note. Returns the note with id and timestamps set.
  Future<Note> saveNote(Note note) async {
    final file = await _notesFile();
    List<Map<String, dynamic>> list = [];
    if (await file.exists()) {
      list = (jsonDecode(await file.readAsString()) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    }
    final id = note.id ?? _uuid.v4();
    final now = DateTime.now().toUtc();
    final toSave = Note(
      id: id,
      deviceId: note.deviceId,
      content: note.content,
      transcription: note.transcription,
      todoList: note.todoList,
      summary: note.summary,
      reminders: note.reminders,
      createdAt: note.createdAt ?? now,
      updatedAt: now,
      syncedToDesktopAt: note.syncedToDesktopAt,
    );
    list.removeWhere((e) => e['id'] == id);
    list.add(toSave.toJson());
    await file.writeAsString(jsonEncode(list));
    return toSave;
  }

  /// Mark these notes as synced to desktop (called when desktop pulls GET /notes).
  Future<void> markNotesSyncedToDesktop(List<Note> notes) async {
    final now = DateTime.now().toUtc();
    for (final note in notes) {
      if (note.id != null && !note.id!.startsWith('transcribing-')) {
        await saveNote(note.copyWith(syncedToDesktopAt: now));
      }
    }
  }

  /// Add a new note (generates id and timestamps). Returns the saved note.
  Future<Note> addNote(Note note) async {
    return saveNote(note);
  }

  /// Remove a note by id.
  Future<void> deleteNote(Note note) async {
    final id = note.id;
    if (id == null) return;
    final file = await _notesFile();
    if (!await file.exists()) return;
    final list = (jsonDecode(await file.readAsString()) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['id'] == id);
    await file.writeAsString(jsonEncode(list));
  }
}
