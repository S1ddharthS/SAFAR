"""Invitation email seam: minimal data, no provider, no outbound calls."""

from __future__ import annotations

import socket
import uuid
from dataclasses import fields

import pytest

from app.integrations import email as email_service
from app.integrations.email import InvitationEmail

VALID_TOKEN = "A" * 32
VALID_PATH = f"/invite/{VALID_TOKEN}"


def _message() -> InvitationEmail:
    return email_service.build_invitation_email(
        "guest@example.com", VALID_PATH, "2026-12-01T00:00:00Z"
    )


def test_minimal_message_contract_cannot_carry_trip_or_member_data():
    message = _message()

    assert {field.name for field in fields(message)} == {
        "recipient",
        "invite_path",
        "expires_at",
    }
    with pytest.raises(TypeError):
        InvitationEmail(
            recipient="guest@example.com",
            invite_path=VALID_PATH,
            trip_name="Kyoto in Slow Bloom",
        )
    with pytest.raises((AttributeError, TypeError)):
        message.budget_limit = 3200


def test_rendered_copy_is_generic_and_uses_only_the_invite_path():
    subject, body = email_service.render_invitation_email(_message())
    rendered = f"{subject}\n{body}".lower()

    assert subject == "Your SAFAR invitation"
    assert VALID_PATH in body
    for marker in ["kyoto", "3200", "budget", "accessibility", "35.0037", "mira"]:
        assert marker not in rendered


@pytest.mark.parametrize(
    "invite_path",
    [
        "https://evil.example/invite/" + VALID_TOKEN,
        f"{VALID_PATH}?token=leak",
        f"{VALID_PATH}#fragment",
        "/media/" + VALID_TOKEN,
        "/invite/../secret",
        "/invite/short",
        "/invite/" + VALID_TOKEN + "/extra",
    ],
)
def test_invite_paths_are_strictly_validated(invite_path):
    with pytest.raises(email_service.EmailValidationError):
        email_service.build_invitation_email("guest@example.com", invite_path)


@pytest.mark.parametrize("recipient", ["not-an-email", "", "guest@localhost", None])
def test_recipients_are_validated_without_deliverability_lookup(recipient):
    with pytest.raises(email_service.EmailValidationError):
        email_service.build_invitation_email(recipient, VALID_PATH)


def test_noop_sender_performs_no_network_call(monkeypatch):
    def fail_connect(*_args, **_kwargs):
        pytest.fail("email sender attempted a network connection")

    monkeypatch.setattr(socket.socket, "connect", fail_connect)

    delivery = email_service.NoopEmailSender().send_invitation(_message())

    assert delivery.provider == "disabled"
    assert delivery.delivered is False
    assert delivery.accepted is False


def test_unknown_and_hosted_test_providers_fail_closed(monkeypatch):
    monkeypatch.setattr(email_service.settings, "email_provider", "smtp")
    with pytest.raises(RuntimeError, match="not implemented"):
        email_service.build_email_sender()

    monkeypatch.setattr(email_service.settings, "email_provider", "memory")
    monkeypatch.setattr(email_service.settings, "environment", "staging")
    with pytest.raises(RuntimeError, match="not allowed"):
        email_service.build_email_sender()


def test_capability_registry_does_not_advertise_outbound_email():
    status = email_service.status()

    assert status["enabled"] is False
    assert status["network"] is False
    for key in ("token", "secret", "value"):
        assert key not in status


def test_invitation_creation_uses_the_sender_without_private_data(
    client, mira, kyoto, monkeypatch
):
    sender = email_service.InMemoryEmailSender()
    monkeypatch.setattr(email_service, "_sender", sender)
    recipient = f"invite-{uuid.uuid4().hex[:8]}@example.com"

    response = client.post(
        f"/api/trips/{kyoto['id']}/invitations",
        headers=mira,
        json={"email": recipient, "role": "member", "scope": "full"},
    )

    assert response.status_code == 201, response.text
    assert len(sender.messages) == 1
    message = sender.messages[0]
    assert message.recipient == recipient
    assert message.invite_path == response.json()["path"]
    _, body = email_service.render_invitation_email(message)
    assert kyoto["name"] not in body
    assert str(kyoto.get("budget_total")) not in body


def test_share_link_invitation_creates_no_email(client, mira, kyoto, monkeypatch):
    sender = email_service.InMemoryEmailSender()
    monkeypatch.setattr(email_service, "_sender", sender)

    response = client.post(
        f"/api/trips/{kyoto['id']}/invitations",
        headers=mira,
        json={"email": None, "role": "member", "scope": "full"},
    )

    assert response.status_code == 201, response.text
    assert sender.messages == []
