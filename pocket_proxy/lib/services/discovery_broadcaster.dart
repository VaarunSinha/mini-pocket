import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP broadcast port for discovery (desktop listens here).
const int kDiscoveryPort = 8766;

/// Sends periodic UDP broadcasts so the desktop app can discover this device.
class DiscoveryBroadcaster {
  RawDatagramSocket? _socket;
  Timer? _timer;
  static const Duration _interval = Duration(seconds: 2);

  /// Resolve a local IPv4 address (non-loopback) for the HTTP server URL.
  static Future<String?> getLocalIpV4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Subnet broadcast from a.b.c.d (e.g. 192.168.1.255 for 192.168.1.x).
  static String? _subnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    try {
      final last = int.tryParse(parts[3]);
      if (last == null) return null;
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    } catch (_) {
      return null;
    }
  }

  /// Start broadcasting [url], [pairingCode], and [name] every [_interval].
  Future<void> start({
    required String url,
    required String pairingCode,
    String name = 'Mini Pocket',
  }) async {
    stop();
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;

      // Do not broadcast pairing code; user enters it on desktop and it is validated on connect.
      final payload = utf8.encode(jsonEncode({'url': url, 'name': name}));

      // Parse host from url (e.g. http://192.168.1.5:8765 -> 192.168.1.5)
      String? subnetBroadcast;
      try {
        final uri = Uri.parse(url);
        if (uri.host.isNotEmpty && uri.host != 'localhost') {
          subnetBroadcast = _subnetBroadcast(uri.host);
        }
      } catch (_) {}

      void send() {
        try {
          _socket?.send(
            payload,
            InternetAddress('255.255.255.255'),
            kDiscoveryPort,
          );
          if (subnetBroadcast != null) {
            _socket?.send(
              payload,
              InternetAddress(subnetBroadcast),
              kDiscoveryPort,
            );
          }
        } catch (_) {}
      }

      send();
      _timer = Timer.periodic(_interval, (_) => send());
    } catch (_) {
      _socket?.close();
      _socket = null;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
