"""Initial schema: matters and audit_events.

Revision ID: 0001
Revises:
Create Date: 2026-11-03
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _enum(name: str, *values: str) -> sa.Enum:
    return sa.Enum(*values, name=name, native_enum=False, length=32)


def upgrade() -> None:
    op.create_table(
        "matters",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("reference", sa.String(32), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("client_department", sa.String(120), nullable=False),
        sa.Column(
            "practice_area",
            _enum(
                "practice_area",
                "litigation",
                "employment",
                "commercial",
                "public_law",
                "regulatory",
            ),
            nullable=False,
        ),
        sa.Column("status", _enum("matter_status", "open", "on_hold", "closed"), nullable=False),
        sa.Column(
            "classification",
            _enum("classification", "OFFICIAL", "OFFICIAL-SENSITIVE"),
            nullable=False,
        ),
        sa.Column("owner", sa.String(200), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("retention_until", sa.Date(), nullable=True),
        sa.Column("retention_flagged_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by", sa.String(200), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_matters_reference", "matters", ["reference"], unique=True)
    op.create_index("ix_matters_client_department", "matters", ["client_department"])
    op.create_index("ix_matters_status", "matters", ["status"])
    op.create_index("ix_matters_retention_until", "matters", ["retention_until"])

    op.create_table(
        "audit_events",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            primary_key=True,
            autoincrement=True,
        ),
        sa.Column("matter_id", sa.Uuid(), sa.ForeignKey("matters.id"), nullable=False),
        sa.Column("action", sa.String(32), nullable=False),
        sa.Column("actor", sa.String(200), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("details", sa.JSON(), nullable=False),
    )
    op.create_index("ix_audit_events_matter_id", "audit_events", ["matter_id"])


def downgrade() -> None:
    op.drop_index("ix_audit_events_matter_id", table_name="audit_events")
    op.drop_table("audit_events")
    op.drop_index("ix_matters_retention_until", table_name="matters")
    op.drop_index("ix_matters_status", table_name="matters")
    op.drop_index("ix_matters_client_department", table_name="matters")
    op.drop_index("ix_matters_reference", table_name="matters")
    op.drop_table("matters")
