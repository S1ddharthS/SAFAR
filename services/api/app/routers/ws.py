"""Trip workspace WebSocket channel for collaborative updates (F05).

Browsers cannot set Authorization headers on WebSocket handshakes, so the
short-lived access token is passed as a query parameter and verified before
the connection is accepted. Membership is re-checked on every connection.
"""

import logging
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from app.core.metrics import metrics
from app.core.realtime import manager
from app.core.security import decode_token
from app.db.context import set_user_context
from app.db.session import SessionLocal
from app.models import Trip, TripMember, User
from app.services.auth_sessions import session_is_active
from app.services.common import event_payload

ws_logger = logging.getLogger("safar.ws")
router = APIRouter()


@router.websocket("/ws/trips/{trip_id}")
async def trip_socket(
    websocket: WebSocket,
    trip_id: str,
    token: str = Query(..., min_length=20),
):
    payload = decode_token(token, "ws")
    if not payload or not payload.get("sub"):
        metrics.record_ws_auth_rejected()
        ws_logger.warning("ws_token_invalid", extra={"trip_id": trip_id})
        await websocket.close(code=4401)
        return

    db = SessionLocal()
    try:
        set_user_context(db, payload["sub"])
        user = db.get(User, payload["sub"])
        if not user or not user.is_active or user.deleted_at:
            metrics.record_ws_auth_rejected()
            ws_logger.warning("ws_user_inactive", extra={"trip_id": trip_id, "sub": payload.get("sub")})
            await websocket.close(code=4401)
            return
        session_id = payload.get("sid")
        if session_id and not session_is_active(db, session_id, user.id):
            metrics.record_ws_auth_rejected()
            ws_logger.warning("ws_session_inactive", extra={"trip_id": trip_id, "sub": user.id})
            await websocket.close(code=4401)
            return
        trip = db.get(Trip, trip_id)
        if not trip or trip.deleted_at:
            await websocket.close(code=4404)
            return
        member = (
            db.query(TripMember)
            .filter(
                TripMember.trip_id == trip.id,
                TripMember.user_id == user.id,
                TripMember.status == "active",
            )
            .first()
        )
        if not member:
            await websocket.close(code=4404)
            return
        display_name = user.display_name
        user_id = user.id
    finally:
        db.close()

    await manager.connect(trip_id, websocket, user_id)
    await websocket.send_json(
        event_payload(
            "connected",
            trip_id=trip_id,
            user=display_name,
            note="Live updates for this trip workspace only.",
        )
    )
    try:
        while True:
            message = await websocket.receive_text()
            if message.strip().lower() == "ping":
                await websocket.send_json(event_payload("pong", trip_id=trip_id))
    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(trip_id, websocket)
