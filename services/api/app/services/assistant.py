"""Grounded, multilingual conversational assistant (F22).

Answers are assembled deterministically from SAFAR's own records through local
templates. No message text leaves the process, no LLM is called, and every
citation declares its provenance. When a fact is not recorded the assistant
says so or asks a clarifying question instead of guessing.
"""

import re
import unicodedata
from collections import Counter
from datetime import date, timedelta

from sqlalchemy.orm import Session

from app.integrations import weather as weather_provider
from app.integrations.base import ESTIMATED, PREDICTED, REPORTED
from app.models import (
    Activity,
    ItineraryItem,
    ItineraryProposal,
    JourneyDNA,
    Profile,
    Recommendation,
    RecommendationBatch,
    Trip,
    TripMember,
    User,
)
from app.services.assistant_text import t
from app.services.expenses import balances
from app.services.feedback import personalization_allowed
from app.services.language import resolve_language
from app.services.places import aggregate_reports

GENERATOR = "safar-grounded-i18n-2.0"

# Keyword lexicons per language. English is always merged in as a fallback so a
# mixed-language message ("¿cuál es el plan del trip?") still resolves.
INTENTS: dict[str, dict[str, tuple[str, ...]]] = {
    "en": {
        "weather": ("weather", "rain", "raining", "forecast", "temperature", "sunny", "snow", "umbrella"),
        "budget": ("budget", "cost", "spend", "spent", "owe", "expense", "money", "expensive", "price"),
        "vote": ("vote", "proposal", "decision", "approve", "pending"),
        "members": ("who is", "members", "group members", "travellers", "travelers", "joining", "group"),
        "privacy": ("privacy", "share", "location", "permission", "my data"),
        "recommend": ("recommend", "suggest", "should we", "what should", "things to do", "options", "idea"),
        "itinerary": ("itinerary", "plan", "schedule", "today", "tomorrow", "doing", "agenda", "when is"),
        "overview": ("overview", "summary", "tell me about", "about the trip", "destination", "dates", "how many days", "group size"),
    },
    "es": {
        "weather": ("clima", "tiempo", "lluvia", "llover", "pronostico", "temperatura", "soleado", "nieve"),
        "budget": ("presupuesto", "costo", "coste", "gasto", "gastado", "debo", "dinero", "caro", "precio"),
        "vote": ("votar", "votacion", "propuesta", "decision", "aprobar", "pendiente"),
        "members": ("miembros", "quienes", "grupo", "viajeros", "unirse"),
        "privacy": ("privacidad", "compartir", "ubicacion", "permiso", "datos"),
        "recommend": ("recomendar", "recomienda", "sugerir", "sugiere", "opciones", "ideas"),
        "itinerary": ("itinerario", "plan", "horario", "hoy", "manana", "agenda"),
        "overview": ("resumen", "informacion", "destino", "fechas", "cuantos dias", "tamano del grupo"),
    },
    "fr": {
        "weather": ("meteo", "pluie", "pleuvoir", "prevision", "temperature", "ensoleille", "neige"),
        "budget": ("budget", "cout", "depense", "depenser", "dois", "argent", "cher", "prix"),
        "vote": ("voter", "vote", "proposition", "decision", "approuver", "en attente"),
        "members": ("membres", "qui", "groupe", "voyageurs", "rejoindre"),
        "privacy": ("confidentialite", "partager", "position", "autorisation", "donnees"),
        "recommend": ("recommander", "recommande", "suggerer", "suggere", "options", "idees"),
        "itinerary": ("itineraire", "programme", "plan", "aujourd", "demain", "horaire", "agenda"),
        "overview": ("apercu", "resume", "destination", "dates", "combien de jours", "taille du groupe"),
    },
    "de": {
        "weather": ("wetter", "regen", "regnen", "vorhersage", "temperatur", "sonnig", "schnee"),
        "budget": ("budget", "kosten", "ausgabe", "ausgegeben", "schulde", "geld", "teuer", "preis"),
        "vote": ("abstimmen", "abstimmung", "vorschlag", "entscheidung", "genehmigen", "offen"),
        "members": ("mitglieder", "wer", "gruppe", "reisende", "beitreten"),
        "privacy": ("datenschutz", "teilen", "standort", "erlaubnis", "daten"),
        "recommend": ("empfehlen", "empfiehl", "vorschlagen", "optionen", "ideen"),
        "itinerary": ("reiseplan", "plan", "zeitplan", "heute", "morgen", "programm", "agenda"),
        "overview": ("ubersicht", "zusammenfassung", "ziel", "daten", "wie viele tage", "gruppengrosse"),
    },
    "pt": {
        "weather": ("clima", "tempo", "chuva", "chover", "previsao", "temperatura", "sol", "neve"),
        "budget": ("orcamento", "custo", "despesa", "gasto", "gastou", "devo", "dinheiro", "caro", "preco"),
        "vote": ("votar", "votacao", "proposta", "decisao", "aprovar", "pendente"),
        "members": ("membros", "quem", "grupo", "viajantes", "juntar"),
        "privacy": ("privacidade", "partilhar", "localizacao", "permissao", "dados"),
        "recommend": ("recomendar", "recomenda", "sugerir", "sugere", "opcoes", "ideias"),
        "itinerary": ("itinerario", "plano", "horario", "hoje", "amanha", "agenda"),
        "overview": ("resumo", "informacao", "destino", "datas", "quantos dias", "tamanho do grupo"),
    },
    "it": {
        "weather": ("meteo", "pioggia", "piovere", "previsioni", "temperatura", "sole", "neve"),
        "budget": ("budget", "costo", "spesa", "speso", "devo", "soldi", "caro", "prezzo"),
        "vote": ("votare", "votazione", "proposta", "decisione", "approvare", "in attesa"),
        "members": ("membri", "chi", "gruppo", "viaggiatori", "unirsi"),
        "privacy": ("privacy", "condividere", "posizione", "permesso", "dati"),
        "recommend": ("consigli", "consigliare", "suggerire", "suggerisci", "opzioni", "idee"),
        "itinerary": ("itinerario", "programma", "piano", "oggi", "domani", "orario", "agenda"),
        "overview": ("panoramica", "riepilogo", "destinazione", "date", "quanti giorni", "dimensione del gruppo"),
    },
    "hi": {
        "weather": ("मौसम", "बारिश", "वर्षा", "पूर्वानुमान", "तापमान", "धूप", "बर्फ"),
        "budget": ("बजट", "खर्च", "लागत", "कीमत", "पैसा", "महंगा"),
        "vote": ("मतदान", "वोट", "प्रस्ताव", "निर्णय", "स्वीकृति", "लंबित"),
        "members": ("सदस्य", "कौन", "समूह", "यात्री", "शामिल"),
        "privacy": ("गोपनीयता", "साझा", "स्थान", "अनुमति", "डेटा"),
        "recommend": ("सिफ़ारिश", "सुझाव", "विकल्प", "आइडिया"),
        "itinerary": ("इतिनेरी", "योजना", "कार्यक्रम", "आज", "कल"),
        "overview": ("अवलोकन", "सारांश", "गंतव्य", "तारीख", "कितने दिन"),
    },
    "ja": {
        "weather": ("天気", "雨", "降水", "予報", "気温", "晴れ", "雪"),
        "budget": ("予算", "費用", "支出", "使った", "お金", "高い", "料金"),
        "vote": ("投票", "提案", "決定", "承認", "未決"),
        "members": ("メンバー", "誰", "グループ", "旅行者", "参加"),
        "privacy": ("プライバシー", "共有", "位置情報", "許可", "データ"),
        "recommend": ("おすすめ", "推薦", "候補", "アイデア"),
        "itinerary": ("旅程", "予定", "スケジュール", "今日", "明日", "プラン"),
        "overview": ("概要", "まとめ", "目的地", "日程", "何日", "人数"),
    },
}

