"""Language detection and negotiation for the grounded assistant.

Detection is deterministic: Unicode script ranges for non-Latin writing systems
and folded stopword scoring for the seven supported Latin-script languages.
No model is downloaded and no text leaves the server.
"""

import re
import unicodedata
from dataclasses import dataclass, field

SUPPORTED_LANGUAGES = ("en", "es", "fr", "de", "pt", "it", "hi", "ja")
LANGUAGE_NAMES = {
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "pt": "Portuguese",
    "it": "Italian",
    "hi": "Hindi",
    "ja": "Japanese",
}
NAME_TO_CODE = {
    "english": "en",
    "spanish": "es",
    "espanol": "es",
    "español": "es",
    "french": "fr",
    "francais": "fr",
    "français": "fr",
    "german": "de",
    "deutsch": "de",
    "portuguese": "pt",
    "portugues": "pt",
    "português": "pt",
    "italian": "it",
    "italiano": "it",
    "hindi": "hi",
    "japanese": "ja",
    "nihongo": "ja",
}

# Folded stopwords. Words shorter than three characters are excluded because
# "a", "o" and "e" appear in several of these languages at once.
STOPWORDS = {
    "en": {
        "the", "and", "what", "where", "when", "our", "trip", "plan", "budget",
        "today", "tomorrow", "much", "should", "have", "with", "this", "that",
        "does", "will", "there", "about", "tell", "please", "thanks", "day", "week",
    },
    "es": {
        "que", "los", "las", "donde", "cuando", "nuestro", "nuestra", "viaje",
        "presupuesto", "hoy", "manana", "cuanto", "como", "para", "este", "esta",
        "cual", "quien", "llover", "vamos", "quiero", "puedo", "hay",
        "gracias", "hola", "plan", "favor", "necesito", "del", "programa", "semana", "dia",
    },
    "fr": {
        "les", "des", "que", "quoi", "notre", "voyage", "budget", "plan", "est",
        "aujourd", "demain", "combien", "comment", "pour", "cette", "nous",
        "pleuvoir", "quel", "quelle", "merci", "bonjour", "voulez", "peut",
        "fait", "hui", "avec", "semaine", "jour",
    },
    "de": {
        "der", "die", "das", "und", "was", "wo", "wann", "unser", "reise",
        "plan", "ist", "heute", "morgen", "wie", "viel", "fur", "diese", "wir",
        "wird", "regnen", "soll", "sollen", "bitte", "danke", "haben", "kann",
        "konnen", "mit", "tag", "woche",
    },
    "pt": {
        "que", "onde", "quando", "nossa", "nosso", "viagem", "orcamento",
        "plano", "hoje", "amanha", "quanto", "como", "para", "esta", "este",
        "chover", "vai", "qual", "quem", "vamos", "quero", "posso", "ha",
        "obrigado", "ola", "favor", "plan", "programa", "semana", "dia",
    },
    "it": {
        "che", "dove", "quando", "nostro", "nostra", "viaggio", "piano",
        "oggi", "domani", "quanto", "come", "per", "questa", "questo", "noi",
        "piovere", "piovera", "quale", "qual", "chi", "andiamo", "voglio", "posso",
        "grazie", "ciao", "favor", "plan", "programma", "settimana", "giorno",
    },
}
INTENT_WORDS = {
    "en": {"itinerary", "recommend", "members", "privacy", "weather", "forecast"},
    "es": {"itinerario", "presupuesto", "recomendar", "votar", "miembros", "privacidad", "clima", "lluvia", "pronostico", "gasto", "dinero"},
    "fr": {"itineraire", "budget", "recommander", "voter", "membres", "confidentialite", "meteo", "pluie", "prevision", "depense", "argent"},
    "de": {"reiseplan", "budget", "empfehlen", "abstimmen", "mitglieder", "datenschutz", "wetter", "regen", "vorhersage", "kosten", "geld"},
    "pt": {"itinerario", "orcamento", "recomendar", "votar", "membros", "privacidade", "clima", "chuva", "previsao", "despesa", "dinheiro"},
    "it": {"itinerario", "budget", "consigli", "votare", "membri", "privacy", "meteo", "pioggia", "previsioni", "spesa", "soldi"},
}

