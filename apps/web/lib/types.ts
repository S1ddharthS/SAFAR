export type ID = string;

export interface User {
  id: ID;
  email: string;
  display_name: string;
  is_admin: boolean;
  quiet_mode?: boolean;
  locale?: string;
  timezone?: string;
  avatar_url?: string | null;
  created_at?: string;
}

export interface Profile {
  user_id?: string;
  display_name?: string;
  email?: string;
  headline?: string | null;
  bio?: string | null;
  home_city?: string | null;
  travel_pace?: string;
  budget_level?: string;
  budget_limit?: number | null;
  interests: string[];
  accessibility_needs: string[];
  dietary: string[];
  languages: string[];
  public_profile: boolean;
  allow_discovery: boolean;
  location_sharing: boolean;
}

export interface DNA {
  scores: Record<string, number>;
  source?: string;
  updated_at?: string;
  dimensions?: string[];
  note?: string;
}

export interface Consent {
  granted: boolean;
  policy_version: string;
  updated_at?: string;
}

export interface Me {
  user: User;
  profile: Profile;
  dna: DNA;
  consents: Record<string, Consent>;
  policy_version: string;
}

export interface Trip {
  id: ID;
  name: string;
  description?: string | null;
  destination_id?: ID | null;
  destination_name: string;
  start_date: string;
  end_date: string;
  group_size: number;
  budget_total?: number | null;
  currency: string;
  base_lat: number;
  base_lon: number;
  status: string;
  privacy: string;
  created_by: ID;
  member_count?: number;
  my_role?: string;
  created_at?: string;
  next_action?: NextAction | null;
}

export interface NextAction {
  title: string;
  reason: string;
  href: string;
  kind: string;
  quiet_mode?: boolean;
}

export interface Member {
  id: ID;
  user: User | null;
  display_name: string;
  role: string;
  status: string;
  joined_at: string;
  is_self: boolean;
  budget_limit?: number | null;
  accessibility_needs?: string[];
}

export interface Destination {
  id: ID;
  slug: string;
  name: string;
  country: string;
  region?: string | null;
  description: string;
  lat: number;
  lon: number;
  hero_image?: string | null;
  tags: string[];
  best_months: number[];
  source_type: string;
  source_name: string;
  activity_count?: number;
  disclosure?: string;
}

export interface Place {
  id: ID;
  destination_id: ID;
  name: string;
  category: string;
  description: string;
  lat: number;
  lon: number;
  address?: string | null;
  fragile?: boolean;
  respect_note?: string | null;
  source_type?: string;
  source_name?: string | null;
  last_verified_at?: string | null;
}

export interface Activity {
  id: ID;
  place_id: ID;
  destination_id: ID;
  name: string;
  description: string;
  tags: string[];
  price_estimate: number;
  currency: string;
  duration_minutes: number;
  effort: number;
  indoor: boolean;
  wheelchair_accessible: boolean | null;
  iconic: boolean;
  popularity: number;
  fragile?: boolean;
  opening_hours?: Record<string, string>;
  access_chain?: Record<string, string | { status?: string; detail?: string }>;
  image_url?: string | null;
  source_type?: string;
  last_verified_at?: string | null;
  place?: Place | null;
  destination?: Destination | null;
}

export interface SearchItem {
  activity: Activity;
  personal_fit: number;
  similar_to?: string | null;
  similarity?: number;
  respect_note?: string | null;
  provenance?: string;
  catalog_freshness?: { label: string; last_verified_at?: string | null };
}

export interface ItineraryItem {
  id: ID;
  day: string;
  start_time: string;
  end_time: string | null;
  title: string;
  activity_id: ID | null;
  place_id: ID | null;
  notes: string | null;
  cost_estimate: number;
  status: string;
  is_protected: boolean;
  sort_order: number;
  created_by?: ID;
  created_at?: string;
  activity?: Activity | null;
  attendance?: { in: number; out: number; join_later: number; my_status: string };
}

export interface Version {
  id: ID;
  version: number;
  snapshot: ItineraryItem[];
  note: string | null;
  created_at: string;
  created_by: ID;
}