INTENT_ORDER = (
    "weather",
    "budget",
    "vote",
    "members",
    "privacy",
    "recommend",
    "itinerary",
    "overview",
)

MODE_LABELS = {
    "en": {"everyone_wins": "Everyone Wins", "your_turn": "Your Turn", "surprise_us": "Surprise Us"},
    "es": {"everyone_wins": "Todos ganan", "your_turn": "Tu turno", "surprise_us": "Sorpréndenos"},
    "fr": {"everyone_wins": "Tout le monde gagne", "your_turn": "À votre tour", "surprise_us": "Surprenez-nous"},
    "de": {"everyone_wins": "Alle gewinnen", "your_turn": "Du bist dran", "surprise_us": "Überrasch uns"},
    "pt": {"everyone_wins": "Todos ganham", "your_turn": "A tua vez", "surprise_us": "Surpreende-nos"},
    "it": {"everyone_wins": "Tutti vincono", "your_turn": "Il tuo turno", "surprise_us": "Sorprendici"},
    "hi": {"everyone_wins": "सब जीतें", "your_turn": "आपकी बारी", "surprise_us": "चौंका दें"},
    "ja": {"everyone_wins": "全員が勝つ", "your_turn": "あなたの番", "surprise_us": "驚かせて"},
}

SOURCE_LABEL_I18N = {
    "en": {"official": "officially sourced", "community": "community reported", "estimated": "estimated", "unknown": "unknown"},
    "es": {"official": "de fuente oficial", "community": "reportado por la comunidad", "estimated": "estimado", "unknown": "desconocido"},
    "fr": {"official": "source officielle", "community": "signalé par la communauté", "estimated": "estimé", "unknown": "inconnu"},
    "de": {"official": "offizielle Quelle", "community": "von der Community gemeldet", "estimated": "geschätzt", "unknown": "unbekannt"},
    "pt": {"official": "fonte oficial", "community": "reportado pela comunidade", "estimated": "estimado", "unknown": "desconhecido"},
    "it": {"official": "fonte ufficiale", "community": "segnalato dalla community", "estimated": "stimato", "unknown": "sconosciuto"},
    "hi": {"official": "आधिकारिक स्रोत", "community": "समुदाय द्वारा रिपोर्ट", "estimated": "अनुमानित", "unknown": "अज्ञात"},
    "ja": {"official": "公式情報", "community": "コミュニティ報告", "estimated": "推定", "unknown": "不明"},
}

