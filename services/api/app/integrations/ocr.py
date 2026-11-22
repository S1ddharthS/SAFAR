"""Local OCR adapter.

Tesseract runs on this server; images are never uploaded to a third party.
The adapter reports itself unavailable when the binary is missing, which is the
honest state rather than a simulated result.
"""

import shutil
from functools import lru_cache
from pathlib import Path

from app.core.config import settings
from app.integrations import base
from app.integrations.base import ProviderResult

PROVIDER = "tesseract"
_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
_MAX_TEXT = 4000
_WINDOWS_PATHS = (
    Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
    Path(r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"),
)


@lru_cache(maxsize=1)
def binary() -> str | None:
    if not settings.ocr_enabled:
        return None
    found = shutil.which("tesseract")
    if found:
        return found
    for candidate in _WINDOWS_PATHS:
        if candidate.is_file():
            return str(candidate)
    return None


def reset() -> None:
    binary.cache_clear()


def available() -> bool:
    return binary() is not None


def status() -> dict:
    installed = binary() is not None
    if not settings.ocr_enabled:
        message = "OCR is disabled by configuration."
    elif not installed:
        message = "The Tesseract binary is not installed on this server."
    else:
        message = "Machine-read text from images stored on this server."
    return {
        "provider": PROVIDER,
        "enabled": installed,
        "installed": installed,
        "network": False,
        "provenance": base.ESTIMATED,
        "message": message,
        "notes": ["Images are processed locally and never uploaded."],
    }


def extract_text(path: Path) -> ProviderResult:
    if not settings.ocr_enabled:
        return base.unavailable(PROVIDER, "OCR is disabled by configuration.")
    executable = binary()
    if not executable:
        return base.unavailable(
            PROVIDER,
            "OCR is not installed on this server, so the image was not analysed.",
        )
    if path.suffix.lower() not in _IMAGE_SUFFIXES:
        return base.failed(PROVIDER, "unsupported_image", "OCR supports PNG, JPEG and WebP images.")
    try:
        size = path.stat().st_size
    except OSError:
        return base.failed(PROVIDER, "missing_file", "The image could not be opened.")
    if size > settings.ocr_max_image_bytes:
        return base.failed(PROVIDER, "image_too_large", "The image is too large to read.")
    try:
        import pytesseract
        from PIL import Image

        pytesseract.pytesseract.tesseract_cmd = executable
        text = pytesseract.image_to_string(Image.open(path), lang="eng", timeout=20)
    except Exception:
        return base.failed(PROVIDER, "ocr_failed", "The image could not be read by OCR.")
    cleaned = " ".join((text or "").split())[:_MAX_TEXT]
    if not cleaned:
        return base.failed(PROVIDER, "no_text", "No readable text was found in the image.")
    return ProviderResult(
        ok=True,
        provider=PROVIDER,
        data={"text": cleaned, "characters": len(cleaned)},
        provenance=base.ESTIMATED,
        fetched_at=base.now(),
        message="Machine-read from your image. OCR can misread text; confirm every candidate.",
    )
