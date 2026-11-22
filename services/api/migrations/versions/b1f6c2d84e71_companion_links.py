"""companion links for one-link companion (F26)

Revision ID: b1f6c2d84e71
Revises: 9c224ee10414
Create Date: 2026-11-19 20:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b1f6c2d84e71'
down_revision: Union[str, Sequence[str], None] = '9c224ee10414'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'companion_links',
        sa.Column('id', sa.String(length=32), nullable=False),
        sa.Column('trip_id', sa.String(length=32), nullable=False),
        sa.Column('created_by', sa.String(length=32), nullable=False),
        sa.Column('purpose', sa.String(length=20), nullable=False),
        sa.Column('target_id', sa.String(length=64), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('max_uses', sa.Integer(), nullable=False),
        sa.Column('used_count', sa.Integer(), nullable=False),
        sa.Column('revoked_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['created_by'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['trip_id'], ['trips.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    with op.batch_alter_table('companion_links', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_companion_links_trip'), ['trip_id', 'created_at'], unique=False)
        batch_op.create_index(batch_op.f('ix_companion_links_trip_id'), ['trip_id'], unique=False)

    op.create_table(
        'companion_responses',
        sa.Column('id', sa.String(length=32), nullable=False),
        sa.Column('link_id', sa.String(length=32), nullable=False),
        sa.Column('value', sa.String(length=20), nullable=False),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['link_id'], ['companion_links.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    with op.batch_alter_table('companion_responses', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_companion_responses_link'), ['link_id', 'created_at'], unique=False)
        batch_op.create_index(batch_op.f('ix_companion_responses_link_id'), ['link_id'], unique=False)


def downgrade() -> None:
    with op.batch_alter_table('companion_responses', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_companion_responses_link_id'))
        batch_op.drop_index(batch_op.f('ix_companion_responses_link'))
    op.drop_table('companion_responses')
    with op.batch_alter_table('companion_links', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_companion_links_trip_id'))
        batch_op.drop_index(batch_op.f('ix_companion_links_trip'))
    op.drop_table('companion_links')