FRESHNESS_I18N = {
    "en": {
        "fresh": "fresh",
        "recent but fading": "recent but fading",
        "old — treat with caution": "old — treat with caution",
        "stale — do not rely on it alone": "stale — do not rely on it alone",
    },
    "es": {
        "fresh": "reciente",
        "recent but fading": "reciente pero perdiendo vigencia",
        "old — treat with caution": "antiguo — trátalo con cautela",
        "stale — do not rely on it alone": "obsoleto — no te bases solo en ello",
    },
    "fr": {
        "fresh": "récent",
        "recent but fading": "récent mais qui s'estompe",
        "old — treat with caution": "ancien — à prendre avec prudence",
        "stale — do not rely on it alone": "périmé — ne vous y fiez pas seul",
    },
    "de": {
        "fresh": "aktuell",
        "recent but fading": "aktuell, aber abnehmend",
        "old — treat with caution": "alt — mit Vorsicht behandeln",
        "stale — do not rely on it alone": "veraltet — nicht allein darauf verlassen",
    },
    "pt": {
        "fresh": "recente",
        "recent but fading": "recente mas a perder validade",
        "old — treat with caution": "antigo — trata com cautela",
        "stale — do not rely on it alone": "desatualizado — não confies só nele",
    },
    "it": {
        "fresh": "recente",
        "recent but fading": "recente ma in calo",
        "old — treat with caution": "vecchio — trattare con cautela",
        "stale — do not rely on it alone": "obsoleto — non fidarti solo di questo",
    },
    "hi": {
        "fresh": "ताज़ा",
        "recent but fading": "हालिया लेकिन पुराना हो रहा",
        "old — treat with caution": "पुराना — सावधानी से लें",
        "stale — do not rely on it alone": "बासी — केवल इस पर निर्भर न रहें",
    },
    "ja": {
        "fresh": "新しい",
        "recent but fading": "やや古くなりつつある",
        "old — treat with caution": "古い — 注意して扱う",
        "stale — do not rely on it alone": "陳腐化 — これだけに頼らない",
    },
}

WEATHER_OFF_LIMIT = {
    "en": "No weather API is configured.",
    "es": "No hay una API de meteorología configurada.",
    "fr": "Aucune API météo n'est configurée.",
    "de": "Es ist keine Wetter-API konfiguriert.",
    "pt": "Não há uma API de meteorologia configurada.",
    "it": "Nessuna API meteo è configurata.",
    "hi": "कोई मौसम API कॉन्फ़िगर नहीं है।",
    "ja": "天気APIは設定されていません。",
}

_ISO_DAY = re.compile(r"\b(?:19|20)\d{2}-\d{2}-\d{2}\b")
_DAY_NUMBER = re.compile(r"\bday\s+(\d{1,2})\b", re.I)


def _fold(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.lower())
    return "".join(char for char in decomposed if not unicodedata.combining(char))


