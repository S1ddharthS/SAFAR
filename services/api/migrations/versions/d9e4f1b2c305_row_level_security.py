"""PostgreSQL row-level security for private trips, preferences and media

Revision ID: d9e4f1b2c305
Revises: c7d3e9a1f204
Create Date: 2026-11-19

Policies rely on per-transaction GUCs set by app/db/context.py:
  app.user_id, app.admin, app.system, app.auth, app.companion_link

The migration role must be able to bypass RLS (superuser or a role with
BYPASSRLS) because the SECURITY DEFINER helpers read the same tables.
The application role must be a NON-owner without BYPASSRLS, otherwise the
policies are bypassed. See docs/DEPLOYMENT.md.
"""

from alembic import op

revision = "d9e4f1b2c305"
down_revision = "c7d3e9a1f204"
branch_labels = None
depends_on = None


HELPERS = [
    """
    CREATE OR REPLACE FUNCTION safar_uid() RETURNS text
    LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.user_id', true), '') $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_system() RETURNS boolean
    LANGUAGE sql STABLE AS $$ SELECT current_setting('app.system', true) = 'on' $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_admin() RETURNS boolean
    LANGUAGE sql STABLE AS $$ SELECT current_setting('app.admin', true) = 'on' $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_auth() RETURNS boolean
    LANGUAGE sql STABLE AS $$ SELECT current_setting('app.auth', true) = 'on' $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_companion_link() RETURNS text
    LANGUAGE sql STABLE AS $$
        SELECT NULLIF(current_setting('app.companion_link', true), '')
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_invitation_token() RETURNS text
    LANGUAGE sql STABLE AS $$
        SELECT NULLIF(current_setting('app.invitation_token', true), '')
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_is_trip_member(tid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_members tm
            JOIN trips t ON t.id = tm.trip_id
            WHERE tm.trip_id = tid AND tm.user_id = safar_uid()
              AND tm.status = 'active' AND t.deleted_at IS NULL
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_is_trip_admin(tid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_members tm
            WHERE tm.trip_id = tid AND tm.user_id = safar_uid()
              AND tm.status = 'active' AND tm.role IN ('owner', 'admin')
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_shares_trip(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_members me
            JOIN trip_members peer ON peer.trip_id = me.trip_id
            JOIN trips t ON t.id = me.trip_id
            WHERE me.user_id = safar_uid() AND me.status = 'active'
              AND peer.user_id = other AND peer.status = 'active'
              AND t.deleted_at IS NULL
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_current_email() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT lower(email) FROM users WHERE id = safar_uid()
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_is_invited(tid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_invitations i
            WHERE i.trip_id = tid AND lower(i.email) = safar_current_email()
              AND i.accepted_at IS NULL
              AND (i.expires_at IS NULL OR i.expires_at > (now() AT TIME ZONE 'UTC'))
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_invitation_trip(tid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_invitations i
            WHERE i.trip_id = tid AND i.token = safar_invitation_token()
              AND (i.expires_at IS NULL OR i.expires_at > (now() AT TIME ZONE 'UTC'))
              AND (i.email IS NULL OR lower(i.email) = safar_current_email())
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_connection_peer(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM connection_requests cr
            WHERE (cr.from_user_id = safar_uid() AND cr.to_user_id = other)
               OR (cr.to_user_id = safar_uid() AND cr.from_user_id = other)
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_block_peer(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM user_blocks b
            WHERE (b.blocker_id = safar_uid() AND b.blocked_id = other)
               OR (b.blocked_id = safar_uid() AND b.blocker_id = other)
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_inviter_of_current(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_invitations i
            WHERE i.created_by = other
              AND (
                lower(i.email) = safar_current_email()
                OR i.token = safar_invitation_token()
              )
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_public_user(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM profiles p WHERE p.user_id = other AND p.public_profile
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_is_local_contributor(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (SELECT 1 FROM local_contributors lc WHERE lc.user_id = other)
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_circle_peer(other text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM circle_members me
            JOIN circle_members peer ON peer.circle_id = me.circle_id
            WHERE me.user_id = safar_uid() AND peer.user_id = other
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_circle_member(cid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM circle_members cm
            WHERE cm.circle_id = cid AND cm.user_id = safar_uid()
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_circle_admin(cid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM circle_members cm
            WHERE cm.circle_id = cid AND cm.user_id = safar_uid()
              AND cm.role IN ('owner', 'admin')
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_circle_public(cid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (SELECT 1 FROM travel_circles c WHERE c.id = cid AND c.is_public)
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_memory_shared(mid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM memory_permissions mp
            WHERE mp.memory_id = mid AND mp.user_id = safar_uid() AND mp.can_view
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_memory_owner(mid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM trip_memories m WHERE m.id = mid AND m.user_id = safar_uid()
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_proposal_trip(pid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM itinerary_proposals WHERE id = pid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_item_trip(iid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM itinerary_items WHERE id = iid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_expense_trip(eid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM expenses WHERE id = eid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_batch_trip(bid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM recommendation_batches WHERE id = bid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_recommendation_trip(rid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM recommendations WHERE id = rid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_link_creator(lid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM companion_links cl
            WHERE cl.id = lid AND cl.created_by = safar_uid()
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_link_trip(lid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM companion_links WHERE id = lid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_link_allows_trip(tid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM companion_links cl
            WHERE cl.id = safar_companion_link() AND cl.trip_id = tid
              AND cl.revoked_at IS NULL
              AND cl.expires_at > (now() AT TIME ZONE 'UTC')
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_link_allows_target(target text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1 FROM companion_links cl
            WHERE cl.id = safar_companion_link() AND cl.target_id = target
              AND cl.revoked_at IS NULL
              AND cl.expires_at > (now() AT TIME ZONE 'UTC')
        )
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_ground_request_trip(rid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT trip_id FROM ground_requests WHERE id = rid
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_ground_request_destination(rid text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT t.destination_id
        FROM ground_requests gr
        JOIN trips t ON t.id = gr.trip_id
        WHERE gr.id = rid AND t.deleted_at IS NULL
    $$
    """,
    """
    CREATE OR REPLACE FUNCTION safar_can_answer_ground_request(rid text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        SELECT EXISTS (
            SELECT 1
            FROM ground_requests gr
            JOIN trips t ON t.id = gr.trip_id
            JOIN local_contributors lc ON lc.user_id = safar_uid()
              AND lc.accepts_requests
              AND lc.destination_id = t.destination_id
            WHERE gr.id = rid AND t.deleted_at IS NULL
        )
    $$
    """,
]


