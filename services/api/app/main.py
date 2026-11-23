"""SAFAR API entrypoint."""

import re
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.core.config import settings
from app.core.logging import configure_logging, install_error_monitor
from app.core.middleware import BodySizeLimitMiddleware, RequestContextMiddleware
from app.core.ratelimit import RateLimitMiddleware
from app.db.session import Base, SessionLocal, check_db_readiness, engine
from app.services.assistant import GENERATOR as ASSISTANT_VERSION
from app.services.engine import ENGINE_VERSION
from app.services.media import verify_media_request
from app.routers import (
    admin,
    assistant,
    auth,
    companion,
    engine as engine_router,
    expenses,
    intelligence,
    itinerary,
    memories,
    opportunity,
    places,
    pulse,
    safety,
    trips,
    users,
    ws,
)

MEDIA_DIR = settings.storage_dir

configure_logging()
install_error_monitor()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Development and tests let SQLAlchemy create the schema. Production must
    # run `alembic upgrade head` first so schema changes are versioned.
    if settings.create_schema:
        Base.metadata.create_all(bind=engine)
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    if settings.auto_seed:
        from app.db.context import system_context
        from app.seed import seed_if_needed

        db = SessionLocal()
        try:
            with system_context(db):
                seed_if_needed(db)
        finally:
            db.close()
    yield


app = FastAPI(
    title="SAFAR API",
    description=(
        "The Living Journey Network — journey intelligence, group decisions and shared memories. "
        "The engine recommends; the group decides."
    ),
    version="1.0.0",
    docs_url="/api/docs" if settings.api_docs_enabled else None,
    redoc_url=None,
    openapi_url="/api/openapi.json" if settings.api_docs_enabled else None,
    lifespan=lifespan,
)

# Middleware order: the last registered middleware runs first. Request context
# is outermost so every response (including limiter rejections) carries the
# request id and security headers.
app.add_middleware(GZipMiddleware, minimum_size=1024)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Accept",
        "X-Requested-With",
        "X-CSRF-Token",
        settings.request_id_header,
    ],
    expose_headers=[settings.request_id_header],
)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.trusted_hosts)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(BodySizeLimitMiddleware)
app.add_middleware(RequestContextMiddleware)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(trips.router)
app.include_router(trips.invitations_router)
app.include_router(itinerary.router)
app.include_router(pulse.router)
app.include_router(engine_router.router)
app.include_router(expenses.router)
app.include_router(places.router)
app.include_router(memories.router)
app.include_router(assistant.router)
app.include_router(assistant.trip_router)
app.include_router(intelligence.router)
app.include_router(admin.router)
app.include_router(companion.router)
app.include_router(companion.public_router)
app.include_router(safety.router)
app.include_router(safety.public_router)
app.include_router(opportunity.router)
app.include_router(ws.router)

MEDIA_DIR.mkdir(parents=True, exist_ok=True)
TRIP_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
MEDIA_NAME_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")


@app.get("/media/{trip_id}/{filename}")
def media_file(trip_id: str, filename: str, request: Request):
    """Serve trip media only with an unexpired HMAC signature."""
    if not TRIP_ID_PATTERN.match(trip_id) or not MEDIA_NAME_PATTERN.match(filename):
        raise HTTPException(status_code=404, detail="Media not found")
    path = f"/media/{trip_id}/{filename}"
    if not verify_media_request(path, dict(request.query_params)):
        raise HTTPException(status_code=403, detail="Media link is missing or expired")
    candidate = (MEDIA_DIR / trip_id / filename).resolve()
    if MEDIA_DIR.resolve() not in candidate.parents or not candidate.is_file():
        raise HTTPException(status_code=404, detail="Media not found")
    return FileResponse(candidate)


@app.get("/")
def root():
    return {
        "product": "SAFAR",
        "positioning": "The Living Journey Network",
        "tagline": "Every Person. Every Moment. One Intelligent Journey.",
        "version": "1.0.0",
        "docs": "/api/docs",
        "health": "/api/health",
        "rule": "The engine recommends. The group decides.",
    }


@app.get("/api/health")
def health():
    db_check = check_db_readiness()
    database = db_check["status"]
    return {
        "status": "ok" if database == "ok" else "degraded",
        "database": database,
        "version": settings.release,
        "engine": ENGINE_VERSION,
        "assistant": ASSISTANT_VERSION,
        # No external AI call is wired into any service. Setting OPENAI_API_KEY
        # does not change behaviour, so health must not imply otherwise.
        "external_ai": False,
    }


@app.get("/api/ready")
def ready():
    """Readiness probe: fails with 503 when the database is unreachable."""
    db_check = check_db_readiness()
    if db_check["status"] != "ok":
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "database": "unavailable"},
        )
    return {"status": "ready", "database": "ok"}