def _keyword_seen(keyword: str, folded: str) -> bool:
    if keyword.isascii():
        if " " in keyword or not keyword.isalpha():
            return re.search(
                rf"(?<![a-z0-9]){re.escape(keyword)}(?![a-z0-9])", folded
            ) is not None
        variants = {keyword, f"{keyword}s", f"{keyword}es"}
        if keyword.endswith("y"):
            variants.add(f"{keyword[:-1]}ies")
        pattern = "|".join(
            sorted((re.escape(variant) for variant in variants), key=len, reverse=True)
        )
        return re.search(rf"(?<![a-z0-9])(?:{pattern})(?![a-z0-9])", folded) is not None
    return keyword in folded


def _detect_intent(message: str, language: str) -> str:
    folded = _fold(message)
    for intent in INTENT_ORDER:
        words = list(INTENTS["en"].get(intent, ()))
        if language != "en":
            words.extend(INTENTS.get(language, {}).get(intent, ()))
        if any(_keyword_seen(word, folded) for word in words):
            return intent
    return "general"


def _today_or_next(items: list[ItineraryItem]) -> tuple[date | None, list[ItineraryItem]]:
    if not items:
        return None, []
    today = date.today()
    upcoming = [item for item in items if item.day >= today]
    pool = upcoming or items
    day = sorted({item.day for item in pool})[0]
    return day, sorted([item for item in pool if item.day == day], key=lambda item: item.start_time)


def _referenced_day(message: str, trip: Trip) -> date | None:
    match = _ISO_DAY.search(message)
    if match:
        try:
            return date.fromisoformat(match.group(0))
        except ValueError:
            return None
    match = _DAY_NUMBER.search(message)
    if match:
        offset = int(match.group(1)) - 1
        span = (trip.end_date - trip.start_date).days
        if 0 <= offset <= span:
            return trip.start_date + timedelta(days=offset)
    return None


def _find_named_activity(db: Session, trip: Trip, message: str) -> Activity | None:
    if not trip.destination_id:
        return None
    lowered = message.lower()
    activities = db.query(Activity).filter(Activity.destination_id == trip.destination_id).all()
    for activity in activities:
        tokens = [token for token in re.split(r"[^a-z0-9]+", activity.name.lower()) if len(token) > 3]
        if activity.name.lower() in lowered or (tokens and all(token in lowered for token in tokens[:2])):
            return activity
    return None


def _cite(label: str, kind: str, entity_id: str | None, provenance: str) -> dict:
    return {"label": label, "type": kind, "id": entity_id, "provenance": provenance}


def _localized_source(label: str, language: str) -> str:
    mapping = {
        "Officially sourced": "official",
        "Community reported": "community",
        "Estimated": "estimated",
        "Unknown": "unknown",
    }
    key = mapping.get(label)
    if not key:
        return label
    return SOURCE_LABEL_I18N.get(language, SOURCE_LABEL_I18N["en"]).get(key, label)


def _localized_freshness(label: str, language: str) -> str:
    return FRESHNESS_I18N.get(language, FRESHNESS_I18N["en"]).get(label, label)


def _activity_answer(db: Session, trip: Trip, activity: Activity, language: str) -> dict:
    reports = aggregate_reports(db, activity.id)
    citations = [_cite(f"Activity record: {activity.name}", "activity", activity.id, REPORTED)]
    lines = [
        t(
            "place.summary",
            language,
            name=activity.name,
            currency=activity.currency,
            price=f"{activity.price_estimate:.0f}",
            minutes=activity.duration_minutes,
            effort=activity.effort,
        )
    ]
    if activity.opening_hours:
        hours = ", ".join(f"{day}: {value}" for day, value in list(activity.opening_hours.items())[:7])
        lines.append(t("place.hours_recorded", language, hours=hours))
    else:
        lines.append(t("place.hours_missing", language))
    if activity.wheelchair_accessible is True:
        lines.append(t("place.stepfree", language))
    elif activity.wheelchair_accessible is None:
        lines.append(t("place.access_unknown", language))
    else:
        lines.append(t("place.access_barriers", language))
    if reports["has_data"]:
        top = reports["categories"][0]
        lines.append(
            t(
                "place.reports_signal",
                language,
                category=top["category"],
                source=_localized_source(top["source_label"], language),
                freshness=_localized_freshness(top["freshness_label"], language),
            )
        )
        citations.append(
            _cite(f"Traveller reports: {top['category']}", "place_report", top["reports"][0]["id"], REPORTED)
        )
    else:
        lines.append(t("place.reports_none", language))
    return {
        "answer": " ".join(lines),
        "citations": citations,
        "grounding": "catalog_and_reports",
        "limitations": [t("place.limit_availability", language), t("place.limit_catalog", language)],
        "suggested_actions": [
            {"label": t("action.evidence", language), "href": f"/trips/{trip.id}/evidence/{activity.id}"}
        ],
        "requires_approval": False,
        "mutation": "none",
    }


