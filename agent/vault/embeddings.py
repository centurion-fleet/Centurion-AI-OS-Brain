"""Offline embedding backends for Vault. No cloud APIs."""

from __future__ import annotations

import hashlib
import logging
import math
import struct
from typing import Optional, Protocol

logger = logging.getLogger(__name__)

STUB_MODEL_ID = "stub-hash-v1"
STUB_DIM = 64


class Embedder(Protocol):
    model_id: str
    dim: int

    def embed(self, text: str) -> list[float]:
        ...


class StubEmbedder:
    """Deterministic hash→vector embedder for tests and offline fallback."""

    model_id = STUB_MODEL_ID
    dim = STUB_DIM

    def embed(self, text: str) -> list[float]:
        digest = hashlib.sha256(text.strip().encode("utf-8")).digest()
        # Expand digest into dim floats in [-1, 1]
        values: list[float] = []
        seed = digest
        while len(values) < self.dim:
            for i in range(0, len(seed), 4):
                if len(values) >= self.dim:
                    break
                chunk = seed[i : i + 4]
                if len(chunk) < 4:
                    chunk = chunk + b"\x00" * (4 - len(chunk))
                (n,) = struct.unpack(">I", chunk)
                values.append((n / 0xFFFFFFFF) * 2.0 - 1.0)
            seed = hashlib.sha256(seed).digest()
        return _l2_normalize(values)


def get_embedder(model_path: Optional[str] = None) -> Embedder:
    """Return best available offline embedder.

    Tries llama-cpp-python GGUF if model_path exists; otherwise StubEmbedder.
    Never calls cloud embedding APIs.
    """
    if model_path:
        try:
            return LlamaCppEmbedder(model_path)
        except Exception as exc:
            logger.info("Vault: llama-cpp embedder unavailable (%s); using stub", exc)
    return StubEmbedder()


class LlamaCppEmbedder:
    """Optional in-process GGUF embedder via llama-cpp-python."""

    def __init__(self, model_path: str):
        from llama_cpp import Llama  # type: ignore

        self.model_id = f"llamacpp:{model_path}"
        self._llm = Llama(
            model_path=model_path,
            embedding=True,
            verbose=False,
            n_ctx=512,
        )
        # Probe dim
        probe = self._llm.create_embedding("probe")
        self.dim = len(probe["data"][0]["embedding"])

    def embed(self, text: str) -> list[float]:
        result = self._llm.create_embedding(text.strip() or " ")
        vec = list(result["data"][0]["embedding"])
        return _l2_normalize(vec)


def cosine(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def _l2_normalize(vec: list[float]) -> list[float]:
    norm = math.sqrt(sum(x * x for x in vec))
    if norm == 0:
        return vec
    return [x / norm for x in vec]
