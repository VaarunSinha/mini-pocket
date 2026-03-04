import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'discovery_broadcaster.dart';
import 'note_storage.dart';

/// Local HTTP server so desktop (Tauri) can discover and pull notes via pairing code.
class LocalServer {
  LocalServer({NoteStorage? storage}) : _storage = storage ?? NoteStorage();

  final NoteStorage _storage;
  HttpServer? _server;
  final DiscoveryBroadcaster _broadcaster = DiscoveryBroadcaster();
  String _pairingCode = '';
  static const int defaultPort = 8765;

  String get pairingCode => _pairingCode;
  bool get isRunning => _server != null;

  /// Generate a 6-digit pairing code.
  static String _generatePairingCode() {
    final r = DateTime.now().millisecondsSinceEpoch % 1000000;
    return r.toString().padLeft(6, '0');
  }

  /// Start server on [port]. Returns the pairing code.
  Future<String> start({int port = defaultPort}) async {
    if (_server != null) return _pairingCode;
    _pairingCode = _generatePairingCode();

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    final localIp = await DiscoveryBroadcaster.getLocalIpV4();
    final host = localIp ?? 'localhost';
    final url = 'http://$host:$port';
    final device = await _storage.getOrCreateDevice();
    await _broadcaster.start(
      url: url,
      pairingCode: _pairingCode,
      name: device.name,
    );
    return _pairingCode;
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    // Pairing: client sends code in header or query to confirm.
    final auth =
        request.headers['x-pairing-code'] ??
        request.url.queryParameters['code'] ??
        '';
    if (auth != _pairingCode) {
      return shelf.Response(401, body: 'Invalid or missing pairing code');
    }

    if (request.method == 'GET' && request.url.path == 'notes') {
      return _getNotes();
    }
    if (request.method == 'GET' && request.url.path == 'device') {
      return _getDevice();
    }
    if (request.method == 'GET' && request.url.path.isEmpty ||
        request.url.path == '/') {
      return shelf.Response.ok(
        jsonEncode({
          'name': 'Mini Pocket',
          'pairing_required': true,
          'endpoints': ['/device', '/notes'],
        }),
      );
    }

    return shelf.Response.notFound('Not found');
  }

  Future<shelf.Response> _getDevice() async {
    final device = await _storage.getOrCreateDevice();
    return shelf.Response.ok(
      jsonEncode(device.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _getNotes() async {
    final device = await _storage.getOrCreateDevice();
    final deviceId = device.id ?? 'local';
    final notes = await _storage.loadNotes(deviceId);
    await _storage.markNotesSyncedToDesktop(notes);
    final list = notes.map((n) => n.toJson()).toList();
    return shelf.Response.ok(
      jsonEncode(list),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<void> stop() async {
    _broadcaster.stop();
    await _server?.close(force: true);
    _server = null;
  }
}