def _weather_answer(trip: Trip, language: str) -> dict:
    if not weather_provider.enabled():
        return {
            "answer": t("weather.unavailable", language),
            "citations": [],
            "grounding": "none",
            "limitations": [WEATHER_OFF_LIMIT.get(language, WEATHER_OFF_LIMIT["en"])],
            "suggested_actions": [{"label": t("action.rescue", language), "href": f"/trips/{trip.id}/rescue"}],
            "requires_approval": False,
            "mutation": "none",
        }
    if not trip.base_lat and not trip.base_lon:
        return {
            "answer": t("weather.no_location", language),
            "citations": [],
            "grounding": "none",
            "limitations": [t("weather.limit", language)],
            "suggested_actions": [],
            "requires_approval": False,
            "mutation": "none",
        }
    result = weather_provider.forecast(trip.base_lat, trip.base_lon, days=3)
    if not result.ok or not result.data:
        return {
            "answer": t("weather.unavailable", language),
            "citations": [],
            "grounding": "none",
            "limitations": [result.message or "The weather provider did not return a forecast."],
            "suggested_actions": [{"label": t("action.rescue", language), "href": f"/trips/{trip.id}/rescue"}],
            "requires_approval": False,
            "mutation": "none",
        }
    rows = []
    for day in result.data.get("days", [])[:3]:
        rain = day.get("precipitation_probability")
        rows.append(
            t(
                "weather.day",
                language,
                date=day.get("date"),
                label=day.get("conditions"),
                min_temp=day.get("temperature_min"),
                max_temp=day.get("temperature_max"),
                rain=rain if rain is not None else "–",
            )
        )
    place = trip.destination_name or trip.name
    return {
        "answer": t(
            "weather.forecast",
            language,
            place=place,
            provider="Open-Meteo",
            summary=" ".join(rows),
        ),
        "citations": [_cite("Open-Meteo forecast", "external_provider", None, PREDICTED)],
        "grounding": "external_forecast",
        "limitations": [t("weather.limit", language)],
        "attribution": weather_provider.ATTRIBUTION,
        "suggested_actions": [{"label": t("action.rescue", language), "href": f"/trips/{trip.id}/rescue"}],
        "requires_approval": False,
        "mutation": "none",
    }


def _itinerary_answer(
    db: Session, trip: Trip, message: str, language: str, citations: list[dict]
) -> dict:
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .order_by(ItineraryItem.day, ItineraryItem.start_time)
        .all()
    )
    referenced = _referenced_day(message, trip)
    day: date | None = None
    day_items: list[ItineraryItem] = []
    if referenced:
        day_items = [item for item in items if item.day == referenced]
        day = referenced if day_items else None
        if not day_items and items:
            # The user named a day that has no confirmed items. Ask rather than
            # silently answering about a different day.
            next_day, _next_items = _today_or_next(items)
            clarifying = t("clarify.ask", language)
            if next_day:
                clarifying += " " + t("itinerary.next_day", language, day=next_day.isoformat())
            return {
                "answer": clarifying,
                "citations": citations,
                "grounding": "trip_data",
                "limitations": [t("limit.trip_data", language)],
                "suggested_actions": [{"label": t("action.itinerary", language), "href": f"/trips/{trip.id}/itinerary"}],
                "requires_approval": False,
                "mutation": "none",
            }
    else:
        day, day_items = _today_or_next(items)
    if not day_items:
        return {
            "answer": t("itinerary.empty", language),
            "citations": citations,
            "grounding": "trip_data",
            "limitations": [],
            "suggested_actions": [
                {"label": t("action.itinerary", language), "href": f"/trips/{trip.id}/itinerary"},
                {"label": t("action.engine", language), "href": f"/trips/{trip.id}/engine"},
            ],
            "requires_approval": False,
            "mutation": "none",
        }
    listing = "; ".join(
        t(
            "itinerary.item_cost" if item.cost_estimate else "itinerary.item",
            language,
            time=item.start_time,
            title=item.title,
            currency=trip.currency,
            cost=f"{item.cost_estimate:.0f}",
        )
        for item in day_items
    )
    citations.extend(
        _cite(f"Itinerary item: {item.title}", "itinerary_item", item.id, REPORTED) for item in day_items[:5]
    )
    return {
        "answer": t("itinerary.plan", language, day=day.isoformat(), listing=listing),
        "citations": citations,
        "grounding": "trip_data",
        "limitations": [t("itinerary.limit", language)],
        "suggested_actions": [{"label": t("action.itinerary", language), "href": f"/trips/{trip.id}/itinerary"}],
        "requires_approval": False,
        "mutation": "none",
    }


