"""F22 multilingual assistant: real conversations, not translated labels.

Each test sends an actual message through the authenticated API and checks the
answer, the negotiated language and the provenance-bearing citations.
"""

import re


def _ask(client, headers, trip, message, **extra):
    response = client.post(
        f"/api/trips/{trip['id']}/assistant",
        headers=headers,
        json={"message": message, **extra},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _limitations(body):
    return " ".join(body.get("limitations") or [])


def test_english_answer_carries_context_and_provenance(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "What is the confirmed plan for the trip?")
    assert body["language"]["code"] == "en"
    assert body["intent"] == "itinerary"
    assert body["answer"]
    assert body["citations"][0]["type"] == "trip"
    assert body["citations"][0]["provenance"] == "REPORTED"
    assert body["context"]["trip"]["destination"]
    assert body["context"]["budget"]["tracked_spend"] >= 0
    assert body["mutation"] == "none"


def test_spanish_message_is_detected_and_answered_in_spanish(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "¿Cuál es el plan confirmado del viaje?")
    assert body["language"]["code"] == "es"
    assert body["language"]["source"] == "detected"
    assert "plan confirmado" in body["answer"].lower()
    assert body["intent"] == "itinerary"


def test_explicit_language_request_overrides_detection(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "What is the plan today?", language="fr")
    assert body["language"]["code"] == "fr"
    assert body["language"]["source"] == "requested"
    assert "programme confirmé" in body["answer"].lower() or "plan confirmé" in body["answer"].lower()


def test_hindi_script_conversation(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "आज की पुष्ट इतिनेरी क्या है?")
    assert body["language"]["code"] == "hi"
    assert re.search(r"[\u0900-\u097f]", body["answer"])
    assert "पुष्ट योजना" in body["answer"]


def test_japanese_script_conversation(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "今日の旅程を教えてください。")
    assert body["language"]["code"] == "ja"
    assert re.search(r"[\u3040-\u30ff]", body["answer"])
    assert "確定プラン" in body["answer"]


def test_unsupported_language_falls_back_honestly(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "Какая сегодня погода?")
    assert body["language"]["code"] == "en"
    assert body["language"]["unsupported"] == "Russian"
    assert "Russian" in _limitations(body)
    # The answer must not pretend to have understood the Russian question.
    assert body["grounding"] in {"trip_data", "none", "product_policy"}


def test_mixed_language_message_is_noted(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "¿Cuál es el plan? and what is the weather?")
    assert body["language"]["mixed"]
    assert "mixed" in _limitations(body).lower()


def test_weather_stays_honest_without_provider(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "Will it rain tomorrow?")
    assert body["intent"] == "weather"
    assert body["grounding"] == "none"
    assert "No weather API is configured." in body["limitations"]
    assert "weather provider" in body["answer"]
    assert body["language"]["code"] == "en"


def test_plural_phrasing_resolves_the_same_intent(client, mira, kyoto):
    votes = _ask(client, mira, kyoto, "Summarise the open votes")
    assert votes["intent"] == "vote"
    assert votes["answer"]

    itineraries = _ask(client, mira, kyoto, "Show me both itineraries")
    assert itineraries["intent"] == "itinerary"


def test_named_activity_uses_localized_catalog_facts(client, mira, kyoto):
    body = _ask(
        client,
        mira,
        kyoto,
        "¿Cuánto cuesta Fushimi Inari Shrine?",
    )
    assert body["language"]["code"] == "es"
    assert body["intent"] == "place_fact"
    assert "estimación del catálogo" in body["answer"]
    assert body["citations"][0]["provenance"] == "REPORTED"


def test_unrecorded_day_triggers_a_clarifying_question(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "What is the plan on 1999-01-01?")
    assert body["intent"] == "itinerary"
    assert "Which day or activity do you mean?" in body["answer"]
    assert body["requires_approval"] is False


def test_privacy_answer_is_localized(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "¿Cuál es la política de privacidad?", language="es")
    assert body["language"]["code"] == "es"
    assert "privados por defecto" in body["answer"]
    assert body["grounding"] == "product_policy"
    assert body["citations"] == []


def test_group_aggregate_only_uses_consented_members(client, mira, kyoto):
    body = _ask(client, mira, kyoto, "Tell me about this trip")
    group = body["context"]["group_preferences"]
    if group is not None:
        assert group["consented_members"] <= group["total_members"]
        assert "no individual values" in group["note"]
        # No member identifiers leak through the aggregate.
        assert not any(key in group for key in ("user_ids", "emails", "budgets"))