export interface Itinerary {
  itinerary_id: ID;
  confirmed_version: number;
  my_role: string;
  items: ItineraryItem[];
  versions: Version[];
  open_proposals: number;
  totals: {
    cost: number;
    currency: string;
    per_person?: number;
    items?: number;
    days?: number;
    protected_items?: number;
  };
}

export interface VoteSet {
  yes: number;
  no: number;
  abstain: number;
}

export interface Proposal {
  id: ID;
  kind: string;
  title: string;
  summary: string | null;
  payload: Record<string, unknown>;
  status: string;
  target_day: string | null;
  created_by: ID;
  author: User | null;
  created_at: string;
  decided_at?: string | null;
  votes: VoteSet;
  vote_count: number;
  my_vote: string | null;
  comments: {
    id: ID;
    user: User | null;
    value: string;
    comment: string;
    created_at: string;
  }[];
  impact?: Record<string, unknown>;
  pact_conflicts?: { item: string; rule: string; resolution: string }[];
  requires_approval?: boolean;
}

export interface Pulse {
  id: ID;
  user_id: ID;
  pulse_date: string;
  energy: number;
  interests: string[];
  available_minutes: number | null;
  budget_comfort?: number;
  radius_km: number | null;
  activity_prefs: string[];
  note?: string | null;
  is_self: boolean;
  author?: { id: ID; display_name: string } | null;
}

export interface PulseResponse {
  date: string;
  items: Pulse[];
  my_pulse: Pulse | null;
  coverage: { shared: number; members: number };
  privacy: string;
}

export interface RecommendationItem {
  id: ID;
  activity_id: ID;
  rank: number;
  score: number;
  average_fit: number;
  minimum_fit: number;
  fairness_spread: number;
  novelty: number;
  penalties: Record<string, number>;
  explanation: {
    summary: string;
    why_selected: string[];
    suits: string[];
    may_not_prefer: string[];
    constraints_checked: { constraint: string; status: string; detail: string }[];
    estimated_cost: number;
    currency: string;
    distance_km: number;
    travel_minutes: number;
    duration_minutes: number;
    data_freshness: { label: string; age_days?: number | null; last_verified_at?: string | null };
    uncertainties: string[];
    metrics: Record<string, number>;
    member_fits_anonymous: number[];
    target_member?: string | null;
    selection?: {
      diversity_penalty: number;
      feedback_adjustment: number;
      note: string;
    };
    alternatives: { activity_id: ID; name: string; score_delta: number }[];
  };
  status: string;
  activity: Activity | null;
  my_feedback?: string | null;
  respect?: {
    fragile: boolean;
    confidence: string;
    status: "not_applicable" | "guidance_recorded" | "no_guidance_recorded";
    guidance: string | null;
  };
}

export interface EngineBatch {
  id: ID | null;
  mode: string;
  mode_meta: { label: string; intent: string };
  for_date: string;
  model_version: string;
  meta: {
    candidate_count?: number;
    eligible_count?: number;
    excluded_count?: number;
    planned_excluded?: number;
    members_count?: number;
    pulse_coverage?: string;
    hard_constraints?: string[];
    ranking_formula?: string;
    disclosure?: string;
    clarifying_question?: string | null;
    exclusion_reasons?: Record<string, number>;
    target_member?: string | null;
    alternative_count?: number;
    evaluation?: {
      fairness: {
        least_served_member_mean_fit: number;
        member_mean_spread: number;
        jain_index: number;
        note?: string;
      };
      satisfaction: {
        mean_average_fit: number;
        mean_minimum_fit: number;
        mean_novelty: number;
      };
      constraints: { violations: number; eligible: number; excluded: number; note?: string };
      diversity: {
        unique_primary_tags: number;
        unique_tags: number;
        mean_pairwise_similarity: number;
        note?: string;
      };
    };
    feedback_learning?: {
      applied_activities: number;
      consented_raters: number;
      enabled: boolean;
      max_adjustment: number;
      note: string;
    };
    protected_time?: {
      protected_items: {
        item_id: ID;
        title: string;
        start: string;
        end: string;
        protected: boolean;
      }[];
      free_windows: { start: string; end: string; minutes: number }[];
      max_free_minutes: number;
      note: string;
    };
  };
  created_at?: string;
  created_by?: ID;
  items: RecommendationItem[];
  message?: string;
}