def _budget_answer(db: Session, trip: Trip, user: User, language: str, citations: list[dict]) -> dict:
    data = balances(db, trip)
    parts = [t("budget.total", language, currency=trip.currency, total=f"{data['total_spent']:.2f}")]
    if trip.budget_total:
        parts.append(t("budget.plan", language, currency=trip.currency, budget=f"{trip.budget_total:.0f}"))
    mine = next((entry for entry in data["balances"] if entry["user_id"] == user.id), None)
    if mine:
        net = f"{trip.currency} {mine['net']:+.2f}"
        parts.append(t("budget.mine_ahead" if mine["net"] >= 0 else "budget.mine_behind", language, net=net))
    if data["settlements"]:
        settle = data["settlements"][0]
        parts.append(
            t(
                "budget.settlement",
                language,
                from_name=settle["from_name"],
                to_name=settle["to_name"],
                currency=trip.currency,
                amount=f"{settle['amount']:.2f}",
            )
        )
        citations.append(_cite("Settlement suggestion", "expense_settlement", trip.id, ESTIMATED))
    parts.append(t("budget.track_only", language))
    return {
        "answer": " ".join(parts),
        "citations": citations,
        "grounding": "trip_data",
        "limitations": [t("budget.limit", language)],
        "suggested_actions": [{"label": t("action.expenses", language), "href": f"/trips/{trip.id}/expenses"}],
        "requires_approval": False,
        "mutation": "none",
    }


def _recommend_answer(db: Session, trip: Trip, language: str, citations: list[dict]) -> dict:
    batch = (
        db.query(RecommendationBatch)
        .filter(RecommendationBatch.trip_id == trip.id)
        .order_by(RecommendationBatch.created_at.desc())
        .first()
    )
    if not batch:
        return {
            "answer": t("recommend.empty", language),
            "citations": citations,
            "grounding": "trip_data",
            "limitations": [],
            "suggested_actions": [{"label": t("action.engine", language), "href": f"/trips/{trip.id}/engine"}],
            "requires_approval": False,
            "mutation": "none",
        }
    recs = (
        db.query(Recommendation)
        .filter(Recommendation.batch_id == batch.id)
        .order_by(Recommendation.rank)
        .limit(3)
        .all()
    )
    lines = []
    for rec in recs:
        activity = db.get(Activity, rec.activity_id)
        if activity:
            lines.append(
                t(
                    "recommend.rec",
                    language,
                    name=activity.name,
                    score=f"{rec.score:.0f}",
                    fit=f"{rec.minimum_fit:.0f}",
                )
            )
            citations.append(_cite(f"Recommendation: {activity.name}", "recommendation", rec.id, PREDICTED))
    if not lines:
        answer = t("recommend.none_stored", language)
    else:
        mode = MODE_LABELS.get(language, MODE_LABELS["en"]).get(batch.mode, batch.mode.replace("_", " "))
        answer = t("recommend.batch", language, mode=mode, listing="; ".join(lines)) + " " + t(
            "recommend.proposals", language
        )
    return {
        "answer": answer,
        "citations": citations,
        "grounding": "trip_data",
        "limitations": [t("recommend.limit", language)],
        "suggested_actions": [{"label": t("action.review", language), "href": f"/trips/{trip.id}/engine"}],
        "requires_approval": True,
        "mutation": "none",
    }


def _vote_answer(db: Session, trip: Trip, language: str, citations: list[dict]) -> dict:
    proposals = (
        db.query(ItineraryProposal)
        .filter(ItineraryProposal.trip_id == trip.id, ItineraryProposal.status == "open")
        .order_by(ItineraryProposal.created_at.desc())
        .all()
    )
    if not proposals:
        text = t("vote.none", language)
    else:
        text = t(
            "vote.open",
            language,
            count=len(proposals),
            titles="; ".join(proposal.title for proposal in proposals[:5]),
        )
        citations.extend(
            _cite(f"Proposal: {proposal.title}", "proposal", proposal.id, REPORTED)
            for proposal in proposals[:5]
        )
    return {
        "answer": text,
        "citations": citations,
        "grounding": "trip_data",
        "limitations": [],
        "suggested_actions": [{"label": t("action.voting", language), "href": f"/trips/{trip.id}/voting"}],
        "requires_approval": True,
        "mutation": "none",
    }


