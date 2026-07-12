"""FastAPI server for Adrian — Centurion-operated support guide endpoint."""

from __future__ import annotations

import logging
import os

from centurion_cli import __version__
from centurion_cli.adrian.service import AdrianChatRequest, AdrianChatResponse, chat

logger = logging.getLogger(__name__)

try:
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse
    from pydantic import BaseModel, Field
except ImportError:
    FastAPI = None  # type: ignore[misc, assignment]


class AdrianMessageModel(BaseModel):
    role: str
    content: str


class AdrianContextModel(BaseModel):
    app_version: str = ""
    connection_state: str = "disconnected"
    thinking_health: str = "unknown"
    thinking_message: str = ""
    has_mission: bool = False
    active_target_count: int = 0
    mission_summary: str = ""
    support_code: str = ""


class AdrianChatPayload(BaseModel):
    install_id: str = Field(..., min_length=8, max_length=64)
    messages: list[AdrianMessageModel] = Field(default_factory=list)
    context: AdrianContextModel = Field(default_factory=AdrianContextModel)


def create_app() -> FastAPI:
    if FastAPI is None:
        raise SystemExit(
            "Adrian server requires fastapi and uvicorn. "
            "Install with: pip install fastapi 'uvicorn[standard]'"
        )

    app = FastAPI(title="Centurion Adrian", version=__version__)

    origins = (
        os.getenv("CENTURION_ADRIAN_CORS_ORIGINS")
        or os.getenv("CENTURION_HERALD_CORS_ORIGINS", "*")
    ).split(",")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in origins if o.strip()],
        allow_credentials=True,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
    )

    @app.get("/health")
    async def health() -> dict:
        return {"ok": True, "service": "adrian", "version": __version__}

    @app.post("/v1/chat")
    async def adrian_chat(payload: AdrianChatPayload, request: Request) -> JSONResponse:
        server_key = (
            os.getenv("CENTURION_ADRIAN_SERVER_KEY")
            or os.getenv("CENTURION_HERALD_SERVER_KEY")
            or ""
        ).strip()
        if server_key:
            header = request.headers.get("X-Centurion-Adrian-Key", "") or request.headers.get(
                "X-Centurion-Herald-Key", ""
            )
            if not header or header != server_key:
                raise HTTPException(status_code=401, detail="Unauthorized")

        req = AdrianChatRequest.from_payload(payload.model_dump())
        result: AdrianChatResponse = chat(req)
        status = 200 if result.ok else 429 if "limit" in result.message.lower() else 400
        return JSONResponse(content=result.to_dict(), status_code=status)

    return app


app = create_app() if FastAPI is not None else None


def serve(host: str = "0.0.0.0", port: int = 9120) -> None:
    if FastAPI is None:
        raise SystemExit("fastapi is required to run Adrian server")
    import uvicorn

    uvicorn.run(
        "centurion_cli.adrian.server:app",
        host=host,
        port=port,
        log_level=os.getenv("CENTURION_ADRIAN_LOG_LEVEL")
        or os.getenv("CENTURION_HERALD_LOG_LEVEL", "info"),
    )