# table -> {command: expression}
POLICIES = {
    "users": {
        "select": "id = safar_uid() OR safar_admin() OR safar_system() OR safar_auth()"
        " OR safar_shares_trip(id) OR safar_inviter_of_current(id)"
        " OR safar_public_user(id) OR safar_connection_peer(id)"
        " OR safar_block_peer(id)"
        " OR safar_circle_peer(id) OR safar_is_local_contributor(id)",
        "insert": "safar_auth() OR safar_system() OR id = safar_uid()",
        "update": "id = safar_uid() OR safar_admin() OR safar_system()",
        "delete": "safar_admin() OR safar_system()",
    },
    "profiles": {
        "select": "user_id = safar_uid() OR safar_admin() OR safar_system()"
        " OR safar_shares_trip(user_id) OR safar_circle_peer(user_id)"
        " OR safar_public_user(user_id)",
        "insert": "user_id = safar_uid() OR safar_auth() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_admin() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "journey_dna": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_auth() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "consent_records": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_auth() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "auth_sessions": {
        "select": "user_id = safar_uid() OR safar_auth() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_auth() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_auth() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "trips": {
        "select": "safar_is_trip_member(id) OR created_by = safar_uid() OR safar_admin()"
        " OR safar_system() OR safar_is_invited(id) OR safar_invitation_trip(id)"
        " OR safar_link_allows_trip(id)"
        " OR (privacy = 'public' AND safar_uid() IS NOT NULL)",
        "insert": "created_by = safar_uid() OR safar_system()",
        "update": "safar_is_trip_member(id) OR safar_admin() OR safar_system()",
        "delete": "created_by = safar_uid() OR safar_admin() OR safar_system()",
    },
    "trip_members": {
        "select": "safar_is_trip_member(trip_id) OR safar_is_trip_admin(trip_id)"
        " OR user_id = safar_uid() OR safar_admin() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_is_trip_admin(trip_id) OR safar_admin() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_is_trip_admin(trip_id) OR safar_admin() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_is_trip_admin(trip_id) OR safar_admin() OR safar_system()",
    },
    "trip_invitations": {
        "select": "safar_is_trip_admin(trip_id) OR safar_admin() OR safar_system()"
        " OR lower(email) = safar_current_email() OR token = safar_invitation_token()",
        "insert": "safar_is_trip_admin(trip_id) OR safar_system()",
        "update": "safar_is_trip_admin(trip_id) OR safar_system()"
        " OR token = safar_invitation_token()",
        "delete": "safar_is_trip_admin(trip_id) OR safar_system()",
    },
    "itineraries": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "itinerary_items": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()"
        " OR safar_link_allows_target(id)",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "itinerary_versions": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "itinerary_proposals": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()"
        " OR safar_link_allows_target(id)",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "itinerary_approvals": {
        "select": "safar_is_trip_member(safar_proposal_trip(proposal_id)) OR safar_admin() OR safar_system()",
        "insert": "(user_id = safar_uid() AND safar_is_trip_member(safar_proposal_trip(proposal_id)))"
        " OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "activity_votes": {
        "select": "safar_is_trip_member(safar_proposal_trip(proposal_id)) OR safar_admin()"
        " OR safar_system() OR safar_link_allows_target(proposal_id)",
        "insert": "(user_id = safar_uid() AND safar_is_trip_member(safar_proposal_trip(proposal_id)))"
        " OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "itinerary_attendance": {
        "select": "safar_is_trip_member(safar_item_trip(item_id)) OR safar_admin() OR safar_system()",
        "insert": "(user_id = safar_uid() AND safar_is_trip_member(safar_item_trip(item_id)))"
        " OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "trip_pulse": {
        "select": "safar_is_trip_member(trip_id) OR safar_system()",
        "insert": "(user_id = safar_uid() AND safar_is_trip_member(trip_id)) OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "recommendation_batches": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "recommendations": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "recommendation_feedback": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "activity_feedback": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },    "journey_pacts": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "shadowplans": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "journey_capsules": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "material_watch": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "expenses": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "expense_participants": {
        "select": "safar_is_trip_member(safar_expense_trip(expense_id)) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(safar_expense_trip(expense_id)) OR safar_system()",
        "update": "safar_is_trip_member(safar_expense_trip(expense_id)) OR safar_system()",
        "delete": "safar_is_trip_member(safar_expense_trip(expense_id)) OR safar_admin() OR safar_system()",
    },
    "expense_settlements": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "trip_memories": {
        "select": "user_id = safar_uid() OR safar_system()"
        " OR (deleted_at IS NULL AND visibility = 'public')"
        " OR (deleted_at IS NULL AND visibility = 'trip' AND safar_is_trip_member(trip_id))"
        " OR (deleted_at IS NULL AND safar_memory_shared(id))",
        "insert": "(user_id = safar_uid() AND safar_is_trip_member(trip_id)) OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "memory_permissions": {
        "select": "user_id = safar_uid() OR safar_memory_owner(memory_id) OR safar_system()",
        "insert": "safar_memory_owner(memory_id) OR safar_system()",
        "update": "safar_memory_owner(memory_id) OR safar_system()",
        "delete": "safar_memory_owner(memory_id) OR safar_system()",
    },
    "memory_events": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "notifications": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "safar_uid() IS NOT NULL OR safar_system() OR safar_auth()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "saved_inspiration": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "offline_sync_queue": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "travel_circles": {
        "select": "is_public OR created_by = safar_uid() OR safar_circle_member(id)"
        " OR safar_admin() OR safar_system()",
        "insert": "created_by = safar_uid() OR safar_system()",
        "update": "created_by = safar_uid() OR safar_admin() OR safar_system()",
        "delete": "created_by = safar_uid() OR safar_admin() OR safar_system()",
    },
    "circle_members": {
        "select": "user_id = safar_uid() OR safar_circle_member(circle_id)"
        " OR safar_circle_public(circle_id) OR safar_admin() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_circle_admin(circle_id) OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_circle_admin(circle_id) OR safar_system()",
    },
    "circle_posts": {
        "select": "safar_circle_member(circle_id) OR safar_circle_public(circle_id)"
        " OR user_id = safar_uid() OR safar_admin() OR safar_system()",
        "insert": "(user_id = safar_uid() AND (safar_circle_member(circle_id) OR safar_circle_public(circle_id)))"
        " OR safar_system()",
        "update": "user_id = safar_uid() OR safar_admin() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "local_contributors": {
        "select": "safar_uid() IS NOT NULL OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_admin() OR safar_system()",
        "delete": "safar_admin() OR safar_system()",
    },
    "traveller_matches": {
        "select": "user_a_id = safar_uid() OR user_b_id = safar_uid() OR safar_admin() OR safar_system()",
        "insert": "user_a_id = safar_uid() OR safar_system()",
        "update": "user_a_id = safar_uid() OR user_b_id = safar_uid() OR safar_system()",
        "delete": "user_a_id = safar_uid() OR user_b_id = safar_uid() OR safar_system()",
    },
    "connection_requests": {
        "select": "from_user_id = safar_uid() OR to_user_id = safar_uid() OR safar_admin() OR safar_system()",
        "insert": "from_user_id = safar_uid() OR safar_system()",
        "update": "to_user_id = safar_uid() OR from_user_id = safar_uid() OR safar_system()",
        "delete": "from_user_id = safar_uid() OR to_user_id = safar_uid() OR safar_system()",
    },
    "user_blocks": {
        "select": "blocker_id = safar_uid() OR blocked_id = safar_uid()"
        " OR safar_admin() OR safar_system()",
        "insert": "blocker_id = safar_uid() OR safar_system()",
        "update": "blocker_id = safar_uid() OR safar_system()",
        "delete": "blocker_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "abuse_reports": {
        "select": "reporter_id = safar_uid() OR safar_admin() OR safar_system()",
        "insert": "reporter_id = safar_uid() OR safar_system()",
        "update": "safar_admin() OR safar_system()",
        "delete": "safar_admin() OR safar_system()",
    },
    "audit_logs": {
        "select": "safar_admin() OR safar_system()",
        "insert": "safar_uid() IS NOT NULL OR safar_system() OR safar_auth()"
        " OR safar_companion_link() IS NOT NULL",
        "update": "safar_system()",
        "delete": "safar_admin() OR safar_system()",
    },
    "ground_requests": {
        "select": "safar_is_trip_member(trip_id) OR requested_by = safar_uid() OR safar_admin()"
        " OR safar_system() OR safar_can_answer_ground_request(id)",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "requested_by = safar_uid() OR safar_is_trip_member(trip_id)"
        " OR safar_system() OR safar_can_answer_ground_request(id)",
        "delete": "requested_by = safar_uid() OR safar_admin() OR safar_system()",
    },
    "ground_responses": {
        "select": "safar_is_trip_member(safar_ground_request_trip(request_id))"
        " OR contributor_id = safar_uid() OR safar_admin() OR safar_system()",
        "insert": "contributor_id = safar_uid() OR safar_system()",
        "update": "contributor_id = safar_uid() OR safar_system()",
        "delete": "contributor_id = safar_uid() OR safar_system()",
    },
    "planner_tasks": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "trip_branches": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "trip_missions": {
        "select": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
        "insert": "safar_is_trip_member(trip_id) OR safar_system()",
        "update": "safar_is_trip_member(trip_id) OR safar_system()",
        "delete": "safar_is_trip_member(trip_id) OR safar_admin() OR safar_system()",
    },
    "user_missions": {
        "select": "user_id = safar_uid() OR safar_system()",
        "insert": "user_id = safar_uid() OR safar_system()",
        "update": "user_id = safar_uid() OR safar_system()",
        "delete": "user_id = safar_uid() OR safar_system()",
    },
    "place_reports": {
        "select": "true",
        "insert": "reporter_id = safar_uid() OR safar_system()",
        "update": "reporter_id = safar_uid() OR safar_admin() OR safar_system()",
        "delete": "reporter_id = safar_uid() OR safar_admin() OR safar_system()",
    },
    "companion_links": {
        "select": "created_by = safar_uid() OR safar_is_trip_admin(trip_id)"
        " OR safar_admin() OR safar_system() OR id = safar_companion_link()",
        "insert": "created_by = safar_uid() OR safar_system()",
        "update": "created_by = safar_uid() OR safar_is_trip_admin(trip_id)"
        " OR safar_system() OR id = safar_companion_link()",
        "delete": "created_by = safar_uid() OR safar_admin() OR safar_system()",
    },
    "companion_responses": {
        "select": "link_id = safar_companion_link() OR safar_link_creator(link_id)"
        " OR safar_is_trip_admin(safar_link_trip(link_id)) OR safar_admin() OR safar_system()",
        "insert": "link_id = safar_companion_link() OR safar_system()",
        "update": "safar_system()",
        "delete": "safar_admin() OR safar_system()",
    },
}