def _members_answer(db: Session, trip: Trip, language: str, citations: list[dict]) -> dict:
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    names = []
    for member in members:
        person = db.get(User, member.user_id) if member.user_id else None
        role = t(f"role.{member.role}", language) if member.role in {"owner", "admin", "member"} else member.role
        names.append(f"{(person.display_name if person else member.display_name or 'Guest')} ({role})")
    return {
        "answer": t("members.names", language, count=len(members), names=", ".join(names)),
        "citations": citations,
        "grounding": "trip_data",
        "limitations": [t("members.limit", language)],
        "suggested_actions": [{"label": t("action.members", language), "href": f"/trips/{trip.id}/members"}],
        "requires_approval": False,
        "mutation": "none",
    }


def _overview_answer(
    trip: Trip,
    items: list[ItineraryItem],
    context: dict,
    language: str,
    citations: list[dict],
) -> dict:
    nights = max((trip.end_date - trip.start_date).days, 0)
    parts = [t("overview.heading", language, name=trip.name)]
    parts.append(
        t(
            "overview.facts",
            language,
            destination=trip.destination_name or "–",
            start=trip.start_date.isoformat(),
            end=trip.end_date.isoformat(),
            nights=nights,
            group_size=trip.group_size,
            currency=trip.currency,
        )
    )
    confirmed = len(items)
    days = len({item.day for item in items})
    protected = sum(1 for item in items if item.is_protected)
    parts.append(t("overview.itinerary", language, confirmed=confirmed, days=days, protected=protected))
    budget_snapshot = context["budget"]
    if budget_snapshot.get("trip_budget") is not None:
        parts.append(
            t(
                "overview.budget",
                language,
                currency=trip.currency,
                budget=f"{budget_snapshot['trip_budget']:.0f}",
                spent=f"{budget_snapshot['tracked_spend']:.2f}",
            )
        )
    else:
        parts.append(t("overview.no_budget", language))
    limitations = [t("overview.limit", language)]
    if context["missing"]:
        limitations.append(
            "Not recorded: " + ", ".join(context["missing"]) + "."
            if language == "en"
            else t("limit.trip_data", language)
        )
    return {
        "answer": " ".join(parts),
        "citations": citations,
        "grounding": "trip_data",
        "limitations": limitations,
        "suggested_actions": [{"label": t("action.itinerary", language), "href": f"/trips/{trip.id}/itinerary"}],
        "requires_approval": False,
        "mutation": "none",
    }


def _build_context(db: Session, user: User, trip: Trip) -> dict:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    dna = db.query(JourneyDNA).filter(JourneyDNA.user_id == user.id).first()
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    owner_profile = {
        "pace": profile.travel_pace if profile else None,
        "budget_level": profile.budget_level if profile else None,
        "interests": list(profile.interests or [])[:8] if profile else [],
        "dietary": list(profile.dietary or [])[:8] if profile else [],
        "accessibility_needs": list(profile.accessibility_needs or [])[:8] if profile else [],
        "languages": list(profile.languages or [])[:4] if profile else [],
        "dna_top": (
            [name for name, _ in sorted(dna.scores.items(), key=lambda item: item[1], reverse=True)[:3]]
            if dna and dna.scores
            else []
        ),
    }
    consented_ids = [
        member.user_id
        for member in members
        if member.user_id and personalization_allowed(db, member.user_id)
    ]
    group_preferences = None
    if len(consented_ids) >= 2:
        group_profiles = db.query(Profile).filter(Profile.user_id.in_(consented_ids)).all()
        pace_counts = Counter(row.travel_pace for row in group_profiles if row)
        interest_counts = Counter(
            str(interest).lower()
            for row in group_profiles
            if row
            for interest in (row.interests or [])
        )
        group_preferences = {
            "consented_members": len(consented_ids),
            "total_members": len(members),
            "pace": dict(pace_counts.most_common(3)),
            "top_interests": [name for name, _ in interest_counts.most_common(3)],
            "note": "Aggregated only over members who allow personalization; no individual values.",
        }
    items = (
        db.query(ItineraryItem)
        .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
        .all()
    )
    data = balances(db, trip)
    context = {
        "trip": {
            "name": trip.name,
            "destination": trip.destination_name or None,
            "start_date": trip.start_date.isoformat(),
            "end_date": trip.end_date.isoformat(),
            "group_size": trip.group_size,
            "currency": trip.currency,
            "has_coordinates": bool(trip.base_lat or trip.base_lon),
        },
        "you": owner_profile,
        "group_preferences": group_preferences,
        "itinerary": {
            "confirmed": len(items),
            "protected": sum(1 for item in items if item.is_protected),
            "days": len({item.day for item in items}),
        },
        "budget": {
            "trip_budget": trip.budget_total,
            "tracked_spend": data["total_spent"],
        },
        "missing": [],
    }
    if not (trip.base_lat or trip.base_lon):
        context["missing"].append("destination coordinates")
    if trip.budget_total is None:
        context["missing"].append("trip budget")
    if not items:
        context["missing"].append("confirmed itinerary")
    return context


