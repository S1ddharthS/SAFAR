import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../services/diagnostics_service.dart';

enum RealtimeStatus { idle, connecting, live, reconnecting, closed }

/// A frame pushed on `/ws/trips/{trip_id}`. The backend envelope is
/// `{event, at, ...data}`; pings and the initial `connected` frame are
/// consumed inside [TripChannel].
class TripEvent {
  const TripEvent({required this.event, required this.at, required this.data});

  final String event;
  final String at;
  final Map<String, dynamic> data;

  /// Display name of whoever triggered the event, when the server sends one.
  String get actor {
    for (final key in const ['by', 'voter', 'display_name']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  static TripEvent? tryParse(Object? raw) {
    if (raw is! String) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final name = decoded['event'];
    if (name is! String || name.isEmpty) return null;
    return TripEvent(
      event: name,
      at: '${decoded['at'] ?? ''}',
      data: Map<String, dynamic>.from(decoded),
    );
  }
}

/// Converts the HTTP API origin into the socket URL for a trip.
String tripSocketUrl({
  required String apiBaseUrl,
  required String tripId,
  required String ticket,
}) {
  final trimmed = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final String base;
  if (trimmed.startsWith('https://')) {
    base = 'wss://${trimmed.substring(8)}';
  } else if (trimmed.startsWith('http://')) {
    base = 'ws://${trimmed.substring(7)}';
  } else if (trimmed.startsWith('wss://') || trimmed.startsWith('ws://')) {
    base = trimmed;
  } else {
    base = 'ws://$trimmed';
  }
  return '$base/ws/trips/${Uri.encodeComponent(tripId)}'
      '?token=${Uri.encodeComponent(ticket)}';
}

const realtimeBackoffSteps = <int>[1, 2, 4, 8, 15, 30];

Duration realtimeBackoff(int attempt) {
  final index = attempt < 0
      ? 0
      : (attempt >= realtimeBackoffSteps.length
            ? realtimeBackoffSteps.length - 1
            : attempt);
  return Duration(seconds: realtimeBackoffSteps[index]);
}

/// Session-bound socket for one trip workspace.
///
/// The WebSocket handshake cannot carry an Authorization header, so a
/// short-lived ticket is fetched over the authenticated HTTP client and passed
/// as a query parameter. The ticket is never logged.
class TripChannel {
  TripChannel({required this.client, required this.tripId});

  final ApiClient client;
  final String tripId;

  final _controller = StreamController<TripEvent>.broadcast();
  final List<String> _recent = [];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;
  bool _everLive = false;

  RealtimeStatus _status = RealtimeStatus.idle;
  RealtimeStatus get status => _status;

  void Function(RealtimeStatus status)? onStatus;
  void Function()? onCatchUp;

  Stream<TripEvent> get events => _controller.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _attempt = 0;
    await _connect();
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _retry = null;
    _teardown();
    _emit(RealtimeStatus.idle);
  }

  Future<void> _connect() async {
    if (!_running) return;
    _emit(_everLive ? RealtimeStatus.reconnecting : RealtimeStatus.connecting);
    final String ticket;
    try {
      final data = await client.post('/api/auth/ws-ticket');
      final value = data is Map ? data['ticket'] : null;
      if (value is! String || value.isEmpty) {
        _retryLater();
        return;
      }
      ticket = value;
    } on ApiException catch (error) {
      final status = error.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        // The session is gone or cannot issue a ticket; polling stays usable.
        _running = false;
        _emit(RealtimeStatus.closed);
        return;
      }
      _retryLater();
      return;
    } on Object {
      _retryLater();
      return;
    }
    if (!_running) return;
    try {
      final uri = Uri.parse(
        tripSocketUrl(
          apiBaseUrl: client.baseUrl,
          tripId: tripId,
          ticket: ticket,
        ),
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      if (!_running) {
        _teardown();
        return;
      }
      _subscription = channel.stream.listen(
        _onFrame,
        onDone: _dropped,
        onError: (Object _) => _dropped(),
        cancelOnError: true,
      );
      _attempt = 0;
      final reconnected = _everLive;
      _everLive = true;
      _emit(RealtimeStatus.live);
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        _send('ping');
      });
      if (reconnected) onCatchUp?.call();
    } on Object {
      _teardown();
      _retryLater();
    }
  }

  void _onFrame(dynamic raw) {
    final event = TripEvent.tryParse(raw);
    if (event == null) return;
    if (event.event == 'connected' || event.event == 'pong') return;
    final key = [
      event.event,
      event.at,
      event.data['proposal_id'],
      event.data['member_id'],
      event.data['voter'],
    ].join('|');
    if (_recent.contains(key)) return;
    _recent.add(key);
    if (_recent.length > 50) _recent.removeAt(0);
    if (!_controller.isClosed) _controller.add(event);
  }

  void _dropped() {
    if (!_running) return;
    _teardown();
    _retryLater();
  }

  void _retryLater() {
    if (!_running) return;
    _emit(_everLive ? RealtimeStatus.reconnecting : RealtimeStatus.connecting);
    final delay = realtimeBackoff(_attempt);
    _attempt += 1;
    _retry?.cancel();
    _retry = Timer(delay, _connect);
  }

  void _send(String message) {
    try {
      _channel?.sink.add(message);
    } on Object {
      // A failed heartbeat surfaces through onDone/onError instead.
    }
  }

  void _teardown() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    channel?.sink.close();
  }

  void _emit(RealtimeStatus status) {
    if (_status == status) return;
    _status = status;
    DiagnosticsService.instance.recordRealtime('status_change', status.name, tripId: tripId);
    onStatus?.call(status);
  }

  void dispose() {
    _running = false;
    _retry?.cancel();
    _teardown();
    _controller.close();
  }
}
