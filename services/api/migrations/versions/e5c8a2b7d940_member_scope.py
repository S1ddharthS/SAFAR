"""Persist invitation scope on trip members

Revision ID: e5c8a2b7d940
Revises: d9e4f1b2c305
Create Date: 2026-11-21
"""

import sqlalchemy as sa
from alembic import op

revision = "e5c8a2b7d940"
down_revision = "d9e4f1b2c305"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "trip_members",
        sa.Column("scope", sa.String(length=20), nullable=False, server_default="full"),
    )


def downgrade() -> None:
    op.drop_column("trip_members", "scope")