export interface Balance {
  user_id: ID;
  display_name: string;
  net: number;
}

export interface Settlement {
  from_user_id: ID;
  from_name: string;
  to_user_id: ID;
  to_name: string;
  amount: number;
  status: string;
}

export interface ExpensesResponse {
  total_spent: number;
  currency: string;
  balances: Balance[];
  settlements: Settlement[];
  disclosure: string;
}

export interface Expense {
  id: ID;
  title: string;
  category: string;
  amount: number;
  currency: string;
  paid_by: ID;
  payer: User | null;
  incurred_on: string;
  notes: string | null;
  participants: {
    id: ID;
    user: User | null;
    guest_name: string | null;
    weight: number;
    share_amount: number;
  }[];
  created_at: string;
}

export interface Memory {
  id: ID;
  user_id: ID;
  author: User | null;
  kind: string;
  text_content: string | null;
  media_url: string | null;
  media_type: string | null;
  caption: string | null;
  captured_at: string;
  lat: number | null;
  lon: number | null;
  visibility: string;
  ai_generated: boolean;
  approved: boolean;
  created_at: string;
}

export interface MemoryDay {
  date: string;
  memories: Memory[];
}

export interface MemoriesResponse {
  days: MemoryDay[];
  total: number;
  permissions: string;
}

export interface Studio {
  memories: Memory[];
  events: {
    id: ID;
    title: string;
    summary: string | null;
    start_at: string;
    end_at: string | null;
    memory_ids: ID[];
    status: string;
  }[];
  capabilities: Record<string, boolean | string>;
  disclosure: string;
}

export interface ReplayResponse {
  trip: { id: ID; name: string; destination: string; start_date: string; end_date: string };
  days: {
    date: string;
    items: { id: ID; title: string; start_time: string; protected: boolean }[];
    memories: Memory[];
    events: { id: ID; title: string; summary: string | null; memory_ids?: ID[] }[];
    captions: { memory_id: ID; caption: string; author?: ID }[];
  }[];
  stats: {
    days_recorded: number;
    memories: number;
    media: number;
    approved_events: number;
    contributors: number;
  };
  permissions: string;
  format_note: string;
}

export interface Pact {
  id: ID;
  must_do: string[];
  flexible: string[];
  individual_limits: Record<string, { budget_limit?: number; note?: string }>;
  confirmed_times: Record<string, string>;
  exceptions: string[];
  updated_at: string;
}

export interface Task {
  id: ID;
  title: string;
  description: string | null;
  assignee_id: ID | null;
  status: string;
  created_at: string;
}

export interface TaskSummary {
  trip_id: ID;
  totals: { open: number; done: number; total: number };
  by_assignee: {
    user_id: ID;
    display_name: string;
    open: number;
    done: number;
    total: number;
  }[];
  unassigned: { open: number; done: number; total: number };
  load: { key: string; display_name: string; open: number }[];
  disclosure: string;
}

export interface Branch {
  id: ID;
  name: string;
  member_ids: ID[];
  activity_id: ID | null;
  reunion_at: string | null;
  reunion_place: string | null;
  status: string;
}

export interface Shadowplan {
  id: ID;
  item_id: ID;
  backup_activity_id: ID;
  notes: string | null;
  readiness: Record<string, string>;
  created_at: string;
}

export interface GroundRequest {
  id: ID;
  question: string;
  place_id: ID | null;
  activity_id: ID | null;
  status: string;
  created_at: string;
  responses: {
    id: ID;
    observation: string;
    observed_at: string;
    confidence: number;
    verified: boolean;
    provenance: string;
    contributor_id: ID;
  }[];
}

