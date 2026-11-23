"""Add trip_type to trips and safety tables for solo travel

Revision ID: f1a2b3c4d5e6
Revises: e5c8a2b7d940
Create Date: 2026-11-22
"""

import sqlalchemy as sa
from alembic import op

revision = "f1a2b3c4d5e6"
down_revision = "e5c8a2b7d940"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add trip_type to trips with server_default='group'
    op.add_column(
        "trips",
        sa.Column("trip_type", sa.String(length=20), nullable=False, server_default="group"),
    )

    # 2. Create emergency_contacts table
    op.create_table(
        "emergency_contacts",
        sa.Column("id", sa.String(length=32), primary_key=True),
        sa.Column(
            "trip_id",
            sa.String(length=32),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "user_id",
            sa.String(length=32),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("relationship", sa.String(length=60), nullable=False, server_default="Contact"),
        sa.Column("phone", sa.String(length=40), nullable=False),
        sa.Column("email", sa.String(length=120), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # 3. Create trip_check_ins table
    op.create_table(
        "trip_check_ins",
        sa.Column("id", sa.String(length=32), primary_key=True),
        sa.Column(
            "trip_id",
            sa.String(length=32),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "user_id",
            sa.String(length=32),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("status", sa.String(length=30), nullable=False, server_default="safe"),
        sa.Column("location_name", sa.String(length=160), nullable=True),
        sa.Column("lat", sa.Float(), nullable=True),
        sa.Column("lon", sa.Float(), nullable=True),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # 4. Create solo_safety_settings table
    op.create_table(
        "solo_safety_settings",
        sa.Column(
            "trip_id",
            sa.String(length=32),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("check_in_frequency_hours", sa.Integer(), nullable=False, server_default="24"),
        sa.Column("last_check_in_at", sa.DateTime(), nullable=True),
        sa.Column("next_check_in_due", sa.DateTime(), nullable=True),
        sa.Column("location_sharing_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("share_token", sa.String(length=64), nullable=True, unique=True, index=True),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("solo_safety_settings")
    op.drop_table("trip_check_ins")
    op.drop_table("emergency_contacts")
    op.drop_column("trips", "trip_type")
