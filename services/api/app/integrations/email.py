"""Provider-neutral invitation email seam.

No transactional provider is wired. The default backend records nothing and
sends nothing; invite links and the share sheet remain the delivery path. A
message may contain only a validated recipient, a relative invite path and an
optional expiry. Trip names, budgets, notes, locations and member details are
not part of the contract.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from urllib.parse import urlsplit

from email_validator import EmailNotValidError, validate_email

from app.core.config import RESTRICTED_ENVIRONMENTS, settings

email_logger = logging.getLogger("safar.email")

_INVITE_TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9_-]{16,128}$")


class EmailValidationError(ValueError):
    """The message contains data outside the minimal invitation contract."""


@dataclass(frozen=True, slots=True)
class InvitationEmail:
    """Allowlisted fields only; extra attributes are impossible by design."""

    recipient: str
    invite_path: str
    expires_at: str | None = None


@dataclass(frozen=True, slots=True)
class EmailDelivery:
    provider: str
    accepted: bool
    delivered: bool
    note: str | None = None


def build_invitation_email(
    recipient: str,
    invite_path: str,
    expires_at: datetime | str | None = None,
) -> InvitationEmail:
    """Validate the recipient/path and discard everything else."""
    try:
        # Deliverability is deliberately not checked: that would make an
        # outbound DNS query during a local invitation request.
        normalized_recipient = validate_email(
            recipient, check_deliverability=False
        ).normalized
    except (EmailNotValidError, AttributeError, TypeError, ValueError) as exc:
        raise EmailValidationError("Invalid email recipient") from exc

    parts = urlsplit(invite_path or "")
    if parts.scheme or parts.netloc or parts.query or parts.fragment:
        raise EmailValidationError("Invite path must be relative and have no query")
    segments = parts.path.split("/")
    if (
        len(segments) != 3
        or segments[0] != ""
        or segments[1] != "invite"
        or not _INVITE_TOKEN_PATTERN.match(segments[2])
    ):
        raise EmailValidationError("Invalid invite path")

    normalized_expiry: str | None = None
    if expires_at is not None:
        raw = expires_at.isoformat() if isinstance(expires_at, datetime) else str(expires_at)
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError as exc:
            raise EmailValidationError("Invalid invitation expiry") from exc
        normalized_expiry = parsed.isoformat()

    return InvitationEmail(
        recipient=normalized_recipient,
        invite_path=parts.path,
        expires_at=normalized_expiry,
    )


def render_invitation_email(message: InvitationEmail) -> tuple[str, str]:
    """Render fixed copy from allowlisted fields only."""
    subject = "Your SAFAR invitation"
    lines = [
        "You have been invited to join a SAFAR trip.",
        "Open SAFAR and use this invitation link:",
        message.invite_path,
    ]
    if message.expires_at:
        lines.append(f"This link expires at {message.expires_at}.")
    lines.append("If you were not expecting this invitation, you can ignore this message.")
    return subject, "\n\n".join(lines)


class EmailSender(Protocol):
    provider_name: str

    def send_invitation(self, message: InvitationEmail) -> EmailDelivery: ...


class NoopEmailSender:
    """Default backend: validate and render, but never send or retain data."""

    provider_name = "disabled"

    def send_invitation(self, message: InvitationEmail) -> EmailDelivery:
        render_invitation_email(message)
        return EmailDelivery(
            provider=self.provider_name,
            accepted=False,
            delivered=False,
            note="Outbound email is disabled; invite links and share sheets remain available.",
        )


class InMemoryEmailSender:
    """Test-only backend that captures messages without any network call."""

    provider_name = "test"

    def __init__(self) -> None:
        self.messages: list[InvitationEmail] = []

    def send_invitation(self, message: InvitationEmail) -> EmailDelivery:
        self.messages.append(message)
        return EmailDelivery(
            provider=self.provider_name,
            accepted=True,
            delivered=True,
            note="Captured in memory for assertions; not sent.",
        )


def build_email_sender(provider: str | None = None) -> EmailSender:
    """Fail closed for unknown or hosted test backends."""
    name = (provider or settings.email_provider).strip().lower()
    if name == "disabled":
        return NoopEmailSender()
    if name in {"memory", "test"}:
        if settings.environment in RESTRICTED_ENVIRONMENTS:
            raise RuntimeError("Test email backends are not allowed in production/staging")
        return InMemoryEmailSender()
    raise RuntimeError(
        f"SAFAR_EMAIL_PROVIDER={name!r} is not implemented; outbound email stays disabled."
    )


_sender: EmailSender | None = None


def get_email_sender() -> EmailSender:
    global _sender
    if _sender is None:
        _sender = build_email_sender()
    return _sender


def set_email_sender(sender: EmailSender | None) -> None:
    """Replace the process-wide sender. Intended for isolated tests."""
    global _sender
    _sender = sender


def status() -> dict:
    return {
        "provider": settings.email_provider,
        "enabled": False,
        "network": False,
        "key_required": False,
        "notes": [
            "No outbound email provider is wired. Invite links and share sheets remain available."
        ],
    }