# Public catalog: readable by anyone, writable only by admin/system.
CATALOG = ("destinations", "places", "activities", "place_sources")


def _create_policies() -> None:
    for sql in HELPERS:
        op.execute(sql)
    for table, commands in POLICIES.items():
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY")
        for command, expression in commands.items():
            if command == "insert":
                op.execute(
                    f"CREATE POLICY p_{table}_insert ON {table} FOR INSERT "
                    f"WITH CHECK ({expression})"
                )
                continue
            check = f" WITH CHECK ({expression})" if command == "update" else ""
            op.execute(
                f"CREATE POLICY p_{table}_{command} ON {table} FOR {command.upper()} "
                f"USING ({expression}){check}"
            )
    for table in CATALOG:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY")
        op.execute(f"CREATE POLICY p_{table}_select ON {table} FOR SELECT USING (true)")
        for command in ("insert", "update", "delete"):
            clause = "USING" if command == "delete" else "WITH CHECK"
            op.execute(
                f"CREATE POLICY p_{table}_{command} ON {table} FOR {command.upper()} "
                f"{clause} (safar_admin() OR safar_system())"
            )
    # Membership lookups are on the hot path for almost every policy.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_trip_members_user_status "
        "ON trip_members (user_id, status)"
    )


def _drop_policies() -> None:
    op.execute("DROP INDEX IF EXISTS ix_trip_members_user_status")
    for table in list(POLICIES) + list(CATALOG):
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")
        for command in ("select", "insert", "update", "delete"):
            op.execute(f"DROP POLICY IF EXISTS p_{table}_{command} ON {table}")
    for sql in reversed(HELPERS):
        name = sql.split("FUNCTION ", 1)[1].split("(", 1)[0].strip()
        op.execute(f"DROP FUNCTION IF EXISTS {name} CASCADE")


def upgrade() -> None:
    if op.get_bind().dialect.name != "postgresql":
        return
    _create_policies()


def downgrade() -> None:
    if op.get_bind().dialect.name != "postgresql":
        return
    _drop_policies()
