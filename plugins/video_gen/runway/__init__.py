"""Runway Gen-4 video generation backend."""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional

from agent.video_gen_provider import VideoGenProvider, error_response, success_response

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "gen-4"
_API_BASE = "https://api.runwayml.com/v1"


class RunwayVideoGenProvider(VideoGenProvider):
    @property
    def name(self) -> str:
        return "runway"

    @property
    def display_name(self) -> str:
        return "Runway"

    def is_available(self) -> bool:
        return bool(os.environ.get("RUNWAY_API_KEY"))

    def list_models(self) -> List[Dict[str, Any]]:
        return [
            {
                "id": DEFAULT_MODEL,
                "display": "Runway Gen-4",
                "speed": "~2-5min",
                "strengths": "Cinematic video ads and storyboards",
                "price": "premium",
            }
        ]

    def default_model(self) -> Optional[str]:
        return DEFAULT_MODEL

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "Runway",
            "badge": "paid",
            "tag": "Gen-4 text-to-video",
            "env_vars": [
                {
                    "key": "RUNWAY_API_KEY",
                    "prompt": "Runway API key",
                    "url": "https://runwayml.com/",
                },
            ],
        }

    def generate(
        self,
        prompt: str,
        aspect_ratio: str = "16:9",
        image_url: str = "",
        duration: int = 5,
        **kwargs: Any,
    ) -> Dict[str, Any]:
        prompt = (prompt or "").strip()
        if not prompt:
            return error_response(
                error="Prompt is required.",
                error_type="invalid_argument",
                provider=self.name,
            )
        if not os.environ.get("RUNWAY_API_KEY"):
            return error_response(
                error="RUNWAY_API_KEY not set.",
                error_type="auth_required",
                provider=self.name,
            )
        try:
            import httpx
        except ImportError:
            return error_response(
                error="httpx is required for Runway video generation.",
                error_type="missing_dependency",
                provider=self.name,
            )

        headers = {
            "Authorization": f"Bearer {os.environ['RUNWAY_API_KEY']}",
            "Content-Type": "application/json",
            "X-Runway-Version": "2024-11-06",
        }
        body = {
            "model": DEFAULT_MODEL,
            "promptText": prompt,
            "ratio": aspect_ratio or "16:9",
            "duration": max(2, min(int(duration or 5), 10)),
        }
        if image_url:
            body["promptImage"] = image_url

        try:
            with httpx.Client(timeout=300.0) as client:
                create = client.post(f"{_API_BASE}/tasks", headers=headers, json=body)
                create.raise_for_status()
                task_id = create.json().get("id")
                if not task_id:
                    return error_response(
                        error="Runway did not return a task id.",
                        error_type="api_error",
                        provider=self.name,
                    )
                for _ in range(120):
                    poll = client.get(f"{_API_BASE}/tasks/{task_id}", headers=headers)
                    poll.raise_for_status()
                    payload = poll.json()
                    status = str(payload.get("status") or "").upper()
                    if status in {"SUCCEEDED", "COMPLETED"}:
                        output = payload.get("output") or payload.get("artifacts") or []
                        video_url = ""
                        if isinstance(output, list) and output:
                            first = output[0]
                            if isinstance(first, dict):
                                video_url = str(first.get("url") or first.get("uri") or "")
                            else:
                                video_url = str(first)
                        if not video_url:
                            return error_response(
                                error="Runway completed without a video URL.",
                                error_type="empty_response",
                                provider=self.name,
                            )
                        return success_response(
                            video=video_url,
                            model=DEFAULT_MODEL,
                            prompt=prompt,
                            modality="image" if image_url else "text",
                            aspect_ratio=aspect_ratio,
                            duration=int(duration or 5),
                            provider=self.name,
                        )
                    if status in {"FAILED", "CANCELLED"}:
                        return error_response(
                            error=f"Runway task failed ({status}).",
                            error_type="api_error",
                            provider=self.name,
                        )
                    import time

                    time.sleep(2.0)
        except Exception as exc:
            logger.debug("Runway video generation failed", exc_info=True)
            return error_response(
                error=f"Runway video generation failed: {exc}",
                error_type="api_error",
                provider=self.name,
            )

        return error_response(
            error="Runway video generation timed out.",
            error_type="timeout",
            provider=self.name,
        )


def register(ctx) -> None:
    ctx.register_video_gen_provider(RunwayVideoGenProvider())
