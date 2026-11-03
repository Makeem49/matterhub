"""Request/response schemas. ``extra="forbid"`` rejects unexpected fields (mass-assignment)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from matterhub.models import Classification, MatterStatus, PracticeArea


class MatterCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str = Field(min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    client_department: str = Field(min_length=2, max_length=120)
    practice_area: PracticeArea
    classification: Classification = Classification.OFFICIAL
    owner: str = Field(min_length=3, max_length=200)


class MatterUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str | None = Field(default=None, min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    status: MatterStatus | None = None
    owner: str | None = Field(default=None, min_length=3, max_length=200)


class MatterRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reference: str
    title: str
    description: str | None
    client_department: str
    practice_area: PracticeArea
    status: MatterStatus
    classification: Classification
    owner: str
    opened_at: datetime
    closed_at: datetime | None
    retention_until: date | None
    created_by: str
    updated_at: datetime


class MatterPage(BaseModel):
    items: list[MatterRead]
    total: int
    limit: int
    offset: int


class AuditEventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    action: str
    actor: str
    occurred_at: datetime
    details: dict[str, Any]


class VersionInfo(BaseModel):
    version: str
    git_sha: str
    environment: str
