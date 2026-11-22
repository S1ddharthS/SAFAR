import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'trip_channel.dart';

class TripLiveState {
  const TripLiveState({this.status = RealtimeStatus.idle, this.lastEvent});

  final RealtimeStatus status;
  final TripEvent? lastEvent;

  bool get live => status == RealtimeStatus.live;
  bool get reconnecting => status == RealtimeStatus.reconnecting;
}

/// Owns the trip socket while any trip screen watches it, and maps pushed
/// events onto Riverpod invalidations so every open screen reconciles.
class TripRealtimeController extends StateNotifier<TripLiveState> {
  TripRealtimeController(this._ref, this.tripId)
    : super(const TripLiveState()) {
    final channel = TripChannel(
      client: _ref.read(apiClientProvider),
      tripId: tripId,
    );
    _channel = channel;
    channel.onStatus = (status) {
      if (!mounted) return;
      state = TripLiveState(status: status, lastEvent: state.lastEvent);
    };
    channel.onCatchUp = _reconcile;
    _events = channel.events.listen(_onEvent);
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _paused = true;
        channel.stop();
      },
      onResume: _resume,
    );
    channel.start();
  }

  final Ref _ref;
  final String tripId;

  late final TripChannel _channel;
  late final StreamSubscription<TripEvent> _events;
  late final AppLifecycleListener _lifecycle;
  bool _paused = false;

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _channel.start();
  }

  void _onEvent(TripEvent event) {
    if (!mounted) return;
    state = TripLiveState(status: _channel.status, lastEvent: event);
    _refreshFor(event.event);
  }

  void _refreshFor(String event) {
    final ref = _ref;
    if (event == 'itinerary.updated' || event.startsWith('proposal.')) {
      ref.invalidate(itineraryProvider(tripId));
      ref.invalidate(proposalsProvider(tripId));
      ref.invalidate(engineProvider(tripId));
      ref.invalidate(tripProvider(tripId));
    } else if (event == 'engine.updated') {
      ref.invalidate(engineProvider(tripId));
      ref.invalidate(itineraryProvider(tripId));
    } else if (event == 'expenses.updated') {
      ref.invalidate(expensesProvider(tripId));
      ref.invalidate(balancesProvider(tripId));
    } else if (event == 'pulse.updated') {
      ref.invalidate(pulseProvider(tripId));
    } else if (event.startsWith('member.')) {
      ref.invalidate(membersProvider(tripId));
      ref.invalidate(tripProvider(tripId));
      ref.invalidate(tripsProvider);
      ref.invalidate(tasksProvider(tripId));
      ref.invalidate(taskSummaryProvider(tripId));
    } else if (event == 'trip.updated' || event == 'trip.deleted') {
      ref.invalidate(tripProvider(tripId));
      ref.invalidate(tripsProvider);
    } else {
      ref.invalidate(tripProvider(tripId));
      ref.invalidate(tripsProvider);
    }
  }

  /// After a reconnect the socket only delivers new frames, so pull the
  /// workspace back in line once instead of trusting a possibly stale cache.
  void _reconcile() {
    final ref = _ref;
    ref.invalidate(tripProvider(tripId));
    ref.invalidate(tripsProvider);
    ref.invalidate(membersProvider(tripId));
    ref.invalidate(itineraryProvider(tripId));
    ref.invalidate(proposalsProvider(tripId));
    ref.invalidate(engineProvider(tripId));
    ref.invalidate(expensesProvider(tripId));
    ref.invalidate(balancesProvider(tripId));
    ref.invalidate(pulseProvider(tripId));
    ref.invalidate(tasksProvider(tripId));
    ref.invalidate(taskSummaryProvider(tripId));
    ref.invalidate(pactProvider(tripId));
    ref.invalidate(branchesProvider(tripId));
    ref.invalidate(missionsProvider(tripId));
    ref.invalidate(watchesProvider(tripId));
    ref.invalidate(memoriesProvider(tripId));
    ref.invalidate(studioProvider(tripId));
    ref.invalidate(offlineSnapshotProvider(tripId));
    ref.invalidate(syncQueueProvider(tripId));
    ref.invalidate(companionLinksProvider(tripId));
    ref.invalidate(groundRequestsProvider(tripId));
    ref.invalidate(inspirationsProvider(tripId));
    ref.invalidate(notificationsProvider);
  }

  void reconnectNow() {
    _paused = false;
    _channel.stop();
    _channel.start();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _events.cancel();
    _channel.dispose();
    super.dispose();
  }
}

final tripRealtimeProvider = StateNotifierProvider.autoDispose
    .family<TripRealtimeController, TripLiveState, String>(
      (ref, tripId) => TripRealtimeController(ref, tripId),
    );
