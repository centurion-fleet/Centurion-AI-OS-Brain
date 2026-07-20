"""Vault types — Core Facts, Experiential Memory, Pattern Memory."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional


class MemoryType(str, Enum):
    CORE = "core"
    EXPERIENTIAL = "experiential"
    PATTERN = "pattern"

    @classmethod
    def parse(cls, value: str) -> "MemoryType":
        normalized = (value or "").strip().lower()
        try:
            return cls(normalized)
        except ValueError as exc:
            raise ValueError(
                f"Invalid memory_type {value!r}; expected core|experiential|pattern"
            ) from exc


class ProposalStatus(str, Enum):
    PENDING = "pending"
    COMMITTED = "committed"
    REJECTED = "rejected"


@dataclass
class VaultEntry:
    id: str
    memory_type: MemoryType
    text: str
    rationale: str = ""
    tags: list[str] = field(default_factory=list)
    importance: int = 5
    created_at: str = ""
    updated_at: str = ""
    source_session: Optional[str] = None
    content_hash: str = ""
    refs: dict[str, Any] = field(default_factory=dict)

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "memory_type": self.memory_type.value,
            "text": self.text,
            "rationale": self.rationale,
            "tags": list(self.tags),
            "importance": self.importance,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "source_session": self.source_session,
            "content_hash": self.content_hash,
            "refs": dict(self.refs),
        }


@dataclass
class VaultProposal:
    id: str
    memory_type: MemoryType
    text: str
    rationale: str = ""
    tags: list[str] = field(default_factory=list)
    importance: int = 5
    status: ProposalStatus = ProposalStatus.PENDING
    created_at: str = ""
    decided_at: Optional[str] = None
    content_hash: str = ""
    source_session: Optional[str] = None

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "memory_type": self.memory_type.value,
            "text": self.text,
            "rationale": self.rationale,
            "tags": list(self.tags),
            "importance": self.importance,
            "status": self.status.value,
            "created_at": self.created_at,
            "decided_at": self.decided_at,
            "content_hash": self.content_hash,
            "source_session": self.source_session,
        }


@dataclass
class SearchHit:
    id: str
    memory_type: MemoryType
    text: str
    score: float
    snippet: str
    created_at: str = ""
    importance: int = 5

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "memory_type": self.memory_type.value,
            "text": self.text,
            "snippet": self.snippet,
            "score": round(self.score, 4),
            "created_at": self.created_at,
            "importance": self.importance,
        }
