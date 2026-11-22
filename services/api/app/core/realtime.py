import asyncio
from collections import defaultdict
import logging
from typing import Any

from fastapi import WebSocket

from app.core.metrics import metrics

ws_logger = logging.getLogger("safar.ws")


class TripConnectionManager:
    """In-process pub/sub for trip workspaces.

    A single-process implementation keeps the reference deployment simple.
    For multi-instance deployments swap this for Redis pub/sub behind the
    same `broadcast` interface (documented in README).
    """

    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._socket_users: dict[WebSocket, tuple[str, str]] = {}
        self._lock = asyncio.Lock()

    async def connect(
        self, trip_id: str, socket: WebSocket, user_id: str | None = None
    ) -> None:
        await socket.accept()
        async with self._lock:
            self._connections[trip_id].add(socket)
            if user_id:
                self._socket_users[socket] = (trip_id, user_id)
        metrics.record_ws_connect()
        ws_logger.info("ws_connected", extra={"trip_id": trip_id, "user_id": user_id})

    async def disconnect(self, trip_id: str, socket: WebSocket) -> None:
        async with self._lock:
            self._connections[trip_id].discard(socket)
            self._socket_users.pop(socket, None)
            if not self._connections[trip_id]:
                self._connections.pop(trip_id, None)
        metrics.record_ws_disconnect()
        ws_logger.info("ws_disconnected", extra={"trip_id": trip_id})

    async def disconnect_user(self, trip_id: str, user_id: str) -> int:
        """Close every live socket a member holds for a trip."""
        async with self._lock:
            sockets = [
                socket
                for socket, key in self._socket_users.items()
                if key == (trip_id, user_id)
            ]
        for socket in sockets:
            try:
                await socket.close(code=4403)
            except Exception:
                pass
            await self.disconnect(trip_id, socket)
        return len(sockets)

    async def broadcast(self, trip_id: str, event: dict[str, Any]) -> None:
        async with self._lock:
            sockets = list(self._connections.get(trip_id, ()))
        metrics.record_ws_broadcast()
        for socket in sockets:
            try:
                await socket.send_json(event)
            except Exception:
                await self.disconnect(trip_id, socket)


manager = TripConnectionManager()
