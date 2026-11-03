"""ORM models.

Legal records are never hard-deleted. Every change is written to an append-only
audit table, and closed matters get a retention date that the retention CronJob
uses to flag them for review.
"""

from __future__ import annotations

import enum
import uuid
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import JSON, BigInteger, Date, DateTime, Enum, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from matterhub.db import Base


def utcnow() -> datetime:
    return datetime.now(UTC)


class MatterStatus(enum.StrEnum):
    OPEN = "open"
    ON_HOLD = "on_hold"
    CLOSED = "closed"


class PracticeArea(enum.StrEnum):
    LITIGATION = "litigation"
    EMPLOYMENT = "employment"
    COMMERCIAL = "commercial"
    PUBLIC_LAW = "public_law"
    REGULATORY = "regulatory"


class Classification(enum.StrEnum):
    """UK Government Security Classifications (subset)."""

    OFFICIAL = "OFFICIAL"
    OFFICIAL_SENSITIVE = "OFFICIAL-SENSITIVE"


def _enum(enum_cls: type[enum.Enum], name: str) -> Enum:
    # Stored as VARCHAR (not a native PG enum) so adding values is a simple migration.
    return Enum(
        enum_cls,
        name=name,
        native_enum=False,
        length=32,
        values_callable=lambda members: [m.value for m in members],
    )


class Matter(Base):
    __tablename__ = "matters"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    reference: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text, default=None)
    client_department: Mapped[str] = mapped_column(String(120), index=True)
    practice_area: Mapped[PracticeArea] = mapped_column(_enum(PracticeArea, "practice_area"))
    status: Mapped[MatterStatus] = mapped_column(
        _enum(MatterStatus, "matter_status"), default=MatterStatus.OPEN, index=True
    )
    classification: Mapped[Classification] = mapped_column(
        _enum(Classification, "classification"), default=Classification.OFFICIAL
    )
    owner: Mapped[str] = mapped_column(String(200))
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    retention_until: Mapped[date | None] = mapped_column(Date, default=None, index=True)
    retention_flagged_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    created_by: Mapped[str] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True
    )
    matter_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matters.id"), index=True)
    action: Mapped[str] = mapped_column(String(32))
    actor: Mapped[str] = mapped_column(String(200))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    details: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
