"""Hybrid FTS5 + local semantic search for Vault."""

from __future__ import annotations

from typing import Optional

from agent.vault.embeddings import Embedder, cosine
from agent.vault.store import VaultStore
from agent.vault.types import MemoryType, SearchHit


def hybrid_search(
    store: VaultStore,
    embedder: Embedder,
    query: str,
    *,
    memory_type: Optional[MemoryType] = None,
    limit: int = 8,
    fts_weight: float = 0.4,
    semantic_weight: float = 0.6,
) -> list[SearchHit]:
    """Rank Vault entries by fused BM25 + cosine similarity."""
    if not query.strip():
        return []

    fts_hits = {
        eid: (snip, score)
        for eid, snip, score in store.fts_search(
            query, memory_type=memory_type, limit=max(limit * 3, 16)
        )
    }

    qvec = embedder.embed(query)
    semantic_scores: dict[str, float] = {}
    for eid, vec, _model in store.all_embeddings():
        semantic_scores[eid] = max(0.0, cosine(qvec, vec))

    # Candidate union
    candidate_ids = set(fts_hits) | set(semantic_scores)
    if memory_type:
        typed = {
            r["id"]
            for r in store.list_entry_ids(memory_type)
        }
        candidate_ids &= typed

    scored: list[tuple[str, float, str]] = []
    for eid in candidate_ids:
        fts_score = fts_hits.get(eid, ("", 0.0))[1]
        snip = fts_hits.get(eid, ("", 0.0))[0]
        sem = semantic_scores.get(eid, 0.0)
        fused = fts_weight * fts_score + semantic_weight * sem
        scored.append((eid, fused, snip))

    scored.sort(key=lambda t: t[1], reverse=True)
    hits: list[SearchHit] = []
    for eid, score, snip in scored[:limit]:
        entry = store.get_entry(eid)
        if not entry:
            continue
        snippet = snip or entry.text[:120]
        hits.append(
            SearchHit(
                id=entry.id,
                memory_type=entry.memory_type,
                text=entry.text,
                score=score,
                snippet=snippet,
                created_at=entry.created_at,
                importance=entry.importance,
            )
        )
    return hits