export interface Mission {
  id: ID;
  title: string;
  description: string;
  constraints: Record<string, unknown>;
  status: string;
  my_status: string | null;
  optional: boolean;
  self_reported: boolean;
}

export interface NearbyItem {
  activity: Activity;
  distance_km: number;
  travel_minutes: number;
  provenance?: string;
  walkable?: boolean;
}

export interface PlaceReportCategory {
  category: string;
  status: string;
  source_type: string;
  source_label: string;
  latest_observed_at: string;
  freshness: number;
  freshness_label: string;
  confidence: number;
  reports_count: number;
  weighted_support: number;
  reports: {
    id: ID;
    value: Record<string, unknown>;
    note: string | null;
    observed_at: string;
    source_type?: string;
    source_label?: string;
    provenance: string;
    verification?: "official_verified" | "moderator_verified" | "unverified";
    verified: boolean;
    confidence: number;
    freshness: number;
    weight?: number;
  }[];
}

export interface PlaceReportsAggregate {
  activity_id: ID;
  window_days: number;
  has_data: boolean;
  disclosure: string;
  categories: PlaceReportCategory[];
}

export interface PlaceDetail {
  activity: Activity;
  catalog_freshness: { label: string; last_verified_at?: string | null };
  reports: PlaceReportsAggregate;
  evidence: {
    activity_id?: ID;
    name?: string;
    sources: { entity: string; name: string; last_verified_at?: string | null; is_live: boolean }[];
    unknowns: string[];
    cost_assumption?: { value: number; currency: string; basis: string };
    travel_assumption?: string;
    provenance?: string;
    disclosure?: string;
    recent_reports?: PlaceReportsAggregate;
    group_suitability?: unknown;
  };
  access_chain: {
    activity_id?: ID;
    stages: { stage: string; label: string; status: string; detail: string | null; source: string | null }[];
    summary: { verified_stages: number; reported_barriers: number; unknown_stages: number };
    disclosure?: string;
  };
  crowd_forecast: {
    activity_id?: ID;
    status: string;
    model?: string;
    message?: string;
    reason?: string;
    required_reports?: number;
    available_reports?: number;
    threshold?: {
      min_reports: number;
      min_reports_per_bucket: number;
      window_days: number;
      max_age_days: number;
    };
    observed?: {
      reports_seen: number;
      reports_used: number;
      excluded_stale: number;
      excluded_unusable: number;
      excluded_outliers?: number;
      latest_observed_at: string | null;
      range: { min: number; max: number } | null;
      buckets: {
        weekday: number;
        bucket: string;
        reports: number;
        mean_level: number;
        latest_observed_at: string;
      }[];
      note?: string;
    };
    latest_observation?: {
      observed_at: string;
      source_type: string;
      source_label?: string;
      value: Record<string, unknown>;
    } | null;
    predicted?: {
      method?: string;
      model?: string;
      provenance: string;
      note?: string;
      forecasts: {
        weekday: number;
        bucket: string;
        expected_level: number;
        level_label?: string;
        spread: number;
        interval_80?: [number, number];
        reports: number;
        granularity?: string;
        fallback?: boolean;
        stale?: boolean;
        confidence?: number;
        confidence_label?: string;
        freshness?: number;
        mean_report_age_days?: number;
      }[];
    };
    disclosure?: string;
  };
}

export interface ExpectationResult {
  activity_id: ID;
  claim: string;
  evidence: { item: string; status: string; detail: string }[];
  recent_reports: PlaceReportCategory[];
  limitations: string[];
  unknowns: string[];
  verdict: string;
}

export interface DestinationCard extends Destination {}

export interface Circle {
  id: ID;
  slug: string;
  name: string;
  description: string;
  interests: string[];
  member_count: number;
  joined: boolean;
  created_at: string;
}

export interface CircleDetail extends Circle {
  posts: {
    id: ID;
    user_id: ID;
    author: User | null;
    title: string;
    body: string;
    activity_id: ID | null;
    status: string;
    created_at: string;
  }[];
  members: { user_id: ID; display_name: string; role: string }[];
}