def answer(
    db: Session,
    user: User,
    trip: Trip,
    message: str,
    *,
    language: str | None = None,
    preferred_language: str | None = None,
) -> dict:
    resolution = resolve_language(message, requested=language, preferred=preferred_language)
    lang = resolution["code"]
    result = _compose_answer(db, user, trip, message, lang)
    limitations = result.setdefault("limitations", [])
    if resolution["unsupported"]:
        limitations.append(
            t(
                "language.note_unsupported",
                lang,
                script=resolution["unsupported"],
                language=resolution["name"],
            )
        )
    elif resolution["mixed"]:
        limitations.append(
            t(
                "language.note_mixed",
                lang,
                mixed=", ".join(resolution["mixed_names"]),
                language=resolution["name"],
            )
        )
    if lang != "en":
        limitations.append(t("language.limit", lang))
    result["language"] = {
        "code": lang,
        "name": resolution["name"],
        "source": resolution["source"],
        "detected": resolution["detected"],
        "confidence": resolution["confidence"],
        "mixed": resolution["mixed"],
        "unsupported": resolution["unsupported"],
    }
    result.setdefault("mutation", "none")
    result.setdefault("requires_approval", False)
    return result


def _compose_answer(db: Session, user: User, trip: Trip, message: str, language: str) -> dict:
    intent = _detect_intent(message, language)
    citations: list[dict] = [_cite(f"Trip: {trip.name}", "trip", trip.id, REPORTED)]
    context = _build_context(db, user, trip)

    named = _find_named_activity(db, trip, message)
    if named and intent in {"general", "budget", "recommend"}:
        result = _activity_answer(db, trip, named, language)
        result["intent"] = "place_fact"
        result["generated_by"] = GENERATOR
        result["context"] = context
        return result

    if intent == "weather":
        result = _weather_answer(trip, language)
    elif intent == "itinerary":
        result = _itinerary_answer(db, trip, message, language, citations)
    elif intent == "budget":
        result = _budget_answer(db, trip, user, language, citations)
    elif intent == "recommend":
        result = _recommend_answer(db, trip, language, citations)
    elif intent == "vote":
        result = _vote_answer(db, trip, language, citations)
    elif intent == "members":
        result = _members_answer(db, trip, language, citations)
    elif intent == "privacy":
        result = {
            "answer": t("privacy.answer", language),
            "citations": [],
            "grounding": "product_policy",
            "limitations": [],
            "suggested_actions": [{"label": t("action.privacy", language), "href": "/settings"}],
            "requires_approval": False,
            "mutation": "none",
        }
    elif intent == "overview":
        items = (
            db.query(ItineraryItem)
            .filter(ItineraryItem.trip_id == trip.id, ItineraryItem.status == "confirmed")
            .order_by(ItineraryItem.day, ItineraryItem.start_time)
            .all()
        )
        result = _overview_answer(trip, items, context, language, citations)
    else:
        result = {
            "answer": t("general.unknown", language),
            "citations": citations,
            "grounding": "trip_data",
            "limitations": [t("limit.no_llm", language)],
            "suggested_actions": [
                {"label": t("action.itinerary", language), "href": f"/trips/{trip.id}/itinerary"},
                {"label": t("action.engine", language), "href": f"/trips/{trip.id}/engine"},
            ],
            "requires_approval": False,
            "mutation": "none",
        }
    result["intent"] = intent
    result["generated_by"] = GENERATOR
    result["context"] = context
    return result
