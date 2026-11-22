"""Capability registry.

Reports what is configured without ever exposing a credential. The frontend
uses this to describe the assistant truthfully instead of claiming AI it does
not have.
"""

from app.integrations import base, links, ocr, weather
from app.services.language import LANGUAGE_NAMES, SUPPORTED_LANGUAGES

TRANSLATION_LANGUAGES = SUPPORTED_LANGUAGES


def capabilities() -> dict:
    weather_status = weather.status()
    link_status = links.status()
    ocr_status = ocr.status()
    return {
        "generated_at": base.now().isoformat(),
        "providers": {
            "weather": weather_status,
            "link_metadata": link_status,
            "ocr": ocr_status,
            "translation": {
                "mode": "local-templates",
                "enabled": True,
                "network": False,
                "languages": list(TRANSLATION_LANGUAGES),
                "language_names": LANGUAGE_NAMES,
                "notes": [
                    "Intent detection and response templates run in-process.",
                    "No message text is sent to a translation vendor.",
                ],
            },
            "llm": {
                "enabled": False,
                "provider": None,
                "note": (
                    "No LLM is wired. The assistant is deterministic grounded retrieval. "
                    "Setting OPENAI_API_KEY does not enable it."
                ),
            },
            "email": {
                "enabled": False,
                "note": "Notifications are in-app only on this deployment.",
            },
            "storage": {
                "enabled": True,
                "mode": "signed-local-url",
                "note": "Uploads stay on this deployment behind expiring signatures.",
            },
        },
        "default_external_ai_calls": False,
        "external_network_used": bool(
            weather_status["enabled"] or link_status["enabled"]
        ),
        "outbound_data": (
            "Rounded coordinates for weather, and page URLs for link reading, "
            "only when those providers are enabled. No user identifier, message, "
            "preference or budget is sent."
        ),
    }