export interface Contributor {
  id: ID;
  user: User;
  destination: Destination;
  bio: string | null;
  expertise: string[];
  verified: boolean;
  accepts_requests: boolean;
}

export interface NotificationItem {
  id: ID;
  trip_id: ID | null;
  kind: string;
  title: string;
  body: string | null;
  link: string | null;
  read: boolean;
  created_at: string;
}

export interface ThreadResponse {
  completed_trips: number;
  traditions: {
    activity_id: ID;
    name: string;
    price_estimate: number;
    duration_minutes: number;
    sentiments: string[];
  }[];
  note: string;
}

export interface AssistantAnswer {
  intent: string;
  answer: string;
  citations: { label: string; type: string; id?: ID; provenance?: string }[];
  grounding: string;
  limitations: string[];
  suggested_actions: { label: string; href?: string; action?: string }[];
  language?: {
    code: string;
    name: string;
    source: string;
    detected?: string | null;
    mixed?: string[];
    unsupported?: string | null;
  };
  context?: {
    trip: { destination: string | null; start_date: string; end_date: string; group_size: number };
    missing: string[];
    group_preferences: { consented_members: number; total_members: number } | null;
  };
  mutation?: string;
  requires_approval?: boolean;
  attribution?: string;
}

export interface DestinationDetail extends Destination {
  sample_activities: SearchItem[];
}

export interface AdminStats {
  users: number;
  trips: number;
  memberships: number;
  proposals_open: number;
  recommendation_batches: number;
  expenses: number;
  memories: number;
  place_reports: number;
  open_abuse_reports: number;
  audit_events: number;
}

export interface TravellerMatch {
  user: {
    id: ID;
    display_name: string;
    avatar_url?: string | null;
    headline?: string | null;
    home_city?: string | null;
  };
  score: number;
  reasons: string[];
  shared_interests: string[];
  privacy: string;
}

export interface ConnectionRequestItem {
  id: ID;
  direction: "incoming" | "outgoing";
  from_user: { id: ID; display_name: string; avatar_url?: string | null } | null;
  to_user: { id: ID; display_name: string; avatar_url?: string | null } | null;
  message: string | null;
  status: string;
  created_at: string;
  decided_at: string | null;
}

export interface InspirationCandidate {
  type: string;
  kind?: string;
  candidate_id?: string;
  id: ID | null;
  name: string;
  confidence: number;
  evidence: string;
  source?: string;
  source_span?: { start: number; end: number; text: string } | null;
  provenance?: string;
  verified?: boolean;
  decision?: "pending" | "accept" | "reject";
  value?: Record<string, unknown>;
}

export interface InspirationExtraction {
  matches?: InspirationCandidate[];
  notes?: string[];
  limitations?: string[];
  review?: { pending: number; accepted: number; rejected: number };
  metadata?: {
    source_hosts?: string[];
    hashtags?: string[];
    providers?: {
      provider: string;
      ok: boolean;
      provenance: string;
      error?: string | null;
      message?: string | null;
      attribution?: string | null;
    }[];
    link?: {
      title?: string | null;
      description?: string | null;
      site_name?: string | null;
      source_url?: string | null;
    } | null;
    ocr?: { available: boolean; characters: number; preview: string } | null;
    [key: string]: unknown;
  };
  [key: string]: unknown;
}

export interface InspirationItem {
  id: ID;
  source_type: string;
  content: string;
  status: string;
  extracted: InspirationExtraction;
  created_at: string;
}

export interface MaterialWatchItem {
  id: ID;
  activity_id: ID;
  activity_name: string | null;
  field: string;
  last_value: Record<string, unknown>;
  status: string;
  last_checked_at: string | null;
}

export interface CapsuleItem {
  id: ID;
  created_at: string;
  stale_after: string;
  stale: boolean;
  snapshot: Record<string, unknown>;
}

export interface TripActivityEvent {
  id: ID;
  action: string;
  entity_type: string;
  entity_id: ID | null;
  detail: Record<string, unknown>;
  created_at: string;
}

