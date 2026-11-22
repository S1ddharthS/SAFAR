import 'common.dart';
import 'json.dart';

class Memory {
  const Memory({
    required this.id,
    required this.userId,
    required this.kind,
    required this.capturedAt,
    required this.visibility,
    required this.aiGenerated,
    required this.approved,
    this.author,
    this.textContent,
    this.mediaUrl,
    this.mediaType,
    this.caption,
    this.lat,
    this.lon,
  });

  final String id;
  final String userId;
  final String kind;
  final String capturedAt;
  final String visibility;
  final bool aiGenerated;
  final bool approved;
  final User? author;
  final String? textContent;
  final String? mediaUrl;
  final String? mediaType;
  final String? caption;
  final double? lat;
  final double? lon;

  bool get isPrivate => visibility == 'private';

  factory Memory.fromJson(Map<String, dynamic> json) {
    final authorJson = jsonMap(json['author']);
    return Memory(
      id: jsonText(json['id']),
      userId: jsonText(json['user_id']),
      kind: jsonText(json['kind'], 'text'),
      capturedAt: jsonText(json['captured_at']),
      visibility: jsonText(json['visibility'], 'trip'),
      aiGenerated: jsonBool(json['ai_generated']),
      approved: jsonBool(json['approved'], true),
      author: authorJson.isEmpty ? null : User.fromJson(authorJson),
      textContent: jsonString(json['text_content']),
      mediaUrl: jsonString(json['media_url']),
      mediaType: jsonString(json['media_type']),
      caption: jsonString(json['caption']),
      lat: jsonDoubleOrNull(json['lat']),
      lon: jsonDoubleOrNull(json['lon']),
    );
  }
}

class MemoryDay {
  const MemoryDay({required this.date, required this.memories});

  final String date;
  final List<Memory> memories;

  factory MemoryDay.fromJson(Map<String, dynamic> json) => MemoryDay(
    date: jsonText(json['date']),
    memories: jsonObjects(json['memories'], Memory.fromJson),
  );
}

class MemoriesResponse {
  const MemoriesResponse({
    required this.days,
    required this.total,
    required this.permissions,
  });

  final List<MemoryDay> days;
  final int total;
  final String permissions;

  factory MemoriesResponse.fromJson(Map<String, dynamic> json) =>
      MemoriesResponse(
        days: jsonObjects(json['days'], MemoryDay.fromJson),
        total: jsonInt(json['total']),
        permissions: jsonText(json['permissions']),
      );
}

class StudioEvent {
  const StudioEvent({
    required this.id,
    required this.title,
    required this.startAt,
    required this.status,
    this.summary,
    this.endAt,
    this.memoryIds = const [],
  });

  final String id;
  final String title;
  final String startAt;
  final String status;
  final String? summary;
  final String? endAt;
  final List<String> memoryIds;

  factory StudioEvent.fromJson(Map<String, dynamic> json) => StudioEvent(
    id: jsonText(json['id']),
    title: jsonText(json['title']),
    startAt: jsonText(json['start_at']),
    status: jsonText(json['status'], 'suggested'),
    summary: jsonString(json['summary']),
    endAt: jsonString(json['end_at']),
    memoryIds: jsonStringList(json['memory_ids']),
  );
}

class Studio {
  const Studio({
    required this.memories,
    required this.events,
    required this.capabilities,
    required this.disclosure,
  });

  final List<Memory> memories;
  final List<StudioEvent> events;
  final Map<String, dynamic> capabilities;
  final String disclosure;

  factory Studio.fromJson(Map<String, dynamic> json) => Studio(
    memories: jsonObjects(json['memories'], Memory.fromJson),
    events: jsonObjects(json['events'], StudioEvent.fromJson),
    capabilities: jsonMap(json['capabilities']),
    disclosure: jsonText(json['disclosure']),
  );
}

class ReplayItem {
  const ReplayItem({
    required this.id,
    required this.title,
    required this.startTime,
    required this.protected,
  });

  final String id;
  final String title;
  final String startTime;
  final bool protected;

  factory ReplayItem.fromJson(Map<String, dynamic> json) => ReplayItem(
    id: jsonText(json['id']),
    title: jsonText(json['title']),
    startTime: jsonText(json['start_time']),
    protected: jsonBool(json['protected']),
  );
}

class ReplayEvent {
  const ReplayEvent({
    required this.id,
    required this.title,
    this.summary,
    this.memoryIds = const [],
  });

  final String id;
  final String title;
  final String? summary;
  final List<String> memoryIds;

  factory ReplayEvent.fromJson(Map<String, dynamic> json) => ReplayEvent(
    id: jsonText(json['id']),
    title: jsonText(json['title']),
    summary: jsonString(json['summary']),
    memoryIds: jsonStringList(json['memory_ids']),
  );
}

class ReplayDay {
  const ReplayDay({
    required this.date,
    required this.items,
    required this.memories,
    required this.events,
  });

  final String date;
  final List<ReplayItem> items;
  final List<Memory> memories;
  final List<ReplayEvent> events;

  factory ReplayDay.fromJson(Map<String, dynamic> json) => ReplayDay(
    date: jsonText(json['date']),
    items: jsonObjects(json['items'], ReplayItem.fromJson),
    memories: jsonObjects(json['memories'], Memory.fromJson),
    events: jsonObjects(json['events'], ReplayEvent.fromJson),
  );
}

class ReplayStats {
  const ReplayStats({
    this.daysRecorded = 0,
    this.memories = 0,
    this.media = 0,
    this.approvedEvents = 0,
    this.contributors = 0,
  });

  final int daysRecorded;
  final int memories;
  final int media;
  final int approvedEvents;
  final int contributors;

  factory ReplayStats.fromJson(Map<String, dynamic> json) => ReplayStats(
    daysRecorded: jsonInt(json['days_recorded']),
    memories: jsonInt(json['memories']),
    media: jsonInt(json['media']),
    approvedEvents: jsonInt(json['approved_events']),
    contributors: jsonInt(json['contributors']),
  );
}

class ReplayTrip {
  const ReplayTrip({
    required this.id,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
  });

  final String id;
  final String name;
  final String destination;
  final String startDate;
  final String endDate;

  factory ReplayTrip.fromJson(Map<String, dynamic> json) => ReplayTrip(
    id: jsonText(json['id']),
    name: jsonText(json['name']),
    destination: jsonText(json['destination']),
    startDate: jsonText(json['start_date']),
    endDate: jsonText(json['end_date']),
  );
}

class ReplayResponse {
  const ReplayResponse({
    required this.trip,
    required this.days,
    required this.stats,
    required this.permissions,
    required this.formatNote,
  });

  final ReplayTrip trip;
  final List<ReplayDay> days;
  final ReplayStats stats;
  final String permissions;
  final String formatNote;

  factory ReplayResponse.fromJson(Map<String, dynamic> json) =>
      ReplayResponse(
        trip: ReplayTrip.fromJson(jsonMap(json['trip'])),
        days: jsonObjects(json['days'], ReplayDay.fromJson),
        stats: ReplayStats.fromJson(jsonMap(json['stats'])),
        permissions: jsonText(json['permissions']),
        formatNote: jsonText(json['format_note']),
      );
}