_SCRIPT_CHECKS = (
    ("ja", re.compile(r"[\u3040-\u30ff]"), "Japanese"),
    ("hi", re.compile(r"[\u0900-\u097f]"), "Hindi"),
    ("ko", re.compile(r"[\uac00-\ud7af]"), "Korean"),
    ("ar", re.compile(r"[\u0600-\u06ff]"), "Arabic"),
    ("ru", re.compile(r"[\u0400-\u04ff]"), "Russian"),
    ("el", re.compile(r"[\u0370-\u03ff]"), "Greek"),
    ("th", re.compile(r"[\u0e00-\u0e7f]"), "Thai"),
    ("he", re.compile(r"[\u0590-\u05ff]"), "Hebrew"),
    ("zh", re.compile(r"[\u4e00-\u9fff]"), "Chinese"),
)


def _fold(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.lower())
    return "".join(char for char in decomposed if not unicodedata.combining(char))


def normalize_language(value: str | None) -> str | None:
    if not value:
        return None
    cleaned = value.strip().lower()
    code = re.split(r"[-_ ]", cleaned)[0]
    if code in SUPPORTED_LANGUAGES:
        return code
    return NAME_TO_CODE.get(cleaned)


@dataclass(slots=True)
class LanguageDetection:
    language: str | None = None
    confidence: float = 0.0
    scores: dict[str, float] = field(default_factory=dict)
    mixed: list[str] = field(default_factory=list)
    script: str | None = None
    unsupported: str | None = None

    @property
    def detected_name(self) -> str | None:
        if self.language:
            return LANGUAGE_NAMES.get(self.language)
        return self.unsupported


def detect_language(message: str) -> LanguageDetection:
    for code, pattern, name in _SCRIPT_CHECKS:
        if len(pattern.findall(message)) >= 2:
            if code in SUPPORTED_LANGUAGES:
                return LanguageDetection(
                    language=code,
                    confidence=0.95,
                    scores={code: 1.0},
                    script=name,
                )
            return LanguageDetection(
                confidence=0.5,
                script=name,
                unsupported=name,
            )

    folded = _fold(message)
    tokens = re.findall(r"[a-z]{3,}", folded)
    if not tokens:
        return LanguageDetection()
    scores = {}
    for language, words in STOPWORDS.items():
        score = 0.0
        for word in words:
            score += tokens.count(word)
        for word in INTENT_WORDS.get(language, set()):
            score += 2 * tokens.count(word)
        if score:
            scores[language] = score
    if not scores:
        return LanguageDetection()
    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    top_language, top_score = ranked[0]
    if top_score < 2:
        if top_score >= 1 and len(ranked) == 1:
            # A single marker that belongs to only one supported language is still
            # useful; report it with modest confidence instead of giving up.
            return LanguageDetection(
                language=top_language,
                confidence=0.45,
                scores=scores,
                script="Latin",
            )
        return LanguageDetection(scores=scores, confidence=0.2)
    mixed = [
        code
        for code, score in ranked[1:]
        if score >= 2 and score >= top_score * 0.3
    ]
    confidence = min(0.95, 0.5 + 0.05 * top_score)
    return LanguageDetection(
        language=top_language,
        confidence=round(confidence, 2),
        scores=scores,
        mixed=mixed,
        script="Latin",
    )


def resolve_language(
    message: str,
    requested: str | None = None,
    preferred: str | None = None,
) -> dict:
    """Pick the reply language: explicit request, then confident detection,
    then the profile preference, then English."""
    detection = detect_language(message)
    requested_code = normalize_language(requested)
    preferred_code = normalize_language(preferred)

    if requested_code:
        code, source = requested_code, "requested"
    elif detection.language:
        code, source = detection.language, "detected"
    elif preferred_code:
        code, source = preferred_code, "profile"
    else:
        code, source = "en", "default"

    return {
        "code": code,
        "name": LANGUAGE_NAMES[code],
        "source": source,
        "detected": detection.language,
        "detected_name": detection.detected_name,
        "confidence": detection.confidence,
        "mixed": detection.mixed,
        "mixed_names": [LANGUAGE_NAMES[item] for item in detection.mixed],
        "unsupported": detection.unsupported,
        "unknown": detection.language is None and detection.unsupported is None,
    }
