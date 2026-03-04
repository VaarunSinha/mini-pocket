import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models/note.dart';
import 'services/local_server.dart';
import 'services/note_storage.dart';
import 'services/recording_service.dart';

void main() {
  runApp(const PocketProxyApp());
}

class PocketProxyApp extends StatelessWidget {
  const PocketProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mini Pocket',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final NoteStorage _storage = NoteStorage();
  late final RecordingService _recording = RecordingService(storage: _storage);
  late final LocalServer _server = LocalServer(storage: _storage);

  List<Note> _notes = [];
  final Set<String> _transcribingIds = {};
  bool _serverRunning = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final device = await _storage.getOrCreateDevice();
    final notes = await _storage.loadNotes(device.id ?? 'local');
    if (mounted) {
      setState(() => _notes = notes);
    }
  }

  Future<void> _toggleServer() async {
    setState(() => _error = '');
    try {
      if (_serverRunning) {
        await _server.stop();
        setState(() => _serverRunning = false);
      } else {
        await _server.start();
        setState(() => _serverRunning = true);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleRecord() async {
    setState(() => _error = '');
    try {
      if (_recording.isRecording) {
        final path = await _recording.stopRecording();
        final device = await _storage.getOrCreateDevice();
        final deviceId = device.id ?? 'local';
        final placeholderId = 'transcribing-${const Uuid().v4()}';
        final placeholder = Note(
          id: placeholderId,
          deviceId: deviceId,
          content: 'Transcribing...',
          createdAt: DateTime.now().toUtc(),
        );
        if (mounted) {
          setState(() {
            _transcribingIds.add(placeholderId);
            _notes.insert(0, placeholder);
          });
        }
        _recording
            .transcribeAndSave(path)
            .then((note) {
              if (!mounted) return;
              setState(() {
                final i = _notes.indexWhere((n) => n.id == placeholderId);
                if (i >= 0) {
                  _notes[i] = note;
                }
                _transcribingIds.remove(placeholderId);
              });
            })
            .catchError((e) {
              if (mounted) {
                setState(() {
                  final i = _notes.indexWhere((n) => n.id == placeholderId);
                  if (i >= 0)
                    _notes[i] = placeholder.copyWith(
                      content: 'Transcription failed: $e',
                    );
                  _transcribingIds.remove(placeholderId);
                });
              }
            });
      } else {
        await _recording.startRecording();
        setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini Pocket'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('Pairing'),
                _pairingCard(),
                const SizedBox(height: 24),
                _section('Record'),
                _recordCard(),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _section('Notes (${_notes.length})'),
                ..._notes.map((n) => _noteTile(n)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _pairingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: const Text('Local server'),
              subtitle: Text(_serverRunning ? 'Desktop can connect' : 'Off'),
              value: _serverRunning,
              onChanged: (_) => _toggleServer(),
            ),
            if (_serverRunning) ...[
              const SizedBox(height: 8),
              Text(
                'Pairing code: ${_server.pairingCode}',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Use this code in the desktop app to pull notes.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recordCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FilledButton.icon(
              onPressed: _toggleRecord,
              icon: Icon(_recording.isRecording ? Icons.stop : Icons.mic),
              label: Text(_recording.isRecording ? 'Stop & save' : 'Record'),
              style: FilledButton.styleFrom(
                backgroundColor: _recording.isRecording ? Colors.red : null,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteTile(Note note) {
    final isTranscribing =
        note.id != null && _transcribingIds.contains(note.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context)
            .push(
              MaterialPageRoute<void>(
                builder: (context) => NoteDetailScreen(
                  note: note,
                  formatDate: _formatDate,
                  storage: _storage,
                  onDeleted: () {
                    _notes.removeWhere((n) => n.id == note.id);
                    setState(() {});
                  },
                ),
              ),
            )
            .then((_) => setState(() {})),
        title: isTranscribing
            ? const Text('Transcribing...')
            : Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: isTranscribing
            ? const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              )
            : Row(
                children: [
                  if (note.createdAt != null)
                    Text(
                      _formatDate(note.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (note.isSyncedToDesktop) ...[
                    if (note.createdAt != null) const SizedBox(width: 8),
                    Icon(
                      Icons.cloud_done,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Synced',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
        trailing: isTranscribing
            ? const SizedBox(
                width: 48,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteNote(note),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
      ),
    );
  }

  Future<void> _deleteNote(Note note) async {
    if (note.id != null && _transcribingIds.contains(note.id)) return;
    await _storage.deleteNote(note);
    setState(() => _notes.removeWhere((n) => n.id == note.id));
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}/${d.year}';
  }
}

/// Full note detail: transcription, date, synced status, delete.
class NoteDetailScreen extends StatelessWidget {
  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.formatDate,
    required this.storage,
    required this.onDeleted,
  });

  final Note note;
  final String Function(DateTime) formatDate;
  final NoteStorage storage;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final isTranscribing = note.content == 'Transcribing...';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!isTranscribing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete note?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await storage.deleteNote(note);
                  onDeleted();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note.createdAt != null)
              Text(
                formatDate(note.createdAt!),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (note.isSyncedToDesktop) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.cloud_done,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Synced to desktop',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Transcription',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: isTranscribing
                    ? const Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 16),
                          Text('Transcribing...'),
                        ],
                      )
                    : SelectableText(
                        note.content,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
              ),
            ),
            if (note.transcription != null &&
                note.transcription != note.content) ...[
              const SizedBox(height: 16),
              Text(
                'Raw transcription',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    note.transcription!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
