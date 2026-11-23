import '../models/invitation.dart';
import '../models/json.dart';
import '../models/monitoring.dart';
import '../models/planning.dart';
import '../models/trip.dart';
import '../network/api_client.dart';

class TripRepository {
  TripRepository(this._api);

  final ApiClient _api;

  Future<List<Trip>> list() async {
    final data = await _api.get('/api/trips');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Trip.fromJson);
  }

  Future<Trip> get(String tripId) async =>
      Trip.fromJson(jsonMap(await _api.get('/api/trips/$tripId')));

  Future<Trip> create({
    required String name,
    required String startDate,
    required String endDate,
    String? destinationId,
    String? destinationName,
    String? description,
    int groupSize = 4,
    double? budgetTotal,
    String currency = 'EUR',
    String tripType = 'group',
  }) async => Trip.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips',
        data: {
          'name': name,
          'start_date': startDate,
          'end_date': endDate,
          'destination_id': ?destinationId,
          'destination_name': ?destinationName,
          if (description != null && description.isNotEmpty)
            'description': description,
          'group_size': groupSize,
          'budget_total': ?budgetTotal,
          'currency': currency,
          'trip_type': tripType,
        },
      ),
    ),
  );

  Future<Trip> update(String tripId, Map<String, dynamic> changes) async =>
      Trip.fromJson(
        jsonMap(await _api.patch('/api/trips/$tripId', data: changes)),
      );

  Future<List<Member>> members(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/members');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Member.fromJson);
  }

  Future<void> updateMemberRole(
    String tripId,
    String memberId,
    String role,
  ) async {
    await _api.patch(
      '/api/trips/$tripId/members/$memberId',
      data: {'role': role},
    );
  }

  Future<void> removeMember(String tripId, String memberId) async {
    await _api.delete('/api/trips/$tripId/members/$memberId');
  }

  Future<List<TripInvitation>> invitations(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/invitations');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, TripInvitation.fromJson);
  }

  Future<TripInvitation> createInvitation(
    String tripId, {
    String? email,
    String role = 'member',
    String scope = 'full',
    int expiresInDays = 7,
  }) async => TripInvitation.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/invitations',
        data: {
          if (email != null && email.trim().isNotEmpty)
            'email': email.trim().toLowerCase(),
          'role': role,
          'scope': scope,
          'expires_in_days': expiresInDays,
        },
      ),
    ),
  );

  Future<void> revokeInvitation(String tripId, String invitationId) async {
    await _api.delete('/api/trips/$tripId/invitations/$invitationId');
  }

  Future<InvitationPreview> previewInvitation(String token) async =>
      InvitationPreview.fromJson(
        jsonMap(await _api.get('/api/invitations/$token')),
      );

  Future<Trip> acceptInvitation(String token) async => Trip.fromJson(
    jsonMap(await _api.post('/api/invitations/$token/accept')),
  );

  Future<Pact?> pact(String tripId) async {
    final data = jsonMap(await _api.get('/api/trips/$tripId/pact'));
    final pact = jsonMap(data['pact']);
    return pact.isEmpty ? null : Pact.fromJson(pact);
  }

  Future<Pact?> savePact(
    String tripId, {
    required List<String> mustDo,
    required List<String> flexible,
    List<String> exceptions = const [],
    Map<String, String> confirmedTimes = const {},
    Map<String, dynamic> individualLimits = const {},
  }) async {
    await _api.put(
      '/api/trips/$tripId/pact',
      data: {
        'must_do': mustDo,
        'flexible': flexible,
        'exceptions': exceptions,
        'confirmed_times': confirmedTimes,
        'individual_limits': individualLimits,
      },
    );
    return pact(tripId);
  }

  Future<List<TaskItem>> tasks(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/tasks');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, TaskItem.fromJson);
  }

  Future<TaskSummary> taskSummary(String tripId) async =>
      TaskSummary.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/tasks/summary')),
      );

  Future<TaskItem> createTask(
    String tripId, {
    required String title,
    String? description,
    String? assigneeId,
  }) async => TaskItem.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/tasks',
        data: {
          'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
          'assignee_id': ?assigneeId,
        },
      ),
    ),
  );

  Future<void> updateTask(
    String tripId,
    String taskId, {
    String? status,
    String? assigneeId,
    bool unassign = false,
  }) async {
    await _api.patch(
      '/api/trips/$tripId/tasks/$taskId',
      data: {
        'status': ?status,
        if (unassign) 'assignee_id': null else 'assignee_id': ?assigneeId,
      },
    );
  }

  Future<List<Branch>> branches(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/branches');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Branch.fromJson);
  }

  Future<BranchCreation> createBranch(
    String tripId, {
    required String name,
    List<String> memberIds = const [],
    String? activityId,
    String? reunionAt,
    String? reunionPlace,
  }) async => BranchCreation.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/branches',
        data: {
          'name': name,
          'member_ids': memberIds,
          'activity_id': ?activityId,
          'reunion_at': ?reunionAt,
          'reunion_place': ?reunionPlace,
        },
      ),
    ),
  );

  Future<List<Mission>> missions(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/missions');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Mission.fromJson);
  }

  Future<void> joinMission(String tripId, String missionId) async {
    await _api.post('/api/trips/$tripId/missions/$missionId/join');
  }

  Future<void> completeMission(String tripId, String missionId) async {
    await _api.post('/api/trips/$tripId/missions/$missionId/complete');
  }

  Future<void> disableMission(String tripId, String missionId) async {
    await _api.post('/api/trips/$tripId/missions/$missionId/disable');
  }

  Future<List<TripActivityEvent>> activity(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/activity');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, TripActivityEvent.fromJson);
  }

  Future<List<Capsule>> capsules(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/capsules');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Capsule.fromJson);
  }

  Future<void> createCapsule(String tripId, {int ttlHours = 72}) async {
    await _api.post(
      '/api/trips/$tripId/capsules',
      data: {'ttl_hours': ttlHours},
    );
  }

  Future<OpportunityClock> opportunityClock(String tripId, {String? on}) async =>
      OpportunityClock.fromJson(
        jsonMap(
          await _api.get(
            '/api/trips/$tripId/opportunity-clock',
            query: on == null ? null : {'on': on},
          ),
        ),
      );

  Future<List<WatchItem>> materialWatches(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/material-watch');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, WatchItem.fromJson);
  }

  Future<void> addMaterialWatch(
    String tripId, {
    required String activityId,
    required String field,
  }) async {
    await _api.post(
      '/api/trips/$tripId/material-watch',
      data: {'activity_id': activityId, 'field': field},
    );
  }

  Future<void> removeMaterialWatch(String tripId, String watchId) async {
    await _api.delete('/api/trips/$tripId/material-watch/$watchId');
  }

  Future<WatchCheckResult> checkMaterialWatches(String tripId) async =>
      WatchCheckResult.fromJson(
        jsonMap(
          await _api.post('/api/trips/$tripId/material-watch/check'),
        ),
      );

  Future<List<GroundRequestItem>> groundRequests(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/ground-requests');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, GroundRequestItem.fromJson);
  }

  Future<void> createGroundRequest(
    String tripId, {
    required String question,
    String? placeId,
    String? activityId,
  }) async {
    await _api.post(
      '/api/trips/$tripId/ground-requests',
      data: {
        'question': question,
        'place_id': ?placeId,
        'activity_id': ?activityId,
      },
    );
  }

  Future<void> respondToGroundRequest(
    String tripId,
    String requestId, {
    required String observation,
    double confidence = 0.5,
  }) async {
    await _api.post(
      '/api/trips/$tripId/ground-requests/$requestId/responses',
      data: {'observation': observation, 'confidence': confidence},
    );
  }

  Future<PulseResponse> pulse(String tripId, {String? day}) async =>
      PulseResponse.fromJson(
        jsonMap(
          await _api.get(
            '/api/trips/$tripId/pulse',
            query: day == null ? null : {'day': day},
          ),
        ),
      );

  Future<void> savePulse(
    String tripId, {
    required int energy,
    required List<String> interests,
    int? availableMinutes,
    int budgetComfort = 3,
    double? radiusKm,
    List<String> activityPrefs = const [],
    String? note,
    String? pulseDate,
  }) async {
    await _api.put(
      '/api/trips/$tripId/pulse',
      data: {
        'pulse_date': ?pulseDate,
        'energy': energy,
        'interests': interests,
        'available_minutes': availableMinutes,
        'budget_comfort': budgetComfort,
        'radius_km': radiusKm,
        'activity_prefs': activityPrefs,
        'note': note,
      },
    );
  }
}