export interface PlaceReportItem {
  id: ID;
  activity_id: ID | null;
  place_id?: ID | null;
  category: string;
  value: Record<string, unknown>;
  note: string | null;
  observed_at: string;
  source_type?: string;
  confidence?: number;
  provenance: string;
  freshness?: number;
  freshness_label?: string;
  verified: boolean;
  helpful_count: number;
  reporter?: User | null;
  is_mine?: boolean;
}

export interface TwinComparison {
  day: string;
  confirmed_plan: {
    name: string;
    total_cost: number;
    total_duration_minutes: number;
    total_travel_minutes: number;
    average_group_fit: number | null;
    minimum_member_fit: number | null;
    items: {
      activity_id: string;
      name: string;
      cost: number;
      duration: number;
      distance_km: number;
      travel_minutes: number;
      eligible: boolean;
    }[];
  };
  alternative_plan: {
    name: string;
    total_cost: number;
    total_duration_minutes: number;
    total_travel_minutes: number;
    average_group_fit: number | null;
    minimum_member_fit: number | null;
    items: {
      activity_id: string;
      name: string;
      cost: number;
      duration: number;
      distance_km: number;
      travel_minutes: number;
      eligible: boolean;
    }[];
  };
  diff: {
    added: { activity_id: string; name: string }[];
    removed: { activity_id: string; name: string }[];
    kept: { activity_id: string; name: string }[];
  };
  trade_offs: string[];
  requires_approval: boolean;
  disclosure: string;
  generated_at: string;
}

export interface RescueAnalysis {
  disruption: { kind: string; label: string; note?: string | null; extra_minutes?: number };
  target_day?: string | null;
  affected: { item_id: ID; title: string; start_time: string; reason: string }[];
  protected?: { item_id: ID; title: string; start_time: string; reason: string }[];
  proposals: {
    item_id: ID;
    day: string;
    title: string;
    start_time: string;
    reason: string;
    original_activity: {
      id: ID;
      name: string;
      price: number;
      duration: number;
      indoor: boolean;
      effort: number;
    } | null;
    travel_minutes: number;
    options: {
      activity_id: ID | null;
      name: string;
      price: number | null;
      duration: number | null;
      indoor: boolean | null;
      effort: number | null;
      source: string;
      score: number | null;
      note: string | null;
      ready: boolean;
    }[];
    recommended: string | null;
    recommended_activity_id: ID | null;
  }[];
  message?: string;
  consequences?: {
    cost_delta: number;
    duration_delta_minutes: number;
    time_saved_or_lost: string;
    pact_conflicts: unknown[];
    protected_respected?: boolean;
  };
  requires_approval: boolean;
  disclosure?: string;
}

export interface OpportunityItem {
  activity_id: ID;
  name: string;
  place_name: string | null;
  duration_minutes: number;
  price_estimate: number;
  currency: string;
  opening_hours_today: string | null;
  opening_source: string;
  last_verified_at: string | null;
  travel_minutes_estimate: number;
  status:
    | "open_now"
    | "later_today"
    | "no_window"
    | "closed_today"
    | "unknown"
    | "window_missed";
  next_start: string | null;
  explanation: string;
  provenance: "ESTIMATED";
}

export interface OpportunityClock {
  date: string;
  available: boolean;
  reason?: string;
  weekday?: string;
  now?: string | null;
  planned_count?: number;
  planned_titles?: string[];
  free_windows?: { start: string; end: string; minutes: number }[];
  items: OpportunityItem[];
  summary: {
    candidates: number;
    open_now: number;
    later_today: number;
    closed_today?: number;
    unknown_hours: number;
  };
  explanation: string;
  disclosure: string;
  plan_unchanged: boolean;
  confirmed_version: number | null;
}

export interface CompanionLink {
  id: ID;
  purpose: "vote" | "checkin";
  target: {
    kind: "proposal" | "checkin";
    id: string;
    title: string;
    status: string;
    day?: string | null;
  };
  status: "active" | "used" | "expired" | "revoked";
  expires_at: string;
  max_uses: number;
  used_count: number;
  anonymous_responses: number;
  response_values: Record<string, number>;
  created_at: string;
}
