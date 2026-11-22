"""Provider capability disclosure (no keys, no trip data)."""

from fastapi import APIRouter

from app.integrations.registry import capabilities

router = APIRouter(prefix="/api/ai", tags=["intelligence"])


@router.get("/capabilities")
def ai_capabilities():
    return capabilities()
