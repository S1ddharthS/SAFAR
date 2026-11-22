"""Phase 7 cross-cutting evaluation: grounding, privacy, providers, latency.

These checks are deliberately end-to-end through the API. They measure the
properties the Phase 7 brief names: hallucination resistance, privacy leakage,
provider failure honesty and response latency.
"""

import json
import time

from app.core.config import settings


def _ask(client, headers, trip_id, message, language=None):
    response = client.post(
        f"/api/trips/{trip_id}/assistant",
        headers=headers,
        json={"message": message, **({"language": language} if language else {})},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_place_answers_do_not_invent_hours_or_availability(client, mira, kyoto):
    answer = _ask(
        client,
        mira,
        kyoto["id"],
        "What do you know about the Kyoto Railway Museum?",
    )
    assert answer["intent"] == "place_fact"
    text = answer["answer"].lower()
    assert "recorded opening hours" in text
    assert "10:00-17:00" in answer["answer"]
    assert "catalog data, not a live feed" in text
    limitations = " ".join(answer["limitations"]).lower()
    assert "no live availability" in limitations
    assert answer["mutation"] == "none"
    assert answer["requires_approval"] is False
    assert answer["grounding"] == "catalog_and_reports"
    assert answer["citations"]
    assert all(citation["provenance"] in {"VERIFIED", "REPORTED", "ESTIMATED"} for citation in answer["citations"])
    assert any("out of date" in limitation for limitation in answer["limitations"])


def test_assistant_does_not_leak_private_member_data(client, mira, jonas, kyoto):
    answer = _ask(
        client,
        mira,
        kyoto["id"],
        "How is my data shared? What can others see about my private preferences?",
    )
    assert answer["intent"] == "privacy"
    text = answer["answer"]
    assert "private" in text.lower()
    assert "Jonas" not in text
    assert "budget_limit" not in text
    serialized = json.dumps(answer)
    assert "Jonas" not in serialized
    assert "safar-demo" not in serialized
    # Group aggregates, when present, are counts and distributions only.
    group = (answer.get("context") or {}).get("group_preferences")
    if group:
        assert set(group) <= {
            "consented_members",
            "total_members",
            "pace",
            "top_interests",
            "note",
        }
        assert isinstance(group["consented_members"], int)
        assert "budget" not in json.dumps(group).lower()


def test_answers_declare_grounding_and_never_mutate(client, mira, kyoto):
    for message in (
        "What is confirmed for today?",
        "Who owes whom after the expenses?",
        "What did the engine recommend and why?",
        "What is the plan if it rains?",
    ):
        answer = _ask(client, mira, kyoto["id"], message)
        assert answer["answer"]
        assert answer["mutation"] == "none"
        assert "generated_by" in answer
        assert answer["generated_by"].startswith("safar-grounded")
        if answer["grounding"] != "none":
            assert answer["citations"]
            assert all("provenance" in citation for citation in answer["citations"])


def test_provider_capabilities_expose_no_secrets(client):
    response = client.get("/api/ai/capabilities")
    assert response.status_code == 200, response.text
    payload = response.json()
    serialized = json.dumps(payload).lower()
    # Documentation may name an env var; it must never carry a secret value.
    assert settings.secret_key.lower() not in serialized
    assert "sk-" not in serialized
    for provider in payload["providers"].values():
        assert "value" not in provider
        assert "token" not in provider
        assert "secret" not in provider

    providers = payload["providers"]
    assert providers["llm"]["enabled"] is False
    assert providers["translation"]["network"] is False
    assert providers["translation"]["mode"] == "local-templates"
    assert providers["storage"]["mode"] == "signed-local-url"
    assert payload["default_external_ai_calls"] is False
    assert payload["external_network_used"] is False
    assert "No user identifier" in payload["outbound_data"]


def test_assistant_and_engine_stay_within_latency_budget(client, mira, kyoto):
    started = time.perf_counter()
    _ask(client, mira, kyoto["id"], "What is confirmed for today?")
    assistant_seconds = time.perf_counter() - started
    assert assistant_seconds < 3.0, f"assistant took {assistant_seconds:.2f}s"

    started = time.perf_counter()
    response = client.post(
        f"/api/trips/{kyoto['id']}/engine/recommend",
        headers=mira,
        json={"mode": "everyone_wins", "for_date": kyoto["start_date"], "limit": 6},
    )
    engine_seconds = time.perf_counter() - started
    assert response.status_code == 201, response.text
    assert engine_seconds < 3.0, f"engine took {engine_seconds:.2f}s"


def test_forecast_and_recommendations_never_claim_verified_predictions(
    client, mira, kyoto
):
    batch = client.post(
        f"/api/trips/{kyoto['id']}/engine/recommend",
        headers=mira,
        json={"mode": "surprise_us", "for_date": kyoto["start_date"], "limit": 3},
    )
    assert batch.status_code == 201, batch.text
    body = batch.json()
    assert body["meta"]["evaluation"]["constraints"]["violations"] == 0
    for item in body["items"]:
        assert "curated seed data" in body["meta"]["disclosure"]
        assert item["status"] == "suggested"
        assert "estimates" in body["meta"]["disclosure"]
